import 'package:bolsa_facil/services/brapi_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

void main() {
  test('fetchQuote mapeia a resposta e não envia o token na URL', () async {
    http.Request? seen;
    final service = brapiWith((request) async {
      seen = request;
      return http.Response(quoteBody('PETR4', price: 38.5), 200);
    }, token: 'abc');
    final result = await service.fetchQuote('petr4');
    expect(result.stock!.symbol, 'PETR4');
    expect(result.stock!.price, 38.5);
    expect(seen!.headers['Authorization'], 'Bearer abc');
    expect(seen!.url.queryParameters.containsKey('token'), isFalse);
  });

  test('classifica falhas: 404, 401 e 500', () async {
    Future<QuoteFailure?> failureFor(int status) async {
      final service = brapiWith((_) async => http.Response('{}', status));
      return (await service.fetchQuote('X')).failure;
    }

    expect(await failureFor(404), QuoteFailure.notFound);
    expect(await failureFor(401), QuoteFailure.unauthorized);
    expect(await failureFor(500), QuoteFailure.other);
  });

  test('resultado vazio vira notFound', () async {
    final service = brapiWith((_) async => http.Response('{"results":[]}', 200));
    expect((await service.fetchQuote('X')).failure, QuoteFailure.notFound);
  });

  test('repete em HTTP 429 com backoff e depois tem sucesso', () async {
    var calls = 0;
    final delays = <Duration>[];
    final service = brapiWith((request) async {
      calls++;
      return calls < 3 ? http.Response('', 429) : http.Response(quoteBody('PETR4'), 200);
    }, delays: delays);
    final result = await service.fetchQuote('PETR4');
    expect(result.stock, isNotNull);
    expect(calls, 3);
    expect(delays, [const Duration(milliseconds: 500), const Duration(milliseconds: 1000)]);
  });

  test('429 persistente vira rateLimited e o lote é abortado', () async {
    var calls = 0;
    final service = brapiWith((_) async {
      calls++;
      return http.Response('', 429);
    });
    final batch = await service.fetchQuotes(['A1', 'B2', 'C3', 'D4', 'E5'], concurrency: 1);
    expect(batch.stocks, isEmpty);
    expect(batch.rateLimited, isTrue);
    expect(batch.failures.keys, containsAll(['A1', 'B2', 'C3', 'D4', 'E5']));
    // Só o primeiro ticker foi tentado (1 + 2 repetições); os demais foram abortados.
    expect(calls, 3);
  });

  test('fetchQuotes respeita o limite de concorrência e remove duplicatas', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final seen = <String>[];
    final service = brapiWith((request) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      seen.add(tickerOf(request));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      return http.Response(quoteBody(tickerOf(request)), 200);
    });
    final symbols = ['AAAA3', 'BBBB3', 'CCCC3', 'DDDD3', 'EEEE3', 'FFFF3', 'aaaa3'];
    final batch = await service.fetchQuotes(symbols, concurrency: 3);
    expect(batch.stocks.keys.toSet(), {'AAAA3', 'BBBB3', 'CCCC3', 'DDDD3', 'EEEE3', 'FFFF3'});
    expect(seen.length, 6);
    expect(maxInFlight, lessThanOrEqualTo(3));
    expect(maxInFlight, greaterThan(1));
  });

  test('getQuote refaz sem fundamentos quando a primeira tentativa falha', () async {
    final urls = <Uri>[];
    final service = brapiWith((request) async {
      urls.add(request.url);
      return request.url.queryParameters.containsKey('modules')
          ? http.Response('{}', 402)
          : http.Response(quoteBody('PETR4'), 200);
    });
    final stock = await service.getQuote('PETR4', range: '1mo');
    expect(stock.symbol, 'PETR4');
    expect(urls, hasLength(2));
    expect(urls.last.queryParameters, {'range': '1mo', 'interval': '1d'});
  });

  test('getQuote lança BrapiException com a falha tipada', () async {
    final service = brapiWith((_) async => http.Response('', 404));
    await expectLater(
      service.getQuote('NADA3'),
      throwsA(isA<BrapiException>().having((e) => e.failure, 'failure', QuoteFailure.notFound)),
    );
  });

  test('searchTickers lê "stocks", aceita stock/symbol e nunca lança', () async {
    final service = brapiWith((request) async {
      expect(request.url.path, endsWith('/quote/list'));
      expect(request.url.queryParameters['search'], 'petr');
      return http.Response(
        '{"stocks":[{"stock":"PETR4","name":"Petrobras PN"},{"symbol":"PETR3","name":"Petrobras ON"},{"stock":"PETR4"}]}',
        200,
      );
    });
    final result = await service.searchTickers('petr');
    expect(result.map((s) => s.symbol), ['PETR4', 'PETR3']);

    final broken = brapiWith((_) async => http.Response('oops', 500));
    expect(await broken.searchTickers('petr'), isEmpty);
    expect(await service.searchTickers('p'), isEmpty);
  });

  test('getQuote: 401/403 nos fundamentos não impede de mostrar o ativo', () async {
    final service = brapiWith((request) async => request.url.queryParameters.containsKey('modules')
        ? http.Response('{}', 403)
        : http.Response(quoteBody('WEGE3'), 200));
    final stock = await service.getQuote('WEGE3');
    expect(stock.symbol, 'WEGE3');
  });

  test('getQuote: sem histórico no plano, devolve a cotação básica', () async {
    final urls = <Uri>[];
    final service = brapiWith((request) async {
      urls.add(request.url);
      return request.url.queryParameters.containsKey('range')
          ? http.Response('{}', 403)
          : http.Response(quoteBody('WEGE3'), 200);
    });
    final stock = await service.getQuote('WEGE3');
    expect(stock.symbol, 'WEGE3');
    expect(stock.history, isEmpty);
    expect(urls, hasLength(3));
  });

  test('getQuote: 401 em todas as tentativas vira unauthorized', () async {
    final service = brapiWith((_) async => http.Response('{}', 401));
    await expectLater(
      service.getQuote('WEGE3'),
      throwsA(isA<BrapiException>().having((e) => e.failure, 'failure', QuoteFailure.unauthorized)),
    );
  });

  test('getQuote não insiste quando há limite de requisições', () async {
    var calls = 0;
    final service = brapiWith((_) async {
      calls++;
      return http.Response('', 429);
    });
    await expectLater(service.getQuote('WEGE3'), throwsA(isA<BrapiException>()));
    expect(calls, 3); // 1 + 2 repetições da primeira tentativa; sem as outras tentativas
  });
}
