-- Gates left shoot rumble to two-hand hold, and scales shoot intensity (Low/Medium/High).
-- Automatic weapons use intermittent pulses instead of continuous rumble.
-- sol2 vrmod userdata ignores method assignment, so we proxy _G.vrmod.
-- Holster/reload/grab pulses (no shoot rumble context) pass through unscaled.

if reframework and reframework.get_game_name then
    local gn = nil
    pcall(function() gn = reframework:get_game_name() end)
    if gn and gn ~= "re8" then
        return {}
    end
end

local CFG_PATH = "re8_vr/re8_vr_haptics.json"

local INTENSITY = {
    low = 0.45,
    medium = 0.80,
    high = 1.20,
}

local FLAME_NAME_HINTS = {
}

local AUTO_PULSE_NAME_HINTS = {
}

local CFG = {
    enabled = true,
    gate_left_shoot = true,
    intensity = "medium",
    auto_pulse = true,
    -- One crisp tick per period; each hand may fire once per tick (L+R pair).
    auto_pulse_on_s = 0.018,
    auto_pulse_off_s = 0.070,
    auto_pulse_max_dur = 0.018,
}

local GRIP_AXIS_ON = 0.65
local TWO_HAND_ENTER_M = 0.32
local TWO_HAND_EXIT_M = 0.48

local M = {
    wrap_installed = false,
    vib_hook_installed = false,
    orig_trigger = nil,
    real_vrmod = nil,
    proxy = nil,
    wrap_sticky = false,
    left_joy = nil,
    right_joy = nil,
    grip_action = nil,
    shoot_rumble_ctx = false,
    shoot_rumble_frame = -1,
    two_handed = false,
    two_hand_reason = "init",
    two_hand_prox = { sticky = false, dist = 99.0 },
    left_grip = false,
    was_gripping = false,
    frame = 0,
    weapon_name = "",
    weapon_kind = "other", -- other | auto | flame
    weapon_cache_frame = -1,
    auto_pulse_phase_t = 0.0,
    auto_pulse_allow = true,
    auto_pulse_last_tick_t = 0.0,
    auto_pulse_tick_sides = nil,
    auto_pulse_prev_gap = -1.0,
}

-- Mag holster grab pulses.
local AMMO = {
    grab_haptic_dur = 0.06,
    grab_haptic_freq = 200.0,
    grab_haptic_amp = 0.7,
    grab_haptic_enabled = true,
    deny_haptic = nil,
    last_reason = "",
}

function AMMO._get_left_joystick()
    local fn = rawget(_G, "__re8_holster_get_left_joystick")
    if type(fn) == "function" then
        local ok, lj = pcall(fn)
        if ok then return lj end
    end
    return nil
end

function AMMO._pulse(lj, dur, freq, amp)
    if not lj or not vrmod then return end
    pcall(function()
        if vrmod.trigger_haptic_vibration then
            vrmod:trigger_haptic_vibration(0.0, dur or 0.05, freq or 200.0, amp or 0.5, lj)
        else
            vrmod:trigger_haptic(lj, dur or 0.05, freq or 200.0, amp or 0.5)
        end
    end)
end

function AMMO._pulse_deny_once(lj)
    AMMO._pulse(lj, 0.035, 240.0, 0.45)
end

function AMMO.tick_deny_haptic()
    local fh = AMMO.deny_haptic
    if type(fh) ~= "table" then return end
    if os.clock() < (tonumber(fh.due_t) or 0) then return end
    AMMO.deny_haptic = nil
    AMMO._pulse_deny_once(AMMO._get_left_joystick())
end

function AMMO.deny_grab_haptic()
    local lj = AMMO._get_left_joystick()
    AMMO._pulse_deny_once(lj)
    AMMO.deny_haptic = {
        due_t = os.clock() + 0.16,
    }
end

