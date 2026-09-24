#!/usr/bin/env bash
# orchestrator-ai-harness / enterprise / uninstall.sh
#
# Remove a politica gerenciada desta maquina. NAO toca no plugin, no cache, nem nos dados de
# ninguem — so no arquivo de politica. Desinstalar a politica e' decisao de administrador;
# desinstalar o harness e' `scripts/uninstall.sh`.

set -euo pipefail
case "$(uname -s)" in
  Darwin) DEST="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  Linux)  DEST="/etc/claude-code/managed-settings.json" ;;
  *) printf 'SO nao suportado: %s\n' "$(uname -s)" >&2; exit 2 ;;
esac

[ -f "$DEST" ] || { printf 'nada a remover: %s nao existe\n' "$DEST"; exit 0; }

printf 'Remover a politica gerenciada em:\n  %s\n\nProsseguir? [y/N] ' "$DEST"
read -r a
case "$a" in [yY]*) ;; *) printf 'cancelado.\n'; exit 0 ;; esac

BACKUP="${TMPDIR:-/tmp}/managed-settings.json.bak.$(date -u +%Y%m%dT%H%M%SZ)"
sudo cp "$DEST" "$BACKUP" && printf 'backup: %s\n' "$BACKUP"
sudo rm -f "$DEST"
# A politica do Codex sai junto, mas so' se for a NOSSA (marcador no cabecalho): um requirements.toml
# da propria maquina ou de outra ferramenta nao e' apagado.
CODEX_REQ="/etc/codex/requirements.toml"
if [ -f "$CODEX_REQ" ] && grep -q 'Politica gerenciada do Codex CLI da Lima Teixeira' "$CODEX_REQ"; then
  sudo cp "$CODEX_REQ" "$BACKUP.codex-requirements.toml" && sudo rm -f "$CODEX_REQ"
  printf 'politica do Codex removida (backup: %s)\n' "$BACKUP.codex-requirements.toml"
fi
printf 'politica removida. O plugin e os dados locais nao foram tocados.\n'
