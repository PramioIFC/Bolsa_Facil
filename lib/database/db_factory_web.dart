import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Usa o SQLite em WebAssembly (`web/sqlite3.wasm` + `web/sqflite_sw.js`).
/// Os dados ficam no armazenamento do navegador, por origem.
Future<void> initDatabaseFactory() async {
  databaseFactory = databaseFactoryFfiWeb;
}
