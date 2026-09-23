#!/usr/bin/env python3
# lt / lib / sensitive_paths.py
#
# Resolvedor de caminho sensivel, UMA invocacao por disparo de hook.
# Aplica LT-FILE-001 (PII/SSL/chave privada fora do alcance) e LT-FILE-002 (infra revisada).
#
# TRES CLASSES, TRES POSTURAS
#   non_overridable  -> block SEMPRE. Nenhuma excecao local alcanca. Inclui o proprio approve.log:
#                       trilha que o auditado edita nao e' trilha.
#   patterns         -> block por padrao; `ask` e' opt-in PERSISTENTE do squad, registrado no
#                       approve.log com o token sensitive-mode-ask.
#   review_before    -> ask sempre. Sao arquivos de infra que a pessoa legitimamente edita com
#                       ajuda da IA; o que LT-FILE-002 exige e' revisao humana, nao proibicao.
#
# context_exemptions existe porque tres skills da casa leem credencial como FUNCAO legitima
# (clickhouse-slice, druid-slice, postgres-staging-dump). Sem a isencao o plugin bloqueia a
# propria skill no primeiro uso, e o falso positivo na semana 1 e' o que faz desativarem o hook.
#
# Saida: JSON no stdout, exit 0 sempre. O hook decide.

import fnmatch
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_text  # noqa: E402

# Comandos que exfiltram sem citar um caminho sensivel no argumento. Cobrem a stack real desta
# casa (mapa de infra: Postgres, ClickHouse, Druid, Kafka, k8s, DigitalOcean).
DANGEROUS_COMMANDS = [
    (r"\bpg_dump(all)?\b", "dump de Postgres"),
    (r"\bmysqldump\b", "dump de MySQL"),
    (r"\bclickhouse-client\b.*--password", "ClickHouse com senha na linha de comando"),
    (r"\bkubectl\s+get\s+secret", "leitura de secret do Kubernetes"),
    (r"\bdoctl\s+auth", "credencial da DigitalOcean"),
    (r"\bgh\s+auth\s+token", "token do GitHub em texto puro"),
    (r"\bop\s+read\b", "leitura do 1Password"),
    (r"\bvault\s+kv\s+get\b", "leitura do Vault"),
    (r"\baws\s+configure\s+get", "credencial da AWS"),
    (r"\bcat\b[^|;]*\.(pem|key|p12|pfx)\b", "leitura de chave privada"),
]


def load_config(plugin_root):
    path = os.path.join(plugin_root, "config", "sensitive-paths.json")
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def expand(path):
    if not path:
        return ""
    return os.path.expanduser(path)


def matches_any(path, patterns):
    """Casa o caminho completo e tambem o basename.

    Casar so o caminho completo deixaria passar `.env` referenciado de forma relativa; casar so o
    basename deixaria passar um diretorio inteiro. Os dois.
    """
    if not path:
        return None
    candidates = [path, os.path.abspath(expand(path)), os.path.basename(path)]
    for pattern in patterns:
        expanded = expand(pattern)
        for candidate in candidates:
            if fnmatch.fnmatch(candidate, pattern) or fnmatch.fnmatch(candidate, expanded):
                return pattern
    return None


def is_exempt_suffix(path, suffixes):
    base = os.path.basename(path or "")
    return any(base.endswith(s) for s in suffixes)


def extract_paths(tool_input, tool_kind):
    if tool_kind == "bash":
        # So o que o shell EXECUTA. Sem esta separacao, mencionar um caminho sensivel como DADO
        # era tratado como tentativa de le-lo — e o guarda chegou a bloquear a sessao que estava
        # escrevendo a documentacao dele proprio. Mesma regra e mesmos limites do guarda
        # destrutivo; ver lib/shell_text.py.
        command = shell_text.executable_text(tool_input.get("command") or "")
        # Tokens que parecem caminho. Heuristica deliberadamente ampla: sobre-detectar aqui
        # custa um `ask`; sub-detectar custa um vazamento.
        return re.findall(r"[~/\w.\-]*[/.][\w.\-/]+", command), command
    found = []
    for key in ("file_path", "path", "notebook_path"):
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            found.append(value)
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        for edit in edits:
            if isinstance(edit, dict):
                value = edit.get("file_path")
                if isinstance(value, str) and value:
                    found.append(value)
    return found, ""


