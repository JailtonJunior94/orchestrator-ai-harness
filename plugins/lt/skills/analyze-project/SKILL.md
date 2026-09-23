---
name: analyze-project
description: Analisa a arquitetura de um projeto (monolito, monolito modular, monorepo, microservico), detecta stack e ferramentas de IA instaladas, e gera arquivos de governanca personalizados. Use quando precisar configurar ou atualizar a governanca orientada a IA em um projeto existente. Nao use para criar codigo de aplicacao ou alterar logica de negocio.
metadata:
  category: governance
  version: 2.0.0
---

# Analisar Projeto

> **Onde a spec mora — inegociável.** O diretório de specs pertence ao **repositório em que o
> comando está sendo executado**, a partir de qualquer pasta dele. Em `lt-api` a spec é
> `lt-api/<specs>/prd-<slug>/`; em `dataflow` é `dataflow/<specs>/prd-<slug>/`.
>
> Nunca monte o caminho à mão. Pergunte:
>
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" specs-root --slug <slug> --create
> ```
>
> O nome do diretório é detectado nesta ordem: `LT_TASKS_ROOT` → `AI_TASKS_ROOT` →
> `tasks_root:` em `.lt/config.yaml`/`.claude/config.yaml` → `.specs/` existente **ou
> versionado no git** → `.lt/specs/`. Alvo fora da raiz do repositório é recusado com
> exit 3. Invariante I-5 da constitution.

> **Camada de linguagem é opcional.** As skills `*-implementation` (Go, Node, Python, .NET) e as
> de design não vêm nesta versão do plugin. Antes de mandar carregar qualquer uma, **verifique o
> que existe**:
>
> ```bash
> bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" skills-available --category language
> ```
>
> Saída vazia significa que a camada não está instalada — siga sem ela e diga isso à pessoa.
> Nunca instrua a carregar uma skill que você não confirmou existir: instruir o agente a abrir
> algo inexistente é o defeito mais caro deste harness.

## Procedimentos

**Etapa 1: Descobrir a raiz e o tipo de projeto**
1. Confirmar o diretorio alvo (parametro ou diretorio atual).
2. Verificar se ja existe governanca instalada (presenca de `CLAUDE.md`, `.lt/config.yaml` ou `.lt/specs/`).
3. Se ja existir, ler os arquivos existentes para preservar personalizacoes antes de evoluir.

**Etapa 2: Identificar arquitetura do projeto**
1. Analisar a estrutura de diretorios para classificar o projeto:
   - **Monolito**: diretorio unico com `main.go`, `main.py`, `pom.xml`, `package.json` etc. na raiz, sem separacao clara de modulos autonomos.
   - **Monolito Modular**: diretorio unico mas com pastas de modulos/dominios independentes (ex: `modules/`, `domains/`, `internal/` com subdiretorios por bounded context), cada um com seus proprios modelos e servicos.
   - **Monorepo**: multiplos projetos/servicos independentes sob a mesma raiz (ex: `services/`, `apps/`, `packages/`, presenca de workspaces em `package.json`, `go.work`, `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`).
   - **Microservico**: projeto unico que faz parte de um ecossistema maior (Dockerfile na raiz, manifests k8s, servico isolado).
2. Registrar a classificacao e as evidencias encontradas:
   - Tipo detectado (monolito, monolito modular, monorepo, microservico).
   - Arquivos ou pastas que sustentam a classificacao (ex: `go.work`, `services/`, `Dockerfile`).
   - Se a classificacao for por default (nenhum padrao forte detectado), declarar explicitamente que e uma suposicao.

**Etapa 3: Detectar stack tecnologica**
1. Identificar linguagens principais por presenca de arquivos-chave:
   - Go: `go.mod`, `go.sum`
   - Node/TypeScript: `package.json`, `tsconfig.json`
   - Python: `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile`
   - Java/Kotlin: `pom.xml`, `build.gradle`, `build.gradle.kts`
   - Rust: `Cargo.toml`
   - C#/.NET: `*.csproj`, `*.sln`
2. Identificar frameworks por dependencias (ex: Gin, Echo, Fiber, Express, NestJS, FastAPI, Django, Spring Boot, ASP.NET).
3. Identificar infraestrutura: Docker, Kubernetes, Terraform, CI/CD (`.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`).
4. Identificar ferramentas de teste, lint e formatacao ja configuradas.

**Etapa 4: Detectar ferramentas de IA instaladas**
1. Verificar presenca de cada ferramenta:
   - Claude Code: `.claude/` ou `CLAUDE.md`
   - OpenCode: `.opencode/` ou `opencode.json`
    - Codex: `.codex/` ou `AGENTS.md`
   - GitHub Copilot: `.github/copilot-instructions.md`
2. Registrar quais ferramentas estao presentes para gerar apenas os arquivos relevantes.

**Etapa 5: Mapear e documentar estrutura de pastas e arquitetura**
1. Percorrer a arvore de diretorios do projeto (excluindo `node_modules/`, `vendor/`, `.git/`, `bin/`, `dist/`, `build/`, `target/`, `__pycache__/`) e gerar um mapa visual da estrutura.
2. Identificar e documentar o padrao arquitetural usado:
   - **Clean Architecture / Hexagonal**: pastas como `domain/`, `application/`, `infrastructure/`, `interfaces/`, `ports/`, `adapters/`.
   - **Arquitetura em Camadas (Layered / N-Tier)**: pastas como `controllers/`, `services/`, `repositories/`, `models/`.
   - **DDD Tatico**: pastas como `aggregates/`, `entities/`, `value_objects/`, `domain_events/`, `specifications/`.
   - **MVC**: pastas como `models/`, `views/`, `controllers/`.
   - **Organizacao por Funcionalidade / Fatiamento Vertical**: pastas por funcionalidade ou caso de uso (ex: `features/create-order/`, `features/auth/`).
   - **CQRS**: separacao explicita de `commands/` e `queries/`.
   - **Pacote por Componente**: cada pasta de alto nivel encapsula controller + service + repository.
3. Documentar o fluxo de dependencias entre camadas/modulos:
   - Qual camada depende de qual.
   - Onde ficam as interfaces/contratos.
   - Onde fica a logica de negocio vs infraestrutura.
4. Incluir a arvore de diretorios formatada e a descricao arquitetural no `AGENTS.md` gerado, na secao `## Arquitetura`.
5. Para **monorepo**: documentar a estrutura de cada workspace/servico individualmente.
6. Para **monolito modular**: documentar as fronteiras entre modulos e suas dependencias.

