<p align="center">
  <img src="assets/branding/app_icon.png" width="120" alt="Bolsa Fácil Logo" />
</p>

<h1 align="center">📈 Bolsa Fácil</h1>

<p align="center">
  <strong>Acompanhe a Bolsa Brasileira com facilidade.</strong><br />
  Cotações em tempo real · Carteira simulada · Alertas de preço · Favoritos · Backup local
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.13.4-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/SQLite-FFI%20%2B%20Wasm-003B57?logo=sqlite&logoColor=white" alt="SQLite" />
  <img src="https://img.shields.io/badge/API-brapi.dev-6558F5" alt="brapi.dev" />
  <img src="https://img.shields.io/badge/Material%203-Design-FF6F00?logo=materialdesign&logoColor=white" alt="Material 3" />
  <img src="https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" alt="CI" />
</p>

<p align="center">
  <a href="#-início-rápido">Início Rápido</a> •
  <a href="#-tecnologias">Tecnologias</a> •
  <a href="#-arquitetura">Arquitetura</a> •
  <a href="#-api--endpoints">API & Endpoints</a> •
  <a href="#-banco-de-dados">Banco de Dados</a> •
  <a href="#-testes">Testes</a> •
  <a href="#-funcionalidades">Funcionalidades</a>
</p>

---

## 📖 Sobre

**Bolsa Fácil** é um aplicativo multiplataforma feito em Flutter para acompanhar ações da B3 em tempo real, gerenciar favoritos, simular uma carteira com compras/vendas e receber alertas de preço — tudo com os dados do usuário armazenados localmente em SQLite (inclusive na Web via WebAssembly).

