# Changelog

Formato: um bloco `## [X.Y.Z] — YYYY-MM-DD` por versão, o mais novo no topo.
Entrada **manual**, na mesma PR do `scripts/bump-version.sh`. Mudança de comportamento ganha
blockquote de aviso.

Este número espelha a versão do plugin core (`lt`) desde a primeira release.

## [Não lançado]

## [0.1.3] — 2026-09-24

A eval deixa de ser relatório e passa a **bloquear release**, com um juiz cuja precisão foi medida.

### Adicionado
- **Calibração do juiz** (`scripts/lib/judge-calibration.py`, `tests/fixtures/judge-calibration.json`,
  `docs/benchmarks/judge-calibration.json`). O conjunto tem 28 itens rotulados à mão: 23 respostas
  reais da eval e 5 controles sintéticos de FAIL. O juiz é medido **no próprio host**: o agente só
  repete a resposta e o grader decide.

  | Juiz | Acurácia | Falsos negativos |
  |---|---|---|
  | haiku (usado até a 0.1.2) | 0,73 | 14 |
  | sonnet | 0,93 | 2 |

- **Eval como gate** (`scripts/lib/eval-gate.py`):
  - `check` reprova se:
    - o juiz tiver acurácia abaixo de 0,90 ou houver menos de 3 execuções por caso;
    - o roteamento ficar abaixo de 95% nos positivos ou de 100% nos negativos;
    - alguma skill regredir mais de 0,05 contra a linha de base do mesmo juiz;
    - alguma skill tiver **ganho negativo sobre o modelo sem o plugin**.
  - `fresh` (gratuito) bloqueia o release quando skills, agents, comandos ou evals mudaram depois
    da última eval aprovada.
  - `merge` completa uma execução que bateu o teto de custo, recusando configurações divergentes.
- `release.yml` roda `eval-gate.py fresh`. `plugin-eval.yml` usa juiz sonnet, 3 execuções, teto de
  USD 30 e `eval-gate.py check`. O CI avisa em todo push quando a eval está desatualizada.
- Regressões cobertas por teste (`eval-gate.test.sh`, `drift-report-tag.test.sh`).

### Alterado
- `bugfix`:
  - corrigidos dois caminhos quebrados desde o rename: o do validador e o do guard de
    profundidade, que não resolviam em host nenhum;
  - sem o código em mãos, a resposta passa a trazer a validação da entrada, uma hipótese de causa
    raiz e o teste de regressão planejado.
- `review`: gatilho para auditoria de qualidade de módulo.
- Gate de descontaminação proíbe os dois padrões de caminho quebrado (listados em
  `config/forbidden-patterns.txt`).

### Resultado (primeira linha de base aprovada; juiz sonnet, 3 execuções, 26 casos)

| Skill | Com plugin | Sem plugin | Delta |
|---|---:|---:|---:|
| `create-technical-specification` | 0,833 | 0,458 | +0,38 |
| `execute-task` | 0,883 | 0,583 | +0,30 |
| `create-prd` | 0,931 | 0,639 | +0,29 |
| `create-tasks` | 0,956 | 0,706 | +0,25 |
| `review` | 0,715 | 0,507 | +0,21 |
| `bugfix` | 0,861 | 0,667 | +0,19 |

- **Roteamento:** 59/60 positivos e 18/18 negativos. Custo USD 36,07, mais USD 3,44 de calibração.
- Com o juiz calibrado, `bugfix` e `create-prd` deixaram de pontuar abaixo do modelo sem plugin. A
  maior parte da diferença vinha de falsos negativos do haiku.
- As notas absolutas não se comparam com as da 0.1.2, porque a régua é outra. O indicador válido
  é o delta.

## [0.1.2] — 2026-09-24

Correções guiadas pela eval da 0.1.1. A medição usa a mesma metodologia: juiz `haiku` explícito,
2 execuções por braço, com e sem o plugin.

### Resultado medido (0.1.1 → 0.1.2)
- **Nota geral:** 0,635 → 0,681. **Delta com e sem plugin:** +0,070 → +0,095.
- **Roteamento:** positivos 26/40 → **40/40**; negativos continuam 12/12.
- **Por skill (com plugin):**
  - `create-technical-specification`: 0,41 → 0,71;
  - `review`: 0,56 → 0,73;
  - `create-tasks`: 0,72 → 0,75.

