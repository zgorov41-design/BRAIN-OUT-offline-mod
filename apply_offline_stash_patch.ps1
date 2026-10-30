$ErrorActionPreference = 'Stop'

$panelPath = Join-Path (Get-Location).Path 'client\src\com\desertkun\brainout\menu\ui\MarketItemsInventoryPanel.java'
$menuPath  = Join-Path (Get-Location).Path 'client\src\com\desertkun\brainout\menu\impl\MarketItemsCategoryMenu.java'
$helperPath = Join-Path (Get-Location).Path 'client\src\com\desertkun\brainout\utils\LocalOfflineMarketStorage.java'

if (!(Test-Path -LiteralPath $panelPath) -or !(Test-Path -LiteralPath $menuPath)) {
    throw 'Run this script from the brainout project root (the folder containing client\src).'
}

$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
function Save-Text([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $script:utf8NoBom)
}
function Backup-File([string]$Path) {
    $backup = "$Path.bak-offline-stash"
    if (Test-Path -LiteralPath $backup) {
        $backup = "$Path.bak-offline-stash-$(Get-Date -Format yyyyMMdd-HHmmss)"
    }
    Copy-Item -LiteralPath $Path -Destination $backup
    Write-Host "Backup: $backup"
}

$helper = @'
package com.desertkun.brainout.utils;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Preferences;
import com.desertkun.brainout.BrainOut;
import com.desertkun.brainout.data.consumable.AcquiredConsumables;
import com.desertkun.brainout.data.consumable.ConsumableContainer;
import com.desertkun.brainout.data.consumable.ConsumableRecord;
import org.anthillplatform.runtime.services.MarketService;
import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/** Local, persistent storage for the offline market stash. */
public final class LocalOfflineMarketStorage
{
    private static final String KEY = "items";

    private LocalOfflineMarketStorage() {}

    private static Preferences preferences()
    {
        String profile = BrainOut.Env.getUniqueId();
        return Gdx.app.getPreferences("brainout-offline-stash-" + profile);
    }

    private static JSONArray load()
    {
        try
        {
            return new JSONArray(preferences().getString(KEY, "[]"));
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Could not read local stash; starting empty.", e);
            return new JSONArray();
        }
    }

    private static void save(JSONArray items)
    {
        Preferences preferences = preferences();
        preferences.putString(KEY, items.toString());
        preferences.flush();
    }

    public static synchronized List<MarketService.MarketItemEntry> getItems()
    {
        List<MarketService.MarketItemEntry> result = new ArrayList<>();
        JSONArray items = load();

        for (int i = 0; i < items.length(); i++)
        {
            try
            {
                JSONObject stored = items.getJSONObject(i);
                String name = stored.getString("name");
                String payloadText = stored.getString("payload");
                int amount = stored.getInt("amount");
                if (amount <= 0) continue;

                ConsumableRecord record = MarketUtils.MarketObjectToConsumableRecord(
                    name, new JSONObject(payloadText), amount);
                if (record == null) continue;

                MarketService.MarketItemEntry entry = MarketUtils.ConsumableRecordToMarketEntry(record);
                if (entry != null) result.add(entry);
            }
            catch (Exception e)
            {
                Gdx.app.error("OfflineStash", "Skipping an invalid local stash entry.", e);
            }
        }

        return result;
    }

    public static synchronized boolean deposit(ConsumableRecord record, int amount,
                                                ConsumableContainer source)
    {
        if (record == null || source == null || amount <= 0 || record.getAmount() < amount)
            return false;

        MarketService.MarketItemEntry entry = MarketUtils.ConsumableRecordToMarketEntry(record);
        if (entry == null || entry.name == null || entry.payload == null)
            return false;

        // Extract from the player inventory first; the market payload above captures the item.
        AcquiredConsumables acquired = source.getConsumable(amount, record);
        if (acquired == null) return false;

        JSONArray items = load();
        JSONObject stored = new JSONObject();
        stored.put("name", entry.name);
        stored.put("payload", entry.payload.toString());
        stored.put("amount", amount);
        items.put(stored);
        save(items);
        return true;
    }

