import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/market_data.dart';
import '../services/brapi_service.dart';
import '../state/app_state.dart';

class DividendsScreen extends StatefulWidget {
  const DividendsScreen({super.key, required this.state, required this.symbol});
  final AppState state;
  final String symbol;

  @override
  State<DividendsScreen> createState() => _DividendsScreenState();
}

class _DividendsScreenState extends State<DividendsScreen> {
  List<CashDividend>? dividends;
  String? error;
  bool loading = false;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++requestId;
    final session = widget.state.authState.capture();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await widget.state.getDividends(widget.symbol);
      if (!mounted || request != requestId) return;
      if (!widget.state.authState.isCurrent(session)) {
        setState(() {
          dividends = null;
          error = 'Sua sessão mudou. Tente novamente.';
        });
        return;
      }
      setState(() => dividends = values);
    } on BrapiException catch (failure) {
      if (mounted && request == requestId) {
        setState(() => error = widget.state.authState.isCurrent(session)
            ? failure.message
            : 'Sua sessão mudou. Tente novamente.');
      }
    } catch (_) {
      if (mounted && request == requestId) {
        setState(() =>
            error = 'Não foi possível carregar os proventos. Tente novamente.');
      }
    } finally {
      if (mounted && request == requestId) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(
                'Dividendos e JCP • ${widget.symbol.trim().toUpperCase()}')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Pagamentos por ação informados pela brapi.'),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
          if (error != null) ...[
            Semantics(
                liveRegion: true,
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
            TextButton.icon(
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente')),
          ],
          if (!loading && error == null && (dividends?.isEmpty ?? false))
            const Text('Nenhum pagamento informado para este ativo.'),
          for (final dividend in dividends ?? const <CashDividend>[]) ...[
            _DividendCard(dividend: dividend),
            const SizedBox(height: 12),
          ],
        ]),
      );
}

class _DividendCard extends StatelessWidget {
  const _DividendCard({required this.dividend});
  final CashDividend dividend;
  String _date(DateTime? value) =>
      value == null ? 'não informado' : DateFormat('dd/MM/yyyy').format(value);

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(dividend.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text(
                '${NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 4).format(dividend.rate)} por ação',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Text('Pagamento: ${_date(dividend.paymentDate)}'),
            Text('Data-com: ${_date(dividend.dateCom)}'),
            Text('Data ex: ${_date(dividend.exDate)}'),
          ])));
}
