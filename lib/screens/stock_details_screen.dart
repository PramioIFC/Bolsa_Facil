import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/stock.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/stock_tile.dart';

class StockDetailsScreen extends StatefulWidget {
  const StockDetailsScreen(
      {super.key, required this.state, required this.initialStock});
  final AppState state;
  final Stock initialStock;

  @override
  State<StockDetailsScreen> createState() => _StockDetailsScreenState();
}

class _StockDetailsScreenState extends State<StockDetailsScreen> {
  Stock? stock;
  String? error;
  String selectedRange = '3mo';
  bool chartLoading = true;

  static const periods = {
    '5d': '5 dias',
    '1mo': '1 mês',
    '3mo': '3 meses',
    '1y': '1 ano',
  };

  @override
  void initState() {
    super.initState();
    stock = widget.initialStock;
    _load();
  }

  Future<void> _load([String? range]) async {
    final requestedRange = range ?? selectedRange;
    setState(() {
      selectedRange = requestedRange;
      chartLoading = true;
      error = null;
    });
    try {
      final value = await widget.state.loadQuote(
        widget.initialStock.symbol,
        range: requestedRange,
      );
      if (mounted) setState(() => stock = value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => chartLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = stock!;
    final up = current.changePercent >= 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(current.symbol),
        actions: [
          AnimatedBuilder(
              animation: widget.state.portfolioState,
              builder: (_, __) => IconButton(
                    onPressed: () =>
                        widget.state.toggleFavorite(current.symbol),
                    icon: Icon(
                        widget.state.favorites.contains(current.symbol)
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: const Color(0xFFFFB020)),
                  )),
          const SizedBox(width: 8)
        ],
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(current.name,
                style: const TextStyle(color: Colors.blueGrey, fontSize: 15)),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(current.price),
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: ink,
                      letterSpacing: -1)),
              const SizedBox(width: 12),
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: (up ? positive : negative).withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(formatPercent(current.changePercent),
                        style: TextStyle(
                            color: up ? positive : negative,
                            fontWeight: FontWeight.w800)),
                  )),
            ]),
            const SizedBox(height: 26),
            Card(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(
                                    'Histórico • ${periods[selectedRange]}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: ink))),
                            if (chartLoading)
                              const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                          ]),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: periods.entries
                                .map((period) => ChoiceChip(
                                      label: Text(period.value),
                                      selected: selectedRange == period.key,
                                      onSelected: chartLoading
                                          ? null
                                          : (_) => _load(period.key),
                                    ))
                                .toList(),
                          ),
                          if (current.history.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              '${_fullDate(current.history.first.date)} — '
                              '${_fullDate(current.history.last.date)}  •  '
                              '${current.history.length} pregões',
                              style: const TextStyle(
                                  color: Colors.blueGrey, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: selectedRange == '1y' ? 340 : 270,
                            child: current.history.isEmpty
                                ? _ChartLoading(
                                    error: error, loading: chartLoading)
                                : _PriceChart(
                                    stock: current,
                                    range: selectedRange,
                                  ),
                          ),
                        ]))),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.monitor_heart_outlined, color: primary),
                            SizedBox(width: 10),
                            Text('Saúde da Empresa',
                                style: TextStyle(
                                    color: ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900))
                          ]),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                                child: _Metric(
                                    label: 'P/L',
                                    value: current.trailingPE
                                            ?.toStringAsFixed(2) ??
                                        '—')),
                            Container(
                                width: 1,
                                height: 38,
                                color: Colors.blueGrey.shade100),
                            Expanded(
                                child: _Metric(
                                    label: 'P/VP',
                                    value: current.priceToBook
                                            ?.toStringAsFixed(2) ??
                                        '—')),
                            Container(
                                width: 1,
                                height: 38,
                                color: Colors.blueGrey.shade100),
                            Expanded(
                                child: _Metric(
                                    label: 'Margem',
                                    value: current.profitMargins != null
                                        ? '${(current.profitMargins! * 100).toStringAsFixed(1)}%'
                                        : '—')),
                          ]),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                                child: _Metric(
                                    label: 'V. Mercado',
                                    value: current.marketCap == null
                                        ? '—'
                                        : _compact(current.marketCap!))),
                            Container(
                                width: 1,
                                height: 38,
                                color: Colors.blueGrey.shade100),
                            Expanded(
                                child: _Metric(
                                    label: 'Dívida',
                                    value: current.totalDebt == null
                                        ? '—'
                                        : _compact(current.totalDebt!))),
                            Container(
                                width: 1,
                                height: 38,
                                color: Colors.blueGrey.shade100),
                            Expanded(
                                child: _Metric(
                                    label: 'Caixa',
                                    value: current.totalCash == null
                                        ? '—'
                                        : _compact(current.totalCash!))),
                          ]),
                        ]))),
            if (current.dividendYield != null &&
                current.dividendYield! > 0) ...[
              const SizedBox(height: 16),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.payments_outlined,
                                  color: Colors.green.shade600),
                              const SizedBox(width: 10),
                              const Text('Dividendos',
                                  style: TextStyle(
                                      color: ink,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900))
                            ]),
                            const SizedBox(height: 12),
                            Text(
                                'Dividend Yield: ${(current.dividendYield! * 100).toStringAsFixed(2)}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 8),
                            Text(
                                'Se você investir R\$ 1.000 hoje, a projeção com base no último ano é receber aproximadamente R\$ ${(1000 * current.dividendYield!).toStringAsFixed(2)} em proventos nos próximos 12 meses.',
                                style: const TextStyle(
                                    color: Colors.blueGrey, height: 1.4)),
                          ]))),
            ],
            const SizedBox(height: 16),
            _BuyCard(state: widget.state, stock: current),
          ]),
    );
  }
}

