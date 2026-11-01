-- zz_test_twist.lua -- TEST ONLY (2026-11-01, Tefa: "left forearm is teleport swapping between poses when using the rifle"):
-- logs every frame-to-frame jump over JUMP_DEG of the left arm's joints (local turn), with the gun and the motion layer.
local JUMP_DEG, NAMES = 8, { "L_Forearm", "L_Forearm_Twist_0", "L_Forearm_Twist_1", "L_Forearm_Twist_2", "L_Forearm_Twist_3", "L_Hand", "L_UpperArm" }
local prev, n, tf, beat, byname = {}, 0, nil, 0, nil
local function player_tf()   -- the way hand_poser.lua finds the character: the scene's app.PlayerUpdaterBase's GameObject
    local sm = sdk.get_native_singleton("via.SceneManager")
    local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local arr = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase"))
    local els = arr and arr:get_elements()
    local c = els and els[1]
    return c and c:call("get_GameObject"):call("get_Transform")
end
local function ang(a, b)   -- degrees between two quaternions
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w); if d > 1 then d = 1 end
    return math.deg(2 * math.acos(d))
end
re.on_pre_application_entry("BeginRendering", function()
    pcall(function()
        tf = tf or player_tf()
        beat = beat + 1
        if beat % 450 == 1 then log.info("[test-twist] heartbeat: player transform " .. tostring(tf ~= nil)) end
        if not tf then return end
        if not byname then
            byname = {}
            local arr = tf:call("get_Joints"); local els = arr and arr:get_elements() or {}
            for _, jj in ipairs(els) do local nn = jj:call("get_Name"); if nn then byname[nn] = jj end end
            local c = 0; for _ in pairs(byname) do c = c + 1 end
            log.info("[test-twist] joints found: " .. c)
        end
        for _, nm in ipairs(NAMES) do
            local j = byname and byname[nm]
            if j then
                local q = j:call("get_LocalRotation")
                local p = prev[nm]
                if beat % 450 == 2 then local e = j:call("get_LocalEulerAngle"); log.info(string.format("[test-twist] %s now %.0f %.0f %.0f", nm, math.deg(e.x), math.deg(e.y), math.deg(e.z))) end
                if p then
                    local a = ang(p, q)
                    if a > JUMP_DEG and n < 400 then n = n + 1; log.info(string.format("[test-twist] %s jumped %.0f deg", nm, a)) end
                end
                prev[nm] = q
            end
        end
    end)
end)
