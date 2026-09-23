# orchestrator-ai-harness / enterprise / uninstall.ps1
#
# Espelho de enterprise/uninstall.sh para Windows.
#
# Remove a politica gerenciada desta maquina. NAO toca no plugin, no cache, nem nos dados de
# ninguem — so no arquivo de politica. Desinstalar a politica e' decisao de administrador;
# desinstalar o harness e' `scripts/uninstall.sh`.
#
# CAMINHO: C:\Program Files\ClaudeCode\managed-settings.json — o mesmo que bootstrap-windows.ps1
# instala. O caminho legado C:\ProgramData\ClaudeCode\ NAO e' lido pelo Claude Code; se houver
# arquivo la', ele e' so' reportado: remove-lo nao muda politica nenhuma, e apagar o que este
# harness nao instalou nao e' papel deste script.
#
# Confirmacao padrao NAO, como no espelho em shell: remover politica de seguranca por um Enter
# distraido e' o pior default possivel.

$ErrorActionPreference = "Stop"

$Dest   = "C:\Program Files\ClaudeCode\managed-settings.json"
$Legacy = "C:\ProgramData\ClaudeCode\managed-settings.json"

if (Test-Path $Legacy) {
  Write-Host "aviso: existe arquivo no caminho legado $Legacy, que o Claude Code NAO le. Nao foi tocado."
}

if (-not (Test-Path $Dest)) {
  Write-Host "nada a remover: $Dest nao existe"
  exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "rode este script como Administrador" }

Write-Host "Remover a politica gerenciada em:"
Write-Host "  $Dest"
Write-Host ""
$answer = Read-Host "Prosseguir? [y/N]"
if ($answer -notmatch '^[yY]') {
  Write-Host "cancelado."
  exit 0
}

# Backup antes de remover, com carimbo UTC: rollback de politica tem de ser uma copia de volta,
# nao uma reconstrucao de memoria.
$Stamp  = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$Backup = Join-Path $env:TEMP "managed-settings.json.bak.$Stamp"
Copy-Item $Dest $Backup -Force
Write-Host "backup: $Backup"

Remove-Item $Dest -Force
Write-Host "politica removida. O plugin e os dados locais nao foram tocados."
