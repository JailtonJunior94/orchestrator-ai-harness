# Constitution do harness LT

Texto canônico que o agente carrega. Norma completa e citável em `docs/policy/ia-automacao.md`
(dono único do assunto) — aqui está a forma operacional, com o que cada regra faz na prática.

## Invariantes de governança

Cinco. Não são recomendações.

### I-1 — Protocolo PRD-first

Toda mudança de comportamento começa por um PRD. É proibido implementar código sem requisito
funcional (`RF-nn`) mapeado.

**Escape hatch** — o ciclo completo é overhead para mudança que não altera requisito. Nestes casos
vá direto ao estágio:

| Situação | Estágio |
|---|---|
| Bug isolado, contrato inalterado | `bugfix` |
| Refactor delimitado, mesmo contrato | `refactor` |
| Rename, typo, import, formatação | `execute-task` sem PRD |

O ciclo completo é **obrigatório** quando a mudança acrescenta, remove ou altera requisito
funcional; muda contrato público (API HTTP, flags de CLI, schema de banco, formato de arquivo); ou
invalida um ADR existente.

### I-5 — A spec pertence ao repositório onde o comando roda

`.lt/specs/prd-<slug>/` nasce e vive na **raiz do repositório em que o comando foi executado**.
Trabalhando em `lt-api`, a spec é `lt-api/.lt/specs/prd-<slug>/`. Trabalhando em
`dataflow`, é `dataflow/.lt/specs/prd-<slug>/`. Não existe local global, não existe fallback para
o diretório do plugin, para `$HOME` ou para `/`.

**Isto é regra de segurança, não de arrumação.** Spec no repositório errado quebra três coisas
ao mesmo tempo: a rastreabilidade `RF → código` passa a mentir; o `check-spec-drift` compara o
requisito de um produto com a implementação de outro e aprova por acidente; e specs de produto
acabam acumuladas dentro do repo de ferramenta, que tem audiência e ciclo de vida diferentes.

Funciona a partir de **qualquer pasta** do repositório: um comando rodado em
`src/modules/users/deep` resolve para a raiz do repositório, não para o `cwd`.

**Raiz do repositório**, nesta ordem: `LT_PROJECT_DIR` (escape hatch explícito) →
`CLAUDE_PROJECT_DIR` → `git rev-parse --show-toplevel` → o próprio `cwd` (para pastas fora de
git, que continuam funcionando).

**Nome do diretório de specs**, nesta ordem: `LT_TASKS_ROOT` → `.specs/` se o repositório já
tiver esse diretório → `.lt/specs/`. O nome é **detectado, não imposto**: um repositório que já
carrega `.specs/` com histórico de PRDs não deve ganhar um segundo diretório de specs só porque
o harness prefere outro nome — dois lugares para a mesma coisa é como a rastreabilidade começa a
divergir.

