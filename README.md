# LT AI Harness

Harness de desenvolvimento assistido por IA da Lima Teixeira. Distribui o ciclo de desenvolvimento
orientado a especificação (SDD), hooks de segurança e audit trail para Claude Code, OpenCode, Codex
e GitHub Copilot de forma versionada, auditável e reversível.

> **Estado: `0.1.2`, em construção.** A versão `1.0.0` só sai quando o checklist do Apêndice J do
> `docs/REPLICATION-GUIDE.md` fechar. Enquanto isso, o número baixo é a informação honesta.

## Instalação

```bash
claude plugin marketplace add JailtonJunior94/orchestrator-ai-harness
claude plugin install lt@lt
```

Ou, do clone, o wizard que valida o estado final:

```bash
bash scripts/install.sh
```

### Codex, Copilot e OpenCode

O plugin Claude é a fonte canônica. Os outros três hosts recebem uma **projeção** das mesmas skills,
agents, comandos e hooks. Os hooks rodam os mesmos scripts canônicos via `plugins/lt/lib/host-dispatch.py`.

```bash
# perfil do usuário: vale para `codex`, `copilot` e `opencode` rodados de qualquer pasta
bash scripts/install.sh --hosts codex,copilot,opencode

# um repositório específico (arquivos versionáveis; --trust registra o repo como confiável)
bash scripts/install.sh --hosts codex,copilot,opencode --project /caminho/do/projeto --trust

# conferir checksums e blocos gerenciados
python3 scripts/reconcile-hosts.py verify --scope global
python3 scripts/reconcile-hosts.py verify --project /caminho/do/projeto
```

- **Escopo global:** as skills vão para `~/.agents/skills`, que os três hosts leem. Os adaptadores
  vão para `$CODEX_HOME`, `$COPILOT_HOME` e `$XDG_CONFIG_HOME/opencode`, e o runtime vai para
  `~/.lt-harness/`.
- **Uninstall:** não toca em nada que já existia antes. Para remover a instalação global, use
  `bash scripts/uninstall.sh --hosts-global`.
- **Paridade:** `docs/capability-matrix.md` é gerado e conferido pelo `scripts/check-host-parity.sh`.
- **Provas por execução real:** em `docs/host-facts.md`, incluindo o que só funciona com o repo
  marcado como confiável.

Três detalhes que custam chamado:

- o subcomando é `claude plugin`, **não** `claude code plugin` (com `code` a palavra vira prompt);
- o prefixo `github:` é rejeitado com `Invalid marketplace source format`;
- **atualizar exige dois passos** — `claude plugin marketplace update lt` só atualiza o clone e
  responde "✔ Successfully updated" sem trocar o que roda. Quem re-resolve o registro é
  `claude plugin update lt@lt --scope user`.

## O que tem dentro

| Camada | Onde | O quê |
|---|---|---|
| Marketplace | `.claude-plugin/marketplace.json` | catálogo de plugins, versão, cadência |
| Plugin core | `plugins/lt/` | ciclo SDD, hooks de segurança, audit trail e statusline |
| Distribuição | `enterprise/` | `managed-settings.json` pinado em tag + bootstraps por SO |
| Ferramental | `scripts/` | instalar, atualizar, remover, migrar do symlink, gates de host |
| Multi-host | `plugins/lt/scripts/reconcile-hosts.py` | projeção em Codex, Copilot e OpenCode (escopo global ou por projeto) |
| Provas | `tests/` | smoke, completeness, e2e, enterprise, unit |

## Documentação

- `CLAUDE.md` — regras para quem edita este repo (bash 3.2, host, idioma, commits)
- `docs/REPLICATION-GUIDE.md` — como este repo é por dentro e como construir um equivalente do zero
- `docs/policy/ia-automacao.md` — a norma de IA e automação da Lima Teixeira, dona única do assunto
- `docs/REPLICATION-GUIDE.md` §3 e §11 — os três números de versão, quem bumpa cada um e como sai um release

## Sobre contagens neste README

Toda contagem em prosa ("N skills", "N hooks") neste README, no `CLAUDE.md` e no
`docs/REPLICATION-GUIDE.md` é conferida contra o disco por `scripts/validate-playbook-counts.sh`,
que roda no CI dentro de `tests/docs-generated-fresh.sh`. Contagem que o script não consegue
conferir não entra: prosa que mente é pior que prosa ausente.