def result(decision, reason, **extra):
    payload = {"decision": decision, "reason": reason}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def main():
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )

    tool_kind = "write"
    argv = sys.argv[1:]
    if "--tool" in argv:
        idx = argv.index("--tool")
        if idx + 1 < len(argv):
            tool_kind = argv[idx + 1]

    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except (ValueError, TypeError):
        payload = {}

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}
    tool_name = (payload.get("tool_name") or "").lower()

    try:
        config = load_config(plugin_root)
    except (IOError, OSError, ValueError) as exc:
        # Config ilegivel e' falha do guarda, nunca "liberado".
        return result("error", "config de caminhos sensiveis ilegivel: %s" % exc)

    mode = config.get("default_mode", "block")
    patterns = config.get("patterns", {})
    non_overridable = config.get("non_overridable", [])
    exemptions = config.get("context_exemptions", [])
    exempt_suffixes = config.get("_exempt_suffixes", [])

    paths, command = extract_paths(tool_input, tool_kind)

    # Isencao de contexto primeiro: a propria skill do harness nao pode ser bloqueada por ele.
    for path in paths:
        if matches_any(path, exemptions):
            return result("allow", "caminho isento por contexto (skill do harness)")

    # 1. non_overridable — nenhuma excecao alcanca.
    for path in paths:
        if is_exempt_suffix(path, exempt_suffixes):
            continue
        hit = matches_any(path, non_overridable)
        if hit:
            return result(
                "block",
                "'%s' esta na classe nao-negociavel do guarda de caminhos (padrao '%s'). "
                "Nenhuma excecao local libera esta classe." % (path, hit),
                path=path,
                pattern=hit,
                klass="non_overridable",
            )

    # 2. comandos perigosos (so no caminho bash)
    if tool_kind == "bash" and command:
        for regex, label in DANGEROUS_COMMANDS:
            if re.search(regex, command):
                return result(
                    "block" if mode == "block" else "ask",
                    "comando de acesso a credencial ou dados sensiveis detectado (%s). "
                    "Aplique LT-SEC-002: use gerenciador de segredos, nunca credencial em "
                    "linha de comando." % label,
                    klass="dangerous_command",
                    label=label,
                )

    # 3. leitura/escrita de caminho sensivel
    key = "read" if tool_kind == "bash" or tool_name in ("read",) else "write"
    for path in paths:
        if is_exempt_suffix(path, exempt_suffixes):
            continue
        hit = matches_any(path, patterns.get(key, []))
        if hit:
            return result(
                "block" if mode == "block" else "ask",
                "'%s' casa o guarda de caminhos sensiveis (padrao '%s', classe %s). "
                "Aplique LT-FILE-001." % (path, hit, key),
                path=path,
                pattern=hit,
                klass=key,
                required_token="sensitive-read" if key == "read" else "sensitive-write",
            )

    # 4. infra: revisao antes de aplicar (LT-FILE-002). Sempre `ask`, nunca block.
    if key == "write":
        for path in paths:
            hit = matches_any(path, patterns.get("review_before_apply", []))
            if hit:
                return result(
                    "ask",
                    "'%s' e' configuracao de infraestrutura (padrao '%s'). LT-FILE-002 exige "
                    "revisao humana antes de aplicar alteracao sugerida pela IA." % (path, hit),
                    path=path,
                    pattern=hit,
                    klass="review_before_apply",
                )

    return result("allow", "nenhum padrao casou")


if __name__ == "__main__":
    sys.exit(main())
