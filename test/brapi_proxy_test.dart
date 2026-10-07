import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/brapi_proxy.dart';

void main() {
  late HttpServer upstream;
  late BrapiProxy proxy;
  late HttpClient client;
  late List<({String path, Map<String, String> query, String? auth})> received;
  var upstreamStatus = 200;
  const fixtureToken = 'fixture-local-proxy-test';
  Uri target(String path) => Uri.parse('http://127.0.0.1:${proxy.port}$path');
  Future<
      ({
        int status,
        String body,
        String? cors,
        String? retry,
        String? location
      })> request(String path, {String method = 'GET', String? origin}) async {
    final outgoing = await client.openUrl(method, target(path));
    outgoing.followRedirects = false;
    if (origin != null) outgoing.headers.set('Origin', origin);
    final response = await outgoing.close();
    final body = await utf8.decoder.bind(response).join();
    return (
      status: response.statusCode,
      body: body,
      cors: response.headers.value('access-control-allow-origin'),
      retry: response.headers.value('retry-after'),
      location: response.headers.value('location')
    );
  }

  setUp(() async {
    received = [];
    upstreamStatus = 200;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      received.add((
        path: request.uri.path,
        query: request.uri.queryParameters,
        auth: request.headers.value(HttpHeaders.authorizationHeader)
      ));
      request.response.statusCode = upstreamStatus;
      request.response.headers.contentType = ContentType.json;
      if (upstreamStatus == 302) {
        request.response.headers
            .set('location', 'http://127.0.0.1:${upstream.port}/sink');
      }
      if (upstreamStatus == 429) {
        request.response.headers.set('retry-after', '17');
      }
      request.response.write(upstreamStatus == 200
          ? jsonEncode({'ok': true})
          : jsonEncode({'error': fixtureToken}));
      await request.response.close();
    });
    proxy = await startBrapiProxy(
        token: fixtureToken,
        port: 0,
        upstreamBase: Uri.parse('http://127.0.0.1:${upstream.port}/'));
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await proxy.close();
    await upstream.close(force: true);
  });

  test('health é local; quote/list preservam filtros e usam token só no header',
      () async {
    expect((await request('/health')).status, 200);
    expect(received, isEmpty);
    expect(
        (await request(
                '/api/quote/PETR4?range=3mo&token=hostile&url=http://evil.example'))
            .status,
        200);
    expect(received.single.query, {'range': '3mo'});
    expect(received.single.auth, 'Bearer $fixtureToken');
    await request(
        '/api/quote/list?search=PETR&limit=5&page=2&sortBy=name&sortOrder=asc');
    expect(received.last.path, '/api/quote/list');
    expect(received.last.query, {
      'search': 'PETR',
      'limit': '5',
      'page': '2',
      'sortBy': 'name',
      'sortOrder': 'asc'
    });
  });

  test('extras encaminham somente parâmetros da rota allowlisted', () async {
    await request(
        '/api/v2/stocks/dividends?symbols=PETR4,VALE3&sortBy=paymentDate&sortOrder=desc&range=1mo&token=hostile');
    expect(received.last.query, {
      'symbols': 'PETR4,VALE3',
      'sortBy': 'paymentDate',
      'sortOrder': 'desc'
    });
    await request('/api/v2/currency?currency=USD-BRL,EUR-BRL&symbols=PETR4');
    expect(received.last.query, {'currency': 'USD-BRL,EUR-BRL'});
    await request(
        '/api/v2/macro/latest?symbols=ipca,ipca12m,igpm&currency=USD-BRL');
    expect(received.last.query, {'symbols': 'ipca,ipca12m,igpm'});
    expect(received.every((r) => r.auth == 'Bearer $fixtureToken'), isTrue);
  });

  test('limites e padrões recusam parâmetros malformados antes do upstream',
      () async {
    final bad = [
      '/api/v2/stocks/dividends',
      '/api/v2/stocks/dividends?symbols=PETR4%2F..',
      '/api/v2/stocks/dividends?symbols=PETR4&sortOrder=sideways',
      '/api/v2/stocks/dividends?symbols=PETR4&sortBy=untrusted',
      '/api/v2/stocks/dividends?symbols=PETR4&symbols=VALE3',
      '/api/v2/currency?currency=USD-BRL%26token%3Dhostile',
      '/api/v2/currency?currency=USD',
      '/api/v2/macro/latest?symbols=IPCA',
      '/api/v2/macro/latest?symbols=${List.filled(21, 'ipca').join(',')}',
      '/api/v2/macro/latest?symbols=${'a' * 201}',
    ];
    for (final path in bad) {
      expect((await request(path)).status, 400, reason: path);
    }
    expect(received, isEmpty);
  });

  test('CORS, preflight e métodos mantêm 403, 204, 405 e 404', () async {
    final allowed =
        await request('/api/quote/PETR4', origin: 'http://localhost:12345');
    expect(allowed.status, 200);
    expect(allowed.cors, 'http://localhost:12345');
    expect(
        (await request('/api/v2/currency?currency=USD-BRL',
                method: 'OPTIONS', origin: 'http://localhost:12345'))
            .status,
        204);
    expect(
        (await request('/api/quote/PETR4', origin: 'https://evil.example'))
            .status,
        403);
    expect(
        (await request('/api/quote/PETR4', origin: 'http://evil@localhost'))
            .status,
        403);
    expect((await request('/api/quote/PETR4', method: 'POST')).status, 405);
    expect((await request('/api/qualquer')).status, 404);
    expect((await request('/api/v2/macro/anything?symbols=ipca')).status, 404);
    expect(received, hasLength(1));
  });

  test('origens configuradas permitem só correspondência exata', () async {
    await proxy.close();
    proxy = await startBrapiProxy(
        token: fixtureToken,
        port: 0,
        allowedOrigins: {'https://app.example'},
        upstreamBase: Uri.parse('http://127.0.0.1:${upstream.port}/'));
    expect((await request('/health', origin: 'http://localhost:8080')).status,
        403);
    expect((await request('/health', origin: 'https://app.example')).cors,
        'https://app.example');
  });

  test('limite local retorna 429 e Retry-After sem consultar upstream',
      () async {
    await proxy.close();
    proxy = await startBrapiProxy(
        token: fixtureToken,
        port: 0,
        rateLimit: 1,
        upstreamBase: Uri.parse('http://127.0.0.1:${upstream.port}/'));
    expect((await request('/health')).status, 200);
    expect((await request('/api/quote/PETR4')).status, 200);
    final limited = await request('/api/v2/currency?currency=USD-BRL');
    expect(limited.status, 429);
    expect(limited.retry, '60');
    expect(received, hasLength(1));
  });

  test(
      'upstream 429 preserva Retry-After mas remove corpo potencialmente secreto',
      () async {
    upstreamStatus = 429;
    final result = await request('/api/quote/PETR4');
    expect(result.status, 429);
    expect(result.retry, '17');
    expect(result.body, isNot(contains(fixtureToken)));
  });

  test('redirect nunca é seguido nem encaminha Location ou erro secreto',
      () async {
    upstreamStatus = 302;
    final result = await request('/api/v2/macro/latest?symbols=ipca');
    expect(result.status, 502);
    expect(result.location, isNull);
    expect(result.body, isNot(contains(fixtureToken)));
    expect(received, hasLength(1));
    expect(received.single.path, '/api/v2/macro/latest');
    upstreamStatus = 500;
    expect((await request('/api/quote/PETR4')).body,
        isNot(contains(fixtureToken)));
  });

  test('injeção programática rejeita upstream externo e segredo em query',
      () async {
    await expectLater(
        startBrapiProxy(
            token: fixtureToken,
            port: 0,
            upstreamBase: Uri.parse('https://evil.example/')),
        throwsArgumentError);
    await expectLater(
        startBrapiProxy(
            token: fixtureToken,
            port: 0,
            upstreamBase: Uri.parse('http://127.0.0.1/?token=hostile')),
        throwsArgumentError);
  });
}
