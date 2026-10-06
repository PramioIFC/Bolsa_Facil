import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/portfolio_item.dart';
import '../models/trade.dart';
import 'auth_state.dart';

class PortfolioState extends ChangeNotifier {
  PortfolioState(this.db, this.auth);
  final AppDatabase db;
  final AuthState auth;
  Set<String> favorites = {};
  List<PortfolioItem> portfolio = [];
  double realizedProfit = 0;
  String? actionError;
  bool _disposed = false;
  int _loadRequest = 0;
  final _favoriteRequests = <String, int>{};

  bool _active(SessionIdentity session) =>
      !_disposed && auth.isCurrent(session);

  void clear() {
    favorites = {};
    portfolio = [];
    realizedProfit = 0;
    actionError = null;
    _loadRequest++;
    notifyListeners();
  }

  String? takeActionError() {
    final message = actionError;
    actionError = null;
    return message;
  }

  Future<void> loadUserData() async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) return;
    final request = ++_loadRequest;
    final savedFavorites = await db.getFavorites(userId);
    if (!_active(session)) return;
    final positions = await db.getPositions(userId);
    if (!_active(session)) return;
    final realized = await db.getRealizedProfit(userId);
    if (!_active(session) || request != _loadRequest) return;
    favorites = savedFavorites;
    portfolio = positions;
    realizedProfit = realized;
    notifyListeners();
  }

  Future<void> _reloadPortfolio(SessionIdentity session) async {
    final userId = session.userId!;
    final request = ++_loadRequest;
    final positions = await db.getPositions(userId);
    if (!_active(session)) return;
    final realized = await db.getRealizedProfit(userId);
    if (!_active(session) || request != _loadRequest) return;
    portfolio = positions;
    realizedProfit = realized;
    notifyListeners();
  }

  Future<void> toggleFavorite(String symbol) async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) return;
    final request = (_favoriteRequests[symbol] ?? 0) + 1;
    _favoriteRequests[symbol] = request;
    final wasFavorite = favorites.contains(symbol);
    favorites = {...favorites};
    wasFavorite ? favorites.remove(symbol) : favorites.add(symbol);
    notifyListeners();
    try {
      await db.toggleFavorite(userId, symbol, !wasFavorite);
    } catch (_) {
      if (!_active(session) || _favoriteRequests[symbol] != request) return;
      favorites = {...favorites};
      wasFavorite ? favorites.add(symbol) : favorites.remove(symbol);
      actionError = 'Não foi possível salvar o favorito. Tente novamente.';
      notifyListeners();
    }
  }

  Future<bool> trade(TradeType type, String symbol, double quantity,
      double price, double fees) async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) return false;
    await db.recordTrade(
        userId,
        Trade(
          symbol: symbol.trim().toUpperCase(),
          type: type,
          quantity: quantity,
          price: price,
          fees: fees,
          executedAt: DateTime.now(),
        ));
    if (!_active(session)) return false;
    await _reloadPortfolio(session);
    return _active(session);
  }

  Future<bool> savePosition(PortfolioItem item) async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) return false;
    await db.adjustPosition(userId, item);
    if (!_active(session)) return false;
    await _reloadPortfolio(session);
    return _active(session);
  }

  Future<void> removePosition(String symbol) async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) return;
    await db.removePosition(userId, symbol);
    if (_active(session)) await _reloadPortfolio(session);
  }

  Future<List<Trade>> tradesFor(String symbol) async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) return const [];
    final trades = await db.getTrades(userId, symbol: symbol);
    return _active(session) ? trades : const [];
  }

  Future<String> exportJson() async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) {
      throw const DataImportException('Faça login para exportar.');
    }
    final data = await db.exportUserData(userId);
    if (!_active(session)) {
      throw const DataImportException('A sessão mudou. Exporte novamente.');
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<bool> importJson(String text) async {
    final session = auth.capture();
    final userId = session.userId;
    if (userId == null) {
      throw const DataImportException('Faça login para importar.');
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw const DataImportException('O texto colado não é um JSON válido.');
    }
    await db.importUserData(userId, data);
    if (!_active(session)) return false;
    await loadUserData();
    return _active(session);
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
