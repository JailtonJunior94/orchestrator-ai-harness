# Versionamento

Três números de versão convivem neste repositório. Confundir um com outro é a origem mais comum
de release incoerente — por isso cada um tem dono, lugar e regra explícitos.

## Os três números

| # | Onde | Quem bumpa | O que significa |
|---|---|---|---|
| 1 | `plugins[].version` em `.claude-plugin/marketplace.json` **e** `version` em `plugins/<nome>/.claude-plugin/plugin.json` | `scripts/bump-version.sh` para os `lockstep`; à mão para os `independent` | versão de **cada plugin** |
| 2 | `.version` na raiz do manifesto (fora do array `plugins`) | **manual, sempre** — nenhum script toca | versão do **arquivo de manifesto**; muda quando um plugin entra ou sai do marketplace |
| 3 | título `## [X.Y.Z] — AAAA-MM-DD` no `CHANGELOG.md` | manual, na mesma PR do bump | espelha a versão do plugin core `lt` desde a primeira release |

## Duas cadências

O campo `cadence` de cada entrada do manifesto é metadado **do repositório**, não do host (o
`claude plugin validate` o reporta como campo desconhecido; o aviso está em
`config/validate-allowlist.txt` com data de caducidade).

- **`lockstep`** — acompanha o core. `bump-version.sh` reescreve a versão; o
  `tests/enterprise/version-pin.sh` reprova quem divergir.
- **`independent`** — plugin opt-in com ciclo próprio. Só precisa bater entre o próprio
  `plugin.json` e a própria entrada no manifesto; `bump-version.sh` o pula.

Hoje o marketplace publica só o core, em `lockstep`. Os plugins opt-in planejados estão
registrados como adiados em `config/deferred-components.txt`.

## Semver no core

| Mudança | Exemplo | Aviso à frota |
|---|---|---|
| patch | correção de hook, texto, gate | livre |
| minor | skill ou command novo, gate novo que nasce advisório | 48 h de aviso, notas no `CHANGELOG.md` |
| major | nome de command muda, formato do audit trail muda, chave de `.lt/` removida | 1 semana de aviso, guia de migração no `CHANGELOG.md`, janela de convivência ≥ 30 dias |

`0.x` é a linha atual: `1.0.0` só sai quando o checklist do Apêndice J de
`docs/REPLICATION-GUIDE.md` fechar. O número baixo é a informação honesta sobre maturidade.

O `"version": "1.0.0"` no topo de `.claude-plugin/marketplace.json` **não** é a versão do plugin: é a
versão do formato do catálogo e não muda com `bump-version.sh`. A versão que vale para o
plugin é a de `plugins[].version` (e a do `plugin.json`), hoje `0.x`.

## O que `bump-version.sh` faz — e o que não faz

`bash scripts/bump-version.sh X.Y.Z`:

1. manifesto: versão dos `lockstep` (por `select`, nunca por índice);
2. `plugin.json` de cada plugin `lockstep`;
3. `enterprise/managed-settings.json`: pin do marketplace em **tag** `vX.Y.Z` (`del(.branch)`
   incondicional — pin por branch torna o rollback não reprodutível);
4. `VERSION=` dos bootstraps de macOS e Linux e `$Version` do bootstrap de Windows;
5. carimbos de versão atual na prosa (`README.md`, `docs/host-facts.md`), substituição exata;
6. `.claude/settings.json` só se **já** houver pin lá — reintroduzir pin local quebra o carregamento.

Todo passo prova o efeito com `cksum` e distingue três resultados: mudou (`✓`), não mudou mas o
alvo já está lá (`=`, reexecução idempotente) e não mudou **sem** o alvo presente (`✗`, falha).
Passo que só imprime `✓` sem verificar é o falso-verde que custa uma release.

**Não bumpa:** `CHANGELOG.md`, `.version` raiz do manifesto, plugins `independent` e
registros datados em `docs/analysis/` — reescrever histórico é falsificá-lo.

## Fluxo completo

```text
1. bash scripts/bump-version.sh X.Y.Z
2. grep -rn "<versão-anterior>" --include='*.md' . | grep -v CHANGELOG   (prosa que o script não alcança)
3. CHANGELOG.md: bloco "## [X.Y.Z] — AAAA-MM-DD" no topo
4. claude plugin tag plugins/lt --dry-run    (plugin.json e manifesto concordam?)
5. bash scripts/pilot-check.sh
6. commit "chore(release): vX.Y.Z" + PR + merge em main
7. git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z    → .github/workflows/release.yml
8. em cada repo consumidor: atualizar o pin + claude plugin update lt@lt --scope project
```

**A tag é o deploy.** O `managed-settings.json` pina o marketplace numa tag; enquanto ela não é
empurrada, a mudança não existe para ninguém da frota. O checklist operacional de cada passo está
em `docs/RELEASE-CHECKLIST.md`; a cadência de aviso e o rollback, em `docs/enterprise-rollout.md`.
