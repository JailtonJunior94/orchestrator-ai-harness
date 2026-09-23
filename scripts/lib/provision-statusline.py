#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / provision-statusline.py
#
# Provisiona a statusline do harness.
#
# FATO DO HOST: PLUGIN NENHUM ENTREGA A BARRA PRINCIPAL.
# `statusLine` nao e' campo de plugin.json (o validate reporta como ignorado) e pelo
# settings.json de um plugin so passam `agent` e `subagentStatusLine`. Quem entrega e' o
# instalador, escrevendo em ~/.claude/settings.json — com consentimento proprio.
#
# CAMINHO ESTAVEL, NAO O CACHE VERSIONADO.
# O shim vai para ~/.claude/lt/statusline-shim.sh. O cache (~/.claude/plugins/cache/lt/lt/<ver>/)
# e' podado quando a versao muda; um comando apontando para la' quebraria a barra a cada update.
#
# NUNCA SOBRESCREVE STATUSLINE DE TERCEIRO.
# is_ours() reconhece exatamente duas formas: a estavel e a legada (dentro do cache). Qualquer
# outra coisa devolve `skipped-foreign` e o arquivo de quem usa fica intacto.
#
# Saida: UMA linha JSON com action em
#   installed | updated | unchanged | skipped-foreign | dry-run

import argparse
import json
import os
import shutil
import sys

STABLE_SUBPATH = os.path.join("lt", "statusline-shim.sh")


def claude_config_dir():
    """Perfil de configuracao do Claude Code em uso.

    Esta maquina pode ter varios perfis (~/.claude, ~/.claude-work, ~/.claude-alt),
    selecionados por CLAUDE_CONFIG_DIR. Instalar no perfil errado significa que o harness
    simplesmente nao aparece na sessao de quem o instalou — e o sintoma ("instalei e nao
    apareceu nada") nao aponta para a causa.
    """
    value = os.environ.get("CLAUDE_CONFIG_DIR")
    if value:
        return os.path.realpath(os.path.expanduser(value))
    return os.path.join(os.path.expanduser("~"), ".claude")


def load_json(path, default):
    if not os.path.isfile(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as fh:
            content = fh.read().strip()
            return json.loads(content) if content else default
    except (IOError, OSError, ValueError):
        return default


def is_ours(command):
    """Reconhece a forma estavel e a legada. Nada mais."""
    if not isinstance(command, str):
        return False
    return ("/lt/statusline-shim.sh" in command
            or ("/plugins/cache/lt/lt/" in command and "statusline" in command))


def out(action, **extra):
    payload = {"action": action}
    payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cfg = claude_config_dir()
    settings_path = os.path.join(cfg, "settings.json")
    stable = os.path.join(cfg, STABLE_SUBPATH)
    source = os.path.join(args.repo, "plugins", "lt", "statusline", "statusline-shim.sh")

    if not os.path.isfile(source):
        return out("error", reason="shim nao encontrado em %s" % source)

    settings = load_json(settings_path, {})
    existing = (settings.get("statusLine") or {}).get("command")

    if existing and not is_ours(existing):
        # Caminho principal nesta frota, nao excecao: muita gente ja tem barra propria.
        return out(
            "skipped-foreign",
            reason="statusLine de terceiro detectada; nada foi alterado",
            existing=existing,
            hint="Para compor as duas barras: /lt:lt-doctor --statusline",
        )

    # Caminho ABSOLUTO no comando: $HOME nao resolveria para o perfil certo quando o
    # usuario roda com CLAUDE_CONFIG_DIR apontando para outro diretorio.
    desired = 'bash "%s"' % stable.replace(os.sep, "/")

    if args.dry_run:
        action = "unchanged" if existing == desired else ("updated" if existing else "installed")
        return out("dry-run", would=action, command=desired)

    os.makedirs(os.path.dirname(stable), exist_ok=True)
    changed_file = True
    if os.path.isfile(stable):
        with open(source, "rb") as a, open(stable, "rb") as b:
            changed_file = a.read() != b.read()
    if changed_file:
        shutil.copy2(source, stable)
        os.chmod(stable, 0o755)

    if existing == desired and not changed_file:
        return out("unchanged", command=desired)

    action = "updated" if existing else "installed"
    settings.setdefault("statusLine", {})
    settings["statusLine"] = {"type": "command", "command": desired}

    if os.path.exists(settings_path):
        shutil.copy2(settings_path, settings_path + ".bak.statusline")
    tmp = settings_path + ".tmp.statusline"
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(settings, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, settings_path)

    return out(action, command=desired, shim=stable)


if __name__ == "__main__":
    sys.exit(main())
