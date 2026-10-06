import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/portfolio_item.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late AppState state;

  setUp(() {
    db = memoryDatabase();
    final brapi = brapiWith((request) async =>
        http.Response(quoteBody(tickerOf(request), price: 50), 200));
    state = AppState(brapi, db);
  });
  tearDown(() async {
    state.dispose();
    await db.close();
  });

  test('initialize sem sessão deixa o app deslogado', () async {
    await state.initialize();
    expect(state.initializing, isFalse);
    expect(state.isAuthenticated, isFalse);
  });

  test('registrar carrega as cotações padrão e restaura a sessão depois', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    expect(state.isAuthenticated, isTrue);
    // As cotações carregam em segundo plano; refresh() junta-se à execução em curso.
    await state.refresh(force: false);
    expect(state.stocks, hasLength(AppState.defaultSymbols.length));
    expect(state.updatedAt, isNotNull);

    final restored = AppState(
      brapiWith((request) async => http.Response(quoteBody(tickerOf(request)), 200)),
      db,
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.currentUser?.email, 'ana@a.com');
    await restored.refresh(force: false); // aguarda o carregamento em segundo plano
  });

  test('e-mail repetido no cadastro lança AuthException', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    await state.logout();
    await expectLater(
      state.register(name: 'Outra', email: 'ana@a.com', password: '654321'),
      throwsA(isA<AuthException>()),
    );
  });

  test('logout limpa o estado em memória', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    await state.toggleFavorite('PETR4');
    await state.logout();
    expect(state.isAuthenticated, isFalse);
    expect(state.stocks, isEmpty);
    expect(state.favorites, isEmpty);
  });

  test('favoritos persistem entre sessões', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    await state.toggleFavorite('WEGE3');
    expect(state.favorites, {'WEGE3'});
    await state.logout();
    await state.login('ana@a.com', '123456');
    expect(state.favorites, {'WEGE3'});
  });

  test('compra, venda e resultado realizado', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    await state.buy('PETR4', 10, 20);
    await state.buy('PETR4', 10, 30);
    expect(state.portfolio.single.averagePrice, 25);
    await state.sell('PETR4', 5, 35);
    expect(state.portfolio.single.quantity, 15);
    expect(state.realizedProfit, closeTo(50, 1e-9));
    await expectLater(state.sell('PETR4', 100, 35), throwsA(isA<TradeException>()));
    expect(state.portfolio.single.quantity, 15);
  });

  test('savePosition e removePosition', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    await state.savePosition(const PortfolioItem(symbol: 'VALE3', quantity: 3, averagePrice: 60));
    expect(state.portfolio.single.symbol, 'VALE3');
    await state.removePosition('VALE3');
    expect(state.portfolio, isEmpty);
  });

  test('exportJson/importJson fazem a ida e volta', () async {
    await state.register(name: 'Ana', email: 'ana@a.com', password: '123456');
    await state.buy('PETR4', 10, 20);
    await state.toggleFavorite('WEGE3');
    final json = await state.exportJson();
    await state.removePosition('PETR4');
    await state.toggleFavorite('WEGE3');
    await state.importJson(json);
    expect(state.portfolio.single.symbol, 'PETR4');
    expect(state.favorites, {'WEGE3'});
    await expectLater(state.importJson('isto não é json'), throwsA(isA<DataImportException>()));
  });
}
