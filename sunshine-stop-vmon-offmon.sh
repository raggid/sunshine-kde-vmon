#!/usr/bin/env bash

PRIMARY="${SUNSHINE_PRIMARY_OUTPUT:-DP-2}"

# Re-enable physical monitor before tearing down the virtual one
kscreen-doctor \
  output.${PRIMARY}.enable \
  output.${PRIMARY}.priority.1

# Kill virtual display
if [ -f /tmp/sunshine-vmon.pid ]; then
  kill "$(cat /tmp/sunshine-vmon.pid)" 2>/dev/null || true
  rm -f /tmp/sunshine-vmon.pid
fi

# Restore Sunshine output to physical display
CONF="${HOME}/.config/sunshine/sunshine.conf"
sed -i '/^output_name/d' "$CONF"
echo "output_name = ${PRIMARY}" >> "$CONF"
