#!/bin/bash
# docx_live_controller.sh – launch live generator with auto-refresh preview
# and automatic closing of tmux session after generator finishes

SESSION_NAME="docx_live"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_WATCH="$SCRIPT_DIR/preview_watch.sh"
GENERATOR="$SCRIPT_DIR/letter_generator_live.sh"
OUTPUT_DIR="$SCRIPT_DIR/../outputs"
PREVIEW_FILE="$OUTPUT_DIR/preview.docx"
FLAG_FILE="/tmp/docx_live_$$.flag"

for cmd in tmux doxx; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is not installed." >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null

# Create a wrapper with trap for any signals
WRAPPER_SCRIPT=$(mktemp)
cat > "$WRAPPER_SCRIPT" <<'EOF'
#!/bin/bash
FLAG_FILE="$1"
GENERATOR="$2"

# On any exit (normal or signal), create flag
cleanup() {
    touch "$FLAG_FILE"
    exit 0
}
trap cleanup EXIT SIGINT SIGTERM

# Run the generator
"$GENERATOR"
EOF
chmod +x "$WRAPPER_SCRIPT"

# Create tmux session
tmux new-session -d -s "$SESSION_NAME" -n "DOCX Live"
tmux split-window -h -t "$SESSION_NAME"

# Left pane: wrapper with arguments
tmux send-keys -t "$SESSION_NAME:0.0" "cd \"$SCRIPT_DIR\" && \"$WRAPPER_SCRIPT\" \"$FLAG_FILE\" \"$GENERATOR\"" Enter

# Right pane: preview_watch with path
tmux send-keys -t "$SESSION_NAME:0.1" "cd \"$SCRIPT_DIR\" && ./preview_watch.sh \"$PREVIEW_FILE\"" Enter

# Adjust sizes
tmux select-pane -t "$SESSION_NAME:0.0"
tmux resize-pane -t "$SESSION_NAME:0.0" -x 60%

# Background monitor (check flag every 0.1 seconds)
(
    while [ ! -f "$FLAG_FILE" ]; do
        sleep 0.1
    done
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    rm -f "$FLAG_FILE"
) &
MONITOR_PID=$!

# Attach user
tmux attach -t "$SESSION_NAME"

# Cleanup after exit (if user exited manually)
kill $MONITOR_PID 2>/dev/null
rm -f "$FLAG_FILE"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null
