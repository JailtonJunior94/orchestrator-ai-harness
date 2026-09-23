#!/usr/bin/env python3
# tests / unit / lib / run-destructive-cases.py
#
# Roda os casos de tests/fixtures/destructive-cases.json contra o guarda destrutivo.
#
# Existe em python, e nao em bash, por um motivo concreto: o hook PreToolUse/Bash do proprio
# harness bloqueia qualquer comando de shell que contenha os literais destrutivos, inclusive um
# teste que apenas os passa como argumento. Python nao passa por esse evento.

import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GUARD = os.path.join(REPO, "plugins", "lt", "lib", "destructive_guard.py")
CASES = os.path.join(REPO, "tests", "fixtures", "destructive-cases.json")


def decide(command):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
    proc = subprocess.run(
        [sys.executable, GUARD],
        input=payload.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        # cwd fora de arvore git: torna o resultado deterministico entre maquinas, porque
        # "reversivel por snapshot" depende de estar dentro de um repositorio.
        cwd="/tmp",
        env=dict(os.environ, CLAUDE_PROJECT_DIR="/tmp"),
    )
    try:
        return json.loads(proc.stdout.decode() or "{}").get("decision", "?")
    except (ValueError, TypeError):
        return "?"


def main():
    with io.open(CASES, encoding="utf-8") as fh:
        data = json.load(fh)

    fails = 0
    for case in data["casos"]:
        got = decide(case["cmd"])
        want = case["esperado"]
        label = "%s  [%s]" % (case["cmd"][:44], case["classe"])
        if got == want:
            print("OK %s -> %s" % (label, got))
        else:
            print("FAIL %s -> %s (esperado %s)" % (label, got, want))
            fails += 1
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
