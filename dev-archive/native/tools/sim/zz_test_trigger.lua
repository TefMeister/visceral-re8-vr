-- zz_test_trigger.lua -- TEST ONLY (2026-11-01, the hammer click): on visceral_re8/test_trigger.json {"seq": n, "id": <wwise id>}
-- the gun in hand's via.wwise.WwiseContainer plays that trigger, so it can be recorded clean.
local last, t = nil, 0
local function play(id)
    local v = rawget(_G, "re8vr"); local w = v and v.weapon
    local go = nil
    pcall(function() go = w:call("get_GameObject") end)
    if go == nil then pcall(function() go = w:get_field("<owner>k__BackingField") end) end
    local c = go and go:call("getComponent(System.Type)", sdk.typeof("via.wwise.WwiseContainer"))
    if not c then log.info("[test-trigger] no container on the gun"); return end
    local known = c:call("exists(System.UInt32)", id)
    c:call("trigger(System.UInt32)", id)
    log.info(string.format("[test-trigger] %s played on %s (known %s)", tostring(id), tostring(go:call("get_Name")), tostring(known)))
end
re.on_frame(function()
    t = t + 1
    if t % 20 ~= 0 then return end
    local ok, q = pcall(json.load_file, "visceral_re8/test_trigger.json")
    if ok and type(q) == "table" and q.seq ~= nil and q.seq ~= last then last = q.seq; local ok2, e = pcall(play, math.floor(q.id)); if not ok2 then log.info("[test-trigger] failed: " .. tostring(e)) end end
end)
