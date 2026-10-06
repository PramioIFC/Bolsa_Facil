import 'dart:convert';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/services/brapi_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Banco SQLite em memória (FFI), com PBKDF2 barato para acelerar os testes.
AppDatabase memoryDatabase() {
  sqfliteFfiInit();
  return AppDatabase(
    factory: databaseFactoryFfi,
    databaseName: inMemoryDatabasePath,
    pbkdf2Iterations: 1000,
  );
}

/// Corpo JSON no formato da brapi para um ticker.
String quoteBody(String symbol, {double price = 10, double change = 1}) => jsonEncode({
      'results': [
        {
          'symbol': symbol,
          'longName': 'Empresa $symbol',
          'regularMarketPrice': price,
          'regularMarketChangePercent': change,
        },
      ],
    });

/// BrapiService apontando para um cliente HTTP simulado (sem rede, sem espera).
BrapiService brapiWith(
  Future<http.Response> Function(http.Request request) handler, {
  String token = '',
  List<Duration>? delays,
}) =>
    BrapiService(
      client: MockClient(handler),
      baseUrl: 'https://brapi.test/api',
      token: token,
      delay: (duration) async => delays?.add(duration),
    );

/// Último segmento do caminho, ex.: `/api/quote/PETR4` → `PETR4`.
String tickerOf(http.Request request) => request.url.pathSegments.last;
