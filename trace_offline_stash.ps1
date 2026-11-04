$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot 'client\src\com\desertkun\brainout\menu\impl\MarketItemsCategoryMenu.java'

if (-not (Test-Path -LiteralPath $path)) {
    throw "File not found: $path"
}

$source = [IO.File]::ReadAllText($path)

function Add-TraceAfterMethodOpen {
    param(
        [string]$Text,
        [string]$Signature,
        [string]$Trace
    )

    $first = $Text.IndexOf($Signature)

    if ($first -lt 0) {
        throw "Method signature not found: $Signature"
    }

    if ($Text.IndexOf($Signature, $first + $Signature.Length) -ge 0) {
        throw "Method signature is not unique: $Signature"
    }

    $brace = $Text.IndexOf('{', $first + $Signature.Length)

    if ($brace -lt 0) {
        throw "Opening brace not found: $Signature"
    }

    return $Text.Insert(
        $brace + 1,
        [Environment]::NewLine + $Trace + [Environment]::NewLine
    )
}

$source = Add-TraceAfterMethodOpen `
    $source `
    'private boolean move(InventoryPanel.InventoryRecord record, int amount, InventoryPanel from, InventoryPanel to)' `
    '        com.badlogic.gdx.Gdx.app.error("OfflineStashTrace", "move called; online=" + BrainOut.OnlineEnabled() + ", from=" + (from == null ? "null" : from.getClass().getName()) + ", to=" + (to == null ? "null" : to.getClass().getName()));'

$source = Add-TraceAfterMethodOpen `
    $source `
    'private boolean putItemIntoMarket(ConsumableRecord record, int amount, MarketItemsInventoryPanel market)' `
    '        com.badlogic.gdx.Gdx.app.error("OfflineStashTrace", "putItemIntoMarket called; online=" + BrainOut.OnlineEnabled() + ", amount=" + amount + ", recordNull=" + (record == null));'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath $path -Destination "$path.bak-trace-$stamp"

$encoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($path, $source, $encoding)

Write-Output "Trace added. Backup timestamp: $stamp"