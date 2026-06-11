#!/usr/bin/env bash
set -euo pipefail

# One-time setup for Colima on macOS with the Docker runtime.
# Uses the docker runtime so the standard `docker` CLI works — compatible with
# docker-compose workflows in sibling repos (e.g. context_generator).
# Safe to re-run; will skip steps that are already done.

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh first." >&2
  exit 1
fi

if brew list --formula colima >/dev/null 2>&1; then
  echo "✓ colima already installed"
else
  echo "→ Installing colima"
  brew install colima
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "→ Installing docker CLI"
  brew install docker
else
  echo "✓ docker CLI already installed"
fi

if brew list --formula docker-buildx >/dev/null 2>&1; then
  echo "✓ docker-buildx already installed"
else
  echo "→ Installing docker-buildx (required for BuildKit --secret support)"
  brew install docker-buildx
fi

BUILDX_PLUGIN_DIR="${HOME}/.docker/cli-plugins"
BUILDX_LINK="${BUILDX_PLUGIN_DIR}/docker-buildx"
BUILDX_BIN="$(brew --prefix)/opt/docker-buildx/bin/docker-buildx"
if [ -L "$BUILDX_LINK" ] && [ "$(readlink "$BUILDX_LINK")" = "$BUILDX_BIN" ]; then
  echo "✓ buildx symlink already in place"
else
  echo "→ Symlinking buildx into docker CLI plugins"
  mkdir -p "$BUILDX_PLUGIN_DIR"
  ln -sfn "$BUILDX_BIN" "$BUILDX_LINK"
fi

# `colima list` reports STATUS and RUNTIME for the default profile even when the
# VM is stopped, so it's a more reliable probe than `colima status` (which only
# succeeds while the VM is running).
VM_ROW="$(colima list 2>/dev/null | awk '$1 == "default" {print; exit}')"
VM_STATUS="$(echo "$VM_ROW" | awk '{print $2}')"
VM_RUNTIME="$(echo "$VM_ROW" | awk '{print $7}')"

if [ -z "$VM_ROW" ]; then
  echo "→ Starting Colima with Docker runtime (4 CPU / 6 GiB RAM / 30 GiB disk)"
  colima start --runtime docker --cpu 4 --memory 6 --disk 30
elif [ "$VM_RUNTIME" != "docker" ]; then
  # Runtime can't be changed in place, and the data disk is provisioned for the
  # old runtime, so the only way to switch is to wipe and recreate the VM.
  echo "→ Existing VM uses runtime '$VM_RUNTIME', not 'docker'. Recreating (this wipes its containers/images)."
  colima delete --data --force
  echo "→ Starting Colima with Docker runtime (4 CPU / 6 GiB RAM / 30 GiB disk)"
  colima start --runtime docker --cpu 4 --memory 6 --disk 30
elif [ "$VM_STATUS" = "Running" ]; then
  echo "✓ Colima already running with the Docker runtime"
else
  echo "→ Starting existing Docker-runtime Colima VM"
  colima start
fi

echo
echo "Sanity check:"
docker info --format '✓ docker is talking to: {{.ServerVersion}} on {{.OperatingSystem}}' \
  || { echo "docker check failed" >&2; exit 1; }

echo
echo "Done. Next: ./run.sh <env>   (envs: rengg | regression | preprod | prod)"
