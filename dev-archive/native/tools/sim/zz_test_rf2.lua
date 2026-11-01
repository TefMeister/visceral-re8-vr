-- zz_test_rf2.lua -- TEST ONLY (2026-11-01, RE2: does the right hand move with no gun out?): lists the player's hand joints once,
-- then logs every frame-to-frame turn over JUMP_DEG of the right hand's finger joints, read before rendering.
local JUMP_DEG, prev, n, tf, byname, listed, beat = 2, {}, 0, nil, nil, false, 0
local function player_tf()
    local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
    local go = pm and pm:call("get_CurrentPlayer")
    return go and go:call("get_Transform")
end
local function ang(a, b)
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w); if d > 1 then d = 1 end
    return math.deg(2 * math.acos(d))
end
re.on_pre_application_entry("BeginRendering", function()
    pcall(function()
        tf = tf or player_tf(); if not tf then return end
        if not byname then
            byname = {}
            local arr = tf:call("get_Joints"); local els = arr and arr:get_elements() or {}
            for _, j in ipairs(els) do local nn = j:call("get_Name"); if nn then byname[nn] = j end end
        end
        if not listed then
            listed = true
            local hand = {}
            for nn, _ in pairs(byname) do if nn:lower():find("hand") or nn:lower():find("finger") or nn:lower():find("thumb") then hand[#hand + 1] = nn end end
            table.sort(hand); log.info("[test-rf2] hand joints: " .. table.concat(hand, ", "))
        end
        beat = beat + 1
        for nn, j in pairs(byname) do
            local l = nn:lower()
            if l:sub(1, 7) == "r_hand_" or (l:sub(1, 2) == "r_" and (l:find("finger") or l:find("thumb") or l:find("index") or l:find("middle"))) then
                local q = j:call("get_LocalRotation")
                local p = prev[nn]
                if p then local a = ang(p, q); if a > JUMP_DEG and n < 600 then n = n + 1; log.info(string.format("[test-rf2] %s moved %.0f deg", nn, a)) end end
                prev[nn] = q
            end
        end
    end)
end)
