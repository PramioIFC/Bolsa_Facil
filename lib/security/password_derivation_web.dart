import 'dart:js_interop';
import 'dart:typed_data';

class PasswordDerivationException implements Exception {
  const PasswordDerivationException(this.message);
  final String message;
  @override
  String toString() => message;
}

@JS('crypto.subtle')
external _SubtleCrypto? get _subtle;

extension type _SubtleCrypto(JSObject _) implements JSObject {
  external JSPromise<JSObject> importKey(String format, JSUint8Array keyData,
      JSString algorithm, bool extractable, JSArray<JSString> usages);
  external JSPromise<JSArrayBuffer> deriveBits(
      _Pbkdf2Params algorithm, JSObject key, int length);
}

extension type _Pbkdf2Params._(JSObject _) implements JSObject {
  external factory _Pbkdf2Params({
    String name,
    JSUint8Array salt,
    int iterations,
    String hash,
  });
}

/// Web Crypto executa a operação assíncrona pelo navegador.
Future<List<int>> derivePasswordKey(
    List<int> password, List<int> salt, int iterations) async {
  if (iterations <= 0) throw ArgumentError.value(iterations, 'iterations');
  final subtle = _subtle;
  if (subtle == null) {
    throw const PasswordDerivationException(
        'O login seguro requer HTTPS ou localhost neste navegador.');
  }
  final key = await subtle
      .importKey('raw', Uint8List.fromList(password).toJS, 'PBKDF2'.toJS, false,
          ['deriveBits'.toJS].toJS)
      .toDart;
  final bits = await subtle
      .deriveBits(
          _Pbkdf2Params(
              name: 'PBKDF2',
              salt: Uint8List.fromList(salt).toJS,
              iterations: iterations,
              hash: 'SHA-256'),
          key,
          256)
      .toDart;
  return bits.toDart.asUint8List();
}
