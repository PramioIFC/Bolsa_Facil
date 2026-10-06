import 'dart:io';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('migra sessão da versão original sem perder conta ou carteira',
      () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('bolsa_legacy_');
    final path = '${dir.path}/copy.db';
    final source = Platform.environment['LEGACY_DATABASE_PATH'];
    if (source != null) {
      await File(source).copy(path);
    } else {
      final legacy = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
              version: 1,
              onCreate: (db, _) async {
                await db.execute(
                    'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT UNIQUE, password_hash TEXT, password_salt TEXT, created_at TEXT)');
                await db.execute(
                    'CREATE TABLE positions (user_id INTEGER, symbol TEXT, quantity REAL, average_price REAL, purchased_at TEXT, PRIMARY KEY(user_id,symbol))');
                await db.execute(
                    'CREATE TABLE favorites (user_id INTEGER, symbol TEXT, PRIMARY KEY(user_id,symbol))');
                await db.execute(
                    'CREATE TABLE session (slot INTEGER PRIMARY KEY CHECK(slot=1), user_id INTEGER)');
                await db.insert('users', {
                  'id': 1,
                  'name': 'Teste',
                  'email': 'teste@example.test',
                  'password_hash': 'legacy',
                  'password_salt': 'salt',
                  'created_at': '2025-01-01'
                });
                await db.insert('session', {'slot': 1, 'user_id': 1});
                await db.insert('positions', {
                  'user_id': 1,
                  'symbol': 'PETR4',
                  'quantity': 12,
                  'average_price': 31.5,
                  'purchased_at': '2025-01-01'
                });
                await db.insert('favorites', {'user_id': 1, 'symbol': 'PETR4'});
              }));
      await legacy.close();
    }
    final before = await databaseFactoryFfi.openDatabase(path);
    final users = await before.query('users');
    final session = await before.query('session');
    final positions = await before.query('positions');
    final favorites = await before.query('favorites');
    await before.close();
    final upgraded =
        AppDatabase(factory: databaseFactoryFfi, databaseName: path);
    try {
      final user = await upgraded.getSession();
      expect(user?.id, session.isEmpty ? null : session.single['user_id']);
      final db = await upgraded.database;
      expect(await db.query('users'), users);
      expect(await db.query('positions'), positions);
      expect(await db.query('favorites'), favorites);
      expect(await db.getVersion(), AppDatabase.schemaVersion);
      expect(await db.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'}
      ]);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final trades = await db.query('transactions');
      expect(trades.length, positions.length);
      for (final row in positions) {
        final trade = trades.singleWhere((t) =>
            t['user_id'] == row['user_id'] && t['symbol'] == row['symbol']);
        expect(trade['quantity'], row['quantity']);
        expect(trade['price'], row['average_price']);
        expect(trade['type'], 'adjust');
      }
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}
