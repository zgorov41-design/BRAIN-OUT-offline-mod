package com.desertkun.brainout.utils;

import com.badlogic.gdx.Gdx;
import com.badlogic.gdx.Preferences;
import com.desertkun.brainout.BrainOut;
import com.desertkun.brainout.data.consumable.ConsumableContainer;
import com.desertkun.brainout.data.consumable.ConsumableRecord;
import org.anthillplatform.runtime.services.MarketService;
import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * Persistent, profile-local storage for Freeplay items.
 *
 * The JSON format is deliberately kept compatible with earlier versions:
 * each entry contains name, payload (as JSON text) and amount.
 */
public final class LocalOfflineMarketStorage
{
    private static final String KEY = "items";
    private static final String PENDING_KEY = "pending-deposits";
    private static final String PREFERENCES_PREFIX = "brainout-offline-stash-";

    private LocalOfflineMarketStorage()
    {
    }

    private static Preferences preferences()
    {
        String profile = BrainOut.Env != null ? BrainOut.Env.getUniqueId() : null;
        // Keep the old "null" suffix for installations whose environment has no profile ID.
        return Gdx.app.getPreferences(PREFERENCES_PREFIX + String.valueOf(profile));
    }

    private static JSONArray load()
    {
        try
        {
            String value = preferences().getString(KEY, "[]");
            return new JSONArray(value);
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Could not read local stash; changes are disabled to protect saved items.", e);
            throw new IllegalStateException("Local Freeplay stash is unreadable.", e);
        }
    }

    private static void save(JSONArray items)
    {
        Preferences prefs = preferences();
        prefs.putString(KEY, items.toString());
        prefs.flush();
    }

    private static JSONArray loadPending()
    {
        try
        {
            return new JSONArray(preferences().getString(PENDING_KEY, "[]"));
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Could not read pending stash transfers.", e);
            throw new IllegalStateException("Pending Freeplay stash transfers are unreadable.", e);
        }
    }

    private static void savePending(JSONArray pending)
    {
        Preferences prefs = preferences();
        prefs.putString(PENDING_KEY, pending.toString());
        prefs.flush();
    }

    private static int countMatchingInventory(ConsumableContainer source, String name, JSONObject payload)
    {
        long total = 0;

        for (com.badlogic.gdx.utils.ObjectMap.Entry<Integer, ConsumableRecord> item : source.getData())
        {
            ConsumableRecord record = item.value;
            if (record == null || record.getAmount() <= 0)
            {
                continue;
            }

            MarketService.MarketItemEntry candidate = MarketUtils.ConsumableRecordToMarketEntry(record);
            if (candidate != null && name.equals(candidate.name) && samePayload(candidate.payload, payload))
            {
                total += record.getAmount();
            }
        }

        return (int)Math.min(total, Integer.MAX_VALUE);
    }

    private static void mergePending(JSONArray pending, String name, JSONObject payload,
                                     int amountBeforeDeposit, int amount)
    {
        int index = findStoredItem(pending, name, payload);

        if (index >= 0)
        {
            JSONObject stored = pending.getJSONObject(index);
            int currentAmount = stored.optInt("amount", 0);

            if (currentAmount < 0 || currentAmount > Integer.MAX_VALUE - amount)
            {
                throw new IllegalArgumentException("Pending stash amount overflow.");
            }

            stored.put("amount", currentAmount + amount);
            // Preserve the inventory baseline from the first deposit of this stack.
            if (stored.optInt("before", 0) <= 0)
            {
                stored.put("before", amountBeforeDeposit);
            }
            stored.put("payload", payload.toString());
            return;
        }

        JSONObject stored = new JSONObject();
        stored.put("name", name);
        stored.put("payload", payload.toString());
        stored.put("amount", amount);
        stored.put("before", amountBeforeDeposit);
        pending.put(stored);
    }

    private static void reducePending(JSONArray pending, String name, JSONObject payload, int amount)
    {
        int index = findStoredItem(pending, name, payload);
        if (index < 0)
        {
            return;
        }

        JSONObject stored = pending.optJSONObject(index);
        int currentAmount = stored != null ? stored.optInt("amount", 0) : 0;

        if (currentAmount <= amount)
        {
            pending.remove(index);
        }
        else
        {
            stored.put("amount", currentAmount - amount);
        }
    }

