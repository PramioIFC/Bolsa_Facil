import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolsa_facil/models/price_alert.dart';
import 'package:bolsa_facil/services/price_alert_notifications.dart';
import 'package:bolsa_facil/utils/format.dart';

class _AndroidNotifications extends AndroidFlutterLocalNotificationsPlugin {
  var initialized = 0;
  var requests = 0;
  var delivered = 0;
  var initializationSucceeds = true;
  var granted = true;
  var failPermission = false;
  var failDelivery = false;
  int? lastId;
  String? lastTitle;
  String? lastBody;
  AndroidNotificationDetails? lastDetails;
  Completer<bool>? permissionCheck;
  Completer<void>? permissionCheckStarted;

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    initialized++;
    expect(settings.defaultIcon, 'ic_notification');
    return initializationSucceeds;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    requests++;
    if (failPermission) throw PlatformException(code: 'permission_error');
    return granted;
  }

  @override
  Future<bool?> areNotificationsEnabled() async {
    permissionCheckStarted?.complete();
    return permissionCheck == null ? granted : await permissionCheck!.future;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (failDelivery) throw PlatformException(code: 'delivery_error');
    delivered++;
    lastId = id;
    lastTitle = title;
    lastBody = body;
    lastDetails = notificationDetails;
  }
}

PriceAlert _alert(
        {int? id = 17, AlertDirection direction = AlertDirection.above}) =>
    PriceAlert(
      id: id,
      symbol: 'PETR4',
      target: 40,
      direction: direction,
      createdAt: DateTime.utc(2026, 10, 5),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // O runner de testes não registra os plugins das plataformas automaticamente.
  // O teste possui também a instância neutra restaurada entre os casos.
  FlutterLocalNotificationsPlatform.instance = _AndroidNotifications();
  late FlutterLocalNotificationsPlatform original;
  late _AndroidNotifications fake;
  late LocalPriceAlertNotifications service;

  setUp(() {
    original = FlutterLocalNotificationsPlatform.instance;
    fake = _AndroidNotifications();
    FlutterLocalNotificationsPlatform.instance = fake;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    service = LocalPriceAlertNotifications();
  });

  tearDown(() {
    FlutterLocalNotificationsPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  test('construção não inicializa nem solicita permissão', () {
    expect(fake.initialized, 0);
    expect(fake.requests, 0);
  });

  test('solicitação explícita trata permissão concedida e negada', () async {
    expect(await service.requestPermission(), isTrue);
    fake.granted = false;
    expect(await service.requestPermission(), isFalse);
    expect(fake.requests, 2);
    expect(fake.initialized, 1);
  });

  test('falha de permissão retorna false sem expor erro nativo', () async {
    fake.failPermission = true;
    expect(await service.requestPermission(), isFalse);
  });

  test('permissão negada não entrega e não solicita de novo no disparo',
      () async {
    fake.granted = false;
    await expectLater(
      service.show(_alert(), 42.5),
      throwsA(isA<PriceAlertNotificationException>().having(
        (e) => e.message,
        'mensagem',
        contains('Permita as notificações'),
      )),
    );
    expect(fake.delivered, 0);
    expect(fake.requests, 0);
  });

  test('entrega usa ID persistido, português, reais e canal de alertas',
      () async {
    await service.show(_alert(), 42.5);
    expect(fake.lastId, 17);
    expect(fake.lastTitle, 'Alerta de preço: PETR4');
    expect(fake.lastBody,
        'PETR4 subiu até ${formatMoney(42.5)}. Preço-alvo: ${formatMoney(40)}.');
    expect(fake.lastDetails?.channelId, 'price_alerts');
    expect(fake.requests, 0);
  });

  test('alerta de queda mantém seu ID e inicialização compartilhada', () async {
    await Future.wait([
      service.show(_alert(), 42),
      service.show(_alert(id: 18, direction: AlertDirection.below), 38),
    ]);
    expect(fake.delivered, 2);
    expect(fake.initialized, 1);
    expect(fake.lastId, 18);
    expect(fake.lastBody, contains('caiu até'));
  });

  test('falha de inicialização retorna false e erro amigável ao entregar',
      () async {
    fake.initializationSucceeds = false;
    expect(await service.requestPermission(), isFalse);
    await expectLater(
      service.show(_alert(), 42),
      throwsA(isA<PriceAlertNotificationException>().having(
        (e) => e.message,
        'mensagem',
        contains('iniciar as notificações'),
      )),
    );
    expect(fake.requests, 0);
    expect(fake.delivered, 0);
  });

  test('falha de entrega não expõe detalhes nativos', () async {
    fake.failDelivery = true;
    await expectLater(
      service.show(_alert(), 42),
      throwsA(isA<PriceAlertNotificationException>().having(
        (e) => e.message,
        'mensagem',
        contains('continua registrado'),
      )),
    );
  });

  test('falha de inicialização permite nova tentativa após recuperação',
      () async {
    fake.initializationSucceeds = false;
    expect(await service.requestPermission(), isFalse);
    fake.initializationSucceeds = true;
    expect(await service.requestPermission(), isTrue);
    await service.show(_alert(), 42);
    expect(fake.initialized, 2);
    expect(fake.delivered, 1);
  });

  test('sessão encerrada durante verificação não entrega notificação',
      () async {
    fake.permissionCheck = Completer<bool>();
    fake.permissionCheckStarted = Completer<void>();
    var currentSession = true;
    final delivering =
        service.show(_alert(), 42, canDeliver: () => currentSession);
    await fake.permissionCheckStarted!.future;
    currentSession = false;
    fake.permissionCheck!.complete(true);
    await delivering;
    expect(fake.delivered, 0);
    expect(fake.requests, 0);
  });

  test('plataformas sem suporte falham sem inicializar o plugin', () async {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.iOS,
      TargetPlatform.macOS
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await service.requestPermission(), isFalse);
      await expectLater(service.show(_alert(), 42),
          throwsA(isA<PriceAlertNotificationException>()));
    }
    expect(fake.initialized, 0);
  });

  test('alerta não persistido e preço inválido não chegam ao plugin', () async {
    await expectLater(service.show(_alert(id: null), 42),
        throwsA(isA<PriceAlertNotificationException>()));
    await expectLater(service.show(_alert(), double.nan),
        throwsA(isA<PriceAlertNotificationException>()));
    expect(fake.initialized, 0);
  });
}
