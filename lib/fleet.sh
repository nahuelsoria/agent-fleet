#!/usr/bin/env bash
# agent-fleet — sourceable core.
# Source this at the top of every agent's run.sh:
#
#   source "$(dirname "$0")/../../lib/fleet.sh"
#
# It resolves FLEET_HOME, loads .env, and exposes `log` and `notify`.

# --- Resolve the fleet root from this file's location (no hardcoded paths) ---
_FLEET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_HOME="${FLEET_HOME:-$(dirname "$_FLEET_LIB_DIR")}"
export FLEET_HOME

# --- Load secrets/config from .env at the repo root, if present --------------
# .env is gitignored. See .env.example for the supported variables.
if [ -f "$FLEET_HOME/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$FLEET_HOME/.env"
    set +a
fi

# --- log "<agent>" "<message>" ----------------------------------------------
# Appends a timestamped line to agents/<agent>/logs/YYYY-MM-DD.log
log() {
    local agent="$1" msg="$2"
    local dir="$FLEET_HOME/agents/$agent/logs"
    mkdir -p "$dir"
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$msg" >> "$dir/$(date +%Y-%m-%d).log"
}

# --- notify "<message>" -----------------------------------------------------
# Sends a message to whatever channels are configured in .env:
#   - Telegram  (TELEGRAM_TOKEN + TELEGRAM_CHAT_ID)
#   - Webhook   (FLEET_WEBHOOK_URL — Slack/Discord/anything accepting {"text":...})
# Telegram is tried as Markdown first and falls back to plain text on a parse
# error (HTTP 400 from unbalanced _ * [ ` in dynamic content) so a message is
# never silently dropped. Returns non-zero only if every configured channel
# failed. With no channel configured it just prints to stdout.
notify() {
    local msg="$1" delivered=0 any_channel=0

    if [ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        any_channel=1
        _fleet_telegram "$msg" && delivered=1
    fi

    if [ -n "${FLEET_WEBHOOK_URL:-}" ]; then
        any_channel=1
        _fleet_webhook "$msg" && delivered=1
    fi

    if [ "$any_channel" -eq 0 ]; then
        printf '[notify] %s\n' "$msg"
        return 0
    fi

    [ "$delivered" -eq 1 ]
}

_fleet_telegram() {
    local msg="$1" api="https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" resp
    _tg_send() {
        if [ -n "$1" ]; then
            curl -s -X POST "$api" \
                --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
                --data-urlencode "text=${msg}" \
                --data-urlencode "parse_mode=$1"
        else
            curl -s -X POST "$api" \
                --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
                --data-urlencode "text=${msg}"
        fi
    }
    resp="$(_tg_send Markdown)"
    case "$resp" in *'"ok":true'*) return 0 ;; esac
    # Markdown failed to parse (or network hiccup) — retry as plain text.
    resp="$(_tg_send "")"
    case "$resp" in *'"ok":true'*) return 0 ;; esac
    printf 'notify: telegram delivery failed: %s\n' "${resp:0:200}" >&2
    return 1
}

_fleet_webhook() {
    local msg="$1" code
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FLEET_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        --data-urlencode "payload@-" <<EOF 2>/dev/null || true
{"text": $(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$msg")}
EOF
)"
    case "$code" in 2*) return 0 ;; esac
    # Some webhooks (Slack/Discord) want the raw JSON body, not urlencoded.
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FLEET_WEBHOOK_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"text\": $(printf '%s' "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$msg")}" 2>/dev/null || true)"
    case "$code" in 2*) return 0 ;; esac
    printf 'notify: webhook delivery failed (HTTP %s)\n' "$code" >&2
    return 1
}
