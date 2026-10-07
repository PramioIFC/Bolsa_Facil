import 'dart:async';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/main.dart';
import 'package:bolsa_facil/screens/auth_screen.dart';
import 'package:bolsa_facil/screens/app_shell.dart';
import 'package:bolsa_facil/screens/splash_screen.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:bolsa_facil/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

class _ThemeDatabase extends AppDatabase {
  final theme = Completer<String>();
  @override
  Future<String> getThemeMode() => theme.future;
}

void main() {
  testWidgets('splash espera sessão e tema e então mostra login',
      (tester) async {
    final db = _ThemeDatabase();
    final state = AppState(brapiWith((_) => throw StateError('sem rede')), db);
    final settings = SettingsState(db)..initialize();
    await tester.pumpWidget(BolsaFacilApp(state: state, settings: settings));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Carregando...'), findsOneWidget);
    state.initializing = false;
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    db.theme.complete('dark');
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splash termina na tela inicial com sessão restaurada',
      (tester) async {
    final db = _ThemeDatabase();
    db.theme.complete('light');
    final settings = SettingsState(db);
    await settings.initialize();
    final state = AppState(brapiWith((_) => throw StateError('sem rede')), db);
    await tester.pumpWidget(BolsaFacilApp(state: state, settings: settings));
    expect(find.byType(SplashScreen), findsOneWidget);
    state.currentUser = UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com');
    state.initializing = false;
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('splash cabe em janela pequena com texto ampliado',
      (tester) async {
    tester.view.physicalSize = const Size(320, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2)),
      child: SplashScreen(),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Carregando o aplicativo'), findsOneWidget);
  });
}
