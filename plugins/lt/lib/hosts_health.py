#!/usr/bin/env python3
"""Saude dos hosts adaptados (Codex, Copilot, OpenCode) para o `lt-doctor --hosts`.

Tres perguntas, cada uma com um modo de falha silenciosa conhecido:
1. A copia instalada bate com a fonte? (drift de arquivo; fonte que evoluiu sem reinstalar)
2. O Codex tem trusted_hash para cada hook nosso? Sem ele o hook e' pulado sem aviso.
3. Os hooks do host DISPARARAM desde a instalacao? E' a unica prova de ponta a ponta: se uma
   versao nova do Codex mudar a formula do hash, (2) continua "ok" e so' (3) acusa.

Saida: linhas "ok|warn|bad<TAB>mensagem". Exit 1 se houver "bad".
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
from runtime_freshness import check as freshness  # noqa: E402

try:
    import tomllib
except ImportError:
    tomllib = None


def emit(level, message):
    print("%s\t%s" % (level, message))


def main():
    home = os.path.expanduser("~")
    runtime = os.environ.get("LT_RUNTIME_HOME") or os.path.join(home, ".lt-harness")
    lt_home = os.path.join(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(home, ".claude"), "lt")
    manifest_path = os.path.join(runtime, "manifest.json")
    if not os.path.isfile(manifest_path):
        emit("warn", "nenhuma instalacao global em %s (Codex/Copilot/OpenCode fora do escopo global)"
             % runtime)
        return 0
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    hosts = manifest.get("hosts", [])
    emit("ok", "instalacao global %s: hosts %s" % (manifest.get("version", "?"), ", ".join(hosts)))
    bad = False

    drift = [path for path, expected in manifest.get("files", {}).items()
             if not os.path.isfile(path)]
    if drift:
        emit("bad", "%d arquivo(s) da instalacao sumiram (ex.: %s) — reinstale" % (len(drift), drift[0]))
        bad = True
    stale = freshness(runtime)
    if stale:
        emit("warn", stale)
    else:
        emit("ok", "copia instalada em dia com a fonte")

    trust = (manifest.get("trust") or {}).get("codex")
    if "codex" in hosts and trust and tomllib is not None:
        hooks_file = os.path.realpath(os.path.join(os.environ.get("CODEX_HOME") or os.path.join(home, ".codex"),
                                                   "hooks.json"))
        try:
            states = (tomllib.load(open(trust, "rb")).get("hooks") or {}).get("state") or {}
            ours = [key for key in states if key.startswith(hooks_file + ":")]
            if len(ours) >= 5:
                emit("ok", "Codex: trusted_hash registrado para %d hook(s)" % len(ours))
            else:
                emit("bad", "Codex: so' %d trusted_hash para %s — hooks sem trust sao pulados em silencio"
                     % (len(ours), hooks_file))
                bad = True
        except (OSError, ValueError) as error:
            emit("bad", "Codex: config.toml ilegivel (%s)" % error)
            bad = True

    installed_at = int(manifest.get("installed_at") or 0)
    for host in hosts:
        path = os.path.join(lt_home, "heartbeat", host + ".json")
        try:
            beat = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            beat = None
        if not beat or int(beat.get("ts", 0)) < installed_at:
            hint = {"codex": "confira o trusted_hash (uma versao nova do Codex pode ter mudado a formula)",
                    "copilot": "confira $COPILOT_HOME/hooks/lt-governance.json",
                    "opencode": "confira o plugin em $XDG_CONFIG_HOME/opencode/plugins"}.get(host, "")
            emit("warn", "%s: nenhuma sessao com hooks do harness desde a instalacao. Abra uma sessao; "
                 "se continuar assim, os hooks estao sendo pulados — %s." % (host, hint))
            continue
        age = int(time.time()) - int(beat["ts"])
        emit("ok", "%s: hooks dispararam ha %s (versao %s)" % (
            host, "%dmin" % (age // 60) if age < 86400 else "%dd" % (age // 86400), beat.get("version", "?")))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
