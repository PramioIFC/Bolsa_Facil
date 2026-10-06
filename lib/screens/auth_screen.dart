import 'package:flutter/material.dart';

import '../state/app_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool registering = false;
  bool obscure = true;
  bool submitting = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate() || submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      if (registering) {
        await widget.state.register(
          name: name.text,
          email: email.text,
          password: password.text,
        );
      } else {
        await widget.state.login(email.text, password.text);
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(Icons.trending_up_rounded,
                                color: Theme.of(context).colorScheme.onPrimary,
                                size: 32),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('Bolsa Fácil',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 28,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text(
                          registering
                              ? 'Crie sua conta para começar'
                              : 'Entre para acessar seus investimentos',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                        if (registering) ...[
                          TextFormField(
                            controller: name,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                                labelText: 'Nome',
                                prefixIcon: Icon(Icons.person_outline_rounded)),
                            validator: (value) =>
                                value == null || value.trim().length < 2
                                    ? 'Informe seu nome.'
                                    : null,
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.mail_outline_rounded)),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            return !text.contains('@') || !text.contains('.')
                                ? 'Informe um e-mail válido.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: password,
                          obscureText: obscure,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => obscure = !obscure),
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (value) =>
                              value == null || value.length < 6
                                  ? 'Use pelo menos 6 caracteres.'
                                  : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 14),
                          Text(error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: submitting ? null : _submit,
                            child: submitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text(registering ? 'Criar conta' : 'Entrar'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () => setState(() {
                                    registering = !registering;
                                    error = null;
                                  }),
                          child: Text(registering
                              ? 'Já tenho uma conta'
                              : 'Ainda não tenho uma conta'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
