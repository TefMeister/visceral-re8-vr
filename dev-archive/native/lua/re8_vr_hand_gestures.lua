if reframework:get_game_name() ~= "re8" then
    return {}
end

-- Visceral RE8 (2026-10-24): while a save loads, the game's getters throw (System.NullReferenceException) and REFramework
-- logs every throw: 7,568 lines in 14 s on 2026-10-24, the frame rate down to 22-28 fps meanwhile. A getter that fails is
-- not asked again for VRZ.BACKOFF_S seconds. In play these getters answer, so nothing changes there.
local VRZ = { BACKOFF_S = 0.5, until_t = {} }
function VRZ.waiting(name) return os.clock() < (VRZ.until_t[name] or 0) end
function VRZ.failed(name) VRZ.until_t[name] = os.clock() + VRZ.BACKOFF_S end

-- Grip/trigger finger poses. Left hand while one-handed armed; both hands when bare.
-- Right hand never overrides a weapon pose. Native two-hand hold suppresses left gestures.

local LOG_TAG = "[re8_vr_hand_gestures]"
local CFG_PATH = "re8_vr/re8_hand_gestures.json"

-- Ulnar pin cache (NOT wrist L_Hand).
local lh_ulnar = {
    joints = {},
    joint_names = {},
    targets = {},
    src = "",
    n = 0,
    last_refresh_t = 0.0,
    last_applied = 0,
    armed = false,
    need_base_arm = false,
}

local function read_grip_axis(joystick)
    if not vrmod or not joystick then return -1 end
    local axis = nil
    pcall(function()
        if vrmod.get_action_grip_axis then
            axis = vrmod:get_action_grip_axis(joystick)
        elseif vrmod.get_grip_axis then
            axis = vrmod:get_grip_axis(joystick)
        end
    end)
    return tonumber(axis) or -1
end

local function get_left_joystick()
    local lj = nil
    pcall(function()
        local h = rawget(_G, "__re8_holster_get_left_joystick")
        if type(h) == "function" then lj = h() end
        if not lj and vrmod then lj = vrmod:get_left_joystick() end
    end)
    return lj
end

local function get_right_joystick()
    local rj = nil
    pcall(function()
        local h = rawget(_G, "__re8_holster_get_right_joystick")
        if type(h) == "function" then rj = h() end
        if rj then return end
        local vrc = rawget(_G, "vrc_manager")
        if vrc and vrc.has_controllers and vrc:has_controllers() then
            local rc = vrc.controllers_list and vrc.controllers_list[2]
            if rc and rc.joystick then
                rj = rc.joystick
                return
            end
        end
        if vrmod then rj = vrmod:get_right_joystick() end
    end)
    return rj
end

local re8vr = rawget(_G, "re8vr")
local vrmod = rawget(_G, "vrmod")

local GESTURE_KEYS = { "finger_point", "fist", "thumbs_up" }
local GESTURE_LABELS = { "Finger point (grip)", "Fist (grip+trigger)", "Thumbs up (trigger)" }

local LEFT_HAND_POSE_BONES = {
    "L_IndexF1", "L_IndexF2", "L_IndexF3",
    "L_MiddleF1", "L_MiddleF2", "L_MiddleF3",
    "L_RingF1", "L_RingF2", "L_RingF3",
    "L_PinkyF1", "L_PinkyF2", "L_PinkyF3",
    "L_Thumb1", "L_Thumb2", "L_Thumb3",
}

local LEFT_HAND_POSE_GROUPS = {
    { id = "index", label = "Index", bones = {
        "L_IndexF1", "L_IndexF2", "L_IndexF3",
    }},
    { id = "middle", label = "Middle", bones = {
        "L_MiddleF1", "L_MiddleF2", "L_MiddleF3",
    }},
    { id = "ring", label = "Ring", bones = {
        "L_RingF1", "L_RingF2", "L_RingF3",
    }},
    { id = "little", label = "Little", bones = {
        "L_PinkyF1", "L_PinkyF2", "L_PinkyF3",
    }},
    { id = "thumb", label = "Thumb", bones = {
        "L_Thumb1", "L_Thumb2", "L_Thumb3",
    }},
}

local function default_gesture_entry()
    return { apply_enabled = true, pose = {}, emv = {} }
end

local function default_cfg()
    return {
        enabled = true,
        blend_sec = 0.12,
        idle_timeout_sec = 3.0,
        preview_sec = 2.0,
        mirror_from_right = { negate_x = false, negate_y = false, negate_z = false },
        gestures = {
            finger_point = default_gesture_entry(),
            fist = default_gesture_entry(),
            thumbs_up = default_gesture_entry(),
        },
    }
end

local CFG = default_cfg()

local runtime = {
    bare_hands = true,
    two_handed = false,
    gate_reason = "init",
    lh = {
        factor = 0.0,
        last_t = nil,
        last_input_t = 0.0,
        want_key = nil,
        applied_key = nil,
        was_applying = false,
        grip = false,
        trigger = false,
        joints = 0,
        gate = "init",
        pose_from_key = nil,
        pose_to_key = nil,
        pose_blend = 1.0,
    },
    rh = {
        factor = 0.0,
        last_t = nil,
        last_input_t = 0.0,
        want_key = nil,
        applied_key = nil,
        was_applying = false,
        grip = false,
        trigger = false,
        joints = 0,
        gate = "init",
        pose_from_key = nil,
        pose_to_key = nil,
        pose_blend = 1.0,
    },
    -- Compat aliases used by UI
    factor = 0.0,
    want_key = nil,
    grip = false,
    trigger = false,
    last_joints = 0,
    last_joints_rh = 0,
    apply_rh = false,
}

local ui = {
    status = nil,
    edit_key = "finger_point",
    selected_bone = "L_IndexF1",
    preview = {
        finger_point = { active = false, until_t = 0.0 },
        fist = { active = false, until_t = 0.0 },
        thumbs_up = { active = false, until_t = 0.0 },
    },
    bone_clipboard = nil,
    pose_clipboard = nil,
    rh_buffer = { pose = {}, emv = {}, status = nil },
}

local poser = nil
local grip_action = nil
local trigger_action = nil

local function sc(obj, method, ...)
    if obj == nil then return nil end
    local ok, r = pcall(function(...)
        return obj:call(method, ...)
    end, ...)
    if ok then return r end
    return nil
end

local function collect_transforms()
    local fn = rawget(_G, "__re8_holster_collect_transforms")
    if type(fn) == "function" then
        local ok, list = pcall(fn)
        if ok and type(list) == "table" then return list end
    end
    return {}
end

local function ensure_cfg_shape()
    if type(CFG) ~= "table" then CFG = default_cfg() end
    if type(CFG.gestures) ~= "table" then CFG.gestures = {} end
    for _, key in ipairs(GESTURE_KEYS) do
        local g = CFG.gestures[key]
        if type(g) ~= "table" then
            CFG.gestures[key] = default_gesture_entry()
        else
            if type(g.pose) ~= "table" then g.pose = {} end
            if g.apply_enabled == nil then g.apply_enabled = true end
        end
    end
    if type(CFG.mirror_from_right) ~= "table" then
        CFG.mirror_from_right = { negate_x = false, negate_y = false, negate_z = false }
    end
end

local function save_cfg()
    ensure_cfg_shape()
    pcall(function()
        json.dump_file(CFG_PATH, CFG)
    end)
end

local function mark_dirty()
    save_cfg()
end

local function load_cfg()
    local ok, data = pcall(function() return json.load_file(CFG_PATH) end)
    if ok and type(data) == "table" then
        CFG = data
    else
        CFG = default_cfg()
    end
    ensure_cfg_shape()
end

local function init_poser()
    local ok, mod = pcall(function() return require("re8_vr_hand_poser") end)
    if not ok or not mod then
        log.warn(LOG_TAG .. " poser require failed: " .. tostring(mod))
        poser = nil
        return
    end
    poser = mod
    if poser.init then
        poser.init({
            sc = sc,
            collect_transforms = collect_transforms,
        })
    end
end

local function pose_has_bones(pose)
    return type(pose) == "table" and next(pose) ~= nil
end

local function entry_has_pose(entry)
    if type(entry) ~= "table" then return false end
    if pose_has_bones(entry.pose) then return true end
    if type(entry.emv) == "table" and next(entry.emv) ~= nil then return true end
    return false
end

local function gesture_entry(key)
    ensure_cfg_shape()
    return CFG.gestures[key] or default_gesture_entry()
end

