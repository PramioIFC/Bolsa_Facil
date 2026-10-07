// Proxy local da brapi para o Bolsa Fácil.
//
// Responsabilidades (e só estas):
//  1. injetar o BRAPI_TOKEN (que nunca chega ao navegador);
//  2. resolver CORS para o Flutter Web;
//  3. proteger a cota: aceita apenas GET /api/quote/{ticker}, repassa só
//     parâmetros conhecidos e limita requisições por IP. Também permite os
//     endpoints específicos de dividendos, câmbio e indicadores macro.
//
// Uso (na raiz do projeto):  dart run tool/brapi_proxy.dart
// Configuração (variáveis de ambiente ou argumentos):
//   BRAPI_TOKEN        token da brapi (ou linha BRAPI_TOKEN=... no arquivo .env)
//   PROXY_HOST/--host  interface de escuta (padrão 127.0.0.1)
//   PORT/--port        porta (padrão 8080)
//   ALLOWED_ORIGINS    origens permitidas, separadas por vírgula. Vazio = só
//                      http(s)://localhost e 127.0.0.1 (desenvolvimento).
//   RATE_LIMIT         requisições por minuto por IP (padrão 120)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _allowedQueryParams = {
  'range',
  'interval',
  'modules',
  'fundamental',
  'dividends',
  'search',
  'limit',
  'page',
  'sortBy',
  'sortOrder',
  'sector',
  'type',
};

final _tickerPattern = RegExp(r'^[A-Za-z0-9^.,\-]{1,64}$');

class _Config {
  _Config({
    required this.token,
    required this.host,
    required this.port,
    required this.allowedOrigins,
    required this.rateLimit,
  });

  final String token;
  final String host;
  final int port;
  final Set<String> allowedOrigins;
  final int rateLimit;

  static _Config load(List<String> args) {
    String? arg(String name) {
      for (final a in args) {
        if (a.startsWith('--$name=')) return a.substring(name.length + 3);
      }
      return null;
    }

    final env = Platform.environment;
    final token =
        (env['BRAPI_TOKEN'] ?? _readEnvFile('BRAPI_TOKEN') ?? '').trim();
    return _Config(
      token: token == 'seu_token_aqui' ? '' : token,
      host: arg('host') ?? env['PROXY_HOST'] ?? '127.0.0.1',
      port: int.tryParse(arg('port') ?? env['PORT'] ?? '') ?? 8080,
      allowedOrigins: (env['ALLOWED_ORIGINS'] ?? '')
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toSet(),
      rateLimit: int.tryParse(env['RATE_LIMIT'] ?? '') ?? 120,
    );
  }
}

