-- visceral_re8_gun_cycle.lua -- puts every gun in the inventory into the hand once, a few seconds each, so the gun survey
-- (visceral_re8_gun_survey.lua) can read each one. Testing only; it does nothing unless the trigger file exists:
--   reframework/data/visceral_re8/cycle_guns.json  {"go": 1}  (set back to {"go": 0} when the cycle ends)
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

local run = nil   -- { guns, i, t }
local last_check = 0
re.on_frame(function()
    local now = os.clock()
    if run == nil then
        if now - last_check < CHECK_SEC then return end
        last_check = now
        local d = safe(function() return json.load_file(TRIGGER) end)
        if type(d) ~= "table" or d.go ~= 1 then return end
        local guns = inventory_guns()
        L(string.format("cycle started: %d gun(s) in the inventory, %.0f s each", #guns, HOLD_SEC))
        run = { guns = guns, i = 0, t = -HOLD_SEC }
        return
    end
    if now - run.t < HOLD_SEC then return end
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
