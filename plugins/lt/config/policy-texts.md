# Textos canônicos selecionados por enum

Este arquivo existe por uma razão de segurança, não de organização.

O `session-start.sh` injeta preferências no contexto. Se ele ecoasse o **conteúdo** de
`.lt/preferences.json`, qualquer repositório de terceiro que a pessoa abrisse poderia escrever
instruções nesse arquivo e elas entrariam no system prompt. Com a indireção, o valor do arquivo é
apenas uma **chave**: ele seleciona um dos textos abaixo, todos escritos aqui, versionados e
revisados por PR. Valor fora da enum resolve para o default e emite `lt_pref_unknown_enum` no
stderr.

O mesmo vale para `preferences.json` no nível da máquina. Nenhum texto de preferência vem de fora
deste arquivo.

---

## code_comments

### code_comments=none
Não escreva comentários no código. O código deve ser autoexplicativo: nomes claros, funções
pequenas, early return.

### code_comments=minimal
Escreva comentário apenas onde a intenção não é recuperável do código — a razão de uma decisão, não
a descrição do que a linha faz.

### code_comments=explanatory
Comente decisões e trechos não óbvios, incluindo o porquê de alternativas descartadas.

---

## output_language

### output_language=pt-BR
Responda em português do Brasil. Identificadores de código, nomes de arquivo e títulos de commit
permanecem em inglês.

### output_language=en
Respond in English.

---

## coauthor_trailer

### coauthor_trailer=on
Acrescente o trailer de co-autoria nos commits que você criar.

### coauthor_trailer=off
Não acrescente trailer de co-autoria.

---

## guided

### guided=off
Modo guiado desligado. Hooks de processo apenas avisam; nada é bloqueado por falta de spec.

### guided=balanced
Modo guiado equilibrado. Escrever código sem spec ativa pede confirmação humana.

### guided=strict
Modo guiado estrito. Escrever código sem spec ativa é bloqueado.

---

## Nota sobre o dial `guided`

O dial nasce `off` de propósito, e atualizar o harness nunca o move. Apertar o parafuso de alguém
sem que a pessoa tenha pedido é o caminho mais curto para o harness ser desinstalado.

Precedência: `LT_GUIDED` > `.lt/config.yaml` (`guided:`) > `off`.

**Hook de segurança não lê este dial.** Nunca. O dial regula rigor de processo; postura de
segurança não é negociável por configuração de projeto.
