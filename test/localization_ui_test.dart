import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/main.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/screens/price_alerts_screen.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:bolsa_facil/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

void main() {
  testWidgets(
      'navegação mantém Voltar em português mesmo com dispositivo em inglês',
      (tester) async {
    tester.binding.platformDispatcher.localeTestValue =
        const Locale('en', 'US');
    tester.binding.platformDispatcher.localesTestValue = const [
      Locale('en', 'US')
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final db = AppDatabase();
    final state = AppState(
        brapiWith((_) async => http.Response('{"currency":[]}', 200)), db)
      ..currentUser =
          const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com')
      ..initializing = false;
    final settings = SettingsState(db)..initializing = false;
    // BolsaFacilApp owns and disposes the injected states; no database is opened.
    await tester.pumpWidget(BolsaFacilApp(state: state, settings: settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertas de preço'));
    await tester.pumpAndSettle();
    expect(find.byType(PriceAlertsScreen), findsOneWidget);
    expect(find.byTooltip('Voltar'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(Localizations.localeOf(tester.element(find.byTooltip('Voltar'))),
        const Locale('pt', 'BR'));
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byType(PriceAlertsScreen), findsNothing);
    expect(find.text('Bolsa Fácil'), findsOneWidget);
  });
}
