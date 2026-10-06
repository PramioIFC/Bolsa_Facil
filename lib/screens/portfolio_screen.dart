import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/portfolio_item.dart';
import '../models/trade.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/stock_tile.dart';
import 'stock_details_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state.marketAndPortfolio,
        builder: (context, _) {
          final items = state.portfolio;
          final invested = items.fold(0.0, (sum, item) => sum + item.invested);
          final current = items.fold(
              0.0, (sum, item) => sum + _priceOf(item) * item.quantity);
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _positionDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 90),
              children: [
                const Text('Carteira simulada',
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900, color: ink)),
                const SizedBox(height: 18),
                _Summary(
                  invested: invested,
                  current: current,
                  profit: current - invested,
                  realized: state.realizedProfit,
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AllocationCard(
                    slices: [
                      for (final item in items)
                        (item.symbol, _priceOf(item) * item.quantity),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Suas posições',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const _EmptyPortfolio()
                else
                  for (final item in items) ...[
                    _PositionCard(
                      item: item,
                      price: _priceOf(item),
                      onTap: () => _openDetails(context, item),
                      onAction: (action) => _onAction(context, item, action),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      );

  double _priceOf(PortfolioItem item) =>
      state.stockFor(item.symbol)?.price ?? item.averagePrice;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onAction(
      BuildContext context, PortfolioItem item, String action) async {
    switch (action) {
      case 'edit':
        await _positionDialog(context, item);
      case 'sell':
        await _sellDialog(context, item);
      case 'history':
        await _historyDialog(context, item);
      case 'remove':
        await _removeDialog(context, item);
    }
  }

  Future<void> _openDetails(BuildContext context, PortfolioItem item) async {
    try {
      final stock =
          state.stockFor(item.symbol) ?? await state.search(item.symbol);
      if (!context.mounted || stock == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StockDetailsScreen(state: state, initialStock: stock),
        ),
      );
    } catch (error) {
      if (context.mounted) _snack(context, error.toString());
    }
  }

  Future<void> _positionDialog(BuildContext context,
      [PortfolioItem? existing]) async {
    final result = await showDialog<PortfolioItem>(
      context: context,
      builder: (_) => _PositionDialog(existing: existing),
    );
    if (result == null) return;
    try {
      await state.savePosition(result);
    } catch (error) {
      if (context.mounted) _snack(context, error.toString());
    }
  }

  Future<void> _sellDialog(BuildContext context, PortfolioItem item) async {
    final result = await showDialog<_SellInput>(
      context: context,
      builder: (_) => _SellDialog(item: item, suggestedPrice: _priceOf(item)),
    );
    if (result == null) return;
    try {
      await state.sell(item.symbol, result.quantity, result.price,
          fees: result.fees);
      if (context.mounted) {
        _snack(context, 'Venda de ${item.symbol} registrada.');
      }
    } catch (error) {
      if (context.mounted) _snack(context, error.toString());
    }
  }

  Future<void> _historyDialog(BuildContext context, PortfolioItem item) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Histórico • ${item.symbol}'),
        content: SizedBox(
          width: 360,
          child: FutureBuilder<List<Trade>>(
            future: state.tradesFor(item.symbol),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()));
              }
              final trades = snapshot.data ?? const <Trade>[];
              if (trades.isEmpty) {
                return const Text('Nenhuma operação registrada.');
              }
              final date = DateFormat('dd/MM/yyyy HH:mm');
              return ListView(
                shrinkWrap: true,
                children: [
                  for (final trade in trades)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${trade.type.label} • ${formatDecimal(trade.quantity)} × ${money(trade.price)}'),
                      subtitle: Text(
                        '${date.format(trade.executedAt.toLocal())}'
                        '${trade.fees > 0 ? ' • taxas ${money(trade.fees)}' : ''}',
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _removeDialog(BuildContext context, PortfolioItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remover ${item.symbol}?'),
        content: const Text(
            'A posição e todo o histórico de operações desse ativo serão apagados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await state.removePosition(item.symbol);
    } catch (error) {
      if (context.mounted) _snack(context, error.toString());
    }
  }
}

double? _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

class _PositionDialog extends StatefulWidget {
  const _PositionDialog({this.existing});
  final PortfolioItem? existing;

  @override
  State<_PositionDialog> createState() => _PositionDialogState();
}

class _PositionDialogState extends State<_PositionDialog> {
  late final TextEditingController symbol;
  late final TextEditingController quantity;
  late final TextEditingController price;

  @override
  void initState() {
    super.initState();
    symbol = TextEditingController(text: widget.existing?.symbol ?? '');
    quantity =
        TextEditingController(text: widget.existing?.quantity.toString() ?? '');
    price = TextEditingController(
      text: widget.existing?.averagePrice
              .toStringAsFixed(2)
              .replaceAll('.', ',') ??
          '',
    );
  }

  @override
  void dispose() {
    symbol.dispose();
    quantity.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nova posição' : 'Editar posição'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: symbol,
          enabled: widget.existing == null,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Código da ação', hintText: 'PETR4'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantidade'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Preço médio de compra', prefixText: r'R$ '),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final qty = _parse(quantity.text);
            final avg = _parse(price.text);
            final ticker = symbol.text.trim().toUpperCase();
            if (ticker.isNotEmpty &&
                qty != null &&
                qty > 0 &&
                avg != null &&
                avg > 0) {
              Navigator.pop(
                  context,
                  PortfolioItem(
                      symbol: ticker, quantity: qty, averagePrice: avg));
            }
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _SellInput {
  const _SellInput(this.quantity, this.price, this.fees);
  final double quantity;
  final double price;
  final double fees;
}

class _SellDialog extends StatefulWidget {
  const _SellDialog({required this.item, required this.suggestedPrice});
  final PortfolioItem item;
  final double suggestedPrice;

  @override
  State<_SellDialog> createState() => _SellDialogState();
}

class _SellDialogState extends State<_SellDialog> {
  late final TextEditingController quantity;
  late final TextEditingController price;
  final fees = TextEditingController(text: '0');
  String? error;

  @override
  void initState() {
    super.initState();
    quantity = TextEditingController(text: widget.item.quantity.toString());
    price = TextEditingController(
        text: widget.suggestedPrice.toStringAsFixed(2).replaceAll('.', ','));
  }

  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    fees.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Vender ${widget.item.symbol}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: quantity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Quantidade (máx. ${widget.item.quantity})'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Preço de venda', prefixText: r'R$ '),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: fees,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Taxas (opcional)', prefixText: r'R$ '),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: const TextStyle(color: negative)),
        ],
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final qty = _parse(quantity.text);
            final sellPrice = _parse(price.text);
            final fee = _parse(fees.text) ?? 0;
            if (qty == null ||
                qty <= 0 ||
                sellPrice == null ||
                sellPrice < 0 ||
                fee < 0) {
              setState(() => error = 'Confira quantidade, preço e taxas.');
              return;
            }
            if (qty > widget.item.quantity + 1e-9) {
              setState(() => error = 'Você só possui ${widget.item.quantity}.');
              return;
            }
            Navigator.pop(context, _SellInput(qty, sellPrice, fee));
          },
          child: const Text('Vender'),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.invested,
    required this.current,
    required this.profit,
    required this.realized,
  });
  final double invested, current, profit, realized;

  @override
  Widget build(BuildContext context) {
    final up = profit >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF38344B),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: primary.withValues(alpha: 0.24),
              blurRadius: 24,
              offset: const Offset(0, 10))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Valor atual', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 5),
        Text(money(current),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: _WhiteMetric(label: 'Investido', value: money(invested))),
          Expanded(
              child: _WhiteMetric(
                  label: up ? 'Lucro' : 'Prejuízo',
                  value: '${up ? '+' : ''}${money(profit)}')),
        ]),
        const SizedBox(height: 14),
        _WhiteMetric(
            label: 'Resultado realizado (vendas)',
            value: '${realized >= 0 ? '+' : ''}${money(realized)}'),
      ]),
    );
  }
}

