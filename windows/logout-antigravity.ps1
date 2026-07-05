param(
    [string]$HermesHome = $(Join-Path $env:LOCALAPPDATA "hermes"),
    [switch]$KeepAgyToken
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$paths = @(
    (Join-Path $HermesHome "auth\google_antigravity.json")
)

if (-not $KeepAgyToken) {
    $paths += @(
        (Join-Path $env:USERPROFILE ".gemini\antigravity-cli\antigravity-oauth-token"),
        (Join-Path $env:USERPROFILE ".gemini\antigravity-cli\oauth-token"),
        (Join-Path $env:USERPROFILE ".gemini\antigravity\antigravity-oauth-token"),
        (Join-Path $env:USERPROFILE ".gemini\antigravity\oauth-token")
    )
}

foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Host "[antigravity] removed $path"
    }
}

Write-Host "[antigravity] logout cleanup complete"
