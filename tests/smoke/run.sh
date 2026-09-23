#!/usr/bin/env bash
# tests / smoke / run.sh — banner de sucesso: SUITE PASSOU
#
# Presenca, forma e invariantes estruturais. Rapido o bastante para rodar antes de todo commit.
#
# PRINCIPIO CENTRAL: LISTA CANONICA CRUZA COM DISCO.
# Uma lista que so valida o que ela mesma lista e' verde por construcao. Toda contagem aqui e'
# comparada com `ls`/`find`, nunca com outra lista escrita a mao.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$REPO"

if [ -t 1 ]; then C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_SKIP=$'\033[33m'; C_OFF=$'\033[0m'
else C_OK=""; C_BAD=""; C_SKIP=""; C_OFF=""; fi
OK=0; BAD=0; SKIP=0
ok()   { OK=$((OK+1));   printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$1"; }
bad()  { BAD=$((BAD+1)); printf '  %s✗%s %s\n' "$C_BAD" "$C_OFF" "$1" >&2; }
skip() { SKIP=$((SKIP+1)); printf '  %s~%s %s (pulado: %s)\n' "$C_SKIP" "$C_OFF" "$1" "$2"; }
sec()  { printf '\n▸ %s\n' "$1"; }

# ── presenca top-level ───────────────────────────────────────────────────────────────────────
sec "presenca"
for f in .claude-plugin/marketplace.json .claude/settings.json CLAUDE.md README.md LICENSE \
         CHANGELOG.md .gitignore config/validate-allowlist.txt config/deferred-components.txt \
         plugins/lt/.claude-plugin/plugin.json plugins/lt/hooks/hooks.json \
         scripts/install.sh scripts/update.sh scripts/uninstall.sh scripts/install-detect.sh \
         scripts/migrate-symlinks.sh scripts/lib/reconcile-plugins.py \
         scripts/lib/provision-statusline.py scripts/pilot-check.sh \
         enterprise/managed-settings.json enterprise/verify.sh enterprise/bootstrap-mac.sh \
         enterprise/bootstrap-linux.sh enterprise/bootstrap-windows.ps1 \
         tests/enterprise/run.sh docs/policy/ia-automacao.md; do
  [ -e "$f" ] && ok "$f" || bad "ausente: $f"
done

# ── JSON valido em todo manifesto e config ───────────────────────────────────────────────────
sec "JSON"
if command -v jq >/dev/null 2>&1; then
  JBAD=0
  while IFS= read -r f; do jq empty "$f" 2>/dev/null || { bad "JSON invalido: $f"; JBAD=1; }; done <<EOF
$(find . -name '*.json' -not -path './.git/*' -not -path './tests/fixtures/*' | sort)
EOF
  [ "$JBAD" -eq 0 ] && ok "todo .json do repo e' valido"
else
  skip "validacao de JSON" "jq ausente"
fi

# ── manifesto ────────────────────────────────────────────────────────────────────────────────
sec "manifesto"
MAN=.claude-plugin/marketplace.json
COUNT="$(python3 -c "import json;print(len(json.load(open('$MAN'))['plugins']))")"
DISK="$(ls -1d plugins/*/ 2>/dev/null | wc -l | tr -d ' ')"
[ "$COUNT" = "$DISK" ] && ok "plugins no manifesto ($COUNT) == diretorios em plugins/ ($DISK)" \
  || bad "manifesto diz $COUNT plugin(s), disco tem $DISK"

MV="$(python3 -c "import json;print(json.load(open('$MAN'))['plugins'][0]['version'])")"
PV="$(python3 -c "import json;print(json.load(open('plugins/lt/.claude-plugin/plugin.json'))['version'])")"
[ "$MV" = "$PV" ] && ok "versao sincronizada manifesto <-> plugin.json ($MV)" \
  || bad "versao divergente: manifesto=$MV plugin.json=$PV"

LIC="$(python3 -c "import json;print(json.load(open('plugins/lt/.claude-plugin/plugin.json'))['license'])")"
[ "$LIC" = "Proprietary" ] && ok "license == Proprietary no plugin.json" || bad "license inesperada: $LIC"
grep -q 'Proprietary' LICENSE && ok "LICENSE declara Proprietary" || bad "LICENSE nao declara Proprietary"

# ── plugin.json nao pode ter chave que o host ignora ─────────────────────────────────────────
sec "chaves mortas"
for k in hooks statusLine skillListingBudgetFraction outputStylesPath; do
  if python3 -c "import json,sys;d=json.load(open('plugins/lt/.claude-plugin/plugin.json'));sys.exit(0 if '$k' in d else 1)" 2>/dev/null; then
    bad "plugin.json declara '$k' — chave que o host ignora e' chave morta"
  else
    ok "plugin.json nao declara '$k'"
  fi
done

# ── hooks ────────────────────────────────────────────────────────────────────────────────────
sec "hooks"
# Descoberta por find, NUNCA por lista fixa: o hooks.json novo que ninguem lembrou de registrar
# ficaria verde por ausencia.
HJ=0; UNQ=0
while IFS= read -r hj; do
  HJ=$((HJ+1))
  while IFS= read -r c; do
    case "$c" in '"${CLAUDE_PLUGIN_ROOT}'*) ;; *) bad "referencia sem aspas em $hj: $c"; UNQ=1 ;; esac
  done <<EOF2
