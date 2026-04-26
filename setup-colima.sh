#!/usr/bin/env bash
set -euo pipefail

# One-time setup for Colima on macOS — no Docker install.
# Uses the containerd runtime + bundled nerdctl (accessed via `colima nerdctl ...`).
# Safe to re-run; will skip steps that are already done.

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh first." >&2
  exit 1
fi

if brew list --formula colima >/dev/null 2>&1; then
  echo "✓ colima already installed"
else
  echo "→ Installing colima (Lima comes as a dependency; no docker required)"
  brew install colima
fi

if colima status >/dev/null 2>&1; then
  echo "✓ Colima already running"
  CURRENT_RUNTIME="$(colima status 2>&1 | awk -F': *' '/runtime/ {print $2; exit}')"
  if [ -n "${CURRENT_RUNTIME:-}" ] && [ "$CURRENT_RUNTIME" != "containerd" ]; then
    echo "⚠  Colima is running with runtime '$CURRENT_RUNTIME', not 'containerd'."
    echo "    To switch:  colima stop && colima start --runtime containerd --cpu 4 --memory 6 --disk 30"
  fi
else
  echo "→ Starting Colima with containerd runtime (4 CPU / 6 GiB RAM / 30 GiB disk)"
  colima start --runtime containerd --cpu 4 --memory 6 --disk 30
fi

echo
echo "Sanity check:"
colima nerdctl -- info --format '✓ nerdctl is talking to: {{.ServerVersion}} on {{.OperatingSystem}}' \
  || { echo "nerdctl check failed" >&2; exit 1; }

echo
echo "Done. Next: ./run.sh <env>   (envs: rengg | regression | preprod | prod)"