    public static synchronized boolean withdraw(MarketService.MarketItemEntry entry, int amount,
                                                 ConsumableContainer target)
    {
        if (entry == null || entry.name == null || entry.payload == null || target == null || amount <= 0)
            return false;

        String requestedPayload = entry.payload.toString();
        JSONArray items = load();

        for (int i = 0; i < items.length(); i++)
        {
            JSONObject stored;
            try
            {
                stored = items.getJSONObject(i);
            }
            catch (Exception ignored)
            {
                continue;
            }

            try
            {
                if (!entry.name.equals(stored.getString("name"))) continue;
                String payloadText = stored.getString("payload");
                if (!samePayload(payloadText, requestedPayload)) continue;

                int storedAmount = stored.getInt("amount");
                if (storedAmount < amount) return false;

                ConsumableRecord restored = MarketUtils.MarketObjectToConsumableRecord(
                    entry.name, new JSONObject(payloadText), amount);
                if (restored == null || restored.getItem() == null) return false;

                // IDs in the stash and player inventory are separate, so allocate a fresh inventory ID.
                restored.setId(target.newId());
                target.addRecord(restored);

                if (storedAmount == amount)
                {
                    JSONArray remaining = new JSONArray();
                    for (int j = 0; j < items.length(); j++)
                    {
                        if (j != i) remaining.put(items.get(j));
                    }
                    items = remaining;
                }
                else
                {
                    stored.put("amount", storedAmount - amount);
                }

                save(items);
                return true;
            }
            catch (Exception e)
            {
                Gdx.app.error("OfflineStash", "Could not withdraw local stash entry.", e);
                return false;
            }
        }

        return false;
    }

    private static boolean samePayload(String first, String second)
    {
        try
        {
            return new JSONObject(first).toString().equals(new JSONObject(second).toString());
        }
        catch (Exception ignored)
        {
            return first.equals(second);
        }
    }
}
'@

# Back up all edited files before patching.
Backup-File $panelPath
Backup-File $menuPath
if (Test-Path -LiteralPath $helperPath) { Backup-File $helperPath }

# Patch offline panel loading: use the persistent local stash instead of expecting PointData to be ItemData.
$panel = [System.IO.File]::ReadAllText($panelPath)
$panelPattern = '(?s)        if \(!BrainOut\.OnlineEnabled\(\)\)\s*\{.*?\n        \}\s*\n\s*LoginService loginService = LoginService\.Get\(\);'
$panelReplacement = @'
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
'@
$panelUpdated = [regex]::Replace($panel, $panelPattern, $panelReplacement, 1)
if ($panelUpdated -eq $panel) { throw 'Could not locate the offline branch in MarketItemsInventoryPanel.java; no source edits were applied after backups.' }

# Patch deposit method with an offline branch while keeping the online service request untouched.
$putPattern = '(?s)    private boolean putItemIntoMarket\(ConsumableRecord record, int amount, MarketItemsInventoryPanel market\)\s*\{.*?\n    \}'
$putReplacement = @'
    private boolean putItemIntoMarket(ConsumableRecord record, int amount, MarketItemsInventoryPanel market)
    {
        int am = Math.min(market.canFitAnItem(record), amount);

        if (am == 0)
        {
            return false;
        }

        if (!BrainOut.OnlineEnabled())
        {
            com.desertkun.brainout.components.PlayerOwnerComponent owner =
                playerData.getComponent(com.desertkun.brainout.components.PlayerOwnerComponent.class);

            if (owner == null || !com.desertkun.brainout.utils.LocalOfflineMarketStorage.deposit(
                record, am, owner.getConsumableContainer()))
            {
                Menu.playSound(MenuSound.denied);
                return false;
            }

            InventoryMoveSoundComponent snd = record.getItem().getContent()
                .getComponent(InventoryMoveSoundComponent.class);
            if (snd != null) snd.play(playerData);
            market.refresh();
            return true;
        }

        JSONObject args = new JSONObject();

        args.put("market", market.getMarket());
        args.put("id", record.getId());
        args.put("amount", am);

        BrainOutClient.SocialController.sendRequest("put_market_item", args,
            new SocialController.RequestCallback()
        {
            @Override
            public void success(JSONObject response)
            {
                InventoryMoveSoundComponent snd = record.getItem().getContent().getComponent(InventoryMoveSoundComponent.class);

                if (snd != null)
                {
                    snd.play(playerData);
                }

                market.refresh();
            }

            @Override
            public void error(String reason)
            {
                if (Log.ERROR) Log.error(reason);
                Menu.playSound(MenuSound.denied);
            }
        });

        return true;
    }
