# Bolsa Fácil

Aplicativo Flutter para acompanhar ações da B3 (cotações da [brapi.dev](https://brapi.dev/)), favoritar ativos e simular uma carteira com compras, vendas e histórico. Os dados do usuário ficam em SQLite local (no navegador, na Web).

Documentação: [`TECHNICAL_DOCS.md`](TECHNICAL_DOCS.md) · Mudanças desta versão: [`MELHORIAS.md`](MELHORIAS.md) · Continuação do trabalho: [`docs/HANDOFF_CODEX.md`](docs/HANDOFF_CODEX.md)

## Requisitos

- Flutter compatível com o lock: >=3.44 e Dart >=3.13 (ambiente verificado: Flutter 3.47.5 / Dart 3.13.4)
- Token gratuito da brapi: <https://brapi.dev/dashboard>

## Configuração do token

| Plataforma | Onde configurar |
|---|---|
| Web | `.env` na raiz (`cp .env.example .env`). Lido **só pelo proxy**; nunca vai ao navegador |
| Android / Windows | `config/dart_defines.json` (copie de `config/dart_defines.example.json`) |

## Executar

```bash
flutter pub get

# Web (precisa do proxy): terminal 1
dart run tool/brapi_proxy.dart
# terminal 2
flutter run -d chrome --web-port 3000
# (Windows: .\run_web.ps1 faz os dois passos)

# Android / Windows (chama a brapi direto)
flutter run --dart-define-from-file=config/dart_defines.json
```

### SQLite na Web (WebAssembly)

A Web usa `sqflite_common_ffi_web`. Os arquivos `web/sqlite3.wasm` e `web/sqflite_sw.js` precisam ser da **mesma versão** do pacote resolvido. Depois de `flutter pub get` (e a cada atualização do pacote), rode:

```bash
dart run sqflite_common_ffi_web:setup
```

## Testes e análise

```bash
flutter analyze
flutter test
```

O CI (`.github/workflows/ci.yml`) roda análise, testes e `flutter build web`.

## Proxy (`tool/brapi_proxy.dart`)

Só encaminha `GET /api/quote/{ticker}` para a brapi, injetando o token. Escuta em `127.0.0.1:8080` por padrão, aceita CORS apenas de `localhost`/`127.0.0.1` e limita 120 req/min por IP. Variáveis: `BRAPI_TOKEN`, `PROXY_HOST`, `PORT`, `ALLOWED_ORIGINS`, `RATE_LIMIT`.

## Backup

Conta → **Exportar backup** copia um JSON (favoritos, operações e alertas, sem senha). **Importar backup** o restaura, substituindo favoritos e carteira. Alertas também são substituídos quando presentes no arquivo; backups antigos sem alertas preservam os existentes.

## Listas

Início e Favoritas ordenam por código, preço ou variação. Carteira ordena por código, valor da posição ou resultado percentual. **Filtrar lista** encontra código/nome entre os itens já carregados. O filtro da carteira mantém os totais e a alocação completos. A busca de ações no Início continua separada.

## Aparência

Conta → **Aparência** oferece Sistema, Claro e Escuro. A escolha fica no SQLite deste dispositivo/navegador e permanece ao sair da conta.

## Ambiente verificado e validação

Validado com Flutter 3.47.5 / Dart 3.13.4. As dependências do lock exigem Flutter >=3.44 e Dart >=3.13. Consulte `TECHNICAL_DOCS.md` e `docs/HANDOFF_CODEX.md` para os resultados e pendências.

No Windows, `./run_web.ps1` usa proxy em 8081; outra porta pode ser escolhida com `./run_web.ps1 -ProxyPort 8082`. O script passa a URL correta ao Flutter e não encerra proxies de outros projetos. A base padrão do serviço continua em 8080 para execução manual; use o mesmo `BRAPI_BASE_URL` do proxy quando escolher outra porta.

```powershell
flutter analyze
flutter test
flutter run -d windows --release -t tool/platform_smoke.dart
```

A verificação de plataforma usa banco descartável e confirma SQLite/sessão/carteira/backup. Não lê nem altera o banco principal.

## Alertas de preço

Início → **Alertas** ou detalhes do ativo → **Criar alerta**. Escolha um alvo de alta ou queda. Cada alerta dispara uma vez ao receber uma cotação da rede com o app aberto; editar e rearmar permite outro disparo. O histórico fica no SQLite da conta, inclusive após recarregar a página.

**Ativar notificações** solicita a permissão do sistema. O histórico funciona mesmo com permissão negada. Não há monitoramento em segundo plano. Notificações Web dependem de contexto seguro e suporte do navegador; Android e Windows usam notificações locais.
