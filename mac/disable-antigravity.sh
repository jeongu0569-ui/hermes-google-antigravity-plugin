#!/usr/bin/env bash
set -euo pipefail

HermesHome="${HERMES_HOME:-$HOME/.hermes}"
FallbackProvider="nous"
FallbackModel="stepfun/step-3.7-flash:free"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hermes-home)
      HermesHome="${2:?missing value for --hermes-home}"
      shift 2
      ;;
    --fallback-provider)
      FallbackProvider="${2:?missing value for --fallback-provider}"
      shift 2
      ;;
    --fallback-model)
      FallbackModel="${2:?missing value for --fallback-model}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./mac/disable-antigravity.sh [--hermes-home PATH] [--fallback-provider ID] [--fallback-model MODEL]
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

ConfigPath="$HermesHome/config.yaml"
if [[ ! -f "$ConfigPath" ]]; then
  printf 'config.yaml not found: %s\n' "$ConfigPath" >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup="$ConfigPath.pre-disable-antigravity-$timestamp"
cp "$ConfigPath" "$backup"

python3 - "$ConfigPath" "$FallbackProvider" "$FallbackModel" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
fallback_provider = sys.argv[2]
fallback_model = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()

in_model = False
for idx, line in enumerate(lines):
    if line == "model:":
        in_model = True
        continue
    if in_model and line and not line.startswith((" ", "\t")):
        break
    if not in_model:
        continue
    if line.startswith("  default: "):
        lines[idx] = f"  default: {fallback_model}"
    elif line.startswith("  provider: "):
        lines[idx] = f"  provider: {fallback_provider}"
    elif line.startswith("  base_url: "):
        lines[idx] = "  base_url: ''"

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

printf '[antigravity] disabled google-antigravity as the default provider\n'
printf '[antigravity] backup: %s\n' "$backup"
printf '[antigravity] fallback provider: %s\n' "$FallbackProvider"
printf '[antigravity] fallback model: %s\n' "$FallbackModel"
