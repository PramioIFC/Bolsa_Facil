import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/price_alert.dart';
import '../services/price_alert_notifications.dart';
import '../services/quote_repository.dart';
import 'auth_state.dart';

class AlertState extends ChangeNotifier {
  AlertState(this.db, this.auth, this.notifications);
  final AppDatabase db;
  final AuthState auth;
  final PriceAlertNotifications notifications;
  List<PriceAlert> alerts = [];
  bool loading = false;
  bool saving = false;
  String? error;
  bool notificationsAllowed = false;
  bool _disposed = false;
  int _loadRequest = 0;
  int _generation = 0;
  final _mutationRevisions = <int, int>{};
  bool _active(SessionIdentity session) =>
      !_disposed && auth.isCurrent(session);
  Set<String> get activeSymbols =>
      alerts.where((a) => !a.isTriggered).map((a) => a.symbol).toSet();

  void clear() {
    _generation++;
    _loadRequest++;
    alerts = [];
    loading = false;
    saving = false;
    error = null;
    notifyListeners();
  }

  Future<void> load() async {
    final session = auth.capture();
    if (session.userId == null || !_active(session)) return;
    final request = ++_loadRequest;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await db.getPriceAlerts(session.userId!);
      if (_active(session) && request == _loadRequest) alerts = result;
    } catch (_) {
      if (_active(session) && request == _loadRequest) {
        error = 'Não foi possível carregar os alertas. Tente novamente.';
      }
    } finally {
      if (_active(session) && request == _loadRequest) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _save(Future<void> Function(int) operation) async {
    final session = auth.capture();
    if (saving || !_active(session)) return;
    if (session.userId == null) {
      throw const PriceAlertException('Faça login para gerenciar alertas.');
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      await operation(session.userId!);
      if (_active(session)) await load();
    } on PriceAlertException catch (e) {
      if (_active(session)) error = e.message;
    } catch (_) {
      if (_active(session)) {
        error = 'Não foi possível salvar o alerta. Tente novamente.';
      }
    } finally {
      if (_active(session)) {
        saving = false;
        notifyListeners();
      }
    }
  }

  Future<void> create(PriceAlert alert) => _save((userId) async {
        await db.createPriceAlert(userId, alert);
      });
  Future<void> update(int id, PriceAlert alert) => _save((userId) async {
        _mutationRevisions[id] = (_mutationRevisions[id] ?? 0) + 1;
        if (!await db.updatePriceAlert(userId, id, alert)) {
          throw const PriceAlertException('Alerta não encontrado.');
        }
      });
  Future<void> delete(int id) => _save((userId) async {
        _mutationRevisions[id] = (_mutationRevisions[id] ?? 0) + 1;
        if (!await db.deletePriceAlert(userId, id)) {
          throw const PriceAlertException('Alerta não encontrado.');
        }
      });

  Future<bool> requestPermission() async {
    final session = auth.capture();
    try {
      final allowed = await notifications.requestPermission();
      if (!_active(session)) return false;
      notificationsAllowed = allowed;
      error = allowed
          ? null
          : 'Notificações não autorizadas. Os alertas continuam disponíveis no aplicativo.';
      notifyListeners();
      return allowed;
    } catch (_) {
      if (_active(session)) {
        error =
            'Não foi possível ativar as notificações. Os alertas continuam no aplicativo.';
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> evaluate(QuoteUpdate update, SessionIdentity session) async {
    if (!_active(session) || session.userId == null) return;
    final generation = _generation;
    final fresh = {
      for (final stock in update.stocks)
        if (update.freshSymbols.contains(stock.symbol))
          stock.symbol: stock.price
    };
    final snapshot = [
      for (final alert in alerts) (alert, _mutationRevisions[alert.id] ?? 0)
    ];
    for (final (alert, revision) in snapshot) {
      if (!_active(session)) return;
      final price = fresh[alert.symbol];
      if (alert.id == null || price == null || !alert.matches(price)) continue;
      bool current() =>
          _active(session) &&
          generation == _generation &&
          revision == (_mutationRevisions[alert.id!] ?? 0);
      if (!current()) continue;
      try {
        final at = DateTime.now().toUtc();
        final marked =
            await db.markPriceAlertTriggered(session.userId!, alert, at);
        if (!_active(session)) return;
        if (!current() || !marked) continue;
        _loadRequest++;
        loading = false;
        final triggered = alert.copyWith(triggeredAt: at);
        alerts = [
          for (final item in alerts) item.id == alert.id ? triggered : item
        ];
        notifyListeners();
        try {
          await notifications.show(triggered, price, canDeliver: current);
        } catch (_) {
          if (_active(session)) {
            error =
                'Alerta acionado. Não foi possível mostrar a notificação do sistema.';
          }
        }
      } catch (_) {
        if (_active(session)) {
          error =
              'Não foi possível registrar o alerta. Tente atualizar novamente.';
        }
      }
      if (_active(session)) notifyListeners();
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
