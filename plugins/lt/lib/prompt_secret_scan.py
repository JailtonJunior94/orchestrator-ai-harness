#!/usr/bin/env python3
# lt / lib / prompt_secret_scan.py
#
# Varre o PROMPT (evento UserPromptSubmit) em busca de segredo literal e emite as pendencias de
# rotacao ja mascaradas, uma por linha JSON.
#
# A pendencia carrega PREFIXO MASCARADO, nunca o segredo. Um arquivo de pendencia com a chave em
# claro seria um segundo vazamento — agora em disco e persistente.
#
# Arquivo proprio pelo mesmo motivo de context_pct.py: heredoc python dentro de $( ) quebra no
# bash 3.2.

import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import secret_scan  # noqa: E402


def main():
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))
    )
    uid = os.environ.get("LT_UID") or "sem-uid"

    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, TypeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    text = payload.get("prompt") or ""
    if not text:
        return 0

    try:
        config = secret_scan.load_config(plugin_root)
    except (IOError, OSError, ValueError):
        return 0

    cap = int(config.get("_max_scan_chars", 200000))
    findings = secret_scan.scan(text[:cap], config)
    blocking = [f for f in findings if f.get("severity") in ("critical", "high")]

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    for finding in blocking:
        print(
            json.dumps(
                {
                    "uid": uid,
                    "detected_at": now,
                    "pattern_id": finding.get("id"),
                    "pattern_name": finding.get("name"),
                    "severity": finding.get("severity"),
                    "masked": finding.get("sample"),
                    "status": "pending",
                    "source": "user_prompt",
                },
                ensure_ascii=False,
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
