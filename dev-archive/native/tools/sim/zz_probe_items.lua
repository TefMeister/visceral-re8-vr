-- zz_probe_items.lua -- TEST ONLY, READ ONLY (2026-11-08, for Tefa's idea 36: "Empty hand grip button takes the item from game
-- world, it travels to player hand as soon as in the close enough area, then while holding the grip button, press trigger to
-- store, no taking items out at all"). Before the hand side can be built we need: which component marks an item lying in the
-- world, where it is, and which of its calls the game itself uses to pick it up. Names seen in re8.exe's text (2026-11-08):
-- InteractItemGet, ItemGetInteract, RequestItemGetInteract, onPickUp, notifyPickUpItem, ItemGetSpawnController.
-- What it does: once a few seconds after load, and again whenever reframework/data/visceral_re8/item_probe.txt exists (the
-- file is then emptied), asks which of the candidate types exist, lists each one's methods and fields (once), then lists the
-- 8 nearest objects carrying it with their distance from the player. Nothing is called, nothing is written to the game.
-- Log lines "[item-probe] ...". Copy into reframework/autorun for one run; take it out after.
local CANDIDATES = {
    "app.InteractItemGet", "app.ItemGetInteract", "app.InteractItemGetCustomParts", "app.InteractItemGetCrest",
    "app.ItemGetSpawnController", "app.ItemGetEnemyDropSpawnController", "app.ItemGetEnemyDropCore", "app.InteractObject",
    "app.InteractOrderObject", "app.ItemCore", "app.DropItem", "app.ItemPickup",
}
local TAG, TRIGGER = "[item-probe] ", "visceral_re8/item_probe.txt"
local listed, beat = {}, 0
local function L(s) log.info(TAG .. s) end

local function player_pos()
    local sm = sdk.get_native_singleton("via.SceneManager")
    local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local arr = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase"))
    local els = arr and arr:get_elements()
    local c = els and els[1]
    return c and c:call("get_GameObject"):call("get_Transform"):call("get_Position"), sc
end

local function describe(td, name)
    if listed[name] then return end
    listed[name] = true
    local ms, fs = {}, {}
    local t = td
    for _ = 1, 4 do   -- the type and three parents
        if not t then break end
        for _, m in ipairs(t:get_methods() or {}) do
            local ok, nm = pcall(function() return m:get_name() end)
            if ok and nm then
                local np = 0
                pcall(function() np = m:get_num_params() end)
                ms[#ms + 1] = t:get_full_name() .. "." .. nm .. "/" .. np
            end
        end
        for _, f in ipairs(t:get_fields() or {}) do
            local ok, nm = pcall(function() return f:get_name() end)
            if ok and nm then fs[#fs + 1] = nm end
        end
        t = t:get_parent_type()
    end
    L(name .. ": " .. #ms .. " methods, " .. #fs .. " fields")
    for i = 1, #ms, 6 do L("  m " .. table.concat(ms, "  ", i, math.min(#ms, i + 5))) end
    for i = 1, #fs, 8 do L("  f " .. table.concat(fs, "  ", i, math.min(#fs, i + 7))) end
end

local function probe()
    local pp, sc = player_pos()
    if not pp or not sc then L("no player yet") return end
    for _, name in ipairs(CANDIDATES) do
        local td = sdk.find_type_definition(name)
        if not td then L(name .. ": no such type")
        else
            describe(td, name)
            local ok, arr = pcall(function() return sc:call("findComponents(System.Type)", sdk.typeof(name)) end)
            local els = ok and arr and arr:get_elements() or {}
            local near = {}
            for _, c in ipairs(els) do
                pcall(function()
                    local go = c:call("get_GameObject")
                    local p = go:call("get_Transform"):call("get_Position")
                    local d = (p - pp):length()
                    near[#near + 1] = { d = d, name = go:call("get_Name") }
                end)
            end
            table.sort(near, function(a, b) return a.d < b.d end)
            local parts = {}
            for i = 1, math.min(8, #near) do parts[#parts + 1] = string.format("%s %.1f m", tostring(near[i].name), near[i].d) end
            L(string.format("%s: %d in the scene; nearest: %s", name, #els, table.concat(parts, ", ")))
        end
    end
end

re.on_frame(function()
    beat = beat + 1
    if beat == 600 then pcall(probe) end
    if beat % 60 == 0 then
        local ok, d = pcall(function() return fs.read(TRIGGER) end)   -- REFramework's fs: paths under reframework/data
        if ok and type(d) == "string" and d ~= "" then
            pcall(function() fs.write(TRIGGER, "") end)
            L("asked by item_probe.txt")
            pcall(probe)
        end
    end
end)
