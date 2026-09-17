#!/usr/bin/env bash
# Start/stop an iOS Simulator screen recording via simctl, tracked with a pid file.
# usage: rec.sh start <file.mp4> | rec.sh stop <file.mp4>
# Why not agent-device's own `record`? It loses ownership of the simctl process when other commands
# run in between and leaves a 0-byte file. Driving simctl directly and stopping it with SIGINT is reliable.
set -euo pipefail
FILE=${2:?usage: rec.sh start|stop <file.mp4>}
case "${1:-}" in
  start)
    if pgrep -f "simctl io .* recordVideo" >/dev/null; then
      echo "another recording is running: $(pgrep -fl 'recordVideo' | head -1)" >&2; exit 1
    fi
    mkdir -p "$(dirname "$FILE")"
    nohup xcrun simctl io booted recordVideo --codec h264 --force "$FILE" >/dev/null 2>&1 &
    echo $! > "$FILE.pid"; sleep 1
    kill -0 "$(cat "$FILE.pid")" 2>/dev/null && echo "recording pid=$(cat "$FILE.pid") -> $FILE" \
      || { echo "could not start recording (is a simulator booted?)" >&2; exit 1; } ;;
  stop)
    PID=$(cat "$FILE.pid"); kill -INT "$PID"
    for _ in $(seq 1 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done   # wait for the moov atom to be written
    kill -0 "$PID" 2>/dev/null && { echo "recorder did not exit pid=$PID" >&2; exit 1; }
    rm -f "$FILE.pid"
    printf '%s  %ss\n' "$FILE" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FILE")" ;;
  *) sed -n '2,3p' "$0"; exit 2 ;;
esac
