import 'dart:async';

import 'package:bolsa_facil/database/app_database.dart';
import 'package:bolsa_facil/models/portfolio_item.dart';
import 'package:bolsa_facil/models/stock.dart';
import 'package:bolsa_facil/models/trade.dart';
import 'package:bolsa_facil/models/user_account.dart';
import 'package:bolsa_facil/services/quote_repository.dart';
import 'package:bolsa_facil/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers/fakes.dart';

const _ana = UserAccount(id: 1, name: 'Ana', email: 'ana@teste.com');
const _bia = UserAccount(id: 2, name: 'Bia', email: 'bia@teste.com');
const _quote =
    Stock(symbol: 'PETR4', name: 'Petrobras', price: 20, changePercent: 1);

class _BoundaryDatabase extends AppDatabase {
  Future<Set<String>>? favoritesResult;
  Future<List<PortfolioItem>>? positionsResult;
  Future<void>? tradeResult;
  Future<void>? importResult;
  final favoriteResults = <Future<void>>[];
  int favoriteCalls = 0;
  int positionCalls = 0;
  int userDataCalls = 0;
  final positionsStarted = Completer<void>();

  @override
  Future<UserAccount?> getSession() async => _ana;
  @override
  Future<void> logout() async {}
  @override
  Future<UserAccount> login(String email, String password) async => _ana;
  @override
  Future<Set<String>> getFavorites(int userId) {
    userDataCalls++;
    return favoritesResult ?? Future.value({'PETR4'});
  }

  @override
  Future<List<PortfolioItem>> getPositions(int userId) {
    positionCalls++;
    if (!positionsStarted.isCompleted) positionsStarted.complete();
    return positionsResult ??
        Future.value(const [
          PortfolioItem(symbol: 'PETR4', quantity: 10, averagePrice: 20),
        ]);
  }

  @override
  Future<double> getRealizedProfit(int userId) async => 12;
  @override
  Future<void> recordTrade(int userId, Trade trade) =>
      tradeResult ?? Future.value();
  @override
  Future<void> toggleFavorite(int userId, String symbol, bool favorite) =>
      favoriteResults.isEmpty
          ? Future.value()
          : favoriteResults[favoriteCalls++];
  @override
  Future<void> importUserData(int userId, Map<String, dynamic> data) =>
      importResult ?? Future.value();
}

class _DeferredQuotes extends QuoteRepository {
  _DeferredQuotes(super.brapi, super.db);
  final results = <Completer<QuoteUpdate>>[];
  @override
  Future<QuoteUpdate> getQuotes(List<String> symbols,
      {bool forceRefresh = false}) {
    final result = Completer<QuoteUpdate>();
    results.add(result);
    return result.future;
  }
}

class _QueuedAuthDatabase extends _BoundaryDatabase {
  final registerStarted = Completer<void>();
  final registerResult = Completer<UserAccount>();
  UserAccount? persistedUser;
  int logoutCalls = 0;

  @override
  Future<UserAccount> register(
      {required String name,
      required String email,
      required String password}) async {
    registerStarted.complete();
    final user = await registerResult.future;
    persistedUser = user;
    return user;
  }

  @override
  Future<UserAccount> login(String email, String password) async {
    persistedUser = _bia;
    return _bia;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    persistedUser = null;
  }
}

