import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/user_account.dart';

/// Identidade de uma sessão; resultados assíncronos só podem publicar nela.
typedef SessionIdentity = ({int epoch, int? userId});

class AuthState extends ChangeNotifier {
  AuthState(this.db);
  final AppDatabase db;
  UserAccount? currentUser;
  bool initializing = true;
  String? initializationError;
  int _epoch = 0;
  bool _disposed = false;
  Future<void> _operations = Future.value();

  SessionIdentity capture() => (epoch: _epoch, userId: currentUser?.id);
  bool isCurrent(SessionIdentity session) => !_disposed && session == capture();
  bool isEpochCurrent(int epoch) => !_disposed && epoch == _epoch;
  int invalidate() => ++_epoch;

  void setUser(UserAccount? user) {
    invalidate();
    currentUser = user;
    initializationError = null;
    notifyListeners();
  }

  /// Serializa também os efeitos persistidos: logout deve ocorrer depois de
  /// um cadastro/login anterior, mesmo que a UI já tenha invalidado a sessão.
  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<UserAccount?> restore() => _enqueue(db.getSession);
  Future<void> logout() => _enqueue(db.logout);
  Future<UserAccount> login(String email, String password) =>
      _enqueue(() => db.login(email, password));
  Future<UserAccount> register(
          {required String name,
          required String email,
          required String password}) =>
      _enqueue(() => db.register(name: name, email: email, password: password));

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    super.dispose();
  }
}
