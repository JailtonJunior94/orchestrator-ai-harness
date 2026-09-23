#!/usr/bin/env python3
"""Gate de paridade entre os quatro hosts e gerador de docs/capability-matrix.md.

Paridade aqui e' verificada pela PROJECAO REAL: o reconciler roda num projeto e num HOME
temporarios e o gate confere, no disco, que toda skill, agent, comando e evento de hook canonico
chegou a cada host. Conferir a lista de nomes no codigo do reconciler provaria so' a intencao.
"""
import json
import os
import subprocess
import sys
import tempfile

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PLUGIN = os.path.join(REPO, "plugins", "lt")
MATRIX = os.path.join(REPO, "docs", "capability-matrix.md")
NEUTRAL_EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop")


def canonical():
    skills = sorted(d for d in os.listdir(os.path.join(PLUGIN, "skills"))
                    if os.path.isfile(os.path.join(PLUGIN, "skills", d, "SKILL.md")))
    agents = sorted(f[:-3] for f in os.listdir(os.path.join(PLUGIN, "agents")) if f.endswith(".md"))
    commands = sorted(f[:-3] for f in os.listdir(os.path.join(PLUGIN, "commands")) if f.endswith(".md"))
    hooks = json.load(open(os.path.join(PLUGIN, "hooks", "hooks.json")))["hooks"]
    return skills, agents, commands, hooks


def portable(command):
    return command if command.startswith("lt-") else "lt-" + command


def project_rows(skills, agents, commands, hooks):
    tmp = tempfile.mkdtemp()
    project = os.path.join(tmp, "p")
    os.makedirs(project)
    env = dict(os.environ, HOME=os.path.join(tmp, "h"), CODEX_HOME=os.path.join(tmp, "h", ".codex"),
               COPILOT_HOME=os.path.join(tmp, "h", ".copilot"),
               XDG_CONFIG_HOME=os.path.join(tmp, "h", ".config"))
    subprocess.run([sys.executable, os.path.join(PLUGIN, "scripts", "reconcile-hosts.py"), "install",
                    "--project", project, "--hosts", "codex,copilot,opencode"],
                   check=True, stdout=subprocess.DEVNULL, env=env)
    exists = lambda *parts: os.path.isfile(os.path.join(project, *parts))
    rows, missing = [], []

    def row(kind, name, claude, codex, copilot, opencode):
        cells = {"Claude Code": claude, "Codex": codex, "Copilot": copilot, "OpenCode": opencode}
        for host, value in cells.items():
            if not value:
                missing.append("%s %s sem projecao no %s" % (kind, name, host))
        rows.append((kind, name, cells))

    for skill in skills:
        skill_ok = exists(".agents", "skills", skill, "SKILL.md")
        row("skill", skill, "`lt:%s`" % skill, skill_ok and "`.agents/skills`",
            skill_ok and "`.agents/skills`", skill_ok and "`.agents/skills`")
    for agent in agents:
        row("agent", agent, "`lt:%s`" % agent,
            exists(".codex", "agents", agent + ".toml") and "`.codex/agents`",
            exists(".github", "agents", agent + ".agent.md") and "`.github/agents`",
            exists(".opencode", "agents", agent + ".md") and "`.opencode/agents`")
    for command in commands:
        name = portable(command)
        as_skill = exists(".agents", "skills", name, "SKILL.md")
        row("comando", command, "`/lt:%s`" % command, as_skill and "skill `%s`" % name,
            as_skill and "skill `%s`" % name,
            exists(".opencode", "commands", name + ".md") and "comando `%s`" % name)
    codex_hooks = json.load(open(os.path.join(project, ".codex", "hooks.json")))["hooks"]
    copilot_hooks = json.load(open(os.path.join(project, ".github", "hooks", "lt-governance.json")))["hooks"]
    plugin_js = open(os.path.join(project, ".opencode", "plugins", "lt-governance.js")).read()
    copilot_names = {"SessionStart": "sessionStart", "UserPromptSubmit": "userPromptSubmitted",
                     "PreToolUse": "preToolUse", "PostToolUse": "postToolUse", "Stop": "agentStop"}
    opencode_names = {"SessionStart": "session.created", "UserPromptSubmit": "chat.message",
                      "PreToolUse": "tool.execute.before", "PostToolUse": "tool.execute.after",
                      "Stop": "session.idle"}
    for event in sorted(hooks):
        scripts = sorted(set(h["command"].split("/")[-1].rstrip('"') for g in hooks[event] for h in g["hooks"]))
        label = "%s (%s)" % (event, ", ".join(scripts))
        if event not in NEUTRAL_EVENTS:
            rows.append(("hook", label, {"Claude Code": "nativo", "Codex": "n/a — evento nao emitido",
                                         "Copilot": "n/a — evento nao emitido",
                                         "OpenCode": "n/a — evento nao emitido"}))
            continue
        row("hook", label, "nativo",
            event in codex_hooks and "`%s`" % event,
            copilot_names[event] in copilot_hooks and "`%s`" % copilot_names[event],
            opencode_names[event] in plugin_js and "`%s`" % opencode_names[event])
    return rows, missing


def render(rows):
    lines = [
        "# Matriz de capacidades por host",
        "",
        "<!-- gerado por scripts/check-host-parity.sh --write; nao edite a mao -->",
        "",
        "Fonte única: `plugins/lt/{skills,agents,commands,hooks}`. Claude Code recebe o plugin; Codex,",
        "Copilot e OpenCode recebem a projeção de `plugins/lt/scripts/reconcile-hosts.py` (escopo",
        "`project` mostrado abaixo; o escopo `global` usa `~/.agents/skills`, `$CODEX_HOME`,",
        "`$COPILOT_HOME` e `$XDG_CONFIG_HOME/opencode`). Hooks dos outros hosts executam os MESMOS scripts",
        "canônicos via `lib/host-dispatch.py`. Evidência de execução real: `docs/host-facts.md`.",
        "",
        "| Tipo | Componente | Claude Code | Codex | Copilot | OpenCode |",
        "|---|---|---|---|---|---|",
    ]
    for kind, name, cells in rows:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (kind, name, cells["Claude Code"], cells["Codex"],
                                                         cells["Copilot"], cells["OpenCode"]))
    return "\n".join(lines) + "\n"


def main():
    rows, missing = project_rows(*canonical())
    text = render(rows)
    if missing:
        sys.stderr.write("PARIDADE QUEBRADA:\n" + "".join("  - %s\n" % m for m in missing))
        return 1
    if "--write" in sys.argv:
        open(MATRIX, "w").write(text)
        print("docs/capability-matrix.md regenerado (%d linhas)" % len(rows))
        return 0
    current = open(MATRIX).read() if os.path.isfile(MATRIX) else ""
    if current != text:
        sys.stderr.write("docs/capability-matrix.md desatualizado: rode bash scripts/check-host-parity.sh --write\n")
        return 1
    print("PARIDADE OK: %d componentes projetados nos 4 hosts" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
