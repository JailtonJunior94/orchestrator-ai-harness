---
description: Prepara o diretório local do harness (.lt/) no repositório atual — config, preferências e trilha de auditoria do squad.
argument-hint: "[--squad <nome>]"
---

Prepare o `.lt/` **do repositório em que esta sessão está**, nunca de outro.

## Passo 1 — confirme onde está

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" specs-root
```

Mostre o caminho à pessoa e confirme que é o repositório certo antes de escrever qualquer coisa.
O invariante I-5 da constitution é inegociável: o estado do harness pertence ao repositório onde
o comando roda.

## Passo 2 — crie a árvore

```
.lt/
├── config.yaml          # squad, guided (nasce off), segmentos da statusline
├── preferences.json     # lido por ENUM, nunca ecoado
├── audit/               # hook-fires.log, exceptions.log
├── cache/               # statusline.json
└── specs/               # prd-<slug>/ — criado pelo ciclo, não aqui
```

`config.yaml` inicial:

```yaml
version: "0.1.0"
squad: "<nome>"
guided: off
statusline:
  segments: [lt_version, model, session_cost, context_pct, git_branch, blocks_today]
```

`preferences.json` inicial:

```json
{ "_version": 1, "code_comments": "minimal", "output_language": "pt-BR", "coauthor_trailer": "on" }
```

## Passo 3 — `.gitignore` do repositório consumidor

Acrescente, se ainda não houver:

```gitignore
.lt/audit/
.lt/cache/
```

`config.yaml`, `preferences.json` e `specs/` **são versionados** — é o contrato do squad e o
registro de decisão das features. `audit/` e `cache/` são locais de cada máquina.

## Regras inegociáveis

- O dial `guided` nasce `off`. Não o suba por iniciativa própria: apertar o parafuso de alguém
  sem pedido é o caminho mais curto para o harness ser desinstalado.
- Nunca sobrescreva um `.lt/` existente. Se já houver, mostre o que existe e pergunte o que mudar.
- `preferences.json` só aceita valores da enum documentada em `config/policy-texts.md`.
