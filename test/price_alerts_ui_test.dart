import 'dart:async';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/price_alert.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/screens/home_screen.dart';
import 'package:bolsa_facil/screens/price_alerts_screen.dart';
import 'package:bolsa_facil/screens/stock_details_screen.dart';
import 'package:bolsa_facil/services/price_alert_notifications.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:bolsa_facil/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

class _AlertUiDatabase extends AppDatabase {
  List<PriceAlert> values = [];
  bool failLoad = false;
  bool failSave = false;
  Completer<List<PriceAlert>>? pendingLoad;
  int nextId = 1;

  @override
  Future<List<PriceAlert>> getPriceAlerts(int userId) async {
    if (failLoad) throw StateError('Falha simulada');
    if (pendingLoad != null) return pendingLoad!.future;
    return List.of(values);
  }

  @override
  Future<PriceAlert> createPriceAlert(int userId, PriceAlert alert) async {
    alert.validate();
    if (failSave) {
      throw const PriceAlertException(
          'Não foi possível salvar o alerta. Tente novamente.');
    }
    final saved = alert.copyWith(id: nextId++);
    values = [...values, saved];
    return saved;
  }

  @override
  Future<bool> updatePriceAlert(int userId, int id, PriceAlert alert) async {
    alert.validate();
    if (!values.any((item) => item.id == id)) return false;
    values = [
      for (final item in values)
        item.id == id ? alert.copyWith(id: id, rearm: true) : item
    ];
    return true;
  }

  @override
  Future<bool> deletePriceAlert(int userId, int id) async {
    if (!values.any((item) => item.id == id)) return false;
    values = values.where((item) => item.id != id).toList();
    return true;
  }
}

class _Notifications implements PriceAlertNotifications {
  int requests = 0;
  bool allowed = false;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return allowed;
  }

  @override
  Future<void> show(PriceAlert alert, double price,
      {bool Function()? canDeliver}) async {
    if (canDeliver?.call() == false) return;
  }
}

AppState _state(_AlertUiDatabase db, _Notifications notifications) => AppState(
      brapiWith(
          (request) async => http.Response(quoteBody(tickerOf(request)), 200)),
      db,
      notifications: notifications,
    )
      ..currentUser =
          const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com')
      ..stocks = const [
        Stock(symbol: 'PETR4', name: 'Petrobras', price: 30, changePercent: 1)
      ];

