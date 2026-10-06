/// Tipos de operação registrados na carteira.
///
/// - [buy]: compra (soma à posição e recalcula o preço médio).
/// - [sell]: venda (reduz a posição e realiza lucro/prejuízo).
/// - [adjust]: ajuste manual; define quantidade e preço médio absolutos.
enum TradeType { buy, sell, adjust }

extension TradeTypeLabel on TradeType {
  String get label => switch (this) {
        TradeType.buy => 'Compra',
        TradeType.sell => 'Venda',
        TradeType.adjust => 'Ajuste',
      };
}

/// Erro de regra de negócio da carteira (ex.: vender mais do que se possui).
class TradeException implements Exception {
  const TradeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Uma operação (compra, venda ou ajuste) de um ativo.
class Trade {
  const Trade({
    this.id,
    required this.symbol,
    required this.type,
    required this.quantity,
    required this.price,
    this.fees = 0,
    required this.executedAt,
  });

  final int? id;
  final String symbol;
  final TradeType type;
  final double quantity;
  final double price;
  final double fees;
  final DateTime executedAt;

  Map<String, Object?> toMap(int userId) => {
        'user_id': userId,
        'symbol': symbol,
        'type': type.name,
        'quantity': quantity,
        'price': price,
        'fees': fees,
        'executed_at': executedAt.toUtc().toIso8601String(),
      };

  factory Trade.fromMap(Map<String, Object?> map) => Trade(
        id: map['id'] as int?,
        symbol: map['symbol'] as String,
        type: TradeType.values.byName(map['type'] as String),
        quantity: (map['quantity'] as num).toDouble(),
        price: (map['price'] as num).toDouble(),
        fees: ((map['fees'] as num?) ?? 0).toDouble(),
        executedAt: DateTime.parse(map['executed_at'] as String),
      );

  Map<String, Object?> toJson() => {
        'symbol': symbol,
        'type': type.name,
        'quantity': quantity,
        'price': price,
        'fees': fees,
        'executedAt': executedAt.toUtc().toIso8601String(),
      };

  /// Lê e valida uma operação vinda de um backup. Lança [FormatException]
  /// (ou [TypeError]) quando algum campo é inválido.
  factory Trade.fromJson(Map<String, dynamic> json) {
    final symbol = (json['symbol'] as String).trim().toUpperCase();
    final quantity = (json['quantity'] as num).toDouble();
    final price = (json['price'] as num).toDouble();
    final fees = ((json['fees'] as num?) ?? 0).toDouble();
    if (symbol.isEmpty) throw const FormatException('símbolo vazio');
    if (!quantity.isFinite || quantity <= 0) {
      throw const FormatException('quantidade inválida');
    }
    if (!price.isFinite || price < 0) {
      throw const FormatException('preço inválido');
    }
    if (!fees.isFinite || fees < 0) {
      throw const FormatException('taxas inválidas');
    }
    return Trade(
      symbol: symbol,
      type: TradeType.values.byName(json['type'] as String),
      quantity: quantity,
      price: price,
      fees: fees,
      executedAt: DateTime.parse(json['executedAt'] as String),
    );
  }
}

/// Resultado consolidado de uma sequência de operações de um mesmo ativo.
class PositionSummary {
  const PositionSummary({
    required this.quantity,
    required this.averagePrice,
    required this.realizedProfit,
  });

  final double quantity;
  final double averagePrice;
  final double realizedProfit;
}

const _epsilon = 1e-9;

/// Consolida [trades] (em ordem cronológica) em quantidade, preço médio e
/// lucro realizado.
///
/// Regras:
/// - compra: `PM = (qtd·PM + qtdCompra·preço + taxas) / (qtd + qtdCompra)`
///   (as taxas entram no custo);
/// - venda: `realizado += (preço − PM)·qtd − taxas`; o PM não muda, e se a
///   posição zera o PM volta a 0;
/// - ajuste: substitui quantidade e PM, sem alterar o realizado.
///
/// Lança [TradeException] se uma venda exceder a posição disponível.
PositionSummary summarizeTrades(Iterable<Trade> trades) {
  var quantity = 0.0;
  var average = 0.0;
  var realized = 0.0;
  for (final trade in trades) {
    switch (trade.type) {
      case TradeType.buy:
        final total = quantity + trade.quantity;
        if (total <= 0) continue;
        average =
            (quantity * average + trade.quantity * trade.price + trade.fees) /
                total;
        quantity = total;
      case TradeType.sell:
        if (trade.quantity > quantity + _epsilon) {
          throw const TradeException(
            'A quantidade vendida é maior do que a posição disponível.',
          );
        }
        realized += (trade.price - average) * trade.quantity - trade.fees;
        quantity -= trade.quantity;
        if (quantity <= _epsilon) {
          quantity = 0;
          average = 0;
        }
      case TradeType.adjust:
        quantity = trade.quantity;
        average = trade.price;
    }
  }
  return PositionSummary(
    quantity: quantity,
    averagePrice: average,
    realizedProfit: realized,
  );
}
