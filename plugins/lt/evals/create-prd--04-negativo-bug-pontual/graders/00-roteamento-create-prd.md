---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?create-prd"'
max: 0
---

A skill `create-prd` NAO deve ser invocada neste cenario.

Sob `--ablation with-without`, este grader vira indicador nao pontuado: sem o
plugin carregado ele nunca poderia passar, entao pontua-lo compararia coisas
diferentes.