local function euler_to_emv_vec(e)
    return string.format("vec:%s %s %s",
        tostring(e[1] or 0), tostring(e[2] or 0), tostring(e[3] or 0))
end

local function copy_euler(e)
    if type(e) ~= "table" then return nil end
    return { tonumber(e[1]) or 0, tonumber(e[2]) or 0, tonumber(e[3]) or 0 }
end

local function mirror_hand_euler(e, negate)
    if not e then return nil end
    local out = { e[1], e[2], e[3] }
    if negate then
        if negate.x then out[1] = -out[1] end
        if negate.y then out[2] = -out[2] end
        if negate.z then out[3] = -out[3] end
    end
    return out
end

local function left_bone_to_right(bone)
    if type(bone) ~= "string" then return nil end
    if bone:sub(1, 2) == "L_" then
        return "R_" .. bone:sub(3)
    end
    return nil
end

local function right_bone_to_left(bone)
    if type(bone) ~= "string" then return nil end
    if bone:sub(1, 2) == "R_" then
        return "L_" .. bone:sub(3)
    end
    return nil
end

local function find_joint_by_name(tf, name)
    if not tf or not name then return nil end
    return sc(tf, "getJointByName", name)
end

local function find_right_joint_on_tf(tf, left_bone)
    if not tf or not left_bone then return nil end
    local r_name = left_bone_to_right(left_bone)
    if r_name then
        return find_joint_by_name(tf, r_name)
    end
    return nil
end

local function lerp_angle(a, b, t)
    local d = ((b - a + 540.0) % 360.0) - 180.0
    return a + d * t
end

local function read_joint_euler(joint)
    if not joint then return nil end
    local e = sc(joint, "get_LocalEulerAngle")
    if e and type(e.x) == "number" then
        return { tonumber(e.x) or 0, tonumber(e.y) or 0, tonumber(e.z) or 0 }
    end
    return nil
end

local function write_joint_euler(joint, tx, ty, tz)
    if not joint then return false end
    local ok = false
    pcall(function()
        joint:call("set_LocalEulerAngle", Vector3f.new(tx, ty, tz))
        ok = true
    end)
    return ok
end

local function rh_src_priority(src)
    if src == "UpperBodyMesh" then return 110 end
    if src == "player" or src == "player_go" then return 105 end
    if src == "RArmMesh" then return 100 end
    if src == "LArmMesh" then return 40 end
    return 10
end

local function ang_wrap_deg(a)
    a = tonumber(a) or 0.0
    while a > 180.0 do a = a - 360.0 end
    while a < -180.0 do a = a + 360.0 end
    return a
end

local function ang_diff_deg(from_a, to_a)
    return ang_wrap_deg((tonumber(to_a) or 0.0) - (tonumber(from_a) or 0.0))
end

local function ang_add_deg(a, d)
    return ang_wrap_deg((tonumber(a) or 0.0) + (tonumber(d) or 0.0))
end

local function read_base_euler(joint)
    if not joint then return nil end
    local q = sc(joint, "get_BaseLocalRotation")
    if q and type(q.w) == "number" then
        local eu = nil
        pcall(function()
            if q.to_euler then eu = q:to_euler() end
        end)
        if eu and type(eu.x) == "number" then
            return { tonumber(eu.x) or 0, tonumber(eu.y) or 0, tonumber(eu.z) or 0 }
        end
    end
    return nil
end

-- Cached right-hand joint map (avoid refresh_skeleton + TF scan every apply).
local rh_skel = {
    joints = {},      -- left_bone_key -> right joint
    left_joints = {}, -- left_bone_key -> left joint (same TF, for rest-delta)
    bind_r = {},
    bind_l = {},
    src = "",
    n = 0,
    last_refresh_t = 0.0,
    last_targets = {}, -- left_bone_key -> {x,y,z}
    last_factor = 0.0,
    last_mode = "none",
    last_ms = 0.0,
}

local function joint_alive(j)
    if not j then return false end
    local ok = false
    pcall(function()
        if j.get_address then ok = (j:get_address() or 0) ~= 0 else ok = true end
    end)
    return ok
end

local function find_left_joint_on_tf(tf, left_bone)
    if not tf or not left_bone then return nil end
    return find_joint_by_name(tf, left_bone)
end

local function refresh_rh_skeleton(force)
    local now = os.clock()
    if not force and rh_skel.n >= 3 and (now - (rh_skel.last_refresh_t or 0)) < 0.35 then
        local alive_n = 0
        for _, j in pairs(rh_skel.joints) do
            if joint_alive(j) then alive_n = alive_n + 1 end
        end
        if alive_n >= 3 then return true end
    end

    local list = collect_transforms()
    if type(list) ~= "table" or #list == 0 then
        rh_skel.n = 0
        return false
    end

    local best = nil
    local best_pri = -1
    local best_n = 0
    for _, entry_tf in ipairs(list) do
        local tf = entry_tf and entry_tf.tf
        if tf then
            local n = 0
            for _, bone in ipairs(LEFT_HAND_POSE_BONES) do
                if find_right_joint_on_tf(tf, bone) then n = n + 1 end
            end
            local pri = rh_src_priority(entry_tf.src or "")
            if n > best_n or (n == best_n and n >= 3 and pri > best_pri) then
                best_n = n
                best_pri = pri
                best = entry_tf
            end
        end
    end

    rh_skel.joints = {}
    rh_skel.left_joints = {}
    rh_skel.bind_r = {}
    rh_skel.bind_l = {}
    rh_skel.n = 0
    rh_skel.src = ""
    if not best or not best.tf or best_n < 3 then
        rh_skel.last_refresh_t = now
        return false
    end

    local tf = best.tf
    rh_skel.src = tostring(best.src or "?")
    for _, bone in ipairs(LEFT_HAND_POSE_BONES) do
        local rj = find_right_joint_on_tf(tf, bone)
        if rj then
            rh_skel.joints[bone] = rj
            rh_skel.bind_r[bone] = read_base_euler(rj)
            rh_skel.n = rh_skel.n + 1
            local lj = find_left_joint_on_tf(tf, bone)
            if lj then
                rh_skel.left_joints[bone] = lj
                rh_skel.bind_l[bone] = read_base_euler(lj)
            end
        end
    end
    rh_skel.last_refresh_t = now
    return rh_skel.n >= 3
end

-- Map saved left pose → right local euler (rest-delta when binds exist).
local function left_pose_to_right_euler(bone, left_target, negate)
    local rj = rh_skel.joints[bone]
    if not rj then return nil, nil end
    local l_bind = rh_skel.bind_l[bone]
    local r_bind = rh_skel.bind_r[bone]
    if l_bind and r_bind and type(left_target) == "table" then
        local dx = ang_diff_deg(l_bind[1], left_target[1])
        local dy = ang_diff_deg(l_bind[2], left_target[2])
        local dz = ang_diff_deg(l_bind[3], left_target[3])
        local delta = mirror_hand_euler({ dx, dy, dz }, negate)
        return {
            ang_add_deg(r_bind[1], delta[1]),
            ang_add_deg(r_bind[2], delta[2]),
            ang_add_deg(r_bind[3], delta[3]),
        }, "rest_delta"
    end
    return mirror_hand_euler(left_target, negate), "absolute"
end

local function write_rh_targets(targets, factor)
    if type(targets) ~= "table" then return 0 end
    factor = tonumber(factor) or 1.0
    if factor <= 0.0001 then return 0 end
    local full = factor >= 0.9999
    local applied = 0
    for bone, target in pairs(targets) do
        local joint = rh_skel.joints[bone]
        if joint and type(target) == "table" then
            local tx = tonumber(target[1]) or 0
            local ty = tonumber(target[2]) or 0
            local tz = tonumber(target[3]) or 0
            if not full then
                local cur = read_joint_euler(joint)
                if cur then
                    tx = lerp_angle(cur[1], tx, factor)
                    ty = lerp_angle(cur[2], ty, factor)
                    tz = lerp_angle(cur[3], tz, factor)
                end
            end
            if write_joint_euler(joint, tx, ty, tz) then
                applied = applied + 1
            end
        end
    end
    return applied
end

