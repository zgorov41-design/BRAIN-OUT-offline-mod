$ErrorActionPreference = 'Stop'

$storagePath = Join-Path $PSScriptRoot 'client\src\com\desertkun\brainout\utils\LocalOfflineMarketStorage.java'
$menuPath = Join-Path $PSScriptRoot 'client\src\com\desertkun\brainout\menu\impl\MarketItemsCategoryMenu.java'

foreach ($path in @($storagePath, $menuPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Source file not found: $path"
    }
}

$storage = [IO.File]::ReadAllText($storagePath)
$menu = [IO.File]::ReadAllText($menuPath)

$storagePattern = '(?s)    public static synchronized boolean deposit\(ConsumableRecord record, int amount,\s*ConsumableContainer source\)\s*\{.*?(?=\r?\n    public static synchronized boolean withdraw\()'

$menuPattern = '(?s)            if \(owner == null \|\| !com\.desertkun\.brainout\.utils\.LocalOfflineMarketStorage\.deposit\(\s*record, am, owner\.getConsumableContainer\(\)\)\)\s*\{\s*Menu\.playSound\(MenuSound\.denied\);\s*return false;\s*\}'

if ([regex]::Matches($storage, $storagePattern).Count -ne 1) {
    throw 'Could not uniquely locate deposit() in storage file. No files changed.'
}

if ([regex]::Matches($menu, $menuPattern).Count -ne 1) {
    throw 'Could not uniquely locate the offline deposit check in menu file. No files changed.'
}

$storageReplacement = @'
    public static synchronized boolean deposit(ConsumableRecord record, int amount,
                                                ConsumableContainer source)
    {
        if (record == null)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: record is null.");
            return false;
        }

        if (source == null)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: source container is null.");
            return false;
        }

        if (amount <= 0 || record.getAmount() < amount)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: invalid amount="
                + amount + ", record amount=" + record.getAmount());
            return false;
        }

        MarketService.MarketItemEntry entry =
            MarketUtils.ConsumableRecordToMarketEntry(record);

        if (entry == null || entry.name == null || entry.payload == null)
        {
            String itemClass = record.getItem() == null
                ? "null" : record.getItem().getClass().getName();

            String contentId = record.getItem() == null
                || record.getItem().getContent() == null
                ? "null" : record.getItem().getContent().getID();

            Gdx.app.error("OfflineStash", "Deposit rejected: unsupported item. class="
                + itemClass + ", content=" + contentId);
            return false;
        }

        ConsumableContainer.AcquiredConsumables acquired =
            source.getConsumable(amount, record);

        if (acquired == null)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: extraction returned null.");
            return false;
        }

        JSONArray items = load();
        JSONObject stored = new JSONObject();
        stored.put("name", entry.name);
        stored.put("payload", entry.payload.toString());
        stored.put("amount", amount);
        items.put(stored);
        save(items);

        Gdx.app.log("OfflineStash", "Deposit saved: " + entry.name
            + ", amount=" + amount);

        return true;
    }
'@

$menuReplacement = @'
            if (owner == null)
            {
                com.badlogic.gdx.Gdx.app.error("OfflineStash",
                    "Deposit rejected: PlayerOwnerComponent is null.");
                Menu.playSound(MenuSound.denied);
                return false;
            }

            if (!com.desertkun.brainout.utils.LocalOfflineMarketStorage.deposit(
                record, am, owner.getConsumableContainer()))
            {
                Menu.playSound(MenuSound.denied);
                return false;
            }
'@

$newStorage = [regex]::Replace(
    $storage, $storagePattern,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $storageReplacement },
    1
)

$newMenu = [regex]::Replace(
    $menu, $menuPattern,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $menuReplacement },
    1
)

if ($newStorage -eq $storage -or $newMenu -eq $menu) {
    throw 'A replacement made no changes. Original files remain untouched.'
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $storagePath "$storagePath.bak-diagnose-$stamp"
Copy-Item $menuPath "$menuPath.bak-diagnose-$stamp"

$encoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($storagePath, $newStorage, $encoding)
[IO.File]::WriteAllText($menuPath, $newMenu, $encoding)

Write-Output 'Offline stash diagnostics added.'
Write-Output "Backups created with timestamp: $stamp"