'@
$menu = [System.IO.File]::ReadAllText($menuPath)
$menuUpdated = [regex]::Replace($menu, $putPattern, $putReplacement, 1)
if ($menuUpdated -eq $menu) { throw 'Could not locate putItemIntoMarket method in MarketItemsCategoryMenu.java.' }

# Patch withdrawal method with an offline branch while keeping the online service request untouched.
$withdrawPattern = '(?s)    private boolean withdrawItemFromMarket\(\s*MarketItemsInventoryPanel\.MarketInventoryRecord record, int amount, MarketItemsInventoryPanel market\)\s*\{.*?\n    \}'
$withdrawReplacement = @'
    private boolean withdrawItemFromMarket(
        MarketItemsInventoryPanel.MarketInventoryRecord record, int amount, MarketItemsInventoryPanel market)
    {
        Content c = record.getRecord().getItem().getContent();
        if (c == null)
            return false;

        if (!BrainOut.OnlineEnabled())
        {
            com.desertkun.brainout.components.PlayerOwnerComponent owner =
                playerData.getComponent(com.desertkun.brainout.components.PlayerOwnerComponent.class);

            if (owner == null || !com.desertkun.brainout.utils.LocalOfflineMarketStorage.withdraw(
                record.getMarketEntry(), amount, owner.getConsumableContainer()))
            {
                Menu.playSound(MenuSound.denied);
                return false;
            }

            InventoryMoveSoundComponent snd = c.getComponent(InventoryMoveSoundComponent.class);
            if (snd != null) snd.play(playerData);
            market.refresh();
            return true;
        }

        JSONObject args = new JSONObject();

        args.put("market", market.getMarket());
        args.put("item", record.getMarketEntry().name);
        args.put("payload", record.getMarketEntry().payload);
        args.put("amount", amount);

        BrainOutClient.SocialController.sendRequest("withdraw_market_item", args,
            new SocialController.RequestCallback()
        {
            @Override
            public void success(JSONObject response)
            {
                InventoryMoveSoundComponent snd = c.getComponent(InventoryMoveSoundComponent.class);

                if (snd != null)
                {
                    snd.play(playerData);
                }

                market.refresh();
            }

            @Override
            public void error(String reason)
            {
                Menu.playSound(MenuSound.denied);
            }
        });

        return true;
    }
'@
$menuFinal = [regex]::Replace($menuUpdated, $withdrawPattern, $withdrawReplacement, 1)
if ($menuFinal -eq $menuUpdated) { throw 'Could not locate withdrawItemFromMarket method in MarketItemsCategoryMenu.java.' }

# Write modified sources only after all target patterns matched.
Save-Text $panelPath $panelUpdated
Save-Text $menuPath $menuFinal
Save-Text $helperPath $helper

Write-Host ''
Write-Host 'Offline stash patch applied.' -ForegroundColor Green
Write-Host 'It adds Preferences-backed local storage and switches stash list/deposit/withdraw to local operations when online mode is disabled.'
Write-Host 'Next, compile the client module and test deposit/withdraw in offline mode. This patch has not been compiled in your environment.'
