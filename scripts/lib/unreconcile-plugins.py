#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / unreconcile-plugins.py
#
# Inverso de reconcile-plugins.py. Desfaz os TRES alvos, na ordem inversa da instalacao:
#
#   1. settings ~/.claude/settings.json                             (enabledPlugins[<p>@<mkt>])
#      + a statusLine, SO se for nossa
#   2. registry ~/.claude/plugins/installed_plugins.json            (entradas de <p>@<mkt>)
#   3. cache    ~/.claude/plugins/cache/<mkt>/<plugin>/             (salvo --keep-cache)
#
# POR QUE UM SCRIPT, E NAO UM HEREDOC NO uninstall.sh
# O removedor tinha o proprio Python inline, com tres defeitos que o reconciliador ja nao tinha:
# escrevia os dois JSON sempre (mesmo sem mudanca, trocando o backup), nao era atomico, e
# reconhecia a statusline pelo caminho fixo "/.claude/lt/..." — que nao casa quando o perfil vem
# de CLAUDE_CONFIG_DIR, deixando a barra apontando para um shim de plugin removido. Aqui as
# primitivas sao as mesmas do reconciliador: safe_segment, confine, escrita atomica com backup,
# e escrita SO do que mudou.
#
# REGRA DE OURO, a mesma do reconciliador: preservar o que nao e' nosso.
#   - remove a CHAVE de enabledPlugins, nao grava false: false mentiria na proxima instalacao,
#     que veria "conhecido, desabilitado" em vez de "nunca instalado";
#   - statusLine de terceiro fica intacta (is_ours identico ao de provision-statusline.py);
#   - dados de trabalho (~/.claude/lt/ com audit e telemetria, os .lt/ dos projetos) NUNCA sao
#     tocados. So' o shim da statusline sai de ~/.claude/lt/, e so' quando a barra era nossa.
#
# Saida: uma linha JSON por alvo, como o reconciliador.

import argparse
import json
import os
import re
import shutil
import sys

SEGMENT_INVALID = re.compile(r"^$|^\.{1,2}$|[/\\\x00]")
SHIM_SUBPATH = os.path.join("lt", "statusline-shim.sh")


def claude_config_dir():
    """Perfil do Claude Code em uso (CLAUDE_CONFIG_DIR ou ~/.claude)."""
    value = os.environ.get("CLAUDE_CONFIG_DIR")
    if value:
        return os.path.realpath(os.path.expanduser(value))
    return os.path.join(os.path.expanduser("~"), ".claude")


def die(msg, code=1):
    sys.stderr.write("[unreconcile] %s\n" % msg)
    raise SystemExit(code)


def safe_segment(value, what):
    """Rejeita nome que possa escapar do diretorio (CWE-22/23). Um rmtree com `..` no nome
    apagaria fora de ~/.claude — esta funcao e' a barreira."""
    if not isinstance(value, str) or SEGMENT_INVALID.search(value):
        die("%s invalido: %r" % (what, value), 2)
    return value


def confine(base, *segments):
    base_real = os.path.realpath(base)
    target = os.path.realpath(os.path.join(base_real, *segments))
    if os.path.commonpath([base_real, target]) != base_real or target == base_real:
        die("caminho escaparia de %s: %s" % (base_real, target), 2)
    return target


