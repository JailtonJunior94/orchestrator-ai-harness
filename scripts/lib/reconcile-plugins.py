#!/usr/bin/env python3
# orchestrator-ai-harness / scripts / lib / reconcile-plugins.py
#
# Reconciliador de instalacao. Garante os TRES alvos, nesta ordem:
#
#   1. cache    ~/.claude/plugins/cache/<mkt>/<plugin>/<versao>/   (copia da arvore do repo)
#   2. registry ~/.claude/plugins/installed_plugins.json            (entrada com scope)
#   3. settings ~/.claude/settings.json                             (enabledPlugins[<p>@<mkt>])
#
# POR QUE NAO CONFIAR EM `claude plugin install`
# O comando do host consolida os tres alvos por conta propria, mas o estado final nao e'
# verificavel de fora e ja se viu divergir (cache presente, registry apontando para versao
# antiga, enabled em outro escopo). O instalador deste harness e' DETERMINISTICO e IDEMPOTENTE:
# escreve os tres, depois VALIDA os tres. Rodar duas vezes devolve "unchanged".
#
# REGRA DE OURO DESTE ARQUIVO: preservar o que nao e' nosso.
# O ~/.claude/settings.json de quem usa tem statusline propria, hooks proprios, plugins de
# terceiros e preferencias de modelo. Carregamos o JSON inteiro, mutamos UMA chave e gravamos de
# volta. Nunca reescrevemos o arquivo a partir de um template.

import argparse
import json
import os
import re
import shutil
import sys

SEGMENT_INVALID = re.compile(r"^$|^\.{1,2}$|[/\\\x00]")


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


def die(msg, code=1):
    sys.stderr.write("[reconcile] %s\n" % msg)
    raise SystemExit(code)


def safe_segment(value, what):
    """Rejeita nome que possa escapar do diretorio (CWE-22/23).

    `lt` e `0.1.0` passam; `../..` ou `a/b` morrem antes de tocar o disco. Esta funcao e' a
    unica barreira entre um argumento de linha de comando e um rm/copy fora de ~/.claude.
    """
    if not isinstance(value, str) or SEGMENT_INVALID.search(value):
        die("%s invalido: %r" % (what, value), 2)
    return value


def confine(base, *segments):
    """Resolve base/segments garantindo que o resultado permanece DENTRO de base."""
    base_real = os.path.realpath(base)
    target = os.path.realpath(os.path.join(base_real, *segments))
    if os.path.commonpath([base_real, target]) != base_real:
        die("caminho escaparia de %s: %s" % (base_real, target), 2)
    return target


def backup_and_write(path, data):
    """Escrita atomica com backup. os.replace e' atomico no mesmo filesystem."""
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak.reconcile")
    tmp = path + ".tmp.reconcile"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)


def load_json(path, default):
    if not os.path.isfile(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as fh:
            content = fh.read().strip()
            return json.loads(content) if content else default
    except (IOError, OSError, ValueError) as exc:
        die("JSON ilegivel em %s: %s" % (path, exc))


def dir_signature(path):
    """(numero de arquivos, maior mtime). Barato e suficiente para decidir se o cache mudou,
    sem hashear a arvore inteira a cada instalacao."""
    count, newest = 0, 0.0
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in (".in_use", "__pycache__", ".git")]
        for name in files:
            if name.endswith(".pyc"):
                continue
            count += 1
            try:
                newest = max(newest, os.path.getmtime(os.path.join(root, name)))
            except OSError:
                pass
    return count, round(newest, 3)


def chmod_hooks(dest):
    """Restaura o bit +x em hooks e scripts.

    O git nao preserva o bit executavel quando o host baixa o marketplace como zip/tarball.
    Sem isto o hook existe, e' referenciado corretamente no hooks.json e simplesmente nao roda
    na primeira sessao — falha silenciosa e dificil de diagnosticar.
    """
    fixed = 0
    for sub in ("hooks", "scripts", "scripts/cycle", "lib", "statusline", "statusline/segments"):
        folder = os.path.join(dest, sub)
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            if os.path.isfile(path) and (name.endswith(".sh") or name.endswith(".py")):
                mode = os.stat(path).st_mode
                if not mode & 0o111:
                    os.chmod(path, mode | 0o755)
                    fixed += 1
    return fixed


def copy_tree(src, dest):
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(
        src, dest,
        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".git", ".in_use"),
    )


