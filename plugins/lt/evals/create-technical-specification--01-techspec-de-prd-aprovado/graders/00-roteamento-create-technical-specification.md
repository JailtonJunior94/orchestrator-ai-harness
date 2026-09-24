---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?create-technical-specification"'
min: 1
---

A skill `create-technical-specification` deve ser invocada neste cenario.

Sob `--ablation with-without`, este grader vira indicador nao pontuado: sem o
plugin carregado ele nunca poderia passar, entao pontua-lo compararia coisas diferentes.
