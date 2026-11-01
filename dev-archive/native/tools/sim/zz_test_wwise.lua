-- zz_test_wwise.lua -- TEST ONLY (2026-11-01, the empty click): asks every via.wwise.WwiseContainer in the scene whether it knows
-- each name in visceral_re8/test_wwise_query.json {"seq": n, "names": [...]} (exists(String)); hits are logged with the owner.
local last, t = nil, 0
local function query(q)
    local sm = sdk.get_native_singleton("via.SceneManager")
    local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local arr = sc:call("findComponents(System.Type)", sdk.typeof("via.wwise.WwiseContainer"))
    local cs = arr and arr:get_elements() or {}
    local hits, checked = 0, 0
    for _, name in ipairs(q.names or {}) do
        local owners = {}
        for _, c in ipairs(cs) do
            local ok, e = pcall(function() return c:call("exists(System.String)", name) end)
            checked = checked + 1
            if ok and e then
                local o = "?"; pcall(function() o = c:call("get_GameObject"):call("get_Name") end)
                owners[#owners + 1] = o
            end
        end
        if #owners > 0 then hits = hits + 1; log.info("[test-wwise] HIT " .. name .. " on " .. table.concat(owners, ", ", 1, math.min(#owners, 5)) .. " (" .. #owners .. ")") end
    end
    log.info(string.format("[test-wwise] query %s: %d names, %d containers, %d hits", tostring(q.seq), #(q.names or {}), #cs, hits))
end
re.on_frame(function()
    t = t + 1
    if t % 60 ~= 0 then return end
    local ok, q = pcall(json.load_file, "visceral_re8/test_wwise_query.json")
    if ok and type(q) == "table" and q.seq ~= nil and q.seq ~= last then last = q.seq; pcall(query, q) end
end)
