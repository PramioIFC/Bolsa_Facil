import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Deriva 256 bits em um isolate, sem bloquear a thread da interface.
Future<List<int>> derivePasswordKey(
  List<int> password,
  List<int> salt,
  int iterations,
) {
  if (iterations <= 0) throw ArgumentError.value(iterations, 'iterations');
  return compute(_derive, (password, salt, iterations));
}

List<int> _derive((List<int>, List<int>, int) input) {
  final (password, salt, iterations) = input;
  final hmac = Hmac(sha256, password);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(block);
  for (var i = 1; i < iterations; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return result;
}
