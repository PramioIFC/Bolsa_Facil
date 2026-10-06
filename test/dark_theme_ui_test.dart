import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/main.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:bolsa_facil/state/settings_state.dart';
import 'package:bolsa_facil/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

class _UiSettings extends SettingsState {
  _UiSettings({this.fail = false}) : super(AppDatabase()) {
    initializing = false;
  }
  final bool fail;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    if (fail) {
      error = 'Não foi possível salvar o tema. Tente novamente.';
    } else {
      themeMode = mode;
    }
    notifyListeners();
  }
}

AppState _state() => AppState(
      brapiWith(
          (request) async => http.Response(quoteBody(tickerOf(request)), 200)),
      AppDatabase(),
    )
      ..currentUser =
          const UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com')
      ..initializing = false
      ..stocks = const [
        Stock(symbol: 'PETR4', name: 'Petrobras', price: 30, changePercent: 1)
      ]
      ..updatedAt = DateTime(2025, 1, 2, 10, 30);

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  Future<void> selectDark(WidgetTester tester) async {
    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButton<ThemeMode>));
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escuro').last);
    await tester.pumpAndSettle();
  }

  testWidgets('seletor em Conta muda o MaterialApp e cores da cotação',
      (tester) async {
    final settings = _UiSettings();
    await tester.pumpWidget(BolsaFacilApp(state: _state(), settings: settings));
    await tester.pumpAndSettle();
    await selectDark(tester);
    expect(settings.themeMode, ThemeMode.dark);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('PETR4'));
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(tester.widget<Text>(find.text('PETR4')).style?.color,
        theme.colorScheme.onSurface);
    expect(theme.cardTheme.color, isNot(Colors.white));
    expect(_contrast(theme.colorScheme.onSurface, theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5));
    expect(
        _contrast(theme.colorScheme.onSurfaceVariant, theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(positiveColor(context), theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(negativeColor(context), theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tema Sistema acompanha brilho do dispositivo', (tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester
        .pumpWidget(BolsaFacilApp(state: _state(), settings: _UiSettings()));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('PETR4'))).brightness,
        Brightness.dark);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpAndSettle();
    final context = tester.element(find.text('PETR4'));
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.light);
    expect(_contrast(positiveColor(context), theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5));
    expect(_contrast(negativeColor(context), theme.cardTheme.color!),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets('erro ao salvar tema aparece e mantém opção anterior',
      (tester) async {
    final settings = _UiSettings(fail: true);
    await tester.pumpWidget(BolsaFacilApp(state: _state(), settings: settings));
    await tester.pumpAndSettle();
    await selectDark(tester);
    expect(settings.themeMode, ThemeMode.system);
    expect(
        tester
            .widget<DropdownButton<ThemeMode>>(
                find.byType(DropdownButton<ThemeMode>))
            .value,
        ThemeMode.system);
    expect(find.text('Não foi possível salvar o tema. Tente novamente.'),
        findsOneWidget);
  });

  testWidgets('Conta e Home cabem em viewport pequeno e Conta permite rolar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(BolsaFacilApp(state: _state(), settings: _UiSettings()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await selectDark(tester);
    await tester.ensureVisible(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    expect(find.text('Sair da conta').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
