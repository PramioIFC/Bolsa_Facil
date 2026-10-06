import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/services/brapi_service.dart';
import 'package:bolsa_facil/services/quote_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late DateTime now;
  late int calls;
  late bool failing;
  late QuoteRepository repository;

  setUp(() {
    db = memoryDatabase();
    now = DateTime(2026, 1, 1, 12);
    calls = 0;
    failing = false;
    final brapi = brapiWith((request) async {
      calls++;
      if (failing) return http.Response('', 500);
      return http.Response(quoteBody(tickerOf(request)), 200);
    });
    repository = QuoteRepository(brapi, db, ttl: const Duration(minutes: 5), clock: () => now);
  });
  tearDown(() => db.close());

  test('primeira consulta busca na rede e grava no cache', () async {
    final update = await repository.getQuotes(['PETR4', 'VALE3']);
    expect(update.stocks.map((s) => s.symbol), ['PETR4', 'VALE3']);
    expect(calls, 2);
    expect(update.failed, isEmpty);
    expect(update.updatedAt, now);
  });

  test('dentro do TTL usa só o cache; forceRefresh ignora o TTL', () async {
    await repository.getQuotes(['PETR4']);
    now = now.add(const Duration(minutes: 2));
    await repository.getQuotes(['PETR4']);
    expect(calls, 1);
    await repository.getQuotes(['PETR4'], forceRefresh: true);
    expect(calls, 2);
  });

  test('após o TTL consulta de novo', () async {
    await repository.getQuotes(['PETR4']);
    now = now.add(const Duration(minutes: 6));
    await repository.getQuotes(['PETR4']);
    expect(calls, 2);
  });

  test('falha na rede usa o cache vencido e sinaliza dado antigo', () async {
    await repository.getQuotes(['PETR4']);
    now = now.add(const Duration(hours: 1));
    failing = true;
    final update = await repository.getQuotes(['PETR4']);
    expect(update.stocks.single.symbol, 'PETR4');
    expect(update.hasStale, isTrue);
    expect(update.failed, {'PETR4'});
    expect(update.updatedAt, DateTime(2026, 1, 1, 12));
  });

  test('sem cache e sem rede lança BrapiException', () async {
    failing = true;
    await expectLater(repository.getQuotes(['PETR4']), throwsA(isA<BrapiException>()));
  });

  test('falha parcial: mantém os que vieram e lista os que falharam', () async {
    final brapi = brapiWith((request) async => tickerOf(request) == 'RUIM3'
        ? http.Response('', 500)
        : http.Response(quoteBody(tickerOf(request)), 200));
    final partial = QuoteRepository(brapi, db, clock: () => now);
    final update = await partial.getQuotes(['PETR4', 'RUIM3']);
    expect(update.stocks.map((s) => s.symbol), ['PETR4']);
    expect(update.failed, {'RUIM3'});
    expect(update.hasStale, isFalse);
  });
}
