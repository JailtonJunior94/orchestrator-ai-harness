#!/usr/bin/env python3
# lt / lib / secret_scan.py
#
# Resolvedor de segredo literal, UMA invocacao por disparo de hook.
#
# POR QUE UMA INVOCACAO: este hook roda em toda chamada de Write/Edit/MultiEdit. Cada processo
# python custa ~170ms. Nesta frota o custo e' ainda mais sensivel porque ja existe outro hook
# registrado em PreToolUse/Bash (hooks de plugin e de user settings sao SOMADOS, nao
# substituidos). Entao o hook faz um unico fork e resolve tudo aqui dentro.
#
# POR QUE `ask` E NAO `exit 2`: o bloqueio duro ensina o agente a contornar o gate — na pratica
# ele move a senha para outro arquivo que o padrao nao cobre. O `ask` mantem o humano no loop,
# que e' o objetivo declarado em LT-SEC-001.
#
# Saida: JSON no stdout, sempre exit 0. O hook decide o que fazer com o veredito.

import json
import os
import re
import sys

MAX_SCAN_DEFAULT = 200000


def load_config(plugin_root):
    path = os.path.join(plugin_root, "config", "secret-patterns.json")
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def gather_text(tool_input):
    """Junta os campos onde conteudo novo pode chegar, por ferramenta.

    MultiEdit entrega uma lista em `edits`; ignorar esse caminho deixaria o vetor mais
    conveniente de todos aberto.
    """
    chunks = []
    for key in ("content", "new_string", "command", "prompt"):
        value = tool_input.get(key)
        if isinstance(value, str):
            chunks.append(value)
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        for edit in edits:
            if isinstance(edit, dict) and isinstance(edit.get("new_string"), str):
                chunks.append(edit["new_string"])
    return "\n".join(chunks)


def path_is_exempt(file_path, exempt_globs, exempt_suffixes):
    if not file_path:
        return False
    import fnmatch

    base = os.path.basename(file_path)
    for suffix in exempt_suffixes:
        if base.endswith(suffix):
            return True
    for pattern in exempt_globs:
        if fnmatch.fnmatch(file_path, pattern) or fnmatch.fnmatch(base, pattern):
            return True
    return False


def mask(value):
    """Prefixo mascarado. O achado precisa ser identificavel sem que o segredo viaje junto
    para o log, o stderr ou a pendencia de rotacao."""
    value = value.strip()
    if len(value) <= 8:
        return value[:2] + "***"
    return value[:6] + "***" + ("(%d chars)" % len(value))


def scan(text, config):
    findings = []
    for pattern in config.get("patterns", []):
        regex = pattern.get("regex")
        if not regex:
            continue
        try:
            compiled = re.compile(regex)
        except re.error as exc:
            # Padrao quebrado e' erro de configuracao, nao motivo para o guarda emudecer.
            findings.append(
                {
                    "id": pattern.get("id", "?"),
                    "name": "PADRAO INVALIDO",
                    "severity": "critical",
                    "sample": "regex invalida: %s" % exc,
                    "config_error": True,
                }
            )
            continue
        match = compiled.search(text)
        if match:
            findings.append(
                {
                    "id": pattern.get("id", "?"),
                    "name": pattern.get("name", pattern.get("id", "?")),
                    "severity": pattern.get("severity", "medium"),
                    "sample": mask(match.group(0)),
                    "note": pattern.get("note", ""),
                }
            )
    return findings


def main():
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )

    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except (ValueError, TypeError):
        payload = {}

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}

    try:
        config = load_config(plugin_root)
    except (IOError, OSError, ValueError) as exc:
        # Config ilegivel e' falha do guarda. Anuncia alto; nunca devolve "limpo".
        print(
            json.dumps(
                {
                    "decision": "error",
                    "reason": "config de segredos ilegivel: %s" % exc,
                    "findings": [],
                }
            )
        )
        return 0

    file_path = tool_input.get("file_path") or tool_input.get("path") or ""
    exempt_globs = config.get("_exempt_paths", [])
    exempt_suffixes = config.get("_exempt_suffixes", [".example", ".sample", ".template", ".dist"])

    if path_is_exempt(file_path, exempt_globs, exempt_suffixes):
        print(json.dumps({"decision": "allow", "reason": "caminho isento", "findings": []}))
        return 0

    text = gather_text(tool_input)
    if not text:
        print(json.dumps({"decision": "allow", "reason": "sem conteudo novo", "findings": []}))
        return 0

    cap = int(config.get("_max_scan_chars", MAX_SCAN_DEFAULT))
    truncated = len(text) > cap
    text = text[:cap]

    findings = scan(text, config)
    blocking = [f for f in findings if f["severity"] in ("critical", "high")]

    critical = [f for f in blocking if f["severity"] == "critical"]

    if blocking:
        names = ", ".join("%s (%s)" % (f["name"], f["sample"]) for f in blocking[:3])
        # FATO DO HOST, documentado: `permissionDecision: "deny"` cancela a chamada MESMO em
        # bypassPermissions e com --dangerously-skip-permissions; `"ask"` apenas mostra o prompt
        # "normalmente" — e onde nao ha prompt, nao ha nada.
        #
        # A frota desta organizacao roda com --dangerously-skip-permissions no alias. Com `ask`
        # em tudo, a guarda de segredos ficaria INERTE justamente nas maquinas que mais confiam
        # nela. Entao:
        #   critical -> deny  (credencial de producao: nao se negocia com bypass)
        #   high     -> ask   (mantem o humano no loop onde ha prompt; o bloqueio duro ensinaria
        #                      o agente a contornar, que e' o defeito que `ask` evita)
        decision = "deny" if critical else "ask"
        reason = (
            "Possivel segredo literal no conteudo: %s. "
            "Use variavel de ambiente ou gerenciador de segredos (LT-SEC-001/002). "
            "Se a chave for real e ja foi exposta, rotacione e registre com "
            "`lt:lt-approve secret-rotated <uid>`." % names
        )
    elif findings:
        decision = "notice"
        reason = "Indicio de baixa severidade: %s" % ", ".join(f["name"] for f in findings[:3])
    else:
        decision = "allow"
        reason = "nenhum padrao casou"

    print(
        json.dumps(
            {
                "decision": decision,
                "reason": reason,
                "findings": findings,
                "critical": len(critical),
                "truncated": truncated,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