-- Mirror left finger pose onto right finger joints (cached, single best TF).
local function apply_right_hand_mirrored(entry, factor)
    local t0 = os.clock()
    factor = tonumber(factor) or 1.0
    if factor <= 0.0001 then return 0 end
    if not entry_has_pose(entry) then return 0 end

    if not refresh_rh_skeleton(false) then
        refresh_rh_skeleton(true)
    end
    if rh_skel.n < 3 then
        return 0
    end

    local mir = CFG.mirror_from_right or {}
    local negate = {
        x = mir.negate_x == true,
        y = mir.negate_y == true,
        z = mir.negate_z == true,
    }
    local pose = entry.pose
    local targets = {}
    local mode_counts = { rest_delta = 0, absolute = 0 }
    for _, bone in ipairs(LEFT_HAND_POSE_BONES) do
        local target = pose and pose[bone]
        if type(target) == "table" then
            local e, mode = left_pose_to_right_euler(bone, target, negate)
            if e then
                targets[bone] = e
                mode_counts[mode or "absolute"] = (mode_counts[mode or "absolute"] or 0) + 1
            end
        end
    end

    local applied = write_rh_targets(targets, factor)
    if applied == 0 then
        refresh_rh_skeleton(true)
        applied = write_rh_targets(targets, factor)
    end

    rh_skel.last_targets = targets
    rh_skel.last_factor = factor
    rh_skel.last_mode = (mode_counts.rest_delta or 0) >= (mode_counts.absolute or 0) and "rest_delta" or "absolute"
    rh_skel.last_ms = (os.clock() - t0) * 1000.0
    return applied
end

local function reapply_rh_cached(factor)
    if rh_skel.n < 3 or type(rh_skel.last_targets) ~= "table" then return 0 end
    if next(rh_skel.last_targets) == nil then return 0 end
    return write_rh_targets(rh_skel.last_targets, factor or rh_skel.last_factor or 1.0)
end

local function blend_sec()
    return tonumber(CFG.blend_sec) or 0.12
end

local function idle_timeout_sec()
    return tonumber(CFG.idle_timeout_sec) or 3.0
end

local function preview_sec()
    return tonumber(CFG.preview_sec) or 2.0
end

local GRIP_AXIS_ON = 0.65

local function ensure_grip_action()
    if not grip_action and vrmod then
        pcall(function() grip_action = vrmod:get_action_grip() end)
    end
    return grip_action
end

local function ensure_trigger_action()
    if not trigger_action and vrmod then
        pcall(function() trigger_action = vrmod:get_action_trigger() end)
    end
    return trigger_action
end

local function digital_grip(joystick)
    local action = ensure_grip_action()
    if not action or not joystick or not vrmod then return false end
    local ok, active = pcall(function()
        return vrmod:is_action_active(action, joystick)
    end)
    return ok and active == true
end

local function digital_trigger(joystick)
    local action = ensure_trigger_action()
    if not action or not joystick or not vrmod then return false end
    local ok, active = pcall(function()
        return vrmod:is_action_active(action, joystick)
    end)
    return ok and active == true
end

-- Per-hand grip. Prefer grip *axis* so shared OpenXR digital grip cannot
-- light up the opposite hand when only one controller is squeezed.
local function read_left_grip()
    local lj = get_left_joystick()
    local rj = get_right_joystick()
    local la = read_grip_axis(lj)
    local ra = read_grip_axis(rj)

    if la >= GRIP_AXIS_ON then
        return true
    end
    -- Right axis clearly pressed: never treat as left grip.
    if ra >= GRIP_AXIS_ON then
        return false
    end

    local dig = digital_grip(lj)
    if dig then
        return true
    end

    local holster = false
        local fn = rawget(_G, "__re8_holster_get_left_grip")
    if type(fn) == "function" then
        local ok, v = pcall(fn)
        holster = ok and v == true
    end
    local re8g = re8vr and re8vr.is_holding_left_grip == true
    -- Only trust published grip flags when right digital is also false.
    if (holster or re8g) and not digital_grip(rj) then
        return true
    end
    -- Per-controller VRC fallback (index 1 = left).
    local vrc = rawget(_G, "vrc_manager")
    if vrc and vrc.has_controllers and vrc:has_controllers() then
        local lc = vrc.controllers_list and vrc.controllers_list[1]
        if lc and vrc.Actions and vrc.Actions.GRIP then
            local ok, v = pcall(function() return lc:is_action_active(vrc.Actions.GRIP) end)
            if ok and v == true and not digital_grip(rj) then
                return true
            end
        end
    end
    return false
end

local function read_left_trigger()
    local lj = get_left_joystick()
    local rj = get_right_joystick()
    if digital_trigger(lj) then return true end
    local fn = rawget(_G, "__re8_holster_get_left_trigger")
    if type(fn) == "function" then
        local ok, v = pcall(fn)
        if ok and v == true and not digital_trigger(rj) then return true end
    end
    return false
end

local function read_right_grip()
    -- Prefer published right-grip helper (works on cold start).
    local hfn = rawget(_G, "__re8_holster_get_right_grip")
    if type(hfn) == "function" then
        local ok, v = pcall(hfn)
        if ok and v == true then return true end
    end

    local lj = get_left_joystick()
    local rj = get_right_joystick()
    local la = read_grip_axis(lj)
    local ra = read_grip_axis(rj)

    if ra >= GRIP_AXIS_ON then
        return true
    end
    if digital_grip(rj) then
        return true
    end
    local vrc = rawget(_G, "vrc_manager")
    if vrc and vrc.has_controllers and vrc:has_controllers() then
        local rc = vrc.controllers_list and vrc.controllers_list[2]
        if rc and vrc.Actions and vrc.Actions.GRIP then
            local ok, v = pcall(function() return rc:is_action_active(vrc.Actions.GRIP) end)
            if ok and v == true then
                return true
            end
            local axis = nil
            pcall(function()
                if rc.get_axis then axis = rc:get_axis(vrc.Actions.GRIP) end
            end)
            if type(axis) == "number" and axis >= GRIP_AXIS_ON then
                return true
            end
        end
    end
    if la >= GRIP_AXIS_ON then
        return false
    end
    return false
end

local function read_right_trigger()
    local hfn = rawget(_G, "__re8_holster_get_right_trigger")
    if type(hfn) == "function" then
        local ok, v = pcall(hfn)
        if ok and v == true then return true end
    end
    local rj = get_right_joystick()
    if digital_trigger(rj) then return true end
    if rj and vrmod then
        local axis = nil
        pcall(function()
            if vrmod.get_action_trigger_axis then
                axis = vrmod:get_action_trigger_axis(rj)
            elseif vrmod.get_trigger_axis then
                axis = vrmod:get_trigger_axis(rj)
            end
        end)
        if type(axis) == "number" and axis >= 0.65 then return true end
    end
    return false
end

local function map_gesture(grip, trigger)
    if grip and trigger then return "fist" end
    if grip and not trigger then return "finger_point" end
    if trigger and not grip then return "thumbs_up" end
    return nil
end

-- Native two-hand clip (update_hand_ik):
-- was_gripping_weapon = (dist(LH, weapon_grip_point) <= 0.1)
--                    || (was_gripping && left_grip held)
-- Always suppress LH gestures while native two-hand is latched.
-- (Controller distance alone is wrong for long guns — forend can be >0.42m from RH.)
-- Palm crush after two-hand is handled by ulnar dirty restore.
local TWO_HAND_ENTER_M = 0.32
local TWO_HAND_EXIT_M = 0.42
local TWO_HAND_REST_ENTER_M = 0.14
local TWO_HAND_REST_EXIT_M = 0.22
local two_hand_prox = {
    sticky = false,
    rest_sticky = false,
    dist = 99.0,
}

local function vec3_len_delta(a, b)
    if not a or not b then return 99.0 end
    if type(a.x) ~= "number" or type(b.x) ~= "number" then return 99.0 end
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function controller_hands_distance()
    if not vrmod then return 99.0 end
    local lp, rp = nil, nil
    pcall(function()
        local lj = vrmod:get_left_joystick()
        local rj = vrmod:get_right_joystick()
        if lj then lp = vrmod:get_position(lj) end
        if rj then rp = vrmod:get_position(rj) end
    end)
    local d = vec3_len_delta(lp, rp)
    if d < 90.0 then return d end
    return vec3_len_delta(rawget(_G, "__vr_lh_world"), rawget(_G, "__vr_rh_world"))
end

local function is_two_handed_rest()
    if not re8vr then
        two_hand_prox.rest_sticky = false
        return false
    end
    if re8vr.was_gripping_weapon == true then
        two_hand_prox.rest_sticky = true
        return true
    end
    local d = controller_hands_distance()
    two_hand_prox.dist = d
    if d <= TWO_HAND_REST_ENTER_M then
        two_hand_prox.rest_sticky = true
        return true
    end
    if two_hand_prox.rest_sticky and d <= TWO_HAND_REST_EXIT_M then
        return true
    end
    two_hand_prox.rest_sticky = false
    return false
