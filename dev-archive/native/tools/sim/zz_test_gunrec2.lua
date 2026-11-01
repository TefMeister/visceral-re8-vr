-- zz_test_gunrec2.lua -- TEST ONLY (RE2, 2026-11-01): which of the gun in hand's joints move, and how far, while the game
-- plays its own reload. Request reframework/data/zz_gunrec.json {"secs": n}: records each joint's largest turn (deg) and
-- shift (cm) from where it was at the start, and logs them when the time is up.
local F, rec = "zz_gunrec.json", nil
local function ang(a, b)
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w); if d > 1 then d = 1 end
    return math.deg(2 * math.acos(d))
end
local function gun_joints()
    local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
    local eq = pm:call("get_CurrentPlayer"):call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.Equipment"))
    return eq:call("get_EquipWeapon"):call("get_GameObject"):call("get_Transform"):call("get_Joints"):get_elements()
end
re.on_pre_application_entry("BeginRendering", function()
    pcall(function()
        local r = json.load_file(F)
        if r and r.secs then
            json.dump_file(F, {}); rec = {t_end = os.clock() + r.secs, js = {}}
            for _, j in ipairs(gun_joints()) do
                rec.js[#rec.js + 1] = {j = j, n = j:call("get_Name"), q0 = j:call("get_LocalRotation"), p0 = j:call("get_LocalPosition"), a = 0, d = 0}
            end
        end
        if not rec then return end
        for _, e in ipairs(rec.js) do
            local a = ang(e.q0, e.j:call("get_LocalRotation")); if a > e.a then e.a = a end
            local p = e.j:call("get_LocalPosition"); local d = ((p.x - e.p0.x) ^ 2 + (p.y - e.p0.y) ^ 2 + (p.z - e.p0.z) ^ 2) ^ 0.5 * 100
            if d > e.d then e.d = d end
        end
        if os.clock() > rec.t_end then
            local out = {}; for _, e in ipairs(rec.js) do out[#out + 1] = string.format("%s %.0fdeg %.1fcm", e.n, e.a, e.d) end
            log.info("[test-gunrec2] " .. table.concat(out, ", ")); rec = nil
        end
    end)
end)
