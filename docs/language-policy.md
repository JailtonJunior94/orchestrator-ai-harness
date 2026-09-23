# Política de idioma — onde mora cada regra e quem a cobra

Este documento **não** define regra de idioma. Ele diz onde cada regra mora e qual gate a cobra.
A razão é o princípio "uma regra, um dono": a mesma afirmação escrita em dois lugares diverge na
primeira edição, e aí o agente obedece à cópia que leu por último.

## Os donos

| Para quem | Dono único | O que ele decide |
|---|---|---|
| Quem edita **este** repositório | `CLAUDE.md` §6 (tabela "Idioma") | idioma de `description`, prosa de doc, mensagens de hook, nomes de arquivo e diretório, IDs de regra, tokens de audit, commits, PRs, branches e comentários de script |
| O que o plugin diz aos **repos consumidores** | `plugins/lt/config/policy-texts.md` | o texto canônico selecionado pela preferência `output_language` de `.lt/preferences.json` |
| O **código** que as skills produzem nos repos dos times | `plugins/lt/config/constitution.md`, regra `R-STYLE-001.1` | idioma de identificadores, mensagens de erro, logs e nomes de teste |

Qualquer outro arquivo que precise falar de idioma **aponta** para um destes três, com link,
em vez de reescrever a regra. Uma skill que precisa lembrar o agente do idioma de saída cita
`policy-texts.md`; um doc de contribuição cita o `CLAUDE.md` §6.

## Por que a preferência é enum

`output_language` em `.lt/preferences.json` não é texto livre: o valor só **seleciona** um dos
textos escritos em `policy-texts.md`. Um repositório de terceiro que a pessoa abra não consegue,
por esse arquivo, injetar instrução no contexto da sessão. Valor fora da enum cai no default e o
hook anuncia `lt_pref_unknown_enum` no stderr. A leitura mora em `plugins/lt/lib/preferences.sh`
e no `session-start.sh`.

## Quem cobra

| Gate | O que verifica |
|---|---|
| `tests/language-policy-check.sh` | afirmação absoluta de idioma fora dos donos acima; nomes de skill, command, agent e hook em kebab ASCII; nomes de arquivo ASCII; tokens do audit trail em kebab ASCII; este documento apontando para os donos |
| `scripts/validate-frontmatter.sh` (código `E6`) | `description` de skill, command e agent lida como pt-BR, por heurística de palavras funcionais e diacríticos |
| `.github/workflows/lt-ai-checks.yml` (job de formato de commit) | título de commit no padrão Conventional Commits, no repo consumidor; nasce advisório |

A heurística do `E6` é deliberadamente simples e conservadora: conta palavras funcionais e
acentos do português contra palavras funcionais do inglês. Ela existe para pegar a `description`
colada de outro projeto, não para julgar estilo. Falso positivo se resolve reescrevendo a
`description` com os gatilhos no idioma do time — que é o que o roteamento do host precisa.

## Exceções

Citação literal (mensagem de erro do host, trecho de documentação oficial, frase que a pessoa
digita e a skill precisa reconhecer, como `"blocked by enterprise policy"`) fica no idioma
original: é dado, não regra. Qualquer outra exceção entra **no dono** da regra, por PR, e não
num comentário no arquivo que quer ser exceção.
