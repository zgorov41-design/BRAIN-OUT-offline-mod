
package com.desertkun.brainout.content.components;

import com.badlogic.gdx.graphics.g2d.TextureRegion;
import com.badlogic.gdx.utils.Json;
import com.badlogic.gdx.utils.JsonValue;
import com.desertkun.brainout.BrainOut;
import com.desertkun.brainout.content.components.base.ContentComponent;
import com.desertkun.brainout.data.components.base.Component;
import com.desertkun.brainout.data.components.base.ComponentObject;
import com.desertkun.brainout.reflection.Reflect;

@Reflect("content.components.BlockTextureComponent")
public class BlockTextureComponent extends ContentComponent
{
    private TextureRegion region;

    @Override
    public Component getComponent(ComponentObject componentObject)
    {
        return null;
    }

    @Override
    public void write(Json json)
    {
    }

    @Override
    public void read(Json json, JsonValue jsonData)
    {
        String regionName = jsonData.getString("region");
        this.region = BrainOut.getInstance().getTextureRegion(regionName);

        if (this.region == null)
        {
            System.err.println("[MISSING BLOCK TEXTURE] region=" + regionName);
        }
    }

    public TextureRegion getRegion()
    {
        return region;
    }
}
