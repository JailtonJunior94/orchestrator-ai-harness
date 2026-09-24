# orchestrator-ai-harness / enterprise / bootstrap-windows.ps1
#
# Instala a politica gerenciada da organizacao nesta maquina (Windows).
#
# CAMINHO: C:\Program Files\ClaudeCode\managed-settings.json
#
# ATENCAO — o caminho legado C:\ProgramData\ClaudeCode\managed-settings.json NAO E' LIDO pelo
# Claude Code. A documentacao oficial e' explicita: "Claude Code doesn't read the legacy Windows
# path". Instalar ali nao da erro e nao faz nada, que e' o pior resultado possivel para uma
# politica de seguranca.

$ErrorActionPreference = "Stop"

$Version = "v0.1.3"
$Repo    = "JailtonJunior94/orchestrator-ai-harness"
$Dest    = "C:\Program Files\ClaudeCode\managed-settings.json"
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Tmp     = [System.IO.Path]::GetTempFileName()

try {
  if ($env:LT_DRYRUN -eq "1") {
    Copy-Item (Join-Path $Here "managed-settings.json") $Tmp -Force
  } else {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh ausente — o repositorio e privado" }
    gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "gh nao autenticado: rode 'gh auth login'" }

    # Confirma a tag antes de baixar, pelo mesmo motivo do bootstrap de macOS.
    gh api "repos/$Repo/git/ref/tags/$Version" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "tag $Version nao existe em $Repo" }

    $b64 = gh api "repos/$Repo/contents/enterprise/managed-settings.json?ref=$Version" --jq '.content'
    [System.IO.File]::WriteAllText($Tmp, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)))
  }

  $json = Get-Content $Tmp -Raw | ConvertFrom-Json
  if ($json.extraKnownMarketplaces.lt.source.ref -ne $Version) {
    throw "o pin do arquivo nao e $Version"
  }

  if ($env:LT_DRYRUN -eq "1") {
    Write-Host "[dry-run] payload validado; copia e verify pulados"
    exit 0
  }

  $isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "rode este script como Administrador" }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
  Copy-Item $Tmp $Dest -Force
  Write-Host "politica instalada em $Dest"

  Write-Host ""
  Write-Host "ATENCAO: enabledPlugins no managed-settings NAO materializa o cache do plugin."
  Write-Host "Rode agora:  claude plugin install lt@lt"
} finally {
  Remove-Item $Tmp -ErrorAction SilentlyContinue
}