    /**
     * Reconciles deposits when a fresh offline Freeplay player inventory is spawned.
     * A deposit can be absent from the newly created inventory object even though the
     * source inventory was correctly reduced before leaving the previous zone.
     */
    public static synchronized void reconcilePendingDeposits(ConsumableContainer target)
    {
        if (target == null)
        {
            return;
        }

        final JSONArray pending;
        try
        {
            pending = loadPending();
        }
        catch (Exception e)
        {
            return;
        }

        if (pending.length() == 0)
        {
            return;
        }

        boolean inventoryChanged = false;

        for (int i = 0; i < pending.length(); i++)
        {
            JSONObject stored = pending.optJSONObject(i);
            if (stored == null)
            {
                continue;
            }

            String name = stored.optString("name", "");
            int amount = stored.optInt("amount", 0);
            int before = stored.optInt("before", 0);
            JSONObject payload = readPayload(stored);

            if (name.isEmpty() || amount <= 0 || before <= 0 || payload == null)
            {
                continue;
            }

            int currentAmount = countMatchingInventory(target, name, payload);

            // If the current inventory is already below the pre-deposit baseline,
            // it retained the removal; do not subtract the same deposit twice.
            if (currentAmount < before)
            {
                continue;
            }

            List<ConsumableRecord> matching = new ArrayList<>();
            for (com.badlogic.gdx.utils.ObjectMap.Entry<Integer, ConsumableRecord> item : target.getData())
            {
                ConsumableRecord record = item.value;
                if (record == null || record.getAmount() <= 0)
                {
                    continue;
                }

                MarketService.MarketItemEntry candidate = MarketUtils.ConsumableRecordToMarketEntry(record);
                if (candidate != null && name.equals(candidate.name) && samePayload(candidate.payload, payload))
                {
                    matching.add(record);
                }
            }

            int remaining = amount;
            for (ConsumableRecord record : matching)
            {
                if (remaining <= 0)
                {
                    break;
                }

                if (target.get(record.getId()) != record)
                {
                    continue;
                }

                int take = Math.min(remaining, record.getAmount());
                ConsumableContainer.AcquiredConsumables acquired = target.getConsumable(take, record);
                remaining -= acquired.amount;
            }

            if (remaining == 0)
            {
                inventoryChanged = true;
                Gdx.app.log("OfflineStash", "Reconciled pending deposit: " + amount + " x " + name);
            }
            else
            {
                Gdx.app.error("OfflineStash", "Could not fully reconcile pending deposit: " + name);
            }
        }

        try
        {
            // Pending deductions are one-shot. If the source inventory already retained
            // the removal, the baseline check above deliberately leaves it unchanged.
            savePending(new JSONArray());
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Could not clear reconciled pending deposits.", e);
        }

        if (inventoryChanged)
        {
            target.updateWeight();
        }
    }

    private static JSONObject readPayload(JSONObject stored)
    {
        Object value = stored.opt("payload");

        if (value instanceof JSONObject)
        {
            return new JSONObject(value.toString());
        }

        if (value instanceof String)
        {
            return new JSONObject((String) value);
        }

        return null;
    }

    private static boolean samePayload(JSONObject first, JSONObject second)
    {
        if (first == null || second == null)
        {
            return false;
        }

        try
        {
            return new JSONObject(first.toString()).toString()
                .equals(new JSONObject(second.toString()).toString());
        }
        catch (Exception ignored)
        {
            return false;
        }
    }

    private static int findStoredItem(JSONArray items, String name, JSONObject payload)
    {
        for (int i = 0; i < items.length(); i++)
        {
            JSONObject stored = items.optJSONObject(i);
            if (stored == null || !name.equals(stored.optString("name", "")))
            {
                continue;
            }

            if (samePayload(readPayload(stored), payload))
            {
                return i;
            }
        }

        return -1;
    }

    private static void mergeItem(JSONArray items, String name, JSONObject payload, int amount)
    {
        int index = findStoredItem(items, name, payload);

        if (index >= 0)
        {
            JSONObject stored = items.optJSONObject(index);
            int currentAmount = stored.optInt("amount", 0);
            if (currentAmount < 0 || currentAmount > Integer.MAX_VALUE - amount)
            {
                throw new IllegalArgumentException("Stash amount overflow.");
            }
            stored.put("amount", currentAmount + amount);
            // Normalize legacy payload objects back to the existing string format.
            stored.put("payload", payload.toString());
            return;
        }

        JSONObject stored = new JSONObject();
        stored.put("name", name);
        stored.put("payload", payload.toString());
        stored.put("amount", amount);
        items.put(stored);
    }

