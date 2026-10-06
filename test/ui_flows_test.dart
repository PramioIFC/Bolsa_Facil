import 'dart:convert';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:bolsa_facil/models/portfolio_item.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/screens/account_screen.dart';
import 'package:bolsa_facil/screens/app_shell.dart';
import 'package:bolsa_facil/screens/home_screen.dart';
import 'package:bolsa_facil/screens/portfolio_screen.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

class _FailingFavoriteDatabase extends AppDatabase {
  @override
  Future<void> toggleFavorite(int userId, String symbol, bool favorite) async {
    throw StateError('Falha de gravação simulada');
  }
}

/// Test double for UI contracts; SQLite atomicity is verified separately.
class _UiDatabase extends AppDatabase {
  final trades = <Trade>[];
  final favorites = <String>{};

  @override
  Future<void> recordTrade(int userId, Trade trade) async {
    summarizeTrades([...trades.where((t) => t.symbol == trade.symbol), trade]);
    trades.add(trade);
  }

  @override
  Future<List<Trade>> getTrades(int userId, {String? symbol}) async =>
      trades.where((t) => symbol == null || t.symbol == symbol).toList();

  @override
  Future<List<PortfolioItem>> getPositions(int userId) async => [
        for (final symbol in trades.map((t) => t.symbol).toSet())
          if (summarizeTrades(trades.where((t) => t.symbol == symbol))
                  .quantity >
              0)
            PortfolioItem(
              symbol: symbol,
              quantity: summarizeTrades(trades.where((t) => t.symbol == symbol))
                  .quantity,
              averagePrice:
                  summarizeTrades(trades.where((t) => t.symbol == symbol))
                      .averagePrice,
            ),
      ];

  @override
  Future<double> getRealizedProfit(int userId) async =>
      trades.map((t) => t.symbol).toSet().fold<double>(
          0.0,
          (sum, symbol) =>
              sum +
              summarizeTrades(trades.where((t) => t.symbol == symbol))
                  .realizedProfit);

  @override
  Future<Set<String>> getFavorites(int userId) async => {...favorites};

  @override
  Future<void> toggleFavorite(int userId, String symbol, bool favorite) async {
    favorite ? favorites.add(symbol) : favorites.remove(symbol);
  }

  @override
  Future<void> removePosition(int userId, String symbol) async =>
      trades.removeWhere((t) => t.symbol == symbol);

  @override
  Future<Map<String, CachedQuote>> getCachedQuotes(
          Iterable<String> symbols) async =>
      {};

  @override
  Future<void> putCachedQuotes(
      Map<String, Stock> quotes, DateTime fetchedAt) async {}

  @override
  Future<Map<String, dynamic>> exportUserData(int userId) async => {
        'app': 'bolsa_facil',
        'version': 1,
        'favorites': favorites.toList(),
        'transactions': trades.map((t) => t.toJson()).toList(),
      };

  @override
  Future<void> importUserData(int userId, Map<String, dynamic> data) async {
    favorites
      ..clear()
      ..addAll((data['favorites'] as List).cast<String>());
    trades
      ..clear()
      ..addAll((data['transactions'] as List)
          .map((t) => Trade.fromJson(t as Map<String, dynamic>)));
  }
}

