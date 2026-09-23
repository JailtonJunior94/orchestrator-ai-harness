#!/usr/bin/env python3
# lt / lib / destructive_guard.py
#
# Classificacao, contencao e snapshot de comando destrutivo — tudo em UMA invocacao.
#
# O MODELO
#   Um comando destrutivo dentro de uma arvore git, cujo alvo esta contido nessa arvore, e'
#   REVERSIVEL: tiramos um snapshot em refs/lt/wip/ e liberamos. O trabalho da pessoa nao se
#   perde e o fluxo nao trava.
#   Fora disso (alvo fora da arvore, caminho absoluto de sistema, arvore nao versionada) exige
#   aprovacao `destructive` fresca no approve.log.
#
# POR QUE ASSIM, E NAO "bloqueia tudo"
#   Um guarda que bloqueia `rm -rf node_modules` dentro do proprio repo e' desligado na primeira
#   semana, e junto com ele vai a protecao contra `rm -rf ~`. Conter o que e' reversivel e' o que
#   compra credibilidade para bloquear o que nao e'.
#
# Saida: JSON no stdout, exit 0 sempre. O hook decide.

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shell_text  # noqa: E402

# Cada entrada: (regex, rotulo, reversivel_se_contido)
# reversivel_se_contido=False => nem dentro de git isto e' liberado (formata disco, sobrescreve
# dispositivo, apaga historico do shell).
DESTRUCTIVE = [
    (r"\brm\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*[rR][a-zA-Z]*f|\brm\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*f[a-zA-Z]*[rR]", "rm recursivo forcado", True),
    (r"\brm\s+-[a-zA-Z]*r\b", "rm recursivo", True),
    (r"\bgit\s+reset\s+--hard\b", "git reset --hard", True),
    (r"\bgit\s+clean\s+-[a-zA-Z]*[dfx]", "git clean", True),
    (r"\bgit\s+checkout\s+--\s+\.", "git checkout -- .", True),
    (r"\bgit\s+push\s+.*--force(?!-with-lease)", "git push --force", False),
    (r"\bgit\s+branch\s+-D\b", "git branch -D", True),
    (r"\bmkfs(\.[a-z0-9]+)?\b", "formatacao de filesystem", False),
    (r"\bdd\s+if=.*\bof=/dev/", "dd para dispositivo", False),
    (r"\bhistory\s+-c\b", "limpeza de historico do shell", False),
    (r">\s*/dev/(sd|nvme|disk)", "escrita direta em dispositivo", False),
    (r"\btruncate\s+-s\s*0\b", "truncate para zero", True),
    (r"\bshred\b", "shred", False),
    (r"\bdrop\s+database\b", "DROP DATABASE", False),
    (r"\btruncate\s+table\b", "TRUNCATE TABLE", False),
    (r"\bkubectl\s+delete\s+(namespace|ns)\b", "kubectl delete namespace", False),
    (r"\bterraform\s+destroy\b", "terraform destroy", False),
    (r"\bdoctl\s+compute\s+droplet\s+delete\b", "delete de Droplet", False),
]

# Alvos que nunca sao "contidos", por mais que o cwd seja um repo git.
CATASTROPHIC_TARGETS = [
    r"\s/(\s|$)", r"\s/\*", r"\s~(\s|/|$)", r"\s\$HOME(\s|/|$)",
    r"\s/etc\b", r"\s/usr\b", r"\s/var\b", r"\s/bin\b", r"\s/System\b",
    r"\s/Library\b", r"\s/Users(\s|$)", r"\s\.\.(\s|/|$)",
]


def run(args, cwd=None):
    try:
        proc = subprocess.run(
            args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        return proc.returncode, proc.stdout.decode("utf-8", "replace").strip()
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def git_root(cwd):
    code, out = run(["git", "rev-parse", "--show-toplevel"], cwd=cwd)
    return out if code == 0 and out else None


def classify(command):
    for regex, label, reversible in DESTRUCTIVE:
        if re.search(regex, command, re.IGNORECASE):
            return label, reversible
    return None, None


def is_catastrophic(command):
    for regex in CATASTROPHIC_TARGETS:
        if re.search(regex, command):
            return True
    return False


def snapshot(root):
    """Snapshot do estado atual em refs/lt/wip/<epoch>.

    Usa uma ref propria em vez de stash: stash mexe no working tree e pode conflitar com o que a
    pessoa esta fazendo. Uma ref so aponta para um commit; nada no working tree muda.
    """
    code, _ = run(["git", "rev-parse", "--verify", "HEAD"], cwd=root)
    if code != 0:
        return None, "repositorio sem commit inicial"
    code, tree = run(["git", "stash", "create"], cwd=root)
    if code != 0:
        return None, "git stash create falhou"
    if not tree:
        return "clean", None
    import time

    ref = "refs/lt/wip/%d" % int(time.time())
    code, _ = run(["git", "update-ref", ref, tree], cwd=root)
    if code != 0:
        return None, "git update-ref falhou"
    return ref, None


def out(decision, reason, **extra):
    payload = {"decision": decision, "reason": reason}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except (ValueError, TypeError):
        payload = {}

    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        tool_input = {}
    command = tool_input.get("command") or ""
    if not command:
        return out("allow", "sem comando")

    # Cap antes de qualquer regex, pelo mesmo motivo do hook: ReDoS.
    command = command[:100000]

    # Classifica SO o que o shell vai executar. Sem esta separacao, `grep -n "rm -rf /" x.md`
    # era tratado como se fosse `rm -rf /` — e o guarda chegou a bloquear a propria sessao que
    # escrevia o teste dele. Ver lib/shell_text.py para a regra e seus limites.
    executed = shell_text.executable_text(command)

    label, reversible = classify(executed)
    if not label:
        return out("allow", "nao destrutivo")

    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if is_catastrophic(executed):
        return out(
            "block",
            "'%s' com alvo fora de qualquer arvore de trabalho. Esta classe nao e' reversivel "
            "por snapshot e nao e' liberada por aprovacao de rotina." % label,
            label=label,
            klass="catastrophic",
        )

    if not reversible:
        if_approved = "destructive"
        return out(
            "needs_approval",
            "'%s' e' irreversivel. Requer aprovacao `destructive` nos ultimos 300s: "
            "`lt:lt-approve destructive \"<motivo>\"`." % label,
            label=label,
            klass="irreversible",
            required_token=if_approved,
        )

    root = git_root(cwd)
    if not root:
        return out(
            "needs_approval",
            "'%s' fora de arvore git — sem snapshot possivel, nada seria recuperavel. "
            "Requer aprovacao `destructive`." % label,
            label=label,
            klass="untracked_tree",
            required_token="destructive",
        )

    ref, err = snapshot(root)
    if err:
        return out(
            "needs_approval",
            "'%s' dentro de arvore git, mas o snapshot falhou (%s). Sem rede de seguranca, "
            "requer aprovacao `destructive`." % (label, err),
            label=label,
            klass="snapshot_failed",
            required_token="destructive",
        )

    return out(
        "allow",
        "'%s' contido na arvore git e reversivel. Snapshot: %s" % (label, ref),
        label=label,
        klass="contained",
        snapshot=ref,
        root=root,
    )


if __name__ == "__main__":
    sys.exit(main())
