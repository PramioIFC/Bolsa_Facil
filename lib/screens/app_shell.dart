import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/settings_state.dart';
import 'account_screen.dart';
import 'favorites_screen.dart';
import 'home_screen.dart';
import 'portfolio_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state, this.settings});
  final AppState state;
  final SettingsState? settings;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    widget.state.portfolioState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.portfolioState.removeListener(_onStateChanged);
    super.dispose();
  }

  /// Exibe, uma única vez, erros de ações do usuário (ex.: falha ao salvar).
  void _onStateChanged() {
    final message = widget.state.takeActionError();
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(state: widget.state),
      FavoritesScreen(state: widget.state),
      PortfolioScreen(state: widget.state),
      AccountScreen(state: widget.state, settings: widget.settings),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.candlestick_chart_outlined),
              selectedIcon: Icon(Icons.candlestick_chart),
              label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.star_outline_rounded),
              selectedIcon: Icon(Icons.star_rounded),
              label: 'Favoritas'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Carteira'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Conta'),
        ],
      ),
    );
  }
}
