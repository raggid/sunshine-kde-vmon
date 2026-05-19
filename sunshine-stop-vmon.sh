#!/usr/bin/env bash

# Restore physical monitor priority
kscreen-doctor output.DP-2.priority.1

# Kill virtual display
if [ -f /tmp/sunshine-vmon.pid ]; then
  kill "$(cat /tmp/sunshine-vmon.pid)" 2>/dev/null || true
  rm -f /tmp/sunshine-vmon.pid
fi

# Restore Sunshine output to physical display
CONF="${HOME}/.config/sunshine/sunshine.conf"
sed -i '/^output_name/d' "$CONF"
echo "output_name = DP-1" >> "$CONF"
