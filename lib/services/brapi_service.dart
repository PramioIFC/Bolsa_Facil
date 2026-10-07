import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/stock.dart';
import '../models/market_data.dart';

/// Motivo pelo qual uma cotação não pôde ser obtida.
enum QuoteFailure { notFound, rateLimited, unauthorized, network, other }

/// Mensagem amigável para cada tipo de falha.
String brapiMessageFor(QuoteFailure failure) => switch (failure) {
      QuoteFailure.notFound => 'Ação não encontrada.',
      QuoteFailure.rateLimited =>
        'Limite de requisições da brapi atingido. Tente novamente em instantes.',
      QuoteFailure.unauthorized =>
        'A brapi negou o acesso: token inválido ou plano sem acesso a este dado.',
      QuoteFailure.network => kIsWeb
          ? 'O proxy da brapi não está acessível. Execute .\\run_web.ps1 '
              'ou "dart run tool/brapi_proxy.dart".'
          : 'Sem conexão com a brapi. Verifique sua internet.',
      QuoteFailure.other =>
        'A brapi retornou um erro inesperado. Tente novamente.',
    };

class BrapiException implements Exception {
  const BrapiException(this.message, {this.failure});
  final String message;
  final QuoteFailure? failure;

  @override
  String toString() => message;
}

/// Resultado de uma consulta individual: ou há [stock], ou há [failure].
class QuoteFetchResult {
  const QuoteFetchResult._(this.stock, this.failure);
  factory QuoteFetchResult.ok(Stock stock) => QuoteFetchResult._(stock, null);
  factory QuoteFetchResult.fail(QuoteFailure failure) =>
      QuoteFetchResult._(null, failure);

  final Stock? stock;
  final QuoteFailure? failure;
}

/// Resultado de uma consulta em lote, por ticker.
class QuotesBatch {
  const QuotesBatch({required this.stocks, required this.failures});

  final Map<String, Stock> stocks;
  final Map<String, QuoteFailure> failures;

  bool get rateLimited => failures.values.contains(QuoteFailure.rateLimited);
  bool get unauthorized => failures.values.contains(QuoteFailure.unauthorized);
}

class BrapiService {
  BrapiService({
    http.Client? client,
    String? baseUrl,
    String? token,
    Future<void> Function(Duration)? delay,
    this.maxRetries = 2,
  })  : _client = client ?? http.Client(),
        _baseUrlOverride = baseUrl,
        _tokenOverride = token,
        _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final http.Client _client;
  final String? _baseUrlOverride;
  final String? _tokenOverride;
  final Future<void> Function(Duration) _delay;

  /// Quantas vezes repetir uma requisição que recebeu HTTP 429.
  final int maxRetries;

  static const _configuredBaseUrl = String.fromEnvironment('BRAPI_BASE_URL');
  static const _nativeToken = String.fromEnvironment('BRAPI_TOKEN');
  static const _timeout = Duration(seconds: 15);

  /// A URL base deve incluir o sufixo `/api`.
  String get _baseUrl {
    if (_baseUrlOverride != null) return _baseUrlOverride;
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return kIsWeb ? 'http://localhost:8080/api' : 'https://brapi.dev/api';
  }

  /// Na Web o token nunca vai ao navegador: quem o injeta é o proxy.
  String get _token => _tokenOverride ?? (kIsWeb ? '' : _nativeToken.trim());

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  // ---------------------------------------------------------------------------
  // Cotações
  // ---------------------------------------------------------------------------

  /// Consulta vários tickers com no máximo [concurrency] requisições
  /// simultâneas (o plano gratuito aceita 1 ticker por requisição).
  ///
  /// Se a brapi responder 429 de forma persistente (ou 401/403), as consultas
  /// restantes são abortadas e marcadas com essa mesma falha, para não insistir.
  Future<QuotesBatch> fetchQuotes(
    List<String> symbols, {
    int concurrency = 3,
  }) async {
    final queue = <String>[];
    for (final symbol in symbols) {
      final normalized = symbol.trim().toUpperCase();
      if (normalized.isNotEmpty && !queue.contains(normalized)) {
        queue.add(normalized);
      }
    }

    final stocks = <String, Stock>{};
    final failures = <String, QuoteFailure>{};
    QuoteFailure? abortWith;
    var next = 0;

    Future<void> worker() async {
      while (next < queue.length) {
        final symbol = queue[next++];
        if (abortWith != null) {
          failures[symbol] = abortWith!;
          continue;
        }
        final result = await fetchQuote(symbol);
        final stock = result.stock;
        if (stock != null) {
          stocks[symbol] = stock;
        } else {
          final failure = result.failure!;
          failures[symbol] = failure;
          if (failure == QuoteFailure.rateLimited ||
              failure == QuoteFailure.unauthorized) {
            abortWith = failure;
          }
        }
      }
    }

    final workers = concurrency < 1 ? 1 : concurrency;
    final count = workers < queue.length ? workers : queue.length;
    await Future.wait([for (var i = 0; i < count; i++) worker()]);
    return QuotesBatch(stocks: stocks, failures: failures);
  }