As cotações são fornecidas pela [brapi.dev](https://brapi.dev/), uma API brasileira gratuita para dados do mercado financeiro.

> **📚 Documentação complementar:**
> - [`TECHNICAL_DOCS.md`](TECHNICAL_DOCS.md) — Documentação técnica detalhada
> - [`MELHORIAS.md`](MELHORIAS.md) — Changelog de melhorias desta versão
> - [`docs/HANDOFF_CODEX.md`](docs/HANDOFF_CODEX.md) — Handoff para continuidade

---

## 🚀 Início Rápido

### Pré-requisitos

| Requisito | Versão |
|---|---|
| **Flutter** | ≥ 3.44 (testado com 3.47.5) |
| **Dart** | ≥ 3.13 (testado com 3.13.4) |
| **Token brapi** | Gratuito em [brapi.dev/dashboard](https://brapi.dev/dashboard) |

### 1. Clone e instale as dependências

```bash
git clone <repo-url>
cd bolsafacil_v2
flutter pub get
```

### 2. Configure o token da brapi

<table>
<tr>
<th>🌐 Web</th>
<th>📱 Android / 🖥️ Windows</th>
</tr>
<tr>
<td>

Crie o arquivo `.env` na raiz:
```bash
cp .env.example .env
```
Edite e insira seu token:
```env
BRAPI_TOKEN=seu_token_aqui
```
> ⚠️ O token é lido **apenas pelo proxy** e nunca é enviado ao navegador.

</td>
<td>

Copie o arquivo de configuração:
```bash
cp config/dart_defines.example.json config/dart_defines.json
```
Edite e insira seu token:
```json
{
  "BRAPI_TOKEN": "seu_token_aqui"
}
```

</td>
</tr>
</table>

### 3. Execute o app

<details>
<summary><strong>🌐 Web (requer proxy)</strong></summary>

**Terminal 1** — Iniciar o proxy:
```bash
dart run tool/brapi_proxy.dart
```

**Terminal 2** — Iniciar o Flutter:
```bash
flutter run -d chrome --web-port 3000
```

**Ou, no Windows, com um único comando:**
```powershell
.\run_web.ps1
```
> O script sobe o proxy em `localhost:8081`, espera o health check e abre o Chrome automaticamente.

</details>

<details>
<summary><strong>📱 Android</strong></summary>

```bash
flutter run --dart-define-from-file=config/dart_defines.json
```
> O app se conecta diretamente à brapi.dev (sem proxy).

</details>

<details>
<summary><strong>🖥️ Windows</strong></summary>

```bash
flutter run -d windows --dart-define-from-file=config/dart_defines.json
```

</details>

### 4. SQLite na Web (WebAssembly)

Após o `flutter pub get` (e a cada atualização do pacote `sqflite_common_ffi_web`):

```bash
dart run sqflite_common_ffi_web:setup
```

> Os arquivos `web/sqlite3.wasm` e `web/sqflite_sw.js` precisam ser da **mesma versão** do pacote resolvido.

---

## 🛠️ Tecnologias

### Core

| Tecnologia | Uso | Versão |
|---|---|---|
| [Flutter](https://flutter.dev/) | Framework multiplataforma | ≥ 3.44 |
| [Dart](https://dart.dev/) | Linguagem principal | ≥ 3.13 |
| [Material 3](https://m3.material.io/) | Design system | — |

### Dependências Principais

| Pacote | Finalidade |
|---|---|
| [`http`](https://pub.dev/packages/http) | Requisições HTTP para a brapi.dev |
| [`sqflite`](https://pub.dev/packages/sqflite) | SQLite para Android/iOS |
| [`sqflite_common_ffi`](https://pub.dev/packages/sqflite_common_ffi) | SQLite para desktop (Windows/Linux/macOS) |
| [`sqflite_common_ffi_web`](https://pub.dev/packages/sqflite_common_ffi_web) | SQLite para Web via WebAssembly |
| [`fl_chart`](https://pub.dev/packages/fl_chart) | Gráficos de linha (histórico) e pizza (alocação) |
| [`crypto`](https://pub.dev/packages/crypto) | Hashing de senhas (PBKDF2-HMAC-SHA256) |
| [`intl`](https://pub.dev/packages/intl) | Formatação de moeda e datas (pt_BR) |
| [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) | Notificações locais de alerta de preço |
| [`flutter_localizations`](https://api.flutter.dev/flutter/flutter_localizations/flutter_localizations-library.html) | Localização dos controles padrão (pt_BR) |

### Infraestrutura

| Ferramenta | Descrição |
|---|---|
| **brapi.dev** | API de cotações da B3 |
| **Proxy local** (`tool/brapi_proxy.dart`) | Injeta token e resolve CORS para a Web |
| **GitHub Actions** (`.github/workflows/ci.yml`) | CI: analyse, testes e build Web |

---

## 🏗️ Arquitetura

### Visão Geral

O app segue uma arquitetura em camadas com separação clara de responsabilidades e gerenciamento de estado com `ChangeNotifier` (sem dependências externas de state management):

```
┌─────────────────────────────────────────────────────────────────┐
│                        🖼️  UI Layer                             │
│  Screens (AnimatedBuilder) ← observam estados via notifyListeners │
├─────────────────────────────────────────────────────────────────┤
│                      🧠 State Layer                             │
│  AppState (facade) → AuthState · MarketState · PortfolioState   │
│                      AlertState · SettingsState                 │
├─────────────────────────────────────────────────────────────────┤
│                    📦 Repository Layer                          │
│  QuoteRepository (cache SQLite com TTL de 5 min)                │
├─────────────────────────────────────────────────────────────────┤
│                     🔌 Service Layer                            │
│  BrapiService (HTTP, retry, rate-limit, fallback)               │
├─────────────────────────────────────────────────────────────────┤
│                    💾 Database Layer                             │
│  AppDatabase (SQLite multiplataforma)                           │
└─────────────────────────────────────────────────────────────────┘
```

### Fluxo de Dados

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

### Estrutura de Pastas

```
lib/
├── main.dart                          # Entry point
├── theme.dart                         # Tema Material 3 (claro/escuro)
│
├── database/                          # 💾 Persistência SQLite
│   ├── app_database.dart              # Schema, migrações, CRUD completo
│   ├── db_factory.dart                # Import condicional por plataforma
│   ├── db_factory_io.dart             # Fábrica nativa (arquivo)
│   └── db_factory_web.dart            # Fábrica Web (Wasm/IndexedDB)
│
├── models/                            # 📋 Modelos de dados
│   ├── stock.dart                     # Stock, PricePoint, TickerSuggestion, CachedQuote
│   ├── portfolio_item.dart            # PortfolioItem (posição na carteira)
│   ├── trade.dart                     # Trade, TradeType, summarizeTrades()
│   ├── price_alert.dart               # PriceAlert, AlertDirection
│   ├── market_data.dart               # CashDividend, CurrencyQuote, InflationIndicator
│   └── user_account.dart              # UserAccount
│
├── services/                          # 🔌 Serviços externos
│   ├── brapi_service.dart             # HTTP para brapi: cotações, dividendos, câmbio
│   ├── quote_repository.dart          # Cache com TTL, fallback para dado antigo
│   └── price_alert_notifications.dart # Notificações locais (Android/Windows/Web)
│
├── state/                             # 🧠 Gerenciamento de estado
│   ├── app_state.dart                 # Facade: coordena os sub-states
│   ├── auth_state.dart                # Sessão e inicialização
│   ├── market_state.dart              # Cotações, cache, qualidade dos dados
│   ├── portfolio_state.dart           # Favoritos, posições, operações, backup
│   ├── alert_state.dart               # Alertas de preço e avaliação
│   └── settings_state.dart            # Tema (sistema/claro/escuro)
│
├── screens/                           # 🖼️ Telas
│   ├── splash_screen.dart             # Splash com branding durante inicialização
│   ├── auth_screen.dart               # Login / Cadastro
│   ├── app_shell.dart                 # NavigationBar com 4 abas
│   ├── home_screen.dart               # Lista de ações, busca, alertas
│   ├── favorites_screen.dart          # Ações favoritas do usuário
│   ├── portfolio_screen.dart          # Carteira: posições, compra/venda, alocação
│   ├── stock_details_screen.dart      # Detalhes: gráfico, fundamentos, dividendos
│   ├── price_alerts_screen.dart       # Gestão de alertas de preço
│   ├── dividends_screen.dart          # Dividendos e JCP por ação
│   └── account_screen.dart            # Conta: backup, aparência, logout
│
├── widgets/                           # 🧩 Componentes reutilizáveis
│   ├── stock_tile.dart                # Card de ação (logo, preço, variação)
│   └── list_order_controls.dart       # Controles de ordenação e filtro
│
├── utils/                             # 🔧 Utilitários
│   ├── format.dart                    # Formatação de moeda/porcentagem
│   └── list_order.dart                # Lógica de ordenação das listas
│
└── security/                          # 🔒 Segurança
    ├── password_derivation.dart       # Import condicional
    ├── password_derivation_io.dart    # PBKDF2 com Isolate (nativo)
    └── password_derivation_web.dart   # PBKDF2 com Web Crypto API

tool/
├── brapi_proxy.dart                   # 🌐 Proxy local para Web (CORS + token)
├── platform_smoke.dart                # 🧪 Teste de validação por plataforma
└── generate_branding.py               # 🎨 Geração de ícones (Pillow)

config/
└── dart_defines.example.json          # Template de configuração do token
```

### Navegação

O app possui 4 abas principais no `NavigationBar`:

| Aba | Ícone | Tela | Descrição |
|---|---|---|---|
| **Início** | 📊 `candlestick_chart` | `HomeScreen` | Lista de cotações, busca de ações, alertas |
| **Favoritas** | ⭐ `star` | `FavoritesScreen` | Ações marcadas como favoritas |
| **Carteira** | 💼 `account_balance_wallet` | `PortfolioScreen` | Posições, compra/venda, alocação |
| **Conta** | 👤 `person` | `AccountScreen` | Backup, aparência, logout |

---

## 🌐 API & Endpoints

A brapi.dev é a fonte de todas as cotações. O app se comunica de forma diferente dependendo da plataforma:

| Plataforma | Comunicação | Base URL padrão |
|---|---|---|
| **Web** | Via proxy local | `http://localhost:8080/api` |
| **Android / Windows** | Direto à brapi | `https://brapi.dev/api` |

### Endpoints da brapi utilizados

#### 📊 `GET /api/quote/{ticker}` — Cotação

Endpoint principal para obter cotação, histórico e fundamentos de uma ação.

| Parâmetro | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `range` | query | Período do histórico | `5d`, `1mo`, `3mo`, `1y` |
| `interval` | query | Intervalo entre pontos | `1d` |
| `modules` | query | Dados extras | `defaultKeyStatistics,financialData` |
| `fundamental` | query | Incluir fundamentos | `true` |
| `dividends` | query | Incluir dividendos | `true` |

**Resposta consumida:**
```json
{
  "results": [{
    "symbol": "PETR4",
    "longName": "Petróleo Brasileiro S.A. - Petrobras",
    "regularMarketPrice": 36.54,
    "regularMarketChangePercent": 1.23,
    "logourl": "https://...",
    "currency": "BRL",
    "marketCap": 480000000000,
    "historicalDataPrice": [
      { "date": 1696118400, "close": 35.20 }
    ],
    "defaultKeyStatistics": {
      "dividendYield": 0.15,
      "trailingPE": 4.5,
      "priceToBook": 1.2,
      "profitMargins": 0.25
    },
    "financialData": {
      "totalDebt": 200000000000,
      "totalCash": 100000000000,
      "profitMargins": 0.25
    }
  }]
}
```

**Cadeia de tentativas (detalhes):**
| Tentativa | Parâmetros | Fallback |
|---|---|---|
| 1ª | `range` + `modules` + `fundamental` + `dividends` | se 401/403/404 → 2ª |
| 2ª | apenas `range` + `interval` | se 401/403/404 → 3ª |
| 3ª | sem parâmetros (cotação básica) | mostra "histórico indisponível" |

> Para em 429 (rate limit) ou falha de rede.

---

#### 🔍 `GET /api/quote/list` — Autocomplete

Busca de tickers por nome ou código.

| Parâmetro | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `search` | query | Termo de busca (min. 2 caracteres) | `PETR` |
| `limit` | query | Limite de resultados | `8` |

```json
{
  "stocks": [
    { "stock": "PETR4", "name": "Petróleo Brasileiro S.A.", "logo": "https://..." }
  ]
}
```

> Nunca lança exceção — retorna lista vazia em caso de falha.

---

#### 💰 `GET /api/v2/stocks/dividends` — Dividendos

Proventos em dinheiro (dividendos e JCP) por ação.

| Parâmetro | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `symbols` | query | Código da ação | `PETR4` |
| `sortBy` | query | Campo de ordenação | `paymentDate` |
| `sortOrder` | query | Direção | `desc` |

---

#### 💱 `GET /api/v2/currency` — Câmbio

Cotação de pares de moedas.

| Parâmetro | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `currency` | query | Pares separados por vírgula | `USD-BRL,EUR-BRL` |

> ⚠️ Acesso depende do plano da brapi. A interface dessa funcionalidade foi removida por limitação do plano gratuito.

---

#### 📊 `GET /api/v2/macro/latest` — Inflação

Indicadores macroeconômicos atuais.

| Parâmetro | Tipo | Descrição | Exemplo |
|---|---|---|---|
| `symbols` | query | Indicadores separados por vírgula | `ipca,ipca12m,igpm` |

> ⚠️ Mesma limitação de plano que o câmbio.

---

### 🔀 Proxy Local (`tool/brapi_proxy.dart`)

O proxy existe por dois motivos:
1. **Segurança**: o token da brapi nunca é compilado no Flutter Web
2. **CORS**: resolve as restrições de cross-origin

| Configuração | Variável de ambiente | Padrão |
|---|---|---|
| Token | `BRAPI_TOKEN` | — (obrigatório) |
| Host | `PROXY_HOST` | `127.0.0.1` |
| Porta | `PORT` | `8080` |
| Origens permitidas | `ALLOWED_ORIGINS` | `localhost` / `127.0.0.1` |
| Limite de requisições | `RATE_LIMIT` | `120 req/min por IP` |

**Rotas do proxy:**

| Método | Rota | Upstream | Descrição |
|---|---|---|---|
| `GET` | `/health` | — | Health check (`{"ok": true}`) |
| `GET` | `/api/quote/{ticker}` | `brapi.dev/api/quote/{ticker}` | Cotação |
| `GET` | `/api/v2/stocks/dividends` | `brapi.dev/api/v2/stocks/dividends` | Dividendos |
| `GET` | `/api/v2/currency` | `brapi.dev/api/v2/currency` | Câmbio |
| `GET` | `/api/v2/macro/latest` | `brapi.dev/api/v2/macro/latest` | Indicadores macro |
| `OPTIONS` | `*` | — | Preflight CORS |
| Qualquer outro | `*` | — | `404` / `405` |

**Fluxo:**
```
Flutter Web ── GET :8080/api/quote/PETR4?range=3mo ──► Proxy ── GET brapi.dev/api/quote/PETR4?range=3mo
                                                         │         (+ Authorization: Bearer <token>)
                                                         ◄── status + JSON ──────────────────────────┘
```

**Segurança do proxy:**
- Só repassa parâmetros de uma whitelist (`range`, `interval`, `modules`, `fundamental`, `dividends`, `search`, `limit`, etc.)
- Qualquer `token` enviado pelo cliente é **descartado**
- Ticker validado por regex (`^[A-Za-z0-9^.,\-]{1,64}$`)
- Rate limiting de 120 req/min por IP (janela fixa de 60s)
- CORS restrito a origens localhost
- Redirects não são seguidos
- Corpos de erro do upstream são substituídos por mensagem genérica
- Timeout de 15s para upstream

---

## 💾 Banco de Dados

### Schema (Versão 6)

SQLite com `PRAGMA foreign_keys = ON`. Migrações sequenciais `onUpgrade` (v1 → v2 → v3 → v4 → v5 → v6).

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│  users   │──1:N│  positions   │     │ quotes_cache │
│          │     │  (derivada)  │     │  (global)    │
│  id (PK) │     └──────────────┘     └──────────────┘
│  name    │
│  email   │──1:N┌──────────────┐     ┌──────────────┐
│  pass..  │     │  favorites   │     │ app_settings │
│  salt    │     └──────────────┘     │  (id=1)      │
│  created │                          └──────────────┘
│          │──1:N┌──────────────┐
│          │     │ transactions │
│          │     └──────────────┘
│          │
│          │──1:N┌──────────────┐     ┌──────────────┐
│          │     │ price_alerts │     │   sessions   │
│          │     └──────────────┘     │   (id=1)     │
│          │──1:1                     └──────────────┘
└──────────┘
```

### Tabelas

<details>
<summary><strong><code>users</code></strong> — Contas de usuário</summary>

| Coluna | Tipo | Restrições |
|---|---|---|
| `id` | INTEGER | PK AUTOINCREMENT |
| `name` | TEXT | — |
| `email` | TEXT | UNIQUE NOCASE |
| `password_hash` | TEXT | — |
| `password_salt` | TEXT | — |
| `created_at` | TEXT | ISO-8601 |

</details>

<details>
<summary><strong><code>transactions</code></strong> — Histórico de operações</summary>

| Coluna | Tipo | Restrições |
|---|---|---|
| `id` | INTEGER | PK AUTOINCREMENT |
| `user_id` | INTEGER | FK → `users` CASCADE |
| `symbol` | TEXT | Ticker em maiúsculas |
| `type` | TEXT | `buy` \| `sell` \| `adjust` |
| `quantity` | REAL | > 0 |
| `price` | REAL | ≥ 0 |
| `fees` | REAL | Padrão 0 |
| `executed_at` | TEXT | ISO-8601 UTC |

Índice: `idx_transactions_user_symbol (user_id, symbol, executed_at)`

</details>

<details>
<summary><strong><code>positions</code></strong> — Cache derivado de transactions</summary>

| Coluna | Tipo |
|---|---|
| `user_id` | INTEGER (PK composta) |
| `symbol` | TEXT (PK composta) |
| `quantity` | REAL |
| `average_price` | REAL |
| `purchased_at` | TEXT |

> Reconstruída por `_rebuildPosition` a cada operação, dentro da mesma transação SQL.

</details>

<details>
<summary><strong><code>favorites</code></strong> — Ações favoritas</summary>

| Coluna | Tipo |
|---|---|
| `user_id` | INTEGER (PK composta) |
| `symbol` | TEXT (PK composta) |

</details>

<details>
<summary><strong><code>price_alerts</code></strong> — Alertas de preço (v6)</summary>

| Coluna | Tipo | Descrição |
|---|---|---|
| `id` | INTEGER | PK AUTOINCREMENT |
| `user_id` | INTEGER | FK → `users` CASCADE |
| `symbol` | TEXT | Ticker |
| `direction` | TEXT | `above` \| `below` |
| `target` | REAL | Preço-alvo (positivo) |
| `created_at` | TEXT | UTC |
| `triggered_at` | TEXT | UTC (null se pendente) |

</details>

<details>
<summary><strong><code>sessions</code></strong> — Sessão ativa</summary>

| Coluna | Tipo | Restrições |
|---|---|---|
| `id` | INTEGER | CHECK = 1 |
| `user_id` | INTEGER | FK → `users` |

> Uma sessão por instalação/navegador.

</details>

<details>
<summary><strong><code>quotes_cache</code></strong> — Cache de cotações</summary>

| Coluna | Tipo |
|---|---|
| `symbol` | TEXT (PK) |
| `payload` | TEXT (JSON) |
| `fetched_at` | INTEGER (epoch ms) |

</details>

<details>
<summary><strong><code>app_settings</code></strong> — Preferências (v5)</summary>

| Coluna | Tipo | Valores |
|---|---|---|
| `id` | INTEGER | CHECK = 1 |
| `theme_mode` | TEXT | `system` \| `light` \| `dark` |

</details>

### Regras da Carteira

| Operação | Efeito |
|---|---|
| **Compra** (`buy`) | `PM = (qtd × PM + q × preço + taxas) / (qtd + q)` |
| **Venda** (`sell`) | `realizado += (preço − PM) × q − taxas`; PM inalterado; erro se `q > qtd` |
| **Ajuste** (`adjust`) | Substitui quantidade e PM; não altera o realizado |

> Posição que chega a zero é removida automaticamente.

---

## 🔐 Autenticação

Autenticação **100% local** — sem servidor, OAuth ou JWT.

| Aspecto | Implementação |
|---|---|
| **Hash** | PBKDF2-HMAC-SHA256 |
| **Salt** | Aleatório, 24 bytes |
| **Iterações** | 60.000 (nativo) / 20.000 (Web) |
| **Nativo** | `compute` em Isolate separado |
| **Web** | Web Crypto API assíncrona (requer HTTPS ou localhost) |
| **Formato** | `pbkdf2_sha256$<iterações>$<hex>` |
| **Rate limit** | 5 falhas em 60s → bloqueio temporário |

```
initialize() → db.getSession() → usuário? → _loadUserData() → refresh → AppShell
                                 └ não ────────────────────────────────→ AuthScreen
```

---

## ✨ Funcionalidades

### 📊 Cotações em Tempo Real
- Lista de ações da B3 com preço e variação
- Detalhes com gráfico de histórico (5d, 1m, 3m, 1y)
- Fundamentos: P/L, P/VP, Dividend Yield, Margem de Lucro
- Busca por código ou nome (autocomplete)

### ⭐ Favoritos
- Marcar/desmarcar ações como favoritas
- Atualização otimista com rollback em caso de falha
- Persistência por conta no SQLite

### 💼 Carteira Simulada
- Compra e venda com preço médio automático
- Cálculo de resultado realizado e não-realizado
- Gráfico de alocação (pizza)
- Histórico completo de operações
- Ajuste manual de posição

### 🔔 Alertas de Preço
- Alertas de alta (`above`) e queda (`below`)
- Disparo único ao receber cotação da rede
- Histórico de alertas no SQLite
- Notificações locais (Android, Windows, Web)
- Editar e rearmar para novo disparo

### 💰 Dividendos
- Proventos em dinheiro (dividendos + JCP) por ação
- Data-com, data ex e data de pagamento
- Dados direto da brapi.dev

### 🎨 Aparência
- Temas: Sistema, Claro e Escuro
- Preferência persistida por dispositivo (independente da conta)
- Material 3 com cores adaptativas
- Cor primária: `#6558F5` (roxo vibrante)

### 📤 Backup
- **Exportar**: JSON com favoritos, operações e alertas (sem senha)
- **Importar**: restaura os dados, substituindo favoritos e carteira
- Alertas: presentes no arquivo → substituem; ausentes → preservam os atuais

### 📋 Ordenação e Filtro
- **Início/Favoritas**: por código, preço ou variação
- **Carteira**: por código, valor da posição ou resultado percentual
- Filtro local por código/nome
- Totais e alocação usam a carteira completa

---

## 🧪 Testes

**184 testes** cobrindo todas as camadas do app.

```bash
# Rodar todos os testes
flutter test

# Análise estática
flutter analyze
```

| Arquivo | Cobertura |
|---|---|
| `trade_test.dart` | Preço médio, taxas, venda, realizado, ajuste, backup |
| `stock_test.dart` | `Stock.fromJson`, histórico, cache map |
| `app_database_test.dart` | Registro, login, sessão, e-mail duplicado, hash legado, carteira, rollback, backup, cache, migração |
| `brapi_service_test.dart` | Parse, falhas tipadas, 429 + backoff, abort de lote, concorrência, fallback, autocomplete |
| `quote_repository_test.dart` | TTL, forceRefresh, dado antigo em falha, falha parcial |
| `app_state_test.dart` | Fluxos de registro, sessão, favoritos, compra/venda, backup |
| `login_security_test.dart` | PBKDF2, concorrência, expiração, migração, hashes fortes |
| `alert_database_test.dart` | Migração, CRUD por conta, backup, concorrência |
| `alert_state_test.dart` | Cache vs rede, sessão, descarte |
| `brapi_proxy_test.dart` | Rotas, CORS, rate limit, parâmetros |
| `theme_settings_test.dart` | Persistência, migração, concorrência |
| `state_boundaries_test.dart` | Notificações por domínio, respostas antigas, descarte |
| `ui_flows_test.dart` | Venda/histórico/alocação, cache, falhas, rollback, backup |
| `list_order_test.dart` | Ordens, desempates, cópias, filtro |
| `market_data_service_test.dart` | Dividendos, câmbio, inflação |
| `splash_screen_test.dart` | Espera pelo tema/sessão, layout |
| `dark_theme_ui_test.dart` | UI no tema escuro |
| `localization_ui_test.dart` | Locale pt_BR, botão Voltar |
| E mais... | Notificações, detalhes, permissões |

### Smoke Test por Plataforma

```bash
# Windows
flutter run -d windows --release -t tool/platform_smoke.dart

# Android
flutter run -d <emulador> -t tool/platform_smoke.dart
```

> Cria banco exclusivo, testa cadastro/login/sessão/carteira/backup e emite `BOLSA_PLATFORM_SMOKE: PASS` ou `FAIL`. Nunca altera o banco principal.

---

## 🔄 CI/CD

O GitHub Actions (`.github/workflows/ci.yml`) executa em cada push/PR:

```yaml
steps:
  - flutter pub get
  - flutter analyze       # Análise estática
  - flutter test           # 184 testes unitários e de widget
  - flutter build web      # Verifica compilação Web
```

---

## ⚙️ Configurações Avançadas

### Variáveis de Ambiente do Proxy

| Variável | Descrição | Padrão |
|---|---|---|
| `BRAPI_TOKEN` | Token da brapi.dev | — |
| `PROXY_HOST` | Interface de escuta | `127.0.0.1` |
| `PORT` | Porta do proxy | `8080` |
| `ALLOWED_ORIGINS` | Origens CORS (vírgula) | `localhost`, `127.0.0.1` |
| `RATE_LIMIT` | Requisições/min por IP | `120` |

### Dart Defines

| Define | Descrição | Usado em |
|---|---|---|
| `BRAPI_BASE_URL` | URL base da API (inclui `/api`) | Web e nativo |
| `BRAPI_TOKEN` | Token da brapi | Apenas nativo |

### Script `run_web.ps1`

```powershell
# Porta padrão do proxy: 8081
.\run_web.ps1

# Porta personalizada
.\run_web.ps1 -ProxyPort 8082
```

O script:
1. Inicia o proxy em background
2. Aguarda o health check (`/health`)
3. Abre o Flutter Web no Chrome (`--web-port 3000`)
4. Encerra o proxy ao fechar o app

---

## ⚠️ Limitações Conhecidas

| Limitação | Detalhe |
|---|---|
| **Sem sincronização em nuvem** | Dados do usuário são 100% locais; a rede é usada apenas para cotações |
| **Dados presos ao dispositivo** | Nativo: desinstalar apaga. Web: preso ao IndexedDB da origem + perfil. Mitigação: backup |
| **Autenticação local** | Protege entre usuários do mesmo aparelho, mas quem acessa o arquivo do banco acessa os dados |
| **Cotações exigem rede** | Cache de 5 min apenas dos campos básicos (sem histórico) |
| **Plano gratuito da brapi** | 1 ticker por requisição e cotas limitadas |
| **Alertas sem background** | Avaliados apenas enquanto o app está aberto |
| **Proxy rate limit em memória** | Reseta ao reiniciar o proxy |

---

## 📜 Licença

Este projeto é de uso privado.

---

<p align="center">
  Feito com 💜 usando Flutter
</p>