    public static synchronized List<MarketService.MarketItemEntry> getItems()
    {
        List<MarketService.MarketItemEntry> result = new ArrayList<>();
        JSONArray items;
        try
        {
            items = load();
        }
        catch (Exception e)
        {
            return result;
        }

        for (int i = 0; i < items.length(); i++)
        {
            try
            {
                JSONObject stored = items.getJSONObject(i);
                String name = stored.optString("name", "");
                int amount = stored.optInt("amount", 0);
                JSONObject payload = readPayload(stored);

                if (name.isEmpty() || amount <= 0 || payload == null)
                {
                    continue;
                }

                int matchingIndex = -1;
                for (int j = 0; j < result.size(); j++)
                {
                    MarketService.MarketItemEntry existing = result.get(j);
                    if (name.equals(existing.name) && samePayload(existing.payload, payload))
                    {
                        matchingIndex = j;
                        break;
                    }
                }

                if (matchingIndex >= 0)
                {
                    MarketService.MarketItemEntry existing = result.get(matchingIndex);
                    long mergedAmount = (long) existing.amount + amount;
                    if (mergedAmount <= Integer.MAX_VALUE)
                    {
                        result.set(matchingIndex, new MarketService.MarketItemEntry(
                            name, (int) mergedAmount, payload));
                    }
                }
                else
                {
                    result.add(new MarketService.MarketItemEntry(name, amount, payload));
                }
            }
            catch (Exception e)
            {
                Gdx.app.error("OfflineStash", "Skipping an invalid local stash entry.", e);
            }
        }

        return result;
    }

    /**
     * Saves the item before removing it from the player's inventory. This way a
     * failed local write cannot silently destroy the player's item.
     */
    public static synchronized boolean deposit(ConsumableRecord record, int amount,
                                                ConsumableContainer source)
    {
        if (record == null || source == null || record.getItem() == null
            || record.getItem().getContent() == null || amount <= 0
            || record.getAmount() < amount || source.get(record.getId()) != record)
        {
            return false;
        }

        MarketService.MarketItemEntry entry =
            MarketUtils.ConsumableRecordToMarketEntry(record);

        if (entry == null || entry.name == null || entry.payload == null)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: item cannot be serialized.");
            return false;
        }

        final JSONArray previous;
        final JSONArray updated;
        final JSONArray previousPending;
        final JSONArray updatedPending;
        final int inventoryAmountBefore;
        try
        {
            previous = load();
            updated = new JSONArray(previous.toString());
            previousPending = loadPending();
            updatedPending = new JSONArray(previousPending.toString());
            inventoryAmountBefore = countMatchingInventory(source, entry.name, entry.payload);
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: local stash data could not be read.", e);
            return false;
        }

        if (inventoryAmountBefore < amount)
        {
            Gdx.app.error("OfflineStash", "Deposit rejected: matching inventory amount could not be verified.");
            return false;
        }

        try
        {
            mergeItem(updated, entry.name, entry.payload, amount);
            mergePending(updatedPending, entry.name, entry.payload, inventoryAmountBefore, amount);
            save(updated);
            savePending(updatedPending);
        }
        catch (Exception e)
        {
            try
            {
                save(previous);
                savePending(previousPending);
            }
            catch (Exception rollbackError)
            {
                Gdx.app.error("OfflineStash", "Could not restore stash data after a failed deposit write.", rollbackError);
            }

            Gdx.app.error("OfflineStash", "Could not save item to local stash.", e);
            return false;
        }

        int sourceAmountBefore = record.getAmount();
        try
        {
            ConsumableContainer.AcquiredConsumables acquired =
                source.getConsumable(amount, record);

            if (acquired == null || acquired.amount != amount)
            {
                boolean sourceChanged = source.get(record.getId()) != record
                    || record.getAmount() != sourceAmountBefore;

                if (!sourceChanged)
                {
                    try
                    {
                        save(previous);
                        savePending(previousPending);
                    }
                    catch (Exception rollbackError)
                    {
                        Gdx.app.error("OfflineStash", "Could not roll back an incomplete deposit.", rollbackError);
                    }
                }

                Gdx.app.error("OfflineStash", "Deposit extraction was incomplete.");
                return sourceChanged;
            }
        }
        catch (Exception e)
        {
            boolean sourceChanged = source.get(record.getId()) != record
                || record.getAmount() != sourceAmountBefore;

            if (!sourceChanged)
            {
                try
                {
                    save(previous);
                    savePending(previousPending);
                }
                catch (Exception rollbackError)
                {
                    Gdx.app.error("OfflineStash", "Could not roll back a failed deposit.", rollbackError);
                }
            }

            Gdx.app.error("OfflineStash", "Inventory extraction failed during local deposit.", e);
            return sourceChanged;
        }

