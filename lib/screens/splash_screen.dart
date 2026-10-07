import 'package:flutter/material.dart';

/// Permanece visível apenas durante a restauração dos dados locais.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Image.asset(
                      'assets/branding/splash.png',
                      fit: BoxFit.contain,
                      semanticLabel: 'Bolsa Fácil',
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF75DFA7),
                      semanticsLabel: 'Carregando o aplicativo',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Carregando...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      );
}
