#!/usr/bin/env bash
set -Eeuo pipefail

LOG="/var/log/netdev-watchdog-rebooter.log"
touch "$LOG"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }

# Follow the journal and react on signature lines
journalctl -f -o cat | while IFS= read -r line; do
  if [[ "$line" == *"NETDEV WATCHDOG"* ]]; then
    log "Detected NETDEV WATCHDOG. Rebooting now."
    /usr/bin/systemctl reboot
  fi
done
