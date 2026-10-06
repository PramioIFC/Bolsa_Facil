import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/portfolio_item.dart';
import '../models/stock.dart';
import '../models/trade.dart';
import '../models/user_account.dart';
import '../services/brapi_service.dart';
import '../services/quote_repository.dart';

/// Estado global do aplicativo.
///
/// Orquestra o banco local ([AppDatabase]), as cotações
/// ([QuoteRepository]/[BrapiService]) e notifica a UI via [ChangeNotifier].
/// Funciona igual em todas as plataformas: o SQLite é local (nativo) ou em
/// WebAssembly (Web), escolhido em `initDatabaseFactory()`.
class AppState extends ChangeNotifier {
  AppState(this.brapiService, this.db, {QuoteRepository? quoteRepository})
      : quotes = quoteRepository ?? QuoteRepository(brapiService, db);

  final BrapiService brapiService;
  final AppDatabase db;
  final QuoteRepository quotes;

  static const defaultSymbols = [
    'PETR4',
    'VALE3',
    'ITUB4',
    'BBDC4',
    'ABEV3',
    'WEGE3',
    'BBAS3',
    'MGLU3',
  ];

  List<Stock> stocks = [];
  Set<String> favorites = {};
  List<PortfolioItem> portfolio = [];
  double realizedProfit = 0;

  bool loading = false;
  bool initializing = true;
  String? error;
  UserAccount? currentUser;

  /// Símbolos que não puderam ser atualizados na última consulta.
  Set<String> failedSymbols = {};
  bool rateLimited = false;

  /// `true` se parte do que está na tela veio do cache por falha na consulta.
  bool usingStaleData = false;

  /// Instante da cotação mais antiga exibida.
  DateTime? updatedAt;

  /// Erro de uma ação do usuário (ex.: falha ao salvar favorito). A UI exibe
  /// uma vez e limpa com [takeActionError].
  String? actionError;

  bool get isAuthenticated => currentUser != null;

  // Incrementado a cada login/logout para descartar respostas atrasadas.
  int _epoch = 0;
  Future<void>? _refreshing;
  int _refreshingEpoch = -1;
  bool _disposed = false;
  final Map<String, List<TickerSuggestion>> _suggestionCache = {};

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String? takeActionError() {
    final message = actionError;
    actionError = null;
    return message;
  }

