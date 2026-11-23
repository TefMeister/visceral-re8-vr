-- visceral_re8_dev_guns.lua -- TESTING ONLY, never shipped: one button in the REFramework menu that puts every story gun
-- (and a stack of each ammo) into Ethan's case, so Tefa can save it to its own slot and test every gun from that save.
-- 2026-11-23, /ms, Tefa: "can you load me in the game with all guns and i can make a separate save so i don't have to ask
-- every time - needs a developer inventory or something i think".
-- The giving is the way that worked on 2026-10-24 (visceral_re8_gun_cycle.lua, the REFramework MCP):
-- InventoryManager.createItemCore(id, 1, 0, 0) -> get_work() -> activeInventory.addItem(work, false, false, false);
-- ammo through createAndAddItem(id, count, 0, 0). A gun's item id = murmur3_32 of UTF-16LE "ri<n>", seed 0xFFFFFFFF
-- [verified-numerically 2026-10-24, n=7; recomputed 2026-11-23 against the 10 ids given then]. Guns already owned are
-- skipped. The case may end up over-full; the game took that on 2026-10-24 (16 guns, no complaint) [measured, n=1].

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

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8: every gun (testing only)") then return end
    imgui.text("Puts every story gun in the case. Then save at a typewriter to an EMPTY slot.")
    if imgui.button("Give every gun + ammo") then pcall(give_all, true) end
    imgui.same_line()
    if imgui.button("Ammo only") then
        local im = sdk.get_managed_singleton("app.InventoryManager")
        local n = 0
        for _, a in ipairs(AMMO) do
            if im and safe(function() return im:call(SIG_CREATE_ADD, a[1], a[2], 0, 0) end) then n = n + 1 end
        end
        status = string.format("%d of %d ammo stacks added", n, #AMMO); L(status)
    end
    imgui.text(status)
    imgui.tree_pop()
end)

-- 2026-11-23 (/lm, Tefa: "please create a save in each game on a free slot with all weapons available"): the save in slot 6
-- keeps 11 of the 16: the five bonus-shop guns (USM-AI, Rocket Pistol, Handcannon PZ, Dragoon, WCX) are gone again after
-- every load, also with room in the case (two saves, a bigger case in between) [verified-live 2026-11-23, n=3 loads]. So the
-- missing guns are given again by themselves a few seconds after any save has loaded (with ammo only when a gun was
-- added, so the stacks do not grow at every load). Off: delete reframework/data/visceral_re8/dev_guns_auto.txt (made on the
-- first run); the button still works.
local AUTO_FILE = "visceral_re8/dev_guns_auto.txt"
local auto_on = json.load_file(AUTO_FILE) ~= nil
if not auto_on and json.load_file("visceral_re8/dev_guns_auto_made.txt") == nil then
    json.dump_file(AUTO_FILE, { on = true }); json.dump_file("visceral_re8/dev_guns_auto_made.txt", { made = true }); auto_on = true
end
local seen_inv, since, frame = nil, 0, 0
re.on_frame(function()
    frame = frame + 1
    if not auto_on or frame % 30 ~= 0 then return end
    local im = sdk.get_managed_singleton("app.InventoryManager")
    local inv = im and safe(function() return im:call("get_activeInventory") end)
    local player = rawget(_G, "re8vr") and re8vr.player
    if inv == nil or player == nil then seen_inv, since = nil, 0 return end
    local addr = safe(function() return inv:get_address() end)
    if addr ~= seen_inv then seen_inv, since = addr, frame return end   -- a new inventory = a save was loaded: wait a little
    if since == 0 or frame - since < 300 then return end
    since = 0
    local have, missing = owned_guns(inv), 0
    for _, g in ipairs(GUNS) do if not have[g[1]] then missing = missing + 1 end end
    if missing > 0 then L(missing .. " gun(s) missing after the load: given again by themselves"); pcall(give_all, true) end
end)

L("loaded (REFramework menu: 'Visceral RE8: every gun'; auto-give after a load: " .. tostring(auto_on) .. ")")
