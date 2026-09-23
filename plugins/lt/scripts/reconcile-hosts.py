#!/usr/bin/env python3
"""Projeta o plugin LT em Codex, Copilot e OpenCode sem criar uma segunda fonte de verdade.

FONTE UNICA
plugins/lt/{skills,agents,commands,hooks} e' o canonico. Este script so' PROJETA: copia o runtime
(hooks, lib, scripts, config) para um diretorio do harness, materializa as skills num lugar que os
tres hosts leem, e escreve em cada host o adaptador nativo que chama os MESMOS hooks canonicos via
lib/host-dispatch.py. Nada aqui tem regra propria; regra nova nasce no plugin e chega aos quatro
hosts por reinstalacao.

DOIS ESCOPOS
- project: dentro de um repositorio (--project). Artefatos versionaveis: AGENTS.md, .agents/skills,
  .codex/, .github/, .opencode/. Runtime em <repo>/.lt-harness/.
- global: no perfil do usuario. Runtime em ~/.lt-harness/; skills em ~/.agents/skills (lido pelos
  tres hosts); adaptadores em $CODEX_HOME, $COPILOT_HOME e $XDG_CONFIG_HOME/opencode.

OS CAMINHOS ABAIXO FORAM PROVADOS EXECUTANDO CADA CLI (docs/host-facts.md, secao multi-host):
- ~/.agents/skills e <repo>/.agents/skills sao lidos por Codex 0.156, Copilot 1.0 e OpenCode 1.18.
- Codex: hooks em <repo>/.codex/hooks.json ou $CODEX_HOME/hooks.json, e CADA hook exige uma
  entrada [hooks.state."<arquivo>:<evento>:<grupo>:<handler>"] trusted_hash no config.toml do
  usuario — sem ela o hook e' pulado EM SILENCIO. O projeto ainda precisa de trust_level.
- Copilot: hooks de repo so' carregam com a pasta em trustedFolders; $COPILOT_HOME/hooks sempre.
- OpenCode: plugin JS em .opencode/plugins ou $XDG_CONFIG_HOME/opencode/plugins, sem trust.

OWNERSHIP
O manifest registra so' o que ESTE script criou. Arquivo que ja existia e nao e' nosso nunca entra
na lista de remocao: a versao anterior varria diretorios inteiros e o uninstall apagava arquivos do
usuario que estavam la antes. Arquivos compartilhados (AGENTS.md, config.toml, hooks.json,
config.json) recebem blocos marcados ou entradas rastreadas e voltam ao estado anterior.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import sys

try:
    import tomllib
except ImportError:  # python < 3.11: a validacao de TOML vira best-effort, nunca silenciosa
    tomllib = None


MARKER_OPEN = "<!-- lt:hosts-generated-start -->"
MARKER_CLOSE = "<!-- lt:hosts-generated-end -->"
TOML_OPEN = "# lt:hosts-generated-start"
TOML_CLOSE = "# lt:hosts-generated-end"
HOSTS = ("codex", "copilot", "opencode")
DISPATCH_SIGNATURE = "host-dispatch.py"
MANIFEST_SCHEMA = 2

# Evento neutro do host-dispatch -> nome do evento em cada host.
CODEX_EVENTS = (
    ("SessionStart", "session_start", "session_start"),
    ("UserPromptSubmit", "user_prompt_submit", "prompt"),
    ("PreToolUse", "pre_tool_use", "before_tool"),
    ("PostToolUse", "post_tool_use", "after_tool"),
    ("Stop", "stop", "stop"),
)
COPILOT_EVENTS = (
    ("sessionStart", "session_start"),
    ("userPromptSubmitted", "prompt"),
    ("preToolUse", "before_tool"),
    ("postToolUse", "after_tool"),
    ("agentStop", "stop"),
)


# --------------------------------------------------------------------------------------------
# utilitarios de arquivo
# --------------------------------------------------------------------------------------------
def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            value.update(chunk)
    return value.hexdigest()


def read(path):
    with open(path, "r", encoding="utf-8") as stream:
        return stream.read()


def write(path, content, executable=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp.lt"
    with open(tmp, "w", encoding="utf-8") as stream:
        stream.write(content)
    os.replace(tmp, path)
    if executable:
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def frontmatter(text):
    """Frontmatter YAML simples (chave: valor em uma linha) — suficiente para name/description."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 4)
    if end < 0:
        return {}, text
    meta = {}
    for line in text[4:end].splitlines():
        match = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if match and match.group(2):
            meta[match.group(1)] = match.group(2).strip().strip('"')
    body = text[end + 4:].lstrip("\n")
    return meta, body


