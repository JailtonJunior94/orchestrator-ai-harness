#!/usr/bin/env python3
# tests / unit / lib / run-sensitive-cases.py
#
# Roda tests/fixtures/sensitive-cases.json contra o guarda de caminhos sensiveis.
#
# Em python, e nao em bash, pelo mesmo motivo do runner destrutivo: o hook PreToolUse/Bash do
# proprio harness bloqueia um comando de shell que mencione os caminhos, mesmo como dado.

import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
GUARD = os.path.join(REPO, "plugins", "lt", "lib", "sensitive_paths.py")
CASES = os.path.join(REPO, "tests", "fixtures", "sensitive-cases.json")


def decide(command):
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
    proc = subprocess.run(
        [sys.executable, GUARD, "--tool", "bash"],
        input=payload.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=dict(os.environ, CLAUDE_PLUGIN_ROOT=os.path.join(REPO, "plugins", "lt")),
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
        label = "%s  [%s]" % (case["cmd"][:42], case["classe"])
        if got == want:
            print("OK %s -> %s" % (label, got))
        else:
            print("FAIL %s -> %s (esperado %s)" % (label, got, want))
            fails += 1
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
