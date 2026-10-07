# Handoff para o Codex — Bolsa Fácil

## Contexto

Aplicativo Flutter (Dart 3) para acompanhar ações da B3 via [brapi.dev](https://brapi.dev/), com favoritos e carteira simulada (compra, venda, histórico, lucro realizado, backup JSON). SQLite local em todas as plataformas (nativo: arquivo; Web: Wasm no navegador). Proxy Dart (`tool/brapi_proxy.dart`) só para a Web.

**Restrições:** manter Flutter, brapi e SQLite. UI e mensagens em português do Brasil. Nunca commitar `.env` nem `config/dart_defines.json`. Sem `kIsWeb` no `AppState` (diferenças de plataforma ficam em `lib/database/db_factory*.dart` e `BrapiService`).

Leia, nesta ordem: `TECHNICAL_DOCS.md` (arquitetura atual), `MELHORIAS.md` (o que mudou).

## Estado atual — verificado em 06/10/2026

Atualização em 07/10/2026: seção Câmbio/Inflação removida da interface por indisponibilidade no plano utilizado. `flutter analyze` sem problemas e 180 testes passaram; quatro testes exclusivos da tela removida foram retirados. Nenhum build ou teste manual de plataforma foi repetido nesta alteração.

| Verificação | Resultado |
|---|---|
| `flutter pub get` e setup SQLite Web | passaram (`sqflite_common_ffi_web 1.2.0`) |
| `flutter analyze` | No issues found |
| `flutter test` | 184 testes passaram |
| Build Web release (base 8080 e 8081) | passou |
| Web em uso real | cadastro, favorito, compra/venda/histórico, F5 com sessão/carteira e cache sem proxy passaram |
| Autocomplete na API real | `stocks[].stock/name/logo` confirmado; `/v2/tickers` também respondeu, mas o endpoint atual foi mantido |
| Proxy com curl (8081) | health/cotação/autocomplete 200, rota 404, POST 405, origem proibida 403 |
| Windows release / APK Android debug | builds passaram |
| SQLite Windows e Android | `tool/platform_smoke.dart`: sessão, favoritos, operações, resultado realizado, backup, login, tema e alertas do schema v6 passaram |
| Alertas Web | criação, disparo com cotação real e histórico após F5 passaram; permissão do sistema não concedida no teste |
| Migração v1 real | cópia do banco v1 local migrada até v6 e testada; original preservado |

## Verificações iniciais e correções

A v2 anexada foi incorporada ao checkout com autorização do usuário, preservando `.git`, `.env` e os wireframes previamente staged. O ZIP tinha 57 testes ao executar; o relato de 53 era anterior. Foram acrescentados quatro testes de UI e um de migração legada.

- Fábricas antigas sem consumidores foram removidas para manter analyze limpo.
- Schema v3 converte `session(slot)` da versão original em `sessions(id)` durante o upgrade. Teste sintético valida posições/histórico, e teste com uma cópia do banco v1 real valida integridade e preservação de conta/sessão.
- Importação de backup corrigida: o controller pertence a um diálogo StatefulWidget e é descartado após a rota sair, evitando uso após dispose.
- Android corrigido para AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14. Builds passam com avisos de atualização futura, sem bypass de validação.
- A porta 8080 pertence a outro serviço. `run_web.ps1` usa 8081 (ou `-ProxyPort`) e passa a mesma base ao Flutter; readiness e cleanup de processo próprio foram verificados. O proxy usa somente bibliotecas padrão, então o script inicia a VM sem build hooks desnecessários de SQLite.

**Limite da verificação:** o smoke nativo testa a implementação SQLite real e dados; não foi feita revisão visual completa das telas Android/Windows. Os fluxos de UI foram exercitados em widgets e no Web. O banco real disponível tinha uma conta e nenhuma posição; a preservação de posições é coberta pelo banco legado sintético.

Comandos do smoke e da migração real estão em `TECHNICAL_DOCS.md`. Segurança, detalhes, divisão de estados, tema e ordenação/filtro concluídos. Dados adicionais implementados; validações finais estão registradas abaixo.

## Estado das pendências de produto

1. **Concluída:** estados Auth/Market/Portfolio com facade compatível e injeção por construtor. Quatorze testes de limites e concorrência; sem dependência adicional.
2. **Concluída:** temas Sistema/Claro/Escuro com preferência SQLite (schema v5), cores adaptadas e Conta rolável.
3. **Concluída:** alertas por conta, histórico persistente e notificações locais com permissão explícita; schema v6 e testes de migração/concorrência. Avaliação somente com o app aberto.
4. **Concluída:** ordenação e filtro local em Início/Favoritas/Carteira, preservando totais/alocação.
5. **Concluída:** dividendos/JCP com contratos v2 e consultas por demanda. Em 07/10/2026, o botão e a tela de Câmbio/Inflação foram removidos por falta de acesso no plano utilizado (403 com o token atual). Contratos internos e testes de serviço foram preservados.
6. **Concluída:** PBKDF2 em isolate nativo / Web Crypto; schema v4 limita cinco falhas de login por 60 segundos. Migração e concorrência cobertas por testes; conta Web existente compatível.
7. **Concluída:** detalhes atualizam `AppState.stocks`; seis testes de concorrência, erros e ciclo de vida.
8. **Concluída:** testes de widget de tema, listas, alertas e dados adicionais.

## Regras para continuar

- Rode `flutter analyze` e `flutter test` a cada mudança; não deixe vermelho.
- Mudou o schema? Suba `AppDatabase.schemaVersion`, escreva `onUpgrade` e um teste de migração (modelo: o de v1→v2 em `test/app_database_test.dart`).
- O ambiente do autor é Windows (arquivos com CRLF): ao gerar patches, prefira editar arquivos direto a `git apply`.
- Atualize `TECHNICAL_DOCS.md` e `MELHORIAS.md` quando algo mudar.
- Commits pequenos, mensagens em português.

## Ordem sugerida

1. Verificações iniciais acima concluídas; repetir as afetadas por cada mudança.
2. Pendência 6 (segurança do login) e 7 (detalhes).
3. Pendência 1 (dividir o `AppState`), mantendo os testes verdes.
4. Pendências 2, 4, 3 e 5, nessa ordem.

## Prompt sugerido para colar no Codex

> Leia `AGENTS.md`, `docs/HANDOFF_CODEX.md`, `TECHNICAL_DOCS.md` e `MELHORIAS.md`. O projeto está com `flutter analyze` limpo e 184 testes passando. Confira o estado verificado e as limitações do handoff. Repita as verificações afetadas por alterações e corrija falhas com regressões quando possível. Mantenha Flutter + brapi + SQLite, UI em português, e rode analyze e test a cada mudança.