void main() {
  Future<AppState> authenticatedState(WidgetTester tester) async {
    final state = AppState(
      brapiWith((request) async =>
          http.Response(quoteBody(tickerOf(request), price: 50), 200)),
      _UiDatabase(),
    )..currentUser =
        const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com');
    addTearDown(state.dispose);
    await state.refresh();
    return state;
  }

  Future<void> wideViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Carteira mostra alocação, valida venda e registra histórico',
      (tester) async {
    await wideViewport(tester);
    final state = await authenticatedState(tester);
    await state.buy('PETR4', 10, 20);
    await tester.pumpWidget(MaterialApp(home: PortfolioScreen(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('Alocação'), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);
    expect(
        tester
            .widget<PieChart>(find.byType(PieChart))
            .data
            .sections
            .single
            .value,
        500);

    await tester.ensureVisible(find.byType(PopupMenuButton<String>).first);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vender'));
    await tester.pumpAndSettle();
    final sellFields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(sellFields.at(0), '11');
    await tester.tap(find.widgetWithText(FilledButton, 'Vender'));
    await tester.pump();
    expect(find.text('Você só possui 10.0.'), findsOneWidget);
    expect(state.portfolio.single.quantity, 10);

    await tester.enterText(sellFields.at(0), '4');
    await tester.enterText(sellFields.at(1), '35,00');
    await tester.enterText(sellFields.at(2), '2,00');

    await tester.tap(find.widgetWithText(FilledButton, 'Vender'));
    await tester.pump();

    await tester.pumpAndSettle();
    expect(find.text('Venda de PETR4 registrada.'), findsOneWidget);
    expect(state.portfolio.single.quantity, 6);
    expect(state.realizedProfit, 58);

    await tester.ensureVisible(find.byType(PopupMenuButton<String>).first);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Histórico'));
    await tester.pump();
    await state.tradesFor('PETR4');

    await tester.pumpAndSettle();
    expect(find.text('Histórico • PETR4'), findsOneWidget);
    expect(find.textContaining('Compra • 10'), findsOneWidget);
    expect(find.textContaining('Venda • 4'), findsOneWidget);
    expect(find.textContaining('taxas'), findsOneWidget);
  });

  testWidgets(
      'Home avisa falhas parciais e dados antigos sem esconder cotações',
      (tester) async {
    final db = _UiDatabase();
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..stocks = const [
        Stock(symbol: 'PETR4', name: 'Petrobras', price: 30, changePercent: 1)
      ]
      ..failedSymbols = {'VALE3', 'BBDC4'}
      ..usingStaleData = true
      ..updatedAt = DateTime(2025, 1, 2, 10, 30);
    addTearDown(state.dispose);
    addTearDown(db.close);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HomeScreen(state: state))));
    expect(find.textContaining('Sem atualização para: BBDC4, VALE3.'),
        findsOneWidget);
    expect(find.textContaining('Exibindo dados salvos'), findsOneWidget);
    expect(find.text('PETR4'), findsOneWidget);
  });

  testWidgets('falha ao salvar favorito faz rollback e exibe SnackBar uma vez',
      (tester) async {
    await wideViewport(tester);
    final db = _FailingFavoriteDatabase();
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser =
          const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com')
      ..stocks = const [
        Stock(symbol: 'PETR4', name: 'Petrobras', price: 30, changePercent: 1)
      ];
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.tap(find.byTooltip('Adicionar aos favoritos'));
    await tester.pumpAndSettle();
    expect(state.favorites, isEmpty);
    expect(find.byTooltip('Adicionar aos favoritos'), findsOneWidget);
    expect(find.text('Não foi possível salvar o favorito. Tente novamente.'),
        findsOneWidget);
    expect(state.actionError, isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Conta exporta JSON sem senha e restaura carteira e favoritos',
      (tester) async {
    await wideViewport(tester);
    final state = await authenticatedState(tester);

    await state.buy('PETR4', 10, 20);
    await state.toggleFavorite('WEGE3');

    String? clipboard;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AccountScreen(state: state))));

    await tester.tap(find.text('Exportar backup (copiar JSON)'));

    await tester.pumpAndSettle();
    expect(find.text('Backup copiado. Cole em um arquivo para guardá-lo.'),
        findsOneWidget);
    expect(clipboard, isNotNull);
    final backup = jsonDecode(clipboard!) as Map<String, dynamic>;
    expect(backup['app'], 'bolsa_facil');
    expect(clipboard, isNot(contains('password')));
    // Complete the export snackbar's visible duration before importing.
    final exportSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    await tester.pump(exportSnackBar.duration);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    await state.removePosition('PETR4');
    await state.toggleFavorite('WEGE3');

    await tester.tap(find.text('Importar backup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), clipboard!);

    await tester.tap(find.widgetWithText(FilledButton, 'Importar'));
    await tester.pump();

    await tester.pumpAndSettle();
    expect(find.text('Backup importado com sucesso.'), findsOneWidget);
    expect(state.portfolio.single.quantity, 10);
    expect(state.favorites, {'WEGE3'});
  });
}
