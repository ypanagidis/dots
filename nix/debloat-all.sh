#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

KEEP_SYSTEM_GENERATIONS="${KEEP_SYSTEM_GENERATIONS:-5}"
PRUNE_DOCKER_VOLUMES="${PRUNE_DOCKER_VOLUMES:-0}"
CLEAN_SANDBOX_NODE_MODULES="${CLEAN_SANDBOX_NODE_MODULES:-1}"
JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-500M}"

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo ./debloat-all.sh"
  exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "${TARGET_USER}" || "${TARGET_USER}" == "root" ]]; then
  warn "SUDO_USER not set. Set TARGET_USER manually if needed."
  TARGET_USER="${TARGET_USER:-yiannis}"
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then
  echo "Could not resolve home directory for user '${TARGET_USER}'."
  exit 1
fi

DEV_WORK_DIR="${TARGET_HOME}/Developer/Work"

run_as_user() {
  local cmd="$1"
  su -s /bin/bash "${TARGET_USER}" -c "${cmd}" || true
}

show_disk() {
  df -h /
}

safe_rm() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    rm -rf -- "${path}"
  fi
}

trim_nix_system_generations() {
  local keep="$1"
  python3 - "$keep" <<'PY'
import glob
import re
import subprocess
import sys

keep = int(sys.argv[1])
paths = glob.glob('/nix/var/nix/profiles/system-*-link')
gens = []
for p in paths:
    m = re.search(r'system-(\d+)-link$', p)
    if m:
        gens.append(int(m.group(1)))
gens = sorted(gens)

if len(gens) <= keep:
    print(f"No system generation deletion needed (have {len(gens)}, keep {keep}).")
    raise SystemExit(0)

old = gens[:-keep]
print(f"Deleting {len(old)} old system generations; keeping latest {keep}: {gens[-keep:]}")
subprocess.run([
    'nix-env',
    '-p',
    '/nix/var/nix/profiles/system',
    '--delete-generations',
    *map(str, old),
], check=True)
PY
}

clean_developer_node_modules() {
  python3 - "$TARGET_HOME" "$DEV_WORK_DIR" <<'PY'
from pathlib import Path
import shutil
import sys

home = Path(sys.argv[1])
work = Path(sys.argv[2]).resolve()
dev = home / 'Developer'

if not dev.exists():
    print('No ~/Developer directory found, skipping node_modules cleanup.')
    raise SystemExit(0)

removed = 0
bytes_removed = 0

for p in dev.rglob('node_modules'):
    if not p.is_dir():
        continue

    rp = p.resolve()
    if str(rp).startswith(str(work) + '/') or rp == work:
        continue

    size = 0
    for f in p.rglob('*'):
        try:
            if f.is_file():
                size += f.stat().st_size
        except OSError:
            pass

    print(f'Removing {p}')
    shutil.rmtree(p, ignore_errors=True)
    removed += 1
    bytes_removed += size

print(f'Removed {removed} node_modules directories')
print(f'Approx reclaimed {bytes_removed / (1024**3):.2f} GiB')
PY
}

log "Starting debloat for user '${TARGET_USER}' (${TARGET_HOME})"
log "Developer/Work will remain untouched: ${DEV_WORK_DIR}"
log "Disk usage before cleanup:"
show_disk

log "Phase 1: Trash + high-churn app caches"
safe_rm "${TARGET_HOME}/.local/share/Trash/files"
safe_rm "${TARGET_HOME}/.local/share/Trash/info"
mkdir -p "${TARGET_HOME}/.local/share/Trash/files" "${TARGET_HOME}/.local/share/Trash/info"

safe_rm "${TARGET_HOME}/.cache/google-chrome"
safe_rm "${TARGET_HOME}/.cache/chromium"
safe_rm "${TARGET_HOME}/.cache/net.imput.helium"
safe_rm "${TARGET_HOME}/.config/discord/Cache"
safe_rm "${TARGET_HOME}/.config/discord/Code Cache"
safe_rm "${TARGET_HOME}/.cache/JetBrains"

log "Phase 2: Package manager caches"
if need_cmd pnpm; then
  run_as_user "pnpm store prune"
else
  warn "pnpm not found; skipping pnpm prune"
fi

if need_cmd npm; then
  run_as_user "npm cache clean --force"
else
  warn "npm not found; skipping npm cache clean"
fi

if need_cmd bun; then
  run_as_user "bun pm cache rm"
fi
safe_rm "${TARGET_HOME}/.bun/install/cache"

log "Phase 3: Developer node_modules cleanup (excluding Developer/Work)"
if [[ "${CLEAN_SANDBOX_NODE_MODULES}" == "1" ]]; then
  clean_developer_node_modules
else
  log "Skipping node_modules cleanup because CLEAN_SANDBOX_NODE_MODULES=${CLEAN_SANDBOX_NODE_MODULES}"
fi

log "Phase 4: Docker cleanup"
if need_cmd docker; then
  docker builder prune -af || true
  docker image prune -af || true
  docker container prune -f || true
  if [[ "${PRUNE_DOCKER_VOLUMES}" == "1" ]]; then
    docker volume prune -f || true
  fi
else
  warn "docker not found; skipping Docker cleanup"
fi

log "Phase 5: Nix cleanup"
if need_cmd nix-env; then
  trim_nix_system_generations "${KEEP_SYSTEM_GENERATIONS}"
else
  warn "nix-env not found; skipping system generation trimming"
fi

if need_cmd nix-collect-garbage; then
  nix-collect-garbage -d || true
  run_as_user "nix-collect-garbage -d"
else
  warn "nix-collect-garbage not found; skipping Nix GC"
fi

log "Phase 6: Journal vacuum"
if need_cmd journalctl; then
  journalctl --vacuum-size="${JOURNAL_MAX_SIZE}" || true
else
  warn "journalctl not found; skipping journal vacuum"
fi

log "Post-cleanup status"
show_disk

if need_cmd docker; then
  docker system df || true
fi

if need_cmd nix-store; then
  nix-store --gc --print-dead | wc -l || true
fi

log "Debloat complete."
