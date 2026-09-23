#!/usr/bin/env python3
# lt / lib / telemetry_line.py
#
# Converte o payload de um hook numa linha JSONL de telemetria LOCAL.
#
# O que NAO entra na linha: conteudo de arquivo, texto de prompt, argumento de comando. Telemetria
# que carrega payload vira um segundo lugar onde um segredo pode parar — e um que ninguem lembra
# de auditar. Aqui so entram nome, horario e contagem.

import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transcript_usage  # noqa: E402


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else "event"
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, TypeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    now = datetime.datetime.now(datetime.timezone.utc)
    line = {
        "ts": now.isoformat(),
        "day": now.strftime("%Y-%m-%d"),
        "kind": "skill.fire" if kind == "skill" else "tool.cost",
        "tool": payload.get("tool_name") or "",
        "session": payload.get("session_id") or "",
    }

    if kind == "skill":
        tool_input = payload.get("tool_input")
        if isinstance(tool_input, dict):
            name = tool_input.get("skill") or tool_input.get("name") or ""
            if isinstance(name, str):
                line["skill"] = name
    else:
        # O PostToolUse nao traz tokens (sondado no CLI 2.1.280): o uso real esta no transcript.
        # Varias chamadas de ferramenta dentro da mesma mensagem do assistente veem o MESMO uso,
        # entao a linha so' sai quando o id da mensagem muda; senao o custo do dia seria somado
        # uma vez por ferramenta chamada. Sem uso legivel, nao ha' linha: uma linha de "custo"
        # sem numero nenhum era o que este hook gravava antes.
        usage = transcript_usage.last_usage(payload.get("transcript_path"))
        if not usage:
            return 0
        state = sys.argv[2] if len(sys.argv) > 2 else ""
        key = "%s %s" % (line["session"], usage["message_id"])
        if state and _seen(state, key):
            return 0
        for field in ("input_tokens", "output_tokens", "cache_read_input_tokens",
                      "cache_creation_input_tokens"):
            line[field] = usage[field]
        line["model"] = usage["model"]
        line["message_id"] = usage["message_id"]
        if state:
            _remember(state, key)

    print(json.dumps(line, ensure_ascii=False))
    return 0


def _seen(state, key):
    try:
        return key in open(state, encoding="utf-8").read().splitlines()
    except (OSError, IOError):
        return False


def _remember(state, key):
    # Guarda so' a ultima chave de cada sessao: o arquivo e' um cursor, nao um historico.
    try:
        keys = open(state, encoding="utf-8").read().splitlines()
    except (OSError, IOError):
        keys = []
    session = key.split(" ", 1)[0]
    keys = [k for k in keys if k.split(" ", 1)[0] != session][-49:] + [key]
    try:
        with open(state, "w", encoding="utf-8") as fh:
            fh.write("\n".join(keys) + "\n")
    except (OSError, IOError):
        pass


if __name__ == "__main__":
    sys.exit(main())
