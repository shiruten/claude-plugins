#!/usr/bin/env bash
# Start/stop an iOS Simulator screen recording via simctl, tracked with a pid file.
# usage: rec.sh start <file.mp4> | rec.sh stop <file.mp4>
# Why not agent-device's own `record`? It loses ownership of the simctl process when other commands
# run in between and leaves a 0-byte file. Driving simctl directly and stopping it with SIGINT is reliable.
# Why touch the status bar? recordVideo writes a frame only when the screen changes, so a scene that ends on a
# static screen is cut at its last change and can lose that change entirely. `stop` changes the battery level twice
# just before SIGINT to flush it; `start` sets the same override so the battery icon looks alike in every scene.
# Undo it when done: xcrun simctl status_bar booted clear
set -euo pipefail
FILE=${2:?usage: rec.sh start|stop <file.mp4>}
battery() { xcrun simctl status_bar booted override --batteryLevel "$1" \
  || echo "status_bar override failed: a scene that ends on a static screen may be cut short" >&2; }
case "${1:-}" in
  start)
    if pgrep -f "simctl io .* recordVideo" >/dev/null; then
      echo "another recording is running: $(pgrep -fl 'recordVideo' | head -1)" >&2; exit 1
    fi
    battery 100; sleep 0.5   # before recording, so the style change is not part of the scene
    mkdir -p "$(dirname "$FILE")"
    nohup xcrun simctl io booted recordVideo --codec h264 --force "$FILE" >/dev/null 2>&1 &
    echo $! > "$FILE.pid"; sleep 1
    kill -0 "$(cat "$FILE.pid")" 2>/dev/null && echo "recording pid=$(cat "$FILE.pid") -> $FILE" \
      || { echo "could not start recording (is a simulator booted?)" >&2; exit 1; } ;;
  stop)
    PID=$(cat "$FILE.pid")
    battery 99; sleep 0.6; battery 100; sleep 0.8   # two tiny screen changes push the final state into the file
    kill -INT "$PID"
    for _ in $(seq 1 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done   # wait for the moov atom to be written
    kill -0 "$PID" 2>/dev/null && { echo "recorder did not exit pid=$PID" >&2; exit 1; }
    rm -f "$FILE.pid"
    printf '%s  %ss\n' "$FILE" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FILE")" ;;
  *) sed -n '2,3p' "$0"; exit 2 ;;
esac
