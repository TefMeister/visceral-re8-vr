-- visceral_re8_bridge.lua -- the go-between for Visceral RE8's native code (2026-10-15, new code).
--
-- Same job as visceral-re2-vr's visceral_bridge.lua: REFramework's plugin API (1.15) gives C++ no VR buttons and no
-- rumble, so this file copies the headset, the controllers and the buttons into one shared System.Single[] every
-- frame, and fires the rumble the plugin asks for. It decides nothing.
-- Village extra: the VR layer is praydog's re8_vr.lua, so a few of its `re8vr` readings, and the globals the
-- not-yet-ported Hands Off files publish, ride along too. Each block says which ported file needs it.
--
-- Hand-over: the plugin picks a game method to hook on its first frame and names it in
-- reframework/data/visceral_re8/mailbox.json; this file passes the array to that method, the plugin recognises it by
-- its sentinel, keeps it, skips the original, and writes 1 into the ACK slot.
-- Slot map must match src/bridge.h.

local TAG = "[visceral-re8-bridge]"
local N = 96
local S_FRAME, S_HMD = 0, 1
local S_LGRIP, S_LTRIG, S_RGRIP, S_RTRIG = 2, 3, 4, 5
local S_LA, S_LB, S_RA, S_RB = 6, 7, 8, 9
local S_RUMBLE_L, S_RUMBLE_R = 10, 13          -- amp, seconds, hz each
local S_HMD_POS, S_HMD_ROT, S_LPOS, S_RPOS = 16, 19, 23, 26
local S_ACK, S_SENTINEL = 30, 31
local S_LGRIP_AXIS, S_RGRIP_AXIS, S_LGRIP_OTHER = 32, 33, 34
local S_RE8VR, S_GRIPPING_WEAPON, S_HANDS_W_OK, S_LHAND_W, S_RHAND_W = 35, 36, 37, 38, 41
local S_WEAPON_AUTO = 44
local S_IN_HOLSTER_ZONE, S_IN_FLASHLIGHT_ZONE, S_MASTER_OFF = 45, 46, 47
local S_NATIVE_HAPTICS = 56
local S_CAN_USE_HANDS, S_IS_RELOADING, S_AIMING, S_RECOIL_FLAGS = 57, 58, 59, 60
-- reload.cpp / rack.cpp (2026-10-18)
local S_LROT, S_RROT, S_CAM_POS, S_CAM_ROT = 64, 68, 72, 75
local S_IN_AMMO_ZONE, S_CUTSCENE, S_RELOAD_BUSY, S_HAND_STATE, S_POSE_LOCK = 79, 80, 81, 82, 83
local S_HUD_PING = 87     -- the plugin bumps it after an ammo change: refresh the game's remaining-ammo display
local REMAIN_AMMO_GUI = 1927694450   -- Andyalpa's ETHAN_REMAIN_AMMO_HASH (re8_vr_ammo_hud.lua)
local hud_ping_seen = 0
local S_SLIDE_HAND = 84   -- x, y, z: the hand on the slide, nudged in cm (gun axes: right, up, forward), saved below
local SLIDE_HAND_FILE = "visceral_re8/slide_hand.json"
local slide_hand = { x = 0.0, y = 0.0, z = 0.0 }
pcall(function() local d = json.load_file(SLIDE_HAND_FILE); if type(d) == "table" then for k, _ in pairs(slide_hand) do if type(d[k]) == "number" then slide_hand[k] = d[k] end end end end)
local LEFT_NAMES = { [0] = "free", "grip (praydog's two-hand)", "on the slide / bolt", "on the pump", "holding a magazine", "holding a round" }
local pose_lock = false
local SENTINEL = 54321.0
local HANDOVER_EVERY_FRAMES = 180
local HANDOVER_TRIES = 10
local MAILBOX_FILE = "visceral_re8/mailbox.json"

local arr = nil
local frame, last_handover, handovers, attached, rumbles = 0, 0, 0, false, 0   -- first hand-over after ~3 s: at frame 1 the plugin has not hooked its mailbox yet and the real setter ran with our array (a caught access violation, 2026-10-18)
local mailbox_name = "(not read yet)"

local function safe(fn) local ok, v = pcall(fn); if ok then return v end; return nil end

