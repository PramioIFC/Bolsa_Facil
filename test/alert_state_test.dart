import 'dart:async';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/price_alert.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/services/price_alert_notifications.dart';
import 'package:bolsa_facil/services/quote_repository.dart';
import 'package:bolsa_facil/state/alert_state.dart';
import 'package:bolsa_facil/state/auth_state.dart';
import 'package:bolsa_facil/state/market_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'helpers/fakes.dart';

class _Db extends AppDatabase {
  List<PriceAlert> stored = [];
  Completer<bool>? markGate;
  Completer<List<PriceAlert>>? loadGate;
  final marked = Completer<void>();
  bool failSave = false;
  @override
  Future<List<PriceAlert>> getPriceAlerts(int userId) async =>
      loadGate == null ? List.of(stored) : await loadGate!.future;
  @override
  Future<PriceAlert> createPriceAlert(int userId, PriceAlert alert) async {
    if (failSave) throw const PriceAlertException('Este alerta já existe.');
    final added = alert.copyWith(id: stored.length + 1);
    stored = [...stored, added];
    return added;
  }

  @override
  Future<bool> markPriceAlertTriggered(
      int userId, PriceAlert alert, DateTime at) async {
    if (!marked.isCompleted) marked.complete();
    final index = stored.indexWhere((a) => a.id == alert.id && !a.isTriggered);
    if (index < 0) return false;
    stored[index] = stored[index].copyWith(triggeredAt: at);
    if (markGate != null) return await markGate!.future;
    return true;
  }

  @override
  Future<bool> updatePriceAlert(int userId, int id, PriceAlert alert) async {
    final index = stored.indexWhere((a) => a.id == id);
    if (index < 0) return false;
    stored[index] = alert.copyWith(id: id, rearm: true);
    return true;
  }

  @override
  Future<bool> deletePriceAlert(int userId, int id) async {
    final length = stored.length;
    stored.removeWhere((a) => a.id == id);
    return stored.length != length;
  }
}

class _Notifications implements PriceAlertNotifications {
  bool allowed = false;
  bool fail = false;
  final shown = <PriceAlert>[];
  Completer<void>? deliveryGate;
  final deliveryStarted = Completer<void>();
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> show(PriceAlert alert, double price,
      {bool Function()? canDeliver}) async {
    if (!deliveryStarted.isCompleted) deliveryStarted.complete();
    await deliveryGate?.future;
    if (canDeliver?.call() == false) return;
    if (fail) throw StateError('notification failure');
    shown.add(alert);
  }
}