def yaml_scalar(value):
    return json.dumps(value, ensure_ascii=False)


# --------------------------------------------------------------------------------------------
# alvos por escopo
# --------------------------------------------------------------------------------------------
class Targets:
    def __init__(self, scope, project):
        home = os.path.expanduser("~")
        self.scope = scope
        if scope == "project":
            self.base = project
            self.runtime = os.path.join(project, ".lt-harness")
            # Relativo: os tres hosts rodam hooks e comandos com cwd na raiz do projeto, e o
            # caminho relativo mantem os arquivos versionaveis e portaveis entre maquinas.
            self.runtime_ref = ".lt-harness"
            self.skills = os.path.join(project, ".agents", "skills")
            self.codex_dir = os.path.join(project, ".codex")
            self.codex_hooks = os.path.join(self.codex_dir, "hooks.json")
            self.codex_agents = os.path.join(self.codex_dir, "agents")
            self.copilot_hooks = os.path.join(project, ".github", "hooks", "lt-governance.json")
            self.copilot_agents = os.path.join(project, ".github", "agents")
            self.opencode_dir = os.path.join(project, ".opencode")
            self.instructions = {"*": os.path.join(project, "AGENTS.md")}
        else:
            self.base = home
            self.runtime = os.environ.get("LT_RUNTIME_HOME") or os.path.join(home, ".lt-harness")
            self.runtime_ref = self.runtime
            self.skills = os.path.join(home, ".agents", "skills")
            self.codex_dir = os.environ.get("CODEX_HOME") or os.path.join(home, ".codex")
            self.codex_hooks = os.path.join(self.codex_dir, "hooks.json")
            self.codex_agents = os.path.join(self.codex_dir, "agents")
            copilot = os.environ.get("COPILOT_HOME") or os.path.join(home, ".copilot")
            self.copilot_hooks = os.path.join(copilot, "hooks", "lt-governance.json")
            self.copilot_agents = os.path.join(copilot, "agents")
            xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
            self.opencode_dir = os.path.join(xdg, "opencode")
            self.instructions = {
                "codex": os.path.join(self.codex_dir, "AGENTS.md"),
                "copilot": os.path.join(copilot, "copilot-instructions.md"),
                "opencode": os.path.join(self.opencode_dir, "AGENTS.md"),
            }
        self.codex_home = os.environ.get("CODEX_HOME") or os.path.join(home, ".codex")
        self.copilot_home = os.environ.get("COPILOT_HOME") or os.path.join(home, ".copilot")
        self.manifest = os.path.join(self.runtime, "manifest.json")

    def dispatch(self, host, event):
        script = os.path.join(self.runtime_ref, "host-dispatch.py")
        return "python3 %s %s %s" % (shell_quote(script), host, event)


def shell_quote(value):
    if re.match(r"^[A-Za-z0-9_./-]+$", value):
        return value
    return "'" + value.replace("'", "'\\''") + "'"


# --------------------------------------------------------------------------------------------
# conteudo projetado
# --------------------------------------------------------------------------------------------
def names(root, marker):
    if not os.path.isdir(root):
        return []
    return sorted(name for name in os.listdir(root)
                  if os.path.isfile(os.path.join(root, name, marker)))


def command_names(plugin):
    root = os.path.join(plugin, "commands")
    return sorted(name[:-3] for name in os.listdir(root) if name.endswith(".md"))


def agent_names(plugin):
    root = os.path.join(plugin, "agents")
    if not os.path.isdir(root):
        return []
    return sorted(name[:-3] for name in os.listdir(root) if name.endswith(".md"))


def portable_command_name(name):
    return name if name.startswith("lt-") else "lt-" + name