void main() {
  Future<void> wideViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Finder fields() => find.descendant(
      of: find.byType(AlertDialog), matching: find.byType(TextField));

  testWidgets('cria com vírgula, valida alvo e remove após confirmação',
      (tester) async {
    await wideViewport(tester);
    final db = _AlertUiDatabase();
    final state = _state(db, _Notifications());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PriceAlertsScreen(state: state, initialSymbol: 'PETR4')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields().at(0)).controller?.text, 'PETR4');
    await tester.enterText(fields().at(1), 'NaN');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar alerta'));
    await tester.pump();
    expect(find.text('Informe um código e um preço-alvo maior que zero.'),
        findsOneWidget);
    expect(db.values, isEmpty);
    await tester.enterText(fields().at(1), '35,50');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar alerta'));
    await tester.pumpAndSettle();
    expect(db.values.single.target, 35.5);
    expect(db.values.single.direction, AlertDirection.above);
    expect(find.text('Ativos'), findsOneWidget);
    expect(find.text('PETR4'), findsOneWidget);
    await tester.tap(find.byTooltip('Remover alerta de PETR4'));
    await tester.pumpAndSettle();
    expect(find.text('Remover alerta de PETR4?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();
    expect(db.values, isEmpty);
    expect(find.text('Nenhum alerta criado.'), findsOneWidget);
  });

  testWidgets('histórico mostra disparo e edição rearma com direção abaixo',
      (tester) async {
    await wideViewport(tester);
    final db = _AlertUiDatabase()
      ..values = [
        PriceAlert(
            id: 1,
            symbol: 'PETR4',
            target: 30,
            direction: AlertDirection.above,
            createdAt: DateTime(2025, 1, 1),
            triggeredAt: DateTime(2025, 1, 2, 10, 30))
      ];
    final state = _state(db, _Notifications());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: PriceAlertsScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('Disparados'), findsOneWidget);
    expect(find.textContaining('Disparado em 02/01/2025'), findsOneWidget);
    await tester.tap(find.text('Editar e rearmar'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Salvar alterações reativa este alerta. Ele poderá disparar novamente na próxima atualização.'),
        findsOneWidget);
    await tester.enterText(fields().at(1), '25,00');
    await tester.tap(find.byType(DropdownButton<AlertDirection>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atingir ou ficar abaixo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar e rearmar'));
    await tester.pumpAndSettle();
    expect(db.values.single.triggeredAt, isNull);
    expect(db.values.single.target, 25);
    expect(db.values.single.direction, AlertDirection.below);
    expect(find.text('Ativos'), findsOneWidget);
    expect(find.text('Disparados'), findsNothing);
  });

  testWidgets('solicita permissão só por botão e negação mantém histórico',
      (tester) async {
    final notifications = _Notifications();
    final state = _state(_AlertUiDatabase(), notifications);
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: PriceAlertsScreen(state: state)));
    await tester.pumpAndSettle();
    expect(notifications.requests, 0);
    await tester.tap(find.text('Ativar notificações'));
    await tester.pumpAndSettle();
    expect(notifications.requests, 1);
    expect(
        find.text(
            'Permissão não concedida. Acompanhe os disparos no histórico do app.'),
        findsOneWidget);
    await tester.tap(find.text('Ativar notificações'));
    await tester.pumpAndSettle();
    expect(notifications.requests, 2);
    expect(find.text('Nenhum alerta criado.'), findsOneWidget);
    expect(
        find.text(
            'Avaliados ao atualizar cotações com o app aberto. Cada alerta dispara uma vez.'),
        findsOneWidget);
  });

  testWidgets('carrega, mostra erro e permite tentar novamente',
      (tester) async {
    final db = _AlertUiDatabase()..pendingLoad = Completer<List<PriceAlert>>();
    final state = _state(db, _Notifications());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: PriceAlertsScreen(state: state)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    db.pendingLoad!.complete([]);
    await tester.pumpAndSettle();
    db.pendingLoad = null;
    db.failLoad = true;
    await tester.tap(find.byTooltip('Recarregar alertas'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar os alertas. Tente novamente.'),
        findsOneWidget);
    db.failLoad = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar os alertas. Tente novamente.'),
        findsNothing);
    expect(find.text('Nenhum alerta criado.'), findsOneWidget);
  });

  testWidgets(
      'falha de gravação preserva campos no diálogo para tentar novamente',
      (tester) async {
    await wideViewport(tester);
    final db = _AlertUiDatabase()..failSave = true;
    final state = _state(db, _Notifications());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: PriceAlertsScreen(state: state, initialSymbol: 'PETR4')));
    await tester.pumpAndSettle();
    await tester.enterText(fields().at(1), '35,50');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar alerta'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(fields().at(1)).controller?.text, '35,50');
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find
                .text('Não foi possível salvar o alerta. Tente novamente.')),
        findsOneWidget);
    db.failSave = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar alerta'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(db.values.single.target, 35.5);
  });

  testWidgets('Início abre alertas e detalhes preenchem código',
      (tester) async {
    await wideViewport(tester);
    final state = _state(_AlertUiDatabase(), _Notifications());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: Scaffold(body: HomeScreen(state: state))));
    await tester.tap(find.text('Alertas de preço'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum alerta criado.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: StockDetailsScreen(
            state: state, initialStock: state.stocks.single)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Criar alerta para PETR4'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields().at(0)).controller?.text, 'PETR4');
  });

  testWidgets('alertas e diálogo cabem em 360px no tema escuro',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _state(_AlertUiDatabase(), _Notifications());
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: PriceAlertsScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar alerta'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(fields().at(0), 'PETR4');
    await tester.enterText(fields().at(1), '30');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar alerta'));
    await tester.pumpAndSettle();
    expect(state.alertState.alerts, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
