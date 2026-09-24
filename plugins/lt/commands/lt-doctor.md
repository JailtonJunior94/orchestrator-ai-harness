---
description: Diagnóstico do harness LT — versões, instalação, hosts, cobertura, audit trail e statusline.
argument-hint: "[--telemetry|--audit|--security|--hosts|--statusline]"
---

Rode o diagnóstico do harness e apresente o resultado.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" $ARGUMENTS
```

Interprete a saída para a pessoa: o que está saudável, o que está divergente e qual é o próximo
comando. Não repita a saída crua se ela estiver longa — diga o que importa e ofereça o detalhe.
