-- visceral_re8_gun_cycle.lua -- puts every gun in the inventory into the hand once, a few seconds each, so the gun survey
-- (visceral_re8_gun_survey.lua) can read each one. Testing only; it does nothing unless the trigger file exists:
--   reframework/data/visceral_re8/cycle_guns.json  {"go": 1}  (set back to {"go": 0} when the cycle ends)
-- Optional in the same file: "hold": seconds per gun; "only": [item ids] to cycle just those; "give": [item ids] of guns to
-- add first (skipped if already owned); "ammo": [[item id, count], ...] to add first. Giving goes the way that worked through
-- the REFramework MCP on 2026-10-24: InventoryManager.createItemCore(id, 1, 0, 0), its get_work(), then
-- activeInventory.addItem(work, false, false, false); ammo through createAndAddItem(id, count, 0, 0).
-- How a gun is put in hand: app.PlayerWeaponChange.set_RequestedItem(ItemCore), the call Andyalpa's holster uses
-- (re8_vr_holster.lua STOW.set_requested_item). The guns are the app.WeaponGunCore items of the active inventory.
-- 2026-10-24 (Tefa: "can you do all the other guns in the game as well, or do you need me to equip them one by one?").

local TAG = "[visceral-re8-cycle]"
local TRIGGER = "visceral_re8/cycle_guns.json"
local HOLD_SEC = 6.0             -- each gun stays in hand this long (the survey needs about 1 s after it appears)
local CHECK_SEC = 2.0            -- how often the trigger file is looked for

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

local function weapon_change()
    local v = rawget(_G, "re8vr")
    local p = v and v.player
    if p == nil then return nil end
    local function comp(t)
        local rt = safe(function() return sdk.typeof(t) end)   -- as utility/RE8.lua does
        return rt and safe(function() return p:call("getComponent(System.Type)", rt) end)
    end
    -- 2026-10-24 first run: getComponent(PlayerWeaponChange) found nothing; the holster goes through the updater
    for _, t in ipairs({ "app.PlayerUpdaterFPS", "app.PlayerUpdater", "app.PlayerUpdaterPl2001" }) do
        local up = comp(t)
        local c = up and safe(function() return up:call("get_playerWeaponChange") end)
        if c then return c end
    end
    for _, t in ipairs({ "app.PlayerWeaponChange", "app.PlayerWeaponChangePl2001" }) do
        local c = comp(t)
        if c then return c end
    end
    return nil
end

local function inventory_guns()
    local out = {}
    local im = sdk.get_managed_singleton("app.InventoryManager")
    local inv = im and safe(function() return im:call("get_activeInventory") end)
    local items = inv and safe(function() return inv:get_field("<items>k__BackingField") end)
    local arr = items and safe(function() return items:call("ToArray") end)
    for _, it in ipairs(arr and safe(function() return arr:get_elements() end) or {}) do
        local tn = safe(function() return it:get_type_definition():get_full_name() end)
        if tn == "app.WeaponGunCore" then
            local w = safe(function() return it:call("get_work") end)
            out[#out + 1] = { item = it, id = w and safe(function() return w:call("get_itemID") end) or 0 }
        end
    end
    return out
end

local SIG_CREATE = "createItemCore(System.UInt32, System.Int32, System.UInt32, System.Int32)"
local SIG_CREATE_ADD = "createAndAddItem(System.UInt32, System.Int32, System.UInt32, System.Int32)"
local SIG_ADD = "addItem(app.ItemCore.InstanceWork, System.Boolean, System.Boolean, System.Boolean)"

local function give(d)
    local im = sdk.get_managed_singleton("app.InventoryManager")
    local inv = im and safe(function() return im:call("get_activeInventory") end)
    if inv == nil then L("give: no inventory") return end
    local owned = {}
    for _, g in ipairs(inventory_guns()) do owned[g.id] = true end
    for _, id in ipairs(type(d.give) == "table" and d.give or {}) do
        if owned[id] then L(string.format("give: gun %d already owned", id))
        else
            local core = safe(function() return im:call(SIG_CREATE, id, 1, 0, 0) end)
            local work = core and safe(function() return core:call("get_work") end)
            local ok = work ~= nil and pcall(function() inv:call(SIG_ADD, work, false, false, false) end)
            L(string.format("give: gun %d %s", id, ok and "added" or "FAILED"))
        end
    end
    for _, a in ipairs(type(d.ammo) == "table" and d.ammo or {}) do
        local r = type(a) == "table" and safe(function() return im:call(SIG_CREATE_ADD, a[1], a[2], 0, 0) end)
        L(string.format("give: ammo %s x%s %s", tostring(a[1]), tostring(a[2]), r and "added" or "FAILED"))
    end
end

local run = nil   -- { guns, i, t, hold }
local last_check = 0
re.on_frame(function()
    local now = os.clock()
    if run == nil then
        if now - last_check < CHECK_SEC then return end
        last_check = now
        local d = safe(function() return json.load_file(TRIGGER) end)
        if type(d) ~= "table" or d.go ~= 1 then return end
        if weapon_change() == nil then return end   -- not in gameplay yet (title, loading): wait, keep the trigger
        pcall(give, d)
        local guns, only = {}, nil
        if type(d.only) == "table" then only = {} for _, id in ipairs(d.only) do only[id] = true end end
        for _, g in ipairs(inventory_guns()) do if only == nil or only[g.id] then guns[#guns + 1] = g end end
        local hold = tonumber(d.hold) or HOLD_SEC
        L(string.format("cycle started: %d gun(s), %.0f s each", #guns, hold))
        run = { guns = guns, i = 0, t = -hold, hold = hold }
        return
    end
    if now - run.t < run.hold then return end
    run.i = run.i + 1
    run.t = now
    local g = run.guns[run.i]
    if g == nil then
        L("cycle done")
        pcall(function() json.dump_file(TRIGGER, { go = 0 }) end)
        run = nil
        return
    end
    local wc = weapon_change()
    local ok = wc ~= nil and pcall(function() wc:call("set_RequestedItem", g.item) end)
    L(string.format("gun %d of %d (item %s): %s", run.i, #run.guns, tostring(g.id), ok and "requested" or "FAILED (no weapon change)"))
end)

L("loaded (runs once when reframework/data/" .. TRIGGER .. " exists)")
