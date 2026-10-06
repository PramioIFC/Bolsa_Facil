# 📈 Bolsa Fácil

> Um aplicativo completo em Flutter para acompanhar o mercado de ações brasileiro, gerenciar seu portfólio de investimentos e visualizar o histórico de ativos usando dados em tempo real da [brapi.dev](https://brapi.dev/).

---

**Documentação Técnica:** [`TECHNICAL_DOCS.md`](TECHNICAL_DOCS.md)  
**Registro de Mudanças:** [`MELHORIAS.md`](MELHORIAS.md)  
**Continuação do trabalho:** [`docs/HANDOFF_CODEX.md`](docs/HANDOFF_CODEX.md)

---

## 🚀 Funcionalidades

- 🔍 **Busca de Ativos:** Lista de ações com preço, variação percentual e busca por _ticker_.
- 📊 **Detalhes e Gráficos:** Visualização do histórico de preços (1D a 5A).
- 🔐 **Autenticação:** Cadastro e login com senha hasheada (SHA-256) e sessão persistida (JWT/Bearer).
- ⭐ **Favoritos:** Marque ações de interesse para acompanhamento rápido.
- 💼 **Carteira Simulada:** Compra simulada com cálculo automático de preço médio e acompanhamento de lucro/prejuízo.
- 👤 **Múltiplos Usuários:** Cada conta no banco de dados local tem sua própria carteira isolada.
- 💾 **Backup de Dados:** Exportação e importação de todo o seu perfil (em JSON).

## 🛠️ Tecnologias Utilizadas

| Camada    | Tecnologia                        | Descrição                                         |
| --------- | --------------------------------- | ------------------------------------------------- |
| Frontend  | [Flutter](https://flutter.dev/)   | UI multiplataforma (Web, Android, Windows)        |
| Estado    | `ChangeNotifier`                  | Gerenciamento de estado via `AppState`             |
| Gráficos  | `fl_chart`                        | Renderização dos gráficos de histórico             |
| HTTP      | `http` (Dart)                     | Comunicação com backend e Brapi                    |
| Sessão    | `shared_preferences` / SQLite     | Armazena o token e dados localmente                |
| Backend   | Dart puro (`HttpServer`)          | Servidor REST local rodando na porta `8080`        |
| Banco     | `sqflite_common_ffi` (SQLite)     | Banco de dados no lado do servidor / web           |
| Segurança | `crypto` (SHA-256)                | Hash de senhas                                     |
| API       | [brapi.dev](https://brapi.dev/)   | Dados financeiros do mercado brasileiro            |

## 🏗️ Arquitetura

O projeto segue uma arquitetura **cliente-servidor local**. A persistência de dados (usuários, carteira, favoritos) é feita pelo backend em Dart via chamadas HTTP locais. O servidor local (`tool/brapi_proxy.dart`) atua como Proxy para não expor as chaves da Brapi e burlar as restrições de CORS da Web.

```text
┌─────────────────────────┐         ┌──────────────────────────────┐
│      Flutter App         │  HTTP   │   Backend Dart (porta 8080)  │
│                         │────────▶│                              │
│  • HomeScreen           │         │  /auth/*    → Autenticação   │
│  • StockDetailsScreen   │         │  /data/*    → CRUD Dados     │
│  • PortfolioScreen      │◀────────│  /api/*     → Proxy Brapi    │
└─────────────────────────┘         └──────────────────────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │   brapi.dev API   │
                                    └──────────────────┘
```

## 💻 Como Rodar o Projeto Localmente

### Pré-requisitos
- Flutter SDK (`>=3.3.0 <4.0.0`)
- Token gratuito da brapi: [brapi.dev/dashboard](https://brapi.dev/dashboard)

### 1. Clonar e Instalar
```bash
git clone https://github.com/PramioIFC/BolsaFacil.git
cd BolsaFacil
flutter pub get
```

### 2. Configurar o Token da Brapi
Crie um arquivo `.env` na raiz do projeto copiando o exemplo:
```bash
cp .env.example .env
```
Abra o `.env` e coloque seu token: `BRAPI_TOKEN=seu_token_aqui`. Este token nunca vai ao navegador, sendo lido apenas pelo seu proxy local.

Para **Android/Windows** nativo, configure também em `config/dart_defines.json` (copie de `config/dart_defines.example.json`).

### 3. Rodar o Backend e o Frontend
**Via atalho (Windows):**
```powershell
.\run_web.ps1
```
Este script subirá o backend local e o app Flutter no Chrome na porta 3000 automaticamente.

**Modo Manual (Dois Terminais):**
```bash
# Terminal 1 - Backend e Proxy
dart run tool/brapi_proxy.dart

# Terminal 2 - Frontend Web
flutter run -d chrome --web-port 3000
```

## 🔌 API do Backend e Banco de Dados

O backend escuta em `127.0.0.1:8080` (e limite de 120 req/min por IP).  
O banco SQLite é criado automaticamente em `.data/bolsa_facil.db`.

**Tabelas do Banco SQLite:**
- `users`: Contas de usuário
- `sessions`: Sessões ativas (token Bearer)
- `positions`: Posições na carteira `(user_id, symbol)`
- `favorites`: Ações favoritadas `(user_id, symbol)`

*(Para mais detalhes dos endpoints REST, consulte a documentação técnica).*

## ⚙️ SQLite na Web (WebAssembly)
A versão Web do aplicativo utiliza `sqflite_common_ffi_web`. Após dar `flutter pub get` ou atualizar dependências, rode o comando abaixo para compilar os binários do SQLite local:
```bash
dart run sqflite_common_ffi_web:setup
```

## ✅ Testes e Análise
O projeto possui CI configurado no GitHub Actions. Para rodar as validações localmente:
```bash
flutter analyze
flutter test
```

## 📄 Licença
Este projeto é de uso acadêmico, desenvolvido no [IFC — Instituto Federal Catarinense](https://ifc.edu.br/).

**Desenvolvido com Flutter 💙**