end

local function is_two_handed_support(grip_active)
    if not re8vr then
        two_hand_prox.sticky = false
        return false
    end

    local ctrl_dist = controller_hands_distance()
    two_hand_prox.dist = ctrl_dist

    -- Native two-hand latch: always yield LH gestures (long guns included).
    -- Check before hip/medicine/flashlight zones so RH hovering a slot cannot
    -- un-suppress and overwrite native two-hand grab fingers.
    if re8vr.was_gripping_weapon == true then
        two_hand_prox.sticky = true
        return true
    end

    if rawget(_G, "__vr_in_holster_zone") == true then
        two_hand_prox.sticky = false
        return false
    end
    if rawget(_G, "__vr_in_medicine_zone") == true then
        two_hand_prox.sticky = false
        return false
    end
    if rawget(_G, "__vr_in_head_flashlight_zone") == true then
        two_hand_prox.sticky = false
        return false
    end

    if grip_active ~= true then
        two_hand_prox.sticky = false
        return false
    end

    -- Pre-latch approach: controllers near each other before native 0.1m clip.
    if ctrl_dist <= TWO_HAND_ENTER_M then
        two_hand_prox.sticky = true
        return true
    end
    if two_hand_prox.sticky and ctrl_dist <= TWO_HAND_EXIT_M then
        return true
    end

    two_hand_prox.sticky = false
    return false
end

local function get_player_component(type_name)
    if not re8vr or not re8vr.player or not type_name then return nil end
    local td = sdk.find_type_definition(type_name)
    if not td then return nil end
    local rt = nil
    pcall(function() rt = td:get_runtime_type() end)
    if not rt then return nil end
    local c = nil
    pcall(function()
        c = re8vr.player:call("getComponent(System.Type)", rt)
    end)
    return c
end

local function get_equip_controller()
    local updater = get_player_component("app.PlayerUpdaterFPS")
    if updater and not VRZ.waiting("get_equipController") then -- Visceral RE8: failed a moment ago (loading)
        local em = sc(updater, "get_equipController")
        if em then return em end
        VRZ.failed("get_equipController")
    end
    return get_player_component("app.EquipController")
end

local function is_bare_hands()
    if not re8vr then return true end
    if re8vr.weapon then
        local eq = false
        pcall(function() eq = re8vr.weapon:call("get_isEquip") == true end)
        if eq then return false end
    end
    local em = get_equip_controller()
    if em then
        local ok, none = pcall(function() return em:call("get_isNoneEquiped") end)
        if ok and none == true then return true end
        local w = sc(em, "get_equipWeaponRight")
        if w then return false end
    end
    return re8vr.weapon == nil
end

local function is_cinematic_blocking()
    local fn = rawget(_G, "__vr_is_cinematic_blocking")
    if type(fn) == "function" then
        local ok, v = pcall(fn)
        if ok and v == true then return true end
    end
    if not re8vr then return false end
    if re8vr.is_in_cutscene then return true end
    if re8vr.is_motion_play then return true end
    if re8vr.is_arm_jacked then return true end
    if re8vr.can_use_hands == false then return true end
    return false
end

local function reload_owns_left_hand()
    if rawget(_G, "__vr_ammo_in_left_hand") == true then return true, "ammo_in_hand" end
    if rawget(_G, "__vr_ammo_insert_active") == true then return true, "ammo_insert" end
    if rawget(_G, "__vr_ammo_dropped") == true then return true, "ammo_dropped" end
    if rawget(_G, "__vr_block_left_hand_ik") == true then return true, "block_lh_ik" end
    if rawget(_G, "__vr_slide_rack_active") == true then return true, "slide_rack" end
    local blend = tonumber(rawget(_G, "__vr_slide_dock_blend_factor")) or 0
    if blend > 0.001 then return true, "slide_dock" end
    local target = tonumber(rawget(_G, "__vr_slide_hand_dock_target")) or 0
    if target > 0.5 then return true, "slide_approach" end
    if rawget(_G, "__vr_left_hand_pose_ammo_active") == true then return true, "lhp_ammo" end
    if rawget(_G, "__vr_left_hand_pose_slide_active") == true then return true, "lhp_slide" end
    if rawget(_G, "__vr_left_hand_pose_slide_back_active") == true then return true, "lhp_slide_back" end
    if rawget(_G, "__vr_grab_hand_pose_lh_active") == true then return true, "grab_lh" end
    if rawget(_G, "__vr_inspect_hand_pose_lh_active") == true then return true, "inspect_lh" end
    return false, nil
end

local function any_preview_active()
    for _, key in ipairs(GESTURE_KEYS) do
        local p = ui.preview[key]
        if p and p.active then return true, key end
    end
    return false, nil
end

local function tick_previews()
    local now = os.clock()
    for _, key in ipairs(GESTURE_KEYS) do
        local p = ui.preview[key]
        if p and p.active and now >= (p.until_t or 0) then
            p.active = false
        end
    end
end

local function extend_preview(key)
    local p = ui.preview[key]
    if type(p) ~= "table" then return end
    p.active = true
    p.until_t = os.clock() + preview_sec()
end

local function cancel_preview(key)
    if key then
        local p = ui.preview[key]
        if p then p.active = false; p.until_t = 0 end
        return
    end
    for _, k in ipairs(GESTURE_KEYS) do
        local p = ui.preview[k]
        if p then p.active = false; p.until_t = 0 end
    end
end

-- side: "lh" | "rh"
-- Returns: allow, key, reason, hard_yield
local function evaluate_hand_gates(side, grip, trigger)
    if CFG.enabled ~= true or rawget(_G, "__vr_reloaded_master_enabled") == false then
        return false, nil, "disabled", false
    end
    if is_cinematic_blocking() then
        return false, nil, "cinematic", true
    end
    if re8vr and re8vr.wants_block == true then
        return false, nil, "block_gesture", true
    end

    local prev_on, prev_key = any_preview_active()
    -- Preview drives left hand (capture target); RH preview only when bare.
    if prev_on then
        if side == "lh" then
            return true, prev_key, "preview", false
        end
        if side == "rh" and runtime.bare_hands == true then
            return true, prev_key, "preview", false
        end
    end

    if side == "lh" then
        local busy, why = reload_owns_left_hand()
        if busy then
            return false, nil, why or "reload", true
        end
        local bare = is_bare_hands()
        runtime.bare_hands = bare
        local two = false
        if not bare then
            two = is_two_handed_support(grip)
        end
        runtime.two_handed = two
        if not bare and two then
            lh_ulnar.need_base_arm = true
            lh_ulnar.armed = false
            lh_ulnar.targets = {}
            lh_ulnar.last_applied = 0
            return false, nil, "two_handed", true
        end
    else
        -- Right hand: bare hands only — never override weapon RH pose.
        local bare = is_bare_hands()
        runtime.bare_hands = bare
        if not bare then
            return false, nil, "weapon_rh", true
        end
        if rawget(_G, "__vr_grab_hand_pose_rh_active") == true then
            return false, nil, "grab_rh", true
        end
        if rawget(_G, "__vr_inspect_hand_pose_rh_active") == true then
            return false, nil, "inspect_rh", true
        end
        if rawget(_G, "__re8_medicine_hand_pose_rh_active") == true
            or rawget(_G, "__re8_medicine_in_hand") == true then
            return false, nil, "med_rh", true
        end
    end

    local mapped = map_gesture(grip, trigger)
    if not mapped then
        return false, nil, "no_input", false
    end
    local entry = gesture_entry(mapped)
    if entry.apply_enabled == false then
        return false, nil, "gesture_disabled", false
    end
    if not entry_has_pose(entry) then
        return false, nil, "no_pose", false
    end
    return true, mapped, "ok", false
end

local function update_hand_blend(hand, want)
    local now = os.clock()
    local last = hand.last_t or now
    local dt = math.max(0.0, math.min(0.1, now - last))
    hand.last_t = now
    hand._dt = dt
    local sec = blend_sec()
    if sec <= 0.0001 then
        hand.factor = want and 1.0 or 0.0
        return dt
    end
    local target = want and 1.0 or 0.0
    local step = dt / sec
    if hand.factor < target then
        hand.factor = math.min(target, hand.factor + step)
    elseif hand.factor > target then
        hand.factor = math.max(target, hand.factor - step)
    end
    return dt
end

