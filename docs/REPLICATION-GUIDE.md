# Guia de replicação — o que este repo é e como construir um equivalente do zero

> **Para quem é:** o time que vai manter um harness de desenvolvimento assistido por IA em outra
> organização e precisa de um repositório de plugins Claude Code pronto para produção, sem
> herdar o que é específico da Lima Teixeira.
>
> **Como este guia foi produzido:** lendo o repositório em disco, executando `claude --version`
> (Claude Code `2.1.267`), `claude plugin validate` sobre o manifesto e o plugin, medindo custo
> com `claude plugin details` sob `HOME` descartável, cronometrando os hooks, e cruzando cada
> afirmação da documentação oficial de Anthropic e OpenAI com o que existe nos diretórios.
> Onde a prosa e o disco divergem, **o disco vence**.
>
> **Convenção tipográfica**
> `[FATO]` verificado neste repo (arquivo e linha citados) ·
> `[HOST]` comportamento do Claude Code provado **executando**, não lendo documentação ·
> `[OFICIAL]` citação direta da documentação de Anthropic ou OpenAI ·
> `[DECISÃO]` a outra organização escolhe; aqui só está o que a Lima Teixeira escolheu e por quê ·
> `[ARMADILHA]` já custou retrabalho aqui.

---

## Sumário

**Parte I — o que este repo é**
1. Natureza e as três camadas · 2. Mapa do repositório · 3. Manifesto e os três números de
versão · 4. Anatomia do plugin · 5. Hooks de segurança · 6. Audit trail · 7. Statusline ·
8. Ciclo SDD · 9. Instalação, atualização, remoção e migração · 10. Distribuição enterprise ·
11. Versionamento e release · 12. Testes · 13. CI · 14. Evals · 15. Governança · 16. Extensão
pelos squads · 17. Registro de decisões · 18. Estado em disco

**Parte II** — passo a passo, Fases 0 a 14 · **Parte III** — mínimo viável vs completo ·
**Parte IV** — armadilhas recorrentes · **Apêndices A–J**

---

# Parte I — o que este repo é

## 1. Natureza e as três camadas

`[FATO]` Este repositório **não é código de produto**. É um framework de processo, governança e
contexto para desenvolvimento assistido por IA, distribuído como **marketplace de plugins do
Claude Code**.

| Camada | Onde vive | O que é |
|---|---|---|
| **Marketplace** | `.claude-plugin/marketplace.json` | catálogo: nome, versão, cadência e fonte de cada plugin. É o que `claude plugin marketplace add` lê. |
| **Plugin** | `plugins/lt/` | `.claude-plugin/plugin.json`, `commands/`, `skills/`, `hooks/`, `lib/`, `scripts/`, `config/`, `statusline/`, `evals/` |
| **Repo consumidor** | `.lt/` no repositório de cada squad | `config.yaml`, `preferences.json`, `sensitive-paths.json`, specs do ciclo, audit local. Gerado por `lt:0-setup`. |

Os princípios que moldaram a engenharia deste repo, e que valem em qualquer organização:

- **Verificação antes de afirmação.** Nada é dado como funcionando sem um comando que prove.
- **Gate que não roda não aprova.** Guarda cuja dependência sumiu falha alto; nunca libera.
- **Conter o reversível compra o direito de bloquear o irreversível.** Um guarda que barra
  `rm -rf node_modules` no próprio repo é desligado na primeira semana, e junto vai a proteção
  real.
- **Auditabilidade nativa.** Toda decisão deixa trilha versionada.
- **Custo de IA é decisão de engenharia.** Medido, não estimado.

## 2. Mapa do repositório

| Caminho | Função |
|---|---|
| `.claude-plugin/marketplace.json` | manifesto: fonte única de nome, versão, cadência e fonte |
| `.claude/settings.json` | settings do próprio repo: `SessionStart` que roda `scripts/install-detect.sh` |
| `plugins/lt/` | o plugin core |
| `enterprise/` | payload de política gerenciada **fora de qualquer plugin**: `managed-settings.json`, três bootstraps, `verify.sh`, `uninstall.sh` |
| `scripts/` | instalador, atualizador, removedor, migração de symlink, bump, gates e `lib/` |
| `tests/` | `smoke/`, `e2e/`, `unit/`, `enterprise/`, `completeness-check.sh`, `fixtures/` |
| `docs/` | este guia, política de IA, fatos do host, análises com evidência, benchmarks |
| `config/` | `validate-allowlist.txt`, `forbidden-patterns.txt`, `bash32-forbidden.txt`, `deferred-components.txt` |
| `.github/` | `harness-ci.yml`, `lt-ai-checks.yml` (reusável), `plugin-eval.yml` |

