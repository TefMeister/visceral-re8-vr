-- visceral_re8_weapon_probe.lua -- rebuild 2, a PROBE (2026-11-27, /ms). Not part of the mod; comes out again.
--
-- Tefa: "when holding out Lemi and running, hand is shaking with the pistol like it hasn't before"; "like a real
-- weapon would shake in hand when running ... an irregular wobble"; the same with the knife; walking too.
-- The walk file of that run: the wrists stay on the controllers while moving (under 0.3 mm a picture). So the
-- question is whether the WEAPON moves against the hand that holds it.
--
-- What this does: once a picture, after everything is placed (LockScene), it takes the weapon's place and turn as
-- seen from the right hand joint. A weapon fixed in the hand gives the same numbers every picture. Once a second
-- it logs how far they strayed inside that second, and whether the player was moving.
local TAG = "[visceral-re8-weapon-probe]"
local WINDOW_S = 1.0

local hand, hand_owner = nil, nil
local told_weapon = nil
local n, t0 = 0, os.clock()
local first_p, first_q = nil, nil
local max_cm, max_deg = 0.0, 0.0
local last_pos, moved_m = nil, 0.0
local hand_step_cm = 0.0
local last_hand = nil

local function weapon_transform()
    local w = re8vr and re8vr.weapon
    if w == nil then return nil end
    local ok, go = pcall(w.call, w, "get_GameObject")
    if not ok or go == nil then go = w:get_field("<owner>k__BackingField") end
    if go == nil then return nil end
    return go:call("get_Transform"), go
end

local function quat_angle_deg(a, b)
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
    if d > 1.0 then d = 1.0 end
    return math.deg(2.0 * math.acos(d))
end

local function step()
    if re8vr == nil or re8vr.player == nil or re8vr.transform == nil then return end
    local pt = re8vr.transform
    if hand == nil or hand_owner ~= pt then
        hand = pt:call("getJointByName", "R_Hand")
        hand_owner = pt
        if hand == nil then return end
    end
    local wt, go = weapon_transform()
    if wt == nil then return end
    if told_weapon ~= wt then
        told_weapon = wt
        local parent = wt:call("get_Parent")
        local pj = nil
        pcall(function() pj = wt:call("get_ParentJoint") end)
        log.info(string.format("%s weapon in hand: %s; its parent: %s; parent joint: %s", TAG,
            tostring(go:call("get_Name")), parent and tostring(parent:call("get_GameObject"):call("get_Name")) or "none", tostring(pj)))
        first_p = nil
    end
    local hp, hq = hand:call("get_Position"), hand:call("get_Rotation")
    local wp, wq = wt:call("get_Position"), wt:call("get_Rotation")
    local inv = hq:inverse()
    local rel_p = inv * (wp - hp)
    local rel_q = inv * wq
    if first_p == nil then first_p, first_q = rel_p, rel_q end
    local cm = (rel_p - first_p):length() * 100.0
    local deg = quat_angle_deg(rel_q, first_q)
    if cm > max_cm then max_cm = cm end
    if deg > max_deg then max_deg = deg end
    local pp = pt:call("get_Position")
    if last_pos ~= nil then moved_m = moved_m + (pp - last_pos):length() end
    last_pos = pp
    n = n + 1
    local now = os.clock()
    if now - t0 >= WINDOW_S then
        log.info(string.format("%s %s (%.1f m/s): the weapon strayed %.2f cm and %.2f deg against the right hand, %d pictures", TAG,
            (moved_m / (now - t0)) > 0.5 and "MOVING" or "still", moved_m / (now - t0), max_cm, max_deg, n))
        n, t0, first_p, max_cm, max_deg, moved_m = 0, now, nil, 0.0, 0.0, 0.0
    end
end

re.on_application_entry("LockScene", function()
    local ok, e = pcall(step)
    if not ok and told_weapon ~= "failed" then
        told_weapon = "failed"
        log.info(TAG .. " FAILED: " .. tostring(e))
    end
end)

log.info(TAG .. " loaded")
