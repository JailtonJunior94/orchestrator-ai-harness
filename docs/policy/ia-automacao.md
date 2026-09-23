# Regras e Boas Práticas (IA & Automação)

> **Dono único deste assunto.** Afirmação absoluta sobre MCP, credencial ou arquivo sensível vive
> aqui e em `plugins/lt/config/policy-texts.md`, em nenhum outro lugar. Um teste do harness
> (`tests/policy-check.sh`) reprova quem repetir a norma noutro arquivo — regra duplicada é regra
> que diverge.
>
> Origem: `guias/Regras e Boas Práticas (IA & Automação).md` do repositório `alexandria`, que passa
> a apontar para cá.

Este documento define as normas obrigatórias para uso de agentes de IA, protocolos de contexto
(MCP) e segurança de dados no ambiente de desenvolvimento da Lima Teixeira.

Cada cláusula tem um **ID citável** e uma coluna dizendo o que a aplica. Cláusula sem mecanismo
está marcada como tal — norma que finge ter enforcement é pior que norma declaradamente manual.

## Model Context Protocol (MCP)

O uso de MCPs amplia as capacidades dos agentes, mas introduz risco de exfiltração.

| ID | Norma |
|---|---|
| **LT-MCP-001** | **Prioridade para oficiais.** Utilize estritamente MCPs mantidos por organizações oficiais ou provedores de infraestrutura homologados (ex.: Anthropic, Google, Supabase, ClickUp). |
| **LT-MCP-002** | **Proibição de terceiros.** É terminantemente proibido o uso de MCPs de desenvolvedores terceiros, repositórios "community-driven" não verificados ou plugins experimentais sem aprovação prévia do time de infraestrutura ou das lideranças técnicas. |
| **LT-MCP-003** | **Menor privilégio.** Ao configurar um MCP (como o de file system), limite o acesso apenas aos diretórios estritamente necessários para a tarefa atual. |


### Servidores MCP homologados — a lista, não só os vendors

`LT-MCP-001` nomeia vendors. Vendor não é allowlist: `allowedMcpServers` recebe **nomes de
servidor**, e uma política que só cita vendors não permite auditar se o que está declarado
corresponde ao que foi decidido. A lista abaixo é a fonte para
`enterprise/managed-settings.json`, e um teste (`tests/enterprise/managed-settings-schema.sh`)
reprova se os dois divergirem.

| `serverName` | Vendor | Por que está homologado |
|---|---|---|
| `claude_ai_Claude_Docs` | Anthropic | documentação viva usada pelo próprio harness |
| `claude_ai_ClickUp` | ClickUp | citado em `LT-MCP-001`; é onde vive o trabalho do time |
| `claude_ai_Google_Drive` | Google | citado em `LT-MCP-001` |
| `claude_ai_Google_Calendar` | Google | citado em `LT-MCP-001` |
| `claude_ai_Gmail` | Google | citado em `LT-MCP-001` |
| `supabase` | Supabase | citado em `LT-MCP-001` |
| `github` | GitHub | **emenda explícita** — não estava em `LT-MCP-001`. Entra porque o próprio harness depende de `gh` para PR, release e bootstrap de repositório privado. Registrada aqui em vez de adicionada em silêncio ao payload. |

**Como homologar um servidor novo.** PR que edita **esta tabela e o
`enterprise/managed-settings.json` juntos**, com avaliação de exfiltração no corpo, mais um
registro `mcp-homologation` no audit trail. Editar só o payload faz o teste reprovar — de
propósito: allowlist que diverge do documento é allowlist que ninguém aprovou.

## Credenciais e Segredos

O vazamento de chaves em prompts é risco crítico: agentes registram o histórico de mensagens.

| ID | Norma |
|---|---|
| **LT-SEC-001** | **Nunca cole** chaves de API, senhas ou tokens diretamente no chat com a IA. |
| **LT-SEC-002** | **Variáveis de ambiente.** Use gerenciadores de segredo (Secrets Manager, `.env` ignorado pelo git) para que o agente leia as chaves programaticamente, em vez de recebê-las como texto puro. |
| **LT-SEC-003** | **Rotação.** Chaves usadas por CLI de IA devem ser rotacionadas periodicamente e ter escopo limitado (ex.: tokens somente-leitura). |

## Arquivos Sensíveis e Permissões

| ID | Norma |
|---|---|
| **LT-FILE-001** | **Identificação.** Arquivos com dados de clientes (PII), certificados SSL, chaves privadas ou segredos de infraestrutura devem estar explicitamente listados em arquivos de ignore (`.gitignore`, `.cursorignore`, `.geminiignore`). |
| **LT-FILE-002** | **Revisão de escrita.** Sempre revise as alterações sugeridas pela IA em arquivos de configuração de infraestrutura (Dockerfile, CI/CD, Terraform) antes de aplicá-las. |
| **LT-FILE-003** | **Logs de auditoria.** Mantenha o rastreamento de quais ações foram executadas de forma autônoma por agentes em ambientes de staging ou produção. |

## Checklist antes de rodar um prompt

| ID | Pergunta |
|---|---|
| **LT-CHK-001** | O prompt contém segredos ou credenciais em texto puro? |
| **LT-CHK-002** | Estou utilizando um MCP não oficial? |
| **LT-CHK-003** | O agente tem permissão de escrita em pastas que não deveria? |
| **LT-CHK-004** | O contexto enviado inclui arquivos com dados sensíveis de produção? |

## Mapa de aplicação

| ID | Aplicada por | Estado |
|---|---|---|
| LT-MCP-001 | `enterprise/managed-settings.json` → `allowedMcpServers` | **não automatizado na wave 1** — lista declarada, `allowManagedMcpServersOnly` ainda `false` |
| LT-MCP-002 | PR em `enterprise/managed-settings.json` + token `mcp-homologation` no audit trail | manual, com trilha |
| LT-MCP-003 | revisão humana no PR de homologação | manual |
| LT-SEC-001 | `user-prompt-detect-secrets.sh`, `pre-write-scan-secrets.sh` | automatizado |
| LT-SEC-002 | `permissions.deny` em `Read(**/.env*)`; `config/sensitive-paths.json` | automatizado |
| LT-SEC-003 | `~/.claude/lt/security-pending.jsonl` + `lt:lt-approve secret-rotated <uid>` | automatizado |
| LT-FILE-001 | `config/sensitive-paths.json`; job `pii-scan` (CPF/CNPJ) | automatizado |
| LT-FILE-002 | `pre-write-block-sensitive-paths.sh` em paths de infra; `deny` em `terraform destroy` | automatizado |
| LT-FILE-003 | `plugins/lt/scripts/approve.sh`, campo `mode=human\|flow\|auto` | automatizado |
| LT-CHK-001..004 | banner do `session-start.sh` + template de PR | lembrete |

### Por que as três de MCP não são hook

Governança de MCP é **política gerenciada**, não hook: o mecanismo correto é
`allowManagedMcpServersOnly` + `allowedMcpServers` no `managed-settings.json`, que o host aplica
antes de qualquer plugin carregar. Um hook que tentasse o mesmo trabalho rodaria depois e poderia
ser contornado.

Na wave 1 a flag fica em `false` de propósito: a norma nomeia quatro vendors, mas há mais
servidores em uso real na frota. Ligar `true` sem inventário cortaria conector em uso no primeiro
restart. A virada para `true` é um PR próprio, cujo corpo traz o inventário e a homologação (ou a
rejeição justificada) de cada servidor que hoje está fora da lista.
