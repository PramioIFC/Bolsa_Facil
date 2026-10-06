import 'package:flutter/material.dart';

import '../state/app_state.dart';

import '../widgets/stock_tile.dart';
import 'stock_details_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state.marketAndPortfolio,
        builder: (context, _) {
          final favorites = state.stocks
              .where((s) => state.favorites.contains(s.symbol))
              .toList();
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
              const SizedBox(height: 22),
              Expanded(
                child: favorites.isEmpty
                    ? const _EmptyFavorites()
                    : RefreshIndicator(
                        onRefresh: state.refresh,
                        child: ListView.separated(
                          itemCount: favorites.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final stock = favorites[index];
                            return StockTile(
                              stock: stock,
                              isFavorite: true,
                              onFavorite: () =>
                                  state.toggleFavorite(stock.symbol),
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => StockDetailsScreen(
                                          state: state, initialStock: stock))),
                            );
                          },
                        ),
                      ),
              ),
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
