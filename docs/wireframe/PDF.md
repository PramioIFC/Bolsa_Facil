# PDF de alta fidelidade

Entrega: `../../output/pdf/bolsa-facil-wireframe-completo.pdf`, com 13 páginas.

As páginas 1-9 reutilizam o PDF e a prancha que já estavam na pasta. As páginas 10-11 acrescentam as referências visuais das capturas: indicadores macro, saúde da empresa e dividendos. As páginas 12-13 documentam navegação e contrato HTTP. Dados pessoais foram substituídos por exemplos fictícios.

Os blocos presentes apenas nas capturas estão identificados como integração pendente. O código atual não fornece endpoints para Dólar, Selic, IPCA, dividendos ou os indicadores adicionais da empresa. Autenticação, favoritas e carteira são operações SQLite locais. O mapa completo da implementação está em `ENDPOINTS.md`.

## Reprodução

Na raiz, executar `python docs/wireframe/build_pdf.py` com `reportlab` e `pypdf` instalados. O gerador requer o PDF base `output/pdf/bolsa-facil-wireframe.pdf`. Não faz chamadas de rede nem modifica o app.

## Verificação

Verificados: 13 páginas, presença dos quatro períodos de histórico, campos de resposta, integridade do protótipo existente via `node docs/wireframe/verify.cjs` e renderização visual das páginas com Poppler. Não houve validação online do provedor nem importação no Figma. O PDF é um documento de apresentação estático.