class Renderer:
    """Reescreve referencias especificas do Claude Code para o host neutro."""

    def __init__(self, plugin, targets):
        self.targets = targets
        known = set(names(os.path.join(plugin, "skills"), "SKILL.md"))
        known |= set(agent_names(plugin))
        self.commands = dict((name, portable_command_name(name)) for name in command_names(plugin))
        self.known = known

    def __call__(self, text, skill_dir=None):
        text = text.replace("${CLAUDE_PLUGIN_ROOT}", self.targets.runtime_ref)
        if skill_dir:
            ref = (os.path.relpath(skill_dir, self.targets.base)
                   if self.targets.scope == "project" else skill_dir)
            text = text.replace("${CLAUDE_SKILL_DIR}", ref)

        def swap(match):
            name = match.group(1)
            if name in self.commands:
                return self.commands[name]
            return name if name in self.known else match.group(0)
        # `lt:<skill>` e' o namespace do plugin no Claude; nos outros hosts o nome e' plano.
        return re.sub(r"\blt:([a-z0-9][a-z0-9-]*)", swap, text)


def instructions(targets):
    skills = os.path.relpath(targets.skills, targets.base) if targets.scope == "project" else targets.skills
    return """# Governança LT

As regras e os fluxos SDD canônicos do harness LT estão em `%s/`. Antes de alterar código,
carregue `agent-governance` e a skill do ciclo correspondente (`create-prd`,
`create-technical-specification`, `create-tasks`, `execute-task`, `execute-all-tasks`, `review`,
`bugfix`, `refactor`). Specs pertencem ao repositório atual e ficam em `.specs/` existente ou em
`.lt/specs/`. Nunca marque tarefa como concluída sem evidência física. Porta de entrada: `using-lt`.
""" % skills


def command_skill(plugin, name, render):
    meta, body = frontmatter(read(os.path.join(plugin, "commands", name + ".md")))
    portable = portable_command_name(name)
    description = meta.get("description", "Comando %s do harness LT." % portable)
    hint = meta.get("argument-hint", "")
    note = ("Argumentos aceitos: `%s`. Trate o texto que a pessoa escreveu depois do nome do "
            "comando como `$ARGUMENTS`.\n\n" % hint) if hint else ""
    return ("---\nname: %s\ndescription: %s\n---\n\n# %s\n\n%s%s" %
            (portable, yaml_scalar(description), portable, note, render(body)))


def opencode_command(plugin, name, render):
    meta, body = frontmatter(read(os.path.join(plugin, "commands", name + ".md")))
    description = meta.get("description", "")
    return "---\ndescription: %s\n---\n\n%s" % (yaml_scalar(description), render(body))


def agent_parts(plugin, name, render):
    meta, body = frontmatter(read(os.path.join(plugin, "agents", name + ".md")))
    return meta.get("description", ""), render(body)


def codex_agent(plugin, name, render):
    description, body = agent_parts(plugin, name, render)
    return 'name = %s\ndescription = %s\n\ndeveloper_instructions = """\n%s\n"""\n' % (
        json.dumps(name), json.dumps(description, ensure_ascii=False),
        body.replace('"""', "'''").rstrip())


def copilot_agent(plugin, name, render):
    description, body = agent_parts(plugin, name, render)
    return "---\nname: %s\ndescription: %s\n---\n\n%s" % (name, yaml_scalar(description), body)


def opencode_agent(plugin, name, render):
    description, body = agent_parts(plugin, name, render)
    return "---\ndescription: %s\nmode: subagent\n---\n\n%s" % (yaml_scalar(description), body)


def opencode_plugin(targets):
    script = os.path.join(targets.runtime_ref, "host-dispatch.py")
    return r'''// Gerado por reconcile-hosts.py (harness LT). Nao edite: reinstale a partir do plugin.
// Cada evento do OpenCode vira um evento neutro de host-dispatch.py, que roda os MESMOS hooks
// canonicos do Claude Code. Deny = excecao lancada em tool.execute.before (provado no 1.18).
import { spawnSync } from "node:child_process"
import path from "node:path"

const DISPATCH = %s

function dispatch(directory, event, payload, mayBlock) {
  const script = path.isAbsolute(DISPATCH) ? DISPATCH : path.join(directory, DISPATCH)
  const result = spawnSync("python3", [script, "opencode", event], {
    cwd: directory, input: JSON.stringify({ ...(payload || {}), cwd: directory }),
    encoding: "utf8", timeout: 30000,
  })
  if (mayBlock && result.status !== 0) {
    throw new Error((result.stderr || "governanca LT negou a operacao").trim())
  }
}

function promptText(output) {
  const parts = (output && output.parts) || []
  return parts.filter((part) => part && part.type === "text").map((part) => part.text).join("\n")
}

export const LTHarnessPlugin = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => dispatch(directory, "before_tool", {
    tool: input && input.tool, args: output && output.args, sessionID: input && input.sessionID,
  }, true),
  "tool.execute.after": async (input, output) => dispatch(directory, "after_tool", {
    tool: input && input.tool, args: (output && output.args) || (input && input.args),
    sessionID: input && input.sessionID, output: output && output.output,
  }, false),
  "chat.message": async (input, output) => dispatch(directory, "prompt", {
    prompt: promptText(output), sessionID: input && input.sessionID,
  }, true),
  event: async ({ event }) => {
    if (!event) return
    if (event.type === "session.created") dispatch(directory, "session_start", {}, false)
    if (event.type === "session.idle") dispatch(directory, "stop", {}, false)
  },
})

export default LTHarnessPlugin
''' % json.dumps(script)


