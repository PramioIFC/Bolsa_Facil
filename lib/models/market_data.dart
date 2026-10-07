/// Provento em dinheiro por ação, separado de bonificações e subscrições.
class CashDividend {
  const CashDividend({
    required this.symbol,
    required this.label,
    required this.rate,
    this.paymentDate,
    this.dateCom,
    this.exDate,
  });

  final String symbol;
  final String label;
  final double rate;
  final DateTime? paymentDate;
  final DateTime? dateCom;
  final DateTime? exDate;

  factory CashDividend.fromJson(String symbol, Map<String, dynamic> json) =>
      CashDividend(
        symbol: symbol,
        label: _text(json['label']),
        rate: _number(json['rate']),
        paymentDate: _date(json['paymentDate']),
        dateCom: _date(json['lastDatePrior']),
        exDate: _date(json['exDate']),
      );
}

class CurrencyQuote {
  const CurrencyQuote({
    required this.fromCurrency,
    required this.toCurrency,
    required this.name,
    required this.bidPrice,
    required this.askPrice,
    required this.changePercent,
    this.updatedAt,
  });

  final String fromCurrency;
  final String toCurrency;
  final String name;
  final double bidPrice;
  final double askPrice;
  final double changePercent;
  final DateTime? updatedAt;

  factory CurrencyQuote.fromJson(Map<String, dynamic> json) {
    final timestamp = json['updatedAtTimestamp'];
    final seconds = timestamp == null ? null : _number(timestamp);
    if (seconds != null && (seconds < 0 || seconds > 8640000000000)) {
      throw const FormatException('Data de câmbio inválida.');
    }
    return CurrencyQuote(
      fromCurrency: _text(json['fromCurrency']),
      toCurrency: _text(json['toCurrency']),
      name: _text(json['name']),
      bidPrice: _number(json['bidPrice']),
      askPrice: _number(json['askPrice']),
      changePercent: _number(json['percentageChange']),
      updatedAt: seconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(),
              isUtc: true),
    );
  }
}

/// O valor e a data são ausentes quando a brapi retorna `latest: null`.
class InflationIndicator {
  const InflationIndicator({
    required this.slug,
    required this.name,
    required this.unit,
    required this.frequency,
    this.value,
    this.referenceDate,
  });

  final String slug;
  final String name;
  final String unit;
  final String frequency;
  final double? value;
  final DateTime? referenceDate;

  factory InflationIndicator.fromJson(Map<String, dynamic> json) {
    final series = json['series'];
    final latest = json['latest'];
    if (series is! Map<String, dynamic> ||
        !json.containsKey('latest') ||
        (latest != null && latest is! Map<String, dynamic>)) {
      throw const FormatException('Indicador de inflação inválido.');
    }
    return InflationIndicator(
      slug: _text(series['slug']),
      name: _text(series['name']),
      unit: _text(series['unit']),
      frequency: _text(series['frequency']),
      value: latest == null ? null : _number(latest['value']),
      referenceDate: latest == null ? null : _date(latest['date']),
    );
  }
}

String _text(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Texto obrigatório ausente.');
  }
  return value.trim();
}

double _number(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  if (parsed == null || !parsed.isFinite) {
    throw const FormatException('Número financeiro inválido.');
  }
  return parsed;
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  if (value is! String || DateTime.tryParse(value) == null) {
    throw const FormatException('Data financeira inválida.');
  }
  // Datas sem horário são períodos de referência, não timestamps da consulta.
  return DateTime.parse(value);
}