String? _readEnvFile(String key) {
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final index = trimmed.indexOf('=');
    if (index <= 0 || trimmed.substring(0, index).trim() != key) continue;
    var value = trimmed.substring(index + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
  return null;
}

/// Janela fixa de 60 s por IP.
class _RateLimiter {
  _RateLimiter(this.limit);
  final int limit;
  final _windows = <String, ({DateTime start, int count})>{};

  bool allow(String key) {
    final now = DateTime.now();
    final current = _windows[key];
    if (current == null ||
        now.difference(current.start) >= const Duration(minutes: 1)) {
      _windows[key] = (start: now, count: 1);
      if (_windows.length > 5000) {
        _windows.removeWhere(
            (_, w) => now.difference(w.start) >= const Duration(minutes: 1));
      }
      return true;
    }
    if (current.count >= limit) return false;
    _windows[key] = (start: current.start, count: current.count + 1);
    return true;
  }
}

bool _originAllowed(String origin, Set<String> allowed) {
  if (allowed.isNotEmpty) return allowed.contains(origin);
  final uri = Uri.tryParse(origin);
  if (uri == null) return false;
  return (uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1') &&
      uri.userInfo.isEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

Future<void> _json(HttpResponse response, int status, Object body) async {
  try {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  } catch (_) {
    // Resposta já iniciada/fechada: nada a fazer.
  }
}

Future<void> _handle(
  HttpRequest request,
  _Config config,
  HttpClient upstream,
  _RateLimiter limiter,
  Uri upstreamBase,
) async {
  final response = request.response;

  final origin = request.headers.value('origin');
  if (origin != null) {
    if (!_originAllowed(origin, config.allowedOrigins)) {
      return _json(response, 403, {'error': 'Origem não permitida.'});
    }
    response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Vary', 'Origin');
  }

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }
  if (request.method != 'GET') {
    return _json(response, 405, {'error': 'Método não permitido.'});
  }

  final segments = request.uri.pathSegments;
  if (segments.length == 1 && segments.first == 'health') {
    return _json(response, 200, {'ok': true});
  }
  final isQuote = segments.length == 3 &&
      segments[0] == 'api' &&
      segments[1] == 'quote' &&
      _tickerPattern.hasMatch(segments[2]) &&
      segments[2]
          .split(',')
          .every((s) => s.isNotEmpty && s != '.' && s != '..');
  final path = request.uri.path;
  final allowed = switch (path) {
    '/api/v2/stocks/dividends' => const {'symbols', 'sortBy', 'sortOrder'},
    '/api/v2/currency' => const {'currency'},
    '/api/v2/macro/latest' => const {'symbols'},
    _ => isQuote ? _allowedQueryParams : null,
  };
  if (allowed == null) {
    return _json(response, 404, {'error': 'Rota não encontrada.'});
  }
  final query = <String, String>{
    for (final entry in request.uri.queryParameters.entries)
      if (allowed.contains(entry.key) && entry.value.length <= 200)
        entry.key: entry.value,
  };
  if (!isQuote && !_validExtrasQuery(path, request.uri, query)) {
    return _json(response, 400, {'error': 'Parâmetros inválidos.'});
  }

  final client =
      request.connectionInfo?.remoteAddress.address ?? 'desconhecido';
  if (!limiter.allow(client)) {
    response.headers.set('Retry-After', '60');
    return _json(response, 429,
        {'error': 'Muitas requisições. Tente novamente em instantes.'});
  }

  final target = upstreamBase.replace(
      path: path, queryParameters: query.isEmpty ? null : query);

  try {
    final outgoing =
        await upstream.getUrl(target).timeout(const Duration(seconds: 15));
    outgoing.followRedirects = false;
    outgoing.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.token}')
      ..set(HttpHeaders.acceptHeader, 'application/json');
    final incoming =
        await outgoing.close().timeout(const Duration(seconds: 15));
    final retryAfter = incoming.headers.value('retry-after');
    if (retryAfter != null && _validRetryAfter(retryAfter)) {
      response.headers.set('Retry-After', retryAfter);
    }
    if (incoming.statusCode >= 300) {
      final status = incoming.statusCode < 400 ? 502 : incoming.statusCode;
      await incoming.timeout(const Duration(seconds: 15)).drain<void>();
      return await _json(
          response, status, {'error': 'A brapi não pôde atender à consulta.'});
    }
    response.statusCode = incoming.statusCode;
    response.headers.contentType = ContentType.json;
    await incoming.timeout(const Duration(seconds: 15)).pipe(response);
  } on TimeoutException {
    await _json(
        response, 504, {'error': 'A brapi demorou demais para responder.'});
  } catch (_) {
    await _json(response, 502, {'error': 'Falha ao consultar a brapi.'});
  }
}

bool _validRetryAfter(String value) {
  if (RegExp(r'^\d{1,10}$').hasMatch(value)) return true;
  if (value.length > 64) return false;
  try {
    HttpDate.parse(value);
    return true;
  } catch (_) {
    return false;
  }
}

bool _validExtrasQuery(String path, Uri uri, Map<String, String> query) {
  // Valores conhecidos duplicados/longos são recusados em vez de truncados.
  final keys = path == '/api/v2/currency'
      ? const {'currency'}
      : path == '/api/v2/stocks/dividends'
          ? const {'symbols', 'sortBy', 'sortOrder'}
          : const {'symbols'};
  for (final key in keys) {
    final values = uri.queryParametersAll[key];
    if (values != null && (values.length != 1 || values.single.length > 200)) {
      return false;
    }
  }
  final value = query[path == '/api/v2/currency' ? 'currency' : 'symbols'];
  if (value == null || value.isEmpty) return false;
  final entries = value.split(',');
  if (entries.length > 20) return false;
  final pattern = path == '/api/v2/currency'
      ? RegExp(r'^[A-Za-z]{3}-[A-Za-z]{3}$')
      : path == '/api/v2/macro/latest'
          ? RegExp(r'^[a-z][a-z0-9-]{0,63}$')
          : RegExp(r'^[A-Za-z0-9^][A-Za-z0-9.^-]{0,31}$');
  if (!entries.every(pattern.hasMatch)) return false;
  if (query['sortOrder'] != null &&
      !const {'asc', 'desc'}.contains(query['sortOrder'])) {
    return false;
  }
  if (query['sortBy'] != null &&
      !const {'rate', 'paymentDate', 'approvedOn', 'lastDatePrior'}
          .contains(query['sortBy'])) {
    return false;
  }
  return true;
}

/// Servidor encerrável usado pelos testes HTTP reais e pelo entrypoint fixo.
class BrapiProxy {
  BrapiProxy._(this._server, this._upstream, this.done);
  final HttpServer _server;
  final HttpClient _upstream;
  final Future<void> done;
  int get port => _server.port;
  Future<void> close() async {
    await _server.close(force: true);
    _upstream.close(force: true);
  }
}

/// Injeção de upstream somente programática para testes locais. O CLI usa brapi.
Future<BrapiProxy> startBrapiProxy(
    {required String token,
    String host = '127.0.0.1',
    int port = 8080,
    Set<String> allowedOrigins = const {},
    int rateLimit = 120,
    Uri? upstreamBase}) async {
  if (token.isEmpty || token.contains('\r') || token.contains('\n')) {
    throw ArgumentError('Token inválido.');
  }
  if (rateLimit <= 0) throw ArgumentError('Limite inválido.');
  final base = upstreamBase ?? Uri.https('brapi.dev', '/');
  if (base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      !(base.scheme == 'https' && base.host == 'brapi.dev' ||
          base.scheme == 'http' &&
              (base.host == '127.0.0.1' ||
                  base.host == 'localhost' ||
                  base.host == '::1'))) {
    throw ArgumentError('Upstream inválido.');
  }
  final config = _Config(
      token: token,
      host: host,
      port: port,
      allowedOrigins: Set.of(allowedOrigins),
      rateLimit: rateLimit);
  final upstream = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final limiter = _RateLimiter(rateLimit);
  final server = await HttpServer.bind(host, port);
  final done = Completer<void>();
  server.listen((request) {
    unawaited(_handle(request, config, upstream, limiter, base)
        .catchError((Object _) async {
      await _json(request.response, 500, {'error': 'Erro interno.'});
    }));
  }, onDone: () {
    done.complete();
  });
  return BrapiProxy._(server, upstream, done.future);
}

Future<void> main(List<String> args) async {
  final config = _Config.load(args);
  if (config.token.isEmpty) {
    stderr.writeln(
      'BRAPI_TOKEN não foi preenchido. Defina a variável de ambiente ou '
      'crie o arquivo .env (veja .env.example).',
    );
    exitCode = 1;
    return;
  }

  final proxy = await startBrapiProxy(
      token: config.token,
      host: config.host,
      port: config.port,
      allowedOrigins: config.allowedOrigins,
      rateLimit: config.rateLimit);
  stdout.writeln(
      'Proxy da brapi ativo em http://${config.host}:${proxy.port} (somente rotas GET permitidas)');
  await proxy.done;
}
