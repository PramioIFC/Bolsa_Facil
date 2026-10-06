import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/price_alert.dart';
import '../state/app_state.dart';
import '../utils/format.dart';

class PriceAlertsScreen extends StatefulWidget {
  const PriceAlertsScreen({super.key, required this.state, this.initialSymbol});
  final AppState state;
  final String? initialSymbol;

  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  String? permissionMessage;
  bool requestingPermission = false;

  @override
  void initState() {
    super.initState();
    widget.state.alertState.load();
    if (widget.initialSymbol?.trim().isNotEmpty ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _edit();
      });
    }
  }

  Future<String?> _save(PriceAlert alert, PriceAlert? existing) async {
    try {
      final id = existing?.id;
      if (id != null) {
        await widget.state.alertState.update(id, alert);
      } else {
        await widget.state.alertState.create(alert);
      }
      return widget.state.alertState.error;
    } on PriceAlertException catch (error) {
      return error.message;
    } catch (_) {
      return 'Não foi possível salvar o alerta. Tente novamente.';
    }
  }

  Future<void> _edit([PriceAlert? existing]) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AlertDialog(
          existing: existing,
          initialSymbol: widget.initialSymbol,
          onSave: (alert) => _save(alert, existing),
        ),
      );

  Future<void> _delete(PriceAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover alerta de ${alert.symbol}?'),
        content:
            const Text('O alerta e seu registro de disparo serão removidos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (confirmed != true || alert.id == null) return;
    try {
      await widget.state.alertState.delete(alert.id!);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Não foi possível remover o alerta. Tente novamente.')));
    }
  }

  Future<void> _permission() async {
    setState(() => requestingPermission = true);
    try {
      final allowed = await widget.state.alertState.requestPermission();
      if (!mounted) return;
      setState(() => permissionMessage = allowed
          ? 'Notificações ativadas.'
          : 'Permissão não concedida. Acompanhe os disparos no histórico do app.');
    } finally {
      if (mounted) setState(() => requestingPermission = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.state.alertState,
        builder: (context, _) {
          final alerts = widget.state.alertState;
          final active = alerts.alerts
              .where((alert) => alert.triggeredAt == null)
              .toList();
          final triggered = alerts.alerts
              .where((alert) => alert.triggeredAt != null)
              .toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Alertas de preço'), actions: [
              IconButton(
                  tooltip: 'Recarregar alertas',
                  onPressed: alerts.loading ? null : alerts.load,
                  icon: const Icon(Icons.refresh)),
            ]),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: alerts.saving ? null : () => _edit(),
                icon: const Icon(Icons.add_alert_outlined),
                label: const Text('Criar alerta')),
            body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                children: [
                  const Text(
                      'Avaliados ao atualizar cotações com o app aberto. Cada alerta dispara uma vez.'),
                  const SizedBox(height: 16),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(permissionMessage ??
                                    (alerts.notificationsAllowed
                                        ? 'Notificações ativadas.'
                                        : 'As notificações não estão ativadas. Os disparos continuam disponíveis no histórico do app.')),
                                if (!alerts.notificationsAllowed) ...[
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                      onPressed: requestingPermission
                                          ? null
                                          : _permission,
                                      icon: const Icon(
                                          Icons.notifications_outlined),
                                      label: const Text('Ativar notificações')),
                                ],
                              ]))),
                  const SizedBox(height: 16),
                  if (alerts.error != null) ...[
                    Semantics(
                        liveRegion: true,
                        child: Text(alerts.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                    TextButton.icon(
                        onPressed: alerts.loading ? null : alerts.load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente')),
                  ],
                  if (alerts.loading && alerts.alerts.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()))
                  else if (alerts.alerts.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Text('Nenhum alerta criado.',
                            textAlign: TextAlign.center)),
                  if (active.isNotEmpty) ...[
                    Text('Ativos',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (final alert in active) ...[
                      _AlertCard(
                          alert: alert,
                          saving: alerts.saving,
                          onEdit: () => _edit(alert),
                          onDelete: () => _delete(alert)),
                      const SizedBox(height: 10),
                    ],
                  ],
                  if (triggered.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Disparados',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (final alert in triggered) ...[
                      _AlertCard(
                          alert: alert,
                          saving: alerts.saving,
                          onEdit: () => _edit(alert),
                          onDelete: () => _delete(alert)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ]),
          );
        },
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard(
      {required this.alert,
      required this.saving,
      required this.onEdit,
      required this.onDelete});
  final PriceAlert alert;
  final bool saving;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert.symbol, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Alvo: ${formatMoney(alert.target)}'),
            Text(alert.direction == AlertDirection.above
                ? 'Ao atingir ou superar o alvo'
                : 'Ao atingir ou ficar abaixo do alvo'),
            if (alert.triggeredAt != null) ...[
              const SizedBox(height: 8),
              Text(
                  'Disparado em ${DateFormat('dd/MM/yyyy HH:mm').format(alert.triggeredAt!.toLocal())}'),
            ],
            const SizedBox(height: 10),
            Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                      onPressed: saving ? null : onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(alert.triggeredAt == null
                          ? 'Editar'
                          : 'Editar e rearmar')),
                  IconButton(
                      tooltip: 'Remover alerta de ${alert.symbol}',
                      onPressed: saving ? null : onDelete,
                      icon: const Icon(Icons.delete_outline)),
                ]),
          ])));
}