Nunca assuma o caminho. Pergunte ao harness:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lt-sdd.sh" specs-root
```

Todo subcomando que recebe um diretório de PRD **recusa** (`exit 3`) alvo fora da raiz detectada.

### I-2 — Âncora de confiança (`spec-hash`)

A integridade Requisito → Arquitetura → Implementação é mantida por SHA-256. A techspec grava o
hash do PRD; `tasks.md` grava o hash de ambos. Editar o PRD sem ressincronizar deixa os
descendentes **stale**, e os estágios de execução param.

`spec-hash.sh` **recusa** rodar sobre estado aprovado sujo — sincronizar hash nunca pode mascarar
drift real.

### I-3 — Isolamento de contexto

Contexto mínimo. Tarefa de execução roda em subagente, sempre. O orquestrador não executa tarefa
em linha e **nunca** muta `tasks.md` por conta própria.

### I-4 — Evidência obrigatória

Uma tarefa só é `done` depois que o relatório de execução está persistido com evidência física
(logs, testes, saídas). Todo critério de aceite precisa de uma linha literal
`- <critério> -> comprovado: <evidência>`.

**Fail-closed:** critério sem prova é rejeitado. Prosa não parseada não é prova de ausência.

## Segurança — as regras que os hooks aplicam

| ID | Regra | Hook |
|---|---|---|
| LT-SEC-001 | Nunca cole chaves, senhas ou tokens no chat | `user-prompt-detect-secrets.sh` (só avisa), `pre-write-scan-secrets.sh` (`deny` em `critical`, `ask` em `high`) |
| LT-SEC-002 | Segredo vem de gerenciador ou `.env` ignorado, nunca de texto puro | `pre-write-block-sensitive-paths.sh` |
| LT-SEC-003 | Chave exposta é chave rotacionada | pendência em `~/.claude/lt/security-pending.jsonl` |
| LT-FILE-001 | PII, SSL e chave privada ficam fora do alcance do agente | `pre-bash-block-sensitive-paths.sh`, `pre-write-block-sensitive-paths.sh` |
| LT-FILE-002 | Alteração em Dockerfile, CI/CD e Terraform é revisada antes de aplicar | `pre-write-block-sensitive-paths.sh` (modo `ask`) |
| LT-FILE-003 | Ação autônoma em staging/produção deixa trilha | `scripts/approve.sh` |
| LT-MCP-001..003 | Governança de MCP | **não é hook** — é política gerenciada (`managed-settings.json`) |

> **Por que `deny` e não `ask` para credencial de produção.** A frota roda
> `claude --dangerously-skip-permissions`. Segundo a documentação oficial, `permissionDecision:
> "deny"` cancela a chamada **mesmo em `bypassPermissions`**, enquanto `"ask"` apenas mostra o
> prompt — e onde não há prompt, não há nada. Uma guarda inteiramente em `"ask"` ficaria inerte
> justamente nas máquinas que mais confiam nela. Detalhes e citação em `docs/host-facts.md`.

**Hook de segurança nunca consulta o dial `guided`.** Só hook de processo consulta. O dial regula
rigor de processo, nunca a postura de segurança.

## Estilo de código — `R-STYLE-001`

Severidade: **hard**. Escopo: o código-fonte que as skills produzem ou editam nos repositórios dos
times (`.go`, `.ts`, `.py`, `.sh`, e demais linguagens de implementação).

### R-STYLE-001.1 — Código em inglês

Identificadores, nomes de pacote e de arquivo, mensagens de erro, textos de log, nomes de teste e
de fixture.

Termo de domínio em pt-BR vindo de PRD, techspec, ADR ou modelo de domínio **nunca** migra literal
para identificador: traduza ao implementar (`Fato` → `Fact`, `Página` → `Page`,
`ChaveSemântica` → `SemanticKey`). A rastreabilidade PRD→código fica no relatório de execução e no
mapeamento de RF, não no nome do identificador.

Exceção única: string que é contrato externo verificável (saída de CLI já publicada, chave de
protocolo, formato consumido por terceiro) permanece no idioma do contrato — com justificativa
explícita no relatório de execução.

### R-STYLE-001.2 — Zero comentários no código produzido

Sem comentário de linha, de bloco, doc-comment, TODO/FIXME/NOTE ou código comentado. Shebang e
diretivas obrigatórias da linguagem (`//go:embed`, `//go:build`, `# -*- coding: -*-`) não são
comentários. Ao editar arquivo que tenha comentário nas linhas tocadas, remova-os — só o diff, não
o arquivo inteiro.

O código deve ser autoexplicativo: nomes claros, funções pequenas, early return. Quando um
comentário pareceria necessário, refatore para eliminar a necessidade.

> ### Exceção de escopo: os scripts do próprio harness
>
> `R-STYLE-001.2` **não se aplica** a `plugins/lt/{hooks,lib,scripts,statusline}/**`,
> `scripts/**` e `tests/**` deste repositório. Nesses arquivos o comentário de justificativa é
> **obrigatório** onde registra decisão.
>
> **Por quê:** este harness não tem ADRs numerados. O registro de decisão são
> `docs/specs/_completed/<slug>/` e os comentários longos dentro dos próprios scripts. Um guard de
> segurança precisa dizer, no ponto de uso, por que bloqueia o que bloqueia e por que a postura é
> `ask` e não `exit 2` — senão o próximo mantenedor "simplifica" o guard e reabre o furo.
>
> Aplicar a regra aqui trocaria um defeito conhecido (comentário que envelhece) por um pior
> (decisão que desaparece). A exceção é escrita, com escopo fechado, e nenhum linter do repo
> cobra zero-comentários sobre essa árvore.

