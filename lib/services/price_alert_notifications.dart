import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/price_alert.dart';
import '../utils/format.dart';

abstract interface class PriceAlertNotifications {
  /// Deve ser chamada somente por uma ação explícita do usuário.
  Future<bool> requestPermission();
  Future<void> show(PriceAlert alert, double price,
      {bool Function()? canDeliver});
}

class PriceAlertNotificationException implements Exception {
  const PriceAlertNotificationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Entrega imediata no sistema; não agenda nem monitora cotações em segundo plano.
class LocalPriceAlertNotifications implements PriceAlertNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<bool>? _initialization;

  bool get _supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows;

  Future<bool> _initialize() {
    final pending = _initialization;
    if (pending != null) return pending;
    final running = _initializePlugin();
    _initialization = running;
    return running.then((succeeded) {
      if (!succeeded && identical(_initialization, running)) {
        _initialization = null;
      }
      return succeeded;
    });
  }

  Future<bool> _initializePlugin() async {
    try {
      return await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('ic_notification'),
              windows: WindowsInitializationSettings(
                appName: 'Bolsa Fácil',
                appUserModelId: 'Com.BolsaFacil.App',
                guid: 'ef73b06a-8d41-4b59-93ce-695d20c4c1f2',
              ),
            ),
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    try {
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin>();
        if (web == null) return false;
        // Solicitar antes de aguardar o worker preserva o gesto do botão.
        final granted = await web.requestNotificationsPermission() == true;
        return granted && await _initialize();
      }
      if (!await _initialize()) return false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ==
            true;
      }
      // Windows controla a entrega nas configurações do próprio sistema.
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show(PriceAlert alert, double price,
      {bool Function()? canDeliver}) async {
    if (canDeliver?.call() == false) return;
    if (!_supported) {
      throw const PriceAlertNotificationException(
        'Notificações do sistema não estão disponíveis nesta plataforma.',
      );
    }
    final id = alert.id;
    if (id == null || id <= 0 || !price.isFinite || price <= 0) {
      throw const PriceAlertNotificationException(
        'Não foi possível enviar a notificação deste alerta.',
      );
    }
    if (!await _initialize()) {
      throw const PriceAlertNotificationException(
        'Não foi possível iniciar as notificações do sistema.',
      );
    }
    try {
      final permitted = kIsWeb
          ? _plugin
                  .resolvePlatformSpecificImplementation<
                      WebFlutterLocalNotificationsPlugin>()
                  ?.permissionStatus ==
              WebNotificationPermission.granted
          : defaultTargetPlatform == TargetPlatform.android
              ? await _plugin
                      .resolvePlatformSpecificImplementation<
                          AndroidFlutterLocalNotificationsPlugin>()
                      ?.areNotificationsEnabled() ==
                  true
              : true;
      if (!permitted) {
        throw const PriceAlertNotificationException(
          'Permita as notificações nas configurações para receber este aviso.',
        );
      }
      final direction =
          alert.direction == AlertDirection.above ? 'subiu até' : 'caiu até';
      // A sessão pode mudar enquanto inicialização/permissão são verificadas.
      if (canDeliver?.call() == false) return;
      await _plugin.show(
        id: id,
        title: 'Alerta de preço: ${alert.symbol}',
        body: '${alert.symbol} $direction ${formatMoney(price)}. '
            'Preço-alvo: ${formatMoney(alert.target)}.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'price_alerts',
            'Alertas de preço',
            channelDescription: 'Avisos quando um ativo atinge seu preço-alvo',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } on PriceAlertNotificationException {
      rethrow;
    } catch (_) {
      throw const PriceAlertNotificationException(
        'Não foi possível entregar a notificação do sistema. '
        'O alerta continua registrado no aplicativo.',
      );
    }
  }
}