local function lerp_pose_tables(pose_a, pose_b, t)
    t = math.max(0.0, math.min(1.0, tonumber(t) or 1.0))
    local out = {}
    local keys = {}
    if type(pose_a) == "table" then
        for bone, _ in pairs(pose_a) do keys[bone] = true end
    end
    if type(pose_b) == "table" then
        for bone, _ in pairs(pose_b) do keys[bone] = true end
    end
    for bone, _ in pairs(keys) do
        local a = pose_a and pose_a[bone]
        local b = pose_b and pose_b[bone]
        if type(a) == "table" and type(b) == "table" then
            out[bone] = {
                lerp_angle(tonumber(a[1]) or 0, tonumber(b[1]) or 0, t),
                lerp_angle(tonumber(a[2]) or 0, tonumber(b[2]) or 0, t),
                lerp_angle(tonumber(a[3]) or 0, tonumber(b[3]) or 0, t),
            }
        elseif type(b) == "table" then
            if t >= 0.999 then
                out[bone] = { tonumber(b[1]) or 0, tonumber(b[2]) or 0, tonumber(b[3]) or 0 }
            elseif type(a) ~= "table" and t > 0.001 then
                -- No from-bone: ease in toward b (apply layer still lerps from live joint via factor).
                out[bone] = { tonumber(b[1]) or 0, tonumber(b[2]) or 0, tonumber(b[3]) or 0 }
            end
        elseif type(a) == "table" then
            if t <= 0.001 then
                out[bone] = { tonumber(a[1]) or 0, tonumber(a[2]) or 0, tonumber(a[3]) or 0 }
            end
        end
    end
    return out
end

local function build_hand_apply_entry(hand)
    local to_key = hand.want_key or hand.applied_key or hand.pose_to_key
    if not to_key then return nil end
    local to_entry = gesture_entry(to_key)
    if not entry_has_pose(to_entry) then return nil end

    local from_key = hand.pose_from_key
    local blend = tonumber(hand.pose_blend) or 1.0
    if from_key and from_key ~= to_key and blend < 0.999 then
        local from_entry = gesture_entry(from_key)
        if entry_has_pose(from_entry) then
            return {
                pose = lerp_pose_tables(from_entry.pose, to_entry.pose, blend),
                emv = nil,
            }
        end
    end
    return to_entry
end

-- Pin L_Palm only. Do not pin L_Hand (wrist).
local ULNAR_PIN_NAMES = {
    "L_Palm",
}

