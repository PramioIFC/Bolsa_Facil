# Integrações do Bolsa Fácil

Mapa da implementação atual, verificado em `lib/services/brapi_service.dart`, `lib/state/app_state.dart`, `lib/models/stock.dart`, `lib/database/app_database.dart` e `tool/brapi_proxy.dart`. Os valores no wireframe são ilustrativos. Este documento descreve o código do projeto, sem presumir novos endpoints ou garantias atuais do provedor.

## Bases e autenticação

- Flutter Web: `http://localhost:8081/api` por padrão.
- Proxy encaminha o mesmo caminho e parâmetros para `https://brapi.dev`, adicionando `Authorization: Bearer <BRAPI_TOKEN>` no servidor.
- Nativo: `https://brapi.dev/api` por padrão; o serviço usa a configuração `BRAPI_TOKEN` no header e no parâmetro `token` quando preenchida. Não incluir credenciais em exemplos ou artefatos.
- `BRAPI_BASE_URL` substitui a base em qualquer plataforma.
- O cliente envia `Accept: application/json`. O proxy responde ao preflight `OPTIONS` com 204; isso é suporte de transporte, não uma integração de negócio.

## Endpoints consultados

| Tela / gatilho | Método e caminho relativo à base | Observação |
|---|---|---|
| Login, cadastro ou sessão restaurada | `GET /quote/{ticker}` | Após autenticação local, `refresh()` carrega cotações. |
| Início / atualização | `GET /quote/{ticker}` | Uma requisição por ticker, executadas em paralelo. |
| Busca de ticker fora do cache | `GET /quote/{ticker}?range=3mo&interval=1d` | Normaliza espaços e maiúsculas. Busca em cache não faz HTTP. |
| Abrir detalhes, inclusive por favorita ou carteira | `GET /quote/{ticker}?range=3mo&interval=1d` | Detalhes sempre carregam o histórico ao abrir. Busca fora do cache seguida de abertura pode fazer duas consultas. |
| Histórico de 5 dias | `GET /quote/{ticker}?range=5d&interval=1d` | Troca de período faz nova consulta. |
| Histórico de 1 mês | `GET /quote/{ticker}?range=1mo&interval=1d` | Mesmo contrato. |
| Histórico de 3 meses | `GET /quote/{ticker}?range=3mo&interval=1d` | Período inicial. |
| Histórico de 1 ano | `GET /quote/{ticker}?range=1y&interval=1d` | Mesmo contrato. |
| Atualizar favoritas | `GET /quote/{ticker}` | Usa `refresh()`, consultando o conjunto completo. Entrar na aba usa cache. |
| Salvar posição de ticker ausente do cache | `GET /quote/{ticker}` | Depois da gravação local, `refresh()` consulta o conjunto completo. |

Exemplo Web: `GET http://localhost:8081/api/quote/PETR4?range=3mo&interval=1d`.

Conjunto de `refresh()`: união sem duplicatas de `PETR4`, `VALE3`, `ITUB4`, `BBDC4`, `ABEV3`, `WEGE3`, `BBAS3`, `MGLU3`, favoritas e tickers da carteira. O cliente atual não consulta `/quote/list`, não usa paginação e não consulta indicadores de índice.

## Campos consumidos

Resposta esperada pelo cliente: objeto com `results`, uma lista de ações. O serviço individual usa a primeira ação retornada.

| Campo em `results[]` | Uso visual |
|---|---|
| `symbol` | Ticker na lista, busca e detalhes |
| `longName` ou `shortName` | Nome da empresa |
| `regularMarketPrice` | Cotação, total da compra e valor da posição |
| `regularMarketChangePercent` | Variação percentual positiva / negativa |
| `logourl` | Logo da ação no app; iniciais ilustrativas no wireframe |
| `currency` | Moeda nos detalhes, padrão `BRL` |
| `marketCap` | Valor de mercado; ausência exibe travessão |
| `historicalDataPrice[].date` | Data Unix em segundos, convertida para data |
| `historicalDataPrice[].close` | Fechamento para o gráfico; valores não positivos são filtrados |

## Operações locais — sem endpoints HTTP

| Tela / ação | Método no projeto | Persistência / resultado |
|---|---|---|
| Cadastro | `database.register(name, email, password)` | `users` e `session`; depois carrega dados e cotações |
| Login | `database.login(email, password)` | Validação local e `session`; depois carrega dados e cotações |
| Inicialização / conta | `database.restoreSession()` / `currentUser` | Sessão e perfil locais |
| Sair | `database.logout()` | Apaga sessão; limpa estado em memória |
| Ler favoritas | `database.favoritesFor(userId)` | Tabela `favorites` por conta |
| Marcar / desmarcar | `database.setFavorite(userId, symbol, enabled)` | Favoritas locais; não chama brapi |
| Ler carteira | `database.positionsFor(userId)` | Tabela `positions` por conta |
| Compra simulada | `AppState.buy(symbol, quantity, price)` | Acumula quantidade, recalcula preço médio ponderado e chama `savePosition` |
| Adicionar / editar posição | `database.savePosition(userId, item)` | Quantidade e preço médio locais; edição mantém ticker |
| Remover posição | `database.removePosition(userId, symbol)` | Remove posição local |

Não existem endpoints `/login`, `/register`, `/favorites`, `/portfolio` ou `/orders` neste projeto. A compra é educacional, sem envio de ordem real. Contas não são sincronizadas entre dispositivos.

Carteira: investido = quantidade × preço médio; atual = quantidade × cotação em cache, ou preço médio quando falta cotação; resultado = atual − investido. Abrir carteira não dispara uma atualização de mercado por si só.

## Estados observáveis

- Início: spinner durante carga inicial; falha sem ações mostra mensagem e “Tentar novamente”. Atualizar usa `refresh()`.
- Consulta individual com status diferente de 200 ou `http.ClientException` retorna ausência; `getQuote()` converte isso em “Ação não encontrada”.
- Lista: respostas individuais indisponíveis são descartadas; todas indisponíveis geram erro. Não há badge de falha parcial no app atual.
- Detalhes: indicador de carregamento e chips desativados durante consulta; sem histórico, a área mostra carregamento ou mensagem de erro conforme o estado atual. Não há botão dedicado de retry nessa tela.
- Autenticação: valida nome, e-mail e senha; mostra erro e desativa envio durante processamento.
- Favoritas / carteira: mensagem de lista vazia. Compra: botão desativado para quantidade inválida e feedback de sucesso.
- A prancha de estados usa skeleton como proposta visual para a carga, em lugar do spinner atual. As demais telas representam a estrutura atual com ajustes de composição para apresentação.
