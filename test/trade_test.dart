import 'package:bolsa_facil/models/trade.dart';
import 'package:flutter_test/flutter_test.dart';

Trade trade(TradeType type, double qty, double price, {double fees = 0}) => Trade(
      symbol: 'PETR4',
      type: type,
      quantity: qty,
      price: price,
      fees: fees,
      executedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('summarizeTrades', () {
    test('primeira compra define quantidade e preço médio', () {
      final s = summarizeTrades([trade(TradeType.buy, 10, 20)]);
      expect(s.quantity, 10);
      expect(s.averagePrice, 20);
      expect(s.realizedProfit, 0);
    });

    test('compras seguintes usam preço médio ponderado', () {
      final s = summarizeTrades([
        trade(TradeType.buy, 10, 20),
        trade(TradeType.buy, 10, 30),
      ]);
      expect(s.quantity, 20);
      expect(s.averagePrice, 25);
    });

    test('taxas da compra entram no preço médio', () {
      final s = summarizeTrades([trade(TradeType.buy, 10, 20, fees: 10)]);
      expect(s.averagePrice, closeTo(21, 1e-9));
    });

    test('venda realiza lucro e preserva o preço médio', () {
      final s = summarizeTrades([
        trade(TradeType.buy, 10, 20),
        trade(TradeType.sell, 4, 25, fees: 1),
      ]);
      expect(s.quantity, 6);
      expect(s.averagePrice, 20);
      expect(s.realizedProfit, closeTo(19, 1e-9)); // (25-20)*4 - 1
    });

    test('venda total zera a posição e o preço médio', () {
      final s = summarizeTrades([
        trade(TradeType.buy, 5, 10),
        trade(TradeType.sell, 5, 8),
      ]);
      expect(s.quantity, 0);
      expect(s.averagePrice, 0);
      expect(s.realizedProfit, closeTo(-10, 1e-9));
    });

    test('vender mais do que possui lança TradeException', () {
      expect(
        () => summarizeTrades([
          trade(TradeType.buy, 5, 10),
          trade(TradeType.sell, 6, 10),
        ]),
        throwsA(isA<TradeException>()),
      );
    });

    test('ajuste substitui quantidade e preço médio sem mexer no realizado', () {
      final s = summarizeTrades([
        trade(TradeType.buy, 10, 20),
        trade(TradeType.sell, 5, 30),
        trade(TradeType.adjust, 100, 7),
      ]);
      expect(s.quantity, 100);
      expect(s.averagePrice, 7);
      expect(s.realizedProfit, closeTo(50, 1e-9));
    });
  });

  group('Trade.fromJson', () {
    test('faz ida e volta', () {
      final original = trade(TradeType.buy, 3, 12.5, fees: 0.5);
      final parsed = Trade.fromJson(Map<String, dynamic>.from(original.toJson()));
      expect(parsed.symbol, 'PETR4');
      expect(parsed.type, TradeType.buy);
      expect(parsed.quantity, 3);
      expect(parsed.price, 12.5);
      expect(parsed.fees, 0.5);
    });

    test('rejeita quantidade inválida', () {
      expect(
        () => Trade.fromJson({
          'symbol': 'PETR4',
          'type': 'buy',
          'quantity': 0,
          'price': 1,
          'executedAt': '2026-01-01T00:00:00Z',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
