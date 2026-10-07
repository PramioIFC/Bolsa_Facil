# Dividendos, câmbio e inflação — 06/10/2026

- Telas de proventos informados por ação e Câmbio/Inflação, com carregamento por tela/aba, vazio, erro e nova tentativa.
- Contratos v2 com validação de valores finitos, números como texto e datas nulas; macro/latest substitui a API legada de inflação.
- Proxy permite somente novas rotas exatas e seus parâmetros; bloqueia redirects e protege conteúdo dos erros.
- Trinta e três testes acrescentados: 16 de contratos, nove HTTP locais do proxy e oito de widgets. Analyze limpo e 183 testes passaram.
- Builds Web/Windows/Android passaram. SQLite schema v6 passou nos dois smokes nativos e na migração de uma cópia v1 real.
- API real: PETR4 retornou 176 proventos; câmbio e inflação negaram acesso com HTTP 403 usando o token atual.

# Alertas de preço

- Alertas por conta com alvo de alta/queda, edição para rearmar e histórico persistente.
- Schema v6 aditivo; migração, isolamento por usuário e backup antigo/novo cobertos por testes.
- Cotações de cache não acionam alertas; somente rede. Atualização condicional evita duplicatas; respostas atrasadas não sobrescrevem edição/exclusão nem notificam após logout.
- Notificações locais Android/Windows/Web, com permissão explícita. Disparo permanece no histórico se o sistema negar ou falhar. Avaliação com o app aberto, sem agendamento em segundo plano.
- Trinta e sete testes acrescentados; analyze limpo e 150 testes passaram.

# Ordenação e filtros

- Listas ordenadas por código, preço/variação ou valor/resultado da posição; desempate por código, sem mutar o estado global.
- Filtro por código/nome; totais e alocação continuam usando a carteira inteira.
- Sem resultados e favoritos com cotação indisponível têm mensagens próprias.
- Dez testes acrescentados; analyze limpo e 113 testes passaram.

# Tema claro, escuro e do sistema

- Seletor de aparência na Conta; preferência global persiste entre sessões. Build Web e escolha Escuro após F5 verificados no navegador.
- Cores das telas e gráficos seguem o tema, e Conta é rolável.
- Schema v5 aditivo com teste de migração preservando carteira e segurança do login. Analyze limpo e 103 testes passando.
- Teste em viewport estreito revelou overflow no cabeçalho da Home; corrigido com largura flexível e quebra natural.

# Estados separados

- Autenticação, mercado e carteira têm notificações independentes; telas observam os domínios necessários.
- Respostas antigas e rollbacks não publicam em outra sessão nem após descarte.
- Operações de autenticação serializadas mantêm SQLite e UI consistentes; dados do usuário carregam antes de liberar a Home.
- Quatorze testes de limites e concorrência acrescentados; 90 no total.

# Cotações dos detalhes

- Abrir detalhes ou trocar período atualiza a cotação nas listas sem duplicar ativos.
- Respostas antigas, de sessão encerrada ou de estado descartado não sobrescrevem dados.
- Seis testes de regressão; total de 76.

# Segurança do login — 05/10/2026

- PBKDF2 em isolate nativo e Web Crypto; compatibilidade com hashes existentes e sem reduzir hashes mais fortes.
- Schema v4: limite persistente de cinco falhas de login por 60 segundos, com serialização de tentativas concorrentes.
- Oito testes acrescentados (70 no total); login Web com conta existente e build Web passaram.

# Verificações e correções locais — 05/10/2026

- V2 incorporada preservando `.git`, `.env` e wireframes preparados anteriormente.
- Analyze limpo, 62 testes passando; builds Web, Windows e Android concluídos.
- SQLite Wasm: sessão, favoritos e carteira persistem após F5; cache funciona sem proxy.
- API real e proxy verificados; autocomplete usa o contrato observado em `/quote/list`.
- Schema v3 corrige migração da sessão `session(slot)` da versão original; teste sintético e cópia do banco real passaram.
- Importação corrigida: controller pertence ao ciclo de vida do diálogo, evitando uso após descarte.
- Quatro testes de widget cobrem fluxos novos e rollback de favorito.
- Fábricas de banco antigas sem consumidores removidas; SQLite Web regenerado.
- Android corrigido para os mínimos do Flutter instalado; sem ignorar validações.
- Script Web aceita porta configurável (8081 padrão) e encerra apenas os processos que criou.
- Smoke SQLite Windows e Android passaram. Pendências de produto abaixo ainda não implementadas.

# Registro histórico da v2 anexada (branch original `melhorias`)

Legenda: ✅ implementado (não executado) · 🟡 parcial · ⬜ não feito.

> **Verificado:** `flutter analyze` sem avisos e `flutter test` com 53 testes passando (rodados pelo autor no Windows). **Não verificado:** `flutter build web`, execução manual do app, autocomplete na API real, SQLite Wasm no navegador. Itens marcados ✅ significam "implementado e coberto por teste quando aplicável", não "validado em uso real".