        try
        {
            source.updateWeight();
        }
        catch (Exception e)
        {
            // The item has already been moved and saved. A display-weight error must
            // not remove its only durable copy.
            Gdx.app.error("OfflineStash", "Deposited item, but inventory weight update failed.", e);
        }

        Gdx.app.log("OfflineStash", "Deposited " + amount + " x " + entry.name);
        return true;
    }

    /**
     * Adds the restored item to the inventory first, then commits the reduced
     * stash. If the disk write fails, the newly added inventory record is removed.
     */
    public static synchronized boolean withdraw(MarketService.MarketItemEntry entry, int amount,
                                                  ConsumableContainer target)
    {
        if (entry == null || entry.name == null || entry.payload == null
            || target == null || amount <= 0)
        {
            return false;
        }

        final JSONArray previous;
        final JSONArray updated;
        final JSONArray previousPending;
        final JSONArray updatedPending;
        try
        {
            previous = load();
            updated = new JSONArray(previous.toString());
            previousPending = loadPending();
            updatedPending = new JSONArray(previousPending.toString());
            reducePending(updatedPending, entry.name, entry.payload, amount);
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Withdrawal rejected: local stash data could not be read.", e);
            return false;
        }

        int index = findStoredItem(updated, entry.name, entry.payload);

        if (index < 0)
        {
            return false;
        }

        JSONObject stored = updated.optJSONObject(index);
        int storedAmount = stored != null ? stored.optInt("amount", 0) : 0;

        if (storedAmount < amount)
        {
            return false;
        }

        ConsumableRecord restored;
        try
        {
            JSONObject payload = readPayload(stored);
            restored = MarketUtils.MarketObjectToConsumableRecord(entry.name, payload, amount);
        }
        catch (Exception e)
        {
            Gdx.app.error("OfflineStash", "Could not recreate item from local stash.", e);
            return false;
        }

        if (restored == null || restored.getItem() == null)
        {
            return false;
        }

        if (storedAmount == amount)
        {
            updated.remove(index);
        }
        else
        {
            stored.put("amount", storedAmount - amount);
        }

        restored.setId(target.newId());

        try
        {
            target.addRecord(restored);
            target.updateWeight();
            save(updated);
            savePending(updatedPending);
            Gdx.app.log("OfflineStash", "Withdrew " + amount + " x " + entry.name);
            return true;
        }
        catch (Exception e)
        {
            // Do not leave a duplicate in the player's inventory if persistence failed.
            if (target.get(restored.getId()) == restored)
            {
                target.removeRecord(restored);
                target.updateWeight();
            }

            try
            {
                save(previous);
                savePending(previousPending);
            }
            catch (Exception rollbackError)
            {
                Gdx.app.error("OfflineStash", "Could not restore stash data after a failed withdrawal write.", rollbackError);
            }

            Gdx.app.error("OfflineStash", "Could not commit local stash withdrawal.", e);
            return false;
        }
    }

    /** Removes a stack from the local stash (used by the Freeplay trash can). */
    public static synchronized boolean remove(MarketService.MarketItemEntry entry, int amount)
    {
        if (entry == null || entry.name == null || entry.payload == null || amount <= 0)
        {
            return false;
        }

        final JSONArray previous;
        final JSONArray updated;
        try
        {
            previous = load();
            updated = new JSONArray(previous.toString());
        }
        catch (Exception e)
        {
            return false;
        }

        int index = findStoredItem(updated, entry.name, entry.payload);
        if (index < 0)
        {
            return false;
        }

        JSONObject stored = updated.optJSONObject(index);
        int storedAmount = stored != null ? stored.optInt("amount", 0) : 0;
        if (storedAmount < amount)
        {
            return false;
        }

        if (storedAmount == amount)
        {
            updated.remove(index);
        }
        else
        {
            stored.put("amount", storedAmount - amount);
        }

        try
        {
            save(updated);
            return true;
        }
        catch (Exception e)
        {
            try
            {
                save(previous);
            }
            catch (Exception rollbackError)
            {
                Gdx.app.error("OfflineStash", "Could not roll back a failed stash removal.", rollbackError);
            }

            Gdx.app.error("OfflineStash", "Could not remove item from local stash.", e);
            return false;
        }
    }
}
