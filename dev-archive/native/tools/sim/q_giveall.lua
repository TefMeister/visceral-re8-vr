local TAG = "[visceral-re8-devguns]"
local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

local GUNS = {
    { 2735256250, "M1911" },          { 97158149,   "LEMI" },          { 1157345091, "V61 Custom" },
    { 3132227914, "USM-AI" },         { 3875003266, "S.T.A.K.E" },     { 949611560,  "Samurai Edge AW" },
    { 2545563073, "Rocket Pistol" },  { 4186049118, "F2 Rifle" },      { 3003110346, "WCX" },
    { 2146816802, "Dragoon" },        { 241847407,  "SYG-12" },        { 738899953,  "W870 TAC" },
    { 2838037082, "M1897" },          { 2576167331, "GM 79" },         { 331140406,  "M1851 Wolfsbane" },
    { 634755339,  "Handcannon PZ" },
}
-- the ammo ids that took on 2026-10-24 (which ammo is which was not written down then); GM 79 rounds (1927571624) did not
local AMMO = { { 1179972000, 60 }, { 1731811000, 30 }, { 3919597625, 30 }, { 2182652875, 30 }, { 2275184395, 12 },
               { 3188868396, 60 } }

local SIG_CREATE = "createItemCore(System.UInt32, System.Int32, System.UInt32, System.Int32)"
local SIG_CREATE_ADD = "createAndAddItem(System.UInt32, System.Int32, System.UInt32, System.Int32)"
local SIG_ADD = "addItem(app.ItemCore.InstanceWork, System.Boolean, System.Boolean, System.Boolean)"

local function owned_guns(inv)
    local out = {}
    local items = safe(function() return inv:get_field("<items>k__BackingField") end)
    local arr = items and safe(function() return items:call("ToArray") end)
    for _, it in ipairs(arr and safe(function() return arr:get_elements() end) or {}) do
        if safe(function() return it:get_type_definition():get_full_name() end) == "app.WeaponGunCore" then
            local w = safe(function() return it:call("get_work") end)
            local id = w and safe(function() return w:call("get_itemID") end)
            if id then out[id] = true end
        end
    end
    return out
end

local status = "not pressed yet"

local function give_all(with_ammo)
    local im = sdk.get_managed_singleton("app.InventoryManager")
    local inv = im and safe(function() return im:call("get_activeInventory") end)
    if inv == nil then status = "no inventory yet: load a save first"; L(status) return end
    local have = owned_guns(inv)
    local added, skipped, failed = 0, 0, {}
    for _, g in ipairs(GUNS) do
        if have[g[1]] then skipped = skipped + 1
        else
            local core = safe(function() return im:call(SIG_CREATE, g[1], 1, 0, 0) end)
            local work = core and safe(function() return core:call("get_work") end)
            local ok = work ~= nil and pcall(function() inv:call(SIG_ADD, work, false, false, false) end)
            if ok then added = added + 1 else failed[#failed + 1] = g[2] end
            L(string.format("gun %s (%d) %s", g[2], g[1], ok and "added" or "FAILED"))
        end
    end
    local ammo_ok = 0
    if with_ammo then
        for _, a in ipairs(AMMO) do
            local r = safe(function() return im:call(SIG_CREATE_ADD, a[1], a[2], 0, 0) end)
            if r then ammo_ok = ammo_ok + 1 end
            L(string.format("ammo %d x%d %s", a[1], a[2], r and "added" or "FAILED"))
        end
    end
    status = string.format("%d gun(s) added, %d already owned%s%s", added, skipped,
        with_ammo and string.format(", %d of %d ammo stacks", ammo_ok, #AMMO) or "",
        #failed > 0 and (", FAILED: " .. table.concat(failed, ", ")) or "")
    L(status)
end
give_all(true); return status
