-- zz_test_gunturn2.lua -- TEST ONLY (RE2, 2026-11-01): turns one joint of the gun in hand, every frame before drawing, so a
-- screenshot shows which part it is. Request reframework/data/zz_gunturn.json {"joint": "_03", "deg": 45, "axis": "x"};
-- {"joint": ""} stops.
local F, want = "zz_gunturn.json", nil
local function gun_joint(name)
    local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
    local eq = pm:call("get_CurrentPlayer"):call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.Equipment"))
    for _, j in ipairs(eq:call("get_EquipWeapon"):call("get_GameObject"):call("get_Transform"):call("get_Joints"):get_elements()) do
        if j:call("get_Name") == name then return j end
    end
end
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