function AMMO.grab_success_haptic()
    if AMMO.grab_haptic_enabled == false then return end
    local want = rawget(_G, "__re8_holster_ammo_grab_haptic_enabled")
    if want == false then return end
    AMMO._pulse(
        AMMO._get_left_joystick(),
        AMMO.grab_haptic_dur, AMMO.grab_haptic_freq, AMMO.grab_haptic_amp)
end

function AMMO.reset(reason)
    AMMO.last_reason = reason or ""
    AMMO.deny_haptic = nil
end

function AMMO.status()
    return {
        last_reason = AMMO.last_reason,
        deny_pending = AMMO.deny_haptic ~= nil,
    }
end

rawset(_G, "__re8_ammo_holster_mod", AMMO)

local function save_cfg()
    pcall(function()
        json.dump_file(CFG_PATH, {
            enabled = CFG.enabled == true,
            gate_left_shoot = CFG.gate_left_shoot == true,
            intensity = CFG.intensity,
            auto_pulse = CFG.auto_pulse == true,
            auto_pulse_on_s = CFG.auto_pulse_on_s,
            auto_pulse_off_s = CFG.auto_pulse_off_s,
            auto_pulse_max_dur = CFG.auto_pulse_max_dur,
        })
    end)
end

local function load_cfg()
    local data = nil
    pcall(function() data = json.load_file(CFG_PATH) end)
    if type(data) ~= "table" then return end
    if data.enabled ~= nil then CFG.enabled = data.enabled == true end
    if data.gate_left_shoot ~= nil then CFG.gate_left_shoot = data.gate_left_shoot == true end
    if type(data.intensity) == "string" and INTENSITY[data.intensity] ~= nil then
        CFG.intensity = data.intensity
    end
    if data.auto_pulse ~= nil then CFG.auto_pulse = data.auto_pulse == true end
    if type(data.auto_pulse_on_s) == "number" then CFG.auto_pulse_on_s = data.auto_pulse_on_s end
    if type(data.auto_pulse_off_s) == "number" then CFG.auto_pulse_off_s = data.auto_pulse_off_s end
    if type(data.auto_pulse_max_dur) == "number" then CFG.auto_pulse_max_dur = data.auto_pulse_max_dur end
    -- Migrate old duty-cycle timings that overlapped into continuous feel.
    if (tonumber(CFG.auto_pulse_max_dur) or 0) >= 0.035 then
        CFG.auto_pulse_max_dur = 0.018
    end
    if (tonumber(CFG.auto_pulse_off_s) or 0) < 0.050 then
        CFG.auto_pulse_off_s = 0.070
    end
    if (tonumber(CFG.auto_pulse_on_s) or 0) > 0.025 then
        CFG.auto_pulse_on_s = 0.018
    end
end

load_cfg()

local function get_re8vr()
    return rawget(_G, "re8vr")
end

local function name_has_any(name, hints)
    if type(name) ~= "string" or name == "" then return false end
    for i = 1, #hints do
        if name:find(hints[i], 1, true) then
            return true
        end
    end
    return false
end

local function managed_alive(obj)
    if obj == nil then return false end
    local ok, alive = pcall(function()
        if obj.get_address then return obj:get_address() ~= 0 end
        return true
    end)
    return ok and alive == true
end