`[DECISÃO]` **Padrões proibidos vivem em arquivos de dados, nunca dentro do teste que os cobra.**
Um guard textual que carrega os próprios literais casa a si mesmo e reprova o repositório
inteiro. Isso aconteceu **três vezes** aqui antes de virar regra.

## 3. Manifesto e os três números de versão

```json
{
  "name": "lt",
  "description": "LT AI Harness — harness corporativo de desenvolvimento assistido por IA da Lima Teixeira",
  "owner": { "name": "Lima Teixeira — Engenharia", "email": "..." },
  "plugins": [
    { "name": "lt", "description": "...", "version": "0.1.0",
      "cadence": "lockstep", "source": "./plugins/lt" }
  ],
  "version": "1.0.0"
}
```

`[HOST]` `claude plugin validate .claude-plugin/marketplace.json` passa com **um warning**:
`plugins[0].cadence: Unknown field 'cadence'`. O campo é metadado do repo, não do host: é lido
por `bump-version.sh` e por `tests/enterprise/version-pin.sh`. O aviso está em
`config/validate-allowlist.txt` **com data de caducidade** — e o gate falha se ele **deixar** de
aparecer, porque aí a allowlist virou mentira.

| # | Onde | Quem bumpa | O quê |
|---|---|---|---|
| 1 | `plugins[].version` + `plugin.json` | `bump-version.sh` | versão de cada plugin |
| 2 | `.version` raiz do manifesto | **manual, sempre** | versão do arquivo de manifesto; muda quando um plugin entra ou sai |
| 3 | `## [X.Y.Z]` no `CHANGELOG.md` | manual, mesma PR | espelha o core desde o dia 1 |

`[DECISÃO]` O plugin nasce em `0.1.0`, não `1.0.0`. `v1.0.0` significa uma coisa só: o checklist
do Apêndice J está verde. Nascer em `1.0.0` seria uma afirmação que o repo não sustenta.

## 4. Anatomia do plugin

`[OFICIAL]` O `plugin.json` só aceita um conjunto de chaves documentado. Quatro que **parecem**
válidas e não são:

| Chave | Por que fica de fora |
|---|---|
| `hooks` | *"Don't put `commands/`, `agents/`, `skills/`, or `hooks/` inside `.claude-plugin/`"*. Hooks vivem em `hooks/hooks.json`. |
| `statusLine` | não existe no schema de manifesto. Só o instalador entrega a barra. |
| `skillListingBudgetFraction` | **não aparece na documentação oficial** (verificado: zero ocorrências em `settings-reference` e `managed-settings`) |
| `outputStylesPath` | declarar desliga o auto-carregamento de `output-styles/` |

`[OFICIAL]` **Frontmatter de `SKILL.md`** tem 20 chaves documentadas. Este repo usa `name`,
`description`, `compatibility` e `metadata`. Três chaves que vieram do harness de origem —
`version`, `category`, `depends_on` — **não são oficiais** e o host as ignorava; passaram para
`metadata`, que a doc declara como YAML livre. Um gate no smoke reprova chave fora da lista.

`[OFICIAL]` Limites: `description` + `when_to_use` ≤ **1.536 chars** (cap do host); corpo do
`SKILL.md` ≤ **500 linhas** (recomendação). Aqui: maior description 726 chars, maior corpo 203
linhas.

`[ARMADILHA]` **Aspe o que parece estrutura.** Uma `description` não aspada contendo `: ` quebra
o YAML, e o host **descarta o frontmatter inteiro** — a skill passa a anunciar o primeiro título
do corpo como descrição. Uma skill deste repo shipou assim: nunca foi descoberta pelos gatilhos
que o autor escreveu, e nada acusou.

## 5. Hooks de segurança

