-- zz_test_gunturn2.lua -- TEST ONLY (RE2 and RE3, 2026-11-01): turns one joint of the gun in hand, every frame before drawing, so a
-- screenshot shows which part it is. Request reframework/data/zz_gunturn.json {"joint": "_03", "deg": 45, "axis": "x"};
-- {"joint": ""} stops.
local F, want = "zz_gunturn.json", nil
local NS = (reframework:get_game_name() == "re3") and "offline" or "app.ropeway"   -- RE3's types live under offline.
local function comp(go, tn)
    local t = sdk.typeof(tn)
    if t == nil then local td = sdk.find_type_definition(tn); t = td and td:get_runtime_type() end
    local c = t and go:call("getComponent(System.Type)", t)
    if c then return c end
    for _, x in ipairs(go:call("get_Components"):get_elements()) do if x:get_type_definition():get_full_name() == tn then return x end end
end
local function gun_joint(name)
    local pm = sdk.get_managed_singleton(NS .. ".PlayerManager")
    local eq = comp(pm:call("get_CurrentPlayer"), NS .. ".survivor.Equipment")
    for _, j in ipairs(eq:call("get_EquipWeapon"):call("get_GameObject"):call("get_Transform"):call("get_Joints"):get_elements()) do
        if j:call("get_Name") == name then return j end
    end
end
local function write()
    if not want or not want.j then return end
    local h = math.rad(want.deg) / 2
    local q = Quaternion.new(math.cos(h), want.axis == "x" and math.sin(h) or 0, want.axis == "y" and math.sin(h) or 0, want.axis == "z" and math.sin(h) or 0)
    want.j:call("set_LocalRotation", q)
end
-- written after the animation (LateUpdateBehavior post) and again before drawing, as the mod's own slide is
re.on_application_entry("LateUpdateBehavior", function() pcall(write) end)
re.on_pre_application_entry("PrepareRendering", function() pcall(write) end)
re.on_pre_application_entry("BeginRendering", function()
    pcall(function()
        local r = json.load_file(F)
        if r and r.joint then
            json.dump_file(F, {})
            if r.joint == "" then want = nil; log.info("[test-gunturn2] stopped"); return end
            want = {j = gun_joint(r.joint), deg = r.deg or 45, axis = r.axis or "x", name = r.joint}
            log.info("[test-gunturn2] turning " .. r.joint .. " " .. want.deg .. " deg about " .. want.axis .. " (found " .. tostring(want.j ~= nil) .. ")")
        end
        if not want or not want.j then return end
        local h = math.rad(want.deg) / 2
        local q = Quaternion.new(math.cos(h), want.axis == "x" and math.sin(h) or 0, want.axis == "y" and math.sin(h) or 0, want.axis == "z" and math.sin(h) or 0)
        want.j:call("set_LocalRotation", q)
    end)
end)
