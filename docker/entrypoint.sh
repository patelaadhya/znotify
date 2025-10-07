#!/bin/bash
set -e

# Start D-Bus session daemon
echo "Starting D-Bus session daemon..."
dbus-daemon --session --fork --address="$DBUS_SESSION_BUS_ADDRESS" --print-address

# Start Xvfb for headless GUI support
echo "Starting Xvfb..."
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
XVFB_PID=$!

# Start notification daemon
echo "Starting notification daemon (dunst)..."
dunst > /dev/null 2>&1 &
DUNST_PID=$!

# Give daemons time to start
sleep 2

echo "Environment ready. D-Bus and notification daemon running."
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
echo "DISPLAY=$DISPLAY"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    kill $DUNST_PID 2>/dev/null || true
    kill $XVFB_PID 2>/dev/null || true
}
trap cleanup EXIT

# Execute the command passed to the container
exec "$@"
