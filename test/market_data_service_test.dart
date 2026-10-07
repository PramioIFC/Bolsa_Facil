import 'dart:async';
import 'dart:convert';

import 'package:bolsa_facil/services/brapi_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

Map<String, Object?> _dividends(
        {String requested = 'PETR4',
        String actual = 'PETR4',
        bool changed = false,
        List<Object?>? events}) =>
    {
      'results': [
        {
          'requestedSymbol': requested,
          'symbol': actual,
          'changed': changed,
          'data': {
            'cashDividends': events ??
                [
                  {
                    'label': 'JCP',
                    'rate': '0.20250435',
                    'paymentDate': '2026-12-21T03:00:00Z',
                    'lastDatePrior': '2026-08-21T03:00:00Z',
                    'exDate': null
                  },
                ],
            'stockDividends': [],
            'subscriptions': []
          }
        },
      ],
    };

Map<String, Object?> _currency(
        {Object? bid = '5.2159',
        Object? change = '-1.035958',
        Object? timestamp = '1770415348',
        String from = 'USD'}) =>
    {
      'fromCurrency': from,
      'toCurrency': 'BRL',
      'name': 'Dólar Americano/Real Brasileiro',
      'bidPrice': bid,
      'askPrice': 5.2189,
      'percentageChange': change,
      'updatedAtTimestamp': timestamp,
    };

Map<String, Object?> _indicator(String slug,
        {Object? latest = const {'value': '0.35', 'date': '2026-09-01'}}) =>
    {
      'series': {
        'slug': slug,
        'name':
            slug == 'ipca12m' ? 'IPCA acumulado 12 meses' : slug.toUpperCase(),
        'unit': 'percent',
        'frequency': 'monthly'
      },
      'latest': latest,
    };

BrapiService _service(Object? body) =>
    brapiWith((_) async => http.Response(jsonEncode(body), 200));

Matcher get _malformed => throwsA(isA<BrapiException>()
    .having((e) => e.failure, 'tipo', QuoteFailure.other)
    .having(
        (e) => e.message, 'mensagem', contains('dados financeiros inválidos')));

