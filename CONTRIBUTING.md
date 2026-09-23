# Como contribuir

Este repositório é o harness de desenvolvimento assistido por IA da Lima Teixeira: um
marketplace de plugins do Claude Code com um plugin core (`plugins/lt/`), adaptadores para
Codex, Copilot e OpenCode, e o ferramental que instala, valida e distribui tudo isso. Antes de
qualquer mudança, leia o `CLAUDE.md` — ele tem as regras duras (bash 3.2, host, idioma) que o
CI cobra.

## Papéis

| Papel | O que faz |
|---|---|
| Mantenedor (`@JailtonJunior94`, ver `.github/CODEOWNERS`) | Dono do core, da política de MCP e do release. Aprova toda mudança em caminho sensível. |
| Squad | Estende o harness **no próprio repo**, em `.lt/` (skills locais, config, preferências). Propõe padrão universal por issue. |
| Dev | Usa o harness; reporta atrito por issue de bug ou na retro do squad. |

**Fronteira:** capacidade de um squad vive em `.lt/skills/` no repo dele. Padrão que vale para
todos entra no core por PR. Plugin novo no marketplace só com aprovação do mantenedor — e
exige release do core (`docs/RELEASE-CHECKLIST.md`).

## Fluxo

1. Abra uma issue (template `Bug` ou `Proposta de feature`) quando a mudança não for trivial.
   Mudança em `plugins/lt/config/constitution.md` **sempre** começa por issue de proposta.
2. Branch a partir de `main`: `<tipo>/<kebab-slug>` em ASCII, com
   `tipo ∈ feat | fix | chore | docs | refactor | spike | proposal`. Branch `spike/` nunca é
   mergeada: vira PR novo com o que se aprendeu.
3. Commits em Conventional Commits (regex no `CLAUDE.md` §5). O escopo é o plugin ou a área:
   `feat(lt): …`, `fix(install): …`, `ci(harness): …`.
4. Antes do push: `bash scripts/pilot-check.sh` — ele roda localmente o que o CI roda e guarda
   evidência em disco quando algo falha.
5. PR contra `main` preenchendo o template. A seção de validação pede **comando → resultado**.

## Onde cada coisa mora

| Quero mexer em… | Caminho | Guia |
|---|---|---|
| skill, command, agent, hook | `plugins/lt/` | `docs/PLUGIN-DEVELOPMENT.md` |
| instalação, atualização, remoção | `scripts/` | `docs/PLUGIN-DEVELOPMENT.md` |
| política gerenciada da frota | `enterprise/` | `enterprise/README.md` |
| versão e release | `scripts/bump-version.sh`, `CHANGELOG.md` | `docs/VERSIONING.md`, `docs/RELEASE-CHECKLIST.md` |
| nome de command ou skill | `docs/command-glossary.md` | `tests/command-glossary-check.sh` |
| idioma de um artefato | — | `docs/language-policy.md` |

## Versionamento

Semver no plugin core. Patch corrige; minor acrescenta sem quebrar; major quebra contrato
(nome de command, formato do audit trail, chave de `.lt/`) e exige janela de migração de pelo
menos 30 dias, com guia de migração no `CHANGELOG.md`. Detalhes em `docs/VERSIONING.md`.

## O que não entra no repositório

Nada do ambiente de quem trabalha: caminho com nome de usuário, pin pessoal, contagem de
instalações da sua máquina, clone aninhado. Isso é evidência e vai no **corpo do PR**. A
pergunta-teste, antes de commitar qualquer prosa: *outro dev, noutro time, leria isto como
verdade sobre o harness?*

## Segurança

Vulnerabilidade não vira issue pública: siga o `SECURITY.md`.
