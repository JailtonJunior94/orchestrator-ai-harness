# Changelog

Formato: um bloco `## [X.Y.Z] — YYYY-MM-DD` por versão, o mais novo no topo.
Entrada **manual**, na mesma PR do `scripts/bump-version.sh`. Mudança de comportamento ganha
blockquote de aviso.

Este número espelha a versão do plugin core (`lt`) desde a primeira release.

## [Não lançado]

### Adicionado
- Esqueleto do marketplace `lt` e do plugin core `lt` (`.claude-plugin/marketplace.json`,
  `plugins/lt/.claude-plugin/plugin.json`), validados por `claude plugin validate` no CLI 2.1.267.
- `CLAUDE.md` com a regra dura de bash 3.2, as regras do host e a exceção de escopo a
  `R-STYLE-001.2` para os scripts do próprio harness.
- `config/validate-allowlist.txt` com caducidade: o gate falha quando o aviso `cadence` deixar
  de aparecer, não só quando aparecer um aviso novo.

### Pendências conhecidas
- `owner.email` / `author.email` estão em `JailtonJunior94@users.noreply.github.com`, um endereço **presumido**.
  Confirmar com o time antes da primeira tag.
- Proveniência do conteúdo SDD portado de `JailtonJunior94/orchestrator` (repo público **sem
  licença**) precisa de grant explícito ou de um `LICENSE` na origem.
