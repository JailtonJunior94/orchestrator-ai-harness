# Índice da documentação

Por onde começar, conforme o que você veio fazer.

## Quero usar o harness

| Documento | Para quê |
|---|---|
| `README.md` | visão geral e instalação em três linhas |
| `PILOT-SETUP.md` | instalar numa máquina nova e sair com evidência de que funciona |
| `plugins/lt/README.md` | o que o plugin core traz: skills, commands, guardas, audit trail |
| `docs/command-glossary.md` | nome canônico de cada command e skill, e como invocar em cada host |
| `docs/policy/ia-automacao.md` | a norma de IA e automação da organização: MCP, segredos, arquivos sensíveis |

## Quero mudar o harness

| Documento | Para quê |
|---|---|
| `CLAUDE.md` | regras duras para quem edita este repositório: bash 3.2, host, idioma, commits |
| `CONTRIBUTING.md` | papéis, fluxo de branch e PR, onde cada coisa mora |
| `docs/PLUGIN-DEVELOPMENT.md` | como acrescentar skill, command, hook ou script — e como provar |
| `docs/language-policy.md` | onde mora cada regra de idioma e qual gate a cobra |
| `docs/host-facts.md` | comportamento do host provado executando, com a versão do CLI |
| `tests/unit/README.md` | como escrever teste unitário com `assert.sh` e ambiente isolado |

## Quero publicar uma versão

| Documento | Para quê |
|---|---|
| `docs/VERSIONING.md` | os três números de versão, as cadências e o semver do core |
| `docs/RELEASE-CHECKLIST.md` | a ordem operacional do bump à tag, e as armadilhas conhecidas |
| `CHANGELOG.md` | histórico por versão |

## Quero distribuir para a frota

| Documento | Para quê |
|---|---|
| `enterprise/README.md` | a política gerenciada: payload, bootstraps, verificação e remoção |
| `docs/enterprise-rollout.md` | ondas, cadência de aviso e rollback |
| `SECURITY.md` | reporte privado de vulnerabilidade, prazos e escopo |

## Quero entender como tudo foi construído

| Documento | Para quê |
|---|---|
| `docs/REPLICATION-GUIDE.md` | anatomia do repositório e passo a passo para construir um equivalente do zero |
| `docs/benchmarks/` | baselines dos ratchets: orçamento de listagem de skills e custo always-on |
| `config/` | allowlist de avisos do host, padrões proibidos, componentes adiados |

## Gates, em uma linha cada

| Comando | Banner de sucesso |
|---|---|
| `bash scripts/pilot-check.sh` | `PILOT CHECK PASSOU` |
| `bash tests/smoke/run.sh` | `SUITE PASSOU` |
| `bash tests/completeness-check.sh` | `TUDO ENTREGUE` |
| `bash tests/e2e/run.sh` | `E2E PASSOU` |
| `bash tests/unit/run.sh` | `Suite unit passou` |
| `bash tests/enterprise/run.sh` | `ENTERPRISE PASSOU` |
| `bash tests/command-glossary-check.sh` | `GLOSSARY CHECK PASSOU` |
| `bash tests/language-policy-check.sh` | `LANGUAGE POLICY CHECK PASSOU` |
| `bash scripts/validate-plugins.sh` | `VALIDATE PASSOU` |
| `bash scripts/validate-frontmatter.sh` | `FRONTMATTER OK` |
| `bash scripts/measure-skill-budget.sh` | `SKILL BUDGET OK` |
| `bash scripts/validate-playbook-counts.sh` | `contagens em prosa conferem com o disco` |
