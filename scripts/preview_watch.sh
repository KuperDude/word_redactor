#!/bin/bash
# preview_watch.sh – auto-refreshing DOCX viewer via time polling

if [ $# -ne 1 ]; then
    echo "Usage: $0 <path_to_docx>"
    exit 1
fi

DOCX_FILE="$1"

if ! command -v doxx &>/dev/null; then
    echo "Error: 'doxx' is not installed." >&2
    exit 1
fi

DOXX_PID=""
last_mtime=""

restart_doxx() {
    # Kill previous process if alive
    if [ -n "$DOXX_PID" ] && kill -0 "$DOXX_PID" 2>/dev/null; then
        kill "$DOXX_PID" 2>/dev/null
        wait "$DOXX_PID" 2>/dev/null
    fi
    clear                     # clear screen from old output
    doxx "$DOCX_FILE" &       # start new viewer
    DOXX_PID=$!
}

# First run
restart_doxx
last_mtime=$(stat -c %Y "$DOCX_FILE" 2>/dev/null)

# Infinite polling loop
while true; do
    sleep 0.5
    current_mtime=$(stat -c %Y "$DOCX_FILE" 2>/dev/null)
    [ -z "$current_mtime" ] && continue   # file temporarily unavailable – wait
    if [ "$current_mtime" != "$last_mtime" ]; then
        last_mtime="$current_mtime"
        restart_doxx
    fi
done
