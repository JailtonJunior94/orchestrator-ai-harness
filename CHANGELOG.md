# Changelog

Formato: um bloco `## [X.Y.Z] — YYYY-MM-DD` por versão, o mais novo no topo.
Entrada **manual**, na mesma PR do `scripts/bump-version.sh`. Mudança de comportamento ganha
blockquote de aviso.

Este número espelha a versão do plugin core (`lt`) desde a primeira release.

## [Não lançado]

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
