<!--
Título do PR em inglês, no formato Conventional Commits:
  <tipo>(<escopo>): <resumo>      tipos: feat fix chore docs refactor perf test build ci
O corpo é em pt-BR. Ambiente local (caminhos da sua máquina, contagem de instalações, pins
pessoais) vai AQUI como evidência, nunca no repositório.
-->

## O que muda e por quê

<!-- O problema, a decisão e o efeito observável. Link para issue ou spec, se houver. -->

## Tipo

- [ ] bug
- [ ] feature
- [ ] docs
- [ ] segurança
- [ ] mudança de comportamento (exige blockquote de aviso no `CHANGELOG.md`)

## Evidência de validação

<!--
Comando → resultado observado. Adjetivo ("testei e funciona") não é evidência.
Suíte é verde pelo BANNER, não só pelo exit code.
-->

| Comando | Resultado |
|---|---|
| `bash scripts/pilot-check.sh` | `PILOT CHECK PASSOU` |
| `bash tests/smoke/run.sh` | `SUITE PASSOU` |

## Checklist

- [ ] Rodei `bash scripts/pilot-check.sh` localmente, num `/bin/bash` 3.2 se estou no macOS.
- [ ] Script novo ou alterado respeita o `CLAUDE.md` §2 (bash 3.2, aspas, `set -euo pipefail`)
      e carrega o porquê em comentário pt-BR onde registra decisão.
- [ ] Hook novo ou alterado tem teste unitário **positivo e negativo** com `HOME` e
      `CLAUDE_CONFIG_DIR` isolados.
- [ ] Skill ou command novo: `description` em pt-BR com gatilhos e quando **não** usar; entrada
      em `docs/command-glossary.md`; `bash scripts/validate-frontmatter.sh` verde.
- [ ] Contagem em prosa mudou? `bash scripts/validate-playbook-counts.sh` verde.
- [ ] Baseline regravada (`docs/benchmarks/*.json`)? A justificativa está **neste corpo** e em
      `_history` (`--write --cause`). Ratchet regravado sem motivo é ratchet desligado.
- [ ] Mexeu em `enterprise/`, no manifesto ou em versão? `bash scripts/bump-version.sh` e
      `tests/enterprise/run.sh` verdes; `CHANGELOG.md` atualizado na mesma PR.
- [ ] Nada do meu ambiente local entrou no diff (caminho com usuário, pin pessoal, clone aninhado).

## Só para mudanças de política

- [ ] `plugins/lt/config/constitution.md` mudou? Existe issue de proposta aprovada antes do PR.
- [ ] Hook que **bloqueia** está categorizado (SEGURANÇA · COMPLIANCE · PROCESSO · QUALIDADE) e
      hook de segurança **não** consulta o dial `guided`.
- [ ] Servidor MCP novo em `enterprise/managed-settings.json`: avaliação de exfiltração no corpo
      do PR e a mesma entrada em `docs/policy/ia-automacao.md`.
