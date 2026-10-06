import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/portfolio_item.dart';
import '../models/stock.dart';
import '../models/trade.dart';
import '../models/user_account.dart';
import '../security/password_derivation.dart';

/// Erro de autenticação/cadastro com mensagem pronta para exibir ao usuário.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Erro ao importar um backup de dados.
class DataImportException implements Exception {
  const DataImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Acesso ao SQLite local: contas, sessão, favoritos, operações, posições e
/// cache de cotações.
///
/// A fábrica (`DatabaseFactory`) e o nome do arquivo são injetáveis para
/// permitir testes com banco em memória. Quando [factory] é `null`, usa-se o
/// `databaseFactory` global configurado por `initDatabaseFactory()`.
class AppDatabase {
  AppDatabase({
    DatabaseFactory? factory,
    String databaseName = 'bolsa_facil.db',
    int? pbkdf2Iterations,
    DateTime Function()? clock,
  })  : _factory = factory,
        _databaseName = databaseName,
        _iterations = pbkdf2Iterations ?? defaultPbkdf2Iterations,
        _clock = clock ?? DateTime.now;

  /// Instância usada pelo aplicativo.
  static final AppDatabase instance = AppDatabase();

  static const schemaVersion = 5;

  /// Mantém o custo configurado nas contas existentes. O cálculo usa isolate
  /// nativo ou Web Crypto na Web, sem executar o laço na thread da interface.
  static int get defaultPbkdf2Iterations => kIsWeb ? 20000 : 60000;

