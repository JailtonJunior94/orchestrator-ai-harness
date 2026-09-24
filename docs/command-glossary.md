# Glossário de commands e skills

Fonte canônica dos nomes que o harness expõe. Todo command em `plugins/lt/commands/` e toda
skill em `plugins/lt/skills/` aparece aqui **uma vez**, na forma `lt:<nome>` — e nada aparece
aqui sem existir em disco. `tests/command-glossary-check.sh` cobra os dois sentidos.

## Forma canônica

No Claude Code, todo componente de plugin é **namespaced** pelo nome do plugin. A forma de
invocar é `/lt:<nome>`; a forma sem prefixo não resolve para o plugin e o host não emite erro.
Por isso a prosa do repositório nunca cita `/<nome>` solto para um nome desta tabela — o mesmo
teste reprova.

Nos outros hosts o nome é o mesmo, sem o prefixo de plugin, porque os adaptadores são
materializados no repositório consumidor por `scripts/install.sh --hosts … --project <repo>`:

| Host | Onde as skills chegam | Onde os commands chegam |
|---|---|---|
| Claude Code | plugin `lt@lt` | plugin `lt@lt` (`/lt:<nome>`) |
| Codex | `.agents/skills/<nome>/` + `.codex/config.toml` | não materializados |
| GitHub Copilot | `.github/skills/<nome>/` + `.github/copilot-instructions.md` | não materializados |
| OpenCode | `.agents/skills/<nome>/` + `.opencode/plugin/` | `.opencode/commands/<nome>.md` |

## Commands

| Canônico | Tipo | O que faz |
|---|---|---|
| `lt:0-setup` | command | Prepara o `.lt/` do repositório atual: config, preferências e trilha de auditoria do squad. |
| `lt:lt-approve` | command | Registra uma aprovação no audit trail pela porta única `plugins/lt/scripts/approve.sh`. |
| `lt:lt-doctor` | command | Diagnóstico: versões, instalação, cobertura, audit trail e statusline. Lê e reporta; nunca conserta. |
| `lt:lt-migrate-legacy` | command | Detecta e aposenta a distribuição antiga por symlink, com arquivamento e restauração. |

## Skills

Ciclo SDD, na ordem em que costuma rodar:

| Canônico | Tipo | O que faz |
|---|---|---|
| `lt:using-lt` | skill | Porta de entrada: descobre a skill ou o command certo para a intenção declarada. |
| `lt:analyze-project` | skill | Detecta arquitetura, stack e ferramentas de IA e gera a governança do projeto. |
| `lt:us-to-prd` | skill | Converte user stories brutas num PRD estruturado. |
| `lt:create-prd` | skill | Cria o PRD: escopo, objetivos, restrições e requisitos funcionais numerados. |
| `lt:create-technical-specification` | skill | Cria a especificação técnica a partir do PRD aprovado, com spec-hash para detectar drift. |
| `lt:create-tasks` | skill | Decompõe PRD e techspec em tarefas incrementais, ordenadas e testáveis. |
| `lt:execute-task` | skill | Executa uma tarefa aprovada com validação, revisão e evidência. |
| `lt:execute-all-tasks` | skill | Orquestra o PRD inteiro, um subagente novo por tarefa, respeitando o DAG. |
| `lt:review` | skill | Revisa um diff quanto a correção, segurança, regressão e testes faltantes. |
| `lt:bugfix` | skill | Corrige bug pela causa raiz com teste de regressão obrigatório. |
| `lt:refactor` | skill | Refatoração incremental que preserva comportamento e prova não regressão. |
| `lt:agent-governance` | skill | Carrega as regras de governança (DDD, erros, segurança, testes) antes de mexer em código. |
| `lt:go-guideline` | skill | Diretrizes Go de produção com o Uber Go Style Guide como fonte mandatória, carregadas quando o diff toca código Go. |
| `lt:design-patterns` | skill | Decide, com evidência do código, se um dos 22 padrões clássicos do Refactoring.Guru se aplica, preferindo a solução direta quando ela custa menos. |
| `lt:domain-modeling` | skill | Modela o domínio com tipos no estilo Domain Modeling Made Functional e traduz o modelo para a linguagem do repositório. |

## Componentes adiados

Nomes citados por skills mas deliberadamente **não** instalados nesta versão vivem em
`config/deferred-components.txt`, com motivo e data de revisão. Eles não entram nesta tabela:
o glossário lista só o que existe.

## Como acrescentar um nome

1. Crie o command ou a skill (`docs/PLUGIN-DEVELOPMENT.md`).
2. Acrescente a linha na tabela certa, na forma `lt:<nome>`.
3. Rode `bash tests/command-glossary-check.sh` — banner `GLOSSARY CHECK PASSOU`.
