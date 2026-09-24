#!/usr/bin/env python3
"""Digest da fonte do plugin e checagem de frescor da copia instalada fora do Claude Code.

Claude Code atualiza o plugin pelo marketplace. Codex, Copilot e OpenCode rodam uma COPIA
projetada (~/.lt-harness ou <repo>/.lt-harness): se o repositorio do harness evolui e ninguem
reinstala, os hosts seguem com regra velha sem nenhum aviso. Este modulo e' o aviso.

Uso:
  runtime_freshness.py digest <plugin-dir>     imprime o digest da fonte
  runtime_freshness.py check <runtime-dir>     imprime aviso se a copia estiver velha; exit 0 sempre
"""
import hashlib
import json
import os
import sys

# Mesmas pastas que o reconciler projeta; o que nao chega aos hosts nao entra no digest.
PARTS = (".claude-plugin", "agents", "commands", "config", "hooks", "lib", "scripts", "skills")


def plugin_digest(plugin):
    value = hashlib.sha256()
    for part in PARTS:
        root = os.path.join(plugin, part)
        for current, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in ("__pycache__", "evals", "results"))
            for name in sorted(files):
                if name.endswith((".pyc", ".pyo")) or name == ".DS_Store":
                    continue
                path = os.path.join(current, name)
                value.update(os.path.relpath(path, plugin).encode("utf-8") + b"\0")
                with open(path, "rb") as stream:
                    value.update(hashlib.sha256(stream.read()).digest())
    return value.hexdigest()


def check(runtime):
    path = os.path.join(runtime, "manifest.json")
    try:
        with open(path, "r", encoding="utf-8") as stream:
            manifest = json.load(stream)
    except (OSError, ValueError):
        return ""
    source = manifest.get("source_plugin")
    installed = manifest.get("plugin_digest")
    if not source or not installed:
        return ""
    if not os.path.isdir(source):
        return ("Harness LT: a fonte da instalacao (%s) nao existe mais; esta copia nao recebe "
                "atualizacao. Reinstale a partir do clone atual." % source)
    if plugin_digest(source) != installed:
        scope = manifest.get("scope", "global")
        hint = ("bash scripts/update.sh --hosts %s" % ",".join(manifest.get("hosts", []))
                if scope == "global" else
                "bash scripts/update.sh --hosts %s --project %s"
                % (",".join(manifest.get("hosts", [])), manifest.get("base", ".")))
        return ("Harness LT DESATUALIZADO neste host: a fonte mudou depois da instalacao "
                "(%s). Rode no clone do harness: %s" % (manifest.get("version", "?"), hint))
    return ""


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("digest", "check"):
        sys.stderr.write(__doc__)
        return 2
    if sys.argv[1] == "digest":
        print(plugin_digest(sys.argv[2]))
        return 0
    message = check(sys.argv[2])
    if message:
        print(message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
