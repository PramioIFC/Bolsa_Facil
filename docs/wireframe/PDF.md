# PDF de alta fidelidade

Entrega: `../../output/pdf/bolsa-facil-wireframe-completo.pdf`, com 9 páginas.

Telas: Entrar, Criar conta, Início, Favoritas, Detalhes, Compra simulada, Carteira, Editar posição e Conta. Cada página apresenta uma tela redesenhada, marcadores numerados e o endpoint ou operação local associado, com uma explicação de uso. Dados pessoais foram substituídos por exemplos fictícios.

O visual usa tipografia Segoe UI, roxo discreto, superfícies neutras, ícones vetoriais e espaçamento consistente. Foram removidos textos promocionais, o card explicativo permanente de favoritas e os blocos sem integração: Dólar, Selic, IPCA, dividendos e indicadores adicionais da empresa. A compra foi separada de detalhes como proposta de navegação. Autenticação, favoritas e carteira seguem documentadas como operações SQLite locais. O mapa completo da implementação está em `ENDPOINTS.md`.

## Reprodução

Na raiz, executar `python docs/wireframe/build_pdf.py` com `reportlab` e `pypdf` instalados. O gerador é independente do PDF antigo e usa fontes do Windows, com fallback Helvetica. Não faz chamadas de rede nem modifica o app. O HTML e os SVGs antigos permanecem na versão anterior; esta revisão atende à entrega em PDF.

## Verificação

Verificados: nove páginas, presença de integração em cada tela, períodos de histórico e contratos locais, renderização visual de todas as páginas com Poppler e `git diff --check`. Não houve validação online do provedor nem importação no Figma. O PDF é uma proposta visual estática; o app não foi alterado.
