# Bolsa Fácil — Documentação Técnica

Aplicativo Flutter para acompanhar ações da B3, favoritar ativos e simular uma carteira, com cotações da [brapi.dev](https://brapi.dev/).

| Item | Valor |
|---|---|
| Pacote / SDK | `bolsa_facil 1.0.0+1` · Dart `>=3.3.0 <4.0.0` |
| Estado global | `AppState extends ChangeNotifier` (sem o pacote `provider`) |
| Persistência | SQLite: `sqflite` (Android/iOS), `sqflite_common_ffi` (desktop), `sqflite_common_ffi_web` (Web, Wasm) |
| API externa | brapi.dev: `/api/quote/{ticker}` e `/api/quote/list` |
| Gráficos | `fl_chart ^0.69.0` (linha no histórico, pizza na alocação) |

> **Verificação em 05/10/2026:** `flutter analyze` limpo; 70 testes passando; builds Web release, Windows release e APK Android debug concluídos. Web verificada em uso real: cadastro, favorito, compra, venda, histórico, sessão/carteira após F5 e cache com proxy desligado. Migração de uma cópia do banco v1 real passou; o original foi preservado. SQLite Windows passou na verificação de sessão, operações e backup. SQLite Android também passou na mesma verificação de dados. Não confundir build ou smoke test de dados com validação visual completa das plataformas nativas.

---

## 1. Arquitetura

| Camada | Pasta | Responsabilidade |
|---|---|---|
| Screens / Widgets | `lib/screens`, `lib/widgets` | UI; chamam apenas o `AppState` |
| State | `lib/state/app_state.dart` | Estado em memória, orquestração, notificação da UI |
| Repository | `lib/services/quote_repository.dart` | Cache SQLite com TTL, fallback para dado antigo |
| Services | `lib/services/brapi_service.dart` | HTTP da brapi: paralelismo, repetição em 429, falhas tipadas |
| Database | `lib/database/` | `AppDatabase` (schema, auth, carteira, backup, cache) e inicialização por plataforma |
| Models | `lib/models/` | `Stock`, `PricePoint`, `TickerSuggestion`, `CachedQuote`, `PortfolioItem`, `Trade`, `UserAccount` |
| Proxy | `tool/brapi_proxy.dart` | Injeta o token e resolve CORS para a Web |

```
 Screens ◄── AnimatedBuilder(state) ── notifyListeners() ──┐
    │ ações                                                 │
    ▼                                                       │
 AppState ──────────────────────────────────────────────────┘
    │ dados do usuário             │ cotações
    ▼                              ▼
 AppDatabase (SQLite)       QuoteRepository ──► cache (tabela quotes_cache)
  nativo: arquivo                  │ miss/expirado
  Web: Wasm no navegador           ▼
                             BrapiService
                          nativo │        │ Web
                                 │        ▼
                                 │   Proxy 127.0.0.1:8080 (+ token)
                                 ▼        ▼
                              https://brapi.dev/api
```

Não há mais ramificação por plataforma no `AppState`: o mesmo `AppDatabase` roda em todas as plataformas. A diferença está só em `initDatabaseFactory()` (import condicional em `lib/database/db_factory.dart`) e na origem das cotações (direto na brapi no nativo, via proxy na Web).

---

## 2. Banco de dados

Arquivo `bolsa_facil.db` (nativo) ou IndexedDB do navegador (Web). `PRAGMA foreign_keys = ON`. **Versão 4** do schema, com migrações `onUpgrade` 1 → 2 → 3 → 4.

```
users 1──N positions      (PK user_id+symbol)  ← derivada de transactions
users 1──N favorites      (PK user_id+symbol)
users 1──N transactions   (histórico de compras/vendas/ajustes)
users 1──0..1 sessions    (id fixo = 1)
quotes_cache              (global, por símbolo)
```

**`users`**: `id` PK AUTOINCREMENT · `name` · `email` UNIQUE NOCASE (minúsculo) · `password_hash` · `password_salt` · `created_at`.

**`transactions`**

| Coluna | Tipo | Restrições |
|---|---|---|
| `id` | INTEGER | PK AUTOINCREMENT |
| `user_id` | INTEGER | FK `users` CASCADE |
| `symbol` | TEXT | ticker em maiúsculas |
| `type` | TEXT | `buy` \| `sell` \| `adjust` |
| `quantity` | REAL | `> 0` |
| `price` | REAL | `>= 0` |
| `fees` | REAL | padrão 0 |
| `executed_at` | TEXT | ISO-8601 UTC |

Índice `idx_transactions_user_symbol (user_id, symbol, executed_at)`.

**`positions`**: `user_id`, `symbol`, `quantity`, `average_price`, `purchased_at` (último recálculo). É um **cache derivado** de `transactions`, reconstruído por `_rebuildPosition` a cada operação, dentro da mesma transação SQL.

**`favorites`**: `user_id`, `symbol` (PK composta).

**`sessions`**: `id` (CHECK = 1), `user_id`. Uma sessão por instalação/navegador.

**`quotes_cache`**: `symbol` PK · `payload` (JSON dos campos básicos do `Stock`) · `fetched_at` (epoch ms).

Os índices em `positions` e `favorites` já são cobertos pelas chaves primárias compostas (prefixo `user_id`).

### 2.1 Regras da carteira (`summarizeTrades`, em `lib/models/trade.dart`)

| Operação | Efeito |
|---|---|
| `buy` | `PM = (qtd·PM + q·preço + taxas) / (qtd + q)` |
| `sell` | `realizado += (preço − PM)·q − taxas`; PM inalterado; erro se `q > qtd` |
| `adjust` | substitui quantidade e PM; não altera o realizado |

Posição que chega a zero é removida. `removePosition` apaga a posição **e** o histórico do ativo.

### 2.2 Migração 1 → 2

Cada linha de `positions` vira uma transação `adjust` (quantidade e PM preservados), de modo que a posição continua consistente e operável.

### 2.3 Migração de sessão para v3

O banco da versão original usava `session(slot)`. A v3 converte essa tabela para `sessions(id)` dentro da transação de upgrade, preservando o usuário logado. Também recupera bancos v2 que ainda mantinham a tabela antiga; uma sessão v2 já existente tem prioridade. O teste `test/legacy_session_test.dart` verifica contas, sessão, posições, favoritos, integridade e histórico sem alterar o banco de origem.

---

## 3. Autenticação e sessão

Autenticação **local**, sem servidor, OAuth ou JWT.

- **Registro** (`AppDatabase.register`): valida nome (≥ 2), e-mail e senha (≥ 6). E-mail já cadastrado → `AuthException('Este e-mail já está cadastrado.')`; a conta existente **não** é alterada.
- **Hash**: PBKDF2-HMAC-SHA256, salt aleatório de 24 bytes, 60.000 iterações no nativo e 20.000 na Web. O nativo usa `compute` em um isolate; a Web usa Web Crypto assíncrono, exigindo HTTPS ou localhost. Formato: `pbkdf2_sha256$<iterações>$<hex>`. Hashes legados são migrados no login; hashes com mais iterações nunca são reduzidos. Comparação em tempo constante.
- **Login**: mesma mensagem para conta inexistente ou senha errada; ambas consomem derivação. O schema v4 registra falhas em `login_attempts(failed_at)`: após cinco falhas nos últimos 60 segundos, novas tentativas aguardam a expiração da mais antiga. O limite é global na instalação, persiste ao reabrir e serializa tentativas concorrentes em transação. Um sucesso não apaga falhas recentes.
- **Sessão**: `sessions(id=1)`. `AppState.initialize()` chama `getSession()` e reidrata o usuário. `logout()` apaga a linha e zera o estado.

```
initialize() → db.getSession() → usuário? → _loadUserData() → refresh(force:false) → AppShell
                                 └ não ─────────────────────────────────────────→ AuthScreen
```

---

## 4. Integração com a API

### 4.1 `BrapiService`

| Elemento | Regra |
|---|---|
| Base | `--dart-define=BRAPI_BASE_URL` (inclui `/api`); senão Web `http://localhost:8080/api`, nativo `https://brapi.dev/api` |
| Token | `BRAPI_TOKEN` via `--dart-define`, só no nativo, enviado em `Authorization: Bearer` (**não** vai mais na query). Na Web é sempre vazio |
| `fetchQuotes` | Até 3 requisições simultâneas; remove duplicatas; resultado por ticker (`QuotesBatch`) |
| 429 | Até 2 repetições com backoff (500 ms, 1 s; respeita `Retry-After`, máx. 5 s). Se persistir, o lote é abortado e os restantes recebem `rateLimited` |
| Falhas | `QuoteFailure`: `notFound`, `rateLimited`, `unauthorized`, `network`, `other`; cada uma com mensagem própria |
| `getQuote` | Cadeia de tentativas: (1) histórico + fundamentos, (2) só histórico, (3) só cotação básica. Segue para a próxima em `notFound`/`other`/`unauthorized` (a brapi nega 401/403 dados fora do plano); para em 429 ou falha de rede. Sem histórico, a tela mostra "indisponível" |
| `searchTickers` | Autocomplete; nunca lança (devolve lista vazia) |

### 4.2 Endpoints

**`GET /api/quote/{ticker}`**

| Parâmetro | Lista (Home) | Detalhes | Valores |
|---|---|---|---|
| `range` | — | sim | `5d`, `1mo`, `3mo` (padrão), `1y` |
| `interval` | — | `1d` | diário |
| `modules` | — | `defaultKeyStatistics,financialData` | 1ª tentativa |
| `fundamental`, `dividends` | — | `true` | 1ª tentativa |

Resposta consumida por `Stock.fromJson` (campos): `symbol`, `longName`/`shortName`, `regularMarketPrice`, `regularMarketChangePercent`, `logourl`, `currency`, `marketCap`, `historicalDataPrice[{date (epoch s), close}]`, `defaultKeyStatistics{dividendYield, trailingPE, priceToBook, profitMargins}`, `financialData{totalDebt, totalCash, profitMargins}`. Pontos com `close <= 0` são descartados.

**`GET /api/quote/list?search={termo}&limit=8`** (autocomplete). Lê `stocks[]`, aceitando `stock` ou `symbol` como código e `name` como nome. A documentação da brapi indica que este endpoint não exige token e que existe um `/api/v2/tickers` mais novo; o formato de resposta do `list` foi implementado de forma defensiva e **não foi validado contra a API real**.

### 4.3 `QuoteRepository`

TTL de 5 minutos. Para cada ticker: cache fresco → usa; senão busca; se a busca falhar e houver cache antigo, usa-o e marca `hasStale`. Devolve `QuoteUpdate` (`stocks`, `failed`, `rateLimited`, `hasStale`, `updatedAt` = cotação mais antiga exibida). Sem nenhum dado, lança `BrapiException`. `refresh(force: true)` (pull-to-refresh) ignora o TTL; login e abertura usam o cache.

### 4.4 Proxy — `tool/brapi_proxy.dart`

**Por que existe:** (1) o token não pode ser compilado no Flutter Web; (2) CORS.

| Regra | Detalhe |
|---|---|
| Rota única | `GET /api/quote/{ticker}` (ticker validado por regex). `/health` responde `{"ok":true}`. Demais rotas: 404; métodos ≠ GET/OPTIONS: 405 |
| Parâmetros | Só repassa `range, interval, modules, fundamental, dividends, search, limit, page, sortBy, sortOrder, sector, type`. Qualquer `token` do cliente é descartado |
| Escuta | `127.0.0.1:8080` por padrão (`PROXY_HOST`, `PORT`) |
| CORS | Reflete a origem só se permitida: `ALLOWED_ORIGINS` ou, vazio, `localhost`/`127.0.0.1`. Outra origem → 403 |
| Limite | 120 req/min por IP (`RATE_LIMIT`), janela fixa; 429 com `Retry-After` |
| Upstream | `https://brapi.dev/api/quote/{ticker}` + `Authorization: Bearer <token>`; timeout 15 s; status espelhado; 502/504 em falha |
| Token | `BRAPI_TOKEN` (ambiente) ou `.env`; ausente → sai com código 1 |

```
Flutter Web ── GET :8080/api/quote/PETR4?range=3mo ──► proxy ── GET brapi.dev/api/quote/PETR4?range=3mo
                                                         (+ Bearer token)  ◄── status + JSON ──┘
```

Execução: `cp .env.example .env` (preencher), depois `dart run tool/brapi_proxy.dart` na raiz do projeto. No Windows, `.\run_web.ps1` sobe proxy e Chrome (`--web-port 3000`, perfil em `.chrome-data/`).

---

## 5. Gerenciamento de estado

`AppState(BrapiService, AppDatabase, {QuoteRepository?})`, criado em `main.dart` e passado por construtor às telas, que o observam com `AnimatedBuilder`.

| Campo | Descrição |
|---|---|
| `stocks`, `favorites`, `portfolio`, `realizedProfit` | Dados exibidos |
| `loading`, `initializing`, `error` | Controle de carregamento e erro de `refresh` |
| `failedSymbols`, `rateLimited`, `usingStaleData`, `updatedAt` | Qualidade da última atualização (banner e rótulo na Home) |
| `actionError` | Erro de ação do usuário; o `AppShell` exibe em SnackBar e limpa (`takeActionError`) |

- **`initialize()`**: resolve sessão e carrega favoritos/carteira/realizado; as cotações carregam **em segundo plano** (`unawaited(refresh(force:false))`), então o app abre sem esperar a rede. O mesmo vale para login e cadastro.
- **`refresh({force = true})`**: busca `defaultSymbols ∪ favoritos ∪ carteira` via `QuoteRepository`. Chamadas simultâneas da mesma sessão compartilham a execução. `dispose()` marca o estado como descartado para que respostas tardias não notifiquem. Um contador `_epoch` descarta resultados que chegam depois de logout/novo login.
- **`toggleFavorite`**: atualização otimista com **rollback** e `actionError` se a gravação falhar.
- **`buy` / `sell` / `savePosition` / `removePosition`**: gravam no banco (transação atômica), recarregam `portfolio` e `realizedProfit`, notificam. Erros de regra (`TradeException`) sobem para a UI.
- **`exportJson` / `importJson`**: backup em JSON (favoritos + operações; sem senha). Importar **substitui** os dados atuais, tudo ou nada.
- **`suggest`**: autocomplete com cache em memória e debounce de 400 ms na UI.

---

## 6. Tratamento de erros

| Cenário | Comportamento |
|---|---|
| Proxy fora do ar (Web) | `QuoteFailure.network` → mensagem orientando o `run_web.ps1`; com cache, a Home mostra os dados antigos e um aviso |
| Limite da brapi (429) | Repetição com backoff; se persistir, banner "limite atingido" e dados do cache |
| Token inválido (nativo) | `unauthorized`: "Token da brapi inválido ou ausente" |
| Ticker que falha na lista | Aparece no banner "Sem atualização para: …" |
| Ticker inexistente na busca | SnackBar "Ação não encontrada." |
| Falha ao gravar favorito | Rollback + SnackBar |
| Venda acima da posição | `TradeException`; nada é gravado |
| E-mail já cadastrado | `AuthException`; conta preservada |
| Backup inválido | `DataImportException`; nada é alterado |

---

## 7. Limitações conhecidas

| Limitação | Detalhe |
|---|---|
| **Sem sincronização em nuvem** | App offline-first para dados do usuário; a rede é usada só para cotações |
| **Dados presos ao armazenamento local** | Nativo: ao arquivo do app (desinstalar apaga). Web: ao IndexedDB **da origem** (domínio + porta) e do perfil do navegador; limpar dados do site ou trocar de porta/perfil perde tudo. Mitigação: exportar/importar backup |
| Autenticação é local | Protege contas entre usuários do mesmo aparelho/navegador, não é segurança de servidor; quem acessa o arquivo do banco acessa os dados |
| Custo do hash | 60.000 (nativo) / 20.000 (Web) iterações, fora da thread da UI; autenticação continua local |
| Limite local de login | Cinco falhas por 60 segundos; acesso direto ao banco pode contornar o limite e retrocesso do relógio pode prolongá-lo |
| Cotações exigem rede | Há cache de 5 min, mas só dos campos básicos (sem histórico/fundamentos) |
| Plano gratuito da brapi | 1 ticker por requisição e cotas limitadas |
| Tela de detalhes | Troca de período não atualiza `AppState.stocks` |
| Sem tema escuro, alertas de preço ou ordenação | Não implementados |
| `AppState` único | Não foi dividido em estados menores; toda notificação reconstrói os builders |
| Proxy | Limite por IP em memória (some ao reiniciar); atrás de proxy reverso o IP observado é o do proxy |
| Web: arquivos Wasm | `web/sqlite3.wasm` e `web/sqflite_sw.js` devem casar com a versão do pacote (`dart run sqflite_common_ffi_web:setup`) |
| Windows | Requer `sqlite3` disponível para o FFI; não verificado em execução |

---

## 8. Testes

| Arquivo | Cobre |
|---|---|
| `test/trade_test.dart` | Preço médio, taxas, venda, realizado, ajuste, validação de backup |
| `test/stock_test.dart` | `Stock.fromJson`, histórico, cache map |
| `test/app_database_test.dart` | Registro/login/sessão, e-mail duplicado, hash legado, carteira, rollback de venda, backup, cache, migração v1→v2 |
| `test/brapi_service_test.dart` | Parse, falhas tipadas, 429 + backoff, abort do lote, concorrência, fallback de fundamentos, autocomplete |
| `test/quote_repository_test.dart` | TTL, forceRefresh, dado antigo em falha, falha parcial |
| `test/app_state_test.dart` | Fluxos de registro, sessão, favoritos, compra/venda, backup |
| `test/widget_test.dart` | `AuthScreen` |

Os testes usam SQLite FFI em memória e `MockClient` (sem rede). Estado atual: 70 testes passando. `test/ui_flows_test.dart` cobre venda/histórico/alocação, cache e falhas na Home, rollback de favorito e backup na Conta.

## 9. Verificações reproduzíveis por plataforma

O ambiente validado usa Flutter 3.47.5 / Dart 3.13.4. O lock requer Flutter >=3.44 e Dart >=3.12. O Android usa AGP 8.11.1, Kotlin 2.2.20 e Gradle 8.14, conforme os mínimos do SDK instalado e a [tabela de compatibilidade Kotlin](https://kotlinlang.org/docs/gradle-configure-project.html). O Flutter emite avisos de atualização futura dessas versões, mas a validação permanece habilitada.

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define=BRAPI_BASE_URL=http://localhost:8080/api
flutter build windows --release
flutter build apk --debug
flutter run -d windows --release -t tool/platform_smoke.dart
flutter run -d <emulador> -t tool/platform_smoke.dart
$env:LEGACY_DATABASE_PATH = 'C:/copia/banco-v1.db'
flutter test test/legacy_session_test.dart
Remove-Item Env:LEGACY_DATABASE_PATH
```

`platform_smoke.dart` cria um banco exclusivo, testa cadastro/login, reabertura de sessão/favorito/carteira, compra/venda, resultado realizado e exportação/importação; remove apenas o banco de teste e emite `BOLSA_PLATFORM_SMOKE: PASS` ou `FAIL`. Nunca usa o banco principal.

O proxy em 8080 colidiu com outro serviço local. `run_web.ps1` usa 8081 por padrão e aceita `-ProxyPort`, passando a mesma URL ao Flutter. Espera `/health` ficar pronto e encerra apenas seu próprio processo e filhos. Os testes curl em 8081 retornaram: health 200, PETR4 200, autocomplete 200, rota inválida 404, POST 405, origem proibida 403. A API real confirmou `stocks[].stock/name/logo` em `/api/quote/list`; `/api/v2/tickers` respondeu com `results[]` e `pagination`. Mantido o endpoint existente, cujo contrato funciona.

### Segurança do login — schema v4

`test/login_security_test.dart` cobre vetores conhecidos de PBKDF2, concorrência, expiração, persistência ao reabrir, migração v3→v4 e hashes mais fortes. Login de uma conta Web existente foi verificado no navegador com Web Crypto. Referências: [Flutter compute](https://api.flutter.dev/flutter/foundation/compute.html) e [Web Cryptography](https://www.w3.org/TR/WebCryptoAPI/#pbkdf2-operations).
