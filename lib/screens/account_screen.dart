import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.state, this.settings});
  final AppState state;
  final SettingsState? settings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([state.authState, settings]),
        builder: (context, _) => _buildAccount(context),
      );

  Widget _buildAccount(BuildContext context) {
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Minha conta',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      user.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(user.email,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (settings != null) ...[
            const SizedBox(height: 16),
            _ThemeSelector(settings: settings!),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _export(context),
              icon: const Icon(Icons.upload_rounded),
              label: const Text('Exportar backup (copiar JSON)'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _import(context),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Importar backup'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: state.logout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sair da conta'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Seus favoritos e investimentos ficam armazenados neste dispositivo (no navegador, na Web), separados por conta. Use o backup para levá-los a outro lugar.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await state.exportJson();
      await Clipboard.setData(ClipboardData(text: json));
      messenger.showSnackBar(const SnackBar(
        content: Text('Backup copiado. Cole em um arquivo para guardá-lo.'),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await state.importJson(text);
      messenger.showSnackBar(
          const SnackBar(content: Text('Backup importado com sucesso.')));
    } on DataImportException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      messenger
          .showSnackBar(SnackBar(content: Text('Falha ao importar: $error')));
    }
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.settings});
  final SettingsState settings;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Aparência', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            InputDecorator(
              decoration:
                  const InputDecoration(labelText: 'Tema do aplicativo'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  isExpanded: true,
                  onChanged: settings.saving
                      ? null
                      : (value) async {
                          if (value != null) await settings.setThemeMode(value);
                        },
                  items: const [
                    DropdownMenuItem(
                        value: ThemeMode.system, child: Text('Sistema')),
                    DropdownMenuItem(
                        value: ThemeMode.light, child: Text('Claro')),
                    DropdownMenuItem(
                        value: ThemeMode.dark, child: Text('Escuro')),
                  ],
                ),
              ),
            ),
            if (settings.saving) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(semanticsLabel: 'Salvando tema'),
            ],
            if (settings.error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                  liveRegion: true,
                  child: Text(settings.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            ],
          ]),
        ),
      );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Importar backup'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Cole o JSON exportado. Isso SUBSTITUI seus favoritos e sua carteira atuais.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '{ "app": "bolsa_facil", ... }',
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Importar'),
          ),
        ],
      );
}