### R-STYLE-001.3 — Sem prefixo `_` em identificador

Visibilidade em Go é pela capitalização, não por underline. `_` isolado como blank identifier é
permitido; `_` no meio de nome, só onde a convenção já exige (`Test_Foo`, `_test.go`, `_linux.go`).

### Artefatos em pt-BR

`.md`, relatórios de execução, ADRs, PRDs, techspecs e changelog continuam em **pt-BR**. A regra de
idioma acima vale para código, não para prosa.

## Testes — `R-TEST-002`

Severidade: **hard**. Escopo: todo repositório que usa o harness, sem exceção. Não consulta o dial
`guided`, não tem chave de configuração para desligar e não tem exceção de legado. Testa-se o que
importa: o número de cobertura é consequência de testes eficazes, nunca o objetivo.

### R-TEST-002.1 — Cobertura por pacote tocado

- Todo pacote ou módulo alterado pela tarefa termina com **≥ 70%** de cobertura de linhas. Se
  estava abaixo, a tarefa sobe até 70% antes de fechar.
- A cobertura do pacote nunca cai (`delta ≥ 0`).
- Faixa-alvo: **70–80%**. Acima de 80% só com teste justificado por risco; teste escrito para
  subir número é achado de review.
- `n/a` só vale quando o diff não toca código-fonte executável (docs, configuração). O validador
  confere pelo patch.
- Gate: `validate-task-evidence.sh` reprova o `done` fora dessas condições (bloco `## Coverage`).

### R-TEST-002.2 — Eficácia

Todo teste precisa **falhar se o comportamento que protege quebrar**. A pergunta de controle é:
"se eu inverter esta condição, apagar esta linha ou trocar este valor, algum teste quebra?".
Proibido:

- teste sem asserção, ou cuja única asserção é "o mock foi chamado";
- teste de getter, setter, DTO, construtor trivial ou wiring sem lógica;
- caso duplicado que não exercita ramo novo;
- snapshot extenso sem intenção declarada;
- asserção tão frouxa que passa com a implementação errada (`not nil`, `len > 0`).

### R-TEST-002.3 — Nível certo para cada risco

| Nível | O que cobre | Como |
|---|---|---|
| Unit | Domínio, use cases, lógica pura, validadores: caminho feliz, falhas e bordas | Determinístico, sem IO real, doubles só nas fronteiras |
| Integração | Cada adapter de fronteira (banco, fila, cliente HTTP, filesystem) | Dependência real efêmera (testcontainers ou equivalente), separada por tag ou script |
| E2E | Só as jornadas críticas de negócio: um fluxo por jornada, não um por requisito | Estável, sem `sleep`, dados próprios, roda na CI |

### R-TEST-002.4 — Zero regressão

- Bug corrigido ganha teste que falha antes da correção e passa depois.
- Diff que cruza pacotes, muda contrato público ou mexe em configuração compartilhada roda a suíte
  completa antes do `done`.
- Teste que falha não é apagado nem marcado como `skip` para destravar a tarefa.

### R-TEST-002.5 — Zero lacuna

Todo `RF-nn` tem pelo menos um teste mapeado: nível, nome do teste e comportamento que ele derruba.
A matriz nasce na techspec e é conferida no review. RF sem teste é achado `high`.

## Precedência

1. Esta constitution
2. `docs/policy/ia-automacao.md` (segurança e MCP)
3. Referências carregadas pela skill ativa
4. Convenção da linguagem

Conflito no mesmo nível: prevalece `hard` sobre `guideline`; empatada a severidade, prevalece a
regra mais restritiva para correção, segurança e determinismo; convenção explícita local prevalece
sobre guia externo quando documentada.

## Proibido

- Aprovação sem evidência.
- Loop infinito de remediação (teto de 5 rodadas `review → bugfix → review`).
- Ação destrutiva de git ou publicação remota sem pedido explícito.
- Seguir adiante sem input obrigatório quando não há inferência segura — pause ou falhe de forma
  explícita.
