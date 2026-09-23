# Changelog

Formato: um bloco `## [X.Y.Z] — YYYY-MM-DD` por versão, o mais novo no topo.
Entrada **manual**, na mesma PR do `scripts/bump-version.sh`. Mudança de comportamento ganha
blockquote de aviso.

Este número espelha a versão do plugin core (`lt`) desde a primeira release.

## [Não lançado]

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
