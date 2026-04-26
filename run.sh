#!/usr/bin/env bash
set -euo pipefail

# Build (if missing) and run the a11y-mocha suite against a chosen env.
# Each env maps to a different browserstack-node-sdk branch baked into its own image,
# so switching envs never touches your host node_modules.
#
# Uses Colima's bundled nerdctl (containerd runtime) — no docker install required.
#
# Usage:
#   ./run.sh <env> [--rebuild] [-- <extra args passed to npm test>]
#
# Envs (mirrors setup.sh):
#   rengg       → ai-a11y-one-day      (default)
#   regression  → a11y-sdk-regression
#   preprod     → a11y-sdk-preprod
#   prod        → main

ENV_NAME="${1:-rengg}"
shift || true

REBUILD=0
EXTRA_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --rebuild) REBUILD=1; shift ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

case "$ENV_NAME" in
  rengg)      SDK_REF="ai-a11y-one-day"     ;;
  regression) SDK_REF="a11y-sdk-regression" ;;
  preprod)    SDK_REF="a11y-sdk-preprod"    ;;
  prod)       SDK_REF="main"                ;;
  *)
    echo "Unknown env: $ENV_NAME" >&2
    echo "Valid: rengg | regression | preprod | prod" >&2
    exit 2
    ;;
esac

IMAGE="a11y-mocha:${ENV_NAME}"

# `colima nerdctl -- ...` forwards args straight to nerdctl inside the VM.
# We wrap it once for readability.
nerd() { colima nerdctl -- "$@"; }

if ! command -v colima >/dev/null 2>&1; then
  echo "colima not found. Run ./setup-colima.sh first." >&2
  exit 1
fi

if ! colima status >/dev/null 2>&1; then
  echo "Colima isn't running. Start it with:  colima start --runtime containerd" >&2
  exit 1
fi

NEED_BUILD=$REBUILD
if [ "$NEED_BUILD" -eq 0 ] && ! nerd image inspect "$IMAGE" >/dev/null 2>&1; then
  NEED_BUILD=1
fi

# ---- Single keys file for all envs --------------------------------------------
# Default: ./keys.env  (next to this script — must be gitignored)
# Override with KEYS_FILE=/some/path ./run.sh ...
# Format (mode 600):
#   GITHUB_TOKEN=ghp_xxx                       # shared default
#   RENGG_BROWSERSTACK_USERNAME=...
#   RENGG_BROWSERSTACK_ACCESS_KEY=...
#   REGRESSION_BROWSERSTACK_USERNAME=...
#   REGRESSION_BROWSERSTACK_ACCESS_KEY=...
#   PREPROD_BROWSERSTACK_USERNAME=...
#   PREPROD_BROWSERSTACK_ACCESS_KEY=...
#   PROD_BROWSERSTACK_USERNAME=...
#   PROD_BROWSERSTACK_ACCESS_KEY=...
#   # Optional per-env GitHub token override:
#   # PROD_GITHUB_TOKEN=ghp_yyy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_FILE="${KEYS_FILE:-${SCRIPT_DIR}/keys.env}"

if [ ! -f "$KEYS_FILE" ]; then
  cat >&2 <<EOF
✗ Keys file not found: $KEYS_FILE

Create it (single file, all envs):
  cat > $KEYS_FILE <<'EOK'
  GITHUB_TOKEN=ghp_xxx

  RENGG_BROWSERSTACK_USERNAME=...
  RENGG_BROWSERSTACK_ACCESS_KEY=...
  REGRESSION_BROWSERSTACK_USERNAME=...
  REGRESSION_BROWSERSTACK_ACCESS_KEY=...
  PREPROD_BROWSERSTACK_USERNAME=...
  PREPROD_BROWSERSTACK_ACCESS_KEY=...
  PROD_BROWSERSTACK_USERNAME=...
  PROD_BROWSERSTACK_ACCESS_KEY=...
  EOK
  chmod 600 $KEYS_FILE
EOF
  exit 1
fi

# Refuse to load a world/group-readable keys file.
KEYS_PERMS="$(stat -f '%A' "$KEYS_FILE" 2>/dev/null || stat -c '%a' "$KEYS_FILE" 2>/dev/null || echo '')"
case "$KEYS_PERMS" in
  600|400) ;;
  *) echo "⚠  $KEYS_FILE has permissions $KEYS_PERMS — tighten with: chmod 600 $KEYS_FILE" >&2; exit 1 ;;