class _AlertDialog extends StatefulWidget {
  const _AlertDialog({this.existing, this.initialSymbol, required this.onSave});
  final PriceAlert? existing;
  final String? initialSymbol;
  final Future<String?> Function(PriceAlert) onSave;

  @override
  State<_AlertDialog> createState() => _AlertDialogState();
}

class _AlertDialogState extends State<_AlertDialog> {
  late final symbol = TextEditingController(
      text: widget.existing?.symbol ?? widget.initialSymbol ?? '');
  late final target = TextEditingController(
      text: widget.existing?.target.toString().replaceAll('.', ',') ?? '');
  late AlertDirection direction =
      widget.existing?.direction ?? AlertDirection.above;
  String? error;
  bool saving = false;

  @override
  void dispose() {
    symbol.dispose();
    target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(target.text.trim().replaceAll(',', '.'));
    if (symbol.text.trim().isEmpty ||
        value == null ||
        !value.isFinite ||
        value <= 0) {
      setState(
          () => error = 'Informe um código e um preço-alvo maior que zero.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final message = await widget.onSave(PriceAlert(
      id: widget.existing?.id,
      symbol: symbol.text.trim().toUpperCase(),
      target: value,
      direction: direction,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      triggeredAt: null,
    ));
    if (!mounted) return;
    if (message == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null
            ? 'Criar alerta'
            : 'Editar e rearmar alerta'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.existing != null) ...[
            const Text(
                'Salvar alterações reativa este alerta. Ele poderá disparar novamente na próxima atualização.'),
            const SizedBox(height: 16),
          ],
          TextField(
              controller: symbol,
              enabled: !saving,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Código da ação', hintText: 'PETR4')),
          const SizedBox(height: 12),
          TextField(
              controller: target,
              enabled: !saving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Preço-alvo', prefixText: r'R$ ')),
          const SizedBox(height: 12),
          InputDecorator(
              decoration: const InputDecoration(labelText: 'Disparar quando'),
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<AlertDirection>(
                value: direction,
                isExpanded: true,
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => direction = value);
                      },
                items: const [
                  DropdownMenuItem(
                      value: AlertDirection.above,
                      child: Text('Atingir ou superar',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: AlertDirection.below,
                      child: Text('Atingir ou ficar abaixo',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ))),
          if (error != null) ...[
            const SizedBox(height: 12),
            Semantics(
                liveRegion: true,
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          ],
        ])),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving
                  ? 'Salvando…'
                  : widget.existing == null
                      ? 'Salvar alerta'
                      : 'Salvar e rearmar')),
        ],
      );
}