local function refresh_lh_ulnar_cache(force)
    local now = os.clock()
    if not force and lh_ulnar.n >= 1 and (now - (lh_ulnar.last_refresh_t or 0)) < 0.5 then
        local alive = 0
        for _, j in pairs(lh_ulnar.joints) do
            if joint_alive(j) then alive = alive + 1 end
        end
        if alive >= 1 then return true end
    end
    local list = collect_transforms()
    lh_ulnar.joints = {}   -- flat list of joints to write
    lh_ulnar.joint_names = {} -- parallel names
    lh_ulnar.n = 0
    lh_ulnar.src = ""
    local srcs = {}
    if type(list) ~= "table" then
        lh_ulnar.last_refresh_t = now
        return false
    end
    for _, entry in ipairs(list) do
        local tf = entry and entry.tf
        if tf then
            local got = 0
            for _, name in ipairs(ULNAR_PIN_NAMES) do
                local j = sc(tf, "getJointByName", name)
                if j then
                    lh_ulnar.n = lh_ulnar.n + 1
                    lh_ulnar.joints[lh_ulnar.n] = j
                    lh_ulnar.joint_names[lh_ulnar.n] = name
                    got = got + 1
                end
            end
            if got > 0 then
                srcs[#srcs + 1] = tostring(entry.src or "?") .. ":" .. tostring(got)
            end
        end
    end
    lh_ulnar.src = table.concat(srcs, "|")
    lh_ulnar.last_refresh_t = now
    return lh_ulnar.n >= 1
end

local function arm_ulnar_targets_from_current()
    if not refresh_lh_ulnar_cache(false) then
        refresh_lh_ulnar_cache(true)
    end
    lh_ulnar.targets = {}
    local got = 0
    local prefer_base = runtime.is_hold == true or lh_ulnar.need_base_arm == true
    local dirty_arm = lh_ulnar.need_base_arm == true
    -- Name-keyed targets so multi-mesh refresh cannot scramble index mapping.
    for i = 1, lh_ulnar.n do
        local joint = lh_ulnar.joints[i]
        local name = lh_ulnar.joint_names[i]
        if name and not lh_ulnar.targets[name] then
            local cur = nil
            local force_safe = dirty_arm == true
            if force_safe then
                -- Never freeze post-grab deform crush into the pin.
                cur = read_base_euler(joint)
                if not cur then
                    cur = { 0, 0, 0 }
                end
            elseif prefer_base then
                cur = read_base_euler(joint)
            end
            if not cur then
                -- Dirty restore: never snapshot live grab-warped eulers.
                if dirty_arm then
                    cur = { 0, 0, 0 }
                else
                    cur = read_joint_euler(joint)
                end
            end
            if not cur then
                cur = read_base_euler(joint)
            end
            if not cur then
                cur = { 0, 0, 0 }
            end
            if cur then
                lh_ulnar.targets[name] = { cur[1], cur[2], cur[3] }
                got = got + 1
            end
        end
    end
    lh_ulnar.armed = got > 0
    if lh_ulnar.armed then
        lh_ulnar.need_base_arm = false
    end
    return lh_ulnar.armed
end

local function clear_ulnar_pin()
    lh_ulnar.armed = false
    lh_ulnar.targets = {}
    lh_ulnar.last_applied = 0
end

local function apply_lh_ulnar_pin(factor)
    factor = tonumber(factor) or 1.0
    if factor <= 0.0001 then
        clear_ulnar_pin()
        return 0
    end
    if not lh_ulnar.armed then
        arm_ulnar_targets_from_current()
    end
    if not lh_ulnar.armed then
        lh_ulnar.last_applied = 0
        return 0
    end
    if not refresh_lh_ulnar_cache(false) then
        refresh_lh_ulnar_cache(true)
    end
    local full = factor >= 0.9999
    local applied = 0
    for i = 1, lh_ulnar.n do
        local joint = lh_ulnar.joints[i]
        local name = lh_ulnar.joint_names[i]
        local target = name and lh_ulnar.targets[name] or nil
        if joint and type(target) == "table" then
            local tx = tonumber(target[1]) or 0
            local ty = tonumber(target[2]) or 0
            local tz = tonumber(target[3]) or 0
            if not full then
                local cur = read_joint_euler(joint)
                if cur then
                    tx = lerp_angle(cur[1], tx, factor)
                    ty = lerp_angle(cur[2], ty, factor)
                    tz = lerp_angle(cur[3], tz, factor)
                end
            end
            if write_joint_euler(joint, tx, ty, tz) then
                applied = applied + 1
            end
        end
    end
    lh_ulnar.last_applied = applied
    return applied
end

local function apply_left_entry(entry, factor)
    if not entry_has_pose(entry) or factor <= 0.0001 then
        clear_ulnar_pin()
        return 0
    end
    local n = 0
    if poser and poser.apply_pl0000_pose then
        n = poser.apply_pl0000_pose(entry, factor) or 0
    end
    -- Pin pinky-side palm/F0 only (snapshot at gesture arm). Never wrist Hand_* .
    local un = apply_lh_ulnar_pin(factor)
    runtime.lh.joints = n
    runtime.last_joints = n
    runtime.lh.ulnar_n = un
    return n
end

local function apply_right_entry(entry, factor)
    if not entry_has_pose(entry) or factor <= 0.0001 then return 0 end
    local n = apply_right_hand_mirrored(entry, factor)
    runtime.rh.joints = n
    runtime.last_joints_rh = n
    return n
end

local function snap_hand_off(hand)
    hand.want_key = nil
    hand.factor = 0.0
    hand.applied_key = nil
    hand.was_applying = false
    hand.last_t = os.clock()
    hand.pose_from_key = nil
    hand.pose_to_key = nil
    hand.pose_blend = 1.0
    if hand == runtime.lh then
        clear_ulnar_pin()
    end
end

local function begin_pose_crossfade(hand, new_key)
    if not new_key then return end
    local prev = hand.pose_to_key or hand.applied_key
    if prev and prev ~= new_key and (hand.factor or 0) > 0.05 then
        hand.pose_from_key = prev
        hand.pose_blend = 0.0
    else
        hand.pose_from_key = nil
        hand.pose_blend = 1.0
    end
    hand.pose_to_key = new_key
end

local function advance_pose_crossfade(hand, dt)
    if (hand.pose_blend or 1) >= 0.999 then
        hand.pose_blend = 1.0
        hand.pose_from_key = nil
        return
    end
    local sec = blend_sec()
    if sec <= 0.0001 then
        hand.pose_blend = 1.0
        hand.pose_from_key = nil
        return
    end
    hand.pose_blend = math.min(1.0, (hand.pose_blend or 0) + dt / sec)
    if hand.pose_blend >= 0.999 then
        hand.pose_blend = 1.0
        hand.pose_from_key = nil
    end
end

local function tick_one_hand(side, hand, grip, trigger, now)
    hand.grip = grip
    hand.trigger = trigger
    if grip or trigger then
        hand.last_input_t = now
    end

    local allow, key, reason, hard_yield = evaluate_hand_gates(side, grip, trigger)
    hand.gate = reason

    local prev_on = reason == "preview"
    local idle = idle_timeout_sec()
    local idle_expired = (now - (hand.last_input_t or 0)) >= idle
    if idle_expired and not prev_on then
        allow = false
        key = nil
        if reason == "ok" or reason == "no_input" then
            hand.gate = "idle_timeout"
        end
    end

    if hard_yield then
        snap_hand_off(hand)
        return false
    end

    local new_want = allow and key or nil
    if new_want and new_want ~= hand.pose_to_key then
        begin_pose_crossfade(hand, new_want)
    end
    hand.want_key = new_want

    local dt = 0.0
    if prev_on then
        hand.factor = 1.0
        hand.last_t = now
        hand._dt = 0.05
        dt = 0.05
        advance_pose_crossfade(hand, dt)
    else
        dt = update_hand_blend(hand, new_want ~= nil)
        advance_pose_crossfade(hand, dt)
    end

    local applied = false
    local apply_fn = (side == "lh") and apply_left_entry or apply_right_entry
    local apply_key = hand.want_key or hand.applied_key
    if hand.factor > 0.001 and apply_key then
        local entry = build_hand_apply_entry(hand)
        if entry and apply_fn(entry, hand.factor) > 0 then
            applied = true
            if hand.want_key then
                hand.applied_key = hand.want_key
            end
        end
    end

    if not applied then
        if hand.factor <= 0.001 then
            hand.applied_key = nil
            hand.pose_from_key = nil
            hand.pose_to_key = nil
            hand.pose_blend = 1.0
        end
        if hand.was_applying and side == "lh" and poser and poser.clear_frozen then
            poser.clear_frozen()
        end
    end
    hand.was_applying = applied
    return applied
end

local function get_frame_count()
    if re and re.get_frame_count then
        local ok, n = pcall(function() return re.get_frame_count() end)
        if ok and type(n) == "number" then return n end
    end
    return math.floor(os.clock() * 90.0)
end

local last_tick_fc = -1
local sticky = {
    lh_entry = nil,
    lh_factor = 0.0,
    rh_factor = 0.0,
}

local function publish_globals(lh_on, rh_on, lh_name, rh_name)
    local active = lh_on or rh_on
    rawset(_G, "__vr_hand_gesture_active", active == true)
    local name = ""
    if lh_on and rh_on then
        name = "L:" .. tostring(lh_name or "") .. "|R:" .. tostring(rh_name or "")
    elseif lh_on then
        name = "L:" .. tostring(lh_name or "")
    elseif rh_on then
        name = "R:" .. tostring(rh_name or "")
    end
    rawset(_G, "__vr_hand_gesture_name", name)
end

local function tick_apply_sticky()
    if sticky.lh_factor > 0.001 and sticky.lh_entry then
        apply_left_entry(sticky.lh_entry, sticky.lh_factor)
    end
    if sticky.rh_factor > 0.001 then
        local n = reapply_rh_cached(sticky.rh_factor)
        runtime.rh.joints = n
        runtime.last_joints_rh = n
    end
end

local function tick_apply()
    local fc = get_frame_count()
    if fc == last_tick_fc then
        tick_apply_sticky()
        return
    end
    last_tick_fc = fc

    if not re8vr then re8vr = rawget(_G, "re8vr") end
    re8vr = rawget(_G, "re8vr") or re8vr
    vrmod = rawget(_G, "vrmod") or vrmod
    tick_previews()

    runtime.is_hold = false
    pcall(function()
        if not re8vr or not re8vr.order then return end
        local player_gun = re8vr.order:call("get_playerGun")
        if player_gun then
            for _, method_name in ipairs({ "get_isAimIdle", "get_isAimAttack", "get_isAimStart", "get_isAttack" }) do
                local ok, aiming = pcall(function() return player_gun:call(method_name) end)
                if ok and aiming == true then
                    runtime.is_hold = true
                    return
                end
            end
        end
        local player_camera = nil
        pcall(function() player_camera = re8vr.order:call("get_playerCamera") end)
        if player_camera then
            local ok, aiming = pcall(function() return player_camera:call("get_isGunAim") end)
            if ok and aiming == true then
                runtime.is_hold = true
            end
        end
    end)

    local lg = read_left_grip()
    local lt = read_left_trigger()
    local rg = read_right_grip()
    local rt = read_right_trigger()
    runtime.grip = lg
    runtime.trigger = lt
    runtime.bare_hands = is_bare_hands()

    do
        local support = false
        if not runtime.bare_hands then
            support = is_two_handed_rest() or is_two_handed_support(lg == true)
        else
            two_hand_prox.sticky = false
            two_hand_prox.rest_sticky = false
        end
        runtime.two_handed = support == true
        rawset(_G, "__re8_lh_weapon_support", support == true)
    end

    local now = os.clock()
    local lh_on = tick_one_hand("lh", runtime.lh, lg, lt, now)
    local rh_on = false
    if runtime.bare_hands then
        rh_on = tick_one_hand("rh", runtime.rh, rg, rt, now)
    else
        snap_hand_off(runtime.rh)
        runtime.rh.gate = "weapon_rh"
        runtime.rh.joints = 0
        runtime.last_joints_rh = 0
        rh_skel.last_targets = {}
    end

    if not rh_on or (runtime.rh.factor or 0) <= 0.001 then
        rh_skel.last_targets = {}
        sticky.rh_factor = 0.0
    else
        sticky.rh_factor = runtime.rh.factor or 0.0
    end

    if lh_on and (runtime.lh.factor or 0) > 0.001 then
        sticky.lh_entry = build_hand_apply_entry(runtime.lh)
        sticky.lh_factor = runtime.lh.factor or 0.0
    else
        sticky.lh_entry = nil
        sticky.lh_factor = 0.0
    end

    runtime.apply_rh = rh_on
    runtime.want_key = runtime.lh.want_key
    runtime.factor = runtime.lh.factor
    runtime.gate_reason = "L:" .. tostring(runtime.lh.gate) .. " R:" .. tostring(runtime.rh.gate)

    publish_globals(
        lh_on and runtime.lh.factor > 0.001,
        rh_on and runtime.rh.factor > 0.001,
        runtime.lh.applied_key,
        runtime.rh.applied_key)
end

local function capture_gesture(key)
    if not poser or not poser.capture_pl0000_pose then
        ui.status = "Capture failed — poser missing"
        return false
    end
    local cap, n = poser.capture_pl0000_pose()
    if not cap or not cap.pose then
        local st = poser.get_state and poser.get_state() or {}
        ui.status = string.format(
            "Capture failed (src=%s joints=%s)",
            tostring(st.src or "?"), tostring(st.joint_count or n or 0))
        return false
    end
    local entry = gesture_entry(key)
    entry.pose = cap.pose
    entry.emv = cap.emv
    CFG.gestures[key] = entry
    extend_preview(key)
    local bone_n = 0
    for _ in pairs(cap.pose) do bone_n = bone_n + 1 end
    local src = "?"
    if poser.get_state then
        local st = poser.get_state()
        src = tostring((st and (st.capture_src or st.src)) or "?")
    end
    ui.status = string.format("Captured %s (%d bones, src=%s)", key, bone_n, src)
    log.info(string.format("%s Captured %s: %d bones", LOG_TAG, key, bone_n))
    mark_dirty()
    return true
end

local function capture_gesture_from_right(key)
    if not poser or not poser.capture_pl0000_pose_from_right_mirrored then
        ui.status = "Mirror capture failed — poser missing"
        return false
    end
    local mir = CFG.mirror_from_right or {}
    local cap, n = poser.capture_pl0000_pose_from_right_mirrored({
        negate = {
            x = mir.negate_x == true,
            y = mir.negate_y == true,
            z = mir.negate_z == true,
        },
    })
    if not cap or not cap.pose then
        ui.status = string.format("R→L capture failed (right_bones=%s)", tostring(n or 0))
        return false
    end
    local entry = gesture_entry(key)
    entry.pose = cap.pose
    entry.emv = cap.emv
    CFG.gestures[key] = entry
    extend_preview(key)
    local bone_n = 0
    for _ in pairs(cap.pose) do bone_n = bone_n + 1 end
    ui.status = string.format(
        "R→L captured %s (%d bones, mode=%s)",
        key, bone_n, tostring(cap.mirror_mode or "?"))
    mark_dirty()
    return true
end

-- Editor-only: mirror current left pose into RH buffer (not live-applied).
local function copy_left_pose_to_right_buffer(key)
    local entry = gesture_entry(key)
    if not entry_has_pose(entry) then
        ui.rh_buffer.status = "No left pose to copy"
        return false
    end
    local mir = CFG.mirror_from_right or {}
    local negate = {
        x = mir.negate_x == true,
        y = mir.negate_y == true,
        z = mir.negate_z == true,
    }
    local pose = {}
    local emv = {}
    local n = 0
    for bone, e in pairs(entry.pose or {}) do
        local rb = left_bone_to_right(bone)
        if rb and type(e) == "table" then
            local me = mirror_hand_euler(copy_euler(e), negate)
            if me then
                pose[rb] = me
                emv[rb] = { _LocalEulerAngle = euler_to_emv_vec(me) }
                n = n + 1
            end
        end
    end
    ui.rh_buffer.pose = pose
    ui.rh_buffer.emv = emv
    ui.rh_buffer.status = string.format("L→R copied %d bones into editor buffer", n)
    ui.status = ui.rh_buffer.status
    return n > 0
end

-- Editor helper: take RH buffer and write mirrored values back into left gesture pose.
local function copy_right_buffer_to_left_pose(key)
    local rh = ui.rh_buffer
    if type(rh) ~= "table" or not pose_has_bones(rh.pose) then
        ui.status = "RH buffer empty — use L→R copy first or paste RH data"
        return false
    end
    local mir = CFG.mirror_from_right or {}
    local negate = {
        x = mir.negate_x == true,
        y = mir.negate_y == true,
        z = mir.negate_z == true,
    }
    local entry = gesture_entry(key)
    entry.pose = entry.pose or {}
    entry.emv = entry.emv or {}
    local n = 0
    for rb, e in pairs(rh.pose) do
        local lb = right_bone_to_left(rb)
        if lb and type(e) == "table" then
            local me = mirror_hand_euler(copy_euler(e), negate)
            if me then
                entry.pose[lb] = me
                entry.emv[lb] = { _LocalEulerAngle = euler_to_emv_vec(me) }
                n = n + 1
            end
        end
    end
    CFG.gestures[key] = entry
    extend_preview(key)
    ui.status = string.format("R buffer → L pose (%d bones) into %s", n, key)
    mark_dirty()
    return n > 0
end

local function copy_bone_to_clipboard(key, bone)
    local entry = gesture_entry(key)
    local e = entry.pose and entry.pose[bone]
    if not e then
        ui.status = "No data for bone " .. tostring(bone)
        return false
    end
    ui.bone_clipboard = {
        bone = bone,
        euler = copy_euler(e),
    }
    ui.status = "Copied bone " .. bone
    return true
end

local function paste_bone_from_clipboard(key, bone)
    local clip = ui.bone_clipboard
    if not clip or type(clip.euler) ~= "table" then
        ui.status = "Bone clipboard empty"
        return false
    end
    local entry = gesture_entry(key)
    entry.pose = entry.pose or {}
    entry.emv = entry.emv or {}
    local e = copy_euler(clip.euler)
    entry.pose[bone] = e
    entry.emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(e) }
    CFG.gestures[key] = entry
    extend_preview(key)
    ui.status = string.format("Pasted into %s", bone)
    mark_dirty()
    return true
