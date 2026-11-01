-- zz_test_equip.lua -- TEST ONLY (2026-11-01, the simulator survey of every Village gun): equips the gun named in
-- reframework/data/visceral_re8/test_equip.json {"id": <item id>, "seq": n} through Andyalpa's native equip
-- (__re8_holster_equip_item, the D-pad path). Taken out of the game after the survey; kept in dev-archive/native/tools/sim.
local FILE, last_seq, t = "visceral_re8/test_equip.json", nil, 0
-- every Village gun's item id (murmur3_32 of the short name, UTF-16LE, seed 0xFFFFFFFF; KNOWN.md): missing ones are added
-- once in play (createItemCore + addItem, the route proven 2026-10-24), so every launch of the survey has them all
local GUNS = { 97158149, 2735256250, 1157345091, 3132227914, 3003110346, 2146816802, 241847407, 331140406, 634755339,
               2576167331, 3875003266, 2545563073, 949611560 }
local gifted = false
local function gift()
    local im = sdk.get_managed_singleton("app.InventoryManager")
    local inv = im and im:call("get_activeInventory")
    if not inv or not inv:call("hasItem", 97158149, false, false) then return end   -- in play only: the save's own LEMI is there
    local n = 0
    for _, id in ipairs(GUNS) do
        if not inv:call("hasItem", id, false, false) then
            local core = im:call("createItemCore", id, 1, 0, 0)
            local work = core and core:call("get_work")
            if work then inv:call("addItem", work, false, false, false); n = n + 1 end
        end
    end
    gifted = true
    log.info("[test-equip] guns added: " .. n)
end
re.on_frame(function()
    t = t + 1
    if t % 30 ~= 0 then return end
    if not gifted and t > 600 then pcall(gift) end
    local ok, req = pcall(json.load_file, FILE)
    if not ok or type(req) ~= "table" or req.seq == nil or req.seq == last_seq then return end
    last_seq = req.seq
    local res = "?"
    pcall(function()
        local inv = sdk.get_managed_singleton("app.InventoryManager"):call("get_activeInventory")
        local list = inv:call("findItems", math.floor(req.id), false, false)
        local item = list and list:call("get_Count") > 0 and list:call("get_Item", 0) or nil
        if not item then res = "not in the inventory"; return end
        local eq = rawget(_G, "__re8_holster_equip_item")
        if not eq then res = "no equip function"; return end
        res = eq(item, "test survey") and "equipped" or "equip refused"
    end)
    log.info("[test-equip] " .. tostring(req.id) .. ": " .. res)
end)
