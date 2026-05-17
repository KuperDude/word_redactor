@echo off
docker run -it --rm -v "%cd%":/app -w /app docx-live-arch ./scripts/docx_live_controller.sh
pause
