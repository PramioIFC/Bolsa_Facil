import 'dart:async';

import 'package:flutter/material.dart';

import '../models/stock.dart';
import '../state/app_state.dart';

import '../utils/format.dart';
import '../widgets/stock_tile.dart';
import 'stock_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final controller = TextEditingController();
  bool searching = false;
  Timer? _debounce;
  List<TickerSuggestion> suggestions = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  /// Autocomplete: espera 400 ms sem digitação e descarta respostas antigas.
  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      if (suggestions.isNotEmpty) setState(() => suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final result = await widget.state.suggest(query);
      if (!mounted || controller.text.trim() != query) return;
      setState(() => suggestions = result);
    });
  }

  void _pick(TickerSuggestion suggestion) {
    controller.text = suggestion.symbol;
    _search();
  }

  Future<void> _search() async {
    _debounce?.cancel();
    if (controller.text.trim().isEmpty) return;
    setState(() {
      searching = true;
      suggestions = const [];
    });
    try {
      final stock = await widget.state.search(controller.text);
      if (mounted && stock != null) _open(stock);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void _open(Stock stock) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            StockDetailsScreen(state: widget.state, initialStock: stock),
      ));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.state.marketAndPortfolio,
        builder: (context, _) => RefreshIndicator(
          onRefresh: widget.state.refresh,
          child: CustomScrollView(slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 6),
              sliver: SliverToBoxAdapter(child: _Header()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Buscar ação, ex: PETR4',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            onPressed: _search,
                            icon: const Icon(Icons.arrow_forward_rounded)),
                  ),
                ),
              ),
            ),
            if (suggestions.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: _Suggestions(items: suggestions, onPick: _pick),
                ),
              ),
            if (_statusMessage(widget.state) != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: _StatusBanner(message: _statusMessage(widget.state)!),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text('Ações em destaque',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface)),
                      Text(_updatedLabel(widget.state),
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12)),
                    ]),
              ),
            ),
            if (widget.state.loading && widget.state.stocks.isEmpty)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()))
            else if (widget.state.error != null && widget.state.stocks.isEmpty)
              SliverFillRemaining(
                  child: _ErrorState(
                      message: widget.state.error!,
                      retry: widget.state.refresh))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                sliver: SliverList.separated(
                  itemCount: widget.state.stocks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final stock = widget.state.stocks[i];
                    return StockTile(
                        stock: stock,
                        isFavorite:
                            widget.state.favorites.contains(stock.symbol),
                        onTap: () => _open(stock),
                        onFavorite: () =>
                            widget.state.toggleFavorite(stock.symbol));
                  },
                ),
              ),
          ]),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.trending_up_rounded,
                color: Theme.of(context).colorScheme.onPrimary)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bolsa Fácil',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface)),
          Text('Invista conhecimento primeiro',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      ]);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded,
                size: 54,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente')),
          ])));
}

String _updatedLabel(AppState state) {
  final time = state.updatedAt;
  return time == null ? 'B3' : 'B3 • atualizado ${formatUpdatedAt(time)}';
}

/// Resume problemas da última atualização (ou `null` se está tudo certo).
String? _statusMessage(AppState state) {
  final parts = <String>[];
  if (state.rateLimited) {
    parts.add(
        'Limite de requisições da brapi atingido; alguns preços podem estar desatualizados.');
  } else if (state.failedSymbols.isNotEmpty) {
    final symbols = state.failedSymbols.toList()..sort();
    parts.add('Sem atualização para: ${symbols.join(', ')}.');
  }
  if (state.usingStaleData && state.updatedAt != null) {
    parts.add('Exibindo dados salvos de ${formatUpdatedAt(state.updatedAt!)}.');
  }
  return parts.isEmpty ? null : parts.join(' ');
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Theme.of(context).colorScheme.onTertiaryContainer)),
          ),
        ]),
      );
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.items, required this.onPick});
  final List<TickerSuggestion> items;
  final ValueChanged<TickerSuggestion> onPick;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Column(children: [
          for (final item in items)
            ListTile(
              dense: true,
              title: Text(item.symbol,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface)),
              subtitle: item.name.isEmpty
                  ? null
                  : Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onPick(item),
            ),
        ]),
      );
}
