import '../database/app_database.dart';
import '../models/stock.dart';
import 'brapi_service.dart';

/// Resultado de uma atualização de cotações para a UI.
class QuoteUpdate {
  const QuoteUpdate({
    required this.stocks,
    this.failed = const {},
    this.rateLimited = false,
    this.hasStale = false,
    this.updatedAt,
  });

  /// Cotações na mesma ordem dos símbolos pedidos (as sem dado ficam de fora).
  final List<Stock> stocks;

  /// Símbolos que não puderam ser atualizados nesta consulta.
  final Set<String> failed;
  final bool rateLimited;

  /// `true` se algum item exibido veio do cache vencido por falha na rede/API.
  final bool hasStale;

  /// Instante da cotação mais antiga entre as exibidas.
  final DateTime? updatedAt;
}

/// Camada entre o estado e a brapi: aplica cache em SQLite com TTL e usa dado
/// antigo como alternativa quando a consulta falha.
class QuoteRepository {
  QuoteRepository(
    this._brapi,
    this._db, {
    Duration ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _ttl = ttl,
        _clock = clock ?? DateTime.now;

  final BrapiService _brapi;
  final AppDatabase _db;
  final Duration _ttl;
  final DateTime Function() _clock;

  Future<QuoteUpdate> getQuotes(
    List<String> symbols, {
    bool forceRefresh = false,
  }) async {
    final requested = <String>[];
    for (final symbol in symbols) {
      final normalized = symbol.trim().toUpperCase();
      if (normalized.isNotEmpty && !requested.contains(normalized)) {
        requested.add(normalized);
      }
    }
    if (requested.isEmpty) return const QuoteUpdate(stocks: []);

    Map<String, CachedQuote> cached;
    try {
      cached = await _db.getCachedQuotes(requested);
    } catch (_) {
      cached = {};
    }

    final now = _clock();
    final results = <String, Stock>{};
    final fetchedAt = <String, DateTime>{};
    final toFetch = <String>[];
    for (final symbol in requested) {
      final entry = cached[symbol];
      if (entry != null && !forceRefresh && now.difference(entry.fetchedAt) < _ttl) {
        results[symbol] = entry.stock;
        fetchedAt[symbol] = entry.fetchedAt;
      } else {
        toFetch.add(symbol);
      }
    }

    final failed = <String>{};
    var rateLimited = false;
    var hasStale = false;
    QuoteFailure? worstFailure;

    if (toFetch.isNotEmpty) {
      final batch = await _brapi.fetchQuotes(toFetch);
      rateLimited = batch.rateLimited;
      for (final symbol in toFetch) {
        final fresh = batch.stocks[symbol];
        if (fresh != null) {
          results[symbol] = fresh;
          fetchedAt[symbol] = now;
          continue;
        }
        failed.add(symbol);
        final failure = batch.failures[symbol];
        if (failure != null) worstFailure = _worse(worstFailure, failure);
        final entry = cached[symbol];
        if (entry != null) {
          results[symbol] = entry.stock;
          fetchedAt[symbol] = entry.fetchedAt;
          hasStale = true;
        }
      }
      try {
        await _db.putCachedQuotes(batch.stocks, now);
      } catch (_) {
        // O cache é só otimização; falha ao gravar não deve quebrar a tela.
      }
    }

    final stocks = [
      for (final symbol in requested)
        if (results[symbol] != null) results[symbol]!,
    ];
    if (stocks.isEmpty) {
      final reason = worstFailure ?? QuoteFailure.other;
      throw BrapiException(brapiMessageFor(reason), failure: reason);
    }

    DateTime? oldest;
    for (final time in fetchedAt.values) {
      if (oldest == null || time.isBefore(oldest)) oldest = time;
    }
    return QuoteUpdate(
      stocks: stocks,
      failed: failed,
      rateLimited: rateLimited,
      hasStale: hasStale,
      updatedAt: oldest,
    );
  }

  /// Escolhe a falha mais informativa para exibir quando nada foi carregado.
  QuoteFailure _worse(QuoteFailure? current, QuoteFailure next) {
    const priority = [
      QuoteFailure.rateLimited,
      QuoteFailure.unauthorized,
      QuoteFailure.network,
      QuoteFailure.other,
      QuoteFailure.notFound,
    ];
    if (current == null) return next;
    return priority.indexOf(next) < priority.indexOf(current) ? next : current;
  }
}
