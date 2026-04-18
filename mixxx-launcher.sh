#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="DDJFLX4"
MIXXX_BIN="/usr/bin/mixxx"
LOG_FILE="/home/pi/.mixxx/mixxx_launcher.log"
SLEEP_INTERVAL=1

echo "Script started. Waiting for device: $DEVICE_NAME"

while true; do
  if aplay -l 2>/dev/null | grep -q "$DEVICE_NAME"; then
    echo "Device '$DEVICE_NAME' detected"

    if pgrep -x mixxx >/dev/null 2>&1; then
      echo "Mixxx already running. Exiting."
    else
      echo "Launching Mixxx..."
      echo "Logging to: $LOG_FILE"

      mkdir -p "$(dirname "$LOG_FILE")"

      nohup "$MIXXX_BIN" >>"$LOG_FILE" 2>&1 &
      echo "Mixxx started"
    fi

    echo "Done. Exiting watcher."
    exit 0
  else
    echo "Device not found, retrying..."
  fi

  sleep "$SLEEP_INTERVAL"
done
