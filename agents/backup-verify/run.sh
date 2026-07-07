#!/usr/bin/env bash
# Example agent: backup-verify.
# Verifies that your most recent backup actually exists, is FRESH, is a
# plausible SIZE, and — for gzip files — is not corrupt. A backup you never
# check isn't a backup. Alerts ONLY on a problem (red-only); silence = healthy.
#
# Point it at your backups via .env (see the BACKUP_* vars below), then schedule
# it a couple of hours after your backup job runs, e.g. backups at 03:00:
#   0 5 * * * /path/to/agent-fleet/agents/backup-verify/run.sh
set -Eeuo pipefail
source "$(dirname "$0")/../../lib/fleet.sh"

AGENT="backup-verify"

# --- config (override in .env) ----------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
BACKUP_GLOB="${BACKUP_GLOB:-*.gz}"        # which files count as "the backup"
BACKUP_MAX_AGE_H="${BACKUP_MAX_AGE_H:-26}" # older than this = stale (default: daily + slack)
BACKUP_MIN_BYTES="${BACKUP_MIN_BYTES:-102400}" # 100 KB — an empty/broken dump weighs far less

problems=()

latest="$(ls -t "$BACKUP_DIR"/$BACKUP_GLOB 2>/dev/null | head -1 || true)"
if [ -z "$latest" ]; then
    problems+=("No file matching '$BACKUP_GLOB' in $BACKUP_DIR")
else
    now=$(date +%s)
    age_h=$(( ( now - $(stat -c %Y "$latest") ) / 3600 ))
    size=$(stat -c %s "$latest")

    [ "$age_h" -gt "$BACKUP_MAX_AGE_H" ] \
        && problems+=("Latest backup is ${age_h}h old (>${BACKUP_MAX_AGE_H}h): $(basename "$latest")")
    [ "$size" -lt "$BACKUP_MIN_BYTES" ] \
        && problems+=("Latest backup is ${size}B (<${BACKUP_MIN_BYTES}B): likely empty/broken")

    # Integrity check for gzip files.
    case "$latest" in
        *.gz) gzip -t "$latest" 2>/dev/null || problems+=("Corrupt gzip: $(basename "$latest")") ;;
    esac
fi

if [ ${#problems[@]} -gt 0 ]; then
    msg="🔴 *$(hostname) — backup check*"
    for p in "${problems[@]}"; do msg="${msg}"$'\n'"• ${p}"; done
    notify "$msg"
    log "$AGENT" "ALERT: ${problems[*]}"
else
    log "$AGENT" "OK — latest backup fresh & valid"
fi
