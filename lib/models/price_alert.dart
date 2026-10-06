enum AlertDirection { above, below }

class PriceAlertException implements Exception {
  const PriceAlertException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Um alerta de execução única; editar reativa um alerta já acionado.
class PriceAlert {
  const PriceAlert(
      {this.id,
      required this.symbol,
      required this.direction,
      required this.target,
      required this.createdAt,
      this.triggeredAt});
  final int? id;
  final String symbol;
  final AlertDirection direction;
  final double target;
  final DateTime createdAt;
  final DateTime? triggeredAt;
  bool get isTriggered => triggeredAt != null;
  bool matches(double price) =>
      !isTriggered &&
      price.isFinite &&
      price > 0 &&
      (direction == AlertDirection.above ? price >= target : price <= target);

  void validate() {
    if (symbol.trim().isEmpty) {
      throw const PriceAlertException('Informe o código da ação.');
    }
    if (!target.isFinite || target <= 0) {
      throw const PriceAlertException('Informe um preço-alvo maior que zero.');
    }
  }

  PriceAlert copyWith(
          {int? id,
          String? symbol,
          AlertDirection? direction,
          double? target,
          DateTime? createdAt,
          DateTime? triggeredAt,
          bool rearm = false}) =>
      PriceAlert(
          id: id ?? this.id,
          symbol: symbol ?? this.symbol,
          direction: direction ?? this.direction,
          target: target ?? this.target,
          createdAt: createdAt ?? this.createdAt,
          triggeredAt: rearm ? null : triggeredAt ?? this.triggeredAt);

  Map<String, Object?> toMap(int userId) => {
        'user_id': userId,
        'symbol': symbol.trim().toUpperCase(),
        'direction': direction.name,
        'target': target,
        'created_at': createdAt.toUtc().toIso8601String(),
        'triggered_at': triggeredAt?.toUtc().toIso8601String()
      };
  factory PriceAlert.fromMap(Map<String, Object?> map) => PriceAlert(
      id: map['id'] as int?,
      symbol: map['symbol'] as String,
      direction: AlertDirection.values.byName(map['direction'] as String),
      target: (map['target'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      triggeredAt: map['triggered_at'] == null
          ? null
          : DateTime.parse(map['triggered_at'] as String).toUtc());
  Map<String, Object?> toJson() => {
        'symbol': symbol.trim().toUpperCase(),
        'direction': direction.name,
        'target': target,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'triggeredAt': triggeredAt?.toUtc().toIso8601String()
      };
  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    final alert = PriceAlert(
        symbol: (json['symbol'] as String).trim().toUpperCase(),
        direction: AlertDirection.values.byName(json['direction'] as String),
        target: (json['target'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        triggeredAt: json['triggeredAt'] == null
            ? null
            : DateTime.parse(json['triggeredAt'] as String).toUtc());
    alert.validate();
    return alert;
  }
}