`[HOST]` Dezesseis hooks, todos com `"timeout": 5` e referência **aspada** a
`"${CLAUDE_PLUGIN_ROOT}/..."` — o cache do plugin pode cair num caminho com espaço.

| Classe | Postura | Consulta o dial `guided`? |
|---|---|---|
| SEGURANÇA | `exit 2` ou `permissionDecision` | **nunca** |
| PROCESSO | lê o dial (`off` → avisa · `balanced` → `ask` · `strict` → `exit 2`) | sempre |
| TELEMETRIA / CONTEXTO | append-only, `exit 0` | — |

`[OFICIAL]` **O valor de `permissionDecision` importa mais do que parece:**

> A hook that returns `permissionDecision: "deny"` blocks the tool **even in `bypassPermissions`
> mode or with `--dangerously-skip-permissions`**. (…) The reverse is not true.

`[ARMADILHA]` Uma frota que roda `--dangerously-skip-permissions` **anula** toda guarda baseada
em `"ask"`: onde não há prompt, `ask` não faz nada. A guarda de segredos deste repo estava
inteiramente em `ask` — inerte exatamente nas máquinas que mais confiavam nela. Hoje `critical`
→ `deny`, `high` → `ask`. `exit 2` sobrevive ao bypass (provado ao vivo).

`[ARMADILHA]` **Casar o texto do comando inteiro produz falso positivo que desliga o hook.** Os
guardas deste repo bloquearam a própria sessão que escrevia a documentação deles, porque a
documentação **mencionava** os comandos. `lib/shell_text.py` separa o que o shell **executa** do
que é **dado**: `bash -c "<destrutivo>"` bloqueia, `grep -n "<destrutivo>" README` passa. O
limite está escrito no cabeçalho: é separador lexico, não parser de shell.

**Modo degradado** (sem `python3`): sobre-bloqueia **e anuncia no stderr**. Sem `grep` também:
escala para `ask`. Guarda que desaparece junto com a dependência é pior que guarda nenhuma — o
time acredita estar protegido.

## 6. Audit trail

`[FATO]` Toda escrita passa por `plugins/lt/scripts/approve.sh`. Existe porque o classificador
de auto mode barra redirecionamento de shell para `~/.claude` — corretamente: trilha que o
próprio auditado escreve com `echo` não é trilha.

Vocabulário em três classes; TSV de 5 campos
`<epoch>\t<token>\t<contexto>\t<operador>\t<mode=human|flow|auto>`. O quinto campo diz **como**
foi aprovado: sem ele a trilha afirmaria que um humano conferiu quando quem conferiu foi o agente.

`[FATO]` Dois furos fechados, ambos no cabeçalho do script: casamento **exato** do token (os
hooks leem por substring — um slug `fix-destructive-cleanup` abriria a guarda `destructive`); e
sanitização de `\t\r\n` (um TAB no e-mail desloca as colunas e quebra todos os parsers em
silêncio). Em `--mode auto`, todo token que abre guarda é **recusado**: o ciclo autônomo não
assina a própria licença.

`[ARMADILHA]` `flock(1)` **não existe no macOS**. `lib/lt-lock.sh` usa `flock` onde há e cai para
spin-lock por `mkdir`. E o fallback de `mtime` devolve o instante **atual**, não zero — com zero
a idade vira o epoch inteiro e o lock é declarado envelhecido de 56 anos.

## 7. Statusline

`[HOST]` **Plugin nenhum entrega a barra principal.** `statusLine` não é campo de `plugin.json`,
e pelo `settings.json` de um plugin só passam `agent` e `subagentStatusLine`. Quem entrega é o
instalador, num **caminho estável** (`<perfil>/lt/statusline-shim.sh`), nunca no cache versionado,
que é podado a cada update.

`[ARMADILHA]` Ordenação lexica escolhe `0.9.4` sobre `0.10.0`: a barra exibe dados de uma versão
antiga enquanto os hooks já rodam a nova, e o sintoma não aponta para a causa. `vc_gt` compara
semanticamente, com `10#` nos componentes (`08` é octal inválido e aborta sob `set -e`).

