class Stock {
  const Stock({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePercent,
    this.logoUrl,
    this.currency = 'BRL',
    this.marketCap,
    this.dividendYield,
    this.trailingPE,
    this.priceToBook,
    this.profitMargins,
    this.totalDebt,
    this.totalCash,
    this.history = const [],
  });

  final String symbol;
  final String name;
  final double price;
  final double changePercent;
  final String? logoUrl;
  final String currency;
  final double? marketCap;

  // Fundamentals & Dividends
  final double? dividendYield;
  final double? trailingPE;
  final double? priceToBook;
  final double? profitMargins;
  final double? totalDebt;
  final double? totalCash;

  final List<PricePoint> history;

  /// Campos básicos persistidos no cache (sem histórico nem fundamentos).
  Map<String, Object?> toCacheMap() => {
        'symbol': symbol,
        'name': name,
        'price': price,
        'changePercent': changePercent,
        'logoUrl': logoUrl,
        'currency': currency,
        'marketCap': marketCap,
      };

  factory Stock.fromCacheMap(Map<String, dynamic> map) => Stock(
        symbol: map['symbol']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        changePercent: (map['changePercent'] as num?)?.toDouble() ?? 0,
        logoUrl: map['logoUrl']?.toString(),
        currency: map['currency']?.toString() ?? 'BRL',
        marketCap: (map['marketCap'] as num?)?.toDouble(),
      );

  factory Stock.fromJson(Map<String, dynamic> json) {
    final historical = (json['historicalDataPrice'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PricePoint.fromJson)
        .where((point) => point.close > 0)
        .toList();

    final stats = json['defaultKeyStatistics'] as Map<String, dynamic>?;
    final financial = json['financialData'] as Map<String, dynamic>?;

    return Stock(
      symbol: json['symbol']?.toString() ?? '',
      name: json['longName']?.toString() ?? json['shortName']?.toString() ?? '',
      price: (json['regularMarketPrice'] as num?)?.toDouble() ?? 0,
      changePercent:
          (json['regularMarketChangePercent'] as num?)?.toDouble() ?? 0,
      logoUrl: json['logourl']?.toString(),
      currency: json['currency']?.toString() ?? 'BRL',
      marketCap: (json['marketCap'] as num?)?.toDouble(),
      dividendYield: (stats?['dividendYield'] as num?)?.toDouble(),
      trailingPE: (stats?['trailingPE'] as num?)?.toDouble(),
      priceToBook: (stats?['priceToBook'] as num?)?.toDouble(),
      profitMargins: (stats?['profitMargins'] as num?)?.toDouble() ?? (financial?['profitMargins'] as num?)?.toDouble(),
      totalDebt: (financial?['totalDebt'] as num?)?.toDouble(),
      totalCash: (financial?['totalCash'] as num?)?.toDouble(),
      history: historical,
    );
  }
}


/// Sugestão de ticker retornada pela busca (autocomplete).
class TickerSuggestion {
  const TickerSuggestion({required this.symbol, required this.name, this.logoUrl});

  final String symbol;
  final String name;
  final String? logoUrl;
}

/// Cotação básica guardada no cache local (SQLite) com o instante da consulta.
class CachedQuote {
  const CachedQuote({required this.stock, required this.fetchedAt});

  final Stock stock;
  final DateTime fetchedAt;
}

class PricePoint {
  const PricePoint({required this.date, required this.close});

  final DateTime date;
  final double close;

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
        date: DateTime.fromMillisecondsSinceEpoch(
          ((json['date'] as num?)?.toInt() ?? 0) * 1000,
        ),
        close: (json['close'] as num?)?.toDouble() ?? 0,
      );
}
