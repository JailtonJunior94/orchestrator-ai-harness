#!/usr/bin/env python3
# lt / lib / transcript_usage.py
#
# Le o uso de tokens da ULTIMA mensagem do assistente no transcript da sessao.
#
# POR QUE ESTE ARQUIVO EXISTE
# Dois hooks esperavam contagem de tokens no payload do host: o aviso de janela procurava
# `context_used_tokens` no UserPromptSubmit e o registro de custo procurava `input_tokens` no
# PostToolUse. Sondado com payload real (CLI 2.1.280), nenhum dos dois eventos traz campo de uso:
# o aviso nunca disparava e o "custo diario" gravava so' nome de ferramenta. O que o host entrega
# e' `transcript_path`, e cada mensagem do assistente no transcript carrega `message.usage`.
#
# CUSTO: le so' o fim do arquivo (TAIL_BYTES). O hook de custo roda em toda chamada de
# ferramenta; reler um transcript de dezenas de MB a cada chamada seria o tipo de custo que faz a
# pessoa desligar o hook.

import json
import os

TAIL_BYTES = 262144


def _tail_lines(path):
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                fh.readline()  # descarta a linha cortada no meio
            data = fh.read()
    except (OSError, IOError):
        return []
    return data.decode("utf-8", "replace").splitlines()


def last_usage(path):
    """Devolve o uso da ultima mensagem do assistente, ou None.

    `context_tokens` e' o que ocupou a janela naquela chamada: entrada nova mais o que veio do
    cache (lido e criado). E' a soma que o host usa para dizer quanto da janela foi gasto.
    """
    if not path or not os.path.isfile(path):
        return None
    for line in reversed(_tail_lines(path)):
        try:
            entry = json.loads(line)
        except (ValueError, TypeError):
            continue
        message = entry.get("message") if isinstance(entry, dict) else None
        usage = message.get("usage") if isinstance(message, dict) else None
        if entry.get("type") != "assistant" or not isinstance(usage, dict):
            continue

        def num(key):
            value = usage.get(key)
            return int(value) if isinstance(value, (int, float)) else 0

        return {
            "message_id": message.get("id") or entry.get("uuid") or "",
            "model": message.get("model") or "",
            "input_tokens": num("input_tokens"),
            "output_tokens": num("output_tokens"),
            "cache_read_input_tokens": num("cache_read_input_tokens"),
            "cache_creation_input_tokens": num("cache_creation_input_tokens"),
            "context_tokens": num("input_tokens") + num("cache_read_input_tokens")
            + num("cache_creation_input_tokens"),
        }
    return None