  static const _hashPrefix = 'pbkdf2_sha256';
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final DatabaseFactory? _factory;
  final String _databaseName;
  final int _iterations;
  final DateTime Function() _clock;
  static const _loginWindowMs = 60000;
  static const _maxLoginFailures = 5;
  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  // ---------------------------------------------------------------------------
  // Abertura e schema
  // ---------------------------------------------------------------------------

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final inMemory = _databaseName == inMemoryDatabasePath;
    final path = inMemory || p.isAbsolute(_databaseName)
        ? _databaseName
        : p.join(await factory.getDatabasesPath(), _databaseName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: !inMemory,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await _createV1(db);
          await _createV2(db);
          await _createV4(db);
          await _createV5(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createV2(db);
            await _seedTransactionsFromPositions(db);
          }
          if (oldVersion < 3) await _migrateLegacySession(db);
          if (oldVersion < 4) await _createV4(db);
          if (oldVersion < 5) await _createV5(db);
        },
      ),
    );
  }

  /// A versão original usava session(slot); a v2 passou a sessions(id).
  /// Também recupera bancos já abertos pela v2 que mantiveram a tabela antiga.
  Future<void> _migrateLegacySession(Database db) async {
    final legacy = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'session'",
    );
    if (legacy.isEmpty) return;
    await db.execute('''CREATE TABLE IF NOT EXISTS sessions (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      user_id INTEGER NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )''');
    await db.execute('''INSERT OR IGNORE INTO sessions (id, user_id)
      SELECT slot, user_id FROM session WHERE slot = 1''');
    await db.execute('DROP TABLE session');
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE positions (
        user_id INTEGER NOT NULL,
        symbol TEXT NOT NULL,
        quantity REAL NOT NULL,
        average_price REAL NOT NULL,
        purchased_at TEXT NOT NULL,
        PRIMARY KEY (user_id, symbol),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE favorites (
        user_id INTEGER NOT NULL,
        symbol TEXT NOT NULL,
        PRIMARY KEY (user_id, symbol),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        user_id INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        symbol TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('buy', 'sell', 'adjust')),
        quantity REAL NOT NULL CHECK (quantity > 0),
        price REAL NOT NULL CHECK (price >= 0),
        fees REAL NOT NULL DEFAULT 0,
        executed_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_transactions_user_symbol
      ON transactions (user_id, symbol, executed_at)
    ''');
    await db.execute('''
      CREATE TABLE quotes_cache (
        symbol TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createV4(Database db) =>
      db.execute('CREATE TABLE login_attempts (failed_at INTEGER NOT NULL)');

  Future<void> _createV5(Database db) async {
    await db.execute('''CREATE TABLE app_settings (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      theme_mode TEXT NOT NULL DEFAULT 'system'
        CHECK (theme_mode IN ('system', 'light', 'dark'))
    )''');
    await db.insert('app_settings', {'id': 1, 'theme_mode': 'system'});
  }

  /// Preferência da instalação, independente da conta e dos backups de carteira.
  Future<String> getThemeMode() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['theme_mode'], where: 'id = ?', whereArgs: [1], limit: 1);
    return rows.isEmpty ? 'system' : rows.first['theme_mode'] as String;
  }

  Future<void> setThemeMode(String mode) async {
    if (!const {'system', 'light', 'dark'}.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Tema inválido.');
    }
    final db = await database;
    await db.insert('app_settings', {'id': 1, 'theme_mode': mode},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Bancos criados na versão 1 só têm o estado consolidado em `positions`.
  /// Cada posição vira um ajuste inicial, preservando quantidade e PM.
  Future<void> _seedTransactionsFromPositions(Database db) async {
    await db.execute('''
      INSERT INTO transactions
        (user_id, symbol, type, quantity, price, fees, executed_at)
      SELECT user_id, symbol, 'adjust', quantity, average_price, 0, purchased_at
      FROM positions
      WHERE quantity > 0
    ''');
  }

  // ---------------------------------------------------------------------------
  // Senhas (PBKDF2-HMAC-SHA256)
  // ---------------------------------------------------------------------------

  String _createSalt() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Formato armazenado: `pbkdf2_sha256$<iterações>$<hash em hex>`.
  Future<String> _hashPassword(String password, String salt) async {
    final key = await derivePasswordKey(
        utf8.encode(password), utf8.encode(salt), _iterations);
    return '$_hashPrefix\$$_iterations\$${_hex(key)}';
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Aceita o formato atual e o legado (`SHA-256("$salt:$senha")` em hex).
  /// `needsUpgrade` indica que o hash deve ser regravado no formato atual.
  Future<({bool ok, bool needsUpgrade})> _verifyPassword(
    String password,
    String salt,
    String stored,
  ) async {
    if (stored.startsWith('$_hashPrefix\$')) {
      final parts = stored.split('\$');
      final iterations = parts.length == 3 ? int.tryParse(parts[1]) : null;
      if (iterations == null || iterations <= 0) {
        return (ok: false, needsUpgrade: false);
      }
      final candidate = _hex(
        await derivePasswordKey(
            utf8.encode(password), utf8.encode(salt), iterations),
      );
      return (
        ok: _constantTimeEquals(candidate, parts[2]),
        needsUpgrade: iterations < _iterations,
      );
    }
    final legacy = sha256.convert(utf8.encode('$salt:$password')).toString();
    return (ok: _constantTimeEquals(legacy, stored), needsUpgrade: true);
  }

  // ---------------------------------------------------------------------------
  // Autenticação e sessão
  // ---------------------------------------------------------------------------

  Future<UserAccount> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (cleanName.length < 2) throw const AuthException('Informe seu nome.');
    if (!_emailPattern.hasMatch(normalizedEmail)) {
      throw const AuthException('Informe um e-mail válido.');
    }
    if (password.length < 6) {
      throw const AuthException('Use pelo menos 6 caracteres na senha.');
    }

    final db = await database;
    final existing = await db.query(
      'users',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [normalizedEmail],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw const AuthException('Este e-mail já está cadastrado.');
    }

    final salt = _createSalt();
    try {
      final id = await db.insert('users', {
        'name': cleanName,
        'email': normalizedEmail,
        'password_hash': await _hashPassword(password, salt),
        'password_salt': salt,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _saveSession(db, id);
      return UserAccount(id: id, name: cleanName, email: normalizedEmail);
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const AuthException('Este e-mail já está cadastrado.');
      }
      rethrow;
    }
  }

  /// O limite é global nesta instalação e persiste ao fechar o aplicativo.
  /// A transação serializa tentativas concorrentes, inclusive em outra instância.
  Future<UserAccount> login(String email, String password) async {
    final db = await database;
    final result =
        await db.transaction<({UserAccount? user, String? error})>((txn) async {
      final now = _clock().millisecondsSinceEpoch;
      await txn.delete('login_attempts',
          where: 'failed_at <= ?', whereArgs: [now - _loginWindowMs]);
      final failures =
          await txn.query('login_attempts', orderBy: 'failed_at ASC');
      if (failures.length >= _maxLoginFailures) {
        final waitMs =
            (failures.first['failed_at'] as int) + _loginWindowMs - now;
        final seconds = (waitMs / 1000).ceil();
        return (
          user: null,
          error:
              'Muitas tentativas de login. Aguarde $seconds ${seconds == 1 ? 'segundo' : 'segundos'} e tente novamente.'
        );
      }
      final rows = await txn.query('users',
          where: 'email = ?',
          whereArgs: [email.trim().toLowerCase()],
          limit: 1);
      var valid = false;
      var needsUpgrade = false;
      if (rows.isEmpty) {
        // Também consome o custo de derivação para e-mails inexistentes.
        await _hashPassword(password, 'usuario-inexistente');
      } else {
        final check = await _verifyPassword(
            password,
            rows.first['password_salt'] as String,
            rows.first['password_hash'] as String);
        valid = check.ok;
        needsUpgrade = check.needsUpgrade;
      }
      if (!valid) {
        await txn.insert(
            'login_attempts', {'failed_at': _clock().millisecondsSinceEpoch});
        return (user: null, error: 'E-mail ou senha incorretos.');
      }
      final row = rows.first;
      if (needsUpgrade) {
        await txn.update(
            'users',
            {
              'password_hash':
                  await _hashPassword(password, row['password_salt'] as String)
            },
            where: 'id = ?',
            whereArgs: [row['id']]);
      }
      final user = UserAccount.fromMap(row);
      await _saveSession(txn, user.id);
      // Um sucesso não apaga as falhas recentes nem reinicia o limite.
      return (user: user, error: null);
    });
    // Lançar somente depois do commit: a falha precisa ficar persistida.
    if (result.error != null) throw AuthException(result.error!);
    return result.user!;
  }

  Future<void> _saveSession(DatabaseExecutor db, int userId) => db.insert(
        'sessions',
        {'id': 1, 'user_id': userId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<UserAccount?> getSession() async {
    final db = await database;
    final sessions = await db.query('sessions', where: 'id = 1', limit: 1);
    if (sessions.isEmpty) return null;
    final users = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [sessions.first['user_id']],
      limit: 1,
    );
    if (users.isEmpty) return null;
    return UserAccount.fromMap(users.first);
  }

  Future<void> logout() async {
    final db = await database;
    await db.delete('sessions');
  }

  // ---------------------------------------------------------------------------
  // Favoritos
  // ---------------------------------------------------------------------------

  Future<Set<String>> getFavorites(int userId) async {
    final db = await database;
    final rows = await db.query(
      'favorites',
      columns: ['symbol'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map((row) => row['symbol'] as String).toSet();
  }

  Future<void> toggleFavorite(
      int userId, String symbol, bool isFavorite) async {
    final db = await database;
    if (isFavorite) {
      await db.insert(
        'favorites',
        {'user_id': userId, 'symbol': symbol},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.delete(
        'favorites',
        where: 'user_id = ? AND symbol = ?',
        whereArgs: [userId, symbol],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Carteira: posições derivadas das operações
  // ---------------------------------------------------------------------------

  Future<List<PortfolioItem>> getPositions(int userId) async {
    final db = await database;
    final rows = await db.query(
      'positions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'purchased_at DESC',
    );
    return rows
        .map((row) => PortfolioItem(
              symbol: row['symbol'] as String,
              quantity: (row['quantity'] as num).toDouble(),
              averagePrice: (row['average_price'] as num).toDouble(),
            ))
        .toList();
  }

  /// Registra uma operação e recalcula a posição do ativo, de forma atômica.
  /// Lança [TradeException] (e não grava nada) se os dados forem inválidos ou
  /// se uma venda exceder a posição.
  Future<void> recordTrade(int userId, Trade trade) async {
    final symbol = trade.symbol.trim().toUpperCase();
    if (symbol.isEmpty) throw const TradeException('Informe o código da ação.');
    if (!trade.quantity.isFinite || trade.quantity <= 0) {
      throw const TradeException('A quantidade deve ser maior que zero.');
    }
    if (!trade.price.isFinite || trade.price < 0) {
      throw const TradeException('Informe um preço válido.');
    }
    if (!trade.fees.isFinite || trade.fees < 0) {
      throw const TradeException('Informe taxas válidas.');
    }
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'transactions',
        Trade(
          symbol: symbol,
          type: trade.type,
          quantity: trade.quantity,
          price: trade.price,
          fees: trade.fees,
          executedAt: trade.executedAt,
        ).toMap(userId),
      );
      await _rebuildPosition(txn, userId, symbol);
    });
  }

  /// Substitui quantidade e preço médio (edição manual) via operação `adjust`.
  Future<void> adjustPosition(int userId, PortfolioItem item) => recordTrade(
        userId,
        Trade(
          symbol: item.symbol,
          type: TradeType.adjust,
          quantity: item.quantity,
          price: item.averagePrice,
          executedAt: DateTime.now(),
        ),
      );

  /// Apaga a posição **e o histórico de operações** do ativo.
  Future<void> removePosition(int userId, String symbol) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'transactions',
        where: 'user_id = ? AND symbol = ?',
        whereArgs: [userId, symbol],
      );
      await txn.delete(
        'positions',
        where: 'user_id = ? AND symbol = ?',
        whereArgs: [userId, symbol],
      );
    });
  }

  Future<List<Trade>> getTrades(int userId, {String? symbol}) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: symbol == null ? 'user_id = ?' : 'user_id = ? AND symbol = ?',
      whereArgs: symbol == null ? [userId] : [userId, symbol],
      orderBy: 'executed_at DESC, id DESC',
    );
    return rows.map(Trade.fromMap).toList();
  }

  /// Lucro/prejuízo realizado (vendas) somado entre todos os ativos.
  Future<double> getRealizedProfit(int userId) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'executed_at ASC, id ASC',
    );
    final bySymbol = <String, List<Trade>>{};
    for (final row in rows) {
      final trade = Trade.fromMap(row);
      bySymbol.putIfAbsent(trade.symbol, () => []).add(trade);
    }
    var total = 0.0;
    for (final trades in bySymbol.values) {
      total += summarizeTrades(trades).realizedProfit;
    }
    return total;
  }

  Future<void> _rebuildPosition(
    DatabaseExecutor txn,
    int userId,
    String symbol,
  ) async {
    final rows = await txn.query(
      'transactions',
      where: 'user_id = ? AND symbol = ?',
      whereArgs: [userId, symbol],
      orderBy: 'executed_at ASC, id ASC',
    );
    final summary = summarizeTrades(rows.map(Trade.fromMap));
    if (summary.quantity > 0) {
      await txn.insert(
        'positions',
        {
          'user_id': userId,
          'symbol': symbol,
          'quantity': summary.quantity,
          'average_price': summary.averagePrice,
          'purchased_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await txn.delete(
        'positions',
        where: 'user_id = ? AND symbol = ?',
        whereArgs: [userId, symbol],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Backup (exportar/importar)
  // ---------------------------------------------------------------------------

  /// Dados do usuário em formato portável. Nunca inclui senha nem hash.
  Future<Map<String, dynamic>> exportUserData(int userId) async {
    final favorites = (await getFavorites(userId)).toList()..sort();
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'executed_at ASC, id ASC',
    );
    return {
      'app': 'bolsa_facil',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'favorites': favorites,
      'transactions': rows.map((row) => Trade.fromMap(row).toJson()).toList(),
    };
  }

  /// Substitui favoritos, operações e posições do usuário pelo conteúdo do
  /// backup. Tudo ou nada: em caso de erro nada é alterado.
  Future<void> importUserData(int userId, Map<String, dynamic> data) async {
    if (data['app'] != 'bolsa_facil') {
      throw const DataImportException(
          'Arquivo não reconhecido como backup do Bolsa Fácil.');
    }
    final favorites = <String>{};
    final trades = <Trade>[];
    try {
      for (final item in (data['favorites'] as List? ?? const [])) {
        final symbol = (item as String).trim().toUpperCase();
        if (symbol.isNotEmpty) favorites.add(symbol);
      }
      for (final item in (data['transactions'] as List? ?? const [])) {
        trades.add(Trade.fromJson(item as Map<String, dynamic>));
      }
    } catch (_) {
      throw const DataImportException('O backup contém dados inválidos.');
    }

    final db = await database;
    try {
      await db.transaction((txn) async {
        for (final table in const ['favorites', 'positions', 'transactions']) {
          await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
        }
        for (final symbol in favorites) {
          await txn.insert('favorites', {'user_id': userId, 'symbol': symbol});
        }
        for (final trade in trades) {
          await txn.insert('transactions', trade.toMap(userId));
        }
        for (final symbol in trades.map((t) => t.symbol).toSet()) {
          await _rebuildPosition(txn, userId, symbol);
        }
      });
    } on TradeException catch (error) {
      throw DataImportException('Backup inconsistente: ${error.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Cache de cotações
  // ---------------------------------------------------------------------------

  Future<Map<String, CachedQuote>> getCachedQuotes(
      Iterable<String> symbols) async {
    final list = symbols.toSet().toList();
    if (list.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(list.length, '?').join(',');
    final rows = await db.query(
      'quotes_cache',
      where: 'symbol IN ($placeholders)',
      whereArgs: list,
    );
    final result = <String, CachedQuote>{};
    for (final row in rows) {
      try {
        final map =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        result[row['symbol'] as String] = CachedQuote(
          stock: Stock.fromCacheMap(map),
          fetchedAt:
              DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
        );
      } catch (_) {
        // Linha corrompida: ignora e deixa a próxima consulta regravar.
      }
    }
    return result;
  }

  Future<void> putCachedQuotes(
      Map<String, Stock> quotes, DateTime fetchedAt) async {
    if (quotes.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    quotes.forEach((symbol, stock) {
      batch.insert(
        'quotes_cache',
        {
          'symbol': symbol,
          'payload': jsonEncode(stock.toCacheMap()),
          'fetched_at': fetchedAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}