  /// Cotação detalhada para a tela de detalhes. Como alguns tickers não têm
  /// fundamentos ou histórico no plano da brapi (a resposta pode ser 401/402/403),
  /// tenta em ordem, do mais completo ao mais simples:
  ///  1. histórico + fundamentos;
  ///  2. só histórico;
  ///  3. só a cotação básica (a tela mostra "histórico indisponível").
  /// Para antes se a falha for de rede ou de limite de requisições (429).
  Future<Stock> getQuote(String symbol, {String range = '3mo'}) async {
    final attempts = <Future<QuoteFetchResult> Function()>[
      () => fetchQuote(symbol, range: range, fundamentals: true),
      () => fetchQuote(symbol, range: range),
      () => fetchQuote(symbol),
    ];
    QuoteFailure? last;
    for (final attempt in attempts) {
      final result = await attempt();
      final stock = result.stock;
      if (stock != null) return stock;
      last = result.failure!;
      final retryable = last == QuoteFailure.notFound ||
          last == QuoteFailure.other ||
          last == QuoteFailure.unauthorized;
      if (!retryable) break;
    }
    throw BrapiException(brapiMessageFor(last!), failure: last);
  }

  /// Uma consulta a `GET /quote/{ticker}`, com repetição em caso de HTTP 429.
  Future<QuoteFetchResult> fetchQuote(
    String symbol, {
    String? range,
    bool fundamentals = false,
  }) async {
    final normalized = symbol.trim().toUpperCase();
    final query = <String, String>{
      if (range != null) 'range': range,
      if (range != null) 'interval': '1d',
      if (fundamentals) 'modules': 'defaultKeyStatistics,financialData',
      if (fundamentals) 'fundamental': 'true',
      if (fundamentals) 'dividends': 'true',
    };
    final uri = Uri.parse('$_baseUrl/quote/${Uri.encodeComponent(normalized)}')
        .replace(queryParameters: query.isEmpty ? null : query);

    for (var attempt = 0;; attempt++) {
      http.Response response;
      try {
        response = await _client.get(uri, headers: _headers).timeout(_timeout);
      } on Exception {
        return QuoteFetchResult.fail(QuoteFailure.network);
      }

      final status = response.statusCode;
      if (status == 429) {
        if (attempt >= maxRetries) {
          return QuoteFetchResult.fail(QuoteFailure.rateLimited);
        }
        await _delay(_retryDelay(response, attempt));
        continue;
      }
      if (status == 404) return QuoteFetchResult.fail(QuoteFailure.notFound);
      if (status == 401 || status == 403) {
        return QuoteFetchResult.fail(QuoteFailure.unauthorized);
      }
      if (status != 200) return QuoteFetchResult.fail(QuoteFailure.other);

      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final stocks = (data['results'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(Stock.fromJson)
            .toList();
        return stocks.isEmpty
            ? QuoteFetchResult.fail(QuoteFailure.notFound)
            : QuoteFetchResult.ok(stocks.first);
      } catch (_) {
        return QuoteFetchResult.fail(QuoteFailure.other);
      }
    }
  }

  /// Respeita `Retry-After` (em segundos) quando presente; senão usa backoff
  /// exponencial (500 ms, 1 s, 2 s…). Limitado a 5 s.
  Duration _retryDelay(http.Response response, int attempt) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    final millis = seconds != null ? seconds * 1000 : 500 * (1 << attempt);
    return Duration(milliseconds: millis.clamp(0, 5000).toInt());
  }

