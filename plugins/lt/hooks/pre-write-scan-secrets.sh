#!/usr/bin/env bash
# lt / hooks / pre-write-scan-secrets.sh
# Categoria: SEGURANCA
#
# Varre conteudo novo (Write/Edit/MultiEdit) em busca de segredo literal. Aplica LT-SEC-001.
#
# POSTURA: `deny` para severidade critical, `ask` para high. Nunca exit 2.
# O bloqueio duro ensina o agente a contornar o gate: ele move a senha para um arquivo que o
# padrao nao cobre e o segredo entra assim mesmo, agora sem ninguem ver. O `ask` mantem o humano
# no loop — que e' o que a norma pede.
#
# Este e' hook de SEGURANCA: NAO consulta o dial `guided`. Nunca.
#
# Contrato: exit 0 sempre; o veredito viaja no JSON do stdout.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

INPUT="$(cat 2>/dev/null || printf '{}')"
# Cap de ReDoS antes de qualquer regex, sem depender de `head` (que forkaria outro processo).
INPUT="${INPUT:0:200000}"

# Curto-circuito barato antes de qualquer fork: se nao ha' nome de ferramenta, nao ha' o que fazer.
case "$INPUT" in *'"tool_name"'*) ;; *) exit 0 ;; esac

# `deny` cancela a chamada mesmo sob bypassPermissions e --dangerously-skip-permissions;
# `ask` so mostra o prompt onde existe prompt. Ver o cabecalho de lib/secret_scan.py.
emit_decision() {  # $1 = deny|ask   $2 = motivo ja em JSON
  printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"$1\",\"permissionDecisionReason\":$2}}"
  exit 0
}
emit_ask() { emit_decision ask "$1"; }

if command -v python3 >/dev/null 2>&1; then
  RESULT="$(printf '%s' "$INPUT" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/lib/secret_scan.py" 2>/dev/null)"

  if [ -z "$RESULT" ]; then
    # O resolvedor nao respondeu. Guard que emudece e libera e' o falso-verde classico:
    # anuncia alto e escala para confirmacao humana.
    printf '[lt] AVISO: o verificador de segredos nao respondeu. Pedindo confirmacao por precaucao.\n' >&2
    emit_ask '"O verificador de segredos do harness falhou. Confirme manualmente que nao ha chave, token ou senha neste conteudo."'
  fi

  DECISION="$(printf '%s' "$RESULT" | sed -n 's/.*"decision"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')"

  # Sai cedo no caminho feliz, antes de qualquer fork adicional.
  case "$DECISION" in allow|'') exit 0 ;; esac

  case "$DECISION" in
    deny|ask|error)
      REASON_JSON="$(printf '%s' "$RESULT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("reason","")))' 2>/dev/null)"
      [ -n "$REASON_JSON" ] || REASON_JSON='"Possivel segredo literal detectado."'
      case "$DECISION" in
        deny) emit_decision deny "$REASON_JSON" ;;
        *)    emit_decision ask  "$REASON_JSON" ;;
      esac
      ;;
    notice)
      printf '[lt] indicio de baixa severidade no conteudo (informativo, nada foi bloqueado).\n' >&2
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
fi

# ---------------------------------------------------------------------------------------------
# MODO DEGRADADO — sem python3.
#
# Sobre-bloqueia DE PROPOSITO e anuncia a degradacao no stderr. A alternativa seria liberar em
# silencio, e um guarda que desaparece junto com sua dependencia e' pior que nenhum guarda:
# o time acredita estar protegido.
# Padroes em ERE, so com builtins, sobre o input ja limitado a 200k.
# ---------------------------------------------------------------------------------------------
printf '[lt] MODO DEGRADADO — python3 ausente; a guarda de segredos esta sobre-bloqueando de proposito.\n' >&2
printf '     Instale python3 e rode `lt:lt-doctor` para sair deste modo.\n' >&2

DEGRADED_ERE='AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|dop_v1_[a-f0-9]{64}|-----BEGIN (RSA|EC|DSA|OPENSSH|PGP) PRIVATE KEY-----|[?&]auth=[A-Za-z0-9._-]{20,}|(postgres|postgresql|clickhouse|mysql|mqtt|amqp|redis)://[^:@/[:space:]]+:[^@/[:space:]]+@'

# Se ate' o grep faltar, o caminho degradado nao consegue decidir NADA. Liberar aqui seria
# exatamente o falso-verde que este bloco existe para evitar — o guarda desapareceria junto com
# a segunda dependencia e ninguem saberia. Entao escala para confirmacao humana sempre.
if ! command -v grep >/dev/null 2>&1; then
  printf '[lt] MODO DEGRADADO SEVERO — nem python3 nem grep disponiveis.\n' >&2
  emit_ask '"O harness nao conseguiu verificar segredos (python3 e grep ausentes). Confirme manualmente que nao ha chave, token ou senha neste conteudo."'
fi

if printf '%s' "$INPUT" | grep -Eq -e "$DEGRADED_ERE"; then
  emit_ask '"Possivel segredo literal detectado (modo degradado, sem python3). Confirme manualmente e prefira variavel de ambiente ou gerenciador de segredos."'
fi

exit 0
