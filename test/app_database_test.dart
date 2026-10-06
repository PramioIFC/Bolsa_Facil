import 'dart:convert';
import 'dart:io';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/portfolio_item.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fakes.dart';

Trade tradeOf(String symbol, TradeType type, double qty, double price, {double fees = 0}) => Trade(
      symbol: symbol,
      type: type,
      quantity: qty,
      price: price,
      fees: fees,
      executedAt: DateTime.now(),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  group('autenticação', () {
    test('registra, abre sessão e restaura a sessão', () async {
      final user = await db.register(name: 'Ana', email: 'ANA@Email.com', password: 'segredo1');
      expect(user.email, 'ana@email.com');
      final session = await db.getSession();
      expect(session?.id, user.id);
      await db.logout();
      expect(await db.getSession(), isNull);
    });

    test('e-mail duplicado é recusado e NÃO sobrescreve a conta existente', () async {
      await db.register(name: 'Ana', email: 'ana@email.com', password: 'senha-original');
      await expectLater(
        db.register(name: 'Invasor', email: 'ANA@email.com', password: 'senha-nova!'),
        throwsA(isA<AuthException>()),
      );
      final user = await db.login('ana@email.com', 'senha-original');
      expect(user.name, 'Ana');
      await expectLater(db.login('ana@email.com', 'senha-nova!'), throwsA(isA<AuthException>()));
    });

    test('valida nome, e-mail e senha', () async {
      await expectLater(db.register(name: 'A', email: 'a@b.co', password: '123456'), throwsA(isA<AuthException>()));
      await expectLater(db.register(name: 'Ana', email: 'sem-arroba', password: '123456'), throwsA(isA<AuthException>()));
      await expectLater(db.register(name: 'Ana', email: 'a@b.co', password: '123'), throwsA(isA<AuthException>()));
    });

    test('senha incorreta e e-mail inexistente dão a mesma mensagem', () async {
      await db.register(name: 'Ana', email: 'ana@email.com', password: 'segredo1');
      Object? wrongPassword;
      Object? unknownUser;
      try {
        await db.login('ana@email.com', 'errada!');
      } catch (e) {
        wrongPassword = e;
      }
      try {
        await db.login('nao@existe.com', 'segredo1');
      } catch (e) {
        unknownUser = e;
      }
      expect(wrongPassword.toString(), unknownUser.toString());
    });

    test('hash legado (SHA-256) continua válido e é migrado para PBKDF2 no login', () async {
      final database = await db.database;
      const salt = 'sal-legado';
      final legacy = sha256.convert(utf8.encode('$salt:antiga123')).toString();
      await database.insert('users', {
        'name': 'Legado',
        'email': 'legado@email.com',
        'password_hash': legacy,
        'password_salt': salt,
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.login('legado@email.com', 'antiga123');
      final row = (await database.query('users', where: 'email = ?', whereArgs: ['legado@email.com'])).first;
      expect((row['password_hash'] as String).startsWith('pbkdf2_sha256\$'), isTrue);
      await db.login('legado@email.com', 'antiga123'); // continua funcionando
    });
  });

  group('carteira', () {
    test('posições são isoladas por usuário', () async {
      final a = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      final b = await db.register(name: 'Beto', email: 'b@b.com', password: '123456');
      await db.recordTrade(a.id, tradeOf('PETR4', TradeType.buy, 10, 20));
      expect((await db.getPositions(a.id)).single.symbol, 'PETR4');
      expect(await db.getPositions(b.id), isEmpty);
    });

    test('compra, compra e venda atualizam posição e resultado realizado', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.recordTrade(u.id, tradeOf('PETR4', TradeType.buy, 10, 20));
      await db.recordTrade(u.id, tradeOf('PETR4', TradeType.buy, 10, 30));
      await db.recordTrade(u.id, tradeOf('PETR4', TradeType.sell, 5, 40));
      final position = (await db.getPositions(u.id)).single;
      expect(position.quantity, 15);
      expect(position.averagePrice, 25);
      expect(await db.getRealizedProfit(u.id), closeTo(75, 1e-9)); // (40-25)*5
      expect(await db.getTrades(u.id, symbol: 'PETR4'), hasLength(3));
    });

    test('venda acima da posição falha e não grava nada', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.recordTrade(u.id, tradeOf('VALE3', TradeType.buy, 5, 10));
      await expectLater(
        db.recordTrade(u.id, tradeOf('VALE3', TradeType.sell, 6, 10)),
        throwsA(isA<TradeException>()),
      );
      expect((await db.getPositions(u.id)).single.quantity, 5);
      expect(await db.getTrades(u.id), hasLength(1));
    });

    test('venda total remove a posição', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.recordTrade(u.id, tradeOf('VALE3', TradeType.buy, 5, 10));
      await db.recordTrade(u.id, tradeOf('VALE3', TradeType.sell, 5, 12));
      expect(await db.getPositions(u.id), isEmpty);
    });

    test('adjustPosition e removePosition', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.adjustPosition(u.id, const PortfolioItem(symbol: 'ITUB4', quantity: 8, averagePrice: 30));
      final position = (await db.getPositions(u.id)).single;
      expect((position.quantity, position.averagePrice), (8.0, 30.0));
      await db.removePosition(u.id, 'ITUB4');
      expect(await db.getPositions(u.id), isEmpty);
      expect(await db.getTrades(u.id), isEmpty);
    });

    test('favoritos: adiciona, ignora duplicata e remove', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.toggleFavorite(u.id, 'PETR4', true);
      await db.toggleFavorite(u.id, 'PETR4', true);
      expect(await db.getFavorites(u.id), {'PETR4'});
      await db.toggleFavorite(u.id, 'PETR4', false);
      expect(await db.getFavorites(u.id), isEmpty);
    });
  });

  group('backup', () {
    test('exporta e importa substituindo os dados (e sem vazar senha)', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.toggleFavorite(u.id, 'WEGE3', true);
      await db.recordTrade(u.id, tradeOf('PETR4', TradeType.buy, 10, 20));
      await db.recordTrade(u.id, tradeOf('PETR4', TradeType.sell, 4, 30));
      final backup = await db.exportUserData(u.id);
      expect(jsonEncode(backup).contains('password'), isFalse);

      // Muda o estado e restaura.
      await db.removePosition(u.id, 'PETR4');
      await db.toggleFavorite(u.id, 'VALE3', true);
      await db.importUserData(u.id, jsonDecode(jsonEncode(backup)) as Map<String, dynamic>);

      expect(await db.getFavorites(u.id), {'WEGE3'});
      final position = (await db.getPositions(u.id)).single;
      expect(position.quantity, 6);
      expect(await db.getRealizedProfit(u.id), closeTo(40, 1e-9));
    });

    test('backup inválido não altera nada', () async {
      final u = await db.register(name: 'Ana', email: 'a@a.com', password: '123456');
      await db.toggleFavorite(u.id, 'WEGE3', true);
      await expectLater(db.importUserData(u.id, {'app': 'outro'}), throwsA(isA<DataImportException>()));
      await expectLater(
        db.importUserData(u.id, {
          'app': 'bolsa_facil',
          'transactions': [
            {'symbol': 'X', 'type': 'sell', 'quantity': 5, 'price': 1, 'executedAt': '2026-01-01T00:00:00Z'},
          ],
        }),
        throwsA(isA<DataImportException>()),
      );
      expect(await db.getFavorites(u.id), {'WEGE3'});
    });
  });

  group('cache de cotações', () {
    test('grava e lê cotações com o instante da consulta', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await db.putCachedQuotes({
        'PETR4': const Stock(symbol: 'PETR4', name: 'Petrobras', price: 38.5, changePercent: 1.1),
      }, at);
      final cached = await db.getCachedQuotes(['PETR4', 'VALE3']);
      expect(cached.keys, ['PETR4']);
      expect(cached['PETR4']!.stock.price, 38.5);
      expect(cached['PETR4']!.fetchedAt, at);
    });
  });

  group('migração v1 → v2', () {
    test('posições existentes viram um ajuste inicial', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('bolsa_facil_test');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/legacy.db';

      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) async {
            await d.execute('CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE COLLATE NOCASE, password_hash TEXT NOT NULL, password_salt TEXT NOT NULL, created_at TEXT NOT NULL)');
            await d.execute('CREATE TABLE positions (user_id INTEGER NOT NULL, symbol TEXT NOT NULL, quantity REAL NOT NULL, average_price REAL NOT NULL, purchased_at TEXT NOT NULL, PRIMARY KEY (user_id, symbol), FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE)');
            await d.execute('CREATE TABLE favorites (user_id INTEGER NOT NULL, symbol TEXT NOT NULL, PRIMARY KEY (user_id, symbol), FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE)');
            await d.execute('CREATE TABLE sessions (id INTEGER PRIMARY KEY CHECK (id = 1), user_id INTEGER NOT NULL, FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE)');
            await d.insert('users', {'id': 1, 'name': 'Ana', 'email': 'ana@a.com', 'password_hash': 'x', 'password_salt': 'y', 'created_at': '2025-01-01T00:00:00.000'});
            await d.insert('positions', {'user_id': 1, 'symbol': 'PETR4', 'quantity': 12.0, 'average_price': 31.5, 'purchased_at': '2025-02-01T10:00:00.000'});
          },
        ),
      );
      await legacy.close();

      final upgraded = AppDatabase(factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 1000);
      addTearDown(upgraded.close);
      final positions = await upgraded.getPositions(1);
      expect(positions.single.symbol, 'PETR4');
      final trades = await upgraded.getTrades(1);
      expect(trades.single.type, TradeType.adjust);
      expect((trades.single.quantity, trades.single.price), (12.0, 31.5));
      // E a carteira continua operável: vender parte da posição migrada.
      await upgraded.recordTrade(1, tradeOf('PETR4', TradeType.sell, 2, 40));
      expect((await upgraded.getPositions(1)).single.quantity, 10);
    });
  });
}
