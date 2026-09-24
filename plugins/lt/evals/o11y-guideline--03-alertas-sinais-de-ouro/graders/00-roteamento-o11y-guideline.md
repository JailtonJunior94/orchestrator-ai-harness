---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?o11y-guideline"'
min: 1
---

A skill `o11y-guideline` deve ser invocada neste cenario.

Sob `--ablation with-without`, este grader vira indicador nao pontuado: sem o
plugin carregado ele nunca poderia passar, entao pontua-lo compararia coisas diferentes.
