# Política de segurança

O LT AI Harness roda dentro da sessão de quem o habilita: seus hooks veem cada comando, cada
escrita e cada prompt. Uma falha aqui não é um bug comum — é um furo na guarda que as pessoas
acreditam estar ligada. Por isso o reporte é **privado** e tem prazo.

## Como reportar

**Não abra issue pública.** Ela expõe a falha antes da correção.

1. Use o reporte privado do GitHub:
   <https://github.com/JailtonJunior94/orchestrator-ai-harness/security/advisories/new>
2. Inclua: versão do plugin (`/lt:lt-doctor`), host (Claude Code, Codex, Copilot ou OpenCode),
   SO, passos para reproduzir e o impacto que você observou.
3. **Não** anexe segredo real, `approve.log` sem sanitizar, nem dado de cliente. Um placeholder
   do mesmo formato basta para reproduzir.

## Prazos

| Etapa | Prazo |
|---|---|
| Confirmação de recebimento | 2 dias úteis |
| Análise inicial e severidade | 5 dias úteis |
| Correção — severidade crítica | 7 dias corridos |
| Correção — severidade alta | 14 dias corridos |
| Correção — média e baixa | próxima versão minor |

A correção sai como release com tag (a tag é o deploy — ver `docs/VERSIONING.md`), com o
aviso no `CHANGELOG.md` e crédito a quem reportou, se desejar.

## Versões suportadas

| Linha | Suporte |
|---|---|
| `0.x` (linha atual) | correções de segurança na versão mais recente |

Antes da `1.0.0` não há backport: a correção vai para a próxima versão, e a máquina volta ao
estado seguro com re-pin (`docs/enterprise-rollout.md`).

## Escopo

**Dentro:**

- bypass de hook de segurança (comando destrutivo, caminho sensível, segredo em escrita ou prompt);
- escrita no audit trail por fora de `plugins/lt/scripts/approve.sh`, falsificação de linha ou
  token de liberação aceito em `--mode auto`;
- vazamento de conteúdo do audit trail, de `~/.claude/lt/` ou de `.lt/` para fora da máquina;
- corrida (race) no append do audit trail que perca ou corrompa linha;
- injeção via payload de hook, via `.lt/preferences.json` ou `.lt/sensitive-paths.json` de repo
  de terceiro (o valor tem de ser enum; ver `plugins/lt/config/policy-texts.md`);
- injeção de shell ou path traversal nos scripts de instalação, reconciliação e remoção,
  inclusive nos adaptadores de Codex, Copilot e OpenCode;
- política gerenciada (`enterprise/`) que deixe de valer em silêncio.

**Fora:**

- vulnerabilidades do Claude Code, Codex, Copilot ou OpenCode em si — reporte ao fornecedor;
- servidores MCP de terceiros;
- consumo de tokens ou custo de sessão (é decisão de engenharia, tratada em issue comum);
- comportamento em máquina com `--dangerously-skip-permissions` que a documentação já declara
  (`docs/host-facts.md`).
