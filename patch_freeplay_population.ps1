$ErrorActionPreference = 'Stop'

$path = 'server\src\com\desertkun\brainout\mode\ServerFreeRealization.java'
if (!(Test-Path $path)) {
    throw "File not found: $path"
}

$text = [System.IO.File]::ReadAllText($path)
if ($text.Contains('private int freeplayBotTarget = -1;') -or
    $text.Contains('maintainFreeplayBots()')) {
    throw 'Patch appears to be already applied. No changes made.'
}

$nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

$spawnPool = '    private Array<ActiveData> spawnPool;'
if (!$text.Contains($spawnPool)) {
    throw 'Cannot find spawnPool field. No changes made.'
}

$scheduleAnchor = '        scheduleTask(this::spawnCrows, 2000, 2000);'
if (!$text.Contains($scheduleAnchor)) {
    throw 'Cannot find spawnCrows schedule. No changes made.'
}

$methodAnchor = '    private static Array<String> ZOMBIES = new Array<>(new String[]{'
if (!$text.Contains($methodAnchor)) {
    throw 'Cannot find zombie method anchor. No changes made.'
}

$backup = "$path.bak-before-freeplay-population"
Copy-Item $path $backup -ErrorAction Stop
Write-Output "Backup created: $backup"

$text = $text.Replace(
    'import com.desertkun.brainout.bot.TaskStack;',
    ('import com.desertkun.brainout.bot.TaskStack;' + $nl +
     'import com.desertkun.brainout.bot.TaskCreator;')
)

$text = $text.Replace(
    'import com.desertkun.brainout.bot.freeplay.TaskFreePlay;',
    ('import com.desertkun.brainout.bot.freeplay.TaskFreePlay;' + $nl +
     'import com.desertkun.brainout.bot.freeplay.HuntAround;')
)

$text = $text.Replace(
    $spawnPool,
    ($spawnPool + $nl +
     '    private int freeplayBotTarget = -1;' + $nl +
     '    private Array<PlayerSkinSlotItem> freeplayBotSkins;')
)

$text = $text.Replace(
    $scheduleAnchor,
    ($scheduleAnchor + $nl +
     '        scheduleTask(this::maintainFreeplayBots, 3000, 10000);')
)

