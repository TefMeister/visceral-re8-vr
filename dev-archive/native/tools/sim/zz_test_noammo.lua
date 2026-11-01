-- zz_test_noammo.lua -- TEST ONLY (2026-11-01, the empty click): on visceral_re8/test_noammo.json {"seq": n}, the gun in hand's
-- spare ammo is taken out of the inventory (in memory; nothing is saved), so the game has nothing to reload with.
local last, t = nil, 0
local function strip()
    local v = rawget(_G, "re8vr"); local w = v and v.weapon
    local core = w
    pcall(function() local g = w:call("get_weaponGun"); if g then core = g end end)
    local id = nil
    pcall(function() id = core:call("getBulletItemID()") end)
    if id == nil then pcall(function() id = core:call("getBulletItemID") end) end
    local inv = sdk.get_managed_singleton("app.InventoryManager"):call("get_activeInventory")
    local have = inv:call("getTotalStackSize", id, false, false)
    if have and have > 0 then inv:call("reduceItem(System.UInt32, System.Int32, System.Boolean, System.Boolean)", id, have, false, false) end
    log.info(string.format("[test-noammo] bullet item %s: %s spare before, %s after", tostring(id), tostring(have), tostring(inv:call("getTotalStackSize", id, false, false))))
end
re.on_frame(function()
    t = t + 1
    if t % 30 ~= 0 then return end
    local ok, q = pcall(json.load_file, "visceral_re8/test_noammo.json")
    if ok and type(q) == "table" and q.seq ~= nil and q.seq ~= last then last = q.seq; local ok2, e = pcall(strip); if not ok2 then log.info("[test-noammo] failed: " .. tostring(e)) end end
end)