### Alterado
- `create-technical-specification`:
  - gate de aprovação pelos bytes (`assert-approved <bundle> prd`, sem techspec "adiantada" de
    PRD em rascunho);
  - procedimento de drift: `check-spec-drift` → `invalidate --from prd` → reaprovação →
    `sync-spec-hash`.
- `create-prd`:
  - editar PRD com artefatos aprovados abaixo leva a `invalidate --from prd`, nunca a
    `sync-spec-hash` para calar o drift;
  - `RF` existente não é renumerado;
  - aprovação é gate humano.
- `review`:
  - bugs na lista canônica `BUG-NNN` validada por `validate-bugs`;
  - resultado em JSON (`review-result` v2) validado por `validate-result review`, com evidência de
    caminho relativo;
  - credencial literal é `critical`, com rotação, limpeza de histórico e sem ecoar o valor.
- `execute-task`: explicita a rodada e o teto do ciclo `review → bugfix → review`.
- **Gatilhos de roteamento nas descriptions** de `bugfix`, `create-tasks`, `review`, `execute-task` e
  `create-technical-specification`. Custo medido: listagem com +621 caracteres (67,7% do orçamento
  padrão) e custo always-on com +156 tokens (1.741).

### Corrigido
- Fixtures de eval:
  - `review--03` rotulava a chave como falsa e zerava o critério de rotação;
  - `execute-task--03` dizia "segue" sem trazer os bugs.

### Pendências conhecidas
- `bugfix` (0,65 contra 0,77 sem o plugin) e `create-prd` (0,71 contra 0,78) pontuam **abaixo** do
  modelo sem o plugin nesta eval. Investigar antes de expandir o uso.
- `execute-task` teve queda no run completo (0,69 → 0,56 com 2 execuções). A re-medição isolada, com
  3 execuções e a fixture corrigida, dá 0,63 contra 0,47 sem o plugin: dentro do ruído do juiz, não
  é regressão confirmada.
- O juiz do host reprova respostas corretas em parte dos critérios (documentado em
  `docs/benchmarks/eval-baseline.json`). As notas LLM são limite inferior.

## [0.1.1] — 2026-09-24

### Adicionado
- **Sinal de vida por host:** `session-start` grava `$CLAUDE_CONFIG_DIR/lt/heartbeat/<host>.json`. O
  `lt-doctor --hosts` cruza esse registro com a data da instalação, confere o `trusted_hash` do Codex e
  o frescor da cópia, e acusa o host cujos hooks nunca dispararam (hook do Codex pulado em silêncio).
- **Frescor da cópia projetada:** o manifest de `reconcile-hosts.py` guarda versão, data e digest da
  fonte (`plugins/lt/lib/runtime_freshness.py`). A sessão avisa quando a fonte mudou e ninguém
  reinstalou. O runtime passa a levar o `plugin.json`, e a versão deixa de aparecer como `?` fora do
  Claude.
- **Evals executadas pela primeira vez** (`docs/benchmarks/eval-baseline.json`):
  - 26 casos, 2 execuções por braço, com e sem o plugin;
  - juiz `haiku` explícito;
  - nota 0,635, aprovação 28,8%, delta +0,07;
  - roteamento: negativos 12/12 corretos, positivos 26/40 (65%).
- `scripts/check-eval-routing.sh` lê o formato real do relatório. `validate-evals.sh` reprova negativo
  sem `min: 0`/`max: 0` e qualquer `add_dirs`.

### Alterado
- **Adaptador em paralelo:** `host-dispatch.py` roda os hooks de um evento ao mesmo tempo, como o
  Claude Code. Mediana por evento, medida no Codex: de 167–207 ms para 109–123 ms. A decisão
  continua determinística.
- **Copilot recebe a razão do deny:** o bloqueio vai como
  `{"permissionDecision":"deny","permissionDecisionReason":…}`. Com exit 2, o modelo só via
  `hook exited with code 2`. Provado ao vivo com `--yolo`.
