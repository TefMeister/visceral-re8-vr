-- zz_test_gunrec2.lua -- TEST ONLY (RE2 and RE3, 2026-11-01): which of the gun in hand's joints move, and how far, while the game
-- plays its own reload. Request reframework/data/zz_gunrec.json {"secs": n}: records each joint's largest turn (deg) and
-- shift (cm) from where it was at the start, and logs them when the time is up.
local F, rec = "zz_gunrec.json", nil
local NS = (reframework:get_game_name() == "re3") and "offline" or "app.ropeway"   -- RE3's types live under offline.
local function comp(go, tn)
    local t = sdk.typeof(tn)
    if t == nil then local td = sdk.find_type_definition(tn); t = td and td:get_runtime_type() end
    local c = t and go:call("getComponent(System.Type)", t)
    if c then return c end
    for _, x in ipairs(go:call("get_Components"):get_elements()) do if x:get_type_definition():get_full_name() == tn then return x end end
end
local function ang(a, b)
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w); if d > 1 then d = 1 end
    return math.deg(2 * math.acos(d))
end
local function gun_joints()
    local pm = sdk.get_managed_singleton(NS .. ".PlayerManager")
    local eq = comp(pm:call("get_CurrentPlayer"), NS .. ".survivor.Equipment")
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
            local q = e.j:call("get_LocalRotation")
            local a = ang(e.q0, q); if a > e.a then e.a = a; e.qmax = q end
            local p = e.j:call("get_LocalPosition"); local d = ((p.x - e.p0.x) ^ 2 + (p.y - e.p0.y) ^ 2 + (p.z - e.p0.z) ^ 2) ^ 0.5 * 100
            if d > e.d then e.d = d end
        end
        if os.clock() > rec.t_end then
            local out = {}
            for _, e in ipairs(rec.js) do
                local ax = ""
                if e.qmax and e.a > 5 then   -- the turn's axis in the joint's own frame: q0^-1 * qmax
                    local a0, b = e.q0, e.qmax
                    local w = a0.w * b.w + a0.x * b.x + a0.y * b.y + a0.z * b.z
                    local x = a0.w * b.x - a0.x * b.w - a0.y * b.z + a0.z * b.y
                    local y = a0.w * b.y + a0.x * b.z - a0.y * b.w - a0.z * b.x
                    local z = a0.w * b.z - a0.x * b.y + a0.y * b.x - a0.z * b.w
                    local n = math.sqrt(x * x + y * y + z * z); if w < 0 then x, y, z = -x, -y, -z end
                    if n > 1e-6 then ax = string.format(" axis(%.2f %.2f %.2f)", x / n, y / n, z / n) end
                end
                out[#out + 1] = string.format("%s %.0fdeg %.1fcm%s", e.n, e.a, e.d, ax)
            end
            log.info("[test-gunrec2] " .. table.concat(out, ", ")); rec = nil
        end
    end)
end)
