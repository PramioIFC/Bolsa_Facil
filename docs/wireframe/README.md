# Wireframe de alta fidelidade

Abra [index.html](index.html) no navegador. Funciona offline, sem dependências, token ou execução do Flutter.

Entregáveis:

- `index.html`: protótipo navegável, com contrato de integração ao lado da tela, navegação por teclado e adaptação à largura do navegador.
- `bolsa-facil-prancha.svg`: prancha com nove telas, em três colunas, para apresentação e importação no Figma.
- `login.svg`, `register.svg`, `home.svg`, `details.svg`, `favorites.svg`, `portfolio.svg`, `position.svg`, `account.svg`, `states.svg`: telas individuais em 390 × 844 px.
- `ENDPOINTS.md`: mapa de endpoints, gatilhos, campos consumidos e operações SQLite.
- `build.cjs`: fonte única dos SVGs e HTML. Regenerar com `node docs/wireframe/build.cjs` na raiz do projeto.
- `verify.cjs`: valida sintaxe do JavaScript do protótipo, telas, destinos e links. Execute `node docs/wireframe/verify.cjs`.

## Fluxos para explorar

1. Entrar ou criar conta → Início → ação → detalhes → alterar período → comprar.
2. Abas Favoritas, Carteira e Conta; estrela demonstra a alternância de favorita.
3. Carteira → Adicionar / editar → Salvar → Carteira.
4. Conta → Sair → Entrar.
5. Estados → Tentar novamente → Início.

O seletor de ticker no painel demonstra o endpoint de cada ação. Na tela de detalhes, clique em Quantidade para mudar o total da compra. Login, cadastro, busca, compra e edição são demonstrações: não validam credenciais, não consultam rede e não persistem alterações. Os campos nas telas SVG são desenhos, não formulários. O feedback informa explicitamente a simulação; salvar ou comprar não modifica as posições ilustrativas da carteira. A alternância de estrela é uma demonstração global, não uma lista de favoritas persistente por ticker. Gráfico e variações são exemplos visuais fixos, mesmo ao trocar ticker ou período.

## Importar no Figma

Arraste `bolsa-facil-prancha.svg` ou os SVGs individuais para o canvas do Figma. Os arquivos usam vetores e texto, sem imagens externas ou `foreignObject`. Desagrupe conforme necessário para editar. Isso entrega elementos vetoriais editáveis; não cria automaticamente componentes, auto layout ou conexões do protótipo no Figma. A navegação pronta está no HTML.

## Referência e escopo visual

Baseado nos widgets e no tema do repositório: roxo `#6558F5`, fundo `#F7F8FC`, texto `#172039`, cards arredondados e navegação inferior. Conteúdo e números são fictícios. Cores de textos positivos/negativos foram escurecidas para legibilidade. As telas foram compostas a partir do código, não são prints do app executado. Nenhum código de produção foi alterado.

O desenho cobre as telas e operações atuais. Na prancha de estados, o skeleton é uma proposta visual; hoje o app usa spinner. Não foram acrescentados endpoints de autenticação ou carteira que o projeto não possui.

## Verificação desta entrega

Validados: geração dos arquivos, sintaxe do gerador e do JavaScript incorporado, nove telas, destinos de navegação, links locais, XML dos dez SVGs e `git diff --check`. A revisão visual e a execução interativa no navegador não foram realizadas: a ferramenta de navegador recusou a abertura de URL local `file:` por política de segurança. Abra `index.html` para revisar os fluxos listados acima e a composição em desktop e celular. A importação efetiva no Figma também não foi executada. Os arquivos permanecem sem commit enquanto essa revisão estiver pendente.
