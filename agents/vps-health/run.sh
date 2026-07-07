#!/usr/bin/env bash
# Example agent: red-only VPS health check.
# Alerts ONLY when something is actually wrong — disk >85%, available memory
# <10%, failed systemd units, or oversized logs. Silence means healthy, which
# keeps the signal-to-noise ratio high enough that you actually read the alerts.
#
# Schedule it from cron, e.g. every day at 09:00:
#   0 9 * * * /path/to/agent-fleet/agents/vps-health/run.sh
set -Eeuo pipefail
source "$(dirname "$0")/../../lib/fleet.sh"

AGENT="vps-health"

DISK_PCT_MAX="${DISK_PCT_MAX:-85}"
MEM_AVAIL_MIN_PCT="${MEM_AVAIL_MIN_PCT:-10}"
LOG_SIZE_MAX="${LOG_SIZE_MAX:-+500M}"
LOG_SCAN_DIRS="${LOG_SCAN_DIRS:-$FLEET_HOME}"

problems=()

# Disk usage of /
disk=$(df --output=pcent / | tail -1 | tr -dc '0-9')
[ "${disk:-0}" -gt "$DISK_PCT_MAX" ] && problems+=("Disk / at ${disk}%")

# Available memory (%)
read -r total avail < <(free -m | awk '/^Mem:/{print $2, $7}')
if [ "${total:-0}" -gt 0 ]; then
    mempct=$(( avail * 100 / total ))
    [ "$mempct" -lt "$MEM_AVAIL_MIN_PCT" ] \
        && problems+=("Available memory ${mempct}% (${avail}MB of ${total}MB)")
fi

# Failed systemd units
failed=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' | paste -sd, - || true)
[ -n "$failed" ] && problems+=("Failed systemd units: ${failed}")

# Oversized log files
big=$(find $LOG_SCAN_DIRS -type f -name "*.log" -size "$LOG_SIZE_MAX" 2>/dev/null \
    | head -5 | paste -sd, - || true)
[ -n "$big" ] && problems+=("Logs larger than ${LOG_SIZE_MAX}: ${big}")

if [ ${#problems[@]} -gt 0 ]; then
    msg="🔴 *$(hostname) — health check*"
    for p in "${problems[@]}"; do msg="${msg}"$'\n'"• ${p}"; done
    notify "$msg"
    log "$AGENT" "ALERT: ${problems[*]}"
else
    log "$AGENT" "OK — all green"
fi