end

local function copy_all_pose(key)
    local entry = gesture_entry(key)
    if not entry_has_pose(entry) then
        ui.status = "No pose to copy"
        return false
    end
    local pose = {}
    for bone, e in pairs(entry.pose or {}) do
        pose[bone] = copy_euler(e)
    end
    ui.pose_clipboard = { pose = pose }
    ui.status = "Copied all bones"
    return true
end

local function paste_all_pose(key)
    local clip = ui.pose_clipboard
    if not clip or type(clip.pose) ~= "table" then
        ui.status = "Pose clipboard empty"
        return false
    end
    local entry = gesture_entry(key)
    entry.pose = {}
    entry.emv = {}
    local n = 0
    for bone, e in pairs(clip.pose) do
        local ce = copy_euler(e)
        if ce then
            entry.pose[bone] = ce
            entry.emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(ce) }
            n = n + 1
        end
    end
    CFG.gestures[key] = entry
    extend_preview(key)
    ui.status = string.format("Pasted all (%d bones) into %s", n, key)
    mark_dirty()
    return true
end

local function draw_ui()
    if not imgui.tree_node("Hand Gestures") then
        return
    end
    ensure_cfg_shape()

    imgui.text("Left grip/trigger → left hand. Right grip/trigger → right hand (bare only).")
    imgui.text("Weapon: LH gestures until two-hand (native latch or LH near RH + grip).")
    imgui.text("Yields to reload (LH), cinematics, block.")

    local ch_en, v_en = imgui.checkbox("Enabled##hg_en", CFG.enabled == true)
    if ch_en then CFG.enabled = v_en; mark_dirty() end

    local blend = tonumber(CFG.blend_sec) or 0.12
    local c_bl, v_bl = imgui.drag_float("Blend sec##hg_blend", blend, 0.01, 0.0, 0.5, "%.2f")
    if c_bl then CFG.blend_sec = v_bl; mark_dirty() end
    imgui.text("Blend sec also smooths gesture→gesture finger transitions.")

    local idle = tonumber(CFG.idle_timeout_sec) or 3.0
    local c_id, v_id = imgui.drag_float("Idle timeout sec##hg_idle", idle, 0.1, 0.5, 30.0, "%.1f")
    if c_id then CFG.idle_timeout_sec = v_id; mark_dirty() end

    local prev = tonumber(CFG.preview_sec) or 2.0
    local c_ps, v_ps = imgui.drag_float("Preview sec##hg_prev", prev, 0.1, 0.5, 15.0, "%.1f")
    if c_ps then CFG.preview_sec = v_ps; mark_dirty() end

    local ctx_idx = 1
    for i, name in ipairs(GESTURE_KEYS) do
        if name == ui.edit_key then ctx_idx = i; break end
    end
    local c_ctx, idx = imgui.combo("Edit gesture##hg_ctx", ctx_idx, GESTURE_LABELS)
    if c_ctx and type(idx) == "number" and GESTURE_KEYS[idx] then
        ui.edit_key = GESTURE_KEYS[idx]
    end
    local edit_key = ui.edit_key or "finger_point"
    local entry = gesture_entry(edit_key)

    local ctx_apply = entry.apply_enabled ~= false
    local ch_ca, v_ca = imgui.checkbox("Apply this gesture##hg_apply_" .. edit_key, ctx_apply)
    if ch_ca then entry.apply_enabled = v_ca; mark_dirty() end

    local bone_n = 0
    if type(entry.pose) == "table" then
        for _ in pairs(entry.pose) do bone_n = bone_n + 1 end
    end
    imgui.text(string.format(
        "L: grip=%s trig=%s want=%s gate=%s f=%.2f(%d) | R: grip=%s trig=%s want=%s gate=%s f=%.2f(%d) | bare=%s",
        tostring(runtime.lh.grip),
        tostring(runtime.lh.trigger),
        tostring(runtime.lh.want_key or runtime.lh.applied_key or "-"),
        tostring(runtime.lh.gate or "-"),
        runtime.lh.factor or 0,
        tonumber(runtime.lh.joints) or 0,
        tostring(runtime.rh.grip),
        tostring(runtime.rh.trigger),
        tostring(runtime.rh.want_key or runtime.rh.applied_key or "-"),
        tostring(runtime.rh.gate or "-"),
        runtime.rh.factor or 0,
        tonumber(runtime.rh.joints) or 0,
        tostring(runtime.bare_hands)))
    imgui.text(string.format(
        "bones: %d | twoH=%s was_gripping=%s dist=%.2f sticky=%s | RH %s n=%d ms=%.2f src=%s",
        bone_n,
        tostring(runtime.two_handed),
        tostring(re8vr and re8vr.was_gripping_weapon == true),
        tonumber(two_hand_prox.dist) or 99.0,
        tostring(two_hand_prox.sticky == true),
        tostring(rh_skel.last_mode or "-"),
        tonumber(rh_skel.n) or 0,
        tonumber(rh_skel.last_ms) or 0,
        tostring(rh_skel.src or "-")))

    CFG.mirror_from_right = CFG.mirror_from_right or {
        negate_x = false, negate_y = false, negate_z = false,
    }
    local mir = CFG.mirror_from_right
    imgui.text("Mirror negate (R↔L transfers):")
    local cx, vx = imgui.checkbox("Negate X##hg_mir_x", mir.negate_x == true)
    if cx then mir.negate_x = vx; mark_dirty() end
    imgui.same_line()
    local cy, vy = imgui.checkbox("Negate Y##hg_mir_y", mir.negate_y == true)
    if cy then mir.negate_y = vy; mark_dirty() end
    imgui.same_line()
    local cz, vz = imgui.checkbox("Negate Z##hg_mir_z", mir.negate_z == true)
    if cz then mir.negate_z = vz; mark_dirty() end

    if imgui.button("Capture skeleton##hg_cap_" .. edit_key) then
        ui.status = "Capturing..."
        pcall(function() capture_gesture(edit_key) end)
    end
    imgui.same_line()
    if imgui.button("Capture R→L##hg_cap_rl_" .. edit_key) then
        ui.status = "Capturing R→L..."
        pcall(function() capture_gesture_from_right(edit_key) end)
    end
    imgui.same_line()
    if imgui.button("L→R copy##hg_lr_" .. edit_key) then
        pcall(function() copy_left_pose_to_right_buffer(edit_key) end)
    end
    imgui.same_line()
    if imgui.button("R buf→L##hg_rlbuf_" .. edit_key) then
        pcall(function() copy_right_buffer_to_left_pose(edit_key) end)
    end

    if imgui.button("Clear pose##hg_clr_" .. edit_key) then
        entry.pose = {}
        entry.emv = nil
        cancel_preview(edit_key)
        ui.status = "Cleared " .. edit_key
        mark_dirty()
    end
    imgui.same_line()
    if imgui.button("Preview##hg_pv_" .. edit_key) then
        extend_preview(edit_key)
    end
    imgui.same_line()
    if imgui.button("Stop preview##hg_sp_" .. edit_key) then
        cancel_preview(edit_key)
    end
    imgui.same_line()
    if imgui.button("Save##hg_save") then
        save_cfg()
        ui.status = "Saved"
    end

    imgui.separator()
    imgui.text("Bone clipboard:")
    local bone_list = LEFT_HAND_POSE_BONES
    local bone_idx = 1
    for i, b in ipairs(bone_list) do
        if b == ui.selected_bone then bone_idx = i; break end
    end
    local c_bn, bidx = imgui.combo("Bone##hg_bone", bone_idx, bone_list)
    if c_bn and type(bidx) == "number" and bone_list[bidx] then
        ui.selected_bone = bone_list[bidx]
    end
    local sel = ui.selected_bone or bone_list[1]
    if imgui.button("Copy bone##hg_cb") then
        copy_bone_to_clipboard(edit_key, sel)
    end
    imgui.same_line()
    if imgui.button("Paste bone##hg_pb") then
        paste_bone_from_clipboard(edit_key, sel)
    end
    imgui.same_line()
    if imgui.button("Copy all##hg_ca") then
        copy_all_pose(edit_key)
    end
    imgui.same_line()
    if imgui.button("Paste all##hg_pa") then
        paste_all_pose(edit_key)
    end
    if ui.bone_clipboard and ui.bone_clipboard.bone then
        imgui.text("Clipboard bone: " .. tostring(ui.bone_clipboard.bone))
    end
    if ui.rh_buffer and ui.rh_buffer.status then
        imgui.text_colored(tostring(ui.rh_buffer.status), 0xFF88CCFF)
    end

    if ui.status then
        imgui.text_colored(ui.status, 0xFF8888FF)
    end
    local pv = ui.preview[edit_key]
    if pv and pv.active then
        local left = math.max(0.0, (pv.until_t or 0) - os.clock())
        imgui.text_colored(string.format("Live preview %.1fs", left), 0xFF88FF88)
    end

    if bone_n > 0 and type(entry.pose) == "table" then
        for _, group in ipairs(LEFT_HAND_POSE_GROUPS) do
            if imgui.tree_node(group.label .. "##hg_grp_" .. edit_key .. "_" .. group.id) then
                for _, bone in ipairs(group.bones) do
                    local vec = entry.pose[bone]
                    if vec then
                        imgui.text_colored(bone, 0xFF88CCFF)
                        imgui.indent(12)
                        local vx2 = tonumber(vec[1]) or 0.0
                        local vy2 = tonumber(vec[2]) or 0.0
                        local vz2 = tonumber(vec[3]) or 0.0
                        local suf = "##hg_" .. edit_key .. "_" .. bone
                        local cx2, nx = imgui.drag_float("X" .. suf, vx2, 0.05, -180.0, 180.0, "%.2f")
                        if cx2 then
                            vec[1] = nx
                            if entry.emv then
                                entry.emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(vec) }
                            end
                            extend_preview(edit_key)
                            mark_dirty()
                        end
                        local cy2, ny = imgui.drag_float("Y" .. suf, vy2, 0.05, -180.0, 180.0, "%.2f")
                        if cy2 then
                            vec[2] = ny
                            if entry.emv then
                                entry.emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(vec) }
                            end
                            extend_preview(edit_key)
                            mark_dirty()
                        end
                        local cz2, nz = imgui.drag_float("Z" .. suf, vz2, 0.05, -180.0, 180.0, "%.2f")
                        if cz2 then
                            vec[3] = nz
                            if entry.emv then
                                entry.emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(vec) }
                            end
                            extend_preview(edit_key)
                            mark_dirty()
                        end
                        if imgui.button("Copy##hg_bc_" .. bone) then
                            copy_bone_to_clipboard(edit_key, bone)
                        end
                        imgui.same_line()
                        if imgui.button("Paste##hg_bp_" .. bone) then
                            paste_bone_from_clipboard(edit_key, bone)
                        end
                        imgui.unindent(12)
                    end
                end
                imgui.tree_pop()
            end
        end
    else
        imgui.text("No pose captured yet for this gesture.")
    end

    imgui.tree_pop()
