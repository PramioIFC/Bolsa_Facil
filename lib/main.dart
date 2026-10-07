import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'database/app_database.dart';
import 'database/db_factory.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'services/brapi_service.dart';
import 'state/app_state.dart';
import 'state/settings_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDatabaseFactory();
  final settings = SettingsState(AppDatabase.instance);
  await settings.initialize();
  runApp(BolsaFacilApp(settings: settings));
}

class BolsaFacilApp extends StatefulWidget {
  /// O aplicativo assume o ciclo de vida dos estados recebidos.
  const BolsaFacilApp({super.key, this.settings, this.state});
  final SettingsState? settings;
  final AppState? state;

  @override
  State<BolsaFacilApp> createState() => _BolsaFacilAppState();
}

class _BolsaFacilAppState extends State<BolsaFacilApp> {
  late final AppState state;
  late final SettingsState settings;

  @override
  void initState() {
    super.initState();
    state = widget.state ??
        (AppState(BrapiService(), AppDatabase.instance)..initialize());
    settings = widget.settings ?? (SettingsState(state.db)..initialize());
  }

  @override
  void dispose() {
    state.dispose();
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: settings,
        builder: (context, _) => MaterialApp(
          title: 'Bolsa Fácil',
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          darkTheme: buildTheme(brightness: Brightness.dark),
          themeMode: settings.themeMode,
          home: AnimatedBuilder(
            animation: state.authState,
            builder: (context, _) {
              if (state.initializing) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              return state.isAuthenticated
                  ? AppShell(state: state, settings: settings)
                  : AuthScreen(state: state);
            },
          ),
        ),
      );
}