## 1. Corrigir o que estava quebrado ou arriscado

| Item | Estado | Onde |
|---|---|---|
| Registro sobrescrevia conta existente | ✅ agora recusa com `AuthException` | `AppDatabase.register` |
| `AppDatabase` injetável (fábrica + nome) e testes consertados | ✅ | `app_database.dart`, `test/` |
| Hash de senha: SHA-256 simples → PBKDF2-HMAC-SHA256 (60k iterações), com migração dos hashes antigos no login | ✅ | `app_database.dart` |
| Proxy: loopback, só `GET /api/quote/*`, allowlist de parâmetros, CORS restrito, rate limit por IP, sem `/auth` e `/data` | ✅ | `tool/brapi_proxy.dart` |
| Falhas silenciosas na Web (`ApiService` sem checar status) | ✅ eliminado: `ApiService` foi removido (item 2) | — |
| Favorito sem rollback | ✅ rollback + SnackBar | `AppState.toggleFavorite`, `AppShell` |
| Token da brapi na query string (nativo) | ✅ agora só no header `Authorization` | `BrapiService` |

## 2. Unificar a persistência

| Item | Estado | Onde |
|---|---|---|
| Web com SQLite em Wasm (`sqflite_common_ffi_web`) e o mesmo `AppDatabase` em todas as plataformas | ✅ | `lib/database/db_factory*.dart`, `main.dart` |
| Remoção de `ApiService`, rotas `/auth` e `/data` do proxy, `kIsWeb` do `AppState`, `shared_preferences` | ✅ | — |
| Windows/Linux/macOS: inicialização FFI | ✅ | `db_factory_io.dart` |

## 3. Usar melhor a brapi

| Item | Estado | Onde |
|---|---|---|
| Cache de cotações no SQLite com TTL (5 min) e dado antigo como fallback | ✅ | `QuoteRepository`, tabela `quotes_cache` |
| Consultas em paralelo (3) e backoff em HTTP 429 | ✅ | `BrapiService.fetchQuotes/fetchQuote` |
| Distinguir 429 / 401 / 404 / rede | ✅ `QuoteFailure` | `brapi_service.dart` |
| Avisar quando um ticker falha e mostrar "atualizado às…" | ✅ | `home_screen.dart` |
| Autocomplete de tickers | ✅ `/api/quote/list?search=` confirmado na API real em 05/10/2026 | `searchTickers`, `home_screen.dart` |
| Novas telas com dividendos/câmbio/inflação | ⬜ | — |

## 4. Modelo de dados

| Item | Estado | Onde |
|---|---|---|
| Migrations (`onUpgrade` v1 → v2) | ✅ | `AppDatabase._open` |
| Tabela `transactions` (compra/venda/ajuste, taxas); posição derivada; lucro realizado | ✅ | `trade.dart`, `AppDatabase` |
| Tela: vender, histórico por ativo, resultado realizado | ✅ | `portfolio_screen.dart` |
| Índices | ✅ só em `transactions`; `positions`/`favorites` já são cobertas pela PK composta | — |
| Exportar/importar JSON | ✅ via área de transferência (sem dependência nova) | Conta |

## 5. Arquitetura

| Item | Estado |
|---|---|
| Repositório de cotações entre estado e fonte | ✅ `QuoteRepository` |
| Tela de detalhes passa pelo `AppState` | ✅ `loadQuote` |
| Dividir `AppState` | ✅ estados Auth/Market/Portfolio, facade compatível, injeção por construtor sem nova dependência |

## 6. Produto e experiência

| Item | Estado |
|---|---|
| Formatação pt-BR com `intl` | ✅ `lib/utils/format.dart` |
| Gráfico de alocação (pizza) e rentabilidade (% por ativo) | ✅ |
| Tema escuro | ✅ Sistema/Claro/Escuro na Conta; escolha persistente no SQLite, schema v5 |
| Alertas de preço-alvo | ⬜ |
| Ordenação/filtro nas listas | ✅ controles no Início, Favoritas e Carteira; filtro local preserva totais/alocação |

## 7. Qualidade contínua

| Item | Estado |
|---|---|
| CI (analyze + test + build web) | ✅ `.github/workflows/ci.yml` |
| Testes novos (trade, stock, banco, brapi, repositório, estado) | ✅ 53 passando |
| `--dart-define-from-file` | ✅ `config/dart_defines.example.json` |
| Limpeza de arquivos sem uso (`sqlite3.wasm`/`sqflite_sw.js` agora são usados) | ✅ |

## Mudanças de comportamento que o usuário percebe

- Contas criadas **no proxy** pela versão antiga da Web **não migram**: a Web agora guarda tudo no navegador. É preciso recriar a conta (ou usar backup, se houver).
- "Remover" uma posição agora também apaga o histórico de operações dela.
- Editar uma posição manualmente registra um `ajuste` no histórico.
- Pull-to-refresh ignora o cache; abrir o app/logar usa o cache de até 5 min.
