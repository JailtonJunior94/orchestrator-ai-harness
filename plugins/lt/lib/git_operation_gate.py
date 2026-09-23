#!/usr/bin/env python3
# lt / lib / git_operation_gate.py
#
# Classifica operacoes git que publicam ou reescrevem historia de BRANCH PROTEGIDA.
#
# DIVISAO DE TRABALHO COM O GUARDA DESTRUTIVO (destructive_guard.py) — decidida para nao haver
# duas regras para o mesmo comando:
#   - destrutivo cobre o que APAGA trabalho: `reset --hard`, `clean`, `checkout -- .`,
#     `branch -D` (contidos por snapshot) e `push --force` (aprovacao `destructive`);
#   - este gate cobre o que PUBLICA ou REESCREVE a historia compartilhada numa branch protegida:
#     `commit` direto nela, `push` para ela e as formas de force que o destrutivo nao casa
#     (`--force-with-lease`, `-f`, refspec `+ref`).
# `push --force` para branch protegida passa pelos dois: o destrutivo exige aprovacao, este nega.
# Nao ha conflito — negar e' mais restritivo, e forcar historia de `main` nao e' rotina de
# ninguem, nem com aprovacao de cinco minutos.
#
# POR QUE `ask` E NAO `deny` NO COMMIT/PUSH SIMPLES: o harness nao commita (R-GOV-001), mas a
# pessoa pode pedir. `ask` devolve a decisao ao humano; `deny` ensinaria o agente a contornar.
#
# Saida: JSON no stdout, exit 0 sempre. O hook decide.

import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys

DEFAULT_PROTECTED = "main master trunk develop production release/* hotfix/*"
WRAPPERS = {"env", "command", "exec", "time", "nohup", "nice", "sudo", "doas", "timeout", "stdbuf"}
GIT_VALUE_FLAGS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PUNCT = set("();<>|&")


def out(decision, reason=""):
    print(json.dumps({"decision": decision, "reason": reason}, ensure_ascii=False))
    return 0


def tokenize(text):
    lexer = shlex.shlex(re.sub(r"\\\r?\n", " ", text), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    return list(lexer)


def segments(tokens):
    current = []
    for token in tokens:
        if token and all(c in PUNCT for c in token):
            if current:
                yield current
            current = []
            continue
        current.append(token)
    if current:
        yield current


def git_invocations(text, depth=0):
    """Cada `git ...` que o shell vai EXECUTAR, com os argumentos apos `git`."""
    found = []
    for seg in segments(tokenize(text)):
        idx = 0
        while idx < len(seg) and ASSIGNMENT.match(seg[idx]):
            idx += 1
        while idx < len(seg) and os.path.basename(seg[idx]) in WRAPPERS:
            idx += 1
            while idx < len(seg) and (seg[idx].startswith("-") or ASSIGNMENT.match(seg[idx])):
                idx += 1
        if idx >= len(seg):
            continue
        head = os.path.basename(seg[idx])
        if head == "git":
            found.append(seg[idx + 1:])
        elif head in SHELLS and "-c" in seg[idx:] and depth < 2:
            pos = seg.index("-c", idx)
            if pos + 1 < len(seg):
                found.extend(git_invocations(seg[pos + 1], depth + 1))
    return found


def split_subcommand(args):
    idx = 0
    while idx < len(args):
        token = args[idx]
        if token in GIT_VALUE_FLAGS:
            idx += 2
            continue
        if token.startswith("-"):
            idx += 1
            continue
        return token, args[idx + 1:]
    return None, []


def protected(branch, patterns):
    return any(fnmatch.fnmatch(branch, p) for p in patterns)


def current_branch(cwd):
    try:
        proc = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None
    name = proc.stdout.decode("utf-8", "replace").strip()
    return name if proc.returncode == 0 and name and name != "HEAD" else None


def push_targets(rest, branch):
    """Branches de destino de um `git push` e se ha force."""
    force = False
    positional = []
    for token in rest:
        if token in ("--force", "-f", "--force-with-lease", "--force-if-includes") or \
                token.startswith("--force-with-lease="):
            force = True
        elif token.startswith("-"):
            if re.match(r"^-[a-zA-Z]*f[a-zA-Z]*$", token):
                force = True
            continue
        else:
            positional.append(token)
    refspecs = positional[1:]
    if not refspecs:
        return ([branch] if branch else []), force
    targets = []
    for spec in refspecs:
        if spec.startswith("+"):
            force = True
            spec = spec[1:]
        dst = spec.split(":", 1)[-1]
        dst = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
        if dst in ("HEAD", "") and branch:
            dst = branch
        targets.append(dst)
    return targets, force


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, TypeError):
        return out("allow", "payload ilegivel")
    tool_input = payload.get("tool_input") if isinstance(payload, dict) else None
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or "git" not in command:
        return out("allow")
    command = command[:100000]
    raw = os.environ.get("LT_PROTECTED_BRANCHES") or DEFAULT_PROTECTED
    patterns = [p for p in re.split(r"[\s,]+", raw) if p]
    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    try:
        invocations = git_invocations(command)
    except ValueError:
        # Aspas desbalanceadas: o shell tambem recusaria. Nada a classificar.
        return out("allow", "comando nao tokenizavel")
    branch = None
    for args in invocations:
        sub, rest = split_subcommand(args)
        if sub not in ("commit", "push"):
            continue
        if branch is None:
            branch = current_branch(cwd) or ""
        if sub == "commit":
            if "--dry-run" in rest or not branch or not protected(branch, patterns):
                continue
            return out("ask", "git commit direto na branch protegida '%s'. O harness nao commita "
                              "(R-GOV-001); confirme que a pessoa pediu este commit, ou trabalhe "
                              "numa branch <tipo>/<slug>." % branch)
        targets, force = push_targets(rest, branch)
        hit = [t for t in targets if protected(t, patterns)]
        if not hit:
            continue
        if force:
            return out("deny", "push forcado para branch protegida (%s) reescreve historia "
                               "compartilhada. Negado sempre; abra PR ou peca a quem administra "
                               "o repositorio." % ", ".join(hit))
        return out("ask", "git push para branch protegida (%s). Publicar e' decisao humana; "
                          "confirme que foi pedido." % ", ".join(hit))
    return out("allow")


if __name__ == "__main__":
    sys.exit(main())
