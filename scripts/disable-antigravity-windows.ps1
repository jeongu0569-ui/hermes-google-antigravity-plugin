param(
    [string]$HermesHome = $(Join-Path $env:LOCALAPPDATA "hermes"),
    [string]$FallbackProvider = "nous",
    [string]$FallbackModel = "stepfun/step-3.7-flash:free"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ConfigPath = Join-Path $HermesHome "config.yaml"
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "config.yaml not found: $ConfigPath"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = "$ConfigPath.pre-disable-antigravity-$timestamp"
Copy-Item -LiteralPath $ConfigPath -Destination $backup

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$lines = [System.Collections.Generic.List[string]]::new()
$rawText = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
$rawLines = $rawText -split "`r?`n"
foreach ($line in $rawLines) {
    $lines.Add($line)
}

$inModel = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq "model:") {
        $inModel = $true
        continue
    }
    if ($inModel -and $lines[$i] -match "^\S") {
        break
    }
    if (-not $inModel) {
        continue
    }
    if ($lines[$i] -match "^  default: ") {
        $lines[$i] = "  default: $FallbackModel"
    } elseif ($lines[$i] -match "^  provider: ") {
        $lines[$i] = "  provider: $FallbackProvider"
    } elseif ($lines[$i] -match "^  base_url: ") {
        $lines[$i] = "  base_url: ''"
    }
}

[System.IO.File]::WriteAllText($ConfigPath, ($lines -join "`n"), $utf8NoBom)

Write-Host "[antigravity] disabled google-antigravity as the default provider"
Write-Host "[antigravity] backup: $backup"
Write-Host "[antigravity] fallback provider: $FallbackProvider"
Write-Host "[antigravity] fallback model: $FallbackModel"
