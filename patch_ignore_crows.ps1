
$ErrorActionPreference = "Stop"

$p = "server\src\com\desertkun\brainout\bot\Task.java"

if (!(Test-Path $p)) {
    throw "Не найден файл: $p"
}

$src = Get-Content $p -Raw

$old = @'
            if (target == getPlayerData())
                return false;
'@

$new = @'
            if (target == getPlayerData())
                return false;

            // Freeplay bots must ignore crows.
            if (target.getCreator() != null &&
                "player-crow".equals(target.getCreator().getID()))
                return false;
'@

if (!$src.Contains($old)) {
    throw "Исходный участок не найден. Файл не изменён."
}

$backup = "$p.bak-before-ignore-crows"
if (!(Test-Path $backup)) {
    Copy-Item $p $backup
}

$src = $src.Replace($old, $new)
Set-Content -Path $p -Value $src -Encoding UTF8 -NoNewline

Write-Host "Готово. Вороны исключены из списка целей."
Write-Host "Резервная копия: $backup"
