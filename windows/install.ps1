param(
    [string]$HermesHome = $(Join-Path $env:LOCALAPPDATA "hermes"),
    [switch]$Check,
    [switch]$Login,
    [switch]$Smoke
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "[antigravity] $Message"
}

function Require-File {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Name not found: $Path"
    }
}

function Copy-One {
    param([string]$From, [string]$To)
    Require-File -Path $From -Name "source file"
    $dir = Split-Path -Parent $To
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -Force -LiteralPath $From -Destination $To
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CommonRoot = Join-Path $RepoRoot "common"
$AgentDir = Join-Path $HermesHome "hermes-agent"
$VenvCandidates = @(
    (Join-Path $AgentDir "venv"),
    (Join-Path $AgentDir ".venv")
)
$VenvDir = $VenvCandidates | Where-Object { Test-Path (Join-Path $_ "Scripts\python.exe") } | Select-Object -First 1
if (-not $VenvDir) {
    throw "Hermes Python venv not found under $AgentDir. Install Hermes first."
}

$Python = Join-Path $VenvDir "Scripts\python.exe"
$HermesExe = Join-Path $VenvDir "Scripts\hermes.exe"

Require-File -Path $Python -Name "Hermes Python"
Require-File -Path $HermesExe -Name "Hermes CLI"
Require-File -Path (Join-Path $CommonRoot "patches\antigravity_provider_patch.py") -Name "Antigravity patch"
Require-File -Path (Join-Path $CommonRoot "sitecustomize_hook.py") -Name "sitecustomize hook"

$AgentRuntimeFiles = @(
    "gemini_cloudcode_adapter.py",
    "google_code_assist.py",
    "google_oauth.py",
    "google_antigravity_adapter.py",
    "google_antigravity_oauth.py",
    "antigravity_quota_grpc.py",
    "antigravity_quota_report.py",
    "antigravity_stream_grpc.py"
)

$ProviderFiles = @(
    "__init__.py",
    "plugin.yaml"
)

foreach ($file in $AgentRuntimeFiles) {
    Require-File -Path (Join-Path $CommonRoot "agent\$file") -Name "Antigravity runtime source"
}
foreach ($file in $ProviderFiles) {
    Require-File -Path (Join-Path $CommonRoot "plugins\model-providers\google-antigravity\$file") -Name "Provider metadata source"
}

$env:HERMES_HOME = $HermesHome
$env:HERMES_PATCHES_DIR = Join-Path $HermesHome "patches"

if ($Check) {
    Write-Step "checking installed provider registration"
    & $Python -c "import hermes_cli.auth as a; print('provider_registered=', 'google-antigravity' in a.PROVIDER_REGISTRY); print('has_resolver=', hasattr(a, 'resolve_antigravity_oauth_runtime_credentials'))"
    & $Python -c "import hermes_cli.providers as p; print('overlay_registered=', 'google-antigravity' in p.HERMES_OVERLAYS); print('label=', p.get_label('google-antigravity'))"
    & $Python -c "import agent.gemini_cloudcode_adapter, agent.google_code_assist, agent.google_antigravity_adapter; print('runtime_imports_ok=', True)"
    $cache = Join-Path $HermesHome "auth\google_antigravity_client.json"
    if (Test-Path -LiteralPath $cache) {
        & $Python -c "import json, pathlib; p=pathlib.Path(r'$cache'); d=json.loads(p.read_text()); print({'client_cache_exists': True, 'extractor_version': d.get('extractor_version'), 'has_client_id': bool(d.get('client_id')), 'secret_len': len(d.get('client_secret',''))})"
    } else {
        Write-Host "{'client_cache_exists': False}"
    }
    exit 0
}

Write-Step "HermesHome: $HermesHome"
Write-Step "AgentDir:   $AgentDir"
Write-Step "VenvDir:    $VenvDir"

Write-Step "copying provider metadata"
foreach ($file in $ProviderFiles) {
    Copy-One (Join-Path $CommonRoot "plugins\model-providers\google-antigravity\$file") `
             (Join-Path $HermesHome "plugins\model-providers\google-antigravity\$file")
}

Write-Step "copying Antigravity runtime files into Hermes checkout"
foreach ($file in $AgentRuntimeFiles) {
    Copy-One (Join-Path $CommonRoot "agent\$file") (Join-Path $AgentDir "agent\$file")
}

Write-Step "copying runtime patch outside the Hermes checkout"
Copy-One (Join-Path $CommonRoot "patches\antigravity_provider_patch.py") `
         (Join-Path $HermesHome "patches\antigravity_provider_patch.py")

Write-Step "installing sitecustomize hook"
$hookSource = Get-Content -Raw -LiteralPath (Join-Path $CommonRoot "sitecustomize_hook.py")
$escapedHermesHome = $HermesHome.Replace("\", "\\")
$oldBlock = @'
_PATCHES_DIR = os.environ.get(
    "HERMES_PATCHES_DIR",
    os.path.expanduser("~/.hermes/patches"),
)
'@
$newBlock = @"
_PATCHES_DIR = os.environ.get(
    "HERMES_PATCHES_DIR",
    os.path.join(
        os.environ.get("HERMES_HOME", r"$escapedHermesHome"),
        "patches",
    ),
)
"@
$hookText = $hookSource.Replace($oldBlock, $newBlock)

$sitecustomizeTargets = @(
    (Join-Path $VenvDir "sitecustomize.py"),
    (Join-Path $VenvDir "Lib\site-packages\sitecustomize.py")
)
foreach ($target in $sitecustomizeTargets) {
    Write-Utf8NoBom -Path $target -Text $hookText
}

Write-Step "priming Antigravity OAuth client cache from agy without printing secrets"
$primeScript = @'
import json
import os
import re
import shutil
from pathlib import Path

EXTRACTOR_VERSION = 4
home = Path(os.environ["HERMES_HOME"])
cache = home / "auth" / "google_antigravity_client.json"
cache.parent.mkdir(parents=True, exist_ok=True)

env_id = os.environ.get("HERMES_ANTIGRAVITY_CLIENT_ID", "").strip()
env_secret = os.environ.get("HERMES_ANTIGRAVITY_CLIENT_SECRET", "").strip()

if env_id and env_secret:
    payload = {
        "client_id": env_id,
        "client_secret": env_secret,
        "extractor_version": EXTRACTOR_VERSION,
        "source": "env",
    }
else:
    agy = shutil.which("agy")
    if not agy:
        print("[warn] agy not found on PATH; OAuth client cache was not updated")
        raise SystemExit(0)
    text = Path(agy).read_bytes().decode("latin1", errors="ignore")
    id_matches = list(re.finditer(r"(\d+-[\w]+\.apps\.googleusercontent\.com)", text))
    secret_matches = list(re.finditer(r"(GOCSPX-[A-Za-z0-9_-]{28})", text))
    if not id_matches or not secret_matches:
        print("[warn] OAuth client id/secret not found inside agy; cache was not updated")
        raise SystemExit(0)
    target = next(
        (match for match in id_matches if match.group(1).startswith("1071006060591")),
        id_matches[0],
    )
    secret_clusters = []
    for match in secret_matches:
        if (
            not secret_clusters
            or match.start() - secret_clusters[-1][-1].start()
            > len(secret_clusters[-1][-1].group(1))
        ):
            secret_clusters.append([match])
        else:
            secret_clusters[-1].append(match)
    nearest_cluster = min(
        secret_clusters,
        key=lambda cluster: min(abs(match.start() - target.start()) for match in cluster),
    )
    st = Path(agy).stat()
    payload = {
        "client_id": target.group(1),
        "client_secret": nearest_cluster[0].group(1),
        "extractor_version": EXTRACTOR_VERSION,
        "source": "windows agy cluster cache",
        "source_agy_path": agy,
        "source_agy_size": st.st_size,
        "source_agy_mtime_ns": st.st_mtime_ns,
    }

tmp = cache.with_suffix(".tmp")
tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
os.replace(tmp, cache)
print(json.dumps({
    "cache": str(cache),
    "client_id_prefix": payload["client_id"][:12],
    "secret_len": len(payload["client_secret"]),
    "extractor_version": payload["extractor_version"],
}, ensure_ascii=False))
'@
$tmpPrime = Join-Path $env:TEMP ("hermes-antigravity-prime-{0}.py" -f ([guid]::NewGuid().ToString("N")))
try {
    Set-Content -LiteralPath $tmpPrime -Value $primeScript -Encoding UTF8
    & $Python $tmpPrime
} finally {
    Remove-Item -LiteralPath $tmpPrime -Force -ErrorAction SilentlyContinue
}

Write-Step "verifying provider registration"
& $Python -c "import hermes_cli.auth as a; print('provider_registered=', 'google-antigravity' in a.PROVIDER_REGISTRY); print('has_resolver=', hasattr(a, 'resolve_antigravity_oauth_runtime_credentials'))"
& $Python -c "import hermes_cli.providers as p; print('overlay_registered=', 'google-antigravity' in p.HERMES_OVERLAYS); print('label=', p.get_label('google-antigravity'))"
& $Python -c "import hermes_cli.auth_commands as ac; print('oauth_capable=', 'google-antigravity' in getattr(ac, '_OAUTH_CAPABLE_PROVIDERS', set())); print('auth_add_patched=', getattr(ac, '_antigravity_auth_add_patched', False))"
& $Python -c "import agent.gemini_cloudcode_adapter, agent.google_code_assist, agent.google_antigravity_adapter; print('runtime_imports_ok=', True)"

if ($Login) {
    Write-Step "starting Google Antigravity OAuth login"
    & $HermesExe auth add google-antigravity
}

if ($Smoke) {
    Write-Step "running smoke request"
    & $HermesExe chat --provider google-antigravity -m gemini-3.5-flash-high -q "OK"
}

Write-Step "done"
Write-Host ""
Write-Host "Next:"
Write-Host "  hermes auth add google-antigravity"
Write-Host "  hermes model"
Write-Host "  hermes chat --provider google-antigravity -m gemini-3.5-flash-high -q `"OK`""
