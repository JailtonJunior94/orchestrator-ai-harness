#!/usr/bin/env python3
"""Adapta eventos de Codex, Copilot e OpenCode para os hooks canonicos do plugin LT.

POR QUE LER O hooks.json EM VEZ DE UMA LISTA PROPRIA
A primeira versao deste adaptador carregava uma lista fixa de scripts por evento. Cada hook novo
registrado em hooks.json exigia lembrar de editar a lista aqui tambem, e o esquecimento produz o
defeito mais silencioso possivel: o hook protege o Claude Code e nao protege os outros tres hosts.
Agora a fonte unica e' o hooks.json canonico copiado para o runtime; o matcher de cada grupo e'
aplicado ao nome canonico da ferramenta, exatamente como o Claude Code faz.

FORMATOS PROVADOS POR EXECUCAO (docs/host-facts.md, secao multi-host)
- Codex 0.156: payload no formato do Claude (tool_name/tool_input/session_id/cwd). Edicao chega
  como tool_name "apply_patch" com o patch em tool_input.command. Deny: exit 2 + stderr.
- Copilot 1.0 (hooks camelCase, version 1): toolName/toolArgs/sessionId/cwd; prompt em "prompt".
  Deny: exit 2 + stderr.
- OpenCode 1.18: o plugin JS repassa {tool, args, sessionID}; deny e' o plugin lancar excecao
  quando este processo sai com codigo != 0.
"""

import json
import os
import re
import subprocess
import sys


HOSTS = ("codex", "copilot", "opencode")

# Evento neutro -> evento canonico do hooks.json. SubagentStop fica de fora de proposito: nenhum
# dos tres hosts disparou evento de fim de subagente nas sondas, e simular o evento a partir de
# outro geraria bloqueio sobre um retorno que o host nunca entregou.
EVENTS = {
    "session_start": "SessionStart",
    "prompt": "UserPromptSubmit",
    "before_tool": "PreToolUse",
    "after_tool": "PostToolUse",
    "stop": "Stop",
}

TOOL_ALIASES = {
    "shell": "Bash", "bash": "Bash", "terminal": "Bash", "exec": "Bash", "exec_command": "Bash",
    "local_shell": "Bash", "run_in_terminal": "Bash", "powershell": "Bash",
    "write": "Write", "create": "Write", "create_file": "Write",
    "edit": "Edit", "str_replace": "Edit", "str_replace_editor": "Edit", "apply_patch": "Edit",
    "patch": "Edit", "multiedit": "MultiEdit", "multi_edit": "MultiEdit",
    "read": "Read", "view": "Read", "read_file": "Read",
    "skill": "Skill", "task": "Task", "agent": "Task",
}

# Scripts cujo contrato depende de evento que so' o Claude Code emite. O gate de preload prova
# "governanca carregada" pelo disparo do tool Skill; o Codex le SKILL.md por shell e nunca
# dispara esse evento, entao o gate bloquearia toda edicao para sempre. Nos outros hosts ele
# roda em modo aviso, salvo se o operador fixar LT_PRELOAD_GATE explicitamente.
WARN_ONLY_DEFAULTS = {"LT_PRELOAD_GATE": "warn"}


def load_payload():
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
        return data if isinstance(data, dict) else {}
    except ValueError:
        return {}


def canonical_tool(name):
    text = str(name or "")
    return TOOL_ALIASES.get(text.lower(), text)


def normalize(host, event, payload):
    tool = payload.get("tool_name") or payload.get("toolName") or payload.get("tool") or payload.get("name") or ""
    tool_input = (payload.get("tool_input") or payload.get("toolArgs") or payload.get("args")
                  or payload.get("input") or {})
    if isinstance(tool_input, str):
        # Copilot pode serializar toolArgs como string JSON; o Codex entrega o patch cru.
        try:
            parsed = json.loads(tool_input)
            tool_input = parsed if isinstance(parsed, dict) else {"command": tool_input}
        except ValueError:
            tool_input = {"command": tool_input}
    if not isinstance(tool_input, dict):
        tool_input = {"value": tool_input}
    tool_input = dict(tool_input)

    canonical = canonical_tool(tool)
    # Os hooks canonicos leem file_path/content; cada host usa um nome diferente para o mesmo dado.
    for source, target in (("filePath", "file_path"), ("path", "file_path"),
                           ("newString", "new_string"), ("file_text", "content"),
                           ("new_str", "new_string"), ("name", "skill")):
        if source in tool_input and target not in tool_input:
            tool_input[target] = tool_input[source]
    if str(tool).lower() == "apply_patch" and "patch" not in tool_input:
        tool_input["patch"] = tool_input.get("command", "")

    cwd = payload.get("cwd") or payload.get("directory") or os.getcwd()
    normalized = {
        "session_id": str(payload.get("session_id") or payload.get("sessionId")
                          or payload.get("sessionID") or ""),
        "cwd": cwd,
        "hook_event_name": EVENTS.get(event, event),
        "tool_name": canonical,
        "tool_input": tool_input,
        "lt_host": host,
    }
    prompt = payload.get("prompt") or payload.get("initialPrompt") or payload.get("text")
    if prompt:
        normalized["prompt"] = prompt
    if "tool_response" in payload or "output" in payload:
        normalized["tool_response"] = payload.get("tool_response", payload.get("output"))
    return normalized


