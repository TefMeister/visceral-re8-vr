if reframework:get_game_name() ~= "re8" then
    return {}
end

if not vrmod then
    return {}
end

local re8 = require("utility/RE8")

local CFG_PATH = "re8_vr/re8_vr_recoil.json"
local LOG_PREFIX = "[re8_vr_recoil]"

local function imgui_col(r, g, b, a)
    a = a or 255
    return ((a & 0xFF) << 24) | ((b & 0xFF) << 16) | ((g & 0xFF) << 8) | (r & 0xFF)
end

local UI_ACCENT = imgui_col(136, 204, 255)
local UI_MUTED = imgui_col(136, 136, 136)
local UI_ENABLE = imgui_col(0, 255, 0)
local UI_DISABLE = imgui_col(255, 64, 64)

local PI_HALF = math.pi * 0.5
local SUPPORT_HAND_DISTANCE = 0.35

-- Per-weapon default intensity by class (1.0-4.0). Non-firearms get no recoil (intensity 0).
local WEAPON_TYPE_INTENSITY = {
    handgun = 1.22,
    revolver = 1.38,
    smg = 1.75,
    rifle = 1.48,
    shotgun = 2.55,
    magnum = 2.90,
    launcher = 2.45,
    flamethrower = 1.52,
    electric = 1.68,
    rpg = 3.90,
    minigun = 3.20,
}

local WEAPON_NO_RECOIL_IDS = {
    ["ri3022_Inventory"] = true,
    ["ri3044_Inventory"] = true,
}

local WEAPON_CATALOG = {
    ["ri3008_Inventory"] = { name = "M1851 Wolfsbane", type = "magnum" },
    ["ri3021_Inventory"] = { name = "W870 TAC", type = "shotgun" },
    ["ri3023_Inventory"] = { name = "GM 79", type = "launcher" },
    ["ri3036_Inventory"] = { name = "M1897", type = "shotgun" },
    ["ri3040_Inventory"] = { name = "M1911", type = "handgun" },
    ["ri3042_Inventory"] = { name = "F2 Rifle", type = "rifle" },
    ["ri3046_Inventory"] = { name = "LEMI", type = "handgun" },
    ["ri3047_Inventory"] = { name = "V61 Custom", type = "handgun" },
    ["ri3048_Inventory"] = { name = "SYG-12", type = "shotgun" },
    ["ri3049_Inventory"] = { name = "WCX", type = "rifle" },
    ["ri3050_Inventory"] = { name = "S.T.A.K.E", type = "magnum" },
    ["ri3115_Inventory"] = { name = "Rocket Pistol", type = "handgun" },
    ["ri3116_Inventory"] = { name = "Handcannon PZ", type = "magnum" },
    ["ri3122_Inventory"] = { name = "Samurai Edge - AW Model-01", type = "handgun" },
    ["ri3124_Inventory"] = { name = "USM-AI", type = "handgun" },
    ["ri3125_Inventory"] = { name = "Dragoon", type = "rifle" },
    ["ri3135_Inventory"] = { name = "LEMI - Shadows of Rose", type = "handgun" },
    ["ri3147_Inventory"] = { name = "M1897 - Shadows of Rose", type = "shotgun" },
    ["ri3081_Inventory"] = { name = "LEMI - Mercenaries", type = "handgun" },
    ["ri3082_Inventory"] = { name = "M1911 - Mercenaries", type = "handgun" },
    ["ri3083_Inventory"] = { name = "V61 Custom - Mercenaries", type = "handgun" },
    ["ri3084_Inventory"] = { name = "M1897 - Mercenaries", type = "shotgun" },
    ["ri3085_Inventory"] = { name = "W870 TAC - Mercenaries", type = "shotgun" },
    ["ri3086_Inventory"] = { name = "SYG-12 - Mercenaries", type = "shotgun" },
    ["ri3087_Inventory"] = { name = "F2 Rifle - Mercenaries", type = "rifle" },
    ["ri3129_Inventory"] = { name = "Dragoon - Mercenaries", type = "rifle" },
    ["ri3130_Inventory"] = { name = "USM-AI - Mercenaries", type = "handgun" },
}

local WEAPON_AUTO_RECOIL_IDS = {
    ["ri3049_Inventory"] = true,
    ["ri3125_Inventory"] = true,
    ["ri3129_Inventory"] = true,
}

local function canonicalize_weapon_id(weapon_id)
    if type(weapon_id) ~= "string" or weapon_id == "" then
        return ""
    end
    if WEAPON_CATALOG[weapon_id] ~= nil
        or WEAPON_NO_RECOIL_IDS[weapon_id]
        or WEAPON_AUTO_RECOIL_IDS[weapon_id] then
        return weapon_id
    end
    local with_inventory = weapon_id .. "_Inventory"
    if WEAPON_CATALOG[with_inventory] ~= nil
        or WEAPON_NO_RECOIL_IDS[with_inventory]
        or WEAPON_AUTO_RECOIL_IDS[with_inventory] then
        return with_inventory
    end
    return weapon_id
end