# --------------------------------------------------------------------------------------------
# blocos marcados em arquivos compartilhados
# --------------------------------------------------------------------------------------------
def merge_block(path, content, opener, closer, prepend=False):
    current = read(path) if os.path.isfile(path) else ""
    block = opener + "\n" + content.rstrip() + "\n" + closer
    if opener in current and closer in current:
        before = current.split(opener, 1)[0]
        after = current.split(closer, 1)[1]
        result = before + block + after
    elif current and prepend:
        result = block + "\n\n" + current.lstrip()
    elif current:
        result = current.rstrip() + "\n\n" + block + "\n"
    else:
        result = block + "\n"
    write(path, result)


def remove_block(path, opener, closer):
    if not os.path.isfile(path):
        return
    current = read(path)
    if opener not in current or closer not in current:
        return
    before = current.split(opener, 1)[0].rstrip()
    after = current.split(closer, 1)[1].lstrip()
    result = (before + ("\n\n" if before and after else "") + after).strip()
    if result:
        write(path, result + "\n")
    else:
        os.remove(path)


# --------------------------------------------------------------------------------------------
# Codex: hooks.json compartilhavel + trusted_hash
# --------------------------------------------------------------------------------------------
def codex_hook_hash(event_key, command, matcher=None):
    # Espelha o hash do Codex 0.156 (provado reproduzindo hashes existentes): JSON compacto com
    # chaves ordenadas; timeout ausente vale 600 e async ausente vale false no calculo.
    hook = {"type": "command", "command": command, "timeout": 600, "async": False}
    ident = {"event_name": event_key, "hooks": [hook]}
    if matcher is not None:
        ident["matcher"] = matcher
    text = json.dumps(ident, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def is_ours(group):
    return any(DISPATCH_SIGNATURE in str(hook.get("command", "")) for hook in group.get("hooks", []))


def codex_install_hooks(targets):
    """Anexa um grupo por evento ao hooks.json (nosso ou do usuario) e devolve as chaves de trust."""
    path = targets.codex_hooks
    data = {}
    if os.path.isfile(path):
        data = json.loads(read(path) or "{}")
    hooks = data.setdefault("hooks", {})
    trust = []
    for event, key, neutral in CODEX_EVENTS:
        groups = [group for group in hooks.get(event, []) if not is_ours(group)]
        command = targets.dispatch("codex", neutral)
        groups.append({"hooks": [{"type": "command", "command": command}]})
        hooks[event] = groups
        index = len(groups) - 1
        trust.append(("%s:%s:%d:0" % (os.path.realpath(path), key, index),
                      codex_hook_hash(key, command)))
    write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return trust


def codex_remove_hooks(path):
    if not os.path.isfile(path):
        return
    data = json.loads(read(path) or "{}")
    hooks = data.get("hooks") or {}
    for event in list(hooks):
        kept = [group for group in hooks[event] if not is_ours(group)]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if hooks:
        write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    else:
        os.remove(path)


def toml_key(value):
    return json.dumps(value, ensure_ascii=False)


def codex_write_trust(targets, trust, project=None):
    """Registra trust no config.toml do usuario num bloco marcado ANEXADO AO FIM.

    Fim do arquivo porque so' tabelas entram aqui: chave solta depois de uma tabela vira campo
    dela (provado: sandbox_mode depois de [[skills.config]] vira skills.config.0.sandbox_mode e e'
    ignorado em silencio). Entrada que o usuario ja tem fora do bloco nao e' redeclarada: tabela
    duplicada torna o TOML invalido e o Codex inteiro para de carregar a config.
    """
    path = os.path.join(targets.codex_home, "config.toml")
    current = read(path) if os.path.isfile(path) else ""
    outside = current
    if TOML_OPEN in current and TOML_CLOSE in current:
        outside = current.split(TOML_OPEN, 1)[0] + current.split(TOML_CLOSE, 1)[1]
    parsed = {}
    if tomllib is not None and outside.strip():
        parsed = tomllib.loads(outside)
    states = ((parsed.get("hooks") or {}).get("state") or {})
    projects = parsed.get("projects") or {}
    lines = ["# Trust dos hooks do harness LT (reconcile-hosts.py). Removido no uninstall."]
    if project and project not in projects:
        lines += ["[projects.%s]" % toml_key(project), 'trust_level = "trusted"', ""]
    for key, value in trust:
        if key in states:
            if states[key].get("trusted_hash") != value:
                raise RuntimeError("config.toml do Codex ja tem trust divergente para %s; "
                                   "remova a entrada antiga e reinstale" % key)
            continue
        lines += ["[hooks.state.%s]" % toml_key(key), "trusted_hash = %s" % toml_key(value), ""]
    merge_block(path, "\n".join(lines), TOML_OPEN, TOML_CLOSE)
    if tomllib is not None:
        tomllib.loads(read(path))


# --------------------------------------------------------------------------------------------
# Copilot: trustedFolders
# --------------------------------------------------------------------------------------------
def copilot_trust(targets, project):
    path = os.path.join(targets.copilot_home, "config.json")
    data = json.loads(read(path)) if os.path.isfile(path) else {}
    folders = data.setdefault("trustedFolders", [])
    if project in folders:
        return False
    folders.append(project)
    write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return True


def copilot_untrust(targets, project):
    path = os.path.join(targets.copilot_home, "config.json")
    if not os.path.isfile(path):
        return
    data = json.loads(read(path))
    folders = data.get("trustedFolders") or []
    if project in folders:
        folders.remove(project)
        write(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


# --------------------------------------------------------------------------------------------
# install / verify / uninstall
# --------------------------------------------------------------------------------------------
def load_manifest(targets):
    if not os.path.isfile(targets.manifest):
        return None
    return json.loads(read(targets.manifest))


def planned_files(plugin, targets, hosts):
    """Arquivos inteiros que este script possui: (destino, conteudo|None-para-copia, origem)."""
    render = Renderer(plugin, targets)
    plan = []
    for folder in ("config", "hooks", "lib", "scripts"):
        source_root = os.path.join(plugin, folder)
        for root, dirs, files in os.walk(source_root):
            dirs[:] = [name for name in dirs if name != "__pycache__"]
            for name in files:
                if name.endswith((".pyc", ".pyo")):
                    continue
                source = os.path.join(root, name)
                target = os.path.join(targets.runtime, folder, os.path.relpath(source, source_root))
                plan.append((target, None, source))
    plan.append((os.path.join(targets.runtime, "host-dispatch.py"), None,
                 os.path.join(plugin, "lib", "host-dispatch.py")))

    for skill in names(os.path.join(plugin, "skills"), "SKILL.md"):
        source_root = os.path.join(plugin, "skills", skill)
        destination_root = os.path.join(targets.skills, skill)
        for root, dirs, files in os.walk(source_root):
            dirs[:] = [name for name in dirs if name not in ("__pycache__", "evals")]
            for name in files:
                source = os.path.join(root, name)
                target = os.path.join(destination_root, os.path.relpath(source, source_root))
                if name.endswith((".md", ".sh", ".py", ".json", ".yaml", ".yml")):
                    plan.append((target, render(read(source), destination_root), source))
                else:
                    plan.append((target, None, source))
    if "codex" in hosts or "copilot" in hosts:
        # Codex nao tem comando customizado (0.156) e o Copilot nao le .github/prompts: o comando
        # vira skill homonima, que os dois descobrem em .agents/skills.
        for command in command_names(plugin):
            target = os.path.join(targets.skills, portable_command_name(command), "SKILL.md")
            plan.append((target, command_skill(plugin, command, render), None))

    agents = agent_names(plugin)
    if "codex" in hosts:
        for agent in agents:
            plan.append((os.path.join(targets.codex_agents, agent + ".toml"),
                         codex_agent(plugin, agent, render), None))
    if "copilot" in hosts:
        for agent in agents:
            plan.append((os.path.join(targets.copilot_agents, agent + ".agent.md"),
                         copilot_agent(plugin, agent, render), None))
        hooks = {"version": 1, "hooks": dict(
            (event, [{"type": "command", "bash": targets.dispatch("copilot", neutral)}])
            for event, neutral in COPILOT_EVENTS)}
        plan.append((targets.copilot_hooks, json.dumps(hooks, indent=2) + "\n", None))
    if "opencode" in hosts:
        for agent in agents:
            plan.append((os.path.join(targets.opencode_dir, "agents", agent + ".md"),
                         opencode_agent(plugin, agent, render), None))
        for command in command_names(plugin):
            plan.append((os.path.join(targets.opencode_dir, "commands",
                                      portable_command_name(command) + ".md"),
                         opencode_command(plugin, command, render), None))
        plan.append((os.path.join(targets.opencode_dir, "plugins", "lt-governance.js"),
                     opencode_plugin(targets), None))
    return plan


def conflicts_for(plan, previous):
    owned = set((previous or {}).get("files", {}))
    conflicts = []
    for target, _, _ in plan:
        if os.path.lexists(target) and target not in owned:
            conflicts.append(target)
    return conflicts


def install(plugin, targets, hosts, trust):
    previous = load_manifest(targets)
    if os.path.isdir(targets.runtime) and previous is None and os.listdir(targets.runtime):
        raise RuntimeError("%s existe sem manifest; recusei sobrescrever" % targets.runtime)
    plan = planned_files(plugin, targets, hosts)
    conflicts = conflicts_for(plan, previous)
    if conflicts:
        raise RuntimeError("arquivos existentes que nao pertencem ao harness (preserve ou remova "
                           "antes): %s" % ", ".join(conflicts[:10]))
    if previous is not None:
        drift = check(previous)
        if drift:
            raise RuntimeError("drift em arquivos do harness (edite no plugin, nao na copia): %s"
                               % ", ".join(drift[:10]))
        remove(targets, previous, quiet=True)

    files = {}
    for target, content, source in plan:
        if content is None:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(source, target)
        else:
            write(target, content, bool(source) and os.access(source, os.X_OK))
        files[target] = digest(target)

    shared = []
    blocks = []
    for host, path in sorted(targets.instructions.items()):
        if host == "*" or host in hosts:
            merge_block(path, instructions(targets), MARKER_OPEN, MARKER_CLOSE)
            blocks.append(path)
    trusted = {}
    if "codex" in hosts:
        keys = codex_install_hooks(targets)
        shared.append(targets.codex_hooks)
        if targets.scope == "global" or trust:
            codex_write_trust(targets, keys, targets.base if targets.scope == "project" else None)
            trusted["codex"] = os.path.join(targets.codex_home, "config.toml")
    if "copilot" in hosts and targets.scope == "project" and trust:
        if copilot_trust(targets, targets.base):
            trusted["copilot"] = targets.base

    manifest = {
        "schema_version": MANIFEST_SCHEMA, "scope": targets.scope, "base": targets.base,
        "runtime": targets.runtime, "hosts": sorted(hosts), "files": files,
        "blocks": blocks, "codex_hooks": shared, "trust": trusted,
    }
    write(targets.manifest, json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    skills = [path for path in files if path.endswith(os.sep + "SKILL.md")]
    print("hosts reconciliados (%s): %s; skills: %d; arquivos: %d"
          % (targets.scope, ", ".join(sorted(hosts)), len(skills), len(files)))
    if targets.scope == "project" and not trust and ("codex" in hosts or "copilot" in hosts):
        print("aviso: Codex e Copilot so' carregam hooks de repositorio confiavel. Reinstale com "
              "--trust ou confie na pasta pelo proprio CLI; sem isso os hooks sao pulados em silencio.")


def check(manifest):
    drift = []
    for path, expected in sorted(manifest.get("files", {}).items()):
        if not os.path.isfile(path) or digest(path) != expected:
            drift.append(path)
    for path in manifest.get("blocks", []):
        if not os.path.isfile(path) or MARKER_OPEN not in read(path):
            drift.append(path + " (bloco gerado ausente)")
    for path in manifest.get("codex_hooks", []):
        data = json.loads(read(path)) if os.path.isfile(path) else {}
        ours = sum(1 for groups in (data.get("hooks") or {}).values() for group in groups if is_ours(group))
        if ours != len(CODEX_EVENTS):
            drift.append(path + " (grupos do harness: %d de %d)" % (ours, len(CODEX_EVENTS)))
    return drift


def verify(targets):
    manifest = load_manifest(targets)
    if manifest is None:
        raise RuntimeError("manifest multi-host ausente em %s" % targets.manifest)
    drift = check(manifest)
    if drift:
        raise RuntimeError("drift multi-host: %s" % ", ".join(drift[:10]))
    print("multi-host verificado (%s): %d arquivos; hosts: %s"
          % (manifest.get("scope"), len(manifest.get("files", {})), ", ".join(manifest.get("hosts", []))))


def prune_empty(path, stop):
    path = os.path.dirname(path)
    while path.startswith(stop + os.sep) and path != stop:
        try:
            os.rmdir(path)
        except OSError:
            return
        path = os.path.dirname(path)


def remove(targets, manifest, quiet=False):
    drift = []
    for path, expected in sorted(manifest.get("files", {}).items(), reverse=True):
        if not os.path.isfile(path):
            continue
        if digest(path) != expected:
            drift.append(path)
            continue
        os.remove(path)
        prune_empty(path, manifest.get("base") or targets.base)
    if drift:
        raise RuntimeError("recusei remover arquivos alterados: %s" % ", ".join(drift[:10]))
    # Cache de bytecode nasce quando os hooks importam lib/*.py; nao e' arquivo do usuario e
    # impediria o runtime de sair inteiro.
    for root, dirs, _ in os.walk(targets.runtime):
        for name in list(dirs):
            if name == "__pycache__":
                shutil.rmtree(os.path.join(root, name), ignore_errors=True)
    for root, _, _ in sorted(os.walk(targets.runtime), reverse=True):
        try:
            os.rmdir(root)
        except OSError:
            pass
    for path in manifest.get("blocks", []):
        remove_block(path, MARKER_OPEN, MARKER_CLOSE)
    for path in manifest.get("codex_hooks", []):
        codex_remove_hooks(path)
    trust = manifest.get("trust") or {}
    if "codex" in trust:
        remove_block(trust["codex"], TOML_OPEN, TOML_CLOSE)
    if "copilot" in trust:
        copilot_untrust(targets, trust["copilot"])
    if os.path.isfile(targets.manifest):
        os.remove(targets.manifest)
    prune_empty(targets.manifest, os.path.dirname(targets.runtime))
    if not quiet:
        print("adaptadores multi-host removidos (%s)" % manifest.get("scope"))


def uninstall(targets):
    manifest = load_manifest(targets)
    if manifest is None:
        raise RuntimeError("manifest multi-host ausente em %s" % targets.manifest)
    remove(targets, manifest)


def main():
    parser = argparse.ArgumentParser(description="Projeta o harness LT em Codex, Copilot e OpenCode.")
    parser.add_argument("action", choices=("install", "verify", "uninstall"))
    parser.add_argument("--scope", choices=("project", "global"), default="project")
    parser.add_argument("--project", default=".")
    parser.add_argument("--hosts", default=",".join(HOSTS))
    parser.add_argument("--trust", action="store_true",
                        help="escopo project: registra o repo como confiavel no Codex e no Copilot")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    plugin = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    project = os.path.realpath(args.project)
    hosts = set(item.strip() for item in args.hosts.split(",") if item.strip())
    unknown = hosts - set(HOSTS)
    if unknown:
        parser.error("hosts desconhecidos: %s" % ", ".join(sorted(unknown)))
    targets = Targets(args.scope, project)
    try:
        if args.dry_run:
            print("dry-run: %s scope=%s hosts=%s base=%s runtime=%s"
                  % (args.action, args.scope, ",".join(sorted(hosts)), targets.base, targets.runtime))
            if args.action == "install":
                for target, _, _ in planned_files(plugin, targets, hosts):
                    print("  escreveria %s" % target)
            return 0
        if args.action == "install":
            install(plugin, targets, hosts, args.trust)
        elif args.action == "verify":
            verify(targets)
        else:
            uninstall(targets)
    except (OSError, ValueError, RuntimeError) as error:
        sys.stderr.write("erro: %s\n" % error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
