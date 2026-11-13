#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# DuckDNS Dynamic IP Updater
# Keeps <subdomain>.duckdns.org pointing at this server's public IP.
#
# Setup:
#   1. Register at https://www.duckdns.org and create a subdomain
#   2. Put DUCKDNS_SUBDOMAIN and DUCKDNS_TOKEN in radiostack/.env
#      (gitignored; see .env.example). Never put the token in this file.
#   3. Add to crontab: */5 * * * * /path/to/radiostack/scripts/duckdns.sh
#
# Log: $DUCKDNS_LOG, default ~/.local/state/duckdns.log
# ─────────────────────────────────────────────────────────
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
LOG="${DUCKDNS_LOG:-$HOME/.local/state/duckdns.log}"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }
die() { log "✗ $*"; echo "duckdns: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found. Run: cp .env.example .env, then fill it in."

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ -n "${DUCKDNS_SUBDOMAIN:-}" ]] || die "DUCKDNS_SUBDOMAIN is empty in $ENV_FILE"
[[ -n "${DUCKDNS_TOKEN:-}" ]]     || die "DUCKDNS_TOKEN is empty in $ENV_FILE"

# Pass the URL on stdin (curl -K -) so the token never shows up in `ps` output.
RESULT=$(printf 'url = "https://www.duckdns.org/update?domains=%s&token=%s&ip="\n' \
           "$DUCKDNS_SUBDOMAIN" "$DUCKDNS_TOKEN" | curl -s -m 15 -K -) || RESULT="curl error"

if [[ "$RESULT" == "OK" ]]; then
  log "✓ $DUCKDNS_SUBDOMAIN.duckdns.org updated"
else
  die "update failed: $RESULT"
fi
