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
