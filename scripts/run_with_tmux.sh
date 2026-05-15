#!/bin/bash

SESSION_NAME="letter_generator"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux attach-session -t "$SESSION_NAME"
else
    tmux new-session -d -s "$SESSION_NAME" -n "generator"
    tmux send-keys -t "$SESSION_NAME:generator" "clear" Enter
    tmux send-keys -t "$SESSION_NAME:generator" "./letter_generator.sh" Enter
    tmux attach-session -t "$SESSION_NAME"
fi
