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
# A ULTIMA TAG NAO ENTRA nesta secao. Ela e' dado do git, nao do conteudo: toda vez que uma tag
# era criada, o primeiro commit seguinte reprovava o gate "gerados em dia" ate' alguem regenerar
# (tres CIs vermelhas em tres releases). O que esta secao afirma precisa ser funcao so' dos arquivos.
# Qual versao esta na frota se consulta onde ela mora: `git tag --list 'v*' | sort -V | tail -1`.
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

EOF

printf '_Gerado em %s por `scripts/gen-drift-report.sh` · CLI %s._\n' \
  "$(date -u +%Y-%m-%d)" "$(claude --version 2>/dev/null | head -1 || echo 'desconhecido')"
printf '<!-- END GENERATED: estado -->\n'
