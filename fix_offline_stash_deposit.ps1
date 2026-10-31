$ErrorActionPreference = 'Stop'

$relativePath = 'client\src\com\desertkun\brainout\menu\impl\MarketItemsCategoryMenu.java'
$filePath = Join-Path $PSScriptRoot $relativePath

if (-not (Test-Path -LiteralPath $filePath)) {
    throw "Java source not found: $filePath"
}

$source = [System.IO.File]::ReadAllText($filePath)

$oldLine = '        int am = Math.min(market.canFitAnItem(record), amount);'
$newLine = '        int am = BrainOut.OnlineEnabled() ? Math.min(market.canFitAnItem(record), amount) : amount;'

$count = [regex]::Matches($source, [regex]::Escape($oldLine)).Count

if ($count -ne 1) {
    throw "Expected exactly one target line; found $count. File was not changed."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$filePath.bak-offline-deposit-$timestamp"

Copy-Item -LiteralPath $filePath -Destination $backupPath

$updatedSource = $source.Replace($oldLine, $newLine)

$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($filePath, $updatedSource, $encoding)

Write-Output 'Offline deposit check updated.'
Write-Output "Backup: $backupPath"