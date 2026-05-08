#!/usr/bin/env bash
# copilot-api.sh — build, install, start (daemon), stop management script

set -euo pipefail

BINARY_NAME="copilot-api"
INSTALL_DIR="/usr/local/bin"
PID_FILE="/tmp/copilot-api.pid"
LOG_DIR="${COPILOT_API_LOG_DIR:-/tmp}"
LOG_FILE="$LOG_DIR/copilot-api.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  install              Build and install the binary to $INSTALL_DIR
  start [args...]      Start copilot-api as a background daemon
  stop                 Stop the running daemon
  restart [args...]    Stop then start
  status               Show daemon status and recent logs
  logs                 Tail daemon logs
  uninstall            Remove the installed binary

Environment variables:
  COPILOT_API_LOG_DIR  Log directory (default: /tmp)

Examples:
  $(basename "$0") install
  $(basename "$0") start --port 12345 --github-token ghp_xxx
  $(basename "$0") start --port 12345             # if token is already saved
  $(basename "$0") stop
  $(basename "$0") logs
EOF
}

cmd_install() {
  echo "==> Installing dependencies..."
  cd "$SCRIPT_DIR"
  bun install

  echo "==> Building copilot-api binary..."
  bun build ./src/main.ts --compile --outfile "$BINARY_NAME"

  echo "==> Installing to $INSTALL_DIR/$BINARY_NAME (may require sudo)..."
  if [ -w "$INSTALL_DIR" ]; then
    mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
  else
    sudo mv "$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"
  fi

  echo "==> Done. Run 'copilot-api --help' to verify."
}

cmd_start() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "copilot-api is already running (PID $pid). Use 'stop' first."
      exit 1
    fi
    rm -f "$PID_FILE"
  fi

  mkdir -p "$LOG_DIR"
  echo "==> Starting copilot-api in background..."
  echo "    Log: $LOG_FILE"
  nohup "$INSTALL_DIR/$BINARY_NAME" start "$@" > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "==> Started (PID $(cat "$PID_FILE"))"
}

cmd_stop() {
  if [ ! -f "$PID_FILE" ]; then
    echo "No PID file found. copilot-api may not be running."
    exit 0
  fi

  local pid
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "==> Stopping copilot-api (PID $pid)..."
    kill "$pid"
    rm -f "$PID_FILE"
    echo "==> Stopped."
  else
    echo "Process $pid is not running. Cleaning up PID file."
    rm -f "$PID_FILE"
  fi
}

cmd_restart() {
  cmd_stop || true
  sleep 1
  cmd_start "$@"
}

cmd_status() {
  if [ ! -f "$PID_FILE" ]; then
    echo "Status: stopped (no PID file)"
    return
  fi

  local pid
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "Status: running (PID $pid)"
    echo "Log:    $LOG_FILE"
    echo ""
    echo "--- Recent logs ---"
    tail -n 20 "$LOG_FILE" 2>/dev/null || echo "(no log yet)"
  else
    echo "Status: stopped (stale PID $pid)"
    rm -f "$PID_FILE"
  fi
}

cmd_logs() {
  if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found at $LOG_FILE"
    exit 1
  fi
  tail -f "$LOG_FILE"
}

cmd_uninstall() {
  if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    echo "==> Removing $INSTALL_DIR/$BINARY_NAME..."
    if [ -w "$INSTALL_DIR" ]; then
      rm -f "$INSTALL_DIR/$BINARY_NAME"
    else
      sudo rm -f "$INSTALL_DIR/$BINARY_NAME"
    fi
    echo "==> Uninstalled."
  else
    echo "Binary not found at $INSTALL_DIR/$BINARY_NAME"
  fi
}

# ---- dispatch ----

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  install)    cmd_install ;;
  start)      cmd_start "$@" ;;
  stop)       cmd_stop ;;
  restart)    cmd_restart "$@" ;;
  status)     cmd_status ;;
  logs)       cmd_logs ;;
  uninstall)  cmd_uninstall ;;
  -h|--help|help) usage ;;
  *)
    echo "Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac
