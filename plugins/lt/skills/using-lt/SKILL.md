---
name: using-lt
description: Use quando a pessoa pedir ajuda para navegar o harness LT ("começar", "estou perdido", "qual comando uso", "como instalo", primeira mensagem da sessão) OU ao esbarrar em problema de instalação, atualização, host ou MCP bloqueado ("plugin não carregou", "blocked by enterprise policy", "conector não funciona", "skill sumiu", "não funciona no Codex/Copilot/OpenCode"). Descobre qual skill ou comando LT atende à intenção declarada e encaminha problema de MCP ao time de engenharia. Não use para escrever código ou revisar artefatos — para isso existem as skills do ciclo SDD.
metadata:
  category: governance
  autor: Lima Teixeira — Engenharia
  runtime: nenhum
---

# using-lt

Porta de entrada do harness. Esta skill não executa trabalho de domínio: ela descobre a intenção e
encaminha para o componente certo.

## Quando usar

Quando a pessoa não sabe qual comando ou skill resolve o que ela quer, quando o harness parece não
estar funcionando (em qualquer host), ou quando um MCP foi bloqueado por política.

**Não use** para fazer o trabalho em si. Se a intenção já está clara ("crie o PRD desta feature"),
encaminhe e saia do caminho.

## Procedimento

1. Leia a intenção declarada. Não pergunte o que já foi dito.
2. Localize o componente pela tabela de roteamento abaixo.
3. Diga **uma** frase: qual componente atende e por quê. Então invoque-o ou instrua a invocá-lo.
4. Se nada atender, diga isso claramente em vez de forçar o encaixe mais próximo.

## Roteamento

| Intenção | Componente |
|---|---|
| Diagnosticar o harness, versões, cobertura, telemetria | `lt:lt-doctor` |
| Preparar o repo do squad (`.lt/`) | `lt:0-setup` |
| Registrar aprovação no audit trail | `lt:lt-approve` |
| Sair da distribuição antiga por symlink | `lt:lt-migrate-legacy` |
| Gerar governança do repo (AGENTS.md, CLAUDE.md, Codex, Copilot, OpenCode) | `analyze-project` |
| Transformar user stories em PRD | `us-to-prd` |
| Começar uma mudança de comportamento | ciclo SDD, a partir de `create-prd` |
| Modelar o domínio com tipos antes da techspec | `domain-modeling` |
| Especificar a solução técnica de um PRD aprovado | `create-technical-specification` |
| Quebrar a TechSpec aprovada em tarefas | `create-tasks` |
| Executar uma tarefa / todas as tarefas | `execute-task` / `execute-all-tasks` |
| Revisar mudança, corrigir bug, refatorar | `review` / `bugfix` / `refactor` |
| Regras transversais de governança e evidência | `agent-governance` |
| Instrumentar com OpenTelemetry, revisar o Collector, alertas dos 4 sinais de ouro | `o11y-guideline` |
| Schema, migração, query ou índice em PostgreSQL | `postgres-guideline` |

## Hosts

O mesmo conteúdo roda em quatro hosts. No Claude Code chega pelo plugin `lt@lt`. Em Codex, Copilot
e OpenCode chega pelo instalador de projeto (`scripts/install.sh --hosts codex,copilot,opencode
--project <repo>`), que materializa as skills em `.agents/skills/` e liga os mesmos hooks
canônicos. Skill ausente num desses hosts é drift: rode `reconcile-hosts.py verify --project
<repo>` antes de concluir que a skill não existe.

## Problema de MCP

Um MCP bloqueado **não** é defeito do harness: é a política de IA e automação da Lima Teixeira
funcionando (`docs/policy/ia-automacao.md`). Encaminhe ao time de engenharia com o nome do servidor
e o caso de uso. Homologar um MCP novo é um PR em `enterprise/managed-settings.json` mais um
registro `mcp-homologation` no audit trail.

Nunca oriente a contornar o bloqueio.

## Regras inegociáveis

- Uma frase de roteamento, não um resumo do harness inteiro.
- Não invente componente que não está na tabela acima.
- Marcador de verificação de carga desta skill: `LT-HARNESS-USING-LT-OK`. Ele existe para a sonda
  de host (`claude -p --plugin-dir …`) provar que a skill carregou — nome inválido cai em silêncio,
  então "não deu erro" não prova nada. Emita-o apenas quando pedido explicitamente.
