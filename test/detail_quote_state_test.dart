import 'package:bolsa_facil/models/price_alert.dart';
import 'dart:async';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/services/brapi_service.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

class _SessionDatabase extends AppDatabase {
  @override
  Future<List<PriceAlert>> getPriceAlerts(int userId) async => [];
  @override
  Future<void> logout() async {}
}

void main() {
  const original =
      Stock(symbol: 'PETR4', name: 'Petrobras', price: 20, changePercent: 1);

  test('detalhes normalizam código e substituem cotação sem duplicar',
      () async {
    String? requestedSymbol;
    final state = AppState(brapiWith((request) async {
      requestedSymbol = tickerOf(request);
      return http.Response(quoteBody(requestedSymbol!, price: 35), 200);
    }), _SessionDatabase())
      ..stocks = [original];
    addTearDown(state.dispose);
    var notifications = 0;
    state.addListener(() => notifications++);

    final quote = await state.loadQuote(' petr4 ', range: '1y');
    expect(requestedSymbol, 'PETR4');
    expect(quote.price, 35);
    expect(state.stocks, hasLength(1));
    expect(state.stockFor('PETR4')?.price, 35);
    expect(notifications, 1);
  });

  test('detalhes inserem cotação quando ativo ainda não está na lista',
      () async {
    final state = AppState(
        brapiWith((request) async =>
            http.Response(quoteBody(tickerOf(request), price: 42), 200)),
        _SessionDatabase());
    addTearDown(state.dispose);
    await state.loadQuote('VALE3');
    expect(state.stocks.single.symbol, 'VALE3');
    expect(state.stocks.single.price, 42);
  });

  test('erro dos detalhes preserva cotação anterior', () async {
    final state = AppState(
        brapiWith((_) async => http.Response('{}', 500)), _SessionDatabase())
      ..stocks = [original];
    addTearDown(state.dispose);
    await expectLater(state.loadQuote('PETR4'), throwsA(isA<BrapiException>()));
    expect(state.stocks.single, same(original));
  });

  test('resposta antiga de outro período não sobrescreve período mais recente',
      () async {
    final oldResponse = Completer<http.Response>();
    final newResponse = Completer<http.Response>();
    final oldStarted = Completer<void>();
    final newStarted = Completer<void>();
    final state = AppState(brapiWith((request) {
      if (request.url.queryParameters['range'] == '5d') {
        oldStarted.complete();
        return oldResponse.future;
      }
      newStarted.complete();
      return newResponse.future;
    }), _SessionDatabase())
      ..stocks = [original];
    addTearDown(state.dispose);
    final oldQuote = state.loadQuote('PETR4', range: '5d');
    await oldStarted.future;
    final newQuote = state.loadQuote('PETR4', range: '1y');
    await newStarted.future;
    newResponse.complete(http.Response(quoteBody('PETR4', price: 50), 200));
    await newQuote;
    oldResponse.complete(http.Response(quoteBody('PETR4', price: 30), 200));
    await oldQuote;
    expect(state.stocks.single.price, 50);
  });

  test('resposta de detalhes após logout não restaura lista', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final state = AppState(brapiWith((_) {
      started.complete();
      return response.future;
    }), _SessionDatabase())
      ..stocks = [original];
    addTearDown(state.dispose);
    final quote = state.loadQuote('PETR4');
    await started.future;
    await state.logout();
    response.complete(http.Response(quoteBody('PETR4', price: 50), 200));
    await quote;
    expect(state.stocks, isEmpty);
  });

  test('resposta de detalhes após dispose não altera nem notifica estado',
      () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final state = AppState(brapiWith((_) {
      started.complete();
      return response.future;
    }), _SessionDatabase())
      ..stocks = [original];
    var notifications = 0;
    state.addListener(() => notifications++);
    final quote = state.loadQuote('PETR4');
    await started.future;
    state.dispose();
    response.complete(http.Response(quoteBody('PETR4', price: 50), 200));
    await quote;
    expect(state.stocks.single, same(original));
    expect(notifications, 0);
  });
}