`[DECISÃO]` `skipped-foreign` é o caminho **principal** aqui, não a exceção: muita gente já tem
barra própria. Uma recusa seca significaria que ninguém vê a barra, então o `doctor` imprime uma
**receita de composição** e o shim aceita `--segments-only` desde o início.

## 8. Ciclo SDD

`[FATO]` Onze skills: `analyze-project → create-prd → create-technical-specification →
create-tasks → execute-task ⇄ review → bugfix → refactor`, mais `agent-governance`,
`execute-all-tasks` e `us-to-prd`.

Regra absoluta: **nunca `create-tasks` sem TechSpec aprovada; nunca `execute-task` sem
`tasks.md` aprovado.**

`[DECISÃO]` **O diretório de specs pertence ao repositório onde o comando roda.** Em
`produto-a` a spec é `produto-a/<specs>/prd-<slug>/`; em `produto-b`, `produto-b/<specs>/…`.
Isso é segurança, não arrumação: spec no repo errado faz a rastreabilidade `RF → código` mentir
e o `check-spec-drift` comparar o requisito de um produto com a implementação de outro.
Todo subcomando **recusa** (`exit 3`) alvo fora da raiz detectada. O nome do diretório é
**detectado** (`LT_TASKS_ROOT` → `.specs/` existente → `.lt/specs/`), não imposto: um repo que já
tem histórico de PRDs não deve ganhar um segundo lugar para a mesma coisa.

`[FATO]` Gates reimplementados em `lib/sdd.py`, com o que **se perde** dito no cabeçalho sem
alegar paridade: validação de descendência de commit, detecção de capacidade de runtime, schema
JSON versionado. O que fica: integridade `spec-hash`, schema de `tasks.md`, DAG, cobertura de
requisitos, contrato de evidência e máquina de estados.

Quatro regras **fail-closed**, cada uma com teste: `sync-spec-hash` recusa rodar sobre artefato
aprovado que mudou (senão sincronizar hash vira a forma mais fácil de esconder drift);
`approve` recusa fora de ordem e recusa reaprovar o que não mudou; `invalidate` propaga `stale`;
`seal-evidence` rejeita critério sem `-> comprovado:` **e** rejeita seção vazia — ausência de
critério não é prova de que foi atendido.

## 9. Instalação, atualização, remoção e migração

`[ARMADILHA]` `claude plugin marketplace update` responde `✔ Successfully updated` e **não troca
o que roda** — só atualiza o clone. Quem re-resolve o registro é `claude plugin update <p>@<mkt>
--scope user`, mais o restart. Parar no primeiro comando e ver o ✔ é o erro natural.

`[DECISÃO]` O instalador não depende da consolidação do host: um reconciliador garante **cache →
registry → settings** e **valida os três** no fim. Primitivas que valem copiar: `safe_segment`
(rejeita `/ \ .. NUL`), `confine` (realpath + commonpath), `backup_and_write` atômico que
**preserva chaves desconhecidas**, `dir_signature` para idempotência, `heal_scopes`, e
`_chmod_hooks` — o git não preserva `+x` quando o host baixa por zip, e sem o bit o hook existe,
é referenciado corretamente e simplesmente não roda.

`[ARMADILHA]` **Uma máquina pode ter vários perfis de configuração** (`CLAUDE_CONFIG_DIR`).
Instalar no perfil errado é a pior classe de erro aqui: nenhuma mensagem, o comando diz que
funcionou, e o harness não aparece. O instalador imprime em qual perfil está operando e lista os
outros como não tocados.

`[DECISÃO]` **Migração de mecanismo anterior** (aqui, symlinks) é peça de primeira classe:
classificação pelo **alvo resolvido** (nunca pelo nome), arquivamento com manifesto escrito antes
do move, `--restore`, e recusa de rodar antes do substituto estar instalado. `mv` de um symlink
move o link, não o alvo — nada do trabalho de ninguém é apagado.

### 9.1 Paridade com Codex, Copilot e OpenCode

`[DECISÃO]` **Fonte única, projeção gerada.** Os outros hosts não recebem uma segunda cópia
editável do harness. `plugins/lt/scripts/reconcile-hosts.py` projeta:
- as skills, os agents e os comandos (convertidos em skill onde o host não tem comando);
- o runtime de hooks, para dois escopos:
  - `project`: `.agents/skills`, `.codex/`, `.github/`, `.opencode/` e `AGENTS.md`;
  - `global`: `~/.agents/skills`, `$CODEX_HOME`, `$COPILOT_HOME`, `$XDG_CONFIG_HOME/opencode`
    e o runtime em `~/.lt-harness/`.

