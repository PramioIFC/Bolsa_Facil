import 'dart:async';
import 'dart:io';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:bolsa_facil/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SettingsDatabase extends AppDatabase {
  String mode = 'system';
  bool failLoad = false;
  bool failSave = false;
  Completer<void>? saveGate;
  Completer<String>? loadGate;
  int writes = 0;
  final saveStarted = Completer<void>();

  @override
  Future<String> getThemeMode() async {
    if (failLoad) throw StateError('falha de leitura');
    return loadGate == null ? mode : await loadGate!.future;
  }

  @override
  Future<void> setThemeMode(String value) async {
    writes++;
    if (!saveStarted.isCompleted) saveStarted.complete();
    if (failSave) throw StateError('falha de gravação');
    await saveGate?.future;
    mode = value;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('SQLite começa no sistema, valida opções e preserva tema após logout',
      () async {
    final db = AppDatabase(
        factory: databaseFactoryFfi,
        databaseName: inMemoryDatabasePath,
        pbkdf2Iterations: 2);
    addTearDown(db.close);
    expect(await db.getThemeMode(), 'system');
    await db.setThemeMode('dark');
    await db.register(name: 'Ana', email: 'ana@a.com', password: 'segredo');
    await db.logout();
    expect(await db.getThemeMode(), 'dark');
    await expectLater(db.setThemeMode('outro'), throwsArgumentError);
    expect(await db.getThemeMode(), 'dark');
    final database = await db.database;
    await expectLater(database.update('app_settings', {'theme_mode': 'outro'}),
        throwsA(isA<DatabaseException>()));
  });

  test('as três opções persistem ao reabrir SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('bolsa_theme_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/theme.db';
    for (final mode in ['light', 'dark', 'system']) {
      final db = AppDatabase(factory: databaseFactoryFfi, databaseName: path);
      await db.setThemeMode(mode);
      await db.close();
      final reopened =
          AppDatabase(factory: databaseFactoryFfi, databaseName: path);
      expect(await reopened.getThemeMode(), mode);
      await reopened.close();
    }
  });

  test('migração v4 → v5 preserva conta, sessão, operações e limite de login',
      () async {
    final dir = await Directory.systemTemp.createTemp('bolsa_theme_migration_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/theme.db';
    final initial = AppDatabase(
        factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 2);
    final user = await initial.register(
        name: 'Ana', email: 'ana@a.com', password: 'segredo');
    await initial.toggleFavorite(user.id, 'PETR4', true);
    await initial.recordTrade(
        user.id,
        Trade(
            symbol: 'PETR4',
            type: TradeType.buy,
            quantity: 2,
            price: 20,
            executedAt: DateTime.utc(2026, 1, 1)));
    final database = await initial.database;
    await database.insert('login_attempts', {'failed_at': 12345});
    await database.execute('DROP TABLE app_settings');
    await database.setVersion(4);
    await initial.close();
    final upgraded = AppDatabase(
        factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 2);
    addTearDown(upgraded.close);
    expect(await upgraded.getThemeMode(), 'system');
    expect((await upgraded.getSession())?.id, user.id);
    expect(await upgraded.getFavorites(user.id), {'PETR4'});
    expect((await upgraded.getPositions(user.id)).single.quantity, 2);
    expect((await upgraded.getTrades(user.id)).single.price, 20);
    expect(
        (await (await upgraded.database).query('login_attempts'))
            .single['failed_at'],
        12345);
    expect(await (await upgraded.database).getVersion(),
        AppDatabase.schemaVersion);
    await upgraded.setThemeMode('dark');
    expect(await upgraded.getThemeMode(), 'dark');
  });

  test('SettingsState carrega cada opção e inicia independente de autenticação',
      () async {
    for (final mode in ThemeMode.values) {
      final db = _SettingsDatabase()..mode = mode.name;
      final settings = SettingsState(db);
      expect(settings.initializing, isTrue);
      await settings.initialize();
      expect(settings.themeMode, mode);
      expect(settings.initializing, isFalse);
      expect(settings.error, isNull);
      settings.dispose();
    }
  });

  test('tema só muda após persistir e gravação concorrente é bloqueada',
      () async {
    final db = _SettingsDatabase()..saveGate = Completer<void>();
    final settings = SettingsState(db);
    addTearDown(settings.dispose);
    await settings.initialize();
    final saving = settings.setThemeMode(ThemeMode.dark);
    await db.saveStarted.future;
    expect(settings.saving, isTrue);
    expect(settings.themeMode, ThemeMode.system);
    await settings.setThemeMode(ThemeMode.light);
    expect(db.writes, 1);
    db.saveGate!.complete();
    await saving;
    expect(settings.saving, isFalse);
    expect(settings.themeMode, ThemeMode.dark);
    expect(db.mode, 'dark');
  });

  test('erro de gravação preserva tema; próxima tentativa pode salvar',
      () async {
    final db = _SettingsDatabase()..mode = 'light';
    final settings = SettingsState(db);
    addTearDown(settings.dispose);
    await settings.initialize();
    db.failSave = true;
    await settings.setThemeMode(ThemeMode.dark);
    expect(settings.themeMode, ThemeMode.light);
    expect(settings.error, 'Não foi possível salvar o tema. Tente novamente.');
    expect(settings.saving, isFalse);
    db.failSave = false;
    await settings.setThemeMode(ThemeMode.dark);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.error, isNull);
  });

  test('erro de leitura mantém sistema e não impede salvar depois', () async {
    final db = _SettingsDatabase()..failLoad = true;
    final settings = SettingsState(db);
    addTearDown(settings.dispose);
    await settings.initialize();
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.initializing, isFalse);
    expect(
        settings.error, 'Não foi possível carregar o tema. Tente novamente.');
    await settings.setThemeMode(ThemeMode.dark);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.error, isNull);
  });

  test('descarte durante leitura não publica nem notifica', () async {
    final db = _SettingsDatabase()..loadGate = Completer<String>();
    final settings = SettingsState(db);
    var notifications = 0;
    settings.addListener(() => notifications++);
    final loading = settings.initialize();
    settings.dispose();
    db.loadGate!.complete('dark');
    await loading;
    expect(notifications, 0);
    expect(settings.themeMode, ThemeMode.system);
    await settings.setThemeMode(ThemeMode.light);
    expect(db.writes, 0);
  });

  test('descarte durante gravação não publica nem notifica resposta', () async {
    final db = _SettingsDatabase()..saveGate = Completer<void>();
    final settings = SettingsState(db);
    await settings.initialize();
    final saving = settings.setThemeMode(ThemeMode.dark);
    await db.saveStarted.future;
    var notifications = 0;
    settings.addListener(() => notifications++);
    settings.dispose();
    db.saveGate!.complete();
    await saving;
    expect(notifications, 0);
    expect(settings.themeMode, ThemeMode.system);
  });
}
