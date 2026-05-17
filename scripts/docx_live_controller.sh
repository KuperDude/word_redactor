#!/bin/bash
# docx_live_controller.sh – запуск live-генератора с автообновлением preview
# и автоматическим закрытием tmux-сессии после завершения генератора

SESSION_NAME="docx_live"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREVIEW_WATCH="$SCRIPT_DIR/preview_watch.sh"
GENERATOR="$SCRIPT_DIR/letter_generator_live.sh"
OUTPUT_DIR="$SCRIPT_DIR/../outputs"
PREVIEW_FILE="$OUTPUT_DIR/preview.docx"
FLAG_FILE="/tmp/docx_live_$$.flag"

for cmd in tmux doxx; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Ошибка: '$cmd' не установлен." >&2
        exit 1
    fi
done

mkdir -p "$OUTPUT_DIR"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null

# Создаём обёртку с trap на любые сигналы
WRAPPER_SCRIPT=$(mktemp)
cat > "$WRAPPER_SCRIPT" <<'EOF'
#!/bin/bash
FLAG_FILE="$1"
GENERATOR="$2"

# При любом выходе (нормальном или по сигналу) создаём флаг
cleanup() {
    touch "$FLAG_FILE"
    exit 0
}
trap cleanup EXIT SIGINT SIGTERM

# Запускаем генератор
"$GENERATOR"
EOF
chmod +x "$WRAPPER_SCRIPT"

# Создаём tmux-сессию
tmux new-session -d -s "$SESSION_NAME" -n "DOCX Live"
tmux split-window -h -t "$SESSION_NAME"

# Левая панель: обёртка с аргументами
tmux send-keys -t "$SESSION_NAME:0.0" "cd \"$SCRIPT_DIR\" && \"$WRAPPER_SCRIPT\" \"$FLAG_FILE\" \"$GENERATOR\"" Enter

# Правая панель: preview_watch с путём
tmux send-keys -t "$SESSION_NAME:0.1" "cd \"$SCRIPT_DIR\" && ./preview_watch.sh \"$PREVIEW_FILE\"" Enter

# Настройка размеров
tmux select-pane -t "$SESSION_NAME:0.0"
tmux resize-pane -t "$SESSION_NAME:0.0" -x 60%

# Фоновый монитор (проверка флага каждые 0.1 секунды)
(
    while [ ! -f "$FLAG_FILE" ]; do
        sleep 0.1
    done
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    rm -f "$FLAG_FILE"
) &
MONITOR_PID=$!

# Присоединяем пользователя
tmux attach -t "$SESSION_NAME"

# Очистка после выхода (если пользователь вышел вручную)
kill $MONITOR_PID 2>/dev/null
rm -f "$FLAG_FILE"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null
