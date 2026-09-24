# Checagem automática

<!-- TL;DR
Regras de linter conferidas na documentação oficial que aproximam as regras de Object Calisthenics, por linguagem, e o que nenhuma ferramenta checa bem.
Keywords: linter, lint, PMD, ESLint, max-depth, no-else-return, golangci-lint, nestif, revive, Pylint, Ruff, RET505, PHP_CodeSniffer, CI
Load complete when: a pessoa quer automatizar a checagem ou pergunta qual regra de linter usar.
-->

- Escopo: ferramentas que já existem. Nenhuma checa as 9 regras com fidelidade.
- Fonte: documentação oficial de cada ferramenta, linkada por linha.

Harness: ligue a regra no linter do projeto no modo de aviso primeiro e meça quantos achados ela
gera no código existente antes de torná-la bloqueante. Limite numérico do linter segue a
convenção do repositório; não copie os limites de Bay para a CI.

## Mapa por regra

| Regra | Java (PMD) | TypeScript e JavaScript (ESLint) | Go (golangci-lint) | Python |
|---|---|---|---|---|
| OC-1 indentação | `AvoidDeeplyNestedIfStmts`, `CognitiveComplexity` | `max-depth` | `nestif`, `gocognit`; revive `max-control-nesting` | Pylint `too-many-nested-blocks` (R1702) |
| OC-2 `else` | sem regra padrão | `no-else-return` | revive `early-return`, `indent-error-flow`, `superfluous-else` | Pylint `no-else-return` (R1705); Ruff `RET505`, `RET506` |
| OC-5 um ponto | `LawOfDemeter` | sem regra padrão | sem regra padrão | sem regra padrão |
| OC-7 tamanho | `NcssCount`, `GodClass` | sem regra padrão de tamanho de classe | `funlen`; revive `function-length` | Pylint `too-many-public-methods` (R0904) |
| OC-8 campos | `TooManyFields` | sem regra padrão | sem regra padrão | Pylint `too-many-instance-attributes` (R0902) |
| OC-9 getters | `DataClass` (aproximação) | sem regra padrão | sem regra padrão | sem regra padrão |

Links: [PMD design](https://pmd.github.io/pmd/pmd_rules_java_design.html),
[ESLint max-depth](https://eslint.org/docs/latest/rules/max-depth),
[ESLint no-else-return](https://eslint.org/docs/latest/rules/no-else-return),
[golangci-lint](https://golangci-lint.run/docs/linters/),
[revive](https://github.com/mgechev/revive/blob/master/RULES_DESCRIPTIONS.md),
[Pylint](https://pylint.readthedocs.io/en/stable/user_guide/checkers/features.html),
[Ruff](https://docs.astral.sh/ruff/rules/).

Valores padrão conferidos: PMD `TooManyFields` 15 campos, `AvoidDeeplyNestedIfStmts` profundidade 3,
`CognitiveComplexity` 15, `NcssCount` 60 por método e 1500 por classe; ESLint `max-depth` 4.

## PHP

O conjunto [object-calisthenics/phpcs-calisthenics-rules](https://github.com/object-calisthenics/phpcs-calisthenics-rules)
implementa sniffs para as regras 1, 2, 5, 6, 7 e parte da 9, e deixa de fora as regras 3, 4 e 8. O
projeto está descontinuado e recomenda regras de PHPStan (`symplify/phpstan-rules`) no lugar.

## O que nenhuma ferramenta checa bem

- OC-3 e OC-4: dependem de saber se o primitivo ou a coleção têm comportamento próprio.
- OC-6: abreviação por dicionário falha com termo de domínio.
- OC-9 no sentido de "Tell, don't ask": o achado é a decisão tomada fora do objeto, não a
  existência do getter.

Esses três ficam para revisão humana ou para esta skill.