**Etapa 6: Gerar AGENTS.md personalizado**
1. Ler `assets/agents-template.md` como base.
2. Quando o contexto permitir automacao local, preferir `scripts/generate-governance.sh` para materializar os arquivos a partir da deteccao real do projeto.
3. Adaptar o conteudo ao tipo de arquitetura detectado:
   - Para **monorepo**: incluir regras de fronteira entre pacotes/servicos, resolucao de dependencias internas e validacao por workspace afetado.
   - Para **monolito modular**: incluir regras de fronteira entre modulos, proibicao de dependencias circulares e respeito a bounded contexts.
   - Para **monolito**: incluir regras de coesao, separacao de camadas e prevencao de acoplamento excessivo.
   - Para **microservico**: incluir regras de contrato de API, independencia de deploy e comunicacao entre servicos.
4. Incluir secao de validacao com comandos reais detectados no projeto (ex: `go test ./...`, `npm test`, `pytest`).
5. Incluir secao de referencias apontando para `${CLAUDE_PLUGIN_ROOT}/skills/` quando o `install.sh` tiver sido usado.

**Etapa 7: Gerar arquivos por ferramenta**
1. Para cada ferramenta detectada na Etapa 4, gerar o arquivo correspondente:
   - **CLAUDE.md**: delegar para `AGENTS.md`; skills continuam entregues pelo plugin `lt@lt`.
   - **OpenCode**: gerar `.opencode/plugin/lt-governance.js` e skills em `.agents/skills/`.
   - **Codex**: gerar `.codex/config.toml` com uma entrada por skill realmente instalada.
   - **GitHub Copilot**: gerar `.github/copilot-instructions.md`, `.github/skills/` e hooks nativos.
2. Cada arquivo deve:
   - Apontar para `AGENTS.md` como fonte canonica.
   - Listar instrucoes de carregamento de contexto.
   - Não referenciar skill opcional que não exista no plugin instalado.
   - Nao duplicar conteudo ja presente em `AGENTS.md`.

**Etapa 8: Gerar regras contextuais**
1. Se a stack tiver uma skill de linguagem realmente instalada, incluir referencia no `AGENTS.md`.
2. Se houver outras skills de linguagem disponiveis, incluir referencias correspondentes.
3. Adaptar a secao de validacao ao toolchain real do projeto:
   - Go: `go fmt`, `go vet`, `golangci-lint run`, `go test ./...`
   - Node: `npm run lint`, `npm test`, `npx prettier --check .`
   - Python: `ruff check .`, `pytest`, `mypy .`
   - Java: `mvn verify`, `gradle test`
   - Rust: `cargo fmt --check`, `cargo clippy`, `cargo test`
   - C#/.NET: `dotnet build`, `dotnet test`, `dotnet format --verify-no-changes`

**Etapa 9: Persistir e reportar**
1. Salvar todos os arquivos gerados nos caminhos corretos do projeto alvo.
2. Nao sobrescrever arquivos existentes sem antes comparar e preservar personalizacoes.
3. Apresentar relatorio final com:
   - Tipo de arquitetura detectado e evidencias.
   - Padrao arquitetural identificado (Clean Architecture, arquitetura em camadas, DDD, MVC, etc.).
   - Arvore de diretorios mapeada.
   - Fluxo de dependencias entre camadas/modulos.
   - Stack identificada.
   - Ferramentas de IA detectadas.
   - Arquivos gerados ou atualizados (com caminhos).
   - Recomendacoes adicionais (ex: skills de linguagem faltantes, ferramentas nao instaladas).

## Tratamento de Erros

* Se o diretorio alvo nao existir ou estiver vazio, retornar erro explicito e nao gerar arquivos.
* Se a arquitetura nao puder ser classificada com confianca, usar `monolito` como default e registrar a suposicao.
* Se nenhuma ferramenta de IA for detectada, gerar apenas `AGENTS.md` como base e informar que o `install.sh` pode ser usado para instalar ferramentas especificas.
* Se arquivos de governanca ja existirem com personalizacoes, fazer merge inteligente preservando secoes customizadas e adicionando apenas conteudo novo.
* Se houver conflito entre convencao detectada no projeto e template padrao, priorizar a convencao do projeto e registrar a decisao.
