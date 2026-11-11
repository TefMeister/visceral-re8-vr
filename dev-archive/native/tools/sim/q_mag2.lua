-- q_mag2.lua (rv.py -f): on the flat screen, tell visceral_re8_mag2.lua that an extra magazine is in the hand, with the
-- "hand's hold" 0.30 m in front of the camera, turned 60 degrees so its side shows. Set E.mag2 = { role = 1|2, rounds = n }
-- to show it, E.mag2 = nil to stop. 2026-11-11 (twomag.h); the plugin writes these slots itself in VR.
if not E.mag2_hooked then
    E.mag2_hooked = true
    re.on_application_entry("UpdateBehavior", function()
        local m = E.mag2
        if not m then return end
        pcall(function()
            local b = visceral_re8_bridge
            local cx = sdk.get_primary_camera():call("get_GameObject"):call("get_Transform")
            local cp, cr = cx:call("get_Position"), cx:call("get_Rotation")
            local f = cr * Vector3f.new(0.0, -0.02, -0.30)
            local h = math.rad(30)
            local q = cr * Quaternion.new(math.cos(h), 0, math.sin(h), 0)
            b.w(228, cp.x + f.x); b.w(229, cp.y + f.y); b.w(230, cp.z + f.z)
            b.w(231, q.x); b.w(232, q.y); b.w(233, q.z); b.w(234, q.w)
            b.w(227, m.role); b.w(235, m.rounds)
            b.w(226, b.r(0) + 1)
        end)
    end)
end
return "hooked"