  // ---------------------------------------------------------------------------
  // Sessão
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    try {
      currentUser = await db.getSession();
      if (currentUser != null) await _loadUserData();
    } catch (e) {
      error = e.toString();
    } finally {
      initializing = false;
      notifyListeners();
    }
    // As cotações carregam em segundo plano: o app abre sem esperar a rede.
    if (currentUser != null) unawaited(refresh(force: false));
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final user = await db.register(name: name, email: email, password: password);
    await _startSession(user);
  }

  Future<void> login(String email, String password) async {
    final user = await db.login(email, password);
    await _startSession(user);
  }

  Future<void> _startSession(UserAccount user) async {
    _epoch++;
    currentUser = user;
    await _loadUserData();
    notifyListeners();
    // Não espera a rede: a Home mostra o carregamento enquanto as cotações chegam.
    unawaited(refresh(force: false));
  }

  Future<void> logout() async {
    _epoch++;
    await db.logout();
    currentUser = null;
    favorites = {};
    portfolio = [];
    stocks = [];
    realizedProfit = 0;
    failedSymbols = {};
    rateLimited = false;
    usingStaleData = false;
    updatedAt = null;
    error = null;
    actionError = null;
    notifyListeners();
  }

  Future<void> _loadUserData() async {
    final user = currentUser;
    if (user == null) return;
    favorites = await db.getFavorites(user.id);
    portfolio = await db.getPositions(user.id);
    realizedProfit = await db.getRealizedProfit(user.id);
  }

  // ---------------------------------------------------------------------------
  // Cotações
  // ---------------------------------------------------------------------------

  /// Atualiza as cotações de: destaques padrão + favoritos + carteira.
  /// Com [force] = `false` usa o cache local enquanto estiver dentro do TTL.
  /// Chamadas simultâneas compartilham a mesma execução.
  Future<void> refresh({bool force = true}) {
    final running = _refreshing;
    if (running != null && _refreshingEpoch == _epoch) return running;
    _refreshingEpoch = _epoch;
    final started = _doRefresh(force);
    _refreshing = started;
    return started.whenComplete(() {
      if (identical(_refreshing, started)) _refreshing = null;
    });
  }

  Future<void> _doRefresh(bool force) async {
    final epoch = _epoch;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final symbols = <String>{
        ...defaultSymbols,
        ...favorites,
        ...portfolio.map((item) => item.symbol),
      };
      final update = await quotes.getQuotes(symbols.toList(), forceRefresh: force);
      if (epoch != _epoch) return;
      stocks = update.stocks;
      failedSymbols = update.failed;
      rateLimited = update.rateLimited;
      usingStaleData = update.hasStale;
      updatedAt = update.updatedAt;
    } catch (e) {
      if (epoch != _epoch) return;
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Stock? stockFor(String symbol) {
    for (final stock in stocks) {
      if (stock.symbol == symbol) return stock;
    }
    return null;
  }

  /// Busca uma ação pelo código (cache em memória primeiro).
  Future<Stock?> search(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final existing = stockFor(normalized);
    if (existing != null) return existing;
    final stock = await brapiService.getQuote(normalized);
    stocks = [...stocks, stock];
    notifyListeners();
    return stock;
  }

  /// Cotação detalhada com histórico (tela de detalhes).
  Future<Stock> loadQuote(String symbol, {String range = '3mo'}) =>
      brapiService.getQuote(symbol, range: range);

  /// Sugestões de tickers para o autocomplete. Nunca lança.
  Future<List<TickerSuggestion>> suggest(String query) async {
    final key = query.trim().toUpperCase();
    if (key.length < 2) return const [];
    final cached = _suggestionCache[key];
    if (cached != null) return cached;
    try {
      final result = await brapiService.searchTickers(key);
      if (result.isNotEmpty) _suggestionCache[key] = result;
      return result;
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Favoritos (atualização otimista com rollback)
  // ---------------------------------------------------------------------------

  Future<void> toggleFavorite(String symbol) async {
    final user = currentUser;
    if (user == null) return;
    final wasFavorite = favorites.contains(symbol);
    if (wasFavorite) {
      favorites.remove(symbol);
    } else {
      favorites.add(symbol);
    }
    notifyListeners();
    try {
      await db.toggleFavorite(user.id, symbol, !wasFavorite);
    } catch (_) {
      if (wasFavorite) {
        favorites.add(symbol);
      } else {
        favorites.remove(symbol);
      }
      actionError = 'Não foi possível salvar o favorito. Tente novamente.';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Carteira
  // ---------------------------------------------------------------------------

  /// Compra: soma à posição e recalcula o preço médio (taxas entram no custo).
  Future<void> buy(String symbol, double quantity, double price, {double fees = 0}) =>
      _trade(TradeType.buy, symbol, quantity, price, fees);

  /// Venda: reduz a posição e realiza lucro/prejuízo. Lança [TradeException]
  /// se a quantidade exceder a posição.
  Future<void> sell(String symbol, double quantity, double price, {double fees = 0}) =>
      _trade(TradeType.sell, symbol, quantity, price, fees);

  Future<void> _trade(
    TradeType type,
    String symbol,
    double quantity,
    double price,
    double fees,
  ) async {
    final user = currentUser;
    if (user == null) return;
    final normalized = symbol.trim().toUpperCase();
    await db.recordTrade(
      user.id,
      Trade(
        symbol: normalized,
        type: type,
        quantity: quantity,
        price: price,
        fees: fees,
        executedAt: DateTime.now(),
      ),
    );
    await _reloadPortfolio(user.id);
    if (stockFor(normalized) == null) await refresh(force: false);
  }

  /// Edição manual: define quantidade e preço médio absolutos.
  Future<void> savePosition(PortfolioItem item) async {
    final user = currentUser;
    if (user == null) return;
    await db.adjustPosition(user.id, item);
    await _reloadPortfolio(user.id);
    if (stockFor(item.symbol) == null) await refresh(force: false);
  }

  /// Remove a posição e o histórico de operações do ativo.
  Future<void> removePosition(String symbol) async {
    final user = currentUser;
    if (user == null) return;
    await db.removePosition(user.id, symbol);
    await _reloadPortfolio(user.id);
  }

  Future<List<Trade>> tradesFor(String symbol) {
    final user = currentUser;
    if (user == null) return Future.value(const []);
    return db.getTrades(user.id, symbol: symbol);
  }

  Future<void> _reloadPortfolio(int userId) async {
    portfolio = await db.getPositions(userId);
    realizedProfit = await db.getRealizedProfit(userId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  /// Backup (favoritos e operações) em JSON identado. Sem senha nem hash.
  Future<String> exportJson() async {
    final user = currentUser;
    if (user == null) throw const DataImportException('Faça login para exportar.');
    final data = await db.exportUserData(user.id);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Substitui favoritos e carteira pelo conteúdo do backup.
  Future<void> importJson(String text) async {
    final user = currentUser;
    if (user == null) throw const DataImportException('Faça login para importar.');
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw const DataImportException('O texto colado não é um JSON válido.');
    }
    await db.importUserData(user.id, data);
    await _loadUserData();
    notifyListeners();
    await refresh(force: false);
  }
}
