Responda reproduzindo EXATAMENTE o texto entre as marcas <<<RESPOSTA e RESPOSTA>>>, sem as marcas, sem comentar e sem acrescentar nada antes ou depois.

<<<RESPOSTA
**Status: `needs_input`.** Não editei o PRD. O bundle já tem `techspec.md` e `tasks.md` aprovados, e essa mudança os afeta.

**O que fica desatualizado:**
- `techspec.md` e `tasks.md` foram gerados a partir desta versão do PRD. Hoje eles só cobrem RF-01 e RF-02, com o endpoint `.csv` e a tarefa 1.0.
- Não é um ajuste pequeno: o PDF sai de "Fora de escopo" e vira um requisito novo, o RF-03. O `spec-version` passa de 1 para 2 e o `spec-hash-prd` em `techspec.md` e `tasks.md` deixa de bater. Com isso, o `execute-task` fica `blocked` até a techspec e as tasks serem refeitas e aprovadas de novo.

**Como você quer seguir?**
- **(a) Seguir (recomendado):** eu atualizo o PRD e marco o bundle para revisão (`lt-sdd.sh invalidate <bundle> --from prd`). Aí a techspec e as tasks precisam ser refeitas e aprovadas de novo.
- **(b) Só ajustes que não mudam requisito:** não serve para este pedido. Incluir o PDF é, por definição, um requisito novo.
- **(c) Cancelar.**

**Se for (a), preciso de três respostas:**
1. **Conteúdo e período do PDF:** mesmos campos do CSV (data, descrição, valor, saldo) e só o mês corrente? Ou o PDF deve ter algo a mais, como cabeçalho com dados do cliente e do banco, saldo inicial/final ou validade como comprovante?
2. **Canal:** só pelo app, como o CSV, ou também por e-mail ou internet banking?
3. **Meta de sucesso:** o objetivo continua sendo "reduzir pedidos de extrato ao suporte". Existe um número a atingir, por exemplo X% a menos de chamados em N meses?

**Mudança proposta** (só para você revisar, não foi aplicada):

```diff
-<!-- spec-version: 1 -->
-# PRD — Extrato em CSV
+<!-- spec-version: 2 -->
+# PRD — Extrato em CSV e PDF
 ...
 - RF-02: o CSV traz data, descrição, valor e saldo, em UTF-8.
+- RF-03: o cliente exporta o extrato do mês corrente em PDF pelo app, com data, descrição, valor e saldo.

 ## Fora de escopo
-- Exportação em PDF.
+(vazio, ou o que sair das respostas acima)
+
+## Histórico
+- v1 → v2: exportação em PDF saiu de "Fora de escopo" e entrou como RF-03.
```

RF-01 e RF-02 continuam com a mesma numeração e o mesmo texto.

Como o repositório não está disponível nesta sessão, vou te devolver o `prd.md` completo em texto. Os comandos `invalidate` e, depois da sua revisão, `lt-sdd.sh approve <bundle> prd` você roda aí. A aprovação é sua; eu não aprovo o PRD.
RESPOSTA>>>
