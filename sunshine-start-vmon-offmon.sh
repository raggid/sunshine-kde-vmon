#!/usr/bin/env bash

WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS%.*}"
FPS="${FPS:-60}"
FPS_MHZ=$(( FPS * 1000 ))
RES="${WIDTH}x${HEIGHT}"

NAME="sunshine-vmon"
PRIMARY="${SUNSHINE_PRIMARY_OUTPUT:-DP-2}"

# Create virtual display at client resolution
krfb-virtualmonitor --resolution "$RES" --name "$NAME" --password "sunshinepass" --port 5905 &
echo $! > /tmp/sunshine-vmon.pid

# Wait for KDE to register the new display
sleep 3

# Add custom mode support for the correct frame rate
kscreen-doctor output.Virtual-${NAME}.addCustomMode.${WIDTH}.${HEIGHT}.${FPS_MHZ}.full

# Virtual display as primary; disable physical monitor
kscreen-doctor \
  output.Virtual-${NAME}.enable \
  output.Virtual-${NAME}.mode.${RES}@${FPS} \
  output.Virtual-${NAME}.priority.1 \
  output.${PRIMARY}.disable

# Tell Sunshine to capture the virtual display
CONF="${HOME}/.config/sunshine/sunshine.conf"
sed -i '/^output_name/d' "$CONF"
echo "output_name = Virtual-${NAME}" >> "$CONF"