end

-- Init
load_cfg()
init_poser()
local _t0 = os.clock()
runtime.lh.last_input_t = _t0
runtime.rh.last_input_t = _t0
log.info(LOG_TAG .. " loaded")

re.on_application_entry("UpdateMotion", function()
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("gestures.sticky_um") end
    pcall(tick_apply_sticky)
    if _on then _p.finish("gestures.sticky_um") end
end)

re.on_application_entry("LateUpdateBehavior", function()
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("gestures.apply_lu") end
    local ok, err = pcall(tick_apply)
    if _on then _p.finish("gestures.apply_lu") end
    if not ok then
        log.error(LOG_TAG .. " tick error: " .. tostring(err))
    end
end)

re.on_application_entry("PrepareRendering", function()
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("gestures.apply_pr") end
    pcall(tick_apply)
    if _on then _p.finish("gestures.apply_pr") end
end)

re.on_application_entry("UpdateJointExpression", function()
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("gestures.apply_uje") end
    pcall(tick_apply)
    if _on then _p.finish("gestures.apply_uje") end
end)

re.on_draw_ui(function()
    local ok, err = pcall(draw_ui)
    if not ok then
        imgui.text(LOG_TAG .. " UI error: " .. tostring(err))
    end
end)

if type(rawget(_G, "__re8_vr_overlay_bind")) ~= "table" then
    rawset(_G, "__re8_vr_overlay_bind", {})
end
rawget(_G, "__re8_vr_overlay_bind").gestures = {
    push = function(api)
        api.set_bool("gestures.enabled", CFG.enabled == true, false)
    end,
    pull = function(api)
        CFG.enabled = api.get_bool("gestures.enabled", CFG.enabled == true)
        save_cfg()
    end,
}

return {
    cfg = function() return CFG end,
    runtime = function() return runtime end,
}
