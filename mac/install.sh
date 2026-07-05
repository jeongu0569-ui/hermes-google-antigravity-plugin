#!/usr/bin/env bash
set -euo pipefail

HermesHome="${HERMES_HOME:-$HOME/.hermes}"
Check=0
Login=0
Smoke=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hermes-home)
      HermesHome="${2:?missing value for --hermes-home}"
      shift 2
      ;;
    --check)
      Check=1
      shift
      ;;
    --login)
      Login=1
      shift
      ;;
    --smoke)
      Smoke=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./mac/install.sh [--hermes-home PATH] [--check] [--login] [--smoke]

Options:
  --hermes-home PATH  Hermes home directory. Defaults to ~/.hermes.
  --check             Check installed Antigravity provider registration.
  --login             Run `hermes auth add google-antigravity` after install.
  --smoke             Run a one-shot smoke chat after install.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

step() {
  printf '[antigravity] %s\n' "$1"
}

require_file() {
  local path="$1"
  local name="$2"
  if [[ ! -e "$path" ]]; then
    printf '%s not found: %s\n' "$name" "$path" >&2
    exit 1
  fi
}

copy_one() {
  local from="$1"
  local to="$2"
  require_file "$from" "source file"
  mkdir -p "$(dirname "$to")"
  cp -f "$from" "$to"
}

ScriptDir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RepoRoot="$(cd -- "$ScriptDir/.." && pwd)"
CommonRoot="$RepoRoot/common"
AgentDir="$HermesHome/hermes-agent"

VenvDir=""
for candidate in "$AgentDir/venv" "$AgentDir/.venv"; do
  if [[ -x "$candidate/bin/python" ]]; then
    VenvDir="$candidate"
    break
  fi
done

if [[ -z "$VenvDir" ]]; then
  printf 'Hermes Python venv not found under %s. Install Hermes first.\n' "$AgentDir" >&2
  exit 1
fi

Python="$VenvDir/bin/python"
HermesExe="$VenvDir/bin/hermes"

require_file "$Python" "Hermes Python"
require_file "$HermesExe" "Hermes CLI"
require_file "$CommonRoot/patches/antigravity_provider_patch.py" "Antigravity patch"
require_file "$CommonRoot/sitecustomize_hook.py" "sitecustomize hook"

AgentRuntimeFiles=(
  gemini_cloudcode_adapter.py
  google_code_assist.py
  google_oauth.py
  google_antigravity_adapter.py
  google_antigravity_oauth.py
  antigravity_quota_grpc.py
  antigravity_quota_report.py
  antigravity_stream_grpc.py
)

ProviderFiles=(
  __init__.py
  plugin.yaml
)

for file in "${AgentRuntimeFiles[@]}"; do
  require_file "$CommonRoot/agent/$file" "Antigravity runtime source"
done
for file in "${ProviderFiles[@]}"; do
  require_file "$CommonRoot/plugins/model-providers/google-antigravity/$file" "Provider metadata source"
done

export HERMES_HOME="$HermesHome"
export HERMES_PATCHES_DIR="$HermesHome/patches"

if [[ "$Check" == "1" ]]; then
  step "checking installed provider registration"
  "$Python" -c "import hermes_cli.auth as a; print('provider_registered=', 'google-antigravity' in a.PROVIDER_REGISTRY); print('has_resolver=', hasattr(a, 'resolve_antigravity_oauth_runtime_credentials'))"
  "$Python" -c "import hermes_cli.providers as p; print('overlay_registered=', 'google-antigravity' in p.HERMES_OVERLAYS); print('label=', p.get_label('google-antigravity'))"
  "$Python" -c "import agent.gemini_cloudcode_adapter, agent.google_code_assist, agent.google_antigravity_adapter; print('runtime_imports_ok=', True)"
  Cache="$HermesHome/auth/google_antigravity_client.json"
  if [[ -f "$Cache" ]]; then
    "$Python" -c "import json, pathlib; p=pathlib.Path('$Cache'); d=json.loads(p.read_text()); print({'client_cache_exists': True, 'extractor_version': d.get('extractor_version'), 'has_client_id': bool(d.get('client_id')), 'secret_len': len(d.get('client_secret',''))})"
  else
    printf "{'client_cache_exists': False}\n"
  fi
  exit 0
fi

step "HermesHome: $HermesHome"
step "AgentDir:   $AgentDir"
step "VenvDir:    $VenvDir"

step "copying provider metadata"
for file in "${ProviderFiles[@]}"; do
  copy_one "$CommonRoot/plugins/model-providers/google-antigravity/$file" \
           "$HermesHome/plugins/model-providers/google-antigravity/$file"
done

step "copying Antigravity runtime files into Hermes checkout"
for file in "${AgentRuntimeFiles[@]}"; do
  copy_one "$CommonRoot/agent/$file" "$AgentDir/agent/$file"
done

step "copying runtime patch outside the Hermes checkout"
copy_one "$CommonRoot/patches/antigravity_provider_patch.py" \
         "$HermesHome/patches/antigravity_provider_patch.py"

step "installing macOS sitecustomize hook"
"$Python" - "$CommonRoot/sitecustomize_hook.py" "$HermesHome" "$VenvDir" <<'PY'
import os
import site
import sys
from pathlib import Path

source = Path(sys.argv[1])
hermes_home = sys.argv[2]
venv_dir = Path(sys.argv[3])
text = source.read_text(encoding="utf-8")
old = '''_PATCHES_DIR = os.environ.get(
    "HERMES_PATCHES_DIR",
    os.path.expanduser("~/.hermes/patches"),
)
'''
new = f'''_PATCHES_DIR = os.environ.get(
    "HERMES_PATCHES_DIR",
    os.path.join(
        os.environ.get("HERMES_HOME", {hermes_home!r}),
        "patches",
    ),
)
'''
text = text.replace(old, new)
targets = [venv_dir / "sitecustomize.py"]
for path in site.getsitepackages():
    targets.append(Path(path) / "sitecustomize.py")
for target in targets:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
PY

step "priming Antigravity OAuth client cache from agy without printing secrets"
"$Python" - <<'PY'
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
        "source": "macos agy cluster cache",
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
PY

step "verifying provider registration"
"$Python" -c "import hermes_cli.auth as a; print('provider_registered=', 'google-antigravity' in a.PROVIDER_REGISTRY); print('has_resolver=', hasattr(a, 'resolve_antigravity_oauth_runtime_credentials'))"
"$Python" -c "import hermes_cli.providers as p; print('overlay_registered=', 'google-antigravity' in p.HERMES_OVERLAYS); print('label=', p.get_label('google-antigravity'))"
"$Python" -c "import hermes_cli.auth_commands as ac; print('oauth_capable=', 'google-antigravity' in getattr(ac, '_OAUTH_CAPABLE_PROVIDERS', set())); print('auth_add_patched=', getattr(ac, '_antigravity_auth_add_patched', False))"
"$Python" -c "import agent.gemini_cloudcode_adapter, agent.google_code_assist, agent.google_antigravity_adapter; print('runtime_imports_ok=', True)"

if [[ "$Login" == "1" ]]; then
  step "starting Google Antigravity OAuth login"
  "$HermesExe" auth add google-antigravity
fi

if [[ "$Smoke" == "1" ]]; then
  step "running smoke request"
  "$HermesExe" chat --provider google-antigravity -m gemini-3.5-flash-high -q "OK"
fi

step "done"
printf '\nNext:\n'
printf '  hermes auth add google-antigravity\n'
printf '  hermes model\n'
printf '  hermes chat --provider google-antigravity -m gemini-3.5-flash-high -q "OK"\n'
