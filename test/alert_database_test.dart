import 'dart:io';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/price_alert.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:bolsa_facil/services/quote_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'helpers/fakes.dart';

PriceAlert draft({double target = 20, String symbol = 'petr4'}) => PriceAlert(
    symbol: symbol,
    direction: AlertDirection.above,
    target: target,
    createdAt: DateTime.utc(2026, 1, 1));

void main() {
  late AppDatabase db;
  late int ana;
  late int bia;
  setUp(() async {
    sqfliteFfiInit();
    db = AppDatabase(
        factory: databaseFactoryFfi,
        databaseName: inMemoryDatabasePath,
        pbkdf2Iterations: 2);
    ana = (await db.register(
            name: 'Ana', email: 'ana@a.com', password: 'segredo'))
        .id;
    bia = (await db.register(
            name: 'Bia', email: 'bia@a.com', password: 'segredo'))
        .id;
  });
  tearDown(() => db.close());

  test('freshSymbols distingue rede, TTL e falha parcial com cache vencido',
      () async {
    var failPetrobras = false;
    var now = DateTime.utc(2026);
    final brapi = brapiWith((request) async {
      final symbol = tickerOf(request);
      return failPetrobras && symbol == 'PETR4'
          ? http.Response('', 500)
          : http.Response(quoteBody(symbol), 200);
    });
    final repository = QuoteRepository(brapi, db, clock: () => now);
    expect((await repository.getQuotes(['PETR4'])).freshSymbols, {'PETR4'});
    expect((await repository.getQuotes(['PETR4'])).freshSymbols, isEmpty);
    failPetrobras = true;
    now = now.add(const Duration(hours: 1));
    final mixed = await repository.getQuotes(['PETR4', 'VALE3']);
    expect(mixed.freshSymbols, {'VALE3'});
    expect(mixed.failed, {'PETR4'});
    expect(mixed.stocks.map((s) => s.symbol), ['PETR4', 'VALE3']);
  });

  test('modelo valida preço finito e comparação inclui igualdade', () {
    expect(draft().matches(20), isTrue);
    expect(draft().matches(19), isFalse);
    expect(draft().matches(double.nan), isFalse);
    expect(
        draft().copyWith(direction: AlertDirection.below).matches(20), isTrue);
    expect(
        draft().copyWith(triggeredAt: DateTime.utc(2026)).matches(30), isFalse);
    expect(PriceAlert.fromJson(draft().toJson()).target, 20);
    for (final target in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => draft(target: target).validate(),
          throwsA(isA<PriceAlertException>()));
    }
  });

  test('CRUD recusa duplicatas e não altera alertas de outra conta', () async {
    final alert = await db.createPriceAlert(ana, draft());
    expect(alert.symbol, 'PETR4');
    await expectLater(
        db.createPriceAlert(ana, draft()), throwsA(isA<PriceAlertException>()));
    await db.createPriceAlert(bia, draft());
    expect(
        await db.updatePriceAlert(bia, alert.id!, draft(target: 30)), isFalse);
    expect(await db.deletePriceAlert(bia, alert.id!), isFalse);
    expect(await db.markPriceAlertTriggered(bia, alert, DateTime.utc(2026)),
        isFalse);
    expect((await db.getPriceAlerts(ana)).single.target, 20);
    expect(
        await db.updatePriceAlert(ana, alert.id!, draft(target: 30)), isTrue);
    expect(await db.deletePriceAlert(ana, alert.id!), isTrue);
    expect(await db.getPriceAlerts(ana), isEmpty);
    expect(await db.getPriceAlerts(bia), hasLength(1));
  });

  test('acionamento concorrente tem um vencedor e edição invalida snapshot',
      () async {
    final alert = await db.createPriceAlert(ana, draft());
    final results = await Future.wait(List.generate(
        10,
        (_) =>
            db.markPriceAlertTriggered(ana, alert, DateTime.utc(2026, 2, 1))));
    expect(results.where((value) => value), hasLength(1));
    expect((await db.getPriceAlerts(ana)).single.isTriggered, isTrue);
    await db.updatePriceAlert(ana, alert.id!, draft(target: 30));
    expect(
        await db.markPriceAlertTriggered(ana, alert, DateTime.utc(2026, 3, 1)),
        isFalse);
    expect((await db.getPriceAlerts(ana)).single.isTriggered, isFalse);
  });

  test('backup novo restaura alertas e antigo preserva; inválido não muda nada',
      () async {
    final alert = await db.createPriceAlert(ana, draft());
    await db.markPriceAlertTriggered(ana, alert, DateTime.utc(2026, 2, 1));
    await db.toggleFavorite(ana, 'PETR4', true);
    final backup = await db.exportUserData(ana);
    await db.importUserData(bia, backup);
    expect((await db.getPriceAlerts(bia)).single.isTriggered, isTrue);
    final legacy = Map<String, dynamic>.from(backup)..remove('alerts');
    await db.importUserData(ana, legacy);
    expect(await db.getPriceAlerts(ana), hasLength(1));
    await expectLater(
        db.importUserData(ana, {
          ...backup,
          'favorites': ['VALE3'],
          'alerts': [draft(target: 0).toJson()]
        }),
        throwsA(isA<DataImportException>()));
    expect(await db.getFavorites(ana), {'PETR4'});
    expect(await db.getPriceAlerts(ana), hasLength(1));
    await expectLater(
        db.importUserData(ana, {
          ...backup,
          'alerts': [draft().toJson(), draft().toJson()]
        }),
        throwsA(isA<DataImportException>()));
    await db.importUserData(ana, {...backup, 'alerts': []});
    expect(await db.getPriceAlerts(ana), isEmpty);
    expect(await db.getPriceAlerts(bia), hasLength(1));
  });

  test('migração v5 → v6 preserva sessão, carteira, tema e limite de login',
      () async {
    final dir = await Directory.systemTemp.createTemp('bolsa_alert_migration_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/legacy.db';
    final initial = AppDatabase(
        factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 2);
    final user = await initial.register(
        name: 'Ana', email: 'ana@a.com', password: 'segredo');
    await initial.toggleFavorite(user.id, 'PETR4', true);
    await initial.setThemeMode('dark');
    await initial.recordTrade(
        user.id,
        Trade(
            symbol: 'PETR4',
            type: TradeType.buy,
            quantity: 2,
            price: 20,
            executedAt: DateTime.utc(2026)));
    final database = await initial.database;
    await database.insert('login_attempts', {'failed_at': 123});
    await database.execute('DROP TABLE price_alerts');
    await database.setVersion(5);
    await initial.close();
    final upgraded = AppDatabase(
        factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 2);
    addTearDown(upgraded.close);
    expect(await upgraded.getPriceAlerts(user.id), isEmpty);
    expect((await upgraded.getSession())?.id, user.id);
    expect(await upgraded.getFavorites(user.id), {'PETR4'});
    expect((await upgraded.getPositions(user.id)).single.quantity, 2);
    expect((await upgraded.getTrades(user.id)).single.price, 20);
    expect(await upgraded.getThemeMode(), 'dark');
    expect(
        (await (await upgraded.database).query('login_attempts'))
            .single['failed_at'],
        123);
    expect(await (await upgraded.database).getVersion(),
        AppDatabase.schemaVersion);
    expect((await upgraded.createPriceAlert(user.id, draft())).id, isNotNull);
  });
}
