// Proxy local da brapi para o Bolsa Fácil.
//
// Responsabilidades (e só estas):
//  1. injetar o BRAPI_TOKEN (que nunca chega ao navegador);
//  2. resolver CORS para o Flutter Web;
//  3. proteger a cota: aceita apenas GET /api/quote/{ticker}, repassa só
//     parâmetros conhecidos e limita requisições por IP.
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
    final token = (env['BRAPI_TOKEN'] ?? _readEnvFile('BRAPI_TOKEN') ?? '').trim();
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
    if (current == null || now.difference(current.start) >= const Duration(minutes: 1)) {
      _windows[key] = (start: now, count: 1);
      if (_windows.length > 5000) {
        _windows.removeWhere((_, w) => now.difference(w.start) >= const Duration(minutes: 1));
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
      (uri.host == 'localhost' || uri.host == '127.0.0.1');
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
      _tickerPattern.hasMatch(segments[2]);
  if (!isQuote) {
    return _json(response, 404, {'error': 'Rota não encontrada. Use GET /api/quote/{ticker}.'});
  }

  final client = request.connectionInfo?.remoteAddress.address ?? 'desconhecido';
  if (!limiter.allow(client)) {
    response.headers.set('Retry-After', '60');
    return _json(response, 429, {'error': 'Muitas requisições. Tente novamente em instantes.'});
  }

  final query = <String, String>{
    for (final entry in request.uri.queryParameters.entries)
      if (_allowedQueryParams.contains(entry.key) && entry.value.length <= 200)
        entry.key: entry.value,
  };
  final target = Uri.https(
    'brapi.dev',
    '/api/quote/${segments[2]}',
    query.isEmpty ? null : query,
  );

  try {
    final outgoing = await upstream.getUrl(target).timeout(const Duration(seconds: 15));
    outgoing.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.token}')
      ..set(HttpHeaders.acceptHeader, 'application/json');
    final incoming = await outgoing.close().timeout(const Duration(seconds: 15));
    response.statusCode = incoming.statusCode;
    response.headers.contentType = ContentType.json;
    final retryAfter = incoming.headers.value('retry-after');
    if (retryAfter != null) response.headers.set('Retry-After', retryAfter);
    await incoming.pipe(response);
  } on TimeoutException {
    await _json(response, 504, {'error': 'A brapi demorou demais para responder.'});
  } catch (_) {
    await _json(response, 502, {'error': 'Falha ao consultar a brapi.'});
  }
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

  final upstream = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final limiter = _RateLimiter(config.rateLimit);
  final server = await HttpServer.bind(config.host, config.port);
  stdout.writeln(
    'Proxy da brapi ativo em http://${config.host}:${config.port} '
    '(somente GET /api/quote/{ticker})',
  );

  await for (final request in server) {
    unawaited(_handle(request, config, upstream, limiter).catchError((Object _) {
      _json(request.response, 500, {'error': 'Erro interno.'});
    }));
  }
}
