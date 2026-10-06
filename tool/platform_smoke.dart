// Execute com flutter run -d windows -t tool/platform_smoke.dart
// ou flutter run -d <emulador> -t tool/platform_smoke.dart.
// Usa um banco isolado, removido ao concluir; não lê dados do aplicativo.
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/database/db_factory.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:bolsa_facil/models/price_alert.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDatabaseFactory();
  runApp(const MaterialApp(
      home: Scaffold(
    body: Center(child: Text('Verificando SQLite da plataforma…')),
  )));
  final path = p.join(await databaseFactory.getDatabasesPath(),
      'bolsa_facil_verificacao_${DateTime.now().microsecondsSinceEpoch}.db');
  var db = AppDatabase(databaseName: path);
  void check(bool ok, String message) {
    if (!ok) throw StateError(message);
  }

  try {
    final user = await db.register(
        name: 'Verificação',
        email: 'verificacao@example.test',
        password: 'Teste-local-2026');
    await db.toggleFavorite(user.id, 'PETR4', true);
    await db.recordTrade(
        user.id,
        Trade(
            symbol: 'PETR4',
            type: TradeType.buy,
            quantity: 12,
            price: 31.5,
            executedAt: DateTime.utc(2026)));
    await db.setThemeMode('dark');
    final alert = await db.createPriceAlert(
        user.id,
        PriceAlert(
          symbol: 'PETR4',
          direction: AlertDirection.above,
          target: 40,
          createdAt: DateTime.utc(2026),
        ));
    await db.close();
    db = AppDatabase(databaseName: path);
    check(await db.getThemeMode() == 'dark', 'Tema não persistiu');
    check((await db.getPriceAlerts(user.id)).single.id == alert.id,
        'Alerta não persistiu');
    check(
        await db.markPriceAlertTriggered(
            user.id, alert, DateTime.utc(2026, 1, 2)),
        'Alerta não foi registrado');
    check(
        !await db.markPriceAlertTriggered(
            user.id, alert, DateTime.utc(2026, 1, 2)),
        'Alerta disparou duas vezes');
    check((await db.getSession())?.id == user.id, 'Sessão não persistiu');
    check((await db.getFavorites(user.id)).contains('PETR4'),
        'Favorito não persistiu');
    check((await db.getPositions(user.id)).single.quantity == 12,
        'Posição não persistiu');
    await db.recordTrade(
        user.id,
        Trade(
            symbol: 'PETR4',
            type: TradeType.sell,
            quantity: 2,
            price: 40,
            executedAt: DateTime.utc(2026, 1, 2)));
    check((await db.getPositions(user.id)).single.quantity == 10,
        'Venda incorreta');
    check((await db.getRealizedProfit(user.id)) == 17,
        'Resultado realizado incorreto');
    final backup = await db.exportUserData(user.id);
    await db.removePosition(user.id, 'PETR4');
    await db.importUserData(user.id, backup);
    check((await db.getPositions(user.id)).single.quantity == 10,
        'Backup incorreto');
    check((await db.getPriceAlerts(user.id)).single.isTriggered,
        'Histórico do alerta não persistiu no backup');
    await db.logout();
    check(await db.getSession() == null, 'Logout incorreto');
    await db.login('verificacao@example.test', 'Teste-local-2026');
    check((await db.getSession())?.id == user.id, 'Login incorreto');
    debugPrint('BOLSA_PLATFORM_SMOKE: PASS');
    runApp(const MaterialApp(
        home: Scaffold(
      body: Center(
          child: Text('SQLite: sessão, carteira, tema e alertas verificados.')),
    )));
  } catch (error, stack) {
    debugPrint('BOLSA_PLATFORM_SMOKE: FAIL $error');
    debugPrintStack(stackTrace: stack);
    runApp(const MaterialApp(
        home: Scaffold(
      body: Center(child: Text('Falha na verificação. Consulte o log.')),
    )));
    rethrow;
  } finally {
    await db.close();
    await databaseFactory.deleteDatabase(path);
  }
}