class _BuyCard extends StatefulWidget {
  const _BuyCard({required this.state, required this.stock});

  final AppState state;
  final Stock stock;

  @override
  State<_BuyCard> createState() => _BuyCardState();
}

class _BuyCardState extends State<_BuyCard> {
  final quantityController = TextEditingController(text: '1');
  bool saving = false;

  double get quantity =>
      double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    quantityController.dispose();
    super.dispose();
  }

  Future<void> _buy() async {
    if (quantity <= 0 || saving) return;
    setState(() => saving = true);
    final purchasedQuantity = quantity;
    try {
      await widget.state.buy(
        widget.stock.symbol,
        purchasedQuantity,
        widget.stock.price,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${purchasedQuantity.toStringAsFixed(2)} ações de '
            '${widget.stock.symbol} adicionadas à carteira.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shopping_cart_outlined, color: primary),
                SizedBox(width: 10),
                Text(
                  'Compra simulada',
                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Adicione esta ação à sua carteira pelo preço atual.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final quantityField = TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    prefixIcon: Icon(Icons.numbers_rounded),
                  ),
                );
                final total = _OrderTotal(
                  unitPrice: widget.stock.price,
                  total: widget.stock.price * quantity,
                );
                if (compact) {
                  return Column(
                    children: [
                      quantityField,
                      const SizedBox(height: 16),
                      total,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: quantityField),
                    const SizedBox(width: 24),
                    Expanded(child: total),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: quantity > 0 && !saving ? _buy : null,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_shopping_cart_rounded),
                label: Text(saving ? 'Adicionando...' : 'Comprar agora'),
              ),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'Simulação educacional — nenhuma ordem real será enviada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTotal extends StatelessWidget {
  const _OrderTotal({required this.unitPrice, required this.total});

  final double unitPrice;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cotação: ${money(unitPrice)}',
            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            'Total: ${money(total)}',
            style: const TextStyle(
              color: ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChart extends StatelessWidget {
  const _PriceChart({required this.stock, required this.range});
  final Stock stock;
  final String range;
  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < stock.history.length; i++)
        FlSpot(i.toDouble(), stock.history[i].close)
    ];
    final rising = stock.history.last.close >= stock.history.first.close;
    final color = rising ? positive : negative;
    final labelDivisions = range == '1y' ? 6 : 4;
    final labelInterval = stock.history.length > 1
        ? (stock.history.length - 1) / labelDivisions
        : 1.0;
    return LineChart(LineChartData(
      minX: 0,
      maxX:
          stock.history.length > 1 ? (stock.history.length - 1).toDouble() : 1,
      gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0xFFEFF1F7), strokeWidth: 1)),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: labelInterval,
            getTitlesWidget: (value, meta) {
              final index = value.round().clamp(0, stock.history.length - 1);
              final date = stock.history[index].date;
              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 9,
                child: Text(
                  range == '1y' ? _monthYear(date) : _dayMonth(date),
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => ink,
              getTooltipItems: (items) => items.map((item) {
                    final index =
                        item.x.round().clamp(0, stock.history.length - 1);
                    final date = stock.history[index].date;
                    return LineTooltipItem(
                      '${_fullDate(date)}\n${money(item.y)}',
                      const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    );
                  }).toList())),
      lineBarsData: [
        LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: .2,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: .25),
                      color.withValues(alpha: 0)
                    ])))
      ],
    ));
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading({this.error, this.loading = false});
  final String? error;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
          child: Text(error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blueGrey)));
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    return const Center(
      child: Text(
        'Histórico indisponível para este ativo no seu plano da brapi.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.blueGrey),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
        const SizedBox(height: 5),
        Text(value,
            style: const TextStyle(color: ink, fontWeight: FontWeight.w800))
      ]);
}

String _compact(double value) {
  if (value >= 1e12) return 'R\$ ${(value / 1e12).toStringAsFixed(1)} tri';
  if (value >= 1e9) return 'R\$ ${(value / 1e9).toStringAsFixed(1)} bi';
  return money(value);
}

String _dayMonth(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

String _monthYear(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';

String _fullDate(DateTime date) => '${_dayMonth(date)}/${date.year.toString()}';
