# Auto-reboot on `NETDEV WATCHDOG` (Minimal Service)

This repo documents a tiny Linux service that **watches the kernel log for `NETDEV WATCHDOG` errors** and **immediately reboots** the VM when they occur. It’s a pragmatic guardrail for single-purpose boxes (e.g., a SABnzbd VM) where a quick reboot is an acceptable way to recover from NIC stalls.

> ⚠️ This is intentionally simple. There’s no rate-limiting or graceful app shutdown. If you need those, consider a “v2” with pausing APIs and backoff.

## How it works

- Follows the system journal in real time (`journalctl -f -o cat`).
- On any line containing `NETDEV WATCHDOG`, calls `systemctl reboot`.
- Runs as a `systemd` service that restarts itself if it ever exits.

---

## 1) Install the watcher script

Create `/usr/local/sbin/netdev-watchdog-rebooter.sh`:

```bash
sudo install -d -m 0755 /usr/local/sbin
sudo tee /usr/local/sbin/netdev-watchdog-rebooter.sh >/dev/null <<'EOF'
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
EOF
sudo chmod 0755 /usr/local/sbin/netdev-watchdog-rebooter.sh
```

This script tails the journal, looks for the substring `NETDEV WATCHDOG`, logs the trip, and reboots.

---

## 2) Create the systemd unit

Create `/etc/systemd/system/netdev-watchdog-rebooter.service`:

```bash
sudo tee /etc/systemd/system/netdev-watchdog-rebooter.service >/dev/null <<'EOF'
[Unit]
Description=Reboot VM automatically on NETDEV WATCHDOG errors
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/netdev-watchdog-rebooter.sh
Restart=always
RestartSec=2
StandardOutput=append:/var/log/netdev-watchdog-rebooter.log
StandardError=append:/var/log/netdev-watchdog-rebooter.log

[Install]
WantedBy=multi-user.target
EOF
```

Then enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now netdev-watchdog-rebooter.service
```

---

## 3) Verify it’s running

```bash
systemctl status netdev-watchdog-rebooter.service
tail -f /var/log/netdev-watchdog-rebooter.log
```

You should see that the service is **active (running)** and the log file exists.

---

## 4) Safe test (no real reboot)

If you want to confirm the trigger without rebooting:

1. Temporarily edit the script and replace:
   ```bash
   /usr/bin/systemctl reboot
   ```
   with:
   ```bash
   echo "[TEST] would reboot now" | tee -a "$LOG"
   ```

2. Restart the service and inject a fake journal line:
   ```bash
   sudo systemctl restart netdev-watchdog-rebooter.service
   sudo logger "NETDEV WATCHDOG: test trip"
   ```

3. Check the log:
   ```bash
   tail -n 50 /var/log/netdev-watchdog-rebooter.log
   ```
   You should see the detection and the “[TEST] would reboot now” line.

4. Put the real reboot command back and `sudo systemctl restart netdev-watchdog-rebooter.service`.

---

## 5) Uninstall / Disable

```bash
sudo systemctl disable --now netdev-watchdog-rebooter.service
sudo rm -f /etc/systemd/system/netdev-watchdog-rebooter.service
sudo systemctl daemon-reload
sudo rm -f /usr/local/sbin/netdev-watchdog-rebooter.sh
sudo rm -f /var/log/netdev-watchdog-rebooter.log
```

---

## Notes & Caveats

- **Scope**: This is best for single-purpose VMs (e.g., downloaders) where a reboot is an acceptable recovery.
- **Trigger text**: The match is a simple substring check on `NETDEV WATCHDOG`. That string shows up on typical Linux kernels/drivers when TX timeouts occur.
- **Logs**: All actions append to `/var/log/netdev-watchdog-rebooter.log`.
- **Privileges**: The service runs as root so it can call `systemctl reboot`. If you need to harden it, you can experiment with `NoNewPrivileges=yes` and `CapabilityBoundingSet=...`, but `systemctl reboot` generally requires full privileges.

---

## License

MIT — do whatever, no warranty.
