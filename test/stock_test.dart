import 'package:bolsa_facil/models/stock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Stock.fromJson', () {
    test('mapeia campos básicos com padrões seguros', () {
      final stock = Stock.fromJson({'symbol': 'PETR4'});
      expect(stock.symbol, 'PETR4');
      expect(stock.name, '');
      expect(stock.price, 0);
      expect(stock.currency, 'BRL');
      expect(stock.marketCap, isNull);
      expect(stock.history, isEmpty);
    });

    test('usa shortName quando não há longName', () {
      final stock = Stock.fromJson({'symbol': 'VALE3', 'shortName': 'VALE'});
      expect(stock.name, 'VALE');
    });

    test('lê fundamentos e cai para financialData em profitMargins', () {
      final stock = Stock.fromJson({
        'symbol': 'ITUB4',
        'defaultKeyStatistics': {'dividendYield': 0.1, 'trailingPE': 8.0},
        'financialData': {'profitMargins': 0.3, 'totalDebt': 5, 'totalCash': 7},
      });
      expect(stock.dividendYield, 0.1);
      expect(stock.trailingPE, 8.0);
      expect(stock.profitMargins, 0.3);
      expect(stock.totalDebt, 5);
      expect(stock.totalCash, 7);
    });

    test('descarta pontos do histórico com fechamento <= 0 e converte data em segundos', () {
      final stock = Stock.fromJson({
        'symbol': 'PETR4',
        'historicalDataPrice': [
          {'date': 1735689600, 'close': 37.9},
          {'date': 1735776000, 'close': 0},
        ],
      });
      expect(stock.history, hasLength(1));
      expect(stock.history.first.close, 37.9);
      expect(stock.history.first.date.millisecondsSinceEpoch, 1735689600 * 1000);
    });
  });

  test('toCacheMap/fromCacheMap preservam os campos básicos', () {
    const original = Stock(
      symbol: 'WEGE3',
      name: 'WEG',
      price: 40.5,
      changePercent: -1.2,
      logoUrl: 'https://x/y.png',
      marketCap: 1e9,
    );
    final copy = Stock.fromCacheMap(Map<String, dynamic>.from(original.toCacheMap()));
    expect(copy.symbol, 'WEGE3');
    expect(copy.price, 40.5);
    expect(copy.changePercent, -1.2);
    expect(copy.logoUrl, 'https://x/y.png');
    expect(copy.marketCap, 1e9);
  });
}