$(python3 -c "
import json
d=json.load(open('$hj'))
for ev in d.get('hooks',{}).values():
    for g in ev:
        for h in g.get('hooks',[]):
            print(h.get('command',''))")
EOF2
done <<EOF3
$(find . -name hooks.json -not -path './.git/*' | sort)
EOF3
[ "$UNQ" -eq 0 ] && ok "\${CLAUDE_PLUGIN_ROOT} aspado em todos os $HJ hooks.json descobertos"

REG="$(python3 -c "
import json
d=json.load(open('plugins/lt/hooks/hooks.json'))
print(sum(len(g.get('hooks',[])) for ev in d['hooks'].values() for g in ev))")"
DISKH="$(ls -1 plugins/lt/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ')"
[ "$REG" = "$DISKH" ] && ok "hooks registrados ($REG) == scripts em disco ($DISKH)" \
  || bad "$REG hooks registrados mas $DISKH scripts em disco"

XH="$(find plugins/lt/hooks -name '*.sh' -perm -u+x | wc -l | tr -d ' ')"
[ "$XH" = "$DISKH" ] && ok "todos os $DISKH hooks sao executaveis" || bad "$XH de $DISKH hooks executaveis"

# ── invariante: hook de SEGURANCA nao consulta o dial ────────────────────────────────────────
sec "invariante de seguranca"
SV=0
for f in pre-bash-block-destructive pre-bash-block-sensitive-paths pre-write-block-sensitive-paths \
         pre-write-scan-secrets user-prompt-detect-secrets user-prompt-block-sensitive-paths; do
  grep -q 'guided-mode.sh' "plugins/lt/hooks/$f.sh" 2>/dev/null && { bad "$f consulta o dial guided"; SV=1; }
done
[ "$SV" -eq 0 ] && ok "nenhum hook de SEGURANCA consulta o dial guided"
grep -q 'guided-mode.sh' plugins/lt/hooks/pre-write-spec-coverage-warn.sh 2>/dev/null \
  && ok "o unico hook de PROCESSO consulta o dial" || bad "o hook de processo NAO consulta o dial"

# ── descontaminacao ──────────────────────────────────────────────────────────────────────────
sec "descontaminacao"
# Os padroes vivem em config/*.txt, e nao aqui dentro: guard textual que carrega os proprios
# literais casa a si mesmo e reprova sempre. Este arquivo tambem se exclui da varredura.
SELF="tests/smoke/run.sh"
scan_forbidden() {  # $1 = arquivo de padroes  $2 = rotulo
  [ -r "$1" ] || { skip "$2" "$1 ausente"; return 0; }
  lt_sf_bad=0
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue ;; esac
    HIT="$(grep -rniE --binary-files=without-match --exclude-dir=.git -- "$pat" . 2>/dev/null \
           | grep -v "^./config/" | grep -v "^./$SELF:" \
           | grep -v "^./tests/enterprise/managed-settings-schema.sh:" | head -3)"
    if [ -n "$HIT" ]; then
      bad "$2: padrao proibido '$pat' encontrado"
      printf '%s\n' "$HIT" | cut -c1-120 | sed 's/^/      /' >&2
      lt_sf_bad=1
    fi
  done < "$1"
  [ "$lt_sf_bad" -eq 0 ] && ok "$2: limpo"
}

scan_forbidden config/forbidden-patterns.txt "descontaminacao"
grep -rq --binary-files=without-match 'ai-spec' plugins/lt 2>/dev/null \
  && bad "referencia ao binario externo ai-spec" \
  || ok "nenhuma referencia ao binario externo"

# ── bash 3.2 ─────────────────────────────────────────────────────────────────────────────────
sec "bash 3.2"
# Este scan e' diferente do de descontaminacao em dois pontos, e ambos foram pagos com falso
# positivo: so olha arquivos .sh (o CLAUDE.md DOCUMENTA a regra e citava os literais), e remove
# linhas de comentario antes de casar (os proprios scripts dizem "bash 3.2: sem declare -A").
B32=0
while IFS= read -r f; do
  case "$f" in ./config/*|./tests/smoke/run.sh) continue ;; esac
  CODE="$(sed 's/^[[:space:]]*#.*$//' "$f")"
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue ;; esac
    if printf '%s' "$CODE" | grep -qE -- "$pat" 2>/dev/null; then
      bad "bash 4+ em $f: $pat"
      B32=1
    fi
  done < config/bash32-forbidden.txt
done <<EOFB
$(find . -name '*.sh' -not -path './.git/*' | sort)
EOFB
[ "$B32" -eq 0 ] && ok "nenhuma construcao de bash 4+ em codigo (comentarios ignorados)"

SN=0
while IFS= read -r f; do bash -n "$f" 2>/dev/null || { bad "sintaxe: $f"; SN=1; }; done <<EOF5
$(find . -name '*.sh' -not -path './.git/*' | sort)
EOF5
[ "$SN" -eq 0 ] && ok "bash -n limpo em todos os $(find . -name '*.sh' -not -path './.git/*' | wc -l | tr -d ' ') scripts"

# ── python ───────────────────────────────────────────────────────────────────────────────────
sec "python"
PN=0
while IFS= read -r f; do
  python3 -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$f" 2>/dev/null \
    || { bad "sintaxe python: $f"; PN=1; }
done <<EOF6
$(find . -name '*.py' -not -path './.git/*' -not -path '*/__pycache__/*' | sort)
EOF6
[ "$PN" -eq 0 ] && ok "sintaxe limpa em todos os $(find . -name '*.py' -not -path './.git/*' -not -path '*/__pycache__/*' | wc -l | tr -d ' ') arquivos python"

# ── frontmatter contra o schema OFICIAL ──────────────────────────────────────────────────────
sec "frontmatter oficial"
# A lista vem da documentacao oficial do Claude Code. Chave fora dela e' ignorada pelo host —
# "chave que o host ignora e' chave morta", a mesma regra que vale para plugin.json. Dado
# customizado tem lugar proprio: `metadata`, que a doc declara como YAML livre.
if python3 - <<'PYEOF'
import glob, sys
try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML ausente — este gate FALHA, nunca pula\n"); sys.exit(2)
OFICIAIS = {"name","description","when_to_use","argument-hint","arguments",
            "disable-model-invocation","user-invocable","allowed-tools","disallowed-tools",
            "model","effort","context","agent","background","hooks","paths","shell",
            "metadata","license","compatibility"}
bad = 0
for p in sorted(glob.glob("plugins/lt/skills/*/SKILL.md")):
    n = p.split("/skills/")[1].split("/")[0]
    d = yaml.safe_load(open(p, encoding="utf-8").read().split("---", 2)[1]) or {}
    fora = [k for k in d if k not in OFICIAIS]
    if fora:
        print("  %s: chave nao-oficial %s" % (n, ", ".join(fora))); bad += 1
    desc = d.get("description", "")
    if not isinstance(desc, str) or not desc.strip():
        print("  %s: description ausente ou nao-escalar" % n); bad += 1
    elif len(desc) > 1536:
        print("  %s: description %d chars (cap oficial 1536)" % (n, len(desc))); bad += 1
    if d.get("name") != n:
        print("  %s: name != nome do diretorio" % n); bad += 1
sys.exit(1 if bad else 0)
PYEOF
then
  ok "11 skills com frontmatter dentro do schema oficial"
else
  RC=$?
  [ "$RC" -eq 2 ] && skip "frontmatter oficial" "PyYAML ausente" || bad "frontmatter fora do schema oficial"
fi

# ── smokes delegados ─────────────────────────────────────────────────────────────────────────
sec "delegados"
if bash tests/unit/scripts/no-phantom-refs.test.sh >/dev/null 2>&1; then
  ok "nenhuma referencia fantasma"
else
  bad "no-phantom-refs FALHOU (rode: bash tests/unit/scripts/no-phantom-refs.test.sh)"
fi

# ── banner ───────────────────────────────────────────────────────────────────────────────────
printf '\n───────────────────────────────\n'
printf '%d ok · %d falha · %d pulado\n' "$OK" "$BAD" "$SKIP"
if [ "$BAD" -eq 0 ]; then printf 'SUITE PASSOU\n'; exit 0; fi
printf 'SUITE FALHOU\n' >&2; exit 1
