import 'dart:async';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/market_data.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/screens/dividends_screen.dart';
import 'package:bolsa_facil/screens/home_screen.dart';
import 'package:bolsa_facil/screens/market_data_screen.dart';
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
  bool failCurrencies = false, failInflation = false, failDividends = false;
  Future<List<CurrencyQuote>>? pendingCurrencies;
  List<CurrencyQuote> currencies = [
    CurrencyQuote(
        fromCurrency: 'USD',
        toCurrency: 'BRL',
        name: 'Dólar / Real',
        bidPrice: 5.1234,
        askPrice: 5.1244,
        changePercent: -1.2,
        updatedAt: DateTime(2025, 10, 1, 10, 30))
  ];
  List<InflationIndicator> inflation = [
    InflationIndicator(
        slug: 'ipca',
        name: 'IPCA',
        unit: 'percent',
        frequency: 'monthly',
        value: 0.48,
        referenceDate: DateTime(2025, 10, 1))
  ];
  List<CashDividend> dividends = const [
    CashDividend(
        symbol: 'PETR4', label: 'Juros sobre capital próprio', rate: 1.2345)
  ];

  @override
  Future<List<CurrencyQuote>> getCurrencies(
      {List<String> pairs = const ['USD-BRL', 'EUR-BRL']}) async {
    currenciesCalls++;
    if (failCurrencies) {
      throw const BrapiException('Câmbio indisponível neste plano.');
    }
    if (pendingCurrencies != null) return pendingCurrencies!;
    return currencies;
  }

  @override
  Future<List<InflationIndicator>> getInflation() async {
    inflationCalls++;
    if (failInflation) {
      throw const BrapiException('Inflação indisponível neste plano.');
    }
    return inflation;
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

  testWidgets(
      'Home consulta câmbio só ao abrir e inflação só na primeira seleção',
      (tester) async {
    await largeViewport(tester);
    final state = _state();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: Scaffold(body: HomeScreen(state: state))));
    expect(state.currenciesCalls, 0);
    expect(state.inflationCalls, 0);
    await tester.tap(find.text('Câmbio e inflação'));
    await tester.pumpAndSettle();
    expect(state.currenciesCalls, 1);
    expect(state.inflationCalls, 0);
    expect(find.text('USD → BRL'), findsOneWidget);
    expect(find.text('Compra (BRL): 5,1234'), findsOneWidget);
    await tester.tap(find.text('Inflação'));
    await tester.pumpAndSettle();
    expect(state.inflationCalls, 1);
    expect(find.text('0,48 %'), findsOneWidget);
    expect(find.text('Periodicidade: Mensal'), findsOneWidget);
    expect(find.text('Referência: 10/2025'), findsOneWidget);
    await tester.tap(find.text('Câmbio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inflação'));
    await tester.pumpAndSettle();
    expect(state.inflationCalls, 1);
    expect(state.currenciesCalls, 1);
  });

  testWidgets(
      'inflação sem latest mostra indisponível e erro tem retry explícito',
      (tester) async {
    final state = _state()
      ..failInflation = true
      ..inflation = const [
        InflationIndicator(
            slug: 'ipca12m',
            name: 'IPCA 12 meses',
            unit: 'percent',
            frequency: 'monthly')
      ];
    addTearDown(state.dispose);
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: MarketDataScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inflação'));
    await tester.pumpAndSettle();
    expect(find.text('Inflação indisponível neste plano.'), findsOneWidget);
    state.failInflation = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(state.inflationCalls, 2);
    expect(find.text('Valor indisponível.'), findsOneWidget);
    expect(find.text('Referência não informada.'), findsOneWidget);
    expect(find.text('0,00 %'), findsNothing);
  });

  testWidgets('câmbio mostra loading, falha, retry e resposta vazia',
      (tester) async {
    final pending = Completer<List<CurrencyQuote>>();
    final state = _state()..pendingCurrencies = pending.future;
    addTearDown(state.dispose);
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: MarketDataScreen(state: state)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(
        const BrapiException('Câmbio indisponível neste plano.'));
    await tester.pumpAndSettle();
    expect(find.text('Câmbio indisponível neste plano.'), findsOneWidget);
    state.pendingCurrencies = null;
    state.currencies = [];
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma cotação de câmbio disponível.'), findsOneWidget);
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
    expect(find.text('Dividend Yield: 5,00%'), findsOneWidget);
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

  testWidgets('resposta depois de trocar sessão não publica dados antigos',
      (tester) async {
    final pending = Completer<List<CurrencyQuote>>();
    final state = _state()..pendingCurrencies = pending.future;
    addTearDown(state.dispose);
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: MarketDataScreen(state: state)));
    state.currentUser =
        const UserAccount(id: 2, name: 'Bia', email: 'bia@teste.com');
    pending.complete(state.currencies);
    await tester.pumpAndSettle();
    expect(find.text('USD → BRL'), findsNothing);
    expect(find.text('Sua sessão mudou. Tente novamente.'), findsOneWidget);
  });

  testWidgets('resposta depois de fechar tela não causa setState após dispose',
      (tester) async {
    final pending = Completer<List<CurrencyQuote>>();
    final state = _state()..pendingCurrencies = pending.future;
    addTearDown(state.dispose);
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: MarketDataScreen(state: state)));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(state.currencies);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('telas extras cabem em 360px com tema escuro', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = _state();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: MarketDataScreen(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inflação'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: DividendsScreen(state: state, symbol: 'PETR4')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
