# Checklist de release

Checklist operacional para cortar uma versão do plugin core. A teoria (os três números, as
cadências, o semver) está em `docs/VERSIONING.md`; aqui está a ordem e o que conferir em cada
passo. Cada item existe porque, sem ele, uma release já saiu errada em algum harness deste tipo.

## 1. Antes do bump

- [ ] `main` atualizada e árvore limpa (`git status`).
- [ ] `bash scripts/pilot-check.sh` → `PILOT CHECK PASSOU`, num `/bin/bash` 3.2 se estiver no
      macOS. Nenhum item amarelo sem explicação: amarelo é gate que **não rodou**.
- [ ] Gates do host verdes com o CLI instalado:
  - [ ] `bash scripts/validate-plugins.sh` → `VALIDATE PASSOU`
  - [ ] `bash scripts/plugin-token-cost.sh` (ratchet do custo always-on)
  - [ ] `bash scripts/measure-skill-budget.sh` → `SKILL BUDGET OK`
- [ ] **Eval como gate** (o release bloqueia sem isto):
  - [ ] skill, agent, comando ou eval mudou? Meça de novo com o juiz calibrado:
        `claude plugin eval plugins/lt --judge-model sonnet --runs 3 --ablation with-without --json <r.json>`
  - [ ] `python3 scripts/lib/eval-gate.py check <r.json> --write` → `EVAL GATE APROVADO`
        (juiz com acurácia ≥ 0,90, ≥ 3 execuções, roteamento ≥ 95%/100%, sem regressão, ganho ≥ 0
        em toda skill)
  - [ ] `python3 scripts/lib/eval-gate.py fresh` → `EVAL EM DIA`
  - [ ] CLI do Claude Code mudou de versão? Recalibre o juiz antes
        (`python3 scripts/lib/judge-calibration.py build` + eval em `--eval-dir evals-calibration`).
- [ ] Toda baseline regravada neste ciclo (`docs/benchmarks/*.json`) tem entrada em `_history`
      e justificativa no corpo do PR que a regravou. **Ratchet regravado sem motivo é ratchet
      desligado.**

## 2. Bump

- [ ] `bash scripts/bump-version.sh X.Y.Z` termina em `BUMP OK`. Qualquer `✗` para tudo: o
      padrão de um carimbo quebrou e o arquivo ficou na versão antiga.
- [ ] Varredura de prosa que o script não alcança:
      `grep -rn "<versão-anterior>" --include='*.md' --include='*.sh' --include='*.ps1' . | grep -v CHANGELOG`.
      Não reescreva entrada histórica do `CHANGELOG.md` nem registro datado de `docs/analysis/`.
- [ ] Mudou a forma do plugin (skill, command, agent ou hook entrou ou saiu)?
      `bash scripts/validate-playbook-counts.sh` e `bash tests/command-glossary-check.sh`.
- [ ] Plugin entrou ou saiu do marketplace? `.version` raiz do manifesto bumpada **à mão**.
- [ ] `CHANGELOG.md`: bloco `## [X.Y.Z] — AAAA-MM-DD` no topo, no formato exato que o
      `release.yml` procura. Mudança de comportamento ganha blockquote de aviso.
- [ ] `claude plugin tag plugins/lt --dry-run` concorda (`plugin.json` × manifesto).

## 3. PR e merge

- [ ] Commit `chore(release): vX.Y.Z`, PR com o template preenchido, CI verde nos dois SOs
      (`harness · CI`: suítes em ubuntu e macOS, guarda de bash 3.2, manifestos, gates do host,
      sincronia de versão).
- [ ] Merge em `main`.

## 4. Tag — o deploy

- [ ] `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
- [ ] `.github/workflows/release.yml` verde: reroda o CI inteiro, confere
      `tag == manifesto == plugin.json == pin do managed-settings` **por nome**, exige o bloco do
      `CHANGELOG.md` e publica a release com os artefatos de `enterprise/`.
- [ ] A release no GitHub tem `managed-settings.json`, os três bootstraps, `verify.sh`,
      `uninstall.sh` e `uninstall.ps1`.

## 5. Depois da tag

- [ ] Numa máquina limpa (ou `HOME` descartável): `claude plugin marketplace add
      JailtonJunior94/orchestrator-ai-harness`, `claude plugin install lt@lt`, reiniciar,
      `/lt:lt-doctor`.
- [ ] Bootstrap enterprise em uma máquina piloto: `enterprise/bootstrap-<so>` → `verify.sh`
      → `VERIFY PASSOU`.
- [ ] Aviso à frota conforme a cadência de `docs/enterprise-rollout.md`.
- [ ] Repos consumidores: pin atualizado e `claude plugin update lt@lt --scope project` **antes**
      do restart.

## Armadilhas conhecidas

- **Verde falso é o defeito mais caro.** `sed` que não casa e imprime `✓`; lista canônica que
  valida só o que ela lista; lib que silencia o próprio stderr. Passo que afirma ter mudado um
  arquivo prova com `cksum` ou `grep`.
- **O pin é global.** Uma sessão num projeto cujo `.claude/settings.json` declara `ref` reescreve
  o registro de marketplaces da máquina inteira. Plugin novo não é testável fora de tag.
- **Opt-in novo exige release do core**: o `release.yml` valida `tag == versão do core`.
- **`marketplace update` não troca o que roda.** Quem re-resolve é `claude plugin update`.
- **Comportamento de host se prova executando.** Sonda com marcador único
  (`claude -p --plugin-dir "$PWD/plugins/lt" '…responda apenas LT-HARNESS-OK'`): nome inválido
  cai em silêncio.
- **Idempotência.** Reexecutar o bump na versão alvo imprime `=`, não `✗`; um guard que confunde
  "já está lá" com "o padrão quebrou" trava a reexecução legítima.
