#!/bin/bash
# preview_watch.sh – автообновляемый просмотр DOCX через опрос времени

if [ $# -ne 1 ]; then
    echo "Использование: $0 <путь_к_docx>"
    exit 1
fi

DOCX_FILE="$1"

if ! command -v doxx &>/dev/null; then
    echo "Ошибка: 'doxx' не установлен." >&2
    exit 1
fi

DOXX_PID=""
last_mtime=""

restart_doxx() {
    # Убить предыдущий процесс, если жив
    if [ -n "$DOXX_PID" ] && kill -0 "$DOXX_PID" 2>/dev/null; then
        kill "$DOXX_PID" 2>/dev/null
        wait "$DOXX_PID" 2>/dev/null
    fi
    clear                     # очистка экрана от старого вывода
    doxx "$DOCX_FILE" &       # запуск нового просмотрщика
    DOXX_PID=$!
}

# Первый запуск
restart_doxx
last_mtime=$(stat -c %Y "$DOCX_FILE" 2>/dev/null)

# Бесконечный цикл опроса
while true; do
    sleep 0.5
    current_mtime=$(stat -c %Y "$DOCX_FILE" 2>/dev/null)
    [ -z "$current_mtime" ] && continue   # файл временно недоступен – ждём
    if [ "$current_mtime" != "$last_mtime" ]; then
        last_mtime="$current_mtime"
        restart_doxx
    fi
done
