import 'dart:convert';
import 'dart:io';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/security/password_derivation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Matcher authMessage(String value) => throwsA(
    isA<AuthException>().having((e) => e.message, 'mensagem', contains(value)));

void main() {
  setUpAll(sqfliteFfiInit);

  test('PBKDF2-HMAC-SHA256 coincide com vetores conhecidos', () async {
    // Vetores independentes: senha "password", salt "salt", saída 256 bits.
    final expected = {
      1: '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      2: 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      4096: 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    };
    for (final entry in expected.entries) {
      expect(
          hex(await derivePasswordKey(
              utf8.encode('password'), utf8.encode('salt'), entry.key)),
          entry.value);
    }
    expect(() => derivePasswordKey([1], [2], 0), throwsArgumentError);
  });

  group('limite persistente de login', () {
    late AppDatabase db;
    late DateTime now;
    setUp(() {
      now = DateTime.utc(2026, 1, 1);
      db = AppDatabase(
          factory: databaseFactoryFfi,
          databaseName: inMemoryDatabasePath,
          pbkdf2Iterations: 2,
          clock: () => now);
    });
    tearDown(() => db.close());

    test('conta cinco falhas inclusive emails inexistentes; expira aos 60s',
        () async {
      await db.register(name: 'Ana', email: 'ana@a.com', password: 'segredo');
      await db.logout();
      for (var i = 0; i < 5; i++) {
        await expectLater(
            db.login(i.isEven ? 'ana@a.com' : 'outra$i@a.com', 'errada'),
            authMessage('incorretos'));
      }
      await expectLater(
          db.login('ana@a.com', 'segredo'), authMessage('60 segundos'));
      expect(await db.getSession(), isNull);
      now = now.add(const Duration(milliseconds: 59999));
      await expectLater(
          db.login('ana@a.com', 'segredo'), authMessage('1 segundo'));
      now = now.add(const Duration(milliseconds: 1));
      expect((await db.login('ana@a.com', 'segredo')).name, 'Ana');
    });

    test('login válido não reinicia o limite de falhas recentes', () async {
      await db.register(name: 'Ana', email: 'ana@a.com', password: 'segredo');
      await expectLater(
          db.login('ana@a.com', 'errada'), authMessage('incorretos'));
      await db.login('ana@a.com', 'segredo');
      for (var i = 0; i < 4; i++) {
        await expectLater(
            db.login('outra@a.com', 'errada'), authMessage('incorretos'));
      }
      await expectLater(
          db.login('ana@a.com', 'segredo'), authMessage('Muitas tentativas'));
    });

    test('tentativas concorrentes gravam somente cinco falhas', () async {
      final errors = await Future.wait(List.generate(12, (i) async {
        try {
          await db.login('email$i@a.com', 'errada');
          return '';
        } on AuthException catch (e) {
          return e.message;
        }
      }));
      expect(errors.where((e) => e.contains('incorretos')), hasLength(5));
      expect(
          errors.where((e) => e.contains('Muitas tentativas')), hasLength(7));
      expect(await (await db.database).query('login_attempts'), hasLength(5));
    });

    test('hash armazenado mais forte nunca é rebaixado', () async {
      final database = await db.database;
      const stored =
          r'pbkdf2_sha256$4096$c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a';
      await database.insert('users', {
        'name': 'Ana',
        'email': 'ana@a.com',
        'password_salt': 'salt',
        'password_hash': stored,
        'created_at': now.toIso8601String()
      });
      await db.login('ana@a.com', 'password');
      expect((await database.query('users')).single['password_hash'], stored);
    });

    test('hash PBKDF2 de custo inferior sobe sem mudar o salt', () async {
      final database = await db.database;
      await database.insert('users', {
        'name': 'Ana',
        'email': 'ana@a.com',
        'password_salt': 'salt',
        'password_hash':
            r'pbkdf2_sha256$1$120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        'created_at': now.toIso8601String()
      });
      await db.login('ana@a.com', 'password');
      final row = (await database.query('users')).single;
      expect(row['password_salt'], 'salt');
      expect(row['password_hash'],
          r'pbkdf2_sha256$2$ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    });
  });

  test('limite continua após reabrir o arquivo SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('bolsa_login_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/login.db';
    final now = DateTime.utc(2026, 1, 1);
    AppDatabase open() => AppDatabase(
        factory: databaseFactoryFfi,
        databaseName: path,
        pbkdf2Iterations: 2,
        clock: () => now);
    final first = open();
    for (var i = 0; i < 5; i++) {
      await expectLater(first.login('desconhecido@a.com', 'errada'),
          authMessage('incorretos'));
    }
    await first.close();
    final reopened = open();
    addTearDown(reopened.close);
    await expectLater(reopened.login('outra@a.com', 'errada'),
        authMessage('Muitas tentativas'));
  });

  test('migração v3 → atual preserva conta, sessão e favoritos', () async {
    final dir = await Directory.systemTemp.createTemp('bolsa_migracao_login_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/legacy.db';
    final initial = AppDatabase(
        factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 2);
    final user = await initial.register(
        name: 'Ana', email: 'ana@a.com', password: 'segredo');
    await initial.toggleFavorite(user.id, 'PETR4', true);
    final database = await initial.database;
    await database.execute('DROP TABLE login_attempts');
    await database.execute('DROP TABLE price_alerts');
    await database.execute('DROP TABLE app_settings');
    await database.setVersion(3);
    await initial.close();
    final upgraded = AppDatabase(
        factory: databaseFactoryFfi, databaseName: path, pbkdf2Iterations: 2);
    addTearDown(upgraded.close);
    expect((await upgraded.getSession())?.id, user.id);
    expect(await upgraded.getFavorites(user.id), {'PETR4'});
    expect(await (await upgraded.database).getVersion(),
        AppDatabase.schemaVersion);
    await expectLater(
        upgraded.login('ana@a.com', 'errada'), authMessage('incorretos'));
    expect(
        await (await upgraded.database).query('login_attempts'), hasLength(1));
    expect((await upgraded.login('ana@a.com', 'segredo')).id, user.id);
  });
}
