#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/openmaic.pid"
LOG_FILE="$SCRIPT_DIR/openmaic.log"

if [ -f "$PID_FILE" ]; then
  EXISTING_PID=$(cat "$PID_FILE")
  if kill -0 "$EXISTING_PID" 2>/dev/null; then
    echo "OpenMAIC is already running (PID $EXISTING_PID)"
    echo "  Log:  $LOG_FILE"
    echo "  URL:  http://localhost:3000"
    exit 0
  else
    echo "Stale PID file found — cleaning up."
    rm -f "$PID_FILE"
  fi
fi

# Load nvm
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

if ! command -v pnpm &>/dev/null; then
  echo "ERROR: pnpm not found after loading nvm. Check your nvm/Node setup." >&2
  exit 1
fi

echo "Starting OpenMAIC dev server..."
cd "$SCRIPT_DIR"
nohup pnpm dev >"$LOG_FILE" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$PID_FILE"

echo "  PID:  $APP_PID"
echo "  Log:  $LOG_FILE"
echo "  URL:  http://localhost:3000"
echo ""
echo "Waiting for server to be ready..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:3000 >/dev/null 2>&1; then
    # Use ss (not lsof) to find the actual listening PID — lsof misses it
    REAL_PID=$(ss -tlnp 'sport = :3000' | grep -oP 'pid=\K\d+' | head -1)
    if [ -n "$REAL_PID" ]; then
      # Store the PGID for reliable process-group kill
      PGID=$(ps -o pgid= -p "$REAL_PID" | tr -d ' ')
      echo "$PGID" > "$PID_FILE"
      APP_PID="$REAL_PID"
    fi
    echo "Server is up at http://localhost:3000 (PID $APP_PID, PGID $(cat "$PID_FILE"))"
    exit 0
  fi
  sleep 1
done
echo "Server did not respond within 30s — check $LOG_FILE for details."
