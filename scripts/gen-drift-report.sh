#!/usr/bin/env bash
# orchestrator-ai-harness / scripts / gen-drift-report.sh
#
# Gera a secao "prosa vs disco" do guia de replicacao, a partir do DISCO.
#
# POR QUE GERAR EM VEZ DE ESCREVER
# Uma secao que denuncia prosa desatualizada e' escrita a mao, envelhece igual, e ai' o
# documento passa a mentir sobre as proprias mentiras. Aqui todo numero vem de `ls`, `jq` e
# `git`, e tests/docs-generated-fresh.sh reprova se o bloco commitado divergir.
#
# Emite entre marcadores BEGIN/END GENERATED. O bump-version pula essas regioes.
#
# O QUE DELIBERADAMENTE NAO ENTRA AQUI: contagem de linhas de codigo.
# A primeira versao contava linhas de bash e python. Resultado: editar QUALQUER script
# desatualizava o bloco, e o gate de frescor passou a reprovar em toda PR — inclusive a PR que
# ligava o proprio gate. Metrica que muda a cada edicao e' ruido, nao sinal: ela treina o time a
# regenerar sem ler, que e' o oposto do que um gate de frescor existe para fazer.
# As grandezas que ficam sao as que mudam quando a FORMA do repo muda, e so entao.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

SK=$(ls -1d plugins/lt/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
CM=$(ls -1 plugins/lt/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
AG=$(ls -1 plugins/lt/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
HK=$(ls -1 plugins/lt/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ')
PL=$(jq '.plugins | length' .claude-plugin/marketplace.json)
MV=$(jq -r '.version' .claude-plugin/marketplace.json)
CV=$(jq -r '.plugins[] | select(.name=="lt") | .version' .claude-plugin/marketplace.json)
EV=$(ls -1 plugins/lt/skills/*/evals/*.json 2>/dev/null | wc -l | tr -d ' ')
NEG=$(ls -1 plugins/lt/skills/*/evals/*negativo*.json 2>/dev/null | wc -l | tr -d ' ')
# `--no-contains HEAD`: a tag que aponta para ESTE commit nunca entra. O documento e' commitado
# antes da tag existir; contando-a, o CI do proprio release (que ja enxerga a tag) comparava
# "v0.1.0" commitado com "v0.1.1" calculado e reprovava a release por construcao.
TAG=$(git tag --list 'v*' --no-contains HEAD 2>/dev/null | sort -V | tail -1)
[ -n "$TAG" ] || TAG="(nenhuma)"
DESC=$(python3 -c "
import glob, yaml
t=0
for p in glob.glob('plugins/lt/skills/*/SKILL.md'):
    d=yaml.safe_load(open(p,encoding='utf-8').read().split('---',2)[1]) or {}
    t+=len(d.get('description',''))
print(t)" 2>/dev/null || echo "?")

cat <<EOF
<!-- BEGIN GENERATED: estado · scripts/gen-drift-report.sh · nao edite a mao -->

| Grandeza | Valor em disco |
|---|---:|
| plugins no marketplace | $PL |
| skills | $SK |
| commands | $CM |
| agents empacotados | $AG |
| hooks registrados | $HK |
| casos de eval | $EV (sendo $NEG negativos) |
| soma das \`description\` | $DESC chars |
| versao do plugin core | $CV |
| \`.version\` raiz do manifesto | $MV |
| ultima tag semver | $TAG |

EOF

if [ "$TAG" = "(nenhuma)" ]; then
  cat <<EOF
> **Para quem esta na frota, este harness ainda nao existe.** Nao ha tag semver. O push da tag
> e' o deploy: enquanto ele nao acontece, \`claude plugin marketplace add\` nao tem o que
> resolver e nenhuma maquina consegue instalar pelo canal oficial.

EOF
elif [ "v$CV" != "$TAG" ]; then
  cat <<EOF
> **A versao $CV existe no repositorio e nao na frota.** A ultima tag e' $TAG. O push da tag e'
> o deploy; ate' la', a mudanca nao alcanca ninguem.

EOF
fi

printf '_Gerado em %s por `scripts/gen-drift-report.sh` · CLI %s._\n' \
  "$(date -u +%Y-%m-%d)" "$(claude --version 2>/dev/null | head -1 || echo 'desconhecido')"
printf '<!-- END GENERATED: estado -->\n'
