// Seleciona, em tempo de compilação, como o SQLite é inicializado:
//  - Web (sem dart:io): SQLite em WebAssembly, persistido no navegador;
//  - Demais plataformas (dart:io): sqflite nativo (Android/iOS) ou FFI
//    (Windows/Linux/macOS).
export 'db_factory_web.dart' if (dart.library.io) 'db_factory_io.dart';