$methods = @'
    private int countAliveFreeplayBots()
    {
        int count = 0;

        for (ObjectMap.Entry<String, Map> entry : Map.AllEntries())
        {
            ObjectMap.Values<ActiveData> players =
                entry.value.getActivesForTag(Constants.ActiveTags.PLAYERS, false);

            for (ActiveData activeData : players)
            {
                if (activeData.isAlive() &&
                    activeData.getComponent(ServerFreePartnerBotComponent.class) != null)
                {
                    count++;
                }
            }
        }

        return count;
    }

    private void maintainFreeplayBots()
    {
        if (spawnPool == null || spawnPool.size == 0)
            return;

        if (freeplayBotTarget < 0)
        {
            freeplayBotTarget = MathUtils.random(20, 25);

            if (Log.INFO)
                Log.info("Freeplay bot target population: " + freeplayBotTarget);
        }

        if (countAliveFreeplayBots() >= freeplayBotTarget)
            return;

        Array<ActiveData> candidates = new Array<>();

        for (ActiveData spawnAt : spawnPool)
        {
            if (!(spawnAt instanceof Spawnable))
                continue;

            Map map = spawnAt.getMap();
            if (map == null)
                continue;

            boolean good = true;

            ObjectMap.Values<ActiveData> players =
                map.getActivesForTag(Constants.ActiveTags.PLAYERS, false);

            for (ActiveData existing : players)
            {
                if (!existing.isAlive())
                    continue;

                float distance = Vector2.dst(
                    existing.getX(), existing.getY(),
                    spawnAt.getX(), spawnAt.getY()
                );

                if (existing.getComponent(ServerFreePartnerBotComponent.class) != null)
                {
                    if (distance < 24)
                    {
                        good = false;
                        break;
                    }

                    continue;
                }

                if (existing.getOwnerId() < 0 || distance > 64)
                    continue;

                if (distance < 32 || spawnAt.isVisible(existing))
                {
                    good = false;
                    break;
                }
            }

            if (good)
                candidates.add(spawnAt);
        }

        candidates.shuffle();

        int spawned = 0;

        for (ActiveData spawnAt : candidates)
        {
            if (countAliveFreeplayBots() >= freeplayBotTarget)
                break;

            if (spawnFreeplayBot(spawnAt))
                spawned++;
        }

        if (spawned > 0)
        {
            if (Log.INFO)
                Log.info("Freeplay bot maintenance spawned " + spawned
                    + " bot(s); alive=" + countAliveFreeplayBots());
        }
        else if (candidates.size == 0 && Log.INFO)
        {
            Log.info("Freeplay bot maintenance: no safe spawn points available.");
        }
    }

    private Array<PlayerSkinSlotItem> getFreeplayBotSkins()
    {
        if (freeplayBotSkins == null)
        {
            freeplayBotSkins = BrainOutServer.ContentMgr.queryContent(
                PlayerSkinSlotItem.class,
                slot -> RandomWeightComponent.Get(slot) != 0
            );
        }

        return freeplayBotSkins;
    }

    private boolean spawnFreeplayBot(ActiveData spawnAt)
    {
        if (spawnAt == null || spawnAt.getMap() == null)
            return false;

        GameMode gameMode = BrainOutServer.Controller.getGameMode();

        if (gameMode == null ||
            !(gameMode.getRealization() instanceof ServerFreeRealization))
            return false;

        Map map = spawnAt.getMap();

        Player player = BrainOutServer.ContentMgr.get(
            "player-freeplay", Player.class
        );
        Team team = BrainOutServer.ContentMgr.get(
            "team-freeplay", Team.class
        );

        if (player == null || team == null)
            return false;

        PlayerData playerData = (PlayerData) player.getData(map.getDimension());
        playerData.setTeam(team);

        BotControllerComponentData botController =
            new BotControllerComponentData(playerData);
        PlayerOwnerComponent ownerComponent =
            new PlayerOwnerComponent(playerData);
        PlayerRemoteComponent remoteComponent =
            new PlayerRemoteComponent(playerData);

        botController.getTasksStack().pushTask(
            new TaskCreator(botController.getTasksStack(),
                (stack, creator) ->
                    creator.pushTask(new HuntAround(stack, new IntSet()))
            )
        );

        playerData.addComponent(new ServerFreePartnerBotComponent(""));
        playerData.addComponent(botController);
        playerData.addComponent(ownerComponent);
        playerData.addComponent(remoteComponent);

        playerData.setPosition(spawnAt.getX(), spawnAt.getY());
        playerData.setAngle(180);

        PlayerAnimationComponentData animation =
            playerData.getComponent(PlayerAnimationComponentData.class);

        Array<PlayerSkinSlotItem> skins = getFreeplayBotSkins();

        if (animation != null && skins != null && skins.size > 0)
            animation.setSkin(skins.random().getSkin());

        PrimaryWeaponAndAmmo.generate(
            this, ownerComponent.getConsumableContainer(),
            map.getDimension(), playerData
        );

        switch (MathUtils.random(3))
        {
            case 0:
                RandomAmmo.generate(this, ownerComponent.getConsumableContainer());
                break;

            case 1:
                SecondaryWeaponAndAmmo.generate(
                    this, ownerComponent.getConsumableContainer(),
                    map.getDimension(), playerData
                );
                break;

            default:
                OtherConsumables.generate(
                    this, ownerComponent.getConsumableContainer()
                );
                break;
        }

        Weapon knife = BrainOutServer.ContentMgr.get("weapon-knife", Weapon.class);

        if (knife != null)
        {
            WeaponData weaponData = knife.getData(map.getDimension());

            ownerComponent.getConsumableContainer().putConsumable(
                1, new InstrumentConsumableItem(weaponData, map.getDimension())
            );
        }

        botController.selectFirstInstrument(ownerComponent);
        remoteComponent.setCurrentInstrument(ownerComponent.getCurrentInstrument());

        map.addActive(
            map.generateServerId(), playerData, true, true,
            ActiveData.ComponentWriter.TRUE
        );

        if (Log.INFO)
            Log.info("Spawned new bot at " + map.getDimension());

        return true;
    }

'@

$methods = ($methods -replace "`r`n|`n", $nl).Trim("`r", "`n")
$text = $text.Replace($methodAnchor, ($methods + $nl + $nl + $methodAnchor))

[System.IO.File]::WriteAllText(
    $path, $text, [System.Text.UTF8Encoding]::new($false)
)

Write-Output 'Patch applied successfully.'
Write-Output 'Backup:'
Write-Output $backup