def load_json(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            content = fh.read().strip()
            return json.loads(content) if content else {}
    except (IOError, OSError, ValueError) as exc:
        # JSON ilegivel NAO e' "nada a remover": reescreve-lo seria destruir a config de alguem.
        die("JSON ilegivel em %s: %s — nada foi alterado" % (path, exc))


def backup_and_write(path, data):
    shutil.copy2(path, path + ".bak.uninstall")
    tmp = path + ".tmp.uninstall"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def is_ours(command):
    """Mesmo reconhecimento de provision-statusline.py: forma estavel e forma legada."""
    if not isinstance(command, str):
        return False
    return ("/lt/statusline-shim.sh" in command
            or ("/plugins/cache/lt/lt/" in command and "statusline" in command))


def main():
    parser = argparse.ArgumentParser(description="Desfaz cache, registry e settings do plugin.")
    parser.add_argument("--marketplace", required=True)
    parser.add_argument("--plugins", required=True, help="lista separada por virgula")
    parser.add_argument("--keep-cache", action="store_true")
    parser.add_argument("--keep-statusline", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    mkt = safe_segment(args.marketplace, "marketplace")
    plugins = [safe_segment(p.strip(), "plugin") for p in args.plugins.split(",") if p.strip()]
    if not plugins:
        die("--plugins vazio", 2)

    cfg = claude_config_dir()
    settings_path = os.path.join(cfg, "settings.json")
    registry_path = os.path.join(cfg, "plugins", "installed_plugins.json")
    cache_root = os.path.join(cfg, "plugins", "cache")
    results = []

    # --- alvo 1: settings ---
    settings = load_json(settings_path)
    if settings is None:
        results.append({"target": "settings", "action": "settings-absent"})
    else:
        before = json.dumps(settings, sort_keys=True)
        enabled = settings.get("enabledPlugins")
        for plugin in plugins:
            key = "%s@%s" % (plugin, mkt)
            if isinstance(enabled, dict) and key in enabled:
                enabled.pop(key)
                results.append({"target": "settings", "action": "disabled", "key": key})
            else:
                results.append({"target": "settings", "action": "already-absent", "key": key})

        command = (settings.get("statusLine") or {}).get("command") if isinstance(settings.get("statusLine"), dict) else None
        if args.keep_statusline:
            results.append({"target": "statusline", "action": "statusline-kept"})
        elif not command:
            results.append({"target": "statusline", "action": "statusline-absent"})
        elif is_ours(command):
            settings.pop("statusLine", None)
            results.append({"target": "statusline", "action": "statusline-removed", "command": command})
        else:
            results.append({"target": "statusline", "action": "statusline-foreign", "command": command})

        if json.dumps(settings, sort_keys=True) != before and not args.dry_run:
            backup_and_write(settings_path, settings)

    removed_ours = any(r.get("action") == "statusline-removed" for r in results)
    shim = os.path.join(cfg, SHIM_SUBPATH)
    if removed_ours and os.path.isfile(shim) and not args.dry_run:
        os.remove(shim)

    # --- alvo 2: registry ---
    registry = load_json(registry_path)
    if registry is None:
        results.append({"target": "registry", "action": "registry-absent"})
    else:
        before = json.dumps(registry, sort_keys=True)
        table = registry.get("plugins") if isinstance(registry.get("plugins"), dict) else {}
        for plugin in plugins:
            key = "%s@%s" % (plugin, mkt)
            if key in table:
                scopes = [e.get("scope", "?") for e in table.pop(key) or [] if isinstance(e, dict)]
                results.append({"target": "registry", "action": "unregistered", "key": key, "scopes": scopes})
            else:
                results.append({"target": "registry", "action": "already-absent", "key": key})
        if json.dumps(registry, sort_keys=True) != before and not args.dry_run:
            backup_and_write(registry_path, registry)

    # --- alvo 3: cache ---
    for plugin in plugins:
        if args.keep_cache:
            results.append({"target": "cache", "action": "cache-kept", "plugin": plugin})
            continue
        if not os.path.isdir(os.path.join(cache_root, mkt, plugin)):
            results.append({"target": "cache", "action": "cache-absent", "plugin": plugin})
            continue
        dest = confine(cache_root, mkt, plugin)
        if not args.dry_run:
            shutil.rmtree(dest)
        results.append({"target": "cache", "action": "cache-removed", "path": dest})
    mkt_dir = os.path.join(cache_root, mkt)
    if not args.keep_cache and not args.dry_run and os.path.isdir(mkt_dir) and not os.listdir(mkt_dir):
        os.rmdir(confine(cache_root, mkt))

    for row in results:
        if args.dry_run:
            row["dry_run"] = True
        print(json.dumps(row, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
