import '../models/portfolio_item.dart';
import '../models/stock.dart';

enum StockOrder {
  code('Código (A–Z)'),
  priceDescending('Maior preço'),
  priceAscending('Menor preço'),
  changeDescending('Maior alta'),
  changeAscending('Maior queda');

  const StockOrder(this.label);
  final String label;
}

enum PortfolioOrder {
  code('Código (A–Z)'),
  valueDescending('Maior valor da posição'),
  valueAscending('Menor valor da posição'),
  resultDescending('Maior resultado (%)'),
  resultAscending('Menor resultado (%)');

  const PortfolioOrder(this.label);
  final String label;
}

bool matchesListFilter(String symbol, String name, String query) {
  final normalized = query.trim().toLowerCase();
  return normalized.isEmpty ||
      symbol.toLowerCase().contains(normalized) ||
      name.toLowerCase().contains(normalized);
}

/// Trabalha sobre uma cópia: ordenação da tela nunca modifica o estado global.
List<Stock> orderStocks(Iterable<Stock> stocks,
    {StockOrder order = StockOrder.code, String query = ''}) {
  final result = stocks
      .where((stock) => matchesListFilter(stock.symbol, stock.name, query))
      .toList();
  result.sort((a, b) {
    final comparison = switch (order) {
      StockOrder.code => 0,
      StockOrder.priceDescending => b.price.compareTo(a.price),
      StockOrder.priceAscending => a.price.compareTo(b.price),
      StockOrder.changeDescending => b.changePercent.compareTo(a.changePercent),
      StockOrder.changeAscending => a.changePercent.compareTo(b.changePercent),
    };
    return comparison != 0 ? comparison : a.symbol.compareTo(b.symbol);
  });
  return result;
}

List<PortfolioItem> orderPortfolio(
    Iterable<PortfolioItem> items, Stock? Function(String) stockFor,
    {PortfolioOrder order = PortfolioOrder.code, String query = ''}) {
  final result = items
      .where((item) => matchesListFilter(
          item.symbol, stockFor(item.symbol)?.name ?? '', query))
      .toList();
  double? metric(PortfolioItem item) {
    final quote = stockFor(item.symbol);
    if (quote == null) return null;
    return switch (order) {
      PortfolioOrder.valueDescending ||
      PortfolioOrder.valueAscending =>
        quote.price * item.quantity,
      PortfolioOrder.resultDescending ||
      PortfolioOrder.resultAscending =>
        item.averagePrice > 0
            ? (quote.price - item.averagePrice) / item.averagePrice * 100
            : null,
      PortfolioOrder.code => 0,
    };
  }

  result.sort((a, b) {
    if (order == PortfolioOrder.code) return a.symbol.compareTo(b.symbol);
    final left = metric(a);
    final right = metric(b);
    // Sem cotação vai para o fim em ambas as direções; PM não é preço atual.
    if (left == null && right != null) return 1;
    if (right == null && left != null) return -1;
    final ascending = order == PortfolioOrder.valueAscending ||
        order == PortfolioOrder.resultAscending;
    final comparison = left == null || right == null
        ? 0
        : ascending
            ? left.compareTo(right)
            : right.compareTo(left);
    return comparison != 0 ? comparison : a.symbol.compareTo(b.symbol);
  });
  return result;
}
