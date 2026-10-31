# Revisão de Spec em Contexto Zero

<!-- TL;DR
Rubrica única para revisar PRD e techspec antes da aprovação humana, aplicada por um subagente que leu só o artefato no disco (sem o histórico de quem escreveu). Três lentes: Zoom-out (YAGNI, reuso, escopo vs PRD), Compreensão (teste de paráfrase) e Prontidão (dá para implementar sem perguntar). Saída fixa: achados 🔴 Blocker / 🟡 Major / 🟢 Nit com seção e evidência, paráfrase, contestações. Teto de UMA re-auditoria; residual vira "Trade-offs aceitos" no artefato.
Keywords: revisão de spec, contexto zero, PRD, techspec, zoom-out, paráfrase, prontidão, blocker, trade-off, re-auditoria, goldfish
Load complete when: um subagente revisor recebe um PRD ou techspec para revisar, ou uma skill de redação precisa triar o relatório dessa revisão.
-->

- Rule ID: R-SPEC-001
- Severidade: hard para o formato de saída e para o teto de re-auditoria; guideline para o conteúdo das lentes
- Escopo: `lt:spec-reviewer` (aplica), `create-prd` e `create-technical-specification` (triam o resultado)

## Objetivo

Dar ao humano, ao lado do pedido de `approve`, a leitura de alguém que **não** escreveu o
artefato. O mesmo contexto que redigiu valida as próprias suposições; um leitor sem esse
contexto encontra o que ficou implícito, sobrou ou falta. É a aplicação de I-3 da constitution
aos artefatos de spec.

## Pré-condições do revisor

- Leu só o artefato (`prd.md`, ou `techspec.md` + `prd.md`), nada da conversa de quem redigiu.
- Sem ferramenta de subagente no host, **esta rubrica não é aplicada no mesmo thread** como se
  fosse revisão independente. A skill declara que o artefato vai à aprovação sem revisão de
  contexto zero e segue.

## Lente 1 — Zoom-out

- **Escopo**: a techspec resolve o PRD e só o PRD. Decisão sem `RF-nn` que a sustente é achado;
  `RF-nn` sem decisão é achado.
- **YAGNI**: camada, abstração, configuração ou dependência sem demanda concreta no PRD é Major.
- **Reuso**: o artefato ignora algo que o repositório já tem (módulo, padrão, adapter) e propõe
  um paralelo? Citar o caminho existente; sem caminho, não é achado.
- **Fora de escopo**: tudo que o PRD exclui continua excluído na techspec.

## Lente 2 — Compreensão (teste de paráfrase)

Escrever, em até 3 linhas, o objetivo e os requisitos como você os entendeu, **sem copiar frases
do artefato**. Se não consegue, ou se duas leituras cabem na mesma frase, é 🔴 Blocker: o humano
vai aprovar algo que dois implementadores lerão diferente. A paráfrase vai no relatório; é ela
que o autor confronta.

## Lente 3 — Prontidão

Para o **PRD**: todo `RF-nn` é numerado, verificável e tem critério de sucesso que um teste
consegue derrubar. RF que descreve solução em vez de necessidade é Major.

Para a **techspec**: toda interface, modelo de dados e integração citados têm forma concreta o
bastante para codificar sem perguntar; toda linha da `Matriz Requisito → Teste` nomeia o
comportamento que o teste derruba (R-TEST-002.5); toda decisão material tem ADR ou justificativa.
Pergunta que um implementador faria na primeira hora e o doc não responde é 🔴 Blocker.

## Severidade

| Nível | Significado | Efeito |
|---|---|---|
| 🔴 Blocker | aprovado assim, gera implementação errada ou duas implementações diferentes | precisa de correção ou contestação com evidência antes do `approve` |
| 🟡 Major | custo evitável ou lacuna que vai virar pergunta durante a execução | corrigir ou registrar em `## Trade-offs aceitos` |
| 🟢 Nit | clareza, forma | opcional |

## Formato do relatório (`<bundle>/review-<prd|techspec>.md`)

```markdown
# Revisão de contexto zero — <prd|techspec>
- Artefato: <caminho>
- Rodada: 1 | 2

## Paráfrase
<até 3 linhas>

## Achados
- 🔴 Blocker | <seção do artefato> | <o que falta ou está ambíguo> | evidência: <trecho ou RF-nn>
- 🟡 Major | ...
- 🟢 Nit | ...
<ou exatamente "Sem achados">

## Contestações
<vazio na rodada 1; na rodada 2, uma linha por achado contestado: retirado | sustentado -> evidência>
```

Relatório vai para arquivo (R-COM-001.1). No chat, só a contagem e o caminho.

## Convergência — teto de uma re-auditoria

1. A skill de redação lê o relatório. Para cada achado: **corrige** o artefato ou **contesta** com
   evidência (`arquivo:linha`, `RF-nn`, comando) numa seção `## Contestações` do relatório.
2. Houve 🔴 Blocker corrigido ou contestado? Uma **única** re-auditoria (rodada 2), mesmo prompt.
   Sem Blocker, não há rodada 2.
3. O que sobrar depois da rodada 2 não gera rodada 3: vai para `## Trade-offs aceitos` do
   artefato, com o motivo, e o humano decide no `approve` com isso à vista. Loop de revisão sem
   fim custa mais do que o achado residual.
4. O checkpoint com a pessoa segue R-MC-001: uma pergunta, opções "Corrigir os achados agora
   (Recomendado) / Edito o documento manualmente / Pausar".

## Anti-padrões

- Revisar no mesmo thread que redigiu e chamar de independente.
- Achado sem seção nem evidência ("está vago").
- Elogio no lugar de achado (R-COM-001.2).
- Terceira rodada "só para fechar".
