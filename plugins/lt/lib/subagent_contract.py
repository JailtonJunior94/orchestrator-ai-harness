#!/usr/bin/env python3
# lt / lib / subagent_contract.py
#
# Confere o contrato de retorno do subagente `task-executor` (execute-all-tasks, Etapa 4):
#
#   status: done | blocked | failed | needs_input
#   report_path: <caminho relativo a raiz do repositorio>
#   summary: <1 linha>
#
# Exatamente esses tres campos, sem extra, sem duplicata, sem texto livre em volta. Para `done`,
# o relatorio tem de existir e nao estar vazio, e o checkpoint `.checkpoints/<id>.json` (que o
# execute-task grava ANTES de mutar tasks.md) tem de existir e passar no schema de checkpoint.
#
# De onde vem a mensagem: `last_assistant_message` do payload do SubagentStop; nas versoes que
# nao a trazem, a ultima mensagem de assistente do `agent_transcript_path`. Sem nenhuma das duas,
# o formato do host mudou — isso e' erro INTERNO (skip anunciado), nao violacao do subagente.
#
# Saida: duas linhas — a decisao (ok|block|skip) e o motivo em uma linha —, exit 0 sempre. Texto
# plano de proposito: o hook le sem um segundo fork de interpretador so para desembrulhar JSON.

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

FIELDS = ("status", "report_path", "summary")
STATUSES = ("done", "blocked", "failed", "needs_input")
RE_FENCE = re.compile(r"```(?:ya?ml)?\s*\n(.*?)```", re.S)
RE_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$")
RE_REPORT = re.compile(r"(?:^|/)(\d+\.\d+)_execution_report\.md$")


def out(decision, reason=""):
    print(decision)
    print(" ".join(reason.split()))
    return 0


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


def last_from_transcript(path):
    if not isinstance(path, str) or not os.path.isfile(path):
        return None
    last = None
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue
            message = row.get("message") if isinstance(row, dict) else None
            if isinstance(message, dict) and message.get("role") == "assistant":
                text = text_of(message.get("content"))
                if text.strip():
                    last = text
    return last


def parse_envelope(message):
    """(campos, erros). Aceita bloco cercado ```yaml ou o texto inteiro como YAML plano."""
    fenced = RE_FENCE.findall(message)
    if len(fenced) > 1:
        return {}, ["mais de um bloco YAML no retorno"]
    body = fenced[0] if fenced else message
    outside = RE_FENCE.sub("", message).strip() if fenced else ""
    errors = []
    if outside:
        errors.append("texto livre fora do bloco YAML")
    fields = {}
    for raw in body.strip().splitlines():
        line = raw.strip()
        if not line:
            continue
        match = RE_LINE.match(line)
        if not match:
            errors.append("linha fora do contrato: %r" % line[:60])
            continue
        key, value = match.group(1), match.group(2).strip().strip("'\"")
        if key in fields:
            errors.append("campo duplicado: %s" % key)
        fields[key] = value
    extra = sorted(set(fields) - set(FIELDS))
    missing = [f for f in FIELDS if f not in fields]
    if extra:
        errors.append("campos fora do contrato: %s" % ", ".join(extra))
    if missing:
        errors.append("campos ausentes: %s" % ", ".join(missing))
    return fields, errors


def check(fields, root):
    errors = []
    status = fields.get("status")
    if status not in STATUSES:
        errors.append("status invalido: %r (use %s)" % (status, "|".join(STATUSES)))
    report = fields.get("report_path") or ""
    if not fields.get("summary"):
        errors.append("summary vazio")
    if report.startswith("/") or re.match(r"^[A-Za-z]:", report) or ".." in report.replace("\\", "/").split("/"):
        errors.append("report_path deve ser relativo a raiz do repositorio, sem '..': %r" % report)
        return errors
    if status != "done":
        return errors
    path = os.path.realpath(os.path.join(root, report))
    if os.path.commonpath([root, path]) != root or not os.path.isfile(path) or os.path.getsize(path) == 0:
        errors.append("done sem relatorio fisico: %s ausente ou vazio" % report)
        return errors
    match = RE_REPORT.search(report.replace("\\", "/"))
    if not match:
        errors.append("report_path fora da convencao <bundle>/<id>_execution_report.md: %r" % report)
        return errors
    checkpoint = os.path.join(os.path.dirname(path), ".checkpoints", "%s.json" % match.group(1))
    if not os.path.isfile(checkpoint):
        errors.append("done sem checkpoint %s (execute-task grava antes de mutar tasks.md)"
                      % os.path.relpath(checkpoint, root))
        return errors
    import sdd  # noqa: E402
    try:
        data = json.load(open(checkpoint, encoding="utf-8"))
    except ValueError as exc:
        return errors + ["checkpoint ilegivel: %s" % exc]
    problems = sdd.result_errors("checkpoint", data)
    if isinstance(data, dict) and data.get("status") != status:
        problems.append("checkpoint diz status=%r, retorno diz %r" % (data.get("status"), status))
    errors.extend("checkpoint: %s" % p for p in problems)
    return errors


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, TypeError):
        return out("skip", "payload ilegivel")
    if not isinstance(payload, dict):
        return out("skip", "payload fora do formato")
    if payload.get("stop_hook_active") is True:
        # O bloqueio ja foi aplicado nesta retomada. Bloquear de novo prenderia o subagente em loop.
        return out("skip", "stop_hook_active")
    agent = str(payload.get("agent_type") or "")
    if agent and not agent.endswith("task-executor"):
        return out("skip", "subagente fora do contrato: %s" % agent)
    message = None
    for key in ("last_assistant_message", "subagent_output", "output"):
        if isinstance(payload.get(key), str) and payload[key].strip():
            message = payload[key]
            break
    if message is None:
        message = last_from_transcript(payload.get("agent_transcript_path"))
    if message is None:
        return out("skip", "retorno do subagente nao encontrado no payload nem no transcript")
    root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd())
    fields, errors = parse_envelope(message)
    if not errors:
        errors = check(fields, root)
    if errors:
        return out("block", "contract violation: " + "; ".join(errors))
    return out("ok")


if __name__ == "__main__":
    sys.exit(main())
