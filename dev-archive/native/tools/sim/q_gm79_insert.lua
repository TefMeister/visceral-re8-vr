-- q_gm79_insert.lua (rv.py -f): where the GM 79's insert point (bridge 164-168) sits against its barrel joints, in the gun's own
-- axes (cm: right, up, forward). 2026-11-25, Tefa: "the shell insert point is off to the right by quite a bit".
local b = rawget(_G, "visceral_re8_bridge")
local v = rawget(_G, "re8vr"); local w = v and v.weapon
if not b or not w then return "no bridge or no weapon" end
local go; pcall(function() go = w:call("get_GameObject") end)
if go == nil then pcall(function() go = w:get_field("<owner>k__BackingField") end) end
local tf = go and go:call("get_Transform"); if not tf then return "no gun transform" end
local gp, gq = tf:call("get_Position"), tf:call("get_Rotation")
local inv = gq:inverse()
local function local_cm(p) local d = inv * (p - gp); return string.format("right %+.1f up %+.1f fwd %+.1f", d.x * 100, d.y * 100, d.z * 100) end
local out = {}
local ins = Vector3f.new(b.r(164), b.r(165), b.r(166))
out[#out + 1] = string.format("insert zone r %.1f cm on %.0f: %s", b.r(167) * 100, b.r(168), local_cm(ins))
for _, n in ipairs({ "Carrier", "Ammo01", "Ammo02", "Sight", "vfx_muzzle1", "vfx_muzzle2", "Lever" }) do
    local j = tf:call("getJointByName", n)
    if j then
        local par = j:call("get_Parent"); local pn = par and par:call("get_Name") or "-"
        out[#out + 1] = string.format("%-12s (under %s): %s", n, pn, local_cm(j:call("get_Position")))
    end
end
local ctl = b.r and nil
return table.concat(out, "\n")
