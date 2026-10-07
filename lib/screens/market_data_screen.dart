import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/market_data.dart';
import '../services/brapi_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';

class MarketDataScreen extends StatefulWidget {
  const MarketDataScreen({super.key, required this.state});
  final AppState state;

  @override
  State<MarketDataScreen> createState() => _MarketDataScreenState();
}

class _MarketDataScreenState extends State<MarketDataScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  List<CurrencyQuote>? currencies;
  List<InflationIndicator>? inflation;
  String? currencyError, inflationError;
  bool currencyLoading = false, inflationLoading = false;
  bool inflationRequested = false;
  int currencyRequest = 0, inflationRequest = 0;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _loadCurrencies();
  }

  void _onTabChanged() {
    if (tabs.index == 1 && !inflationRequested) _loadInflation();
  }

  @override
  void dispose() {
    tabs.removeListener(_onTabChanged);
    tabs.dispose();
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    final request = ++currencyRequest;
    final session = widget.state.authState.capture();
    setState(() {
      currencyLoading = true;
      currencyError = null;
    });
    try {
      final values = await widget.state.getCurrencies();
      if (!mounted || request != currencyRequest) return;
      if (!widget.state.authState.isCurrent(session)) {
        setState(() {
          currencies = null;
          currencyError = 'Sua sessão mudou. Tente novamente.';
        });
        return;
      }
      setState(() => currencies = values);
    } on BrapiException catch (error) {
      if (mounted && request == currencyRequest) {
        setState(() => currencyError = widget.state.authState.isCurrent(session)
            ? error.message
            : 'Sua sessão mudou. Tente novamente.');
      }
    } catch (_) {
      if (mounted && request == currencyRequest) {
        setState(() => currencyError =
            'Não foi possível carregar o câmbio. Tente novamente.');
      }
    } finally {
      if (mounted && request == currencyRequest) {
        setState(() => currencyLoading = false);
      }
    }
  }

  Future<void> _loadInflation() async {
    inflationRequested = true;
    final request = ++inflationRequest;
    final session = widget.state.authState.capture();
    setState(() {
      inflationLoading = true;
      inflationError = null;
    });
    try {
      final values = await widget.state.getInflation();
      if (!mounted || request != inflationRequest) return;
      if (!widget.state.authState.isCurrent(session)) {
        setState(() {
          inflation = null;
          inflationError = 'Sua sessão mudou. Tente novamente.';
        });
        return;
      }
      setState(() => inflation = values);
    } on BrapiException catch (error) {
      if (mounted && request == inflationRequest) {
        setState(() => inflationError =
            widget.state.authState.isCurrent(session)
                ? error.message
                : 'Sua sessão mudou. Tente novamente.');
      }
    } catch (_) {
      if (mounted && request == inflationRequest) {
        setState(() => inflationError =
            'Não foi possível carregar a inflação. Tente novamente.');
      }
    } finally {
      if (mounted && request == inflationRequest) {
        setState(() => inflationLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Câmbio e inflação'),
            bottom: TabBar(
                controller: tabs,
                tabs: const [Tab(text: 'Câmbio'), Tab(text: 'Inflação')])),
        body: TabBarView(controller: tabs, children: [
          _dataBody(
              loading: currencyLoading,
              error: currencyError,
              empty: currencies?.isEmpty ?? false,
              emptyMessage: 'Nenhuma cotação de câmbio disponível.',
              retry: _loadCurrencies,
              children: [
                for (final quote in currencies ?? const <CurrencyQuote>[])
                  _CurrencyCard(quote: quote)
              ]),
          _dataBody(
              loading: inflationLoading,
              error: inflationError,
              empty: inflation?.isEmpty ?? false,
              emptyMessage: 'Nenhum indicador de inflação disponível.',
              retry: _loadInflation,
              children: [
                for (final indicator
                    in inflation ?? const <InflationIndicator>[])
                  _InflationCard(indicator: indicator)
              ]),
        ]),
      );

  Widget _dataBody(
      {required bool loading,
      required String? error,
      required bool empty,
      required String emptyMessage,
      required Future<void> Function() retry,
      required List<Widget> children}) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      if (loading)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator())),
      if (error != null) ...[
        Semantics(
            liveRegion: true,
            child: Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton.icon(
            onPressed: loading ? null : retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente')),
      ],
      if (!loading && error == null && empty) Text(emptyMessage),
      for (final child in children) ...[child, const SizedBox(height: 12)],
    ]);
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({required this.quote});
  final CurrencyQuote quote;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat('#,##0.0000', 'pt_BR');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${quote.fromCurrency} → ${quote.toCurrency}',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(quote.name),
              const SizedBox(height: 12),
              Text(
                  'Compra (${quote.toCurrency}): ${number.format(quote.bidPrice)}'),
              Text(
                  'Venda (${quote.toCurrency}): ${number.format(quote.askPrice)}'),
              Text('Variação: ${formatPercent(quote.changePercent)}',
                  style: TextStyle(
                      color: quote.changePercent >= 0
                          ? positiveColor(context)
                          : negativeColor(context))),
              const SizedBox(height: 8),
              Text(
                  quote.updatedAt == null
                      ? 'Horário não informado.'
                      : 'Atualizado em ${DateFormat('dd/MM/yyyy HH:mm').format(quote.updatedAt!.toLocal())}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])));
  }
}

class _InflationCard extends StatelessWidget {
  const _InflationCard({required this.indicator});
  final InflationIndicator indicator;

  String get frequency => switch (indicator.frequency.toLowerCase()) {
        'monthly' => 'Mensal',
        'yearly' || 'annual' => 'Anual',
        'daily' => 'Diária',
        'weekly' => 'Semanal',
        _ => indicator.frequency,
      };
  String get unit => switch (indicator.unit.toLowerCase()) {
        'percent' || 'percentage' => '%',
        'points' => 'pontos',
        _ => indicator.unit,
      };

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(indicator.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
                indicator.value == null
                    ? 'Valor indisponível.'
                    : '${NumberFormat('#,##0.00', 'pt_BR').format(indicator.value)} $unit',
                style: Theme.of(context).textTheme.titleMedium),
            Text('Periodicidade: $frequency'),
            Text(indicator.referenceDate == null
                ? 'Referência não informada.'
                : 'Referência: ${DateFormat(indicator.frequency.toLowerCase() == 'monthly' ? 'MM/yyyy' : 'dd/MM/yyyy').format(indicator.referenceDate!)}'),
          ])));
}
