---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?review"'
min: 0
max: 0
---

A skill `review` NAO deve ser invocada neste cenario.

Sob `--ablation with-without`, este grader vira indicador nao pontuado: sem o
plugin carregado ele passaria sempre, entao pontua-lo compararia coisas diferentes.