local function read_system_string(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local s = nil
    pcall(function()
        if v.to_string then
            s = v:to_string()
        elseif v.call then
            s = v:call("ToString")
        end
    end)
    if type(s) == "string" then return s end
    return tostring(v)
end

local function get_equipped_weapon_go()
    local re8vr = get_re8vr()
    -- Only use live VR weapon pointer. Inventory/_PlayerObj getComponent
    -- throws InvalidOperationException on menu/teardown even when
    -- sdk.is_valid_obj reports true.
    if re8vr and managed_alive(re8vr.weapon) then
        local weapon = re8vr.weapon
        local go = nil
        pcall(function() go = weapon:get_field("<owner>k__BackingField") end)
        if not managed_alive(go) then
            pcall(function() go = weapon:call("get_owner") end)
        end
        if not managed_alive(go) then
            pcall(function() go = weapon:call("get_GameObject") end)
        end
        if managed_alive(go) then
            return go, weapon
        end
    end
    return nil, nil
end

local function classify_weapon_kind(name, weapon_obj)
    if name_has_any(name, FLAME_NAME_HINTS) then
        return "flame"
    end
    if name_has_any(name, AUTO_PULSE_NAME_HINTS) then
        return "auto"
    end
    if weapon_obj ~= nil then
        local is_auto = false
        pcall(function()
            is_auto = weapon_obj:call("enableFullAuto") == true
        end)
        if is_auto then return "auto" end
    end
    return "other"
end

local function refresh_weapon_kind()
    if M.weapon_cache_frame == M.frame then return end
    M.weapon_cache_frame = M.frame
    local go, weapon = get_equipped_weapon_go()
    local name = ""
    if go then
        pcall(function() name = read_system_string(go:call("get_Name")) or "" end)
        M.weapon_name = name
        M.weapon_kind = classify_weapon_kind(name, weapon)
    else
        M.weapon_name = ""
        M.weapon_kind = "other"
    end
end

local function now_s()
    local t = 0.0
    pcall(function() t = os.clock() end)
    return t
end

local function auto_pulse_allows(side)
    if CFG.auto_pulse ~= true then
        return true
    end
    refresh_weapon_kind()
    if M.weapon_kind ~= "auto" then
        return true
    end

    local on_s = tonumber(CFG.auto_pulse_on_s) or 0.018
    local off_s = tonumber(CFG.auto_pulse_off_s) or 0.070
    if on_s < 0.008 then on_s = 0.008 end
    if off_s < 0.020 then off_s = 0.020 end
    local period = on_s + off_s
    local t = now_s()
    local last = tonumber(M.auto_pulse_last_tick_t) or 0.0
    local sides = M.auto_pulse_tick_sides
    if type(sides) ~= "table" then
        sides = {}
        M.auto_pulse_tick_sides = sides
    end

    -- New tick period: start fresh and allow this hand.
    if last <= 0 or (t - last) >= period then
        M.auto_pulse_prev_gap = (last > 0) and (t - last) or -1.0
        M.auto_pulse_last_tick_t = t
        M.auto_pulse_tick_sides = { [side] = true }
        M.auto_pulse_allow = true
        return true
    end

    -- Same tick: allow the other hand once (L+R pair).
    if sides[side] == true then
        M.auto_pulse_allow = false
        return false
    end
    if sides.left == true or sides.right == true then
        sides[side] = true
        M.auto_pulse_allow = true
        return true
    end

    M.auto_pulse_allow = false
    return false
end

local function intensity_scale()
    local s = INTENSITY[CFG.intensity]
    if type(s) ~= "number" then return INTENSITY.medium end
    return s
end

local function set_intensity(level)
    if INTENSITY[level] == nil then return end
    CFG.intensity = level
    save_cfg()
end

local function get_real_vrmod()
    if M.real_vrmod ~= nil then
        return M.real_vrmod
    end
    local cur = rawget(_G, "vrmod")
    if cur ~= nil and cur ~= M.proxy and type(cur) == "userdata" then
        M.real_vrmod = cur
        return cur
    end
    return nil
end

local function get_vrmod()
    return get_real_vrmod() or rawget(_G, "vrmod")
end

local function refresh_joysticks()
    local vrmod = get_vrmod()
    if not vrmod then return end
    pcall(function() M.left_joy = vrmod:get_left_joystick() end)
    pcall(function() M.right_joy = vrmod:get_right_joystick() end)
end

local function ensure_grip_action()
    if M.grip_action then return M.grip_action end
    local vrmod = get_vrmod()
    if not vrmod then return nil end
    pcall(function() M.grip_action = vrmod:get_action_grip() end)
    return M.grip_action
end

local function read_grip_axis(joystick)
    local vrmod = get_vrmod()
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

local function digital_grip(joystick)
    local vrmod = get_vrmod()
    local action = ensure_grip_action()
    if not vrmod or not action or not joystick then return false end
    local ok, active = pcall(function()
        return vrmod:is_action_active(action, joystick)
    end)
    return ok and active == true
end

local function read_left_grip()
    local re8vr = get_re8vr()
    refresh_joysticks()
    local lj = M.left_joy
    local rj = M.right_joy
    local la = read_grip_axis(lj)
    local ra = read_grip_axis(rj)

    if la >= GRIP_AXIS_ON then return true end
    if ra >= GRIP_AXIS_ON then return false end
    if digital_grip(lj) then return true end

    local holster = false
    local fn = rawget(_G, "__re8_holster_get_left_grip")
    if type(fn) == "function" then
        local ok, v = pcall(fn)
        holster = ok and v == true
    end
    local re8g = re8vr and re8vr.is_holding_left_grip == true
    if (holster or re8g) and not digital_grip(rj) then
        return true
    end

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

local function vec3_len_delta(a, b)
    if not a or not b then return 99.0 end
    if type(a.x) ~= "number" or type(b.x) ~= "number" then return 99.0 end
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function hands_world_distance()
    local re8vr = get_re8vr()
    local vrmod = get_vrmod()
    if re8vr then
        local d = vec3_len_delta(re8vr.last_left_hand_position, re8vr.last_right_hand_position)
        if d < 90.0 then return d end
    end
    if not vrmod then return 99.0 end
    local lp, rp = nil, nil
    pcall(function()
        refresh_joysticks()
        if M.left_joy then lp = vrmod:get_position(M.left_joy) end
        if M.right_joy then rp = vrmod:get_position(M.right_joy) end
    end)
    return vec3_len_delta(lp, rp)
end

local function is_two_handed_support(grip_active)
    if rawget(_G, "__vr_in_holster_zone") == true then
        M.two_hand_prox.sticky = false
        M.two_hand_reason = "holster_zone"
        return false
    end
    if rawget(_G, "__vr_in_head_flashlight_zone") == true then
        M.two_hand_prox.sticky = false
        M.two_hand_reason = "flashlight_zone"
        return false
    end

    local re8vr = get_re8vr()
    if not re8vr then
        M.two_hand_prox.sticky = false
        M.two_hand_reason = "no_re8vr"
        return false
    end

    if re8vr.was_gripping_weapon == true then
        M.two_hand_prox.sticky = true
        M.two_hand_prox.dist = hands_world_distance()
        M.two_hand_reason = "was_gripping_weapon"
        return true
    end

    if grip_active ~= true then
        M.two_hand_prox.sticky = false
        M.two_hand_prox.dist = 99.0
        M.two_hand_reason = "no_left_grip"
        return false
    end

    local dist = hands_world_distance()
    M.two_hand_prox.dist = dist

    if dist <= TWO_HAND_ENTER_M then
        M.two_hand_prox.sticky = true
        M.two_hand_reason = "prox_enter"
        return true
    end
    if M.two_hand_prox.sticky and dist <= TWO_HAND_EXIT_M then
        M.two_hand_reason = "prox_sticky"
        return true
    end
    if M.two_hand_prox.sticky and dist > TWO_HAND_EXIT_M then
        M.two_hand_prox.sticky = false
    end
    M.two_hand_reason = "hands_apart"
    return false
end

local function update_two_hand_state()
    local re8vr = get_re8vr()
    M.was_gripping = re8vr and re8vr.was_gripping_weapon == true
    M.left_grip = read_left_grip()
    M.two_handed = is_two_handed_support(M.left_grip)
end

local function classify_source(source)
    refresh_joysticks()
    if M.left_joy ~= nil and source == M.left_joy then return "left" end
    if M.right_joy ~= nil and source == M.right_joy then return "right" end
    if source == 0 or source == "0" then return "left" end
    if source == 1 or source == "1" then return "right" end
    return "other"
end

local function haptic_trigger(self, seconds_from_now, duration, frequency, amplitude, source)
    local orig = M.orig_trigger
    local vm = get_real_vrmod()
    if type(orig) ~= "function" or vm == nil then
        return
    end

    if CFG.enabled ~= true or rawget(_G, "__vr_reloaded_master_enabled") == false then
        return orig(vm, seconds_from_now, duration, frequency, amplitude, source)
    end

    local side = classify_source(source)
    local amp = tonumber(amplitude) or 0
    local dur = tonumber(duration) or 0
    local freq = tonumber(frequency) or 0
    -- Village pad→controller path uses frequency 1; that pre-hook often runs before ours sets ctx.
    local pad_rumble = freq > 0 and freq <= 1.5
    local in_zone = rawget(_G, "__vr_in_holster_zone") == true
        or rawget(_G, "__vr_in_head_flashlight_zone") == true
    local in_rumble = M.shoot_rumble_ctx == true
        or (M.shoot_rumble_frame >= 0 and (M.frame - M.shoot_rumble_frame) <= 2)
    if pad_rumble and not in_zone then
        in_rumble = true
    end

    if side == "left" and CFG.gate_left_shoot == true and in_rumble and M.two_handed ~= true then
        return
    end

    if in_rumble then
        if not auto_pulse_allows(side) then
            return
        end
        amp = amp * intensity_scale()
        if amp < 0 then amp = 0 end
        if amp > 1.5 then amp = 1.5 end
        if M.weapon_kind == "auto" and CFG.auto_pulse == true then
            local max_dur = tonumber(CFG.auto_pulse_max_dur) or 0.018
            if max_dur < 0.010 then max_dur = 0.010 end
            if max_dur > 0.030 then max_dur = 0.030 end
            dur = max_dur
        end
    end

    return orig(vm, seconds_from_now, dur, frequency, amp, source)
end

local function install_wrap()
    local cur = rawget(_G, "vrmod")
    if cur == nil then return end

    if M.proxy ~= nil and cur == M.proxy then
        if M.real_vrmod ~= nil then
            rawset(_G, "__re8_real_vrmod", M.real_vrmod)
        end
        M.wrap_installed = true
        M.wrap_sticky = true
        return
    end

    if type(cur) == "userdata" then
        M.real_vrmod = cur
    elseif M.real_vrmod == nil then
        return
    end

    local real = M.real_vrmod
    if real == nil or type(real.trigger_haptic_vibration) ~= "function" then
        return
    end
    rawset(_G, "__re8_real_vrmod", real)

    M.orig_trigger = real.trigger_haptic_vibration

    local proxy = M.proxy
    if proxy == nil then
        proxy = {}
        M.proxy = proxy
    end

    setmetatable(proxy, {
        __index = function(_, key)
            if key == "trigger_haptic_vibration" then
                return haptic_trigger
            end
            local v = real[key]
            if type(v) == "function" then
                return function(_, ...)
                    return v(real, ...)
                end
            end
            return v
        end,
        __newindex = function(_, key, val)
            real[key] = val
        end,
    })

    rawset(_G, "vrmod", proxy)
    rawset(_G, "__re8_real_vrmod", real)
    M.wrap_sticky = (rawget(_G, "vrmod") == proxy)
    M.wrap_installed = true
end

local function uninstall_wrap()
    if M.wrap_installed ~= true then return end
    if M.real_vrmod ~= nil then
        rawset(_G, "vrmod", M.real_vrmod)
        rawset(_G, "__re8_real_vrmod", M.real_vrmod)
    end
    M.wrap_installed = false
    M.wrap_sticky = false
end

local function on_pre_order_vibration(args)
    if CFG.enabled ~= true then return end
    local vrmod = get_vrmod()
    if not vrmod then return end
    local using = false
    pcall(function() using = vrmod:is_using_controllers() end)
    if not using then return end

    update_two_hand_state()
    refresh_weapon_kind()

    if M.auto_pulse_phase_t <= 0 then
        M.auto_pulse_phase_t = now_s()
    end

    M.shoot_rumble_ctx = true
    M.shoot_rumble_frame = M.frame
    M.wrap_sticky = (M.proxy ~= nil and rawget(_G, "vrmod") == M.proxy)
end

local function on_post_order_vibration(retval)
    -- Keep shoot_rumble_ctx sticky; on_frame clears after a few frames.
    -- Clearing here races pad→VR haptic calls that run in other OrderVibration pre-hooks.
    return retval
end

local function install_vib_hook()
    if M.vib_hook_installed == true then return end
    local td = sdk.find_type_definition("app.HIDVibrationManager")
    if not td then return end
    local hooked = false
    local m1 = td:get_method("OrderVibration(app.VibrationTask)")
    if m1 ~= nil then
        sdk.hook(m1, on_pre_order_vibration, on_post_order_vibration)
        hooked = true
    end
    local m2 = td:get_method("OrderVibration(System.Single, System.Single, System.Single, System.Boolean, System.Int32, System.Boolean, System.Single, System.Single, via.GameObject, System.Single, System.Single)")
    if m2 ~= nil then
        sdk.hook(m2, on_pre_order_vibration, on_post_order_vibration)
        hooked = true
    end
    if hooked then
        M.vib_hook_installed = true
    end
end

re.on_frame(function()
    M.frame = M.frame + 1
    if CFG.enabled == true then
        install_wrap()
        install_vib_hook()
        if M.frame % 2 == 0 then
            update_two_hand_state()
            refresh_weapon_kind()
        end
    elseif M.wrap_installed then
        uninstall_wrap()
    end
    if M.shoot_rumble_frame >= 0 and (M.frame - M.shoot_rumble_frame) > 2 then
        M.shoot_rumble_ctx = false
        M.shoot_rumble_frame = -1
        M.auto_pulse_phase_t = 0.0
        M.auto_pulse_last_tick_t = 0.0
        M.auto_pulse_tick_sides = {}
    end
end)

local function intensity_button(label, level)
    local mark = (CFG.intensity == level) and ("* " .. label) or label
    if imgui.button(mark .. "##hap_int_" .. level) then
        set_intensity(level)
    end
end

if not rawget(_G, "__re8_vr_haptics_ref_ui") then
    rawset(_G, "__re8_vr_haptics_ref_ui", true)
    re.on_draw_ui(function()
        if not imgui.tree_node("Weapon Shooting Haptics##re8_vr_hap") then return end
        local ce, ve = imgui.checkbox("Enabled##re8_vr_hap_en", CFG.enabled == true)
        if ce then
            CFG.enabled = ve == true
            save_cfg()
            if CFG.enabled then
                install_wrap()
                install_vib_hook()
            else
                uninstall_wrap()
            end
        end
        imgui.tree_pop()
    end)
end

pcall(install_wrap)
pcall(install_vib_hook)

if type(rawget(_G, "__re8_vr_overlay_bind")) ~= "table" then
    rawset(_G, "__re8_vr_overlay_bind", {})
end
rawget(_G, "__re8_vr_overlay_bind").haptics = {
    push = function(api)
        api.set_bool("haptics.enabled", CFG.enabled == true, false)
    end,
    pull = function(api)
        CFG.enabled = api.get_bool("haptics.enabled", CFG.enabled == true)
        save_cfg()
    end,
}

return {
    cfg = function() return CFG end,
    state = function() return M end,
    ammo = AMMO,
}
