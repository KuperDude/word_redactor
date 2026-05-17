@echo off
chcp 65001 >nul
echo ========================================
echo DOCX Live Editor
echo ========================================
echo.

REM Проверяем, что Docker запущен
docker info >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: Docker Desktop не запущен!
    echo Пожалуйста, запустите Docker Desktop и повторите попытку.
    pause
    exit /b 1
)

echo 1. Конвертируем скрипты в Unix-формат (LF)...
powershell -Command "Get-ChildItem scripts\*.sh | ForEach-Object { $content = Get-Content $_.FullName -Raw; $content = $content -replace \"`r`n\", \"`n\"; [System.IO.File]::WriteAllText($_.FullName, $content, [System.Text.UTF8Encoding]::new($false)) }"
if errorlevel 1 (
    echo ПРЕДУПРЕЖДЕНИЕ: Не удалось сконвертировать скрипты, но продолжаем...
)

echo 2. Запускаем контейнер...
echo.

REM Запуск контейнера
docker run -it --rm -v "%cd%":/app -w /app docx-live-arch ./scripts/docx_live_controller.sh

REM Если контейнер завершился с ошибкой - показать сообщение
if errorlevel 1 (
    echo.
    echo ОШИБКА: Контейнер завершился с ошибкой.
    echo Проверьте, что образ собран: docker build -t docx-live-arch .
)

pause