-- Per-type one/two-hand modifiers (stack on global one_hand_* / two_hand_scale / auto_scale).
-- kick = impulse mult, spring = stiffness mult, auto = auto_scale mult, sustain = damping mult.
local WEAPON_GRIP_PROFILE = {
    handgun = {
        weight = "light",
        one = { kick = 1.08, spring = 1.10, auto = 1.00, sustain = 1.00 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    revolver = {
        weight = "light",
        one = { kick = 1.14, spring = 1.15, auto = 1.00, sustain = 1.00 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    smg = {
        weight = "light",
        one = { kick = 1.10, spring = 1.12, auto = 1.55, sustain = 1.18 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    rifle = {
        weight = "medium",
        one = { kick = 1.18, spring = 1.20, auto = 1.25, sustain = 1.10 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    shotgun = {
        weight = "heavy",
        one = { kick = 1.22, spring = 1.48, auto = 1.00, sustain = 1.05 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    magnum = {
        weight = "heavy",
        one = { kick = 1.26, spring = 1.40, auto = 1.00, sustain = 1.00 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    launcher = {
        weight = "heavy",
        one = { kick = 1.20, spring = 1.35, auto = 1.00, sustain = 1.00 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    flamethrower = {
        weight = "medium",
        one = { kick = 1.12, spring = 1.14, auto = 1.35, sustain = 1.15 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    electric = {
        weight = "medium",
        one = { kick = 1.14, spring = 1.16, auto = 1.20, sustain = 1.08 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    rpg = {
        weight = "heavy",
        one = { kick = 1.30, spring = 1.38, auto = 1.00, sustain = 1.00 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
    minigun = {
        weight = "heavy",
        one = { kick = 1.15, spring = 1.22, auto = 1.65, sustain = 1.25 },
        two = { kick = 1.00, spring = 1.00, auto = 1.00, sustain = 1.00 },
    },
}

local CFG = {
    enabled = true,
    use_native_recoil = false,
    suppress_native_recoil = false,
    suppress_camera_recoil = false,
    intensity = 2.0,
    attack_duration = 0.005,
    spring_stiffness = 50.0,
    spring_damping = 5.0,
    sustained_damping = 10.0,
    spring_settle_mult = 4.5,
    sustained_window = 0.125,
    substep_dt = 0.008,
    position_intensity = 0.006,
    position_up_ratio = 1.0,
    position_back_ratio = 0.0,
    rotation_intensity = 0.01,
    wrist_pitch_sign = -1.0,
    yaw_intensity = 0.171,
    wrist_yaw_sign = 1.0,
    apply_yaw_rotation = true,
    horizontal_spread = 0.0,
    vertical_spread = 0.0,
    randomness = 0.347,
    mult_exponent = 0.1,
    stack_cap = 2.0,
    auto_scale = 0.25,
    two_hand_scale = 0.55,
    one_hand_light = 1.18,
    one_hand_heavy = 1.90,
    weapons = {},
}

local m_recoil = {
    spring_pos_y = 0.0,
    spring_pos_z = 0.0,
    spring_vel_y = 0.0,
    spring_vel_z = 0.0,
    spring_pitch = 0.0,
    spring_vel_pitch = 0.0,
    spring_yaw = 0.0,
    spring_vel_yaw = 0.0,
}

local m_attack = {
    active = false,
    t = 0.0,
    pos_y = 0.0,
    pos_z = 0.0,
    pitch = 0.0,
    yaw = 0.0,
}

local m_pending_recoil_shots = 0
local m_recoil_last_shot_t = 0.0
local m_recoil_last_t = 0.0
local m_recoil_active = false

local m_recoil_grip = {
    two_hand = false,
    wtype = "handgun",
    weight = "light",
    global_kick = 1.0,
    kick_mult = 1.0,
    spring_mult = 1.0,
    auto_mult = 1.0,
    sustain_mult = 1.0,
}

local m_recoil_last_weapon = nil
local m_recoil_last_ammo_count = -1

local fire_hooks_installed = false
local camera_recoil_hooks_installed = false
local ik_hook_installed = false
local ik_hook_warned = false
local settings_bootstrapped = false
local fire_had_loaded_ammo = false

local grip_action = nil

local l_arm_wrist_hash = nil
local r_arm_wrist_hash = nil

local frame_apply = {
    weapon_has_ammo = false,
    two_handed = false,
    has_recoil = false,
}

local frame_ik = {
    grip_offset_frame = -1,
    grip_pos_rel = nil,
    grip_rot_rel = nil,
    lh_pre_matrix = nil,
    lh_ik_hand = nil,
    rh_ik_pre_matrix = nil,
}

local motion_get_joint_index = nil
local motion_get_world_position = nil
local motion_get_world_rotation = nil

local sim_frame = 0
local last_physics_frame = -1
local ik_physics_sync_frame = -1

local RECOIL_FADEOUT_DURATION = 0.045

local frame_ik_recoil = {
    frame = -1,
    pitch = 0.0,
    yaw = 0.0,
    pos_y = 0.0,
    pos_z = 0.0,
}

local m_recoil_fadeout = {
    active = false,
    t = 0.0,
    duration = RECOIL_FADEOUT_DURATION,
    pitch = 0.0,
    yaw = 0.0,
    pos_y = 0.0,
    pos_z = 0.0,
}

local ik_recoil_sync_frame = -1
local via_motion_type = sdk.typeof("via.motion.Motion")

local application = sdk.get_native_singleton("via.Application")
local application_type = sdk.find_type_definition("via.Application")
local get_uptime_second_function = application_type and application_type:get_method("get_UpTimeSecond") or nil

local via_murmur_hash_type = sdk.find_type_definition("via.murmur_hash")
local via_murmur_hash_calc32 = via_murmur_hash_type and via_murmur_hash_type:get_method("calc32") or nil

local weapon_gun_types = {
    sdk.typeof("app.WeaponGunCore"),
}

local weapon_gun_cache = { weapon_addr = nil, wid = "", gun = nil, miss = false }

local ik_recoil_pass_state = { frame = -1, idle_after_first = false }

local function get_weapon_object_addr(weapon)
    if weapon == nil then return nil end
    local ok, addr = pcall(function() return weapon:get_address() end)
    if ok and addr ~= nil then return addr end
    return weapon
end

local function uptime_now()
    if application and get_uptime_second_function then
        local ok, t = pcall(function() return get_uptime_second_function:call(application) end)
        if ok and type(t) == "number" then
            return t
        end
    end
    return os.clock()
end

local function save_cfg()
    pcall(function() json.dump_file(CFG_PATH, CFG) end)
end

local function clamp_weapon_intensity(v)
    if type(v) ~= "number" then return 1.0 end
    if v < 1.0 then return 1.0 end
    if v > 4.0 then return 4.0 end
    return v
end

local function weapon_intensity_from_entry(entry)
    if type(entry) == "number" then
        return clamp_weapon_intensity(entry)
    end
    if type(entry) == "table" and entry.intensity ~= nil then
        local v = tonumber(entry.intensity)
        if v ~= nil then
            return clamp_weapon_intensity(v)
        end
    end
    return nil
end

local function resolve_weapon_type(weapon_id, weapon)
    weapon_id = canonicalize_weapon_id(weapon_id)
    local catalog = WEAPON_CATALOG[weapon_id]
    if catalog ~= nil and type(catalog.type) == "string" then
        return catalog.type
    end
    if weapon ~= nil then
        local ok_short, is_short = pcall(function() return weapon:call("isShortWeapon") end)
        if ok_short and is_short == true then
            return "handgun"
        end
        local ok_long, is_long = pcall(function() return weapon:call("isLongWeapon") end)
        if ok_long and is_long == true then
            return "rifle"
        end
    end
    return nil
end

local function weapon_recoil_supported(weapon_id, weapon)
    weapon_id = canonicalize_weapon_id(weapon_id)
    if weapon_id == "" then
        return false
    end
    if WEAPON_NO_RECOIL_IDS[weapon_id] then
        return false
    end
    local wtype = resolve_weapon_type(weapon_id, weapon)
    return wtype ~= nil and WEAPON_TYPE_INTENSITY[wtype] ~= nil
end

local function default_weapon_entry(weapon_id)
    weapon_id = canonicalize_weapon_id(weapon_id)
    if not weapon_recoil_supported(weapon_id) then
        return nil
    end
    local catalog = WEAPON_CATALOG[weapon_id]
    local wtype = resolve_weapon_type(weapon_id)
    local entry = {
        intensity = WEAPON_TYPE_INTENSITY[wtype],
        type = wtype,
    }
    if catalog ~= nil and type(catalog.name) == "string" then
        entry.name = catalog.name
    end
    return entry
end

local function normalize_weapon_entry(weapon_id, entry)
    weapon_id = canonicalize_weapon_id(weapon_id)
    if not weapon_recoil_supported(weapon_id) then
        return nil
    end
    if type(entry) ~= "table" then
        return default_weapon_entry(weapon_id)
    end
    if entry.type == "utility" then
        return nil
    end
    local intensity = weapon_intensity_from_entry(entry)
    if intensity == nil then
        return default_weapon_entry(weapon_id)
    end
    local out = {
        intensity = intensity,
        type = type(entry.type) == "string" and entry.type or resolve_weapon_type(weapon_id),
    }
    if type(entry.name) == "string" and entry.name ~= "" then
        out.name = entry.name
    elseif WEAPON_CATALOG[weapon_id] ~= nil and WEAPON_CATALOG[weapon_id].name ~= nil then
        out.name = WEAPON_CATALOG[weapon_id].name
    end
    return out
end

local function import_weapons_into_cfg(weapons_tbl, overwrite)
    if type(weapons_tbl) ~= "table" then
        return false
    end
    local changed = false
    for weapon_id, entry in pairs(weapons_tbl) do
        local canonical_id = canonicalize_weapon_id(weapon_id)
        local normalized = normalize_weapon_entry(canonical_id, entry)
        if normalized ~= nil and (overwrite or CFG.weapons[canonical_id] == nil) then
            CFG.weapons[canonical_id] = normalized
            changed = true
        end
    end
    return changed
end

local function prune_non_recoil_weapons_from_cfg()
    local changed = false
    for weapon_id, _ in pairs(CFG.weapons) do
        if not weapon_recoil_supported(weapon_id) then
            CFG.weapons[weapon_id] = nil
            changed = true
        end
    end
    return changed
end

local function load_cfg_from_disk()
    local data = json.load_file(CFG_PATH)
    if type(data) ~= "table" then
        return
    end
    for k, v in pairs(data) do
        if k == "weapons" then
            if type(v) == "table" then
                CFG.weapons = {}
                import_weapons_into_cfg(v, true)
            end
        elseif CFG[k] ~= nil and type(v) == type(CFG[k]) then
            CFG[k] = v
        end
    end
end

local function ensure_cfg_weapon_defaults()
    local changed = prune_non_recoil_weapons_from_cfg()
    for weapon_id, _ in pairs(WEAPON_CATALOG) do
        if CFG.weapons[weapon_id] == nil then
            local entry = default_weapon_entry(weapon_id)
            if entry ~= nil then
                CFG.weapons[weapon_id] = entry
                changed = true
            end
        end
    end
    return changed
end

local function bootstrap_settings()
    if settings_bootstrapped then
        return
    end
    if ensure_cfg_weapon_defaults() then
        save_cfg()
    end
    settings_bootstrapped = true
end

pcall(load_cfg_from_disk)

local function lua_recoil_active()
    if rawget(_G, "__vr_reloaded_master_enabled") == false then
        return false
    end
    if not CFG.enabled or CFG.use_native_recoil then
        return false
    end
    return true
end

local function vr_active()
    if not lua_recoil_active() then
        return false
    end
    if re8vr ~= nil and re8vr.can_use_hands == false then
        return false
    end
    local ok_hmd, hmd = pcall(function() return vrmod:is_hmd_active() end)
    local ok_ctrl, ctrl = pcall(function() return vrmod:is_using_controllers() end)
    return ok_hmd and hmd and ok_ctrl and ctrl
end

local function get_localplayer()
    return re8.get_localplayer()
end

local function player_is_reloading()
    if re8vr ~= nil and re8vr.is_reloading == true then
        return true
    end
    return false
end

local function player_is_aiming()
    if re8vr == nil or re8vr.order == nil then
        return false
    end
    local player_gun = nil
    pcall(function() player_gun = re8vr.order:call("get_playerGun") end)
    if player_gun ~= nil then
        for _, method_name in ipairs({ "get_isAimIdle", "get_isAimAttack", "get_isAimStart", "get_isAttack" }) do
            local ok, aiming = pcall(function() return player_gun:call(method_name) end)
            if ok and aiming == true then
                return true
            end
        end
    end
    local player_camera = nil
    pcall(function() player_camera = re8vr.order:call("get_playerCamera") end)
    if player_camera ~= nil then
        local ok, aiming = pcall(function() return player_camera:call("get_isGunAim") end)
        if ok and aiming == true then
            return true
        end
    end
    return false
end

local function is_left_grip_active()
    if not grip_action then
        pcall(function() grip_action = vrmod:get_action_grip() end)
    end
    if not grip_action then return false end
    local left_joy = nil
    pcall(function() left_joy = vrmod:get_left_joystick() end)
    if not left_joy then return false end
    local ok, active = pcall(function()
        return vrmod:is_action_active(grip_action, left_joy)
    end)
    return ok and active == true
end

-- Left grip held counts as two-handed support.
local function is_two_hand_recoil_active()
    if not is_left_grip_active() then
        return false
    end
    if rawget(_G, "__vr_in_holster_zone") == true then
        return false
    end
    if rawget(_G, "__vr_in_head_flashlight_zone") == true then
        return false
    end
    return true
end

local function get_game_frame_id()
    if re.get_frame_count then
        local ok, n = pcall(function() return re.get_frame_count() end)
        if ok and type(n) == "number" then
            return n
        end
    end
    return sim_frame
end

local function get_hand_world_pos(which)
    local key = (which == "left") and "__vr_lh_world" or "__vr_rh_world"
    local p = rawget(_G, key)
    if p ~= nil and type(p.x) == "number" then
        return p
    end
    local controllers = nil
    pcall(function() controllers = vrmod:get_controllers() end)
    if not controllers then return nil end
    local idx = (which == "left") and 1 or 2
    local ctrl = controllers[idx]
    if not ctrl then return nil end
    local ok, pos = pcall(function() return vrmod:get_position(ctrl) end)
    return ok and pos or nil
end

local function hands_are_supporting_weapon()
    local lh = get_hand_world_pos("left")
    local rh = get_hand_world_pos("right")
    if lh == nil or rh == nil then return false end
    if type(lh.x) ~= "number" or type(rh.x) ~= "number" then return false end
    local dx = lh.x - rh.x
    local dy = lh.y - rh.y
    local dz = lh.z - rh.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= SUPPORT_HAND_DISTANCE
end

local function is_two_handed()
    if player_is_reloading() then
        return true
    end
    if rawget(_G, "__vr_in_holster_zone") == true then
        return false
    end
    if rawget(_G, "__vr_in_head_flashlight_zone") == true then
        return false
    end
    if not is_left_grip_active() then
        return false
    end
    if hands_are_supporting_weapon() then
        return true
    end
    if player_is_aiming() then
        return true
    end
    return false
end

local function is_support_hand_active()
    return is_two_hand_recoil_active()
end

local function is_weapon_grip_active()
    if is_support_hand_active() then
        return true
    end
    if re8vr ~= nil and re8vr.was_gripping_weapon == true then
        return true
    end
    return is_two_handed()
end

local function get_equipment_weapon(player)
    if player == nil then return nil end
    if re8vr == nil then return nil end
    return re8vr:get_weapon_object(player)
end

local AMMO_METHOD_NAMES = {
    "getBulletNum",
}

local function try_ammo_on_object(obj)
    if obj == nil then return -1 end
    for _, method_name in ipairs(AMMO_METHOD_NAMES) do
        local ok, v = pcall(function() return obj:call(method_name) end)
        if ok and type(v) == "number" then
            return math.floor(v)
        end
    end
    return -1
end

local function get_weapon_ammo_count(weapon)
    if weapon == nil then return -1 end
    local v = try_ammo_on_object(weapon)
    if v >= 0 then return v end

    local ok_ud, user_data = pcall(function() return weapon:call("get_UserData") end)
    if ok_ud and user_data then
        v = try_ammo_on_object(user_data)
        if v >= 0 then return v end
    end

    local ok_gun, gun = pcall(function() return weapon:call("get_Gun") end)
    if ok_gun and gun ~= nil and gun ~= weapon then
        v = try_ammo_on_object(gun)
        if v >= 0 then return v end
        local ok_gud, gun_ud = pcall(function() return gun:call("get_UserData") end)
        if ok_gud and gun_ud then
            v = try_ammo_on_object(gun_ud)
            if v >= 0 then return v end
        end
    end

    local ok_work, work = pcall(function() return weapon:call("get_work") end)
    if ok_work and work then
        v = try_ammo_on_object(work)
        if v >= 0 then return v end
    end

    local ok_w2, work2 = pcall(function() return weapon:get_field("<Work>k__BackingField") end)
    if ok_w2 and work2 then
        v = try_ammo_on_object(work2)
        if v >= 0 then return v end
    end

    return -1
end

local function get_weapon_recoil_id(weapon)
    if weapon == nil then return "" end

    local owner = nil
    pcall(function() owner = weapon:get_field("<owner>k__BackingField") end)
    if owner == nil then
        pcall(function() owner = weapon:call("get_owner") end)
    end
    if owner then
        local ok_name, name = pcall(function() return owner:call("get_Name") end)
        if ok_name and type(name) == "string" and name ~= "" then
            return canonicalize_weapon_id(name)
        end
    end

    local ok_go, go = pcall(function() return weapon:call("get_GameObject") end)
    if ok_go and go then
        local ok_name, name = pcall(function() return go:call("get_Name") end)
        if ok_name and type(name) == "string" and name ~= "" then
            return canonicalize_weapon_id(name)
        end
    end

    local ok_wn, weapon_name = pcall(function() return weapon:call("get_weaponName") end)
    if ok_wn and type(weapon_name) == "string" and weapon_name ~= "" then
        return canonicalize_weapon_id(weapon_name)
    end

    local tdef = weapon:get_type_definition()
    if tdef then
        local ok_fn, fn = pcall(function() return tdef:get_full_name() end)
        if ok_fn and type(fn) == "string" then
            return canonicalize_weapon_id(fn)
        end
    end
    return ""
end

local equip_recoil_cache = { frame = -1, supported = false, weapon = nil, wid = "" }

local function get_equipped_recoil_state()
    local fid = get_game_frame_id()
    if equip_recoil_cache.frame ~= fid then
        equip_recoil_cache.frame = fid
        local weapon = get_equipment_weapon(get_localplayer())
        equip_recoil_cache.weapon = weapon
        equip_recoil_cache.wid = get_weapon_recoil_id(weapon)
        equip_recoil_cache.supported = weapon_recoil_supported(equip_recoil_cache.wid, weapon)
    end
    return equip_recoil_cache.supported, equip_recoil_cache.weapon, equip_recoil_cache.wid
end

local function get_per_weapon_intensity(weapon)
    local id = get_weapon_recoil_id(weapon)
    if id == "" then return 1.0 end
    if not weapon_recoil_supported(id, weapon) then
        return 0.0
    end
    local entry = CFG.weapons[id]
    if entry == nil then
        return weapon_intensity_from_entry(default_weapon_entry(id)) or 1.0
    end
    local v = weapon_intensity_from_entry(entry)
    if v == nil then return 1.0 end
    return v
end

local function is_auto_weapon(weapon)
    local wid = get_weapon_recoil_id(weapon)
    if wid == "" then
        return false
    end
    return WEAPON_AUTO_RECOIL_IDS[wid] == true
end

local function set_per_weapon_intensity(weapon_id, intensity)
    weapon_id = canonicalize_weapon_id(weapon_id)
    if weapon_id == "" then return end
    if not weapon_recoil_supported(weapon_id) then return end
    local entry = CFG.weapons[weapon_id]
    if type(entry) ~= "table" then
        entry = default_weapon_entry(weapon_id)
    end
    if entry == nil then return end
    entry.intensity = clamp_weapon_intensity(intensity)
    CFG.weapons[weapon_id] = entry
end

local function weapon_display_name(weapon_id)
    weapon_id = canonicalize_weapon_id(weapon_id)
    if weapon_id == "" then
        return ""
    end
    local entry = CFG.weapons[weapon_id]
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
        return entry.name
    end
    local catalog = WEAPON_CATALOG[weapon_id]
    if catalog ~= nil and type(catalog.name) == "string" then
        return catalog.name
    end
    return weapon_id
end

local function object_is_weapon_gun_core(obj)
    if obj == nil then
        return false
    end
    local tdef = nil
    pcall(function() tdef = obj:get_type_definition() end)
    if tdef == nil then
        return false
    end
    local ok_name, full_name = pcall(function() return tdef:get_full_name() end)
    if ok_name and full_name == "app.WeaponGunCore" then
        return true
    end
    local ok_a, is_a = pcall(function() return tdef:is_a("app.WeaponGunCore") end)
    return ok_a and is_a == true
end

local function get_weapon_gun_from_weapon(weapon)
    if weapon == nil then
        return nil
    end
    local weapon_id = get_weapon_recoil_id(weapon)
    if weapon_id ~= "" and WEAPON_NO_RECOIL_IDS[weapon_id] then
        return nil
    end
    local weapon_addr = get_weapon_object_addr(weapon)
    if weapon_gun_cache.weapon_addr == weapon_addr
        and weapon_gun_cache.wid == weapon_id then
        if weapon_gun_cache.miss then
            return nil
        end
        return weapon_gun_cache.gun
    end
    if object_is_weapon_gun_core(weapon) then
        weapon_gun_cache.weapon_addr = weapon_addr
        weapon_gun_cache.wid = weapon_id
        weapon_gun_cache.gun = weapon
        weapon_gun_cache.miss = false
        return weapon
    end
    local weapon_go = nil
    pcall(function() weapon_go = weapon:call("get_GameObject") end)
    if weapon_go ~= nil then
        for _, gun_type in ipairs(weapon_gun_types) do
            if gun_type ~= nil then
                local ok, gun = pcall(function()
                    return weapon_go:call("getComponent(System.Type)", gun_type)
                end)
                if ok and gun ~= nil then
                    weapon_gun_cache.weapon_addr = weapon_addr
                    weapon_gun_cache.wid = weapon_id
                    weapon_gun_cache.gun = gun
                    weapon_gun_cache.miss = false
                    return gun
                end
            end
        end
    end
    if weapon_id ~= "" then
        weapon_gun_cache.weapon_addr = weapon_addr
        weapon_gun_cache.wid = weapon_id
        weapon_gun_cache.gun = nil
        weapon_gun_cache.miss = true
    end
    return nil
end

local function should_suppress_camera_recoil()
    return vr_active() and CFG.suppress_camera_recoil
end

local CAMERA_TYPE_NAMES = {
    "app.PlayerCamera",
}

local CAMERA_SUPPRESS_METHODS = {
    "updateCameraShakeValue",
}

local function on_pre_update_camera_shake(args)
    if should_suppress_camera_recoil() then
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end

local function try_hook_camera_suppress_method(type_name, method_name)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return false
    end
    local method = td:get_method(method_name)
    if not method then
        return false
    end
    sdk.hook(method, on_pre_update_camera_shake, function(retval) return retval end)
    log.info(string.format("%s Hooked %s.%s", LOG_PREFIX, type_name, method_name))
    return true
end

local function install_camera_recoil_hooks()
    if camera_recoil_hooks_installed then
        return
    end

    local hooked = 0
    for _, type_name in ipairs(CAMERA_TYPE_NAMES) do
        for _, method_name in ipairs(CAMERA_SUPPRESS_METHODS) do
            if try_hook_camera_suppress_method(type_name, method_name) then
                hooked = hooked + 1
            end
        end
    end

    camera_recoil_hooks_installed = hooked > 0
    if camera_recoil_hooks_installed then
        log.info(string.format("%s Camera recoil/shake hooks installed (%d)", LOG_PREFIX, hooked))
    else
        log.warn(string.format("%s Camera recoil/shake hooks not installed (types/methods missing)", LOG_PREFIX))
    end
end

local function cancel_recoil_state(weapon_for_log, reason)
    m_recoil.spring_pos_y = 0.0
    m_recoil.spring_pos_z = 0.0
    m_recoil.spring_vel_y = 0.0
    m_recoil.spring_vel_z = 0.0
    m_recoil.spring_pitch = 0.0
    m_recoil.spring_vel_pitch = 0.0
    m_recoil.spring_yaw = 0.0
    m_recoil.spring_vel_yaw = 0.0
    m_attack.active = false
    m_attack.t = 0.0
    m_attack.pos_y = 0.0
    m_attack.pos_z = 0.0
    m_attack.pitch = 0.0
    m_attack.yaw = 0.0
    m_recoil_active = false
    m_recoil_last_t = 0.0
    m_recoil_fadeout.active = false
    m_recoil_fadeout.t = 0.0
end

local function get_effective_recoil_offsets()
    if m_recoil_fadeout.active then
        local blend = 1.0 - math.min(1.0, m_recoil_fadeout.t / m_recoil_fadeout.duration)
        return m_recoil_fadeout.pitch * blend, m_recoil_fadeout.yaw * blend,
            m_recoil_fadeout.pos_y * blend, m_recoil_fadeout.pos_z * blend
    end
    if frame_ik_recoil.frame == get_game_frame_id() then
        return frame_ik_recoil.pitch, frame_ik_recoil.yaw, frame_ik_recoil.pos_y, frame_ik_recoil.pos_z
    end
    return m_recoil.spring_pitch, m_recoil.spring_yaw, m_recoil.spring_pos_y, m_recoil.spring_pos_z
end

local function capture_frame_ik_recoil()
    local pitch, yaw, pos_y, pos_z = get_effective_recoil_offsets()
    frame_ik_recoil.frame = get_game_frame_id()
    frame_ik_recoil.pitch = pitch
    frame_ik_recoil.yaw = yaw
    frame_ik_recoil.pos_y = pos_y
    frame_ik_recoil.pos_z = pos_z
end

local function begin_recoil_fadeout()
    if m_recoil_fadeout.active then
        return
    end
    m_recoil_fadeout.pitch = m_recoil.spring_pitch
    m_recoil_fadeout.yaw = m_recoil.spring_yaw
    m_recoil_fadeout.pos_y = m_recoil.spring_pos_y
    m_recoil_fadeout.pos_z = m_recoil.spring_pos_z
    local rot_mag = math.abs(m_recoil_fadeout.pitch) + math.abs(m_recoil_fadeout.yaw)
    local pos_mag = math.abs(m_recoil_fadeout.pos_y) + math.abs(m_recoil_fadeout.pos_z)
    if rot_mag < 1e-7 and pos_mag < 1e-7 then
        -- Spring already settled to zero; nothing to fade. End the recoil cycle cleanly
        -- so update_recoil does not loop on the spring block indefinitely.
        m_recoil_active = false
        return
    end
    m_recoil_fadeout.active = true
    m_recoil_fadeout.t = 0.0
    m_recoil_fadeout.duration = RECOIL_FADEOUT_DURATION
    m_recoil.spring_pos_y = 0.0
    m_recoil.spring_pos_z = 0.0
    m_recoil.spring_vel_y = 0.0
    m_recoil.spring_vel_z = 0.0
    m_recoil.spring_pitch = 0.0
    m_recoil.spring_vel_pitch = 0.0
    m_recoil.spring_yaw = 0.0
    m_recoil.spring_vel_yaw = 0.0
    m_attack.active = false
    m_recoil_active = true
end

local function angle_axis_quat(angle, axis)
    local half = angle * 0.5
    local s = math.sin(half)
    return Quaternion.new(math.cos(half), axis.x * s, axis.y * s, axis.z * s):normalized()
end

local function quat_from_vr_rotation(rot)
    if rot == nil then return nil end
    if type(rot) == "Quaternion" then
        return rot:normalized()
    end
    if type(rot.w) == "number" then
        return Quaternion.new(rot.w, rot.x, rot.y, rot.z):normalized()
    end
    local ok, q = pcall(function() return rot:to_quat() end)
    return ok and q and q:normalized() or nil
end

-- Wrist-local recoil: pitch about +X (muzzle climb), yaw about +Y (horizontal), optional slide in hand space.
local LOCAL_WRIST_RIGHT = Vector3f.new(1.0, 0.0, 0.0)
local LOCAL_WRIST_UP = Vector3f.new(0.0, 1.0, 0.0)

local function get_wrist_axis_sign(cfg_key)
    local s = tonumber(CFG[cfg_key]) or 1.0
    if s >= 0.0 then return 1.0 end
    return -1.0
end

local function get_wrist_recoil_transform(hand_rot, scale)
    if hand_rot == nil then
        return nil, nil, nil
    end
    scale = tonumber(scale) or 1.0
    if scale <= 0.0 then
        return Quaternion.identity(), Vector3f.new(0.0, 0.0, 0.0), Quaternion.identity()
    end

    hand_rot = quat_from_vr_rotation(hand_rot) or Quaternion.identity()

    local eff_pitch, eff_yaw, eff_pos_y, eff_pos_z = get_effective_recoil_offsets()
    local pitch = eff_pitch * scale * get_wrist_axis_sign("wrist_pitch_sign")
    local yaw = eff_yaw * scale * get_wrist_axis_sign("wrist_yaw_sign")
    local local_pitch = angle_axis_quat(pitch, LOCAL_WRIST_RIGHT)
    local local_yaw = angle_axis_quat(yaw, LOCAL_WRIST_UP)
    local local_recoil = (local_pitch * local_yaw):normalized()
    local recoil_rot = (hand_rot * local_recoil):normalized()
    local delta_rot = (recoil_rot * hand_rot:inverse()):normalized()

    local up_ratio = math.max(0.0, tonumber(CFG.position_up_ratio) or 0.0)
    local pos_y = eff_pos_y * scale * up_ratio
    local pos_z = eff_pos_z * scale
    local local_offset = Vector3f.new(0.0, pos_y, pos_z)
    local world_offset = recoil_rot * local_offset

    return recoil_rot, world_offset, delta_rot
end

local function is_block_left_hand_ik()
    return rawget(_G, "__vr_block_left_hand_ik") == true
end

-- Left hand follows weapon hand when gripping or reloading.
local function should_support_hand_follow_weapon()
    if is_block_left_hand_ik() then
        return false
    end
    if player_is_reloading() then
        return true
    end
    if not is_left_grip_active() then
        return false
    end
    return is_weapon_grip_active()
end

local function reset_frame_ik_state()
    frame_ik.grip_offset_frame = -1
    frame_ik.grip_pos_rel = nil
    frame_ik.grip_rot_rel = nil
    frame_ik.lh_pre_matrix = nil
    frame_ik.lh_ik_hand = nil
    frame_ik.rh_ik_pre_matrix = nil
end

local function ensure_wrist_hashes()
    if l_arm_wrist_hash ~= nil and r_arm_wrist_hash ~= nil then
        return
    end
    if not via_murmur_hash_calc32 then return end
    local ok_l, lh = pcall(function() return via_murmur_hash_calc32:call(nil, "l_arm_wrist", 0) end)
    local ok_r, rh = pcall(function() return via_murmur_hash_calc32:call(nil, "r_arm_wrist", 0) end)
    if ok_l then l_arm_wrist_hash = lh end
    if ok_r then r_arm_wrist_hash = rh end
end

local function ensure_motion_methods()
    if motion_get_joint_index ~= nil then
        return true
    end
    local motion_t = sdk.find_type_definition("via.motion.Motion")
    if motion_t == nil then
        return false
    end
    motion_get_joint_index = motion_t:get_method("getJointIndexByNameHash")
    motion_get_world_position = motion_t:get_method("getWorldPosition")
    motion_get_world_rotation = motion_t:get_method("getWorldRotation")
    return motion_get_joint_index ~= nil and motion_get_world_position ~= nil and motion_get_world_rotation ~= nil
end

local function get_player_motion()
    local player = get_localplayer()
    if player == nil then
        return nil
    end
    local transform = nil
    pcall(function()
        local go = player:call("get_GameObject")
        if go ~= nil then
            transform = go:call("get_Transform")
        end
    end)
    if transform == nil or via_motion_type == nil then
        return nil
    end
    local motion = nil
    pcall(function()
        motion = transform:call("getComponent(System.Type)", via_motion_type)
    end)
    return motion
end

local function vec4_to_vec3(v)
    if v == nil or type(v.x) ~= "number" then
        return nil
    end
    return Vector3f.new(v.x, v.y, v.z)
end

local function get_motion_wrist_pose(which)
    if not ensure_motion_methods() then
        return nil, nil
    end
    ensure_wrist_hashes()
    local hash = (which == "left") and l_arm_wrist_hash or r_arm_wrist_hash
    if hash == nil then
        return nil, nil
    end
    local motion = get_player_motion()
    if motion == nil then
        return nil, nil
    end

    local idx = nil
    pcall(function() idx = motion_get_joint_index:call(motion, hash) end)
    if idx == nil then
        return nil, nil
    end

    local pos_raw, rot_raw = nil, nil
    pcall(function() pos_raw = motion_get_world_position:call(motion, idx) end)
    pcall(function() rot_raw = motion_get_world_rotation:call(motion, idx) end)
    local pos = vec4_to_vec3(pos_raw)
    local rot = quat_from_vr_rotation(rot_raw)
    return pos, rot
end

-- Skeleton wrist-joint grip offset relative to weapon hand.
local function get_skeleton_grip_offset_relative_to_weapon()
    local frame_id = get_game_frame_id()
    if frame_ik.grip_offset_frame == frame_id and frame_ik.grip_pos_rel ~= nil and frame_ik.grip_rot_rel ~= nil then
        return frame_ik.grip_pos_rel, frame_ik.grip_rot_rel
    end

    local lh_pos, lh_rot = get_motion_wrist_pose("left")
    local rh_pos, rh_rot = get_motion_wrist_pose("right")
    if lh_pos == nil or lh_rot == nil or rh_pos == nil or rh_rot == nil then
        return nil, nil
    end

    local rh_inv = rh_rot:conjugate()
    local delta = Vector3f.new(lh_pos.x - rh_pos.x, lh_pos.y - rh_pos.y, lh_pos.z - rh_pos.z)
    local pos_rel = rh_inv * delta
    local rot_rel = (rh_inv * lh_rot):normalized()

    frame_ik.grip_pos_rel = pos_rel
    frame_ik.grip_rot_rel = rot_rel
    frame_ik.grip_offset_frame = frame_id
    return pos_rel, rot_rel
end

local function matrix_to_pos_rot(mat)
    if mat == nil then return nil, nil end
    local pos = Vector3f.new(mat[3].x, mat[3].y, mat[3].z)
    local ok, rot = pcall(function() return mat:to_quat():normalized() end)
    return pos, ok and rot or nil
end

local function build_matrix_from_pos_rot(pos, rot)
    if pos == nil or rot == nil then
        return nil
    end
    rot = quat_from_vr_rotation(rot) or Quaternion.identity()
    local m = rot:to_mat4()
    m[3] = Vector4f.new(pos.x, pos.y, pos.z, 1.0)
    return m
end

local function compute_hand_offset_relative_to_weapon(lh_mat, rh_mat)
    local lh_pos, lh_rot = matrix_to_pos_rot(lh_mat)
    local rh_pos, rh_rot = matrix_to_pos_rot(rh_mat)
    if lh_pos == nil or lh_rot == nil or rh_pos == nil or rh_rot == nil then
        return nil, nil
    end
    local rh_inv = rh_rot:conjugate()
    local delta = Vector3f.new(lh_pos.x - rh_pos.x, lh_pos.y - rh_pos.y, lh_pos.z - rh_pos.z)
    local pos_rel = rh_inv * delta
    local rot_rel = (rh_inv * lh_rot):normalized()
    return pos_rel, rot_rel
end

-- Invert lh = rh + rh*pos_rel and lh_rot = rh_rot*rot_rel to recover weapon-hand pre-recoil pose.
local function reconstruct_weapon_hand_matrix_from_support(lh_mat, pos_rel, rot_rel)
    local lh_pos, lh_rot = matrix_to_pos_rot(lh_mat)
    if lh_pos == nil or lh_rot == nil or pos_rel == nil or rot_rel == nil then
        return nil
    end
    local rh_rot = (lh_rot * rot_rel:conjugate()):normalized()
    local rh_pos = lh_pos - (rh_rot * pos_rel)
    return build_matrix_from_pos_rot(rh_pos, rh_rot)
end

local function build_support_hand_matrix_from_weapon(rh_post_mat, pos_rel, rot_rel)
    if rh_post_mat == nil or pos_rel == nil or rot_rel == nil then
        return nil
    end
    local rh_pos, rh_rot = matrix_to_pos_rot(rh_post_mat)
    if rh_pos == nil or rh_rot == nil then
        return nil
    end
    local lh_pos = rh_pos + (rh_rot * pos_rel)
    local lh_rot = (rh_rot * rot_rel):normalized()
    local new_m = lh_rot:to_mat4()
    new_m[3] = Vector4f.new(lh_pos.x, lh_pos.y, lh_pos.z, 1.0)
    return new_m
end

local function weapon_has_ammo_for_apply(weapon)
    if weapon == nil then
        return false
    end
    local ammo = get_weapon_ammo_count(weapon)
    if ammo < 0 then
        return true
    end
    return ammo > 0
end

local function refresh_frame_recoil_offsets(weapon_for_log)
    if m_recoil_fadeout.active then
        frame_apply.has_recoil = true
        return
    end
    -- Attack phase: springs are 0 while ramping, but recoil IS active.
    if m_attack.active then
        frame_apply.has_recoil = true
        return
    end
    local pos_mag = math.abs(m_recoil.spring_pos_y) + math.abs(m_recoil.spring_pos_z)
    local rot_mag = math.abs(m_recoil.spring_pitch) + math.abs(m_recoil.spring_yaw)
    if pos_mag < 1e-7 and rot_mag < 1e-7 then
        frame_apply.has_recoil = false
        return
    end
    frame_apply.has_recoil = true
    if not CFG.apply_yaw_rotation then
        m_recoil.spring_yaw = 0.0
        m_recoil.spring_vel_yaw = 0.0
    end
end

local function is_support_hand_active_for_recoil()
    return is_two_hand_recoil_active()
end

local function one_hand_global_kick_scale(weight)
    local light = tonumber(CFG.one_hand_light) or 1.18
    local heavy = tonumber(CFG.one_hand_heavy) or 1.9
    if weight == "heavy" then
        return heavy
    end
    if weight == "medium" then
        return light + (heavy - light) * 0.42
    end
    return light
end

local function get_weapon_grip_profile(wtype)
    if type(wtype) ~= "string" or wtype == "" then
        return WEAPON_GRIP_PROFILE.handgun
    end
    return WEAPON_GRIP_PROFILE[wtype] or WEAPON_GRIP_PROFILE.handgun
end

local function update_recoil_grip_state(weapon)
    local weapon_id = ""
    if weapon ~= nil then
        weapon_id = get_weapon_recoil_id(weapon)
    end
    local wtype = resolve_weapon_type(weapon_id, weapon) or "handgun"
    local profile = get_weapon_grip_profile(wtype)
    local two_hand = is_support_hand_active_for_recoil()
    local mods = two_hand and profile.two or profile.one
    m_recoil_grip.two_hand = two_hand
    m_recoil_grip.wtype = wtype
    m_recoil_grip.weight = profile.weight
    m_recoil_grip.kick_mult = mods.kick or 1.0
    m_recoil_grip.spring_mult = mods.spring or 1.0
    m_recoil_grip.auto_mult = mods.auto or 1.0
    m_recoil_grip.sustain_mult = mods.sustain or 1.0
    if two_hand then
        m_recoil_grip.global_kick = tonumber(CFG.two_hand_scale) or 0.55
    else
        m_recoil_grip.global_kick = one_hand_global_kick_scale(profile.weight)
    end
    return m_recoil_grip
end

local function apply_recoil_kickback(weapon_for_id)
    if not vr_active() then return end

    local weapon_base = get_per_weapon_intensity(weapon_for_id)
    if weapon_base <= 0.0 then return end

    local weapon_multiplier = weapon_base * CFG.intensity
    if weapon_multiplier <= 0.0 then return end

    local grip = update_recoil_grip_state(weapon_for_id)

    local random_factor = 1.0 + (math.random() - 0.5) * CFG.randomness
    local exp = math.max(0.1, math.min(1.0, CFG.mult_exponent))
    local total_mult = (weapon_multiplier ^ exp) * random_factor

    local grip_kick = (grip.global_kick or 1.0) * (grip.kick_mult or 1.0)
    if grip_kick > 0.0 then
        total_mult = total_mult * grip_kick
    end

    if is_auto_weapon(weapon_for_id) then
        local auto_mult = math.max(0.05, tonumber(CFG.auto_scale) or 0.25)
        auto_mult = auto_mult * (grip.auto_mult or 1.0)
        total_mult = total_mult * auto_mult
    end

    if total_mult <= 0.0 then return end

    local up_ratio = math.max(0.0, tonumber(CFG.position_up_ratio) or 0.0)
    local back_ratio = math.max(0.0, tonumber(CFG.position_back_ratio) or 0.0)
    local pos_peak = CFG.position_intensity * total_mult
    local new_pos_y = pos_peak * up_ratio
    local new_pos_z = -pos_peak * back_ratio

    local pitch_peak = CFG.rotation_intensity * total_mult
    if CFG.vertical_spread > 0.0 then
        pitch_peak = pitch_peak + (math.random() - 0.5) * CFG.vertical_spread * total_mult
    end
    local yaw_peak = 0.0
    if CFG.apply_yaw_rotation then
        yaw_peak = (tonumber(CFG.yaw_intensity) or 0.0) * total_mult
        if CFG.horizontal_spread > 0.0 then
            yaw_peak = yaw_peak + (math.random() - 0.5) * 2.0 * CFG.horizontal_spread * total_mult
        end
    end

    m_attack.pos_y = m_attack.pos_y + new_pos_y
    m_attack.pos_z = m_attack.pos_z + new_pos_z
    m_attack.pitch = m_attack.pitch + pitch_peak
    m_attack.yaw = m_attack.yaw + yaw_peak

    if CFG.stack_cap > 0.0 then
        local cap_pos = CFG.position_intensity * CFG.stack_cap
        local cap_rot = CFG.rotation_intensity * CFG.stack_cap
        local cap_yaw = math.max(tonumber(CFG.yaw_intensity) or 0.0, CFG.horizontal_spread) * CFG.stack_cap
        m_attack.pos_y = math.min(m_attack.pos_y, cap_pos * up_ratio)
        m_attack.pos_z = math.max(m_attack.pos_z, -cap_pos * back_ratio)
        m_attack.pitch = math.min(m_attack.pitch, cap_rot)
        if m_attack.yaw > cap_yaw then m_attack.yaw = cap_yaw end
        if m_attack.yaw < -cap_yaw then m_attack.yaw = -cap_yaw end
    end

    m_attack.t = 0.0
    m_attack.active = true
    m_recoil_active = true

    local now = uptime_now()
    if m_recoil_last_t == 0.0 then
        m_recoil_last_t = now
    end
    m_recoil_last_shot_t = now
end

local function update_recoil(dt)
    dt = math.min(dt, 0.05)

    local player = get_localplayer()
    local current_weapon = get_equipment_weapon(player)

    if m_recoil_fadeout.active and dt > 0.0 then
        m_recoil_fadeout.t = m_recoil_fadeout.t + dt
        if m_recoil_fadeout.t >= m_recoil_fadeout.duration then
            cancel_recoil_state(current_weapon, "fadeout_done")
        end
        return
    end

    if not m_recoil_active and not m_attack.active then
        return
    end

    local now = uptime_now()
    if m_recoil_last_t > 0.0 then
        dt = math.min(now - m_recoil_last_t, 0.05)
    end
    m_recoil_last_t = now

    local attack_duration = CFG.attack_duration
    if attack_duration < 0.001 then attack_duration = 0.001 end

    local grip = update_recoil_grip_state(current_weapon)
    local k = CFG.spring_stiffness * (grip.spring_mult or 1.0)
    local c_base = CFG.spring_damping * (grip.sustain_mult or 1.0)
    local c_sustained = CFG.sustained_damping * (grip.sustain_mult or 1.0)
    local sustained_window = CFG.sustained_window
    if sustained_window < 0.01 then sustained_window = 0.01 end

    if m_attack.active and dt > 0.0 then
        m_attack.t = m_attack.t + dt

        if m_attack.t >= attack_duration then
            local prev_pitch = m_recoil.spring_pitch
            local peak_pitch = m_attack.pitch
            m_recoil.spring_pos_y = m_attack.pos_y
            m_recoil.spring_pos_z = m_attack.pos_z
            m_recoil.spring_pitch = peak_pitch
            m_recoil.spring_yaw = m_attack.yaw
            m_recoil.spring_vel_y = 0.0
            m_recoil.spring_vel_z = 0.0
            m_recoil.spring_vel_pitch = 0.0
            m_recoil.spring_vel_yaw = 0.0
            m_attack.pos_y = 0.0
            m_attack.pos_z = 0.0
            m_attack.pitch = 0.0
            m_attack.yaw = 0.0
            m_attack.t = 0.0
            m_attack.active = false
        else
            local s = math.sin((m_attack.t / attack_duration) * PI_HALF)
            m_recoil.spring_pos_y = m_attack.pos_y * s
            m_recoil.spring_pos_z = m_attack.pos_z * s
            m_recoil.spring_pitch = m_attack.pitch * s
            m_recoil.spring_yaw = m_attack.yaw * s
            m_recoil.spring_vel_y = 0.0
            m_recoil.spring_vel_z = 0.0
            m_recoil.spring_vel_pitch = 0.0
            m_recoil.spring_vel_yaw = 0.0
        end
    end

    if not m_attack.active and dt > 0.0 then
        local c = c_base
        if m_recoil_last_shot_t > 0.0 then
            local since_last = now - m_recoil_last_shot_t
            if since_last < sustained_window then
                local t_blend = 1.0 - (since_last / sustained_window)
                c = c + (c_sustained - c) * t_blend
            end
        end

        local settle_mult = math.max(1.0, tonumber(CFG.spring_settle_mult) or 4.5)
        local steps = math.max(1, math.floor(dt / CFG.substep_dt))
        local sub = dt / steps

        local function spring_channel_damping(pos, vel, base_c, settle_start, snap_pos, snap_vel)
            local pos_abs = math.abs(pos)
            local c_eff = base_c
            if pos_abs < settle_start then
                local blend = 1.0 - (pos_abs / settle_start)
                c_eff = base_c * (1.0 + blend * (settle_mult - 1.0))
            end
            local accel = -k * pos - c_eff * vel
            vel = vel + accel * sub
            pos = pos + vel * sub
            if math.abs(pos) < snap_pos and math.abs(vel) < snap_vel then
                return 0.0, 0.0
            end
            return pos, vel
        end

        local pitch_before_settle = m_recoil.spring_pitch
        for _ = 1, steps do
            m_recoil.spring_pos_y, m_recoil.spring_vel_y = spring_channel_damping(
                m_recoil.spring_pos_y, m_recoil.spring_vel_y, c, 0.002, 0.00003, 0.0006)
            m_recoil.spring_pos_z, m_recoil.spring_vel_z = spring_channel_damping(
                m_recoil.spring_pos_z, m_recoil.spring_vel_z, c, 0.002, 0.00003, 0.0006)
            m_recoil.spring_pitch, m_recoil.spring_vel_pitch = spring_channel_damping(
                m_recoil.spring_pitch, m_recoil.spring_vel_pitch, c, 0.04, 0.007, 0.06)
            m_recoil.spring_yaw, m_recoil.spring_vel_yaw = spring_channel_damping(
                m_recoil.spring_yaw, m_recoil.spring_vel_yaw, c, 0.025, 0.005, 0.05)
        end

        local pos_mag = math.abs(m_recoil.spring_pos_y) + math.abs(m_recoil.spring_pos_z)
        local rot_mag = math.abs(m_recoil.spring_pitch) + math.abs(m_recoil.spring_yaw)
        local vel_mag = math.abs(m_recoil.spring_vel_y) + math.abs(m_recoil.spring_vel_z)
            + math.abs(m_recoil.spring_vel_pitch) + math.abs(m_recoil.spring_vel_yaw)

        if pos_mag < 0.00003 and rot_mag < 0.00012 and vel_mag < 0.0005 then
            begin_recoil_fadeout()
        end
    end
end

local function process_recoil_physics()
    local frame_id = get_game_frame_id()
    if frame_id == last_physics_frame then
        return
    end
    last_physics_frame = frame_id

    if not vr_active() then
        m_pending_recoil_shots = 0
        frame_apply.weapon_has_ammo = false
        frame_apply.two_handed = false
        frame_apply.has_recoil = false
        return
    end

    local player = get_localplayer()
    local current_weapon = get_equipment_weapon(player)
    local _, cached_weapon = get_equipped_recoil_state()
    if cached_weapon ~= nil then
        current_weapon = cached_weapon
    end
    if not weapon_recoil_supported(get_weapon_recoil_id(current_weapon), current_weapon) then
        m_pending_recoil_shots = 0
        frame_apply.weapon_has_ammo = false
        frame_apply.two_handed = false
        frame_apply.has_recoil = false
        return
    end
    update_recoil_grip_state(current_weapon)
    local two_handed = is_two_handed()

    local pending = m_pending_recoil_shots
    m_pending_recoil_shots = 0

    local apply_pending = pending > 0
    if apply_pending then
        local n = pending
        if n > 10 then n = 10 end
        for _ = 1, n do
            apply_recoil_kickback(current_weapon)
        end
    end

    if not apply_pending and current_weapon ~= nil then
        -- Recoil is driven entirely by the requestFire hook; ammo-delta detection is
        -- disabled because it fired phantom kickbacks during reload animations when
        -- the ammo field briefly showed a stale intermediate count (e.g. 2→0 on
        -- slide-rack), producing a spurious second recoil animation after the last shot.
        m_recoil_last_weapon = current_weapon
        m_recoil_last_ammo_count = get_weapon_ammo_count(current_weapon)
    else
        -- Pending shots consumed above; reset ammo tracking for next call.
        m_recoil_last_weapon = current_weapon
        m_recoil_last_ammo_count = -1
    end

    local dt = 0.0
    if m_recoil_last_t > 0.0 then
        dt = math.min(uptime_now() - m_recoil_last_t, 0.05)
    else
        dt = 1.0 / 60.0
    end
    update_recoil(dt)

    frame_apply.two_handed = two_handed
    frame_apply.weapon_has_ammo = weapon_has_ammo_for_apply(current_weapon)
    refresh_frame_recoil_offsets(current_weapon)
    capture_frame_ik_recoil()
end

local function resolve_hand_side_from_ik(ik_hand)
    if ik_hand == nil or re8vr == nil then
        return nil
    end
    if re8vr.right_hand_ik ~= nil and ik_hand == re8vr.right_hand_ik then
        return "right"
    end
    if re8vr.left_hand_ik ~= nil and ik_hand == re8vr.left_hand_ik then
        return "left"
    end
    local addr = nil
    pcall(function() addr = ik_hand:get_address() end)
    if addr == nil then
        return nil
    end
    if re8vr.right_hand_ik ~= nil then
        local ok_r, r_addr = pcall(function() return re8vr.right_hand_ik:get_address() end)
        if ok_r and r_addr == addr then
            return "right"
        end
    end
    if re8vr.left_hand_ik ~= nil then
        local ok_l, l_addr = pcall(function() return re8vr.left_hand_ik:get_address() end)
        if ok_l and l_addr == addr then
            return "left"
        end
    end
    return nil
end

local function is_player_hand_ik(ik_hand)
    return resolve_hand_side_from_ik(ik_hand) ~= nil
end

local function read_ik_target_matrix(ik_hand)
    if ik_hand == nil then
        return nil
    end
    local target = nil
    pcall(function() target = ik_hand:get_field("Target") end)
    if target == nil then
        return nil
    end
    local pos, rot = nil, nil
    pcall(function() pos = target:call("get_Position") end)
    pcall(function() rot = target:call("get_Rotation") end)
    return build_matrix_from_pos_rot(pos, rot)
end

local function write_ik_target_matrix(ik_hand, mat)
    if ik_hand == nil or mat == nil then
        return false
    end
    local target = nil
    pcall(function() target = ik_hand:get_field("Target") end)
    if target == nil then
        return false
    end
    local pos, rot = matrix_to_pos_rot(mat)
    if pos == nil or rot == nil then
        return false
    end
    pcall(function() target:call("set_Position", pos) end)
    pcall(function() target:call("set_Rotation", rot) end)
    return true
end

-- Pitch wrist in local +X so the weapon muzzle kicks up (weapon / one-hand only).
local function build_recoiled_hand_matrix(target_matrix)
    if target_matrix == nil then
        return nil
    end
    local hand_rot = target_matrix:to_quat():normalized()
    local recoil_rot, world_offset = get_wrist_recoil_transform(hand_rot, 1.0)
    if recoil_rot == nil or world_offset == nil then
        return nil
    end

    local pos_v = Vector3f.new(
        target_matrix[3].x + world_offset.x,
        target_matrix[3].y + world_offset.y,
        target_matrix[3].z + world_offset.z)

    local new_m = recoil_rot:to_mat4()
    new_m[3] = Vector4f.new(pos_v.x, pos_v.y, pos_v.z, 1.0)
    return new_m
end

local function patch_support_hand_follow_weapon(rh_post_matrix, pos_rel, rot_rel)
    if pos_rel == nil or rot_rel == nil then
        return nil
    end
    return build_support_hand_matrix_from_weapon(rh_post_matrix, pos_rel, rot_rel)
end

local function get_weapon_hand_pre_for_support(lh_pre_matrix)
    if lh_pre_matrix == nil then
        return nil, nil, nil, "none"
    end
    if frame_ik.rh_ik_pre_matrix ~= nil then
        local pos_rel, rot_rel = compute_hand_offset_relative_to_weapon(lh_pre_matrix, frame_ik.rh_ik_pre_matrix)
        if pos_rel ~= nil then
            return frame_ik.rh_ik_pre_matrix, pos_rel, rot_rel, "same_frame_rh_ik"
        end
    end
    local rh_pos, rh_rot = get_motion_wrist_pose("right")
    if rh_pos ~= nil and rh_rot ~= nil then
        local rh_ref = build_matrix_from_pos_rot(rh_pos, rh_rot)
        if rh_ref ~= nil then
            local pos_rel, rot_rel = compute_hand_offset_relative_to_weapon(lh_pre_matrix, rh_ref)
            if pos_rel ~= nil then
                return rh_ref, pos_rel, rot_rel, "motion_rh_live_offset"
            end
        end
    end
    local sk_pos, sk_rot = get_skeleton_grip_offset_relative_to_weapon()
    if sk_pos == nil then
        return nil, nil, nil, "none"
    end
    local rh_pre = reconstruct_weapon_hand_matrix_from_support(lh_pre_matrix, sk_pos, sk_rot)
    return rh_pre, sk_pos, sk_rot, "skeleton_reconstruct"
end

local function patch_support_hand_ik_target(lh_ik_hand, lh_pre_matrix)
    local rh_pre, pos_rel, rot_rel = get_weapon_hand_pre_for_support(lh_pre_matrix)
    if rh_pre == nil or pos_rel == nil or rot_rel == nil then
        return write_ik_target_matrix(lh_ik_hand, build_recoiled_hand_matrix(lh_pre_matrix))
    end

    local rh_post = build_recoiled_hand_matrix(rh_pre)
    if rh_post == nil then
        return false
    end

    local lh_post = patch_support_hand_follow_weapon(rh_post, pos_rel, rot_rel)
    return write_ik_target_matrix(lh_ik_hand, lh_post)
end

local function patch_ik_hand_target(ik_hand, wrist_side)
    local target_matrix = read_ik_target_matrix(ik_hand)
    if target_matrix == nil then
        return false
    end

    if wrist_side == "right" then
        frame_ik.rh_ik_pre_matrix = target_matrix
        local rh_post = build_recoiled_hand_matrix(target_matrix)
        if rh_post ~= nil and frame_ik.lh_pre_matrix ~= nil and frame_ik.lh_ik_hand ~= nil then
            local pos_rel, rot_rel = compute_hand_offset_relative_to_weapon(frame_ik.lh_pre_matrix, target_matrix)
            if pos_rel ~= nil then
                local lh_post = patch_support_hand_follow_weapon(rh_post, pos_rel, rot_rel)
                write_ik_target_matrix(frame_ik.lh_ik_hand, lh_post)
            end
        end
        return write_ik_target_matrix(ik_hand, rh_post)
    end

    if wrist_side == "left" and should_support_hand_follow_weapon() then
        frame_ik.lh_pre_matrix = target_matrix
        frame_ik.lh_ik_hand = ik_hand
        return patch_support_hand_ik_target(ik_hand, target_matrix)
    end

    return write_ik_target_matrix(ik_hand, build_recoiled_hand_matrix(target_matrix))
end

local function sync_recoil_for_ik()
    local frame_id = get_game_frame_id()
    if frame_id ~= ik_physics_sync_frame then
        ik_physics_sync_frame = frame_id
        -- Do NOT reset last_physics_frame here: UpdateMotion may have already run
        -- process_recoil_physics for this frame. Resetting would bypass the gate and
        -- call update_recoil a second time, over-advancing spring physics every frame.
        reset_frame_ik_state()
        process_recoil_physics()
    else
        local _, weapon = get_equipped_recoil_state()
        refresh_frame_recoil_offsets(weapon)
    end
end

-- Fire can run after the first IkHand.calc in a frame (common when aiming sideways).
-- Apply any pending kick before reading has_recoil so this IK pass can patch Target.
-- update_recoil runs here ONLY when a fresh kick was applied mid-frame, then the frame
-- cache is re-captured so all subsequent IK passes in this frame use the same offset.
local function flush_pending_recoil_before_ik()
    local pending = m_pending_recoil_shots
    if pending > 0 then
        m_pending_recoil_shots = 0
        local n = pending
        if n > 10 then n = 10 end
        local weapon = get_equipment_weapon(get_localplayer())
        for _ = 1, n do
            apply_recoil_kickback(weapon)
        end
        -- Reset ammo tracking so the delta-detection path in process_recoil_physics
        -- does not see a stale pre-shot count and fire a second phantom kickback.
        m_recoil_last_weapon = weapon
        m_recoil_last_ammo_count = -1
        -- Seed the frame IK cache with the attack peak so all remaining IK passes
        -- this frame see a stable non-zero offset without calling update_recoil
        -- (which would use dt≈0 because m_recoil_last_t was just set by process_recoil_physics).
        -- Spring physics take over properly from the next frame onwards.
        local fid = get_game_frame_id()
        frame_ik_recoil.frame = fid
        frame_ik_recoil.pitch = m_attack.pitch
        frame_ik_recoil.yaw = m_attack.yaw
        frame_ik_recoil.pos_y = m_attack.pos_y
        frame_ik_recoil.pos_z = m_attack.pos_z
        frame_apply.has_recoil = true
        return
    end

    local _, weapon = get_equipped_recoil_state()
    refresh_frame_recoil_offsets(weapon)
end

local function should_apply_recoil_to_ik_hand(side)
    if side == "right" then
        return true
    end
    if side == "left" then
        return frame_apply.two_handed or is_weapon_grip_active()
    end
    return true
end

local function on_pre_ik_hand_calc(args)
    if not vr_active() or not lua_recoil_active() then return end

    local ik_hand = sdk.to_managed_object(args[2])
    if ik_hand == nil or not is_player_hand_ik(ik_hand) then
        return
    end

    if not get_equipped_recoil_state() then
        rawset(_G, "__vr_recoil_ik_patching", false)
        return
    end

    local ik_frame = get_game_frame_id()
    if ik_frame == ik_recoil_pass_state.frame
        and ik_recoil_pass_state.idle_after_first
        and m_pending_recoil_shots == 0 then
        rawset(_G, "__vr_recoil_ik_patching", false)
        return
    end

    if ik_frame ~= ik_recoil_sync_frame then
        ik_recoil_sync_frame = ik_frame
        ik_recoil_pass_state.frame = ik_frame
        ik_recoil_pass_state.idle_after_first = false
        sync_recoil_for_ik()
        flush_pending_recoil_before_ik()
    end

    if not frame_apply.has_recoil then
        ik_recoil_pass_state.idle_after_first = true
        rawset(_G, "__vr_recoil_ik_patching", false)
        rawset(_G, "__vr_recoil_has_active", false)
        return
    end

    rawset(_G, "__vr_recoil_has_active", true)

    local side = resolve_hand_side_from_ik(ik_hand)
    if not should_apply_recoil_to_ik_hand(side) then
        return
    end

    rawset(_G, "__vr_recoil_ik_patching", true)
    patch_ik_hand_target(ik_hand, side)
end

local function on_post_ik_hand_calc(retval)
    return retval
end

local function install_ik_hook()
    if ik_hook_installed then return end
    ensure_wrist_hashes()

    local ik_types = { "app.AnimIK2Bone" }
    local hooked = 0
    for _, type_name in ipairs(ik_types) do
        local td = sdk.find_type_definition(type_name)
        if td then
            local method = td:get_method("calc")
            if method then
                sdk.hook(method, on_pre_ik_hand_calc, on_post_ik_hand_calc)
                hooked = hooked + 1
                log.info(string.format("%s Hooked %s.calc", LOG_PREFIX, type_name))
            end
        end
    end

    if hooked == 0 then
        if not ik_hook_warned then
            log.warn(string.format("%s Hand IK calc hook not found", LOG_PREFIX))
            ik_hook_warned = true
        end
        return
    end

    ik_hook_installed = true
    log.info(string.format("%s Hand IK calc hook installed", LOG_PREFIX))
end

local function weapon_gun_has_loaded_ammo(gun)
    if gun == nil then return nil end

    local ok_infinite, infinite = pcall(function()
        return gun:call("get_isLoadNumInfinity")
    end)
    if ok_infinite and infinite == true then
        return true
    end

    local ok_empty, empty = pcall(function()
        return gun:call("get_isMagazineEmpty")
    end)
    if ok_empty and type(empty) == "boolean" then
        return not empty
    end

    local ok_bullets, bullets = pcall(function()
        return gun:call("getBulletNum")
    end)
    if ok_bullets and type(bullets) == "number" then
        return bullets > 0
    end

    local ok_under, under_one = pcall(function()
        return gun:call("get_isLoadNumUnderOne")
    end)
    if ok_under and type(under_one) == "boolean" then
        return not under_one
    end

    return nil
end

local function get_chamber_bullet_count()
    local weapon = get_equipment_weapon(get_localplayer())
    local gun = get_weapon_gun_from_weapon(weapon)
    if gun == nil then return -1 end
    local ok, n = pcall(function() return gun:call("getBulletNum") end)
    if ok and type(n) == "number" then
        return math.floor(n)
    end
    return -1
end

local function should_cancel_recoil_after_fire()
    if rawget(_G, "__vr_block_fire_when_empty") == true then
        return true
    end
    if rawget(_G, "__vr_manual_reload_enabled") ~= true then
        return false
    end
    if rawget(_G, "__vr_mag_dropped") == true
        or rawget(_G, "__vr_ammo_dropped") == true then
        return true
    end
    return get_chamber_bullet_count() == 0
end

local function should_block_recoil_queue()
    if should_cancel_recoil_after_fire() then
        return true
    end
    return rawget(_G, "__vr_needs_pump") == true
        or rawget(_G, "__vr_needs_rack") == true
end

local function add_pending_recoil_shot()
    if not lua_recoil_active() then return end
    if should_block_recoil_queue() then
        return
    end
    if m_pending_recoil_shots < 20 then
        m_pending_recoil_shots = m_pending_recoil_shots + 1
    end
end

local function is_player_weapon_gun(gun)
    if gun == nil then
        return false
    end
    if re8vr ~= nil and re8vr.weapon ~= nil and gun == re8vr.weapon then
        return true
    end
    local player_weapon = get_equipment_weapon(get_localplayer())
    local player_gun = get_weapon_gun_from_weapon(player_weapon)
    return player_gun ~= nil and gun == player_gun
end

local function on_pre_request_fire(args)
    local gun = sdk.to_managed_object(args[2])
    fire_had_loaded_ammo = false
    if gun == nil then
        return
    end
    if not is_player_weapon_gun(gun) then
        return
    end
    local has_loaded_ammo = weapon_gun_has_loaded_ammo(gun)
    fire_had_loaded_ammo = has_loaded_ammo ~= false
    if fire_had_loaded_ammo then
        add_pending_recoil_shot()
    end
end

local function on_post_request_fire(retval)
    -- A final live round reads as zero after shoot returns; preserve that valid
    -- shot's queued kick and only cancel a fire call that started empty.
    if not fire_had_loaded_ammo and should_cancel_recoil_after_fire() then
        cancel_recoil_state(get_equipment_weapon(get_localplayer()), "post_fire_blocked")
        m_pending_recoil_shots = 0
    end
    fire_had_loaded_ammo = false
    return retval
end

local FIRE_TYPE_NAMES = {
    "app.WeaponGunCore",
}

local function try_hook_fire_method(type_name, method_name)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return false
    end
    local method = td:get_method(method_name)
    if not method then
        return false
    end
    sdk.hook(method, on_pre_request_fire, on_post_request_fire)
    log.info(string.format("%s Hooked %s.%s", LOG_PREFIX, type_name, method_name))
    return true
end

local function install_fire_hooks()
    if fire_hooks_installed then return end
    local hooked = 0
    for _, type_name in ipairs(FIRE_TYPE_NAMES) do
        if try_hook_fire_method(type_name, "shoot") then
            hooked = 1
            break
        end
    end
    fire_hooks_installed = true
    if hooked == 0 then
        log.warn(string.format("%s Fire hooks not installed (no matching WeaponGunCore methods)", LOG_PREFIX))
    end
end

-- Lua API only exposes on_pre_application_entry (not post). IK pre-hook syncs physics;
-- pre entries + on_frame cover the rest of the frame.
re.on_pre_application_entry("UpdateMotion", function()
    sim_frame = get_game_frame_id()
    process_recoil_physics()
end)

re.on_pre_application_entry("LateUpdateBehavior", function()
    process_recoil_physics()
end)

re.on_pre_application_entry("UpdateBehavior", function()
    bootstrap_settings()
end)

re.on_frame(function()
    sim_frame = sim_frame + 1
    if lua_recoil_active() then
        if not fire_hooks_installed then
            install_fire_hooks()
        end
        if not ik_hook_installed then
            install_ik_hook()
        end
        if CFG.suppress_camera_recoil and not camera_recoil_hooks_installed then
            install_camera_recoil_hooks()
        end
    end
end)

local function draw_feature_enable_toggle(is_enabled, id, label)
    local changed = false
    local new_val = is_enabled
    if is_enabled then
        imgui.push_style_color(0, UI_ENABLE)
        if imgui.button("Enable##" .. id) then
            new_val = false
            changed = true
        end
        imgui.pop_style_color(1)
    else
        imgui.push_style_color(0, UI_DISABLE)
        if imgui.button("Disable##" .. id) then
            new_val = true
            changed = true
        end
        imgui.pop_style_color(1)
    end
    imgui.same_line()
    imgui.text(label)
    return changed, new_val
end

local function draw_recoil_ui()
    if not imgui.tree_node("Weapon Recoil") then return end
    local dirty = false
    local c, v = imgui.checkbox("Enable Recoil System##recoil_en", CFG.enabled == true)
    if c then CFG.enabled = v; dirty = true end
    c, v = imgui.slider_float("Global Recoil Intensity##recoil_g", tonumber(CFG.intensity) or 2.0, 0.0, 3.0, "%.2f")
    if c then CFG.intensity = v; dirty = true end
    local supported, weapon = get_equipped_recoil_state()
    if supported == true and weapon ~= nil then
        local wid = get_weapon_recoil_id(weapon)
        local label = weapon_display_name(wid)
        if label == "" then label = wid end
        if label == "" then label = "Equipped" end
        local per = get_per_weapon_intensity(weapon)
        c, v = imgui.slider_float("Equipped (" .. label .. ")##recoil_eq", per, 1.0, 4.0, "%.2f")
        if c then
            if wid ~= "" then set_per_weapon_intensity(wid, v) end
            dirty = true
        end
    else
        imgui.text("Equipped Recoil: N/A")
    end
    if dirty then save_cfg() end
    imgui.tree_pop()
end

_G.__vr_ui_callbacks = _G.__vr_ui_callbacks or {}
table.insert(_G.__vr_ui_callbacks, { order = 42, fn = draw_recoil_ui })

if not _G.__vr_ui_master_installed then
    _G.__vr_ui_master_installed = true
    re.on_draw_ui(function()
        if not _G.__vr_ui_callbacks then
            return
        end
        table.sort(_G.__vr_ui_callbacks, function(a, b)
            return (a.order or 0) < (b.order or 0)
        end)
        for _, cb in ipairs(_G.__vr_ui_callbacks) do
            if cb.fn then
                pcall(cb.fn)
            end
        end
    end)
end

bootstrap_settings()
if lua_recoil_active() then
    install_fire_hooks()
    install_ik_hook()
    if CFG.suppress_camera_recoil then
        install_camera_recoil_hooks()
    end
end
log.info(string.format(
    "%s Loaded (mode=%s) cfg=%s",
    LOG_PREFIX,
    CFG.use_native_recoil and "native" or "lua-ik",
    CFG_PATH))

if type(rawget(_G, "__re8_vr_overlay_bind")) ~= "table" then
    rawset(_G, "__re8_vr_overlay_bind", {})
end

local function recoil_cfg_weapon_id(weapon)
    if weapon == nil then return "" end
    local go_id = get_weapon_recoil_id(weapon)
    if go_id ~= "" and weapon_recoil_supported(go_id, weapon) then
        return go_id
    end
    return go_id
end

rawget(_G, "__re8_vr_overlay_bind").recoil = {
    push = function(api)
        api.set_bool("recoil.enabled", CFG.enabled == true, false)
        api.set_float("recoil.global", tonumber(CFG.intensity) or 2.0, 0.0, 3.0, false)
        local supported, weapon = get_equipped_recoil_state()
        local ok = supported == true and weapon ~= nil
        local label = "No weapon"
        local intensity = 1.22
        if ok then
            local wid = recoil_cfg_weapon_id(weapon)
            label = weapon_display_name(wid)
            if label == "" then label = wid end
            if label == "" then label = "Equipped" end
            intensity = get_per_weapon_intensity(weapon)
        end
        api.set_bool("recoil.equipped_ok", ok, false)
        api.set_string("recoil.equipped_label", label, false)
        api.set_float("recoil.equipped", intensity, 1.0, 4.0, false)
    end,
    pull = function(api)
        CFG.enabled = api.get_bool("recoil.enabled", CFG.enabled == true)
        CFG.intensity = api.get_float("recoil.global", tonumber(CFG.intensity) or 2.0)
        if api.get_bool("recoil.equipped_ok", false) then
            local supported, weapon = get_equipped_recoil_state()
            if supported and weapon then
                local wid = recoil_cfg_weapon_id(weapon)
                if wid ~= "" then
                    set_per_weapon_intensity(wid, api.get_float("recoil.equipped", 1.22))
                end
            end
        end
        save_cfg()
    end,
}

return {}
