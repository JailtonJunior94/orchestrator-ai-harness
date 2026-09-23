#!/usr/bin/env python3
# lt / lib / context_pct.py
#
# Calcula o percentual de uso da janela de contexto: uso lido do payload ou, como o host nao o
# manda, do transcript da sessao; janela lida do payload ou da configuracao explicita.
#
# REGRA CENTRAL: DESCONHECIDO RESOLVE PARA DESCONHECIDO.
# Se a janela nao vier de fonte confiavel, imprime lt_ctx_unknown_window e o hook cala.
# A tentacao seria assumir a menor janela plausivel "por seguranca", mas isso produz avisos de
# 115% em que ninguem acredita — e um aviso em que ninguem acredita e' pior que nenhum aviso,
# porque treina a pessoa a ignorar a categoria inteira.
#
# Vive em arquivo proprio, e nao num heredoc dentro do hook, por um motivo concreto: no bash 3.2
# um heredoc dentro de $( ) tem o conteudo reparseado e um apostrofo em comentario quebra o
# script inteiro. Arquivo separado tambem torna esta logica testavel sozinha.

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import transcript_usage  # noqa: E402

USED_KEYS = ("context_used_tokens", "used_tokens", "input_tokens")
TOTAL_KEYS = ("context_window", "context_window_tokens", "max_context_tokens")

UNKNOWN = "lt_ctx_unknown_window"

# O host nao informa o tamanho da janela em nenhum payload nem no transcript (sondado no CLI
# 2.1.280). Por isso ela vem de configuracao explicita, e o valor da preferencia e' ENUM, como
# toda preferencia do harness: o arquivo so' seleciona um numero daqui, nunca fornece um.
WINDOW_ENUM = {"200k": 200000, "1m": 1000000}


def window_from_config():
    raw = os.environ.get("LT_CONTEXT_WINDOW", "").strip()
    if raw.isdigit() and int(raw) > 0:
        return float(raw)
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    plugin = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for path in (
        os.path.join(os.environ.get("CLAUDE_PROJECT_DIR", "."), ".lt", "preferences.json"),
        os.path.join(cfg, "lt", "preferences.json"),
        os.path.join(plugin, "config", "preferences.defaults.json"),
    ):
        try:
            value = json.load(open(path, encoding="utf-8")).get("context_window")
        except (OSError, IOError, ValueError, AttributeError):
            continue
        if value in WINDOW_ENUM:
            return float(WINDOW_ENUM[value])
        if value is not None:
            return None  # `unknown` ou valor fora da enum: desconhecido, e nao cai para o proximo
    return None


def pick(payload, keys):
    for key in keys:
        value = payload.get(key)
        if isinstance(value, (int, float)) and value > 0:
            return float(value)
    return None


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, TypeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    used = pick(payload, USED_KEYS)
    if used is None:
        usage = transcript_usage.last_usage(payload.get("transcript_path"))
        if usage and usage["context_tokens"] > 0:
            used = float(usage["context_tokens"])
    total = pick(payload, TOTAL_KEYS) or window_from_config()

    if used is None or total is None:
        print(UNKNOWN)
        return 0

    pct = used / total * 100.0

    # Guard de sanidade INDEPENDENTE do calculo. Todo numero exibido passa por aqui, mesmo que
    # a conta acima pareca obviamente correta.
    if not 0 < pct <= 100:
        print(UNKNOWN)
        return 0

    print("%d %s" % (int(pct), payload.get("session_id") or "nosession"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
