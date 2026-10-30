$ErrorActionPreference = 'Stop'

$relativePath = 'client\src\com\desertkun\brainout\menu\ui\MarketItemsInventoryPanel.java'
$filePath = Join-Path $PSScriptRoot $relativePath

if (-not (Test-Path -LiteralPath $filePath)) {
    throw "Java source not found: $filePath"
}

$source = [System.IO.File]::ReadAllText($filePath)

$pattern = '(?s)    private void requestItems\(\)\s*\{.*?(?=\r?\n    protected void updated\(float weight\))'
$matchesFound = [regex]::Matches($source, $pattern)

if ($matchesFound.Count -ne 1) {
    throw "Expected exactly one requestItems() method; found $($matchesFound.Count). File was not changed."
}

$replacement = @'
    private void requestItems()
    {
        if (!BrainOut.OnlineEnabled())
        {
            List<MarketService.MarketItemEntry> entries =
                com.desertkun.brainout.utils.LocalOfflineMarketStorage.getItems();

            stopLoading();
            renderItems(entries);

            if (itemsLoadedHook != null)
            {
                itemsLoadedHook.loaded(entries);
            }

            return;
        }

        LoginService loginService = LoginService.Get();
        MarketService marketService = MarketService.Get();

        marketService.getMarketItems(
            "freeplay",
            loginService.getCurrentAccessToken(),
            (request, result, entries) -> Gdx.app.postRunnable(() ->
            {
                stopLoading();

                if (result == Request.Result.success)
                {
                    renderItems(entries);

                    if (itemsLoadedHook != null)
                    {
                        itemsLoadedHook.loaded(entries);
                    }
                }
                else
                {
                    renderFailure();
                }
            })
        );
    }
'@

$updatedSource = [regex]::Replace(
    $source,
    $pattern,
    [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $replacement
    },
    1
)

if ($updatedSource -eq $source) {
    throw 'Source was not changed. Check the method before trying again.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$filePath.bak-before-fix-$timestamp"

Copy-Item -LiteralPath $filePath -Destination $backupPath

$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($filePath, $updatedSource, $encoding)

Write-Output "Offline stash panel updated."
Write-Output "Backup: $backupPath"