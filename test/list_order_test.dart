import 'package:bolsa_facil/models/portfolio_item.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/utils/list_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stocks = [
    Stock(
        symbol: 'VALE3', name: 'Vale Mineradora', price: 50, changePercent: -2),
    Stock(symbol: 'PETR4', name: 'Petrobras', price: 30, changePercent: 3),
    Stock(symbol: 'ABEV3', name: 'Ambev', price: 30, changePercent: 3),
  ];
  const items = [
    PortfolioItem(symbol: 'VALE3', quantity: 10, averagePrice: 40),
    PortfolioItem(symbol: 'PETR4', quantity: 2, averagePrice: 10),
    PortfolioItem(symbol: 'ABEV3', quantity: 2, averagePrice: 10),
    PortfolioItem(symbol: 'SEM3', quantity: 100, averagePrice: 1000),
  ];
  Stock? quoteFor(String symbol) {
    for (final stock in stocks) {
      if (stock.symbol == symbol) return stock;
    }
    return null;
  }

  test('ações ordenam por código/preço/variação e desempate sempre pelo código',
      () {
    final cases = {
      StockOrder.code: ['ABEV3', 'PETR4', 'VALE3'],
      StockOrder.priceDescending: ['VALE3', 'ABEV3', 'PETR4'],
      StockOrder.priceAscending: ['ABEV3', 'PETR4', 'VALE3'],
      StockOrder.changeDescending: ['ABEV3', 'PETR4', 'VALE3'],
      StockOrder.changeAscending: ['VALE3', 'ABEV3', 'PETR4'],
    };
    for (final entry in cases.entries) {
      expect(orderStocks(stocks, order: entry.key).map((s) => s.symbol),
          entry.value);
    }
    expect(stocks.map((s) => s.symbol), ['VALE3', 'PETR4', 'ABEV3']);
  });

  test('filtro local aceita código e nome sem diferenciar maiúsculas', () {
    expect(orderStocks(stocks, query: '  petr ').single.symbol, 'PETR4');
    expect(orderStocks(stocks, query: 'MINERADORA').single.symbol, 'VALE3');
    expect(orderStocks(stocks, query: 'inexistente'), isEmpty);
    expect(orderStocks(stocks, query: '  '), hasLength(3));
  });

  test(
      'carteira ordena valor/resultado e cotação ausente fica sempre por último',
      () {
    final cases = {
      PortfolioOrder.code: ['ABEV3', 'PETR4', 'SEM3', 'VALE3'],
      PortfolioOrder.valueDescending: ['VALE3', 'ABEV3', 'PETR4', 'SEM3'],
      PortfolioOrder.valueAscending: ['ABEV3', 'PETR4', 'VALE3', 'SEM3'],
      PortfolioOrder.resultDescending: ['ABEV3', 'PETR4', 'VALE3', 'SEM3'],
      PortfolioOrder.resultAscending: ['VALE3', 'ABEV3', 'PETR4', 'SEM3'],
    };
    for (final entry in cases.entries) {
      expect(
          orderPortfolio(items, quoteFor, order: entry.key)
              .map((s) => s.symbol),
          entry.value);
    }
    expect(items.map((s) => s.symbol), ['VALE3', 'PETR4', 'ABEV3', 'SEM3']);
  });

  test('carteira filtra nome quando disponível e código mesmo sem cotação', () {
    expect(orderPortfolio(items, quoteFor, query: 'mineradora').single.symbol,
        'VALE3');
    expect(orderPortfolio(items, quoteFor, query: 'sem').single.symbol, 'SEM3');
    expect(orderPortfolio(items, quoteFor, query: 'ausente'), isEmpty);
  });
  test(
      'resultado percentual sem custo fica indisponível e ao fim, mas valor segue válido',
      () {
    const zero = PortfolioItem(symbol: 'ZER3', quantity: 1, averagePrice: 0);
    Stock? withZero(String symbol) => symbol == 'ZER3'
        ? const Stock(
            symbol: 'ZER3', name: 'Sem custo', price: 30, changePercent: 0)
        : quoteFor(symbol);
    for (final order in [
      PortfolioOrder.resultAscending,
      PortfolioOrder.resultDescending
    ]) {
      final sorted = orderPortfolio([zero, ...items], withZero, order: order);
      expect(sorted.skip(3).map((item) => item.symbol), ['SEM3', 'ZER3']);
    }
    expect(
        orderPortfolio([zero, ...items], withZero,
                order: PortfolioOrder.valueAscending)
            .first
            .symbol,
        'ZER3');
  });
}
