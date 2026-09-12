#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/openmaic.pid"

# Find the process actually listening on port 3000 using ss (reliable)
LISTEN_PID=$(ss -tlnp 'sport = :3000' | grep -oP 'pid=\K\d+' | head -1)

if [ -z "$LISTEN_PID" ] && [ ! -f "$PID_FILE" ]; then
  echo "No processes found on port 3000 — OpenMAIC does not appear to be running."
  rm -f "$PID_FILE"
  exit 0
fi

# Get the PGID: from PID file (which stores PGID), or derive from the listening process
PGID=""
if [ -f "$PID_FILE" ]; then
  PGID=$(cat "$PID_FILE")
fi
if [ -n "$LISTEN_PID" ]; then
  DERIVED_PGID=$(ps -o pgid= -p "$LISTEN_PID" 2>/dev/null | tr -d ' ')
  if [ -n "$DERIVED_PGID" ]; then
    PGID="$DERIVED_PGID"
  fi
fi

echo "Stopping OpenMAIC (PGID $PGID, listener PID ${LISTEN_PID:-unknown})..."

# Kill the entire process group (kills all: pnpm, sh, node, next-server, postcss)
if [ -n "$PGID" ]; then
  kill -- "-$PGID" 2>/dev/null || true
fi
# Also kill the listener directly as fallback
if [ -n "$LISTEN_PID" ]; then
  kill "$LISTEN_PID" 2>/dev/null || true
fi

# Wait up to 5s for port 3000 to free
for i in $(seq 1 5); do
  if ! ss -tlnp 'sport = :3000' | grep -q 'pid='; then break; fi
  sleep 1
done

# Force-kill if port still occupied
if ss -tlnp 'sport = :3000' | grep -q 'pid='; then
  echo "Port 3000 still in use — sending SIGKILL..."
  REMAINING_PID=$(ss -tlnp 'sport = :3000' | grep -oP 'pid=\K\d+' | head -1)
  REMAINING_PGID=$(ps -o pgid= -p "$REMAINING_PID" 2>/dev/null | tr -d ' ')
  if [ -n "$REMAINING_PGID" ]; then
    kill -9 -- "-$REMAINING_PGID" 2>/dev/null || true
  fi
  kill -9 "$REMAINING_PID" 2>/dev/null || true
fi

rm -f "$PID_FILE"
echo "OpenMAIC stopped."