- `plugin-eval.yml` passa `--judge-model haiku`. O juiz padrão reprovou 9/9 votos numa resposta correta.

### Corrigido
- `session-start` anunciava "atualização pendente 1.0.0" em toda sessão aberta no clone, porque lia o
  `.version` da raiz do manifesto. Agora lê a versão do plugin pelo nome.
- Suíte de evals, que nunca tinha rodado:
  - `add_dirs` inexistente, e 4 casos não rodavam;
  - negativos com intervalo impossível ("1..0");
  - critérios que exigiam ações proibidas pelo caso;
  - juiz sem o pedido original.
- `gen-drift-report.sh` não conta a tag que aponta para o próprio commit, que reprovava o CI do release
  por construção.

### Pendências conhecidas (medidas pelas evals, não corrigidas nesta versão)
- `create-technical-specification` (nota 0,41) não tem procedimento de aprovação nem de drift:
  nunca cita `check-spec-drift`, `assert-approved` nem `approve`.
- `create-prd` não orienta `lt-sdd.sh invalidate --from prd` ao editar PRD com artefatos
  aprovados abaixo.
- `review`:
  - não emite bugs no formato canônico;
  - não cita `validate-result review`;
  - usa caminhos absolutos na evidência.
- Roteamento: quando o conteúdo já vem no prompt, o modelo responde sem invocar a skill (6 casos).
- A fixture de `review--03` rotula a chave como falsa e derruba o critério de rotação.

## [0.1.0] — 2026-09-23

Primeira release do LT AI Harness.

### Adicionado
- Marketplace `lt` com o plugin core `lt`:
  - 12 skills do ciclo SDD mais `using-lt`;
  - 8 agents (`task-executor`, `reviewer`, `prd-writer`, `technical-specification-writer`,
    `task-planner`, `bugfixer`, `refactorer`, `project-analyzer`);
  - 4 comandos (`0-setup`, `lt-approve`, `lt-doctor`, `lt-migrate-legacy`);
  - 16 hooks: segurança, processo, telemetria e governança de sessão.
- Motor SDD (`plugins/lt/lib/sdd.py` via `plugins/lt/scripts/lt-sdd.sh`):
  - aprovação por hash com `assert-approved`;
  - schemas versionados de resultado (`execution`, `review`, `checkpoint`);
  - `seal-evidence --commit`;
  - `check-traceability`;
  - estado v2 com `migrate-sdd` / `rollback-sdd` / `orchestrate --run-id`;
  - `validate-bugs`, memória durável por PRD e `telemetry report`;
  - 24 evals estáticos.
- Paridade com Codex, GitHub Copilot e OpenCode:
  - `plugins/lt/scripts/reconcile-hosts.py` projeta skills, agents, comandos e hooks nos escopos
    `global` e `project`, com uninstall que preserva arquivos do usuário e com trust de hook do Codex;
  - `plugins/lt/lib/host-dispatch.py` roda o `hooks.json` canônico em todos os hosts;
  - gate `scripts/check-host-parity.sh` e `docs/capability-matrix.md`.
- Instalador, atualizador e desinstalador (`--hosts` com escopo global ou `--project`), payload
  enterprise pinado em tag, bootstraps por SO, governança do repositório e suítes smoke,
  completeness, e2e, unit e enterprise na CI (Ubuntu, macOS e `/bin/bash` 3.2 real).

### Provado ao vivo
- Claude Code, Codex, OpenCode e Copilot, cada um no modo sem confirmação que se usa no dia a dia:
  o hook canônico nega `git push --force` para `main` e a escrita de segredo literal, e o disco
  confirma que nada foi aplicado. Detalhes e limites (cota do Copilot, TUI do OpenCode) estão em
  `docs/host-facts.md`.

### Pendências conhecidas
- O conteúdo SDD portado de `JailtonJunior94/orchestrator` é do mesmo owner deste repositório.
  O repositório de origem ainda não declara `LICENSE`.
- `LICENSE` é `Proprietary` num repositório público: o código fica visível, mas não é licenciado
  para reuso. Mudar isso é decisão do owner.