  /// Proventos em dinheiro da API v2; não altera a cotação nem o cache local.
  Future<List<CashDividend>> getDividends(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9^.\-]{1,32}$').hasMatch(normalized)) {
      throw const BrapiException('Informe um código de ação válido.');
    }
    final data = await _getMarketData('/v2/stocks/dividends', {
      'symbols': normalized,
      'sortBy': 'paymentDate',
      'sortOrder': 'desc',
    });
    try {
      final results = data['results'] as List;
      if (results.isEmpty) return const [];
      if (results.length != 1) throw const FormatException();
      final result = results.single as Map<String, dynamic>;
      final actual = result['symbol'];
      if (result['requestedSymbol'] != normalized ||
          actual is! String ||
          !RegExp(r'^[A-Z0-9^.\-]{1,32}$').hasMatch(actual) ||
          (actual != normalized && result['changed'] != true)) {
        throw const FormatException();
      }
      final payload = result['data'] as Map<String, dynamic>;
      return (payload['cashDividends'] as List)
          .map((item) =>
              CashDividend.fromJson(actual, item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw _invalidMarketData();
    }
  }

  Future<List<CurrencyQuote>> getCurrencies({
    List<String> pairs = const ['USD-BRL', 'EUR-BRL'],
  }) async {
    final requested = pairs.map((pair) => pair.trim().toUpperCase()).toSet();
    if (requested.isEmpty) return const [];
    if (requested
        .any((pair) => !RegExp(r'^[A-Z]{3}-[A-Z]{3}$').hasMatch(pair))) {
      throw const BrapiException('Informe um par de moedas válido.');
    }
    final data =
        await _getMarketData('/v2/currency', {'currency': requested.join(',')});
    try {
      final seen = <String>{};
      return (data['currency'] as List).map((item) {
        final quote = CurrencyQuote.fromJson(item as Map<String, dynamic>);
        final pair = '${quote.fromCurrency}-${quote.toCurrency}';
        if (!requested.contains(pair) ||
            !seen.add(pair) ||
            quote.bidPrice <= 0 ||
            quote.askPrice <= 0) {
          throw const FormatException();
        }
        return quote;
      }).toList();
    } catch (_) {
      throw _invalidMarketData();
    }
  }

  Future<List<InflationIndicator>> getInflation() async {
    const slugs = ['ipca', 'ipca12m', 'igpm'];
    final data =
        await _getMarketData('/v2/macro/latest', {'symbols': slugs.join(',')});
    try {
      final seen = <String>{};
      return (data['results'] as List).map((item) {
        final indicator =
            InflationIndicator.fromJson(item as Map<String, dynamic>);
        if (!slugs.contains(indicator.slug) || !seen.add(indicator.slug)) {
          throw const FormatException();
        }
        return indicator;
      }).toList();
    } catch (_) {
      throw _invalidMarketData();
    }
  }

  BrapiException _invalidMarketData() => const BrapiException(
      'A brapi retornou dados financeiros inválidos. Tente novamente.',
      failure: QuoteFailure.other);

  Future<Map<String, dynamic>> _getMarketData(
      String path, Map<String, String> query) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    for (var attempt = 0;; attempt++) {
      http.Response response;
      try {
        response = await _client.get(uri, headers: _headers).timeout(_timeout);
      } on Exception {
        throw BrapiException(brapiMessageFor(QuoteFailure.network),
            failure: QuoteFailure.network);
      }
      if (response.statusCode == 429 && attempt < maxRetries) {
        await _delay(_retryDelay(response, attempt));
        continue;
      }
      final failure = switch (response.statusCode) {
        200 => null,
        401 || 402 || 403 => QuoteFailure.unauthorized,
        404 => QuoteFailure.notFound,
        429 => QuoteFailure.rateLimited,
        _ => QuoteFailure.other,
      };
      if (failure != null) {
        throw BrapiException(
            failure == QuoteFailure.notFound
                ? 'Dados financeiros não encontrados.'
                : brapiMessageFor(failure),
            failure: failure);
      }
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw _invalidMarketData();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Busca de tickers (autocomplete)
  // ---------------------------------------------------------------------------

  /// Busca tickers por `GET /quote/list?search=`. Nunca lança: em qualquer
  /// falha devolve lista vazia (o autocomplete é apenas uma conveniência).
  Future<List<TickerSuggestion>> searchTickers(String query,
      {int limit = 8}) async {
    final term = query.trim();
    if (term.length < 2) return const [];
    final uri = Uri.parse('$_baseUrl/quote/list').replace(queryParameters: {
      'search': term,
      'limit': '$limit',
    });
    try {
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final seen = <String>{};
      final suggestions = <TickerSuggestion>[];
      for (final item in (data['stocks'] as List<dynamic>? ?? [])) {
        if (item is! Map<String, dynamic>) continue;
        final symbol = (item['stock'] ?? item['symbol'])
                ?.toString()
                .trim()
                .toUpperCase() ??
            '';
        if (symbol.isEmpty || !seen.add(symbol)) continue;
        suggestions.add(TickerSuggestion(
          symbol: symbol,
          name: item['name']?.toString() ?? '',
          logoUrl: item['logo']?.toString(),
        ));
      }
      return suggestions;
    } catch (_) {
      return const [];
    }
  }
}
