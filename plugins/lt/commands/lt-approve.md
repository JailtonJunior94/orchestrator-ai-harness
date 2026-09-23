---
description: Registra uma aprovação no audit trail do harness — fases do ciclo, liberação de guarda ou registro avulso.
argument-hint: "[--mode human|flow|auto] <token> [contexto]"
---

Registre a aprovação pedida no audit trail, usando a **porta única**.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/approve.sh" $ARGUMENTS
```

Chame exatamente nessa forma, **sem prefixo `VAR=x`**: o classificador de auto mode lê
`bash <plugin>/scripts/<script> <args>` de um jeito e a forma prefixada de outro.

## Vocabulário

**Fases do ciclo** — registram passagem, não liberam nada:
`analyze-project` · `create-prd` · `create-technical-specification` · `create-tasks` ·
`execute-task` · `review` · `bugfix` · `refactor`

**Abrem uma guarda de segurança** (valem 5 minutos, e são **recusados** em `--mode auto`):
`destructive` · `sensitive-read` · `sensitive-write` · `secret-write` · `sensitive-mode-ask` ·
`allowlist-change`

**Avulsos:** `sensitive-mode-block` · `secret-rotated` · `exception` · `audit-security` ·
`mcp-homologation` · `legacy-symlink-migrated`

## Regras

- Token fora do vocabulário é recusado. O casamento é **exato**, nunca por substring — um slug
  como `fix-destructive-cleanup` não abre a guarda `destructive`.
- O campo `mode` diz **como** o checkpoint foi aprovado. Use `human` quando a pessoa decidiu,
  `flow` dentro do ciclo assistido, `auto` em execução autônoma.
- Em `--mode auto`, qualquer token que abre guarda sai com `exit 3`: o ciclo autônomo não assina
  a própria licença. Nesse caso, peça a aprovação humana explicitamente.
- Depois de registrar, diga em uma linha o que foi registrado e por quanto tempo vale.