Todo evento de host passa por `plugins/lt/lib/host-dispatch.py`. Ele lê o `hooks.json` canônico e
roda os mesmos scripts. Hook novo no plugin chega aos quatro hosts sem editar o adaptador.

`[HOST]` Trust é a armadilha comum aos três. O Codex exige trust do projeto **e** um
`trusted_hash` por hook no `config.toml` do usuário. O Copilot exige a pasta em `trustedFolders`.
Sem isso, os hooks de repositório são pulados **em silêncio**. O escopo global evita a primeira
metade, porque os hooks pessoais do Copilot e do OpenCode não pedem trust. O instalador grava os
hashes do Codex. Detalhes e a prova ao vivo nos quatro hosts estão em `docs/host-facts.md`. A
matriz `docs/capability-matrix.md` é gerada e cobrada por `scripts/check-host-parity.sh`.

`[ARMADILHA]` No Codex, deny por JSON com stderr vazio vira "hook Failed", e **a ferramenta
executa**. O adaptador sempre promove a razão para o stderr. Um `apply_patch` com segredo passou
na primeira prova ao vivo por causa disso.

## 10. Distribuição enterprise

`[OFICIAL]` Caminhos, conferidos na documentação:

| SO | Caminho |
|---|---|
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Linux e WSL | `/etc/claude-code/managed-settings.json` |
| Windows | `C:\Program Files\ClaudeCode\` |

`[ARMADILHA]` O caminho `C:\ProgramData\ClaudeCode\` é **legado e não é lido**. A documentação é
explícita. Instalar ali não dá erro e não faz nada — o pior resultado possível para uma política
de segurança. Há teste que reprova o caminho errado.

`[DECISÃO]` Três escolhas registradas no próprio payload:
- **`permissions.defaultMode` ausente.** Managed vence user; mandar `"default"` rebaixaria em
  silêncio quem escolheu `auto`, no primeiro restart.
- **`allowManagedMcpServersOnly: false` na wave 1.** Ligar `true` sem inventário corta conector
  em uso — e o harness leva a culpa.
- **Nenhuma chave não documentada.** Governança sobre chave que pode sumir num upgrade não é
  governança.

`[DECISÃO]` A política escrita **nomeia os servidores**, não só os vendors: `allowedMcpServers`
recebe nomes de servidor, e um documento que só cita vendor não permite auditar se o declarado
corresponde ao decidido. Um teste casa nos **dois sentidos**.

`[ARMADILHA]` `enabledPlugins` no managed-settings **não materializa o cache**. O dev reinicia e
não tem harness, sem erro. O bootstrap termina mandando instalar — e o aviso aparece em três
lugares de propósito.

## 11. Versionamento e release

`[ARMADILHA]` Um bump que imprime `✓ arquivo` sem verificar se o arquivo mudou **mente por
releases inteiras**. Todo passo prova com `cksum` e distingue três resultados: mudou (`✓`), não
mudou mas o alvo já está lá (`=`, reexecução tolerada), não mudou e o alvo **não** está lá (`✗`,
falha). O teste compara com um `stamp()` sem esse ramo: o mesmo padrão quebrado passa com exit 0.

`[ARMADILHA]` **`\b` não existe no sed do BSD.** A expressão não casa nada no macOS e o arquivo
fica intocado, em silêncio — a classe "verde no CI Linux, morto no Mac" dentro do script de
release.

**A tag é o deploy.** `release.yml` valida `tag == versão do core` selecionada **por nome**
(`select(.name=="lt")`), nunca por índice.

## 12. Testes

| Suíte | Banner | Prova |
|---|---|---|
| `tests/smoke/run.sh` | `SUITE PASSOU` | presença, JSON, chaves mortas, `${CLAUDE_PLUGIN_ROOT}` aspado em todo `hooks.json` **descoberto por find**, invariante de segurança, frontmatter oficial, descontaminação, bash 3.2 |
| `tests/completeness-check.sh` | `TUDO ENTREGUE` | inventário **cruzado com disco** |
| `tests/e2e/run.sh` | `E2E PASSOU` | hooks com payload do host; ciclo SDD num repo git de sandbox; os negativos |
| `tests/enterprise/run.sh` | `ENTERPRISE PASSOU` | pin, schema do payload, dry-run dos bootstraps |
| `tests/unit/run.sh` | `Suite unit passou` | descoberta por `find`, nunca por lista fixa |

**Os cinco princípios, cada um pago com um defeito real:**

1. **Lista canônica cruza com disco.** Provado criando um `hook-fantasma.sh`: duas suítes
   independentes reprovaram. Sem o cruzamento, inventário é verde por construção.
2. **`skip` ≠ `fail`.** Dependência ausente é amarelo **contado**.
3. **`HOME` e perfil isolados.** Um teste com `HOME` isolado mas `CLAUDE_CONFIG_DIR` apontando
   para o perfil real escreveu dez linhas falsas no audit trail de produção — e **passou verde**,
   porque as linhas que ele mesmo criou satisfaziam as próprias asserções.
4. **Teste de regressão que falha contra o código antigo.**
5. **Suíte gateada pelo banner**, não só pelo exit code: um `set -e` mal posto devolve 0 com
   metade dos testes pulados.

## 13. CI

Matriz `ubuntu` + `macos` com `fail-fast: false`. Job dedicado que **confirma que o `/bin/bash`
do runner ainda é 3.x** — se um dia subir, o job falha alto, em vez de continuar exibindo uma
garantia que deixou de valer. O job de host instala o CLI e `exit 1` se ele faltar.

`[DECISÃO]` **Ordem de adoção** para organização sem CI: tudo nasce em `report` (roda, escreve no
resumo, sai 0); a promoção para `block` é um diff de uma linha. Todos os scans olham **só linhas
adicionadas**, então ligar o gate não transforma o passado em dívida vermelha.

## 14. Evals

`[OFICIAL]` A pergunta nº 1 do guia de avaliação de agentes da OpenAI é *"Did the agent pick the
right tool?"*. E a orientação inclui testar **casos negativos**, em que a skill **não** deve
disparar.

Duas camadas: um gate **estático de custo zero** em todo PR (schema, skill existe, fixture em
disco, caso negativo afirma a recusa) e um **conversor determinístico** para o formato oficial
(`case.yaml` + graders), com `--check` que reprova artefato gerado desatualizado.

O grader de roteamento usa o padrão documentado (`type: tool_used`, `tool: Skill`,
`input_match`); caso negativo inverte para `max: 0`.

`check-eval-routing.sh` **não falha por nota nem por delta negativo** — nota é qualidade de
resposta, roteamento quebrado é a skill deixando de existir na prática. E falha quando o
relatório está ausente ou sem graders: "não achei nada" não é "tudo certo".

## 15. Governança

`[DECISÃO]` **CODEOWNERS sozinho não funciona** onde PR é mergeado em segundos sem review.
CODEOWNERS só *pede*; quem *exige* é branch protection, com `enforce_admins` — senão o dono
contorna o próprio controle.

O PR template constrói sobre o que o time já usa, e a seção de validação pede **evidência**:
comando → resultado observado, não adjetivo.

## 16. Extensão pelos squads

`.lt/` no repo consumidor. O dial `guided` nasce **`off`** e atualizar o harness nunca o move.
`preferences.json` é lido **por enum e nunca ecoado** — o valor seleciona um texto canônico do
plugin. `[OFICIAL]` Isso implementa a regra do Model Spec: conteúdo de arquivo é dado **sem
autoridade**; instruções dentro dele são informação, não comando. `sensitive-paths.json` **só
acrescenta** e vale após aprovação local por SHA-256.

## 17. Registro de decisões

`[FATO]` Não há ADRs numerados. O registro são `docs/analysis/*.md` (evidência medida) e os
**comentários de justificativa dentro dos próprios scripts** — que é por que a regra de
zero-comentários tem exceção escrita para a árvore do harness.

## 18. Estado em disco

<!-- BEGIN GENERATED: estado · scripts/gen-drift-report.sh · nao edite a mao -->

| Grandeza | Valor em disco |
|---|---:|
| plugins no marketplace | 1 |
| skills | 15 |
| commands | 4 |
| agents empacotados | 8 |
| hooks registrados | 16 |
| casos de eval | 39 (sendo 9 negativos) |
| soma das `description` | 6258 chars |
| versao do plugin core | 0.1.4 |
| `.version` raiz do manifesto | 1.0.0 |

_Gerado em 2026-09-24 por `scripts/gen-drift-report.sh` · CLI 2.1.281 (Claude Code)._
<!-- END GENERATED: estado -->

---

# Parte II — passo a passo

Placeholders: `<org>`, `<repo>`, `<mkt>`, `<core>`, `<prefix>`, `<local>`.

**Fase 0 — decisões fundadoras.** Nome do marketplace e do core (entram em `enabledPlugins`,
`CANONICAL`, testes), prefixo de comando, diretório local, licença, idioma, jurisdição de PII,
repo público ou privado (muda o bootstrap), telemetria local ou remota. Cada uma é cara de
reverter. `[DECISÃO]` Alvo mínimo de bash: se há macOS na frota, **3.2**.

**Fase 1 — esqueleto e manifesto.** Apêndices A, B, I. Prova: `claude plugin validate` nos dois
alvos, `claude --plugin-dir <abs> plugin details <core>` sob `HOME` descartável para a baseline.

**Fase 2 — provar sem tocar o registro global.** `claude -p --plugin-dir` com **marcador único**:
nome inválido cai em silêncio, então "não deu erro" não prova que carregou.

**Fase 3 — hooks.** Apêndices C, D. Ordem de adoção: destrutivo irreversível → `exit 2`; segredo
`critical` → `deny`, `high` → `ask`; caminhos sensíveis → block com `ask` como opt-in do squad;
processo consulta o dial; `UserPromptSubmit` só avisa. Separe texto **executado** de **dado**
desde o início.

**Fase 4 — audit trail.** Porta única, três classes de token, TSV de 5 campos com `mode`, recusa
de bypass em `auto`, lock portátil.

**Fase 5 — statusline.** Shim em caminho estável, comparação semântica, `skipped-foreign` com
receita de composição.

**Fase 6 — instalador.** Reconciliador com os três alvos, validação end-to-end, honrar
`CLAUDE_CONFIG_DIR`, e a migração do mecanismo anterior se houver.

**Fase 7 — enterprise.** Payload pinado em tag, três bootstraps (tag existe → baixar → `jq empty`
→ copiar → verify), `verify.sh`, `*_DRYRUN` para o CI. Confira os caminhos por SO na
documentação, não na memória.

**Fase 8 — versionamento.** `bump-version.sh` com guards `cksum`; CHANGELOG manual; a tag é o
deploy.

**Fase 9 — testes.** As cinco suítes e os cinco princípios da §12.

**Fase 10 — CI.** Matriz mac+linux, guarda de bash 3.2, host job que falha sem CLI, workflow
reusável com `enforce: report|block`.

**Fase 11 — gates e ratchets.** Baselines versionadas; regravar exige justificativa no PR.

**Fase 12 — governança.** CODEOWNERS **mais** branch protection.

**Fase 13 — extensão pelos squads.** `<local>/`, dial nascendo `off`, preferências por enum.

**Fase 14 — evals.** Gate estático primeiro; eval pago atrás de label com teto de custo;
roteamento medido separado da nota.

---

# Parte III — mínimo viável vs completo

| # | Peça | Sem ela |
|---|---|---|
| 1 | manifesto + `plugin.json` com os três números | não há o que instalar |
| 2 | hooks com config JSON única e resolvedor em uma invocação | segurança depende de o agente lembrar |
| 3 | porta única de audit com allowlist de tokens | trilha falsificável |
| 4 | instalador que valida os três alvos | cada máquina num estado |
| 5 | as cinco suítes com banner | "CI verde" não significa nada |
| 6 | gates de host no CI que **falham** sem o CLI | chaves mortas passam meses |
| 7 | payload enterprise pinado em tag | política sem distribuição |

**Dá para adiar:** plugins opt-in, output styles, integrações, catálogo curado, eval pago.

**Não dá para adiar:** a regra de bash 3.2 escrita **antes do primeiro hook**; o `.gitignore` que
impede estado local de entrar; a separação executado/dado nos guardas; e o isolamento de `HOME`
**e** perfil nos testes.

---

# Parte IV — armadilhas recorrentes

- **Verde falso é o defeito mais caro.** Seis formas vistas aqui: `sed` que não casa e imprime ✓;
  lista canônica que valida só o que ela lista; suíte que sai 0 sem chegar ao banner; gate que
  imprime erro e segue para o sucesso; teste que escreve no ambiente real e passa por causa
  disso; guard cuja dependência sumiu e libera em silêncio.
- **Guard textual casa o próprio texto.** Padrões proibidos em arquivo de dados, e o teste se
  exclui da varredura. Aconteceu três vezes.
- **O valor de `permissionDecision` decide se a guarda existe.** Sob bypass, só `deny` e `exit 2`
  sobrevivem.
- **Sobre-bloquear desliga o hook.** Separe executado de dado, ou o guarda bloqueia a
  documentação dele mesmo.
- **`\b` não existe no sed do BSD.** E `flock(1)` não existe no macOS. E `08` é octal inválido.
- **Perfil de configuração errado é silencioso.** Nenhum erro, e o harness não aparece.
- **Caminho legado de política no Windows não é lido.** Instalar ali não dá erro e não faz nada.
- **A tag é o deploy.** Enquanto ela não sai, a mudança não existe para ninguém.
- **Nunca escreva uma contagem em prosa sem um teste que a cruze com `ls`.**

---

# Apêndices

**A. `marketplace.json`** — cinco chaves na raiz, cinco por plugin. Nada mais.
**B. `plugin.json`** — conjunto fechado; sem `hooks`, `statusLine`, `outputStylesPath` nem chave
não documentada.
**C. `hooks.json`** — `"${CLAUDE_PLUGIN_ROOT}/..."` **aspado**, `"timeout"` em toda entrada.
**D. Skeleton de hook** — `set -uo pipefail`; cap `"${INPUT:0:100000}"` antes de regex; curto-
circuito antes de qualquer fork; categoria na linha 3; modo degradado que sobre-bloqueia e
anuncia.
**E. `managed-settings.json`** — pin em tag, `del(.branch)`, sem chave não documentada,
`defaultMode` ausente.
**F. `release.yml`** — suítes, `tag == versão do core` **por nome**, artefatos de `enterprise/`.
**G. Regex de commit e CODEOWNERS** — mais branch protection com `enforce_admins`.
**H. `.claude/settings.json` do repo** — `SessionStart` de auto-detecção, **sem**
`extraKnownMarketplaces` com `ref`.
**I. `.gitignore`** — `<local>/`, estado pessoal, `__pycache__`, outputs de teste.

**J. Checklist antes do primeiro `v1.0.0`**

- [x] `claude plugin validate` limpo (só warnings allowlistados) e `--strict` no plugin
- [x] baseline de custo medida sob `HOME` descartável e gravada — e guardada por `scripts/check-cost-baseline.sh` no job de host
- [x] todo `hooks.json` com referência aspada; nenhum `plugin.json` com `hooks`
- [x] cada hook com teste positivo **e** negativo, `HOME` **e** perfil isolados — os quatro que faltavam em `tests/unit/hooks/behavior.test.sh`, sobre payload real sondado
- [x] porta de audit recusa bypass em `--mode auto`
- [x] instalador idempotente; segunda rodada dá `unchanged`; `--dry-run` não escreve — `tests/unit/scripts/reconcile-idempotent.test.sh`
- [ ] `managed-settings.json` pinado em tag; caminhos por SO conferidos na documentação
- [x] `bump-version.sh` com guards `cksum` e teste que compara com a versão sem o guard
- [ ] CI em matriz mac+linux; job de host falha sem CLI
- [x] contagens em prosa guardadas por teste — `scripts/validate-playbook-counts.sh`, dentro de `tests/docs-generated-fresh.sh`
- [x] gate estático de evals verde; eval pago atrás de label com teto
- [x] nada do ambiente de quem construiu no repo
- [ ] tag empurrada → release publicada → bootstrap em máquina limpa → verify → instalar →
      restart → doctor
