# run.ps1
chcp 65001 > $null
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================" -ForegroundColor Green
Write-Host "DOCX Live Editor" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Конвертация CRLF -> LF
Get-ChildItem scripts\*.sh | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $content, [System.Text.UTF8Encoding]::new($false))
}

# Запуск контейнера
docker run -it --rm `
    -v "${PWD}:/app" `
    -w /app `
    -e LANG=C.UTF-8 `
    -e LC_ALL=C.UTF-8 `
    docx-live-arch ./scripts/docx_live_controller.sh

Write-Host ""
Write-Host "Нажмите любую клавишу для выхода..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