-- Camera Jitter BeG0nE (2026-10-19, Tefa: "log everything"; wired as Visceral RE2's bridge does it): the head pose as
-- read, the camera as the game takes it and each picture presented go to %LOCALAPPDATA%\BeG0nE\jitter\ while the
-- headset is live. jitterlog.lua sits beside this file; without it nothing is recorded and nothing else changes.
local jl_ok, jl = pcall(require, "jitterlog")
if jl_ok and type(jl) == "table" then jl.init("visceral-re8-vr", "openxr") else jl = nil end
local jl_live = false
local function ypr(q)
    local f = q * Vector3f.new(0, 0, -1)
    local u = q * Vector3f.new(0, 1, 0)
    local yaw = math.deg(math.atan(f.x, -f.z))
    local pitch = math.deg(math.asin(math.max(-1, math.min(1, f.y))))
    local rr = q * Vector3f.new(1, 0, 0)
    local roll = math.deg(math.atan(-rr.y, u.y))
    return yaw, pitch, roll
end
local function jl_pose(vr)
    if not jl then return end
    local q = safe(function() return vr:get_transform(0):to_quat() end)
    local p = safe(function() return vr:get_position(0) end)
    if q and type(q.w) == "number" then
        local yaw, pitch, roll = ypr(q)
        jl.pose(yaw, pitch, roll, p and p.x or 0, p and p.y or 0, p and p.z or 0)
    end
end
local function jl_camera()
    if not jl or not jl.is_on() then return end
    local m = safe(function() return sdk.get_primary_camera():call("get_WorldMatrix") end)
    local q = m and safe(function() return m:to_quat() end)
    if q and type(q.w) == "number" then
        local yaw, pitch, roll = ypr(q)
        local p = safe(function() return m[3] end)
        jl.camera(yaw, pitch, roll, p and p.x or 0, p and p.y or 0, p and p.z or 0)
    end
    jl.present()
end
local function r(slot) return arr:read_float(0x20 + slot * 4) end   -- 0x20 = element 0; the plugin checks it by the sentinel
local function w(slot, v) arr:write_float(0x20 + slot * 4, v or 0.0) end
local function wb(slot, b) w(slot, b and 1 or 0) end
local function w3(slot, v)
    if v and type(v.x) == "number" then w(slot, v.x); w(slot + 1, v.y); w(slot + 2, v.z) else w(slot, 0); w(slot + 1, 0); w(slot + 2, 0) end
end
local function w4(slot, q)
    if q and type(q.w) == "number" then w(slot, q.x); w(slot + 1, q.y); w(slot + 2, q.z); w(slot + 3, q.w)
    else w(slot, 0); w(slot + 1, 0); w(slot + 2, 0); w(slot + 3, 1) end
end

local function setup()
    arr = sdk.create_managed_array("System.Single", N)
    if not arr then log.error(TAG .. " could not create the array"); return false end
    arr:add_ref()
    for i = 0, N - 1 do w(i, 0.0) end
    w(S_LGRIP_AXIS, -1); w(S_RGRIP_AXIS, -1)
    w(S_SENTINEL, SENTINEL)
    log.info(TAG .. " array ready")
    return true
end

local function handover()
    if handovers >= HANDOVER_TRIES then return end
    handovers = handovers + 1
    local choice = safe(function() return json.load_file(MAILBOX_FILE) end)
    local t = choice and choice.type and sdk.find_type_definition(choice.type)
    local m = t and choice.method and t:get_method(choice.method)
    if not m then
        mailbox_name = "(no mailbox.json yet)"
        log.info(TAG .. " hand-over #" .. handovers .. ": the plugin has not named its mailbox yet")
    else
        mailbox_name = choice.type .. "." .. choice.method
        log.info(TAG .. " hand-over #" .. handovers .. " at frame " .. frame .. " through " .. mailbox_name)
        pcall(function() m:call(nil, arr) end)
    end
    if handovers == HANDOVER_TRIES then log.warn(TAG .. " no answer from visceral_re8_native.dll after " .. HANDOVER_TRIES .. " tries") end
end

local function poses(vr)
    w3(S_HMD_POS, safe(function() return vr:get_position(0) end))
    local q = safe(function() return vr:get_rotation(0):to_quat() end)   -- get_rotation is a Matrix4x4f in Lua (RE2 b111)
    if q and type(q.w) == "number" then w(S_HMD_ROT, q.x); w(S_HMD_ROT + 1, q.y); w(S_HMD_ROT + 2, q.z); w(S_HMD_ROT + 3, q.w)
    else w(S_HMD_ROT, 0); w(S_HMD_ROT + 1, 0); w(S_HMD_ROT + 2, 0); w(S_HMD_ROT + 3, 1) end
    local c = safe(function() return vr:get_controllers() end)
    if c and c[1] then w3(S_LPOS, safe(function() return vr:get_position(c[1]) end)); w4(S_LROT, safe(function() return vr:get_rotation(c[1]):to_quat() end)) end
    if c and c[2] then w3(S_RPOS, safe(function() return vr:get_position(c[2]) end)); w4(S_RROT, safe(function() return vr:get_rotation(c[2]):to_quat() end)) end
    -- reload.cpp / rack.cpp: the game camera, so room space and the world can be turned into each other
    local tf = safe(function() return sdk.get_primary_camera():call("get_GameObject"):call("get_Transform") end)
    w3(S_CAM_POS, tf and safe(function() return tf:call("get_Position") end))
    w4(S_CAM_ROT, tf and safe(function() return tf:call("get_Rotation") end))
end

-- haptics.cpp: the grip axes, -1 when vrmod has none (re8_vr_haptics.lua read_grip_axis)
local function grip_axis(vr, joy)
    if not joy then return -1 end
    local a = safe(function()
        if vr.get_action_grip_axis then return vr:get_action_grip_axis(joy) end
        if vr.get_grip_axis then return vr:get_grip_axis(joy) end
        return nil
    end)
    return tonumber(a) or -1
end

-- haptics.cpp: the other left-grip signals (re8_vr_haptics.lua read_left_grip, its last three tests)
local function left_grip_other(re8vr)
    local fn = rawget(_G, "__re8_holster_get_left_grip")
    if type(fn) == "function" and safe(fn) == true then return true end
    if re8vr and re8vr.is_holding_left_grip == true then return true end
    local vrc = rawget(_G, "vrc_manager")
    if vrc and vrc.has_controllers and safe(function() return vrc:has_controllers() end) then
        local lc = vrc.controllers_list and vrc.controllers_list[1]
        if lc and vrc.Actions and vrc.Actions.GRIP then
            return safe(function() return lc:is_action_active(vrc.Actions.GRIP) end) == true
        end
    end
    return false
end

local function alive(obj)
    return obj ~= nil and safe(function() return obj.get_address == nil or obj:get_address() ~= 0 end) == true
end

-- recoil.cpp: re8_vr_recoil.lua player_is_aiming, as it was (the gun's aim states, else the camera's gun aim)
local AIM_METHODS = { "get_isAimIdle", "get_isAimAttack", "get_isAimStart", "get_isAttack" }
local function aiming(re8vr)
    local order = re8vr and re8vr.order
    if order == nil then return false end
    local gun = safe(function() return order:call("get_playerGun") end)
    if gun ~= nil then
        for _, m in ipairs(AIM_METHODS) do
            if safe(function() return gun:call(m) end) == true then return true end
        end
    end
    local cam = safe(function() return order:call("get_playerCamera") end)
    return cam ~= nil and safe(function() return cam:call("get_isGunAim") end) == true
end
-- S_RECOIL_FLAGS bit order = src/bridge.h RecoilFlag (none of the Hands Off files sets these; other mods may)
local RECOIL_GLOBALS = { "__vr_block_left_hand_ik", "__vr_block_fire_when_empty", "__vr_manual_reload_enabled",
    "__vr_mag_dropped", "__vr_ammo_dropped", "__vr_needs_pump", "__vr_needs_rack" }

-- haptics.cpp: praydog's re8vr table and the Hands Off globals the unported files publish
local function village_readings()
    local re8vr = rawget(_G, "re8vr")
    wb(S_RE8VR, re8vr ~= nil)
    wb(S_GRIPPING_WEAPON, re8vr and re8vr.was_gripping_weapon == true)
    local lh = re8vr and re8vr.last_left_hand_position
    local rh = re8vr and re8vr.last_right_hand_position
    local hands = lh and rh and type(lh.x) == "number" and type(rh.x) == "number"
    wb(S_HANDS_W_OK, hands)
    if hands then w3(S_LHAND_W, lh); w3(S_RHAND_W, rh) end
    local weapon = re8vr and re8vr.weapon
    wb(S_WEAPON_AUTO, alive(weapon) and safe(function() return weapon:call("enableFullAuto") end) == true)
    wb(S_LGRIP_OTHER, left_grip_other(re8vr))
    wb(S_IN_HOLSTER_ZONE, rawget(_G, "__vr_in_holster_zone") == true)
    wb(S_IN_FLASHLIGHT_ZONE, rawget(_G, "__vr_in_head_flashlight_zone") == true)
    wb(S_MASTER_OFF, rawget(_G, "__vr_reloaded_master_enabled") == false)
    -- recoil.cpp (re8_vr_recoil.lua): its three re8vr readings and the other mods' globals it checked
    wb(S_CAN_USE_HANDS, not (re8vr and re8vr.can_use_hands == false))
    wb(S_IS_RELOADING, re8vr and re8vr.is_reloading == true)
    wb(S_AIMING, aiming(re8vr))
    local bits = 0
    for i, name in ipairs(RECOIL_GLOBALS) do
        if rawget(_G, name) == true then bits = bits | (1 << (i - 1)) end
    end
    w(S_RECOIL_FLAGS, bits)
    -- reload.cpp: Andyalpa's left-hip ammo spot is our ammo pouch; the pose switch; the block-pose stand-down
    wb(S_IN_AMMO_ZONE, rawget(_G, "__vr_in_ammo_holster_zone") == true)
    wb(S_CUTSCENE, re8vr and re8vr.is_in_cutscene == true)
    wb(S_POSE_LOCK, pose_lock)
    w(S_SLIDE_HAND, slide_hand.x); w(S_SLIDE_HAND + 1, slide_hand.y); w(S_SLIDE_HAND + 2, slide_hand.z)
    -- 2026-10-19: the rifle showed 0/0 after a reload until the trigger was pulled. Do what the game's own HUD code does on
    -- a change: apply the remaining-ammo driver to its UI and ask its order to show the remaining ammo.
    local ping = r(S_HUD_PING)
    if ping ~= hud_ping_seen then
        hud_ping_seen = ping
        pcall(function()
            local gm = sdk.get_managed_singleton("app.GUIManager")
            local h = gm and gm:call("findGUI", REMAIN_AMMO_GUI)
            local drv = h and h:call("get_driver")
            if not drv then return end
            pcall(function() drv:call("applyToUI") end)
            local order = nil
            pcall(function() order = drv:call("get_order") end)
            if not order then pcall(function() order = drv:get_field("guiOrder") end) end
            if order then
                pcall(function() order:call("cancelHide") end)
                local mode, item = nil, nil
                pcall(function() mode = drv:call("get_mode") end)
                pcall(function() item = drv:call("get_itemID") end)
                if mode ~= nil and item ~= nil then pcall(function() order:call("showRemainAmmo", mode, item) end) end
            end
        end)
    end
    rawset(_G, "__visceral_reload_busy", attached and r(S_RELOAD_BUSY) == 1.0 or nil)
end

local function buttons()
    local vr = _G.vrmod
    local live = vr and safe(function() return vr:is_hmd_active() and vr:is_using_controllers() end) == true
    wb(S_HMD, live)
    if jl and live ~= jl_live then
        jl_live = live
        if live then jl.vr_on() else jl.vr_off() end
        log.info(TAG .. " jitter recording " .. (live and "ON" or "OFF"))
    end
    if live then jl_pose(vr) end
    if not live then
        for s = S_LGRIP, S_RB do w(s, 0) end
        w(S_LGRIP_AXIS, -1); w(S_RGRIP_AXIS, -1)
        return
    end
    poses(vr)
    local lj = safe(function() return vr:get_left_joystick() end)
    local rj = safe(function() return vr:get_right_joystick() end)
    local grip = safe(function() return vr:get_action_grip() end)
    local trig = safe(function() return vr:get_action_trigger() end)
    local a = safe(function() return vr:get_action_a_button() end)
    local b = safe(function() return vr:get_action_b_button() end)
    local function on(action, joy)
        if not action or not joy then return 0 end
        return safe(function() return vr:is_action_active(action, joy) end) == true and 1 or 0
    end
    w(S_LGRIP, on(grip, lj)); w(S_LTRIG, on(trig, lj)); w(S_RGRIP, on(grip, rj)); w(S_RTRIG, on(trig, rj))
    w(S_LA, on(a, lj)); w(S_LB, on(b, lj)); w(S_RA, on(a, rj)); w(S_RB, on(b, rj))
    w(S_LGRIP_AXIS, grip_axis(vr, lj)); w(S_RGRIP_AXIS, grip_axis(vr, rj))
end

local function rumble()
    local vr = _G.vrmod
    if not vr then return end
    local function fire(slot, getter)
        local amp, sec, hz = r(slot), r(slot + 1), r(slot + 2)
        if amp <= 0 then return end
        w(slot, 0); w(slot + 1, 0)
        local joy = safe(getter)
        if not joy or sec <= 0 then return end
        rumbles = rumbles + 1
        pcall(function() vr:trigger_haptic_vibration(0.0, sec, hz, amp, joy) end)
    end
    fire(S_RUMBLE_L, function() return vr:get_left_joystick() end)
    fire(S_RUMBLE_R, function() return vr:get_right_joystick() end)
end

re.on_pre_application_entry("UpdateHID", function()
    if not arr and not setup() then return end
    frame = frame + 1
    w(S_FRAME, frame)
    if not attached then
        if r(S_ACK) == 1.0 then
            attached = true
            log.info(TAG .. " plugin answered at frame " .. frame)
        elseif frame - last_handover > HANDOVER_EVERY_FRAMES then
            last_handover = frame
            handover()
        end
    end
    -- re8_vr.lua (our copy) stands its two rumble forwards down while this is true; see src/haptics.h
    rawset(_G, "__visceral_native_haptics", attached and r(S_NATIVE_HAPTICS) == 1.0)
    rumble()
    buttons()
    village_readings()
end)

re.on_application_entry("BeginRendering", function() jl_camera() end)   -- REFramework's "post" hook (RE2 note 2026-10-14)

_G.visceral_re8_bridge = {
    ready = function() return arr ~= nil end,
    attached = function() return attached end,
    r = function(slot) return r(slot) end,
    w = function(slot, v) w(slot, v) end,
}

re.on_draw_ui(function()
    if imgui.tree_node("Visceral RE8 reload") then
        if arr then imgui.text("Left hand: " .. (LEFT_NAMES[math.floor(r(S_HAND_STATE) + 0.5)] or "?")) end
        local changed, v = imgui.checkbox("Hold this pose (a magazine stays in the hand, the hand stays on the slide)", pose_lock)
        if changed then pose_lock = v end
        imgui.text("The left hand on the slide (cm, along the gun):")
        local moved = false
        for _, k in ipairs({ "x", "y", "z" }) do
            local label = ({ x = "right (+) / left (-)", y = "up (+) / down (-)", z = "forward (+) / back (-)" })[k]
            local c, nv = imgui.slider_float(label, slide_hand[k], -15.0, 15.0, "%.1f")
            if c then slide_hand[k] = nv; moved = true end
        end
        if moved then pcall(function() json.dump_file(SLIDE_HAND_FILE, slide_hand) end) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Visceral RE8 bridge") then
        imgui.text(string.format("frame %d  attached=%s  rumbles fired %d", frame, tostring(attached), rumbles))
        imgui.text("mailbox: " .. mailbox_name)
        if arr then
            imgui.text(string.format("L grip %.0f (axis %.2f) trig %.0f  |  R grip %.0f (axis %.2f) trig %.0f",
                r(S_LGRIP), r(S_LGRIP_AXIS), r(S_LTRIG), r(S_RGRIP), r(S_RGRIP_AXIS), r(S_RTRIG)))
            imgui.text(string.format("re8vr %.0f  gun docked %.0f  full-auto %.0f  plugin rumble %.0f",
                r(S_RE8VR), r(S_GRIPPING_WEAPON), r(S_WEAPON_AUTO), r(S_NATIVE_HAPTICS)))
        end
        imgui.tree_pop()
    end
end)
