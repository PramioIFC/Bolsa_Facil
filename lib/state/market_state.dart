import 'package:flutter/foundation.dart';

import '../models/stock.dart';
import '../services/brapi_service.dart';
import '../services/quote_repository.dart';
import 'auth_state.dart';

class MarketState extends ChangeNotifier {
  MarketState(this.brapiService, this.quotes, this.auth, {this.onFreshQuotes});
  final Future<void> Function(QuoteUpdate, SessionIdentity)? onFreshQuotes;
  final BrapiService brapiService;
  final QuoteRepository quotes;
  final AuthState auth;
  List<Stock> stocks = [];
  bool loading = false;
  String? error;
  Set<String> failedSymbols = {};
  bool rateLimited = false;
  bool usingStaleData = false;
  DateTime? updatedAt;
  Future<void>? _refreshing;
  SessionIdentity? _refreshSession;
  bool _disposed = false;
  final _suggestionCache = <String, List<TickerSuggestion>>{};
  final _detailRequests = <String, int>{};
  int _refreshRequest = 0;

  bool _active(SessionIdentity session) =>
      !_disposed && auth.isCurrent(session);

  void clear() {
    stocks = [];
    loading = false;
    error = null;
    failedSymbols = {};
    rateLimited = false;
    usingStaleData = false;
    updatedAt = null;
    _refreshing = null;
    _refreshSession = null;
    _refreshRequest++;
    _suggestionCache.clear();
    // Keep per-symbol request counters monotonic across sessions.
    notifyListeners();
  }

  Future<void> refresh(List<String> symbols, {bool force = true}) {
    final session = auth.capture();
    if (_refreshing != null && _refreshSession == session) return _refreshing!;
    _refreshSession = session;
    final request = ++_refreshRequest;
    final running = _doRefresh(symbols, force, session, request);
    _refreshing = running;
    return running.whenComplete(() {
      if (identical(_refreshing, running)) _refreshing = null;
    });
  }

  Future<void> _doRefresh(List<String> symbols, bool force,
      SessionIdentity session, int request) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final update = await quotes.getQuotes(symbols, forceRefresh: force);
      if (!_active(session) || request != _refreshRequest) return;
      stocks = update.stocks;
      failedSymbols = update.failed;
      rateLimited = update.rateLimited;
      usingStaleData = update.hasStale;
      updatedAt = update.updatedAt;
      await onFreshQuotes?.call(update, session);
    } catch (e) {
      if (!_active(session) || request != _refreshRequest) return;
      error = e.toString();
    } finally {
      if (_active(session) && request == _refreshRequest) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Stock? stockFor(String symbol) {
    for (final stock in stocks) {
      if (stock.symbol == symbol) return stock;
    }
    return null;
  }

  void _publishQuote(Stock stock) {
    final index = stocks.indexWhere((item) => item.symbol == stock.symbol);
    stocks = [...stocks];
    if (index < 0) {
      stocks.add(stock);
    } else {
      stocks[index] = stock;
    }
    notifyListeners();
  }

  Future<Stock?> search(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final existing = stockFor(normalized);
    if (existing != null) return existing;
    final session = auth.capture();
    final stock = await brapiService.getQuote(normalized);
    if (!_active(session)) return null;
    _publishQuote(stock);
    await onFreshQuotes?.call(
        QuoteUpdate(stocks: [stock], freshSymbols: {stock.symbol}), session);
    return stock;
  }

  Future<Stock> loadQuote(String symbol, {String range = '3mo'}) async {
    final normalized = symbol.trim().toUpperCase();
    final session = auth.capture();
    final request = (_detailRequests[normalized] ?? 0) + 1;
    _detailRequests[normalized] = request;
    final stock = await brapiService.getQuote(normalized, range: range);
    if (_active(session) && _detailRequests[normalized] == request) {
      _publishQuote(stock);
      await onFreshQuotes?.call(
          QuoteUpdate(stocks: [stock], freshSymbols: {stock.symbol}), session);
    }
    return stock;
  }

  Future<List<TickerSuggestion>> suggest(String query) async {
    final key = query.trim().toUpperCase();
    if (key.length < 2) return const [];
    final cached = _suggestionCache[key];
    if (cached != null) return cached;
    final session = auth.capture();
    try {
      final result = await brapiService.searchTickers(key);
      if (!_active(session)) return const [];
      if (result.isNotEmpty) _suggestionCache[key] = result;
      return result;
    } catch (_) {
      return const [];
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
