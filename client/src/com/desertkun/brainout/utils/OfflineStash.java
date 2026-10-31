package com.desertkun.brainout.utils;

import com.badlogic.gdx.Gdx;
import org.anthillplatform.runtime.services.MarketService;
import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public final class OfflineStash
{
    private static final String FILE_NAME = "offline-stash.json";

    private OfflineStash()
    {
    }

    private static JSONArray readItems()
    {
        if (!Gdx.files.local(FILE_NAME).exists())
        {
            return new JSONArray();
        }

        return new JSONArray(
            Gdx.files.local(FILE_NAME).readString("UTF-8")
        );
    }

    private static void writeItems(JSONArray items)
    {
        Gdx.files.local(FILE_NAME).writeString(
            items.toString(4),
            false,
            "UTF-8"
        );
    }

    public static synchronized List<MarketService.MarketItemEntry> load()
    {
        JSONArray items = readItems();
        List<MarketService.MarketItemEntry> result = new ArrayList<>();

        for (int i = 0; i < items.length(); i++)
        {
            JSONObject item = items.optJSONObject(i);

            if (item == null)
                continue;

            String name = item.optString("name", "");
            int amount = item.optInt("amount", 0);
            JSONObject payload = item.optJSONObject("payload");

            if (name.isEmpty() || amount <= 0 || payload == null)
                continue;

            result.add(new MarketService.MarketItemEntry(
                name, amount, payload
            ));
        }

        return result;
    }

    public static synchronized void add(
        String name, JSONObject payload, int amount)
    {
        if (name == null || payload == null || amount <= 0)
            throw new IllegalArgumentException("Invalid stash item");

        JSONArray items = readItems();

        for (int i = 0; i < items.length(); i++)
        {
            JSONObject item = items.optJSONObject(i);

            if (item == null)
                continue;

            JSONObject savedPayload = item.optJSONObject("payload");

            if (name.equals(item.optString("name"))
                && savedPayload != null
                && savedPayload.toString().equals(payload.toString()))
            {
                item.put("amount", item.optInt("amount", 0) + amount);
                writeItems(items);
                return;
            }
        }

        JSONObject item = new JSONObject();
        item.put("name", name);
        item.put("amount", amount);
        item.put("payload", new JSONObject(payload.toString()));

        items.put(item);
        writeItems(items);
    }

    public static synchronized boolean remove(
        MarketService.MarketItemEntry entry, int amount)
    {
        if (entry == null || amount <= 0)
            return false;

        JSONArray items = readItems();

        for (int i = 0; i < items.length(); i++)
        {
            JSONObject item = items.optJSONObject(i);

            if (item == null)
                continue;

            JSONObject savedPayload = item.optJSONObject("payload");

            if (!entry.name.equals(item.optString("name"))
                || savedPayload == null
                || !savedPayload.toString().equals(entry.payload.toString()))
            {
                continue;
            }

            int storedAmount = item.optInt("amount", 0);

            if (storedAmount < amount)
                return false;

            int remaining = storedAmount - amount;

            if (remaining == 0)
            {
                items.remove(i);
            }
            else
            {
                item.put("amount", remaining);
            }

            writeItems(items);
            return true;
        }

        return false;
    }
}