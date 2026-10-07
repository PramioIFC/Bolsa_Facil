import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/market_data.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/screens/dividends_screen.dart';
import 'package:bolsa_facil/screens/home_screen.dart';
import 'package:bolsa_facil/screens/stock_details_screen.dart';
import 'package:bolsa_facil/services/brapi_service.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:bolsa_facil/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

class _DataState extends AppState {
  _DataState()
      : super(brapiWith((_) async => http.Response('{}', 500)), AppDatabase());
  int currenciesCalls = 0, inflationCalls = 0, dividendsCalls = 0;
  bool failDividends = false;
  List<CashDividend> dividends = const [
    CashDividend(
        symbol: 'PETR4', label: 'Juros sobre capital próprio', rate: 1.2345)
  ];

  @override
  Future<List<CurrencyQuote>> getCurrencies(
      {List<String> pairs = const ['USD-BRL', 'EUR-BRL']}) async {
    currenciesCalls++;
    return const [];
  }

  @override
  Future<List<InflationIndicator>> getInflation() async {
    inflationCalls++;
    return const [];
  }

  @override
  Future<List<CashDividend>> getDividends(String symbol) async {
    dividendsCalls++;
    if (failDividends) {
      throw const BrapiException('Proventos indisponíveis neste plano.');
    }
    return dividends;
  }

  @override
  Future<Stock> loadQuote(String symbol, {String range = '3mo'}) async =>
      stockFor(symbol)!;
}

_DataState _state() => _DataState()
  ..currentUser = const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com')
  ..stocks = const [
    Stock(
        symbol: 'PETR4',
        name: 'Petrobras',
        price: 30,
        changePercent: 1,
        dividendYield: .05)
  ];

void main() {
  Future<void> largeViewport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('Home não oferece câmbio e inflação nem consulta esses dados',
      (tester) async {
    await largeViewport(tester);
    final state = _state();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: Scaffold(body: HomeScreen(state: state))));
    await tester.pumpAndSettle();
    expect(find.text('Câmbio e inflação'), findsNothing);
    expect(find.byIcon(Icons.currency_exchange), findsNothing);
    expect(find.text('Alertas de preço'), findsOneWidget);
    expect(find.text('PETR4'), findsOneWidget);
    expect(state.currenciesCalls, 0);
    expect(state.inflationCalls, 0);
  });
  testWidgets('detalhes abrem pagamentos reais sem projetar retorno',
      (tester) async {
    await largeViewport(tester);
    final state = _state();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: StockDetailsScreen(
            state: state, initialStock: state.stocks.single)));
    await tester.pumpAndSettle();
    expect(state.dividendsCalls, 0);
    expect(find.text('Rendimento de dividendos: 5,00%'), findsOneWidget);
    expect(find.textContaining('Se você investir'), findsNothing);
    await tester.tap(find.text('Dividendos e JCP'));
    await tester.pumpAndSettle();
    expect(state.dividendsCalls, 1);
    expect(find.text('Juros sobre capital próprio'), findsOneWidget);
    expect(find.textContaining('1,2345'), findsOneWidget);
    expect(find.text('Pagamento: não informado'), findsOneWidget);
    expect(find.text('Data-com: não informado'), findsOneWidget);
    expect(find.text('Data ex: não informado'), findsOneWidget);
  });

  testWidgets('proventos vazios e falha de plano mostram estados distintos',
      (tester) async {
    final state = _state()
      ..failDividends = true
      ..dividends = [];
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: DividendsScreen(state: state, symbol: 'PETR4')));
    await tester.pumpAndSettle();
    expect(find.text('Proventos indisponíveis neste plano.'), findsOneWidget);
    state.failDividends = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum pagamento informado para este ativo.'),
        findsOneWidget);
  });

  testWidgets('proventos cabem em 360px com tema escuro', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _state();
    addTearDown(state.dispose);

    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: DividendsScreen(state: state, symbol: 'PETR4')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