def heal_scopes(registry, key, install_path):
    """Remove entradas de QUALQUER escopo cujo installPath sumiu ou aponta para outra versao.

    Sem isto, um `--scope project` antigo de outro checkout sequestra o carregamento: o host
    resolve por registro, nao pelo que o usuario acha que instalou.
    """
    healed = []
    entries = registry.get("plugins", {}).get(key, [])
    kept = []
    for entry in entries:
        path = entry.get("installPath", "")
        if path == install_path:
            continue
        if not path or not os.path.exists(path):
            healed.append("%s (installPath inexistente)" % entry.get("scope", "?"))
            continue
        kept.append(entry)
    registry.setdefault("plugins", {})[key] = kept
    return healed


def main():
    parser = argparse.ArgumentParser(description="Reconcilia cache, registry e settings do plugin.")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--marketplace", required=True)
    parser.add_argument("--plugins", required=True, help="lista separada por virgula")
    parser.add_argument("--scope", default="user")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force-refresh", action="store_true")
    args = parser.parse_args()

    mkt = safe_segment(args.marketplace, "marketplace")
    repo = os.path.realpath(args.repo)
    if not os.path.isdir(repo):
        die("repo nao encontrado: %s" % repo)

    claude_home = claude_config_dir()
    cache_root = os.path.join(claude_home, "plugins", "cache")
    registry_path = os.path.join(claude_home, "plugins", "installed_plugins.json")
    settings_path = os.path.join(claude_home, "settings.json")

    manifest = load_json(os.path.join(repo, ".claude-plugin", "marketplace.json"), None)
    if not manifest:
        die("marketplace.json nao encontrado em %s" % repo)
    versions = dict((p["name"], p["version"]) for p in manifest.get("plugins", []))

    results = []
    registry = load_json(registry_path, {"version": 2, "plugins": {}})
    settings = load_json(settings_path, {})
    # Estado de partida serializado, para escrever SO' o que mudou. Reescrever os dois arquivos a
    # cada rodada fazia a segunda execucao relatar "registered" e trocar o backup, e ninguem
    # distinguia uma instalacao nova de uma reexecucao sem efeito.
    before = (json.dumps(registry, sort_keys=True), json.dumps(settings, sort_keys=True))

    for name in [p.strip() for p in args.plugins.split(",") if p.strip()]:
        plugin = safe_segment(name, "plugin")
        if plugin not in versions:
            die("plugin '%s' nao esta no manifesto (%s)" % (plugin, ", ".join(sorted(versions))))
        version = safe_segment(versions[plugin], "version")

        src = os.path.join(repo, "plugins", plugin)
        if not os.path.isdir(src):
            die("arvore do plugin nao encontrada: %s" % src)

        dest = confine(cache_root, mkt, plugin, version)

        # --- alvo 1: cache ---
        if not os.path.isdir(dest):
            action = "cache-created"
        elif args.force_refresh:
            action = "cache-forced"
        elif dir_signature(src) != dir_signature(dest):
            action = "cache-refresh"
        else:
            action = "cache-ok"

        if not args.dry_run and action != "cache-ok":
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            copy_tree(src, dest)
        fixed = 0 if args.dry_run else chmod_hooks(dest)
        results.append({"target": "cache", "action": action, "path": dest, "chmod_fixed": fixed})

        # --- alvo 2: registry ---
        key = "%s@%s" % (plugin, mkt)
        previous = json.dumps(registry.get("plugins", {}).get(key, []), sort_keys=True)
        healed = heal_scopes(registry, key, dest)
        entry = {"scope": args.scope, "installPath": dest, "version": version,
                 "marketplace": mkt, "name": plugin}
        registry.setdefault("plugins", {}).setdefault(key, []).append(entry)
        same = json.dumps(registry["plugins"][key], sort_keys=True) == previous
        results.append({"target": "registry", "action": "registry-ok" if same else "registered",
                        "key": key, "scope": args.scope, "healed": healed})

        # --- alvo 3: settings ---
        # Muta UMA chave. Tudo o mais no arquivo de quem usa sobrevive intacto.
        enabled = settings.setdefault("enabledPlugins", {})
        already = enabled.get(key) is True
        enabled[key] = True
        results.append({"target": "settings", "action": "already-enabled" if already else "enabled",
                        "key": key})

    if not args.dry_run:
        os.makedirs(os.path.dirname(registry_path), exist_ok=True)
        if json.dumps(registry, sort_keys=True) != before[0]:
            backup_and_write(registry_path, registry)
        if json.dumps(settings, sort_keys=True) != before[1]:
            backup_and_write(settings_path, settings)

    for row in results:
        print(json.dumps(row, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
