import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/portfolio_item.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/screens/favorites_screen.dart';
import 'package:bolsa_facil/screens/home_screen.dart';
import 'package:bolsa_facil/screens/portfolio_screen.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:bolsa_facil/theme.dart';
import 'package:bolsa_facil/utils/format.dart';
import 'package:bolsa_facil/utils/list_order.dart';
import 'package:bolsa_facil/widgets/stock_tile.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

class _ListState extends AppState {
  _ListState()
      : super(brapiWith((_) async => http.Response('{}', 500)), AppDatabase());
  int suggestionCalls = 0;
  int searchCalls = 0;
  int refreshCalls = 0;
  @override
  Future<List<TickerSuggestion>> suggest(String query) async {
    suggestionCalls++;
    return [];
  }

  @override
  Future<Stock?> search(String symbol) async {
    searchCalls++;
    return stockFor(symbol);
  }

  @override
  Future<void> refresh({bool force = true}) async {
    refreshCalls++;
  }
}

_ListState _state() => _ListState()
  ..currentUser = const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com')
  ..stocks = const [
    Stock(
        symbol: 'VALE3', name: 'Vale Mineradora', price: 50, changePercent: -2),
    Stock(symbol: 'PETR4', name: 'Petrobras', price: 30, changePercent: 3),
  ];

void main() {
  Future<void> largeViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Início ordena e filtra localmente sem consultar API',
      (tester) async {
    await largeViewport(tester);
    final state = _state();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: Scaffold(body: HomeScreen(state: state))));
    expect(
        tester
            .widgetList<StockTile>(find.byType(StockTile))
            .map((w) => w.stock.symbol),
        ['PETR4', 'VALE3']);
    await tester.tap(find.byType(DropdownButton<StockOrder>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maior preço').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<StockTile>(find.byType(StockTile))
            .map((w) => w.stock.symbol),
        ['VALE3', 'PETR4']);
    await tester.enterText(
        find.byKey(const Key('home-list-filter')), 'mineradora');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StockTile), findsOneWidget);
    expect(
        tester.widget<StockTile>(find.byType(StockTile)).stock.symbol, 'VALE3');
    expect(state.searchCalls, 0);
    expect(state.suggestionCalls, 0);
    expect(state.stocks.first.symbol, 'VALE3');
    await tester.enterText(
        find.byKey(const Key('home-list-filter')), 'ausente');
    await tester.pump();
    expect(find.text('Nenhuma ação corresponde ao filtro.'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(state.refreshCalls, 1);
  });

  testWidgets(
      'favoritos salvos sem cotação mantêm dados e oferecem tentar novamente',
      (tester) async {
    final state = _state()
      ..stocks = []
      ..favorites = {'PETR4'};
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: FavoritesScreen(state: state))));
    expect(find.text('Nenhuma favorita ainda'), findsNothing);
    expect(
        find.text(
            'Seus favoritos estão salvos, mas ainda não há cotações disponíveis.'),
        findsOneWidget);
    expect(find.text('Sem cotação: PETR4.'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(state.refreshCalls, 1);
    expect(state.favorites, {'PETR4'});
  });

  testWidgets(
      'Favoritas filtra nome e distingue filtro sem resultado de lista vazia',
      (tester) async {
    await largeViewport(tester);
    final state = _state()..favorites = {'PETR4', 'VALE3'};
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: FavoritesScreen(state: state))));
    await tester.enterText(
        find.byKey(const Key('favorites-list-filter')), 'petro');
    await tester.pump();
    expect(
        tester.widget<StockTile>(find.byType(StockTile)).stock.symbol, 'PETR4');
    await tester.enterText(
        find.byKey(const Key('favorites-list-filter')), 'ausente');
    await tester.pump();
    expect(
        find.text('Nenhuma favorita corresponde ao filtro.'), findsOneWidget);
    expect(state.favorites, {'PETR4', 'VALE3'});
  });

  testWidgets('filtro da Carteira preserva totais e pizza de toda a carteira',
      (tester) async {
    await largeViewport(tester);
    final state = _state()
      ..portfolio = const [
        PortfolioItem(symbol: 'VALE3', quantity: 10, averagePrice: 40),
        PortfolioItem(symbol: 'PETR4', quantity: 2, averagePrice: 10),
      ];
    addTearDown(state.dispose);
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: PortfolioScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.text(formatMoney(560)), findsOneWidget);
    expect(tester.widget<PieChart>(find.byType(PieChart)).data.sections,
        hasLength(2));
    expect(tester.getTopLeft(find.text('PETR4').last).dy,
        lessThan(tester.getTopLeft(find.text('VALE3').last).dy));
    await tester.tap(find.byType(DropdownButton<PortfolioOrder>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maior valor da posição').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('VALE3').last).dy,
        lessThan(tester.getTopLeft(find.text('PETR4').last).dy));
    await tester.enterText(
        find.byKey(const Key('portfolio-list-filter')), 'petro');
    await tester.pumpAndSettle();
    expect(find.text(formatMoney(560)), findsOneWidget);
    expect(tester.widget<PieChart>(find.byType(PieChart)).data.sections,
        hasLength(2));
    expect(find.text('VALE3'),
        findsOneWidget); // Legend remains; position is filtered.
    expect(state.portfolio, hasLength(2));
  });

  testWidgets('controles de lista cabem em 360px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _state()..favorites = {'PETR4', 'VALE3'};
    addTearDown(state.dispose);
    for (final screen in [
      HomeScreen(state: state),
      FavoritesScreen(state: state),
      PortfolioScreen(state: state)
    ]) {
      await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: Scaffold(body: screen)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
