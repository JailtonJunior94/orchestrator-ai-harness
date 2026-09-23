# Rollout na frota

Como uma versão do harness chega às máquinas da organização, em que ritmo, e como volta atrás.
O payload e os scripts estão em `enterprise/` (ver `enterprise/README.md`); a mecânica de versão,
em `docs/VERSIONING.md`.

## O modelo

A distribuição é por **política gerenciada**, sem MDM: cada máquina recebe
`managed-settings.json` por um bootstrap rodado com privilégio de administrador. O arquivo:

- registra o marketplace `lt` pinado numa **tag** (`ref: vX.Y.Z`, nunca branch);
- habilita `lt@lt`;
- declara a lista de servidores MCP homologados (`docs/policy/ia-automacao.md` é a dona dela);
- aplica um `permissions.deny` mínimo, aditivo, que vale em qualquer modo de permissão.

Três decisões registradas no próprio payload e cobradas por `enterprise/verify.sh`:

- `permissions.defaultMode` **ausente** — managed vence user; mandar `default` rebaixaria em
  silêncio quem escolheu `auto`;
- `allowManagedMcpServersOnly: false` na primeira onda — ligar sem inventário corta conector em
  uso no primeiro restart; a virada é um PR próprio com o inventário;
- nenhuma chave fora da referência oficial de settings.

Se a organização adotar MDM, o payload é o mesmo arquivo: muda só quem o copia.

## Ondas

| Onda | Quem | Critério para avançar |
|---|---|---|
| 0 | mantenedor | `PILOT-SETUP.md` completo numa máquina limpa |
| 1 | um squad piloto | uma semana sem bloqueio indevido; achados triados em issue |
| 2 | squads voluntários | nenhum incidente aberto de severidade alta |
| 3 | frota | política de MCP com inventário fechado |

O número da onda em curso fica em `_audit.rollout_wave` do `managed-settings.json`.

## Cadência de aviso

| Tipo de release | Aviso antes da tag | Obrigatório junto |
|---|---|---|
| patch | nenhum | bloco no `CHANGELOG.md` |
| minor | 48 h | notas de release e o que muda para quem usa |
| major | 1 semana | RFC em issue de proposta, guia de migração, janela de convivência ≥ 30 dias |

Mudança de comportamento em hook de segurança (algo que passa a bloquear ou pedir confirmação)
é tratada como minor, no mínimo, mesmo que o diff seja pequeno.

## Passo a passo de uma atualização

1. Release cortada conforme `docs/RELEASE-CHECKLIST.md` — o CI do `release.yml` só publica depois
   das mesmas suítes do CI de `main` e da coerência `tag == manifesto == plugin.json == pin`.
2. Máquinas com a política: o administrador roda de novo o bootstrap do SO (ele baixa o
   `managed-settings.json` da tag nova) e `enterprise/verify.sh`.
3. Cada pessoa: `claude plugin update lt@lt --scope user` e reinicia a sessão. O
   `claude plugin marketplace update` sozinho responde sucesso e **não** troca o que roda.
4. Repos consumidores com pin próprio: commit do pin novo e
   `claude plugin update lt@lt --scope project` antes do restart. Com adaptadores de outros hosts,
   `bash scripts/update.sh --hosts <lista> --project <repo>`.

**`enabledPlugins` no managed-settings não materializa o cache.** Máquina nova recebe a política,
reinicia e não tem harness, sem erro. O bootstrap termina mandando rodar
`claude plugin install lt@lt` (ou `scripts/install.sh`).

## Rollback

Rollback é **re-pin**, nunca edição à mão numa máquina:

1. `bash scripts/bump-version.sh <versão-anterior>` num branch de correção — ou reverter o commit
   de release — e seguir o fluxo normal até uma tag nova que aponta para o conteúdo bom;
2. em emergência, redistribuir o `managed-settings.json` da release anterior (está anexado a ela)
   pelo bootstrap;
3. remover a política de uma máquina: `enterprise/uninstall.sh` (macOS, Linux) ou
   `enterprise/uninstall.ps1` (Windows) — ambos fazem backup antes de apagar.

Remover o harness de uma pessoa é outra coisa: `bash scripts/uninstall.sh`, que não toca em
`.lt/` dos projetos nem no audit trail.

## Suítes que protegem o rollout

`tests/enterprise/run.sh` roda em todo push: `version-pin.sh` (pin igual em manifesto,
`plugin.json`, managed-settings e nos três bootstraps), `managed-settings-schema.sh` (forma do
payload) e `bootstrap-dryrun.sh` (`LT_DRYRUN=1`, sem sudo e sem rede; o Windows é `skip`
contado quando não há `pwsh`).
