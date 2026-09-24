# Matriz de capacidades por host

<!-- gerado por scripts/check-host-parity.sh --write; nao edite a mao -->

Fonte única: `plugins/lt/{skills,agents,commands,hooks}`. Claude Code recebe o plugin; Codex,
Copilot e OpenCode recebem a projeção de `plugins/lt/scripts/reconcile-hosts.py` (escopo
`project` mostrado abaixo; o escopo `global` usa `~/.agents/skills`, `$CODEX_HOME`,
`$COPILOT_HOME` e `$XDG_CONFIG_HOME/opencode`). Hooks dos outros hosts executam os MESMOS scripts
canônicos via `lib/host-dispatch.py`. Evidência de execução real: `docs/host-facts.md`.

| Tipo | Componente | Claude Code | Codex | Copilot | OpenCode |
|---|---|---|---|---|---|
| skill | agent-governance | `lt:agent-governance` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | analyze-project | `lt:analyze-project` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | bugfix | `lt:bugfix` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | create-prd | `lt:create-prd` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | create-tasks | `lt:create-tasks` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | create-technical-specification | `lt:create-technical-specification` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | execute-all-tasks | `lt:execute-all-tasks` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | execute-task | `lt:execute-task` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | go-guideline | `lt:go-guideline` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | refactor | `lt:refactor` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | review | `lt:review` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | us-to-prd | `lt:us-to-prd` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| skill | using-lt | `lt:using-lt` | `.agents/skills` | `.agents/skills` | `.agents/skills` |
| agent | bugfixer | `lt:bugfixer` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | prd-writer | `lt:prd-writer` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | project-analyzer | `lt:project-analyzer` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | refactorer | `lt:refactorer` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | reviewer | `lt:reviewer` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | task-executor | `lt:task-executor` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | task-planner | `lt:task-planner` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| agent | technical-specification-writer | `lt:technical-specification-writer` | `.codex/agents` | `.github/agents` | `.opencode/agents` |
| comando | 0-setup | `/lt:0-setup` | skill `lt-0-setup` | skill `lt-0-setup` | comando `lt-0-setup` |
| comando | lt-approve | `/lt:lt-approve` | skill `lt-approve` | skill `lt-approve` | comando `lt-approve` |
| comando | lt-doctor | `/lt:lt-doctor` | skill `lt-doctor` | skill `lt-doctor` | comando `lt-doctor` |
| comando | lt-migrate-legacy | `/lt:lt-migrate-legacy` | skill `lt-migrate-legacy` | skill `lt-migrate-legacy` | comando `lt-migrate-legacy` |
| hook | PostToolUse (post-skill-fire.sh, post-tool-capture-tokens.sh, post-tool-validate-governance.sh) | nativo | `PostToolUse` | `postToolUse` | `tool.execute.after` |
| hook | PreToolUse (pre-bash-block-destructive.sh, pre-bash-block-sensitive-paths.sh, pre-bash-git-operation-gate.sh, pre-write-block-sensitive-paths.sh, pre-write-scan-secrets.sh, pre-write-spec-coverage-warn.sh, pre-write-validate-preload.sh) | nativo | `PreToolUse` | `preToolUse` | `tool.execute.before` |
| hook | SessionStart (session-start.sh) | nativo | `SessionStart` | `sessionStart` | `session.created` |
| hook | Stop (stop-validate-session-end.sh) | nativo | `Stop` | `agentStop` | `session.idle` |
| hook | SubagentStop (subagent-stop-wrapper.sh) | nativo | n/a — evento nao emitido | n/a — evento nao emitido | n/a — evento nao emitido |
| hook | UserPromptSubmit (user-prompt-block-sensitive-paths.sh, user-prompt-context-warning.sh, user-prompt-detect-secrets.sh) | nativo | `UserPromptSubmit` | `userPromptSubmitted` | `chat.message` |
