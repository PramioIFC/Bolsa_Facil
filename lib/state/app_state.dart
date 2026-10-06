import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/portfolio_item.dart';
import '../models/stock.dart';
import '../models/trade.dart';
import '../models/user_account.dart';
import '../services/brapi_service.dart';
import '../services/quote_repository.dart';
import '../services/price_alert_notifications.dart';
import 'alert_state.dart';
import 'auth_state.dart';
import 'market_state.dart';
import 'portfolio_state.dart';

/// Facade compatível que coordena estados independentes e a sessão local.
class AppState extends ChangeNotifier {
  AppState(this.brapiService, this.db,
      {QuoteRepository? quoteRepository,
      PriceAlertNotifications? notifications})
      : quotes = quoteRepository ?? QuoteRepository(brapiService, db) {
    authState = AuthState(db);
    alertState = AlertState(
        db, authState, notifications ?? LocalPriceAlertNotifications());
    marketState = MarketState(brapiService, quotes, authState,
        onFreshQuotes: alertState.evaluate);
    portfolioState = PortfolioState(db, authState);
    marketAndPortfolio = Listenable.merge([marketState, portfolioState]);
    for (final state in [authState, marketState, portfolioState, alertState]) {
      state.addListener(notifyListeners);
    }
  }

  final BrapiService brapiService;
  final AppDatabase db;
  final QuoteRepository quotes;
  late final AuthState authState;
  late final MarketState marketState;
  late final PortfolioState portfolioState;
  late final AlertState alertState;
  late final Listenable marketAndPortfolio;
  bool _disposed = false;

  static const defaultSymbols = [
    'PETR4',
    'VALE3',
    'ITUB4',
    'BBDC4',
    'ABEV3',
    'WEGE3',
    'BBAS3',
    'MGLU3'
  ];

  List<Stock> get stocks => marketState.stocks;
  set stocks(List<Stock> value) {
    marketState.stocks = value;
    marketState.notifyListeners();
  }

  Set<String> get favorites => portfolioState.favorites;
  set favorites(Set<String> value) {
    portfolioState.favorites = value;
    portfolioState.notifyListeners();
  }

  List<PortfolioItem> get portfolio => portfolioState.portfolio;
  set portfolio(List<PortfolioItem> value) {
    portfolioState.portfolio = value;
    portfolioState.notifyListeners();
  }

  double get realizedProfit => portfolioState.realizedProfit;
  set realizedProfit(double value) {
    portfolioState.realizedProfit = value;
    portfolioState.notifyListeners();
  }

  bool get loading => marketState.loading;
  set loading(bool value) {
    marketState.loading = value;
    marketState.notifyListeners();
  }

  bool get initializing => authState.initializing;
  set initializing(bool value) {
    authState.initializing = value;
    authState.notifyListeners();
  }

  String? get error => marketState.error ?? authState.initializationError;
  set error(String? value) {
    marketState.error = value;
    marketState.notifyListeners();
  }

  UserAccount? get currentUser => authState.currentUser;
  set currentUser(UserAccount? value) {
    authState.invalidate();
    _clearData();
    authState.setUser(value);
  }

  Set<String> get failedSymbols => marketState.failedSymbols;
  set failedSymbols(Set<String> value) {
    marketState.failedSymbols = value;
    marketState.notifyListeners();
  }

  bool get rateLimited => marketState.rateLimited;
  set rateLimited(bool value) {
    marketState.rateLimited = value;
    marketState.notifyListeners();
  }

  bool get usingStaleData => marketState.usingStaleData;
  set usingStaleData(bool value) {
    marketState.usingStaleData = value;
    marketState.notifyListeners();
  }

  DateTime? get updatedAt => marketState.updatedAt;
  set updatedAt(DateTime? value) {
    marketState.updatedAt = value;
    marketState.notifyListeners();
  }

  String? get actionError => portfolioState.actionError;
  set actionError(String? value) {
    portfolioState.actionError = value;
    portfolioState.notifyListeners();
  }

  bool get isAuthenticated => currentUser != null;
  String? takeActionError() => portfolioState.takeActionError();

  void _clearData() {
    marketState.clear();
    portfolioState.clear();
    alertState.clear();
  }

