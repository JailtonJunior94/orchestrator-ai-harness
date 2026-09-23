---
name: Bug
about: Algo do harness LT não se comporta como a documentação promete.
title: "fix: <resumo curto em inglês>"
labels: bug
---

<!--
VULNERABILIDADE NÃO ENTRA AQUI. Bypass de hook, vazamento do audit trail ou injeção em payload
de hook: siga o SECURITY.md (canal privado). Issue pública expõe a falha antes da correção.
-->

## O que aconteceu

<!-- Comportamento observado, com a mensagem exata. -->

## O que era esperado

## Como reproduzir

1.
2.

## Ambiente

| Item | Valor |
|---|---|
| Versão do plugin (`/lt:lt-doctor`) | |
| `claude --version` | |
| Host (Claude Code, Codex, Copilot, OpenCode) | |
| SO e `/bin/bash --version` | |
| Instalação (marketplace, `scripts/install.sh`, `--hosts`) | |

## Saída do diagnóstico

<!-- Cole a saída de `/lt:lt-doctor`. Revise antes: nada de token, e-mail ou caminho privado. -->

```text
```

## Linhas do audit trail (se relevante)

<!--
De `~/.claude/lt/approve.log` ou `.lt/audit/hook-fires.log`. Sanitize o campo de operador e
qualquer contexto sensível; mantenha epoch, token e mode.
-->

```text
```
