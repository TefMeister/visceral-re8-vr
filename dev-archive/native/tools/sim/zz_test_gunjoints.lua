-- zz_test_gunjoints.lua -- TEST ONLY (2026-11-01, the shotguns' shell guard): on visceral_re8/test_gunjoints.json
-- {"seq": n, "joints": [...], "secs": s} logs the gun in hand's named joints (local position and turn) every frame for s seconds,
-- read after the animation (LateUpdateBehavior), to see how the game's own pump moves them.
local last, t, until_t, want = nil, 0, 0, {}
local function gun_tf()
    local v = rawget(_G, "re8vr"); local w = v and v.weapon
    if not w then return nil end
    local go = nil
    pcall(function() go = w:call("get_GameObject") end)
    if go == nil then pcall(function() go = w:get_field("<owner>k__BackingField") end) end
    return go and go:call("get_Transform")
end
re.on_frame(function()
    t = t + 1
    if t % 20 ~= 0 then return end
    local ok, q = pcall(json.load_file, "visceral_re8/test_gunjoints.json")
    if ok and type(q) == "table" and q.seq ~= nil and q.seq ~= last then last = q.seq; want = q.joints or {}; until_t = os.clock() + (q.secs or 2) end
end)
re.on_application_entry("LateUpdateBehavior", function()
    if os.clock() > until_t then return end
    pcall(function()
        local tf = gun_tf(); if not tf then return end
        local parts = {}
        for _, nm in ipairs(want) do
            local j = tf:call("getJointByName", nm)
            if j then
                local p = j:call("get_LocalPosition"); local e = j:call("get_LocalEulerAngle")
                parts[#parts + 1] = string.format("%s p %.3f %.3f %.3f r %.0f %.0f %.0f", nm, p.x, p.y, p.z, math.deg(e.x), math.deg(e.y), math.deg(e.z))
            else parts[#parts + 1] = nm .. " ?" end
        end
        log.info(string.format("[test-gj] %.3f %s", os.clock(), table.concat(parts, " | ")))
    end)
end)
