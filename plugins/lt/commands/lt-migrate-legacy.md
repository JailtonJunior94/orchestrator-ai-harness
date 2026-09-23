---
description: Detecta e aposenta a distribuição antiga por symlink em ~/.claude/{skills,agents,commands}.
argument-hint: "[--detect|--apply|--restore <dir>]"
---

Antes de qualquer coisa, **detecte**. O padrão é read-only:

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/migrate-symlinks.sh" --detect
```

Apresente o resultado explicando a classificação:

- **nosso** — symlink apontando para `tools/modelo-generico/` do repositório de conhecimento.
  Convivendo com o plugin, cria **duas fontes da mesma skill**: a pessoa edita o repo e executa
  o cache, sem erro nenhum aparecer.
- **de terceiro** — qualquer outro alvo. Nunca é tocado. A classificação é pelo **alvo
  resolvido** (`realpath`), nunca pelo nome: uma skill pessoal com nome igual ao nosso, mas
  apontando para outro lugar, não é nossa.

## Para aposentar

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/migrate-symlinks.sh" --apply
```

Diga isto à pessoa, porque é a pergunta que ela vai fazer: **nada é apagado**. `mv` de um
symlink move o *link*, não o alvo — o conteúdo continua no repositório git. O link vai para
`<perfil>/lt/legacy-symlinks/<timestamp>/` com um manifesto, e há `--restore`.

O comando **recusa** rodar antes do plugin estar instalado: tirar o symlink sem o substituto
deixaria a pessoa sem skill nenhuma.

## Depois

Confirme com `lt:lt-doctor --instalacao`, que deve reportar "sem symlinks legados".
