import 'package:flutter/material.dart';

import '../database/app_database.dart';

/// Tema da instalação, mantido ao entrar ou sair de qualquer conta.
class SettingsState extends ChangeNotifier {
  SettingsState(this.db);
  final AppDatabase db;
  ThemeMode themeMode = ThemeMode.system;
  bool initializing = true;
  bool saving = false;
  String? error;
  bool _disposed = false;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final mode = await db.getThemeMode();
      if (_disposed) return;
      themeMode = switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      error = null;
    } catch (_) {
      if (_disposed) return;
      error = 'Não foi possível carregar o tema. Tente novamente.';
    } finally {
      if (!_disposed) {
        initializing = false;
        notifyListeners();
      }
    }
  }

  /// Persiste antes de publicar; a UI desabilita a seleção durante a gravação.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_disposed || saving) return;
    // Bloqueia chamadas concorrentes também enquanto inicializa.
    saving = true;
    error = null;
    notifyListeners();
    try {
      await initialize();
      if (_disposed) return;
      await db.setThemeMode(mode.name);
      if (_disposed) return;
      themeMode = mode;
      error = null;
    } catch (_) {
      if (!_disposed) {
        error = 'Não foi possível salvar o tema. Tente novamente.';
      }
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
