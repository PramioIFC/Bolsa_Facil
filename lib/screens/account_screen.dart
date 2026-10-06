import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../state/app_state.dart';
import '../theme.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state.authState,
        builder: (context, _) => _buildAccount(context),
      );

  Widget _buildAccount(BuildContext context) {
    final user = state.currentUser;
    if (user == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Minha conta',
              style: TextStyle(
                  color: ink, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFF0EFFF),
                    child: Text(
                      user.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: primary,
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
                            style: const TextStyle(
                                color: ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(user.email,
                            style: const TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          const Text(
            'Seus favoritos e investimentos ficam armazenados neste dispositivo (no navegador, na Web), separados por conta. Use o backup para levá-los a outro lugar.',
            style: TextStyle(color: Colors.blueGrey, height: 1.5),
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