void main() {
  test('mercado e carteira notificam só seu domínio e mantêm facade compatível',
      () async {
    final db = _BoundaryDatabase();
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    var authNotifications = 0;
    var marketNotifications = 0;
    var portfolioNotifications = 0;
    var facadeNotifications = 0;
    state.authState.addListener(() => authNotifications++);
    state.marketState.addListener(() => marketNotifications++);
    state.portfolioState.addListener(() => portfolioNotifications++);
    state.addListener(() => facadeNotifications++);
    state.stocks = [_quote];
    expect(authNotifications, 0);
    expect(portfolioNotifications, 0);
    expect(marketNotifications, 1);
    await state.toggleFavorite('PETR4');
    expect(authNotifications, 0);
    expect(marketNotifications, 1);
    expect(portfolioNotifications, 1);
    expect(facadeNotifications, 2);
  });

  test('finally de refresh antigo não encerra carregamento da sessão nova',
      () async {
    final db = _BoundaryDatabase();
    final brapi = brapiWith((_) async => http.Response('{}', 500));
    final repository = _DeferredQuotes(brapi, db);
    final state = AppState(brapi, db, quoteRepository: repository)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final oldRefresh = state.refresh();
    await state.logout();
    state.currentUser = _bia;
    final newRefresh = state.refresh();
    repository.results[0].complete(const QuoteUpdate(stocks: [_quote]));
    await oldRefresh;
    expect(state.loading, isTrue);
    expect(state.stocks, isEmpty);
    repository.results[1].complete(const QuoteUpdate(stocks: [_quote]));
    await newRefresh;
    expect(state.loading, isFalse);
    expect(state.stocks.single, same(_quote));
  });

  test('search depois de logout não repopula cotações', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final state = AppState(brapiWith((_) {
      started.complete();
      return response.future;
    }), _BoundaryDatabase())
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final search = state.search('PETR4');
    await started.future;
    await state.logout();
    response.complete(http.Response(quoteBody('PETR4'), 200));
    expect(await search, isNull);
    expect(state.stocks, isEmpty);
  });

  test('rollback antigo não altera favoritos nem erros da outra conta',
      () async {
    final pending = Completer<void>();
    final db = _BoundaryDatabase()..favoriteResults.add(pending.future);
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final toggle = state.toggleFavorite('PETR4');
    state.currentUser = _bia;
    state.favorites = {'VALE3'};
    pending.completeError(StateError('gravação recusada'));
    await toggle;
    expect(state.favorites, {'VALE3'});
    expect(state.actionError, isNull);
  });

  test('falha de toggle antigo não desfaz toggle mais recente', () async {
    final oldWrite = Completer<void>();
    final newWrite = Completer<void>();
    final db = _BoundaryDatabase()
      ..favoriteResults.addAll([oldWrite.future, newWrite.future]);
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final oldToggle = state.toggleFavorite('PETR4');
    final newToggle = state.toggleFavorite('PETR4');
    newWrite.complete();
    await newToggle;
    oldWrite.completeError(StateError('gravação recusada'));
    await oldToggle;
    expect(state.favorites, isEmpty);
    expect(state.actionError, isNull);
  });

  test('trade pendente não carrega carteira depois de mudar de conta',
      () async {
    final pending = Completer<void>();
    final db = _BoundaryDatabase()..tradeResult = pending.future;
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final trade = state.buy('PETR4', 10, 20);
    state.currentUser = _bia;
    pending.complete();
    await trade;
    expect(db.positionCalls, 0);
    expect(state.portfolio, isEmpty);
    expect(state.realizedProfit, 0);
  });

  test('dados de usuário só publicam juntos após todas as leituras', () async {
    final pending = Completer<List<PortfolioItem>>();

    final db = _BoundaryDatabase()..positionsResult = pending.future;
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final load = state.portfolioState.loadUserData();
    await db.positionsStarted.future;
    expect(state.favorites, isEmpty);
    expect(state.portfolio, isEmpty);
    pending.complete(
        const [PortfolioItem(symbol: 'PETR4', quantity: 10, averagePrice: 20)]);
    await load;
    expect(state.favorites, {'PETR4'});
    expect(state.portfolio.single.quantity, 10);
    expect(state.realizedProfit, 12);
  });

  test('loadUserData pendente não publica após troca de conta', () async {
    final pending = Completer<Set<String>>();
    final db = _BoundaryDatabase()..favoritesResult = pending.future;
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final load = state.portfolioState.loadUserData();
    state.currentUser = _bia;
    state.favorites = {'VALE3'};
    pending.complete({'PETR4'});
    await load;
    expect(state.favorites, {'VALE3'});
    expect(state.portfolio, isEmpty);
    expect(db.positionCalls, 0);
  });

  test('importação pendente não recarrega dados nem mercado de outra conta',
      () async {
    final pending = Completer<void>();
    final db = _BoundaryDatabase()..importResult = pending.future;
    final state = AppState(brapiWith((_) async => http.Response('{}', 500)), db)
      ..currentUser = _ana;
    addTearDown(state.dispose);
    final importing = state.importJson('{"app":"bolsa_facil"}');
    state.currentUser = _bia;
    pending.complete();
    await importing;
    expect(db.userDataCalls, 0);
    expect(state.portfolio, isEmpty);
    expect(state.loading, isFalse);
  });

  test('dispose durante refresh impede alteração e notificação tardia',
      () async {
    final db = _BoundaryDatabase();
    final brapi = brapiWith((_) async => http.Response('{}', 500));
    final repository = _DeferredQuotes(brapi, db);
    final state = AppState(brapi, db, quoteRepository: repository)
      ..currentUser = _ana;
    final refresh = state.refresh();
    var notifications = 0;
    state.addListener(() => notifications++);
    state.dispose();
    repository.results.single.complete(const QuoteUpdate(stocks: [_quote]));
    await refresh;
    expect(state.stocks, isEmpty);
    expect(notifications, 0);
  });
  test('login só libera Home quando todos os dados do usuário estão prontos',
      () async {
    final positions = Completer<List<PortfolioItem>>();
    final db = _BoundaryDatabase()..positionsResult = positions.future;
    final brapi = brapiWith((_) async => http.Response('{}', 500));
    final repository = _DeferredQuotes(brapi, db);
    final state = AppState(brapi, db, quoteRepository: repository)
      ..initializing = false;
    addTearDown(state.dispose);
    final login = state.login('ana@teste.com', '123456');
    await db.positionsStarted.future;
    expect(state.initializing, isTrue);
    expect(state.portfolio, isEmpty);
    expect(state.favorites, isEmpty);
    expect(repository.results, isEmpty);
    positions.complete(
        const [PortfolioItem(symbol: 'PETR4', quantity: 10, averagePrice: 20)]);
    await login;
    expect(state.initializing, isFalse);
    expect(state.portfolio.single.quantity, 10);
    expect(state.favorites, {'PETR4'});
    repository.results.single.complete(const QuoteUpdate(stocks: [_quote]));
    await state.refresh(force: false);
  });
  test('logout aguarda cadastro pendente e deixa memória e banco deslogados',
      () async {
    final db = _QueuedAuthDatabase();
    final state =
        AppState(brapiWith((_) async => http.Response('{}', 500)), db);
    addTearDown(state.dispose);
    final registration =
        state.register(name: 'Ana', email: 'ana@teste.com', password: '123456');
    await db.registerStarted.future;
    final logout = state.logout();
    expect(db.logoutCalls, 0);
    db.registerResult.complete(_ana);
    await Future.wait([registration, logout]);
    expect(db.logoutCalls, 1);
    expect(db.persistedUser, isNull);
    expect(state.currentUser, isNull);
  });

  test('login mais recente fica igual na memória e sessão persistida',
      () async {
    final db = _QueuedAuthDatabase();
    final brapi = brapiWith((_) async => http.Response('{}', 500));
    final repository = _DeferredQuotes(brapi, db);
    final state = AppState(brapi, db, quoteRepository: repository);
    addTearDown(state.dispose);
    final registration =
        state.register(name: 'Ana', email: 'ana@teste.com', password: '123456');
    await db.registerStarted.future;
    final login = state.login('bia@teste.com', '123456');
    db.registerResult.complete(_ana);
    await Future.wait([registration, login]);
    expect(db.persistedUser, same(_bia));
    expect(state.currentUser, same(_bia));
    repository.results.single.complete(const QuoteUpdate(stocks: [_quote]));
    await state.refresh(force: false);
  });

  test('falha de autenticação não bloqueia logout seguinte na fila', () async {
    final db = _QueuedAuthDatabase();
    final state =
        AppState(brapiWith((_) async => http.Response('{}', 500)), db);
    addTearDown(state.dispose);
    final registration =
        state.register(name: 'Ana', email: 'ana@teste.com', password: '123456');
    final failure = expectLater(registration, throwsA(isA<AuthException>()));
    await db.registerStarted.future;
    final logout = state.logout();
    db.registerResult.completeError(const AuthException('Cadastro recusado.'));
    await failure;
    await logout;
    expect(db.logoutCalls, 1);
    expect(db.persistedUser, isNull);
    expect(state.currentUser, isNull);
  });
}
