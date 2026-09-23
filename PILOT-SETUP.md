# Piloto — instalar e provar o harness numa máquina nova

Roteiro para quem instala o LT AI Harness pela primeira vez numa máquina (ou num squad piloto) e
precisa sair com **evidência** de que ele está funcionando — não com a impressão de que está.
Cada fase termina num critério observável.

## Fase 0 — pré-requisitos

| Ferramenta | Por quê | Conferir |
|---|---|---|
| Claude Code | host principal e gates de validação | `claude --version` |
| `python3` | reconciliador, guardas, gates | `python3 --version` |
| `git` | snapshot antes de comando destrutivo, atualização | `git --version` |
| `jq` | bootstraps enterprise; hooks mais rápidos | `jq --version` |
| `gh` (opcional) | bootstrap enterprise e publicação | `gh auth status` |
| PyYAML (opcional) | gates de frontmatter e de orçamento de listagem | `python3 -c 'import yaml'` |

No macOS o `/bin/bash` é 3.2 — é ele que roda os hooks, e é nele que as suítes precisam passar.

**Critério:** todos os comandos acima respondem.

## Fase 1 — suítes verdes antes de instalar

```bash
git clone https://github.com/JailtonJunior94/orchestrator-ai-harness.git
cd orchestrator-ai-harness
bash scripts/pilot-check.sh
```

**Critério:** `PILOT CHECK PASSOU`. Item amarelo é gate que **não rodou** (dependência ausente) —
resolva ou registre o motivo antes de seguir. Falha preserva a evidência num diretório
temporário, com o caminho impresso.

## Fase 2 — instalar

Pelo canal oficial:

```bash
claude plugin marketplace add JailtonJunior94/orchestrator-ai-harness
claude plugin install lt@lt
```

Ou pelo wizard, que valida cache, registro e settings no fim e oferece a statusline:

```bash
bash scripts/install.sh              # interativo
bash scripts/install.sh --dry-run    # mostra o que faria, sem escrever
```

O wizard registra o marketplace **por caminho local**, o que tira a máquina do canal oficial de
atualização; ele imprime o caminho de volta. Se a máquina tem mais de um perfil do Claude Code,
confira a linha `perfil:` da Fase 0 do wizard — instalar no perfil errado não dá erro.

**Critério:** Fase 3 do wizard com `✓ lt: cache@<versão> · registro · habilitado`, ou
`claude plugin list` mostrando `lt@lt` habilitado.

## Fase 3 — reiniciar e diagnosticar

Plugin só carrega em sessão nova: `/exit` e `claude` de novo. Então:

```text
/lt:lt-doctor
```

**Critério:** a saída mostra a versão instalada igual à do manifesto e nenhuma seção em falha. O
banner `Harness LT <versão> ativo.` aparece no início da sessão.

## Fase 4 — projeto piloto

Num repositório de produto (não neste):

```text
/lt:0-setup
```

Para squads que também usam Codex, Copilot ou OpenCode:

```bash
bash scripts/install.sh --hosts codex,copilot,opencode --project /caminho/do/projeto
python3 scripts/reconcile-hosts.py verify --project /caminho/do/projeto
```

**Critério:** `.lt/` criado com `config.yaml` e `preferences.json`; `verify` sem drift.

## Fase 5 — smoke ponta a ponta

Na sessão do projeto piloto, peça ao agente cada ação abaixo e observe a reação da guarda:

| Ação | Resultado esperado |
|---|---|
| escrever um arquivo com um token de acesso de formato real (use um placeholder inválido) | escrita negada ou confirmação pedida, conforme a severidade |
| `rm -rf` de um diretório fora do repositório | bloqueio com instrução de aprovação `destructive` |
| ler `.env` ou uma chave SSH | bloqueio de caminho sensível |
| editar código comum, sem segredo | passa sem interrupção |
| colar um segredo no prompt | aviso e pendência de rotação registrada |
| rodar o ciclo curto (`lt:create-prd` → `lt:create-technical-specification` → `lt:create-tasks`) | artefatos em `.lt/specs/` e linhas de fase em `~/.claude/lt/approve.log` |

**Critério:** todas as linhas com o resultado esperado; `.lt/audit/hook-fires.log` registrando
os bloqueios.

## Fase 6 — aceitação

- [ ] `PILOT CHECK PASSOU` no clone.
- [ ] `lt@lt` instalado, habilitado, e `/lt:lt-doctor` limpo após restart.
- [ ] Statusline do harness visível, ou barra própria preservada (`skipped-foreign`).
- [ ] Os seis casos da Fase 5 observados.
- [ ] Achados de atrito registrados em issue (template `Bug` ou `Proposta de feature`).

## Próximos passos

- Política gerenciada para a frota: `enterprise/README.md` e `docs/enterprise-rollout.md`.
- Atualizar: `bash scripts/update.sh` e depois `claude plugin update lt@lt --scope user` — o
  `marketplace update` sozinho não troca o que roda.
- Remover: `bash scripts/uninstall.sh` (confirmação padrão **não**; preserva `.lt/` e o audit trail).
