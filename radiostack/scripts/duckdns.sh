#!/bin/bash
# ─────────────────────────────────────────────────────────
# DuckDNS Dynamic IP Updater
# Run this as a cron job to keep your domain pointing to
# your home server's current public IP.
#
# Setup:
#   1. Register at https://www.duckdns.org
#   2. Create a subdomain (e.g. myradio.duckdns.org)
#   3. Copy your token from the DuckDNS dashboard
#   4. Fill in SUBDOMAIN and TOKEN below
#   5. Add to crontab: */5 * * * * /path/to/duckdns.sh
# ─────────────────────────────────────────────────────────

SUBDOMAIN="your-subdomain-here"   # e.g. myradio
TOKEN="your-duckdns-token-here"   # from duckdns.org dashboard
LOG="/var/log/duckdns.log"

echo "[$(date)] Updating DuckDNS..." >> $LOG
RESULT=$(curl -s "https://www.duckdns.org/update?domains=${SUBDOMAIN}&token=${TOKEN}&ip=")
echo "[$(date)] Response: $RESULT" >> $LOG

if [ "$RESULT" = "OK" ]; then
  echo "[$(date)] ✓ IP updated successfully" >> $LOG
else
  echo "[$(date)] ✗ Update failed" >> $LOG
fi