  Future<void> initialize() async {
    var epoch = authState.invalidate();
    try {
      final user = await authState.restore();
      if (!authState.isEpochCurrent(epoch)) return;
      currentUser = user;
      epoch = authState.capture().epoch;
      if (user != null) {
        await portfolioState.loadUserData();
        if (authState.isEpochCurrent(epoch)) await alertState.load();
      }
    } catch (e) {
      if (authState.isEpochCurrent(epoch)) {
        authState.initializationError = e.toString();
      }
    } finally {
      if (authState.isEpochCurrent(epoch)) {
        authState.initializing = false;
        authState.notifyListeners();
      }
    }
    if (authState.isEpochCurrent(epoch) && currentUser != null) {
      unawaited(refresh(force: false));
    }
  }

  Future<void> _startSession(UserAccount user, int epoch) async {
    if (!authState.isEpochCurrent(epoch)) return;
    authState.initializing = true;
    currentUser = user;
    final session = authState.capture();
    try {
      await portfolioState.loadUserData();
      if (authState.isCurrent(session)) await alertState.load();
    } finally {
      if (authState.isCurrent(session)) {
        authState.initializing = false;
        authState.notifyListeners();
      }
    }
    if (authState.isCurrent(session)) unawaited(refresh(force: false));
  }

  Future<void> register(
      {required String name,
      required String email,
      required String password}) async {
    final epoch = authState.invalidate();
    final user =
        await authState.register(name: name, email: email, password: password);
    await _startSession(user, epoch);
  }

  Future<void> login(String email, String password) async {
    final epoch = authState.invalidate();
    final user = await authState.login(email, password);
    await _startSession(user, epoch);
  }

  Future<void> logout() async {
    final epoch = authState.invalidate();
    await authState.logout();
    if (!authState.isEpochCurrent(epoch)) return;
    authState.initializing = false;
    currentUser = null;
  }

  Future<void> refresh({bool force = true}) => marketState.refresh(
      {
        ...defaultSymbols,
        ...favorites,
        ...portfolio.map((item) => item.symbol),
        ...alertState.activeSymbols
      }.toList(),
      force: force);
  Stock? stockFor(String symbol) => marketState.stockFor(symbol);
  Future<Stock?> search(String symbol) => marketState.search(symbol);
  Future<Stock> loadQuote(String symbol, {String range = '3mo'}) =>
      marketState.loadQuote(symbol, range: range);
  Future<List<TickerSuggestion>> suggest(String query) =>
      marketState.suggest(query);
  Future<void> toggleFavorite(String symbol) =>
      portfolioState.toggleFavorite(symbol);

  Future<void> buy(String symbol, double quantity, double price,
          {double fees = 0}) =>
      _trade(TradeType.buy, symbol, quantity, price, fees);
  Future<void> sell(String symbol, double quantity, double price,
          {double fees = 0}) =>
      _trade(TradeType.sell, symbol, quantity, price, fees);
  Future<void> _trade(TradeType type, String symbol, double quantity,
      double price, double fees) async {
    final session = authState.capture();
    final applied =
        await portfolioState.trade(type, symbol, quantity, price, fees);
    if (applied &&
        authState.isCurrent(session) &&
        stockFor(symbol.trim().toUpperCase()) == null) {
      await refresh(force: false);
    }
  }

  Future<void> savePosition(PortfolioItem item) async {
    final session = authState.capture();
    final applied = await portfolioState.savePosition(item);
    if (applied &&
        authState.isCurrent(session) &&
        stockFor(item.symbol) == null) {
      await refresh(force: false);
    }
  }

  Future<void> removePosition(String symbol) =>
      portfolioState.removePosition(symbol);
  Future<List<Trade>> tradesFor(String symbol) =>
      portfolioState.tradesFor(symbol);
  Future<String> exportJson() => portfolioState.exportJson();
  Future<void> importJson(String text) async {
    final session = authState.capture();
    final applied = await portfolioState.importJson(text);
    if (applied && authState.isCurrent(session)) {
      await alertState.load();
      if (authState.isCurrent(session)) await refresh(force: false);
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final state in [authState, marketState, portfolioState, alertState]) {
      state.removeListener(notifyListeners);
    }
    marketState.dispose();
    portfolioState.dispose();
    alertState.dispose();
    authState.dispose();
    super.dispose();
  }
}
