import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../utils/list_order.dart';
import '../widgets/list_order_controls.dart';
import '../widgets/stock_tile.dart';
import 'stock_details_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, required this.state});
  final AppState state;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  AppState get state => widget.state;
  StockOrder order = StockOrder.code;
  String filter = '';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state.marketAndPortfolio,
        builder: (context, _) {
          final quotes = state.stocks
              .where((stock) => state.favorites.contains(stock.symbol));
          final visible = orderStocks(quotes, order: order, query: filter);
          final missing = state.favorites
              .where((symbol) =>
                  state.stockFor(symbol) == null &&
                  matchesListFilter(symbol, '', filter))
              .toList()
            ..sort();
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suas favoritas',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 6),
              Text('Acompanhe de perto as ações que importam.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              if (state.favorites.isNotEmpty) ...[
                ListOrderControls<StockOrder>(
                  order: order,
                  orders: {
                    for (final value in StockOrder.values) value: value.label
                  },
                  filterKey: const Key('favorites-list-filter'),
                  onFilterChanged: (value) => setState(() => filter = value),
                  onOrderChanged: (value) => setState(() => order = value),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                  child: state.favorites.isEmpty
                      ? const _EmptyFavorites()
                      : RefreshIndicator(
                          onRefresh: state.refresh,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              if (visible.isEmpty && missing.isEmpty)
                                const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                        'Nenhuma favorita corresponde ao filtro.')),
                              if (missing.isNotEmpty) ...[
                                Text(visible.isEmpty
                                    ? 'Seus favoritos estão salvos, mas ainda não há cotações disponíveis.'
                                    : 'Alguns favoritos ainda não têm cotação.'),
                                const SizedBox(height: 6),
                                Text('Sem cotação: ${missing.join(', ')}.'),
                                TextButton.icon(
                                    onPressed: state.loading
                                        ? null
                                        : () => state.refresh(),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Tentar novamente')),
                                const SizedBox(height: 10),
                              ],
                              for (final stock in visible) ...[
                                StockTile(
                                    stock: stock,
                                    isFavorite: true,
                                    onFavorite: () =>
                                        state.toggleFavorite(stock.symbol),
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => StockDetailsScreen(
                                                state: state,
                                                initialStock: stock)))),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        )),
            ]),
          );
        },
      );
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                shape: BoxShape.circle),
            child: const Icon(Icons.star_outline_rounded,
                size: 42, color: Color(0xFFFFB020))),
        const SizedBox(height: 18),
        Text('Nenhuma favorita ainda',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 6),
        Text('Toque na estrela de uma ação para\nencontrá-la rapidamente aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5)),
      ]));
}