esac

# Hard guard: refuse to use a keys file that git is tracking. Catches the case
# where someone stripped .gitignore or staged the file by accident.
keys_dir="$(dirname "$KEYS_FILE")"
keys_name="$(basename "$KEYS_FILE")"
if git -C "$keys_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$keys_dir" ls-files --error-unmatch "$keys_name" >/dev/null 2>&1; then
    cat >&2 <<EOF
✗ $KEYS_FILE is tracked by git — secrets must NEVER be committed.

  Untrack and gitignore it:
    git rm --cached "$keys_name"
    grep -qxF "$keys_name" .gitignore || echo "$keys_name" >> .gitignore
    git add .gitignore
    git commit -m "stop tracking $keys_name"

  Then ROTATE every credential in that file — assume it leaked
  (it lives in git history even after the rm above).
EOF
    exit 1
  fi
  if git -C "$keys_dir" diff --cached --name-only -- "$keys_name" 2>/dev/null | grep -qx "$keys_name"; then
    echo "✗ $keys_name is staged for commit — unstage with:  git reset HEAD $keys_name" >&2
    exit 1
  fi
fi

# Source the file. set -a auto-exports every assignment so they're visible to nerdctl.
set -a
# shellcheck disable=SC1090
. "$KEYS_FILE"
set +a

# Resolve per-env vars by prefix (e.g., PREPROD_BROWSERSTACK_USERNAME).
ENV_UPPER="$(printf '%s' "$ENV_NAME" | tr '[:lower:]' '[:upper:]')"

bs_user_var="${ENV_UPPER}_BROWSERSTACK_USERNAME"
bs_key_var="${ENV_UPPER}_BROWSERSTACK_ACCESS_KEY"
gh_tok_var="${ENV_UPPER}_GITHUB_TOKEN"

BROWSERSTACK_USERNAME="${!bs_user_var:-}"
BROWSERSTACK_ACCESS_KEY="${!bs_key_var:-}"
RESOLVED_GH_TOKEN="${!gh_tok_var:-${GITHUB_TOKEN:-}}"

if [ -z "$BROWSERSTACK_USERNAME" ] || [ -z "$BROWSERSTACK_ACCESS_KEY" ]; then
  echo "✗ ${bs_user_var} or ${bs_key_var} missing in $KEYS_FILE" >&2
  exit 1
fi
export BROWSERSTACK_USERNAME BROWSERSTACK_ACCESS_KEY

if [ "$NEED_BUILD" -eq 1 ] && [ -z "$RESOLVED_GH_TOKEN" ]; then
  echo "✗ No GitHub token: set GITHUB_TOKEN (shared) or ${gh_tok_var} (per-env) in $KEYS_FILE" >&2
  exit 1
fi
# -------------------------------------------------------------------------------

if [ "$NEED_BUILD" -eq 1 ]; then
  # Write the resolved token to a $HOME-resident file so Colima's VM can mount it.
  TOKEN_FILE="${HOME}/.cache/a11y-mocha-gh-token"
  mkdir -p "${HOME}/.cache"
  umask 077
  printf '%s' "$RESOLVED_GH_TOKEN" > "$TOKEN_FILE"
  trap 'rm -f "$TOKEN_FILE"' EXIT

  echo "→ Building $IMAGE  (SDK_REF=$SDK_REF)"
  nerd build \
    --build-arg "SDK_REF=${SDK_REF}" \
    --secret "id=gh_token,src=${TOKEN_FILE}" \
    -t "$IMAGE" \
    .
else
  echo "✓ Reusing existing image $IMAGE  (use --rebuild to refresh)"
fi

mkdir -p log

echo "→ Running $IMAGE  (env=$ENV_NAME, BS user=$BROWSERSTACK_USERNAME)"
exec colima nerdctl -- run --rm -it \
  -e "BUILD_NUMBER=${BUILD_NUMBER:-local-$(date +%s)}" \
  -e BROWSERSTACK_USERNAME \
  -e BROWSERSTACK_ACCESS_KEY \
  -v "$PWD/src:/app/src" \
  -v "$PWD/data:/app/data" \
  -v "$PWD/log:/app/log" \
  -v "$PWD/browserstack.yml:/app/browserstack.yml:ro" \
  "$IMAGE" \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