def hook_commands(runtime, event, tool):
    """Comandos do hooks.json canonico cujo matcher casa a ferramenta, na ordem declarada."""
    path = os.path.join(runtime, "hooks", "hooks.json")
    with open(path, "r", encoding="utf-8") as stream:
        config = json.load(stream)
    commands = []
    for group in (config.get("hooks") or {}).get(EVENTS[event], []):
        matcher = group.get("matcher")
        if matcher and event in ("before_tool", "after_tool"):
            if not re.fullmatch(matcher, tool or ""):
                continue
        for hook in group.get("hooks", []):
            if hook.get("type") == "command" and hook.get("command"):
                commands.append((hook["command"], int(hook.get("timeout") or 5)))
    return commands


def decision_from(stdout, returncode):
    """(decisao, razao). A razao importa tanto quanto a decisao: provado no Codex 0.156 que exit 2
    com stderr VAZIO e' registrado como "hook Failed" e a ferramenta EXECUTA — so' exit 2 com a
    razao no stderr vira "Blocked". Hook canonico que nega por JSON no stdout (o formato do Claude)
    deixava o stderr vazio e o segredo passava."""
    if returncode == 2:
        return "deny", ""
    for line in reversed(stdout.splitlines()):
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if not isinstance(data, dict):
            continue
        if data.get("decision") == "block":
            return "deny", str(data.get("reason") or "")
        specific = data.get("hookSpecificOutput") or {}
        decision = specific.get("permissionDecision")
        if decision in ("deny", "ask", "allow"):
            return decision, str(specific.get("permissionDecisionReason") or "")
    return "allow", ""


def context_from(stdout):
    """additionalContext emitido pelos hooks de SessionStart/UserPromptSubmit."""
    parts = []
    for line in stdout.splitlines():
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if isinstance(data, dict):
            value = (data.get("hookSpecificOutput") or {}).get("additionalContext")
            if value:
                parts.append(value)
    return "\n".join(parts)


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("uso: host-dispatch.py <codex|copilot|opencode> <evento>\n")
        return 2
    host, event = sys.argv[1:]
    if host not in HOSTS:
        sys.stderr.write("host invalido: %s\n" % host)
        return 2
    if event not in EVENTS:
        sys.stderr.write("evento invalido: %s (use %s)\n" % (event, ", ".join(sorted(EVENTS))))
        return 2

    runtime = os.path.realpath(os.path.dirname(os.path.abspath(__file__)))
    payload = normalize(host, event, load_payload())
    encoded = json.dumps(payload, ensure_ascii=False)
    # Sem bytecode no runtime: __pycache__ gerado ali vira drift para o verify do reconciler.
    env = dict(os.environ, CLAUDE_PLUGIN_ROOT=runtime, LT_HOST=host, PYTHONDONTWRITEBYTECODE="1")
    env.setdefault("CLAUDE_PROJECT_DIR", payload["cwd"])
    for key, value in WARN_ONLY_DEFAULTS.items():
        env.setdefault(key, value)

    final = "allow"
    messages = []
    contexts = []
    for command, timeout in hook_commands(runtime, event, payload["tool_name"]):
        # O comando fica intacto: `bash -c` expande "${CLAUDE_PLUGIN_ROOT}" do env, com as
        # mesmas aspas do hooks.json — substituir texto quebraria caminho com espaco.
        try:
            result = subprocess.run(
                ["bash", "-c", command], input=encoded, text=True, cwd=payload["cwd"]
                if os.path.isdir(payload["cwd"]) else None,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=max(timeout, 5) * 2,
            )
        except subprocess.TimeoutExpired:
            # Mesma semantica do host Claude: hook que estoura o timeout nao decide nada.
            messages.append("[lt] hook excedeu o timeout e foi ignorado: %s" % command)
            continue
        if result.stderr.strip():
            messages.append(result.stderr.strip())
        context = context_from(result.stdout)
        if context:
            contexts.append(context)
        decision, reason = decision_from(result.stdout, result.returncode)
        if reason and reason not in result.stderr:
            messages.append(reason)
        if decision == "deny":
            final = "deny"
            break
        if decision == "ask":
            # Nenhum dos tres hosts tem pergunta ao usuario disparavel por hook nos modos de uso
            # real (--yolo, --auto, bypass). "ask" que vira "allow" em silencio seria um gate
            # aberto; vira deny com a razao, e a pessoa executa o passo fora do agente.
            final = "deny"
            messages.append("[lt] esta operacao exige confirmacao humana; no %s ela e' bloqueada — "
                            "execute-a manualmente fora do agente." % host)
            break

    if messages:
        # As mensagens canonicas citam comandos pelo namespace do plugin (`lt:lt-approve`). Fora do
        # Claude o comando existe como skill/comando plano (`lt-approve`, `lt-0-setup`): citar o
        # nome que nao existe no host mandaria a pessoa procurar algo que ela nao vai achar.
        text = re.sub(r"\blt:(lt-[a-z0-9-]+)", r"\1", "\n".join(messages))
        text = re.sub(r"\blt:0-setup\b", "lt-0-setup", text)
        sys.stderr.write(text + "\n")
    if final == "deny":
        if not messages:
            sys.stderr.write("[lt] operacao negada pela governanca do harness LT\n")
        return 2
    if contexts and host == "codex" and event in ("session_start", "prompt"):
        sys.stdout.write(json.dumps({"hookSpecificOutput": {
            "hookEventName": EVENTS[event], "additionalContext": "\n".join(contexts)}},
            ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
