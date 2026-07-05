#!/usr/bin/env bash
set -euo pipefail

HermesHome="${HERMES_HOME:-$HOME/.hermes}"
KeepAgyToken=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hermes-home)
      HermesHome="${2:?missing value for --hermes-home}"
      shift 2
      ;;
    --keep-agy-token)
      KeepAgyToken=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./mac/logout-antigravity.sh [--hermes-home PATH] [--keep-agy-token]
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

paths=("$HermesHome/auth/google_antigravity.json")

if [[ "$KeepAgyToken" != "1" ]]; then
  paths+=(
    "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    "$HOME/.gemini/antigravity-cli/oauth-token"
    "$HOME/.gemini/antigravity/antigravity-oauth-token"
    "$HOME/.gemini/antigravity/oauth-token"
  )
fi

for path in "${paths[@]}"; do
  if [[ -e "$path" ]]; then
    rm -f "$path"
    printf '[antigravity] removed %s\n' "$path"
  fi
done

printf '[antigravity] logout cleanup complete\n'