void main() {
  late _Db db;
  late AuthState auth;
  late _Notifications notifications;
  late AlertState state;
  final draft = PriceAlert(
      symbol: 'PETR4',
      direction: AlertDirection.above,
      target: 20,
      createdAt: DateTime.utc(2026));
  const quote =
      Stock(symbol: 'PETR4', name: 'Petrobras', price: 21, changePercent: 0);
  setUp(() {
    db = _Db();
    auth = AuthState(db)
      ..setUser(const UserAccount(id: 1, name: 'Ana', email: 'ana@a.com'));
    notifications = _Notifications();
    state = AlertState(db, auth, notifications);
  });
  tearDown(() {
    state.dispose();
    auth.dispose();
  });

  test('detalhe só avalia resposta publicada mais recente', () async {
    final old = Completer<http.Response>();
    final latest = Completer<http.Response>();
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var calls = 0;
    final brapi = brapiWith((_) {
      calls++;
      if (calls == 1) {
        firstStarted.complete();
        return old.future;
      }
      secondStarted.complete();
      return latest.future;
    });
    final published = <QuoteUpdate>[];
    final market = MarketState(brapi, QuoteRepository(brapi, db), auth,
        onFreshQuotes: (update, session) async {
      published.add(update);
    });
    addTearDown(market.dispose);
    final olderRequest = market.loadQuote('PETR4', range: '1mo');
    await firstStarted.future;
    final latestRequest = market.loadQuote('PETR4', range: '3mo');
    await secondStarted.future;
    latest.complete(http.Response(quoteBody('PETR4'), 200));
    await latestRequest;
    old.complete(http.Response(quoteBody('PETR4'), 200));
    await olderRequest;
    expect(published, hasLength(1));
    expect(published.single.freshSymbols, {'PETR4'});
  });

  test('somente rede aciona; TTL e cache vencido nunca acionam', () async {
    await state.create(draft);
    await state.evaluate(const QuoteUpdate(stocks: [quote]), auth.capture());
    await state.evaluate(
        const QuoteUpdate(stocks: [quote], hasStale: true, failed: {'PETR4'}),
        auth.capture());
    expect(state.alerts.single.isTriggered, isFalse);
    expect(notifications.shown, isEmpty);
    await state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    expect(state.alerts.single.isTriggered, isTrue);
    expect(state.activeSymbols, isEmpty);
    expect(notifications.shown, hasLength(1));
  });

  test('avaliações concorrentes notificam uma única vez', () async {
    await state.create(draft);
    await Future.wait(List.generate(
        5,
        (_) => state.evaluate(
            const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
            auth.capture())));
    expect(notifications.shown, hasLength(1));
  });

  test('permissão negada e falha do sistema não perdem aviso persistido',
      () async {
    await state.create(draft);
    expect(await state.requestPermission(), isFalse);
    notifications.fail = true;
    await state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    expect(db.stored.single.isTriggered, isTrue);
    expect(state.alerts.single.isTriggered, isTrue);
    expect(state.error, contains('Alerta acionado'));
    notifications.fail = false;
    await state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    expect(notifications.shown, isEmpty);
  });

  test('logout durante acionamento não publica nem notifica conta antiga',
      () async {
    await state.create(draft);
    db.markGate = Completer<bool>();
    final evaluation = state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    await db.marked.future;
    auth.setUser(null);
    state.clear();
    db.markGate!.complete(true);
    await evaluation;
    expect(state.alerts, isEmpty);
    expect(notifications.shown, isEmpty);
  });

  test('logout enquanto notificador inicializa impede entrega antiga',
      () async {
    await state.create(draft);
    notifications.deliveryGate = Completer<void>();
    final evaluation = state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    await notifications.deliveryStarted.future;
    expect(db.stored.single.isTriggered, isTrue);
    auth.setUser(null);
    state.clear();
    notifications.deliveryGate!.complete();
    await evaluation;
    expect(notifications.shown, isEmpty);
    expect(state.alerts, isEmpty);
  });

  test('editar mesmos critérios após commit não publica acionamento antigo',
      () async {
    await state.create(draft);
    db.markGate = Completer<bool>();
    final evaluation = state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    await db.marked.future;
    expect(db.stored.single.isTriggered, isTrue);
    await state.update(state.alerts.single.id!, draft);
    expect(db.stored.single.isTriggered, isFalse);
    db.markGate!.complete(true);
    await evaluation;
    expect(state.alerts.single.isTriggered, isFalse);
    expect(notifications.shown, isEmpty);
  });

  test('excluir enquanto entrega do sistema aguarda impede notificação antiga',
      () async {
    await state.create(draft);
    notifications.deliveryGate = Completer<void>();
    final evaluation = state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        auth.capture());
    await notifications.deliveryStarted.future;
    await state.delete(state.alerts.single.id!);
    notifications.deliveryGate!.complete();
    await evaluation;
    expect(state.alerts, isEmpty);
    expect(notifications.shown, isEmpty);
  });

  test('busca avalia só cotação da rede; resultado existente não reavalia',
      () async {
    final brapi = brapiWith(
        (request) async => http.Response(quoteBody(tickerOf(request)), 200));
    final published = <QuoteUpdate>[];
    final market = MarketState(brapi, QuoteRepository(brapi, db), auth,
        onFreshQuotes: (update, session) async {
      published.add(update);
    });
    addTearDown(market.dispose);
    await market.search('PETR4');
    await market.search('PETR4');
    expect(published, hasLength(1));
    expect(published.single.freshSymbols, {'PETR4'});
  });

  test('resposta atrasada de carga e cotação não publica na outra conta',
      () async {
    final oldSession = auth.capture();
    db.loadGate = Completer<List<PriceAlert>>();
    final loading = state.load();
    auth.setUser(const UserAccount(id: 2, name: 'Bia', email: 'bia@a.com'));
    state.clear();
    db.loadGate!.complete([draft.copyWith(id: 1)]);
    await loading;
    await state.evaluate(
        const QuoteUpdate(stocks: [quote], freshSymbols: {'PETR4'}),
        oldSession);
    expect(state.alerts, isEmpty);
    expect(notifications.shown, isEmpty);
  });

  test('erro de CRUD em português não deixa salvando', () async {
    db.failSave = true;
    await state.create(draft);
    expect(state.error, 'Este alerta já existe.');
    expect(state.saving, isFalse);
  });

  test('descarte durante carga não publica', () async {
    db.loadGate = Completer<List<PriceAlert>>();
    final loading = state.load();
    // Use instância separada para não duplicar dispose no tearDown.
    final disposed = AlertState(db, auth, notifications);
    final other = disposed.load();
    disposed.dispose();
    db.loadGate!.complete([draft.copyWith(id: 1)]);
    await Future.wait([loading, other]);
    expect(disposed.alerts, isEmpty);
  });
}