class _WhiteMetric extends StatelessWidget {
  const _WhiteMetric({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ]);
}

const _palette = [
  Color(0xFF6558F5),
  Color(0xFF12B886),
  Color(0xFFFFB020),
  Color(0xFFE8590C),
  Color(0xFF1C7ED6),
  Color(0xFFD6336C),
  Color(0xFF74B816),
  Color(0xFF868E96),
];

/// Distribuição da carteira por ativo (valor atual).
class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.slices});
  final List<(String, double)> slices;

  @override
  Widget build(BuildContext context) {
    final valid = slices.where((s) => s.$2 > 0).toList();
    final total = valid.fold(0.0, (sum, s) => sum + s.$2);
    if (total <= 0) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Alocação',
              style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: PieChart(PieChartData(
              centerSpaceRadius: 32,
              sectionsSpace: 2,
              sections: [
                for (var i = 0; i < valid.length; i++)
                  PieChartSectionData(
                    value: valid[i].$2,
                    color: _palette[i % _palette.length],
                    radius: 46,
                    title: valid[i].$2 / total >= 0.07
                        ? '${(valid[i].$2 / total * 100).toStringAsFixed(0)}%'
                        : '',
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800),
                  ),
              ],
            )),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (var i = 0; i < valid.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: _palette[i % _palette.length],
                        shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(valid[i].$1,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ]),
          ]),
        ]),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.item,
    required this.price,
    required this.onTap,
    required this.onAction,
  });
  final PortfolioItem item;
  final double price;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final result = (price - item.averagePrice) * item.quantity;
    final percent =
        item.averagePrice > 0 ? (price / item.averagePrice - 1) * 100 : 0.0;
    final color = result >= 0 ? positive : negative;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.symbol,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: ink)),
                    const SizedBox(height: 5),
                    Text(
                      '${formatDecimal(item.quantity)} ações • PM ${money(item.averagePrice)}',
                      style:
                          const TextStyle(color: Colors.blueGrey, fontSize: 12),
                    ),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(price * item.quantity),
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, color: ink)),
              Text(
                '${result >= 0 ? '+' : ''}${money(result)} (${formatPercent(percent)})',
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ]),
            PopupMenuButton<String>(
              onSelected: onAction,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sell', child: Text('Vender')),
                PopupMenuItem(value: 'history', child: Text('Histórico')),
                PopupMenuItem(
                    value: 'edit', child: Text('Editar (ajuste manual)')),
                PopupMenuItem(value: 'remove', child: Text('Remover')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _EmptyPortfolio extends StatelessWidget {
  const _EmptyPortfolio();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Sua simulação começa aqui.\nAdicione uma posição para acompanhar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey, height: 1.5),
          ),
        ),
      );
}
