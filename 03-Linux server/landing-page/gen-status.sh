#!/usr/bin/env bash
# gen-status.sh - writes status.json for the Northstar portal.
# Run on NS-SRV01. Usage: sudo ./gen-status.sh [output-path]
# Default output: /var/www/northstar/html/status.json (the Nginx web root)

set -euo pipefail

OUT="${1:-/var/www/northstar/html/status.json}"

# Fail loudly if the folder is wrong, instead of writing the file somewhere Nginx never looks
if [ ! -d "$(dirname "$OUT")" ]; then
  echo "ERROR: output folder does not exist: $(dirname "$OUT")" >&2
  exit 1
fi

TMP="$(mktemp)"

# Prints the systemd state of a unit: active, inactive, failed...
svc_state() { systemctl is-active "$1" 2>/dev/null || true; }

HOSTNAME_VALUE="$(hostname)"
OS_VALUE="$(. /etc/os-release && echo "$PRETTY_NAME")"
UPTIME_VALUE="$(uptime -p)"
NOW="$(date --iso-8601=seconds)"

# Root filesystem: size and used space in GB, plus percent used
read -r TOTAL USED PERCENT < <(df -BG --output=size,used,pcent / | tail -n 1 | tr -d 'G%')

cat > "$TMP" <<EOF
{
  "generated": "$NOW",
  "hostname": "$HOSTNAME_VALUE",
  "os": "$OS_VALUE",
  "uptime": "$UPTIME_VALUE",
  "disk": { "total_gb": $TOTAL, "used_gb": $USED, "percent": $PERCENT },
  "services": [
    { "name": "Web server", "unit": "nginx.service", "state": "$(svc_state nginx)", "detail": "Serving the internal portal on port 80" },
    { "name": "Remote administration", "unit": "ssh.service", "state": "$(svc_state ssh)", "detail": "OpenSSH, port 22" },
    { "name": "Firewall", "unit": "ufw.service", "state": "$(svc_state ufw)", "detail": "UFW, default deny incoming" }
  ]
}
EOF

# Replace the file in one step so visitors never read a half-written file
chmod 644 "$TMP"
mv "$TMP" "$OUT"