void main() {
  test('dividendos usa v2, token no header e contrato de provento por ação',
      () async {
    http.Request? seen;
    final service = brapiWith((request) async {
      seen = request;
      return http.Response(jsonEncode(_dividends()), 200);
    }, token: 'fixture');
    final events = await service.getDividends(' petr4 ');
    expect(seen!.url.path, '/api/v2/stocks/dividends');
    expect(seen!.url.queryParameters,
        {'symbols': 'PETR4', 'sortBy': 'paymentDate', 'sortOrder': 'desc'});
    expect(seen!.headers['Authorization'], 'Bearer fixture');
    expect(seen!.url.queryParameters.containsKey('token'), isFalse);
    expect(events.single.symbol, 'PETR4');
    expect(events.single.label, 'JCP');
    expect(events.single.rate, 0.20250435);
    expect(events.single.paymentDate, DateTime.utc(2026, 12, 21, 3));
    expect(events.single.dateCom, DateTime.utc(2026, 8, 21, 3));
    expect(events.single.exDate, isNull);
  });

  test('dividendos vazio e datas desconhecidas permanecem vazios e nulos',
      () async {
    expect(await _service({'results': []}).getDividends('PETR4'), isEmpty);
    expect(
        await _service(_dividends(events: [])).getDividends('PETR4'), isEmpty);
    final result = await _service(_dividends(events: [
      {
        'label': 'DIVIDENDO',
        'rate': 0,
        'paymentDate': null,
        'lastDatePrior': null,
        'exDate': null
      },
    ])).getDividends('PETR4');
    expect(result.single.rate, 0);
    expect(result.single.paymentDate, isNull);
    expect(result.single.dateCom, isNull);
  });

  test('renome de ticker precisa corresponder ao símbolo solicitado', () async {
    final events = await _service(
            _dividends(requested: 'ELET6', actual: 'AXIA6', changed: true))
        .getDividends('ELET6');
    expect(events.single.symbol, 'AXIA6');
    await expectLater(
        _service(_dividends(actual: 'VALE3')).getDividends('PETR4'),
        _malformed);
    await expectLater(
        _service(_dividends(requested: 'VALE3')).getDividends('PETR4'),
        _malformed);
  });

  test('dividendo incompleto ou não finito nunca vira zero', () async {
    for (final rate in [null, 'NaN', 'Infinity', true, 'não é número']) {
      await expectLater(
          _service(_dividends(events: [
            {'label': 'JCP', 'rate': rate}
          ])).getDividends('PETR4'),
          _malformed);
    }
    await expectLater(
        _service(_dividends(events: [
          {'label': 'JCP', 'rate': 1, 'paymentDate': 'inválida'}
        ])).getDividends('PETR4'),
        _malformed);
  });

  test('câmbio converte textos e números e usa timestamp UTC', () async {
    http.Request? seen;
    final service = brapiWith((request) async {
      seen = request;
      return http.Response(
          jsonEncode({
            'currency': [_currency()]
          }),
          200);
    }, token: 'fixture');
    final quotes = await service.getCurrencies();
    expect(seen!.url.path, '/api/v2/currency');
    expect(seen!.url.queryParameters, {'currency': 'USD-BRL,EUR-BRL'});
    expect(seen!.headers['Authorization'], 'Bearer fixture');
    expect(quotes.single.fromCurrency, 'USD');
    expect(quotes.single.toCurrency, 'BRL');
    expect(quotes.single.bidPrice, 5.2159);
    expect(quotes.single.askPrice, 5.2189);
    expect(quotes.single.changePercent, -1.035958);
    expect(quotes.single.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1770415348000, isUtc: true));
  });

  test('câmbio normaliza pares, elimina duplicados e preserva data ausente',
      () async {
    final service = brapiWith((request) async {
      expect(request.url.queryParameters, {'currency': 'USD-BRL'});
      return http.Response(
          jsonEncode({
            'currency': [_currency(timestamp: null)]
          }),
          200);
    });
    final quotes = await service.getCurrencies(pairs: [' usd-brl ', 'USD-BRL']);
    expect(quotes.single.updatedAt, isNull);
    expect(await _service({'currency': []}).getCurrencies(), isEmpty);
  });

  test('par de câmbio inesperado, duplicado ou preço ausente falha', () async {
    await expectLater(
        _service({
          'currency': [_currency(from: 'GBP')]
        }).getCurrencies(),
        _malformed);
    await expectLater(
        _service({
          'currency': [_currency(), _currency()]
        }).getCurrencies(),
        _malformed);
    for (final price in [null, 'NaN', 'Infinity', 0, -1]) {
      await expectLater(
          _service({
            'currency': [_currency(bid: price)]
          }).getCurrencies(),
          _malformed);
    }
    await expectLater(
        _service({
          'currency': [_currency(timestamp: 'NaN')]
        }).getCurrencies(),
        _malformed);
  });

  test('macro consulta somente inflação v2 com período de referência',
      () async {
    final service = brapiWith((request) async {
      expect(request.url.path, '/api/v2/macro/latest');
      expect(request.url.queryParameters, {'symbols': 'ipca,ipca12m,igpm'});
      expect(request.headers['Authorization'], 'Bearer fixture');
      return http.Response(
          jsonEncode({
            'results': [
              _indicator('ipca'),
              _indicator('ipca12m',
                  latest: {'value': 4.14, 'date': '2026-08-01'}),
              _indicator('igpm', latest: null),
            ]
          }),
          200);
    }, token: 'fixture');
    final indicators = await service.getInflation();
    expect(indicators.map((e) => e.slug), ['ipca', 'ipca12m', 'igpm']);
    expect(indicators.first.value, 0.35);
    expect(indicators.first.referenceDate, DateTime(2026, 9, 1));
    expect(indicators.first.unit, 'percent');
    expect(indicators.first.frequency, 'monthly');
    expect(indicators[1].name, 'IPCA acumulado 12 meses');
    expect(indicators[1].value, 4.14);
    expect(indicators.last.value, isNull);
    expect(indicators.last.referenceDate, isNull);
  });

  test('deflação é válida e macro vazia é distinta de erro', () async {
    final result = await _service({
      'results': [
        _indicator('igpm', latest: {'value': '-0.42', 'date': '2026-09-01'})
      ]
    }).getInflation();
    expect(result.single.value, -0.42);
    expect(await _service({'results': []}).getInflation(), isEmpty);
  });

  test('macro fora da consulta, duplicada ou com valor inválido falha',
      () async {
    for (final entries in [
      [_indicator('selic')],
      [_indicator('ipca'), _indicator('ipca')],
      [
        _indicator('ipca', latest: {'date': '2026-09-01'})
      ],
      [
        _indicator('ipca', latest: {'value': 'Infinity', 'date': '2026-09-01'})
      ],
      [
        _indicator('ipca', latest: {'value': 1, 'date': 'inválida'})
      ],
      [_indicator('ipca')..remove('latest')],
    ]) {
      await expectLater(
          _service({'results': entries}).getInflation(), _malformed);
    }
  });

  test('entradas inválidas não fazem HTTP; lista de moedas vazia não consulta',
      () async {
    var calls = 0;
    final service = brapiWith((_) async {
      calls++;
      return http.Response('{}', 200);
    });
    await expectLater(
        service.getDividends('PETR4,VALE3'), throwsA(isA<BrapiException>()));
    await expectLater(service.getCurrencies(pairs: ['USD/BRL']),
        throwsA(isA<BrapiException>()));
    expect(await service.getCurrencies(pairs: []), isEmpty);
    expect(calls, 0);
  });

  test('401, 402 e 403 têm erro de token ou plano sem fallback silencioso',
      () async {
    for (final status in [401, 402, 403]) {
      var calls = 0;
      final service = brapiWith((_) async {
        calls++;
        return http.Response('{}', status);
      });
      await expectLater(
          service.getInflation(),
          throwsA(isA<BrapiException>()
              .having((e) => e.failure, 'tipo', QuoteFailure.unauthorized)
              .having((e) => e.message, 'mensagem', contains('plano'))));
      expect(calls, 1);
    }
  });

  test('429 respeita Retry-After e volta a carregar dados', () async {
    var calls = 0;
    final delays = <Duration>[];
    final service = brapiWith((_) async {
      calls++;
      return calls == 1
          ? http.Response('{}', 429, headers: {'retry-after': '2'})
          : http.Response(
              jsonEncode({
                'currency': [_currency()]
              }),
              200);
    }, delays: delays);
    expect(await service.getCurrencies(), hasLength(1));
    expect(calls, 2);
    expect(delays, [const Duration(seconds: 2)]);
  });

  test('429 persistente termina após limite e 404/500 são tipados', () async {
    for (final (status, failure) in [
      (429, QuoteFailure.rateLimited),
      (404, QuoteFailure.notFound),
      (500, QuoteFailure.other)
    ]) {
      var calls = 0;
      final service = brapiWith((_) async {
        calls++;
        return http.Response('{}', status);
      });
      await expectLater(
          service.getInflation(),
          throwsA(
              isA<BrapiException>().having((e) => e.failure, 'tipo', failure)));
      expect(calls, status == 429 ? 3 : 1);
    }
  });

  test('falha de rede e timeout têm mensagem tipada sem detalhes internos',
      () async {
    for (final error in [
      http.ClientException('internal'),
      TimeoutException('internal')
    ]) {
      final service = brapiWith((_) async => throw error);
      await expectLater(
          service.getCurrencies(),
          throwsA(isA<BrapiException>()
              .having((e) => e.failure, 'tipo', QuoteFailure.network)
              .having(
                  (e) => e.message, 'mensagem', isNot(contains('internal')))));
    }
  });

  test('JSON inválido ou envelope de dados incorreto não parece vazio',
      () async {
    final service = brapiWith((_) async => http.Response('não é JSON', 200));
    await expectLater(service.getDividends('PETR4'), _malformed);
    await expectLater(_service({}).getCurrencies(), _malformed);
    await expectLater(
        _service({
          'results': [null]
        }).getInflation(),
        _malformed);
    await expectLater(
        _service({'results': null}).getDividends('PETR4'), _malformed);
  });
}
