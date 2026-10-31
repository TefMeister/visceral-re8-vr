if reframework:get_game_name() ~= "re8" then
    return {}
end

-- Visceral RE8 (2026-10-24): while a save loads, the game's getters throw (System.NullReferenceException) and REFramework
-- logs every throw: 7,568 lines in 14 s on 2026-10-24, the frame rate down to 22-28 fps meanwhile. A getter that fails is
-- not asked again for VRZ.BACKOFF_S seconds. In play these getters answer, so nothing changes there.
local VRZ = { BACKOFF_S = 0.5, until_t = {} }
function VRZ.waiting(name) return os.clock() < (VRZ.until_t[name] or 0) end
function VRZ.failed(name) VRZ.until_t[name] = os.clock() + VRZ.BACKOFF_S end

if not vrmod then
    return {}
end

if not re8vr then
    return {}
end

local statics = require("utility/Statics")
local vrc_manager = require("vr/VRControllerManager")
local GameObject = require("utility/GameObject")

local CHAR = {
    PROFILE_DEFAULT = "default",
    PROFILE_CHRIS = "chris",
}
function CHAR.extract_pl_id(name)
    if type(name) ~= "string" then return nil end
    return name:lower():match("(pl%d%d%d%d)")
end
function CHAR.normalize_profile_name(raw)
    if raw == nil then return CHAR.PROFILE_DEFAULT end
    local name = tostring(raw):lower()
    if name == "chris" or name:find("chris", 1, true) or name:find("pl2001", 1, true) then
        return CHAR.PROFILE_CHRIS
    end
    local pl = CHAR.extract_pl_id(name)
    if pl == "pl2001" then return CHAR.PROFILE_CHRIS end
    return CHAR.PROFILE_DEFAULT
end
function CHAR.get_active_profile_key(player)
    local n = ""
    pcall(function()
        if player then n = player:call("get_Name") or "" end
    end)
    return CHAR.normalize_profile_name(n)
end
local vr_char = CHAR

local CFG_PATH = "re8_vr/re8_vr_holster.json"

local function imgui_col(r, g, b, a)
    a = a or 255
    return ((a & 0xFF) << 24) | ((b & 0xFF) << 16) | ((g & 0xFF) << 8) | (r & 0xFF)
end

local UI_ACCENT = imgui_col(136, 204, 255)
local UI_BTN = imgui_col(64, 224, 208)
local UI_ENABLE = imgui_col(0, 255, 0)
local UI_DISABLE = imgui_col(255, 64, 64)

-- Live inventory cores populate this (weaponName / owner GO -> slot type).
local WEAPON_TYPE_BY_ID = {}

local EXCLUDED_TYPES = {
    Ammo = true,
}

local HOLSTER_EXCLUDED_IDS = {
}

-- Single slot config: home slot + allowed types (weapon-agnostic lookups use this table).
local HOLSTER_SLOTS = {
    pistol = { home_types = { HG = true, MAG = true }, profile_key = "last_pistol_id" },
    longarm = { home_types = { SG = true, SMG = true, GL = true, FT = true }, profile_key = "last_longarm_id" },
    knife = { home_types = { KNF = true }, profile_key = "last_knife_id" },
    medicine = { home_types = { MED = true }, profile_key = "last_medicine_id" },
    -- Unassigned: routing/in-hand tracking only. No zone, mesh clone, or grip draw/stow.
    utility = { home_types = { UTIL = true }, profile_key = "last_utility_id", unassigned = true },
}

local TYPE_TO_SLOT = {
    HG = "pistol",
    SG = "longarm",
    SMG = "longarm",
    GL = "longarm",
    MAG = "pistol",
    FT = "longarm",
    KNF = "knife",
    MED = "medicine",
    UTIL = "utility",
}

-- Physical holster zones: which weapon types may be stowed/drawn per slot (inventory must have item).
-- utility is profile-fit only; STOW.holster_zone_active never creates a body zone for it.
local SLOT_ALLOWED_TYPES = {
    pistol = HOLSTER_SLOTS.pistol.home_types,
    longarm = HOLSTER_SLOTS.longarm.home_types,
    knife = HOLSTER_SLOTS.knife.home_types,
    medicine = HOLSTER_SLOTS.medicine.home_types,
    utility = HOLSTER_SLOTS.utility.home_types,
}

local item_type = sdk.typeof("app.ItemCore")
local motion_type = sdk.typeof("via.motion.Motion")

local PWT_HASH = {
    hg = nil,
    sg = nil,
    smg = nil,
    gl = nil,
    sniper = nil,
    melee = nil,
}
pcall(function()
    local t = sdk.find_type_definition("app.PlayerWeaponType")
    if not t then return end
    local function hash_of(name)
        local f = t:get_field(name)
        if not f then return nil end
        local v = f:get_data(nil)
        if type(v) == "number" then return v end
        return tonumber(v)
    end
    PWT_HASH.hg = hash_of("HandgunHash")
    PWT_HASH.sg = hash_of("ShotgunHash")
    PWT_HASH.smg = hash_of("MachinegunHash")
    PWT_HASH.gl = hash_of("GrenadeLauncherHash")
    PWT_HASH.sniper = hash_of("SniperRifleHash")
    PWT_HASH.melee = hash_of("MeleeHash")
end)

local function safe_call(obj, m, ...)
    if not obj then return nil end
    local ok, a, b, c = pcall(function(...) return obj:call(m, ...) end, ...)
    if not ok then return nil end
    return a, b, c
end

local function managed_object_alive(obj)
    if not obj then return false end
    if sdk.is_valid_obj then
        local okv, valid = pcall(function() return sdk.is_valid_obj(obj) end)
        if okv and valid == false then return false end
    end
    local ok, addr = pcall(function() return obj:get_address() end)
    if not ok or addr == nil or addr == 0 then return false end
    local ok2, td = pcall(function() return obj:get_type_definition() end)
    return ok2 and td ~= nil
end

-- Item-box / storage can leave Weapon components that still pass managed_object_alive
-- but throw InvalidOperationException on get_GameObject. Avoid touching them.
local function weapon_component_usable(weapon)
    if not weapon or not managed_object_alive(weapon) then return false end
    local ok = false
    pcall(function()
        local go = weapon:call("get_GameObject")
        if not go then go = weapon:call("get_owner") end
        if not go then go = weapon:get_field("<owner>k__BackingField") end
        if go and managed_object_alive(go) then ok = true end
    end)
    return ok
end
rawset(_G, "__re8_weapon_component_usable", weapon_component_usable)

local function read_system_string(s)
    if s == nil then return nil end
    if type(s) == "string" then return s end
    local ok, v = pcall(function() return s:gsub("%z.*", "") end)
    if ok and type(v) == "string" and v ~= "" then return v end
    ok, v = pcall(function()
        if s.get_type_definition then
            return tostring(s)
        end
        return nil
    end)
    if ok and type(v) == "string" then
        v = v:gsub("%z.*", "")
        if v ~= "" then return v end
    end
    return nil
end

local function normalize_item_id(id)
    if type(id) ~= "string" then return nil end
    id = id:gsub("^%s+", ""):gsub("%s+$", "")
    if id == "" then return nil end
    -- Inventory GO names are ri####_Inventory; keep the ri#### id.
    id = id:gsub("_Inventory$", ""):gsub("_Equipped$", "")
    return id
end

local function pwt_u32(v)
    if type(v) == "number" then return v end
    if v == nil then return nil end
    local n = tonumber(v)
    if type(n) == "number" then return n end
    return nil
end

local function pwt_name_for_hash(hash)
    if hash == nil then return nil end
    local n = nil
    pcall(function()
        local td = sdk.find_type_definition("app.PlayerWeaponType")
        local m = td and td:get_method("getName")
        if m then n = m:call(nil, hash) end
    end)
    if type(n) == "string" and n ~= "" then return n end
    return nil
end

local function classify_from_weapon_type_hash(hash)
    hash = pwt_u32(hash)
    if hash == nil then return nil end
    if PWT_HASH.hg ~= nil and hash == PWT_HASH.hg then return "HG" end
    if PWT_HASH.sg ~= nil and hash == PWT_HASH.sg then return "SG" end
    if PWT_HASH.smg ~= nil and hash == PWT_HASH.smg then return "SMG" end
    if PWT_HASH.gl ~= nil and hash == PWT_HASH.gl then return "GL" end
    if PWT_HASH.sniper ~= nil and hash == PWT_HASH.sniper then return "SG" end
    if PWT_HASH.melee ~= nil and hash == PWT_HASH.melee then return "KNF" end
    local nm = pwt_name_for_hash(hash)
    if type(nm) == "string" then
        local lower = string.lower(nm)
        if lower:find("handgun", 1, true) then return "HG" end
        if lower:find("shotgun", 1, true) then return "SG" end
        if lower:find("sniper", 1, true) then return "SG" end
        if lower:find("machinegun", 1, true) or lower:find("machine", 1, true) then return "SMG" end
        if lower:find("grenade", 1, true) then return "GL" end
        if lower:find("melee", 1, true) then return "KNF" end
    end
    return nil
end

local MEDICINE_IDS = {
    ri1020 = true, -- First Aid Med
    ri1021 = true, -- Chem Fluid / med variant
    ri1022 = true, -- Syringe
}

local function is_medicine_core(core)
    if not core then return false end
    local ok, td = pcall(function() return core:get_type_definition() end)
    if not ok or not td then return false end
    local ok_m, is_m = pcall(function() return td:is_a("app.MedicineCore") end)
    return ok_m and is_m == true
end

local function is_medicine_item_id(item_id)
    item_id = normalize_item_id(item_id)
    if not item_id then return false end
    if MEDICINE_IDS[item_id] then return true end
    local mapped = WEAPON_TYPE_BY_ID[item_id]
    return mapped == "MED"
end

local function classify_item_core(core)
    if not core then return nil end
    if is_medicine_core(core) then return "MED" end
    local td = nil
    pcall(function() td = core:get_type_definition() end)
    if not td then return nil end
    local ok_thr, is_thr = pcall(function() return td:is_a("app.WeaponThrowableCore") end)
    if ok_thr and is_thr then return "UTIL" end
    local ok_melee, is_melee = pcall(function() return td:is_a("app.WeaponMeleeCore") end)
    if ok_melee and is_melee then return "KNF" end
    local hash = nil
    pcall(function()
        local spec = core:call("get_spec")
        if not spec then return end
        local wspec = spec:call("get_weapon")
        if not wspec then wspec = spec:get_field("Weapon") end
        if not wspec then return end
        hash = wspec:call("get_weaponTypeHash")
        if hash == nil then hash = wspec:get_field("WeaponTypeHash") end
    end)
    local from_hash = classify_from_weapon_type_hash(hash)
    if from_hash then return from_hash end
    local long_w = false
    local short_w = false
    pcall(function() long_w = core:call("isLongWeapon") == true end)
    pcall(function() short_w = core:call("isShortWeapon") == true end)
    if long_w then return "SG" end
    if short_w then return "HG" end
    local gun = nil
    pcall(function()
        local go = core:call("get_owner") or core:call("get_GameObject")
        if not go then return end
        local gt = sdk.typeof("app.WeaponGunCore")
        if gt then gun = go:call("getComponent(System.Type)", gt) end
    end)
    if gun and gun ~= core then
        pcall(function() long_w = gun:call("isLongWeapon") == true end)
        pcall(function() short_w = gun:call("isShortWeapon") == true end)
        if long_w then return "SG" end
        if short_w then return "HG" end
        local gun_hash = nil
        pcall(function()
            local spec = gun:call("get_spec")
            local wspec = spec and (spec:call("get_weapon") or spec:get_field("Weapon"))
            if wspec then
                gun_hash = wspec:call("get_weaponTypeHash") or wspec:get_field("WeaponTypeHash")
            end
        end)
        from_hash = classify_from_weapon_type_hash(gun_hash)
        if from_hash then return from_hash end
    end
    return nil
end

local function weapon_type_for_item_id(item_id)
    item_id = normalize_item_id(item_id)
    if not item_id then return nil end
    if HOLSTER_EXCLUDED_IDS[item_id] then return "UTIL" end
    local mapped = WEAPON_TYPE_BY_ID[item_id]
    if mapped then return mapped end
    if MEDICINE_IDS[item_id] then return "MED" end
    if item_id:find("Handgun", 1, true) then return "HG" end
    if item_id:find("Shotgun", 1, true) or item_id:find("Sniper", 1, true) then return "SG" end
    if item_id:find("MachineGun", 1, true) or item_id:find("Machinegun", 1, true) then return "SMG" end
    if item_id:find("Magnum", 1, true) then return "MAG" end
    if item_id:find("Knife", 1, true) then return "KNF" end
    if item_id:find("Medicine", 1, true) or item_id:find("Herb", 1, true) then return "MED" end
    if item_id:find("GrenadeLauncher", 1, true) then return "GL" end
    return nil
end

local function type_allowed_for_holster_slot(wtype, slot)
    if not wtype or not slot or slot == "chest" then return false end
    local allowed = SLOT_ALLOWED_TYPES[slot]
    return allowed ~= nil and allowed[wtype] == true
end

local function item_type_fits_holster_slot(item_id, slot)
    return type_allowed_for_holster_slot(weapon_type_for_item_id(item_id), slot)
end

local function holster_slot_for_item_id(item_id)
    item_id = normalize_item_id(item_id)
    if not item_id then return nil end
    local wtype = weapon_type_for_item_id(item_id)
    if not wtype or EXCLUDED_TYPES[wtype] then
        return nil
    end
    return TYPE_TO_SLOT[wtype]
end

local function weapon_id_matches_holster_slot(item_id, slot)
    if not item_id or not slot then return false end
    return holster_slot_for_item_id(item_id) == slot
end

local function fallback_slot_from_weapon_type(weapon)
    if not weapon then return nil end
    local wtype = classify_item_core(weapon)
    if wtype then return TYPE_TO_SLOT[wtype] end
    local ok, td = pcall(function() return weapon:get_type_definition() end)
    if not ok or not td then return nil end
    local checks = {
        { "app.WeaponMeleeCore", "knife" },
        { "app.MedicineCore", "medicine" },
        { "app.WeaponThrowableCore", "utility" },
        { "app.WeaponGunCore", "longarm" },
    }
    for _, c in ipairs(checks) do
        local ok2, is_a = pcall(function() return td:is_a(c[1]) end)
        if ok2 and is_a then return c[2] end
    end
    return nil
end

local function block_weapon_inputs_active()
    return rawget(_G, "__vr_block_weapon_inputs") == true
end

local function manual_reload_blocks_holster()
    if rawget(_G, "__vr_ammo_blocks_weapon_holster") == true then return true end
    if rawget(_G, "__vr_ammo_in_left_hand") == true then return true end
    if rawget(_G, "__vr_ammo_insert_active") == true then return true end
    local fn = rawget(_G, "__re8_ammo_drop_mag_blocks_holster")
    if type(fn) == "function" then
        local ok, v = pcall(fn)
        if ok and v == true then return true end
    end
    -- Do NOT block on raw ap.get_state(): parked OUT on another weapon must
    -- not lock weapon holster / swap for the active gun.
    return false
end

local function slide_dock_blocks_inventory_gesture()
    return rawget(_G, "__vr_slide_dock_blocks_inventory") == true
end

local CFG = {
    enabled = true,
    hip_pistol_enabled = true,
    ammo_left_enabled = true,
    ammo_left_zone_haptic_enabled = true,
    shoulder_enabled = true,
    chest_enabled = false,
    knife_enabled = true,
    medicine_enabled = true,
    medicine_holster_v2 = false,
    medicine_pour_xy_m = 0.24,
    medicine_pour_above_m = 0.05,
    medicine_pour_dot = -0.50,
    medicine_pour_hold_s = 0.12,
    medicine_pour_axis = 1,
    medicine_pour_axis_sign = 1.0,
    medicine_pour_palm_m = 0.10,
    medicine_inject_m = 0.16,
    medicine_inject_hold_s = 0.12,
    medicine_inject_bottom_m = 0.07,
    ammo_left_zone_haptic_continuous = true,
    -- Optional left-controller pulse when ammo mag successfully grabs to hand.
    ammo_grab_haptic_enabled = true,
    block_swap_anims = true,
    suppress_motion_layers = { 0, 2, 3, 5 },
    zone_haptic_enabled = true,
    hip_zone_haptic_enabled = true,
    hip_zone_haptic_continuous = false,
    shoulder_zone_haptic_enabled = true,
    shoulder_zone_haptic_continuous = false,
    chest_zone_haptic_enabled = true,
    chest_zone_haptic_continuous = true,
    knife_zone_haptic_enabled = true,
    knife_zone_haptic_continuous = false,
    medicine_zone_haptic_enabled = true,
    medicine_zone_haptic_continuous = false,
    head_flashlight_enabled = true,
    head_flash_zone_haptic_enabled = true,
    head_flash_zone_haptic_continuous = true,
    inventory_gesture_enabled = true,
    inventory_zone_haptic_enabled = true,
    inventory_zone_haptic_continuous = true,
    -- Shift inventory touch target to the palm/front of the left wrist so
    -- brushing the back of the wrist does not count as in-zone.
    inventory_wrist_front_m = 0.04,
    inventory_wrist_front_sign = 1.0,
    inventory_wrist_front_only = true,
    -- Continuous zone indicator preset (enter + optional hold rumble).
    zone_haptic_duration = 0.15,
    zone_haptic_frequency = 58.883,
    zone_haptic_amplitude = 0.05,
    zone_haptic_frames = 2,
    haptic_intensity = 0.8,
    grab_haptic_duration = 0.06,
    grab_haptic_frequency = 200.0,
    grab_haptic_amplitude = 0.7,
    medicine_grab_haptic_duration = 0.1,
    medicine_grab_haptic_frequency = 1.0,
    medicine_grab_haptic_amplitude = 5.0,
    suppress_shoot_ready_after_holster_equip = true,
    suppress_shoot_ready_after_holster_s = 0.45,
    suppress_shoot_ready_in_holster_zone = true,
    holster_weapon_hover_m = 0.24,
    -- Short world-space fly for hip/knife draw+stow (probe mesh lerp).
    holster_fly_enabled = true,
    holster_fly_s = 0.10,
    medicine_fly_s = 0.28,
    -- Fallback hand-local offset to held-weapon pivot (right/up/forward on RH IK).
    -- Auto-learned from weaponMeshObject whenever a gun/knife is held; these are seeds.
    holster_fly_hold_off_r = -0.10,
    holster_fly_hold_off_u = -0.03,
    holster_fly_hold_off_f = 0.02,
    -- Tighter holster mesh body follow when tight=true.
    holster_mesh_follow_tight = true,
    holster_mesh_smooth_enabled = true,
    holster_mesh_smooth_deadzone_m = 0.008,
    holster_mesh_smooth_tau_fast = 0.02,
    holster_mesh_smooth_tau_slow = 0.035,
    holster_mesh_smooth_snap_m = 0.55,
    holster_zone_motion_sync = true,
    holster_zone_waist_tau = 0.12,
    holster_zone_chest_tau = 0.25,
    holster_zone_yaw_tau = 0.10,
    holster_follow_v1 = false,
    medicine_inner_m = 0.16,
    medicine_blocks_weapon_m = 0.17,
    -- Bare hands + hold RT in a holster zone to start capture countdown.
    quick_calib_enabled = true,
    quick_calib_hold_s = 3.0,
    -- Upper-body torso frame for weapon holsters (hip pistol + chest knife).
    -- Offset from the player body root (after VR body IK) to the torso reference
    -- plane, expressed in yaw-only axes (right, up, forward). Not HMD-relative.
    torso_neck_off_x = 0.0,
    torso_neck_off_y = -0.15,
    torso_neck_off_z = 0.02,
}

local PROFILE_KEYS = {
    "hip_pistol_off_right", "hip_pistol_off_up", "hip_pistol_off_forward",
    "hip_pistol_trigger_dist", "hip_pistol_release_dist", "hip_pistol_cooldown",
    "hip_pistol_grab_scale",
    "ammo_left_off_right", "ammo_left_off_up", "ammo_left_off_forward",
    "ammo_left_trigger_dist", "ammo_left_release_dist", "ammo_left_cooldown",
    "shoulder_off_x", "shoulder_off_y", "shoulder_off_z",
    "shoulder_trigger_dist", "shoulder_release_dist", "shoulder_cooldown",
    "chest_off_x", "chest_off_y", "chest_off_z",
    "chest_trigger_dist", "chest_release_dist", "chest_cooldown",
    "knife_off_x", "knife_off_y", "knife_off_z",
    "knife_trigger_dist", "knife_release_dist", "knife_cooldown",
    "knife_grab_scale",
    "medicine_off_right", "medicine_off_up", "medicine_off_forward",
    "medicine_trigger_dist", "medicine_release_dist", "medicine_cooldown",
    "head_flash_off_x", "head_flash_off_y", "head_flash_off_z",
    "head_flash_trigger_dist", "head_flash_release_dist", "head_flash_cooldown",
    "head_flash_beam_right", "head_flash_beam_up", "head_flash_beam_forward",
    "head_flash_beam_yaw", "head_flash_beam_pitch", "head_flash_beam_roll",
    "inventory_trigger_dist", "inventory_release_dist", "inventory_cooldown",
    "last_pistol_id", "last_longarm_id", "last_chest_id", "last_knife_id",
    "last_medicine_id", "last_utility_id", "medicine_grab_scale",
}

local function make_default_profile()
    return {
        hip_pistol_off_right = -0.24957496712143068,
        hip_pistol_off_up = 0.34659043220402697,
        hip_pistol_off_forward = 0.15094777712697272,
        hip_pistol_trigger_dist = 0.10,
        hip_pistol_release_dist = 0.11,
        hip_pistol_grab_scale = 1.10,
        hip_pistol_cooldown = 0.6,
        -- Left-hip ammo pouch (mirror of right pistol hip; calibrate with left hand).
        ammo_left_off_right = 0.34470150762389484,
        ammo_left_off_up = 0.04021004482211055,
        ammo_left_off_forward = 0.008698713984337303,
        ammo_left_trigger_dist = 0.24,
        ammo_left_release_dist = 0.34,
        ammo_left_cooldown = 0.45,
        shoulder_off_x = -0.1520686949958485,
        shoulder_off_y = -0.037568839918572364,
        shoulder_off_z = 0.014533467698119643,
        shoulder_trigger_dist = 0.23,
        shoulder_release_dist = 0.33,
        shoulder_cooldown = 0.6,
        chest_off_x = -0.2970419969179548,
        chest_off_y = 0.17201436252781332,
        chest_off_z = -0.12454713812898097,
        chest_trigger_dist = 0.23,
        chest_release_dist = 0.11,
        chest_cooldown = 0.6,
        knife_off_x = 0.03797339896846097,
        knife_off_y = -0.0264306664466858,
        knife_off_z = 0.18073278537372062,
        knife_trigger_dist = 0.10,
        knife_release_dist = 0.11,
        knife_grab_scale = 1.10,
        knife_cooldown = 0.6,
        -- Ethan right-chest medicine (joint-local).
        medicine_off_right = -0.09186137021077913,
        medicine_off_up = -0.18121802806854248,
        medicine_off_forward = 0.16367426811675045,
        medicine_trigger_dist = 0.10,
        medicine_release_dist = 0.16,
        medicine_cooldown = 0.5,
        medicine_grab_scale = 1.10,
        -- HMD-local left-head flashlight defaults.
        head_flash_off_x = -0.16000282433421262,
        head_flash_off_y = 0.004465746947476267,
        head_flash_off_z = -0.06936190240480249,
        head_flash_trigger_dist = 0.10,
        head_flash_release_dist = 0.16,
        head_flash_cooldown = 0.5,
        head_flash_beam_right = 0.0,
        head_flash_beam_up = 0.0,
        head_flash_beam_forward = 0.0,
        head_flash_beam_yaw = 0.0,
        head_flash_beam_pitch = 0.0,
        head_flash_beam_roll = 0.0,
        -- Right index tip (R_IndexF3) near left hand/wrist (L_Hand).
        inventory_trigger_dist = 0.04,
        inventory_release_dist = 0.10,
        inventory_cooldown = 0.8,
        last_pistol_id = "",
        last_longarm_id = "",
        last_chest_id = "",
        last_knife_id = "",
        last_medicine_id = "",
        last_utility_id = "",
    }
end

-- Per-character profiles hang on PROF to stay under Lua 200-local limit.
local PROF = {
    key = "default",
    pl = "",
    map = { default = make_default_profile() },
    slot_offset_keys = {
        hip = { "hip_pistol_off_right", "hip_pistol_off_up", "hip_pistol_off_forward" },
        shoulder = { "shoulder_off_x", "shoulder_off_y", "shoulder_off_z" },
        knife = { "knife_off_x", "knife_off_y", "knife_off_z" },
        medicine = { "medicine_off_right", "medicine_off_up", "medicine_off_forward" },
        flashlight = { "head_flash_off_x", "head_flash_off_y", "head_flash_off_z" },
    },
    builtin_offsets = {
        default = {
            hip = { -0.24957496712143068, 0.34659043220402697, 0.15094777712697272 },
            shoulder = { -0.1520686949958485, -0.037568839918572364, 0.014533467698119643 },
            knife = { 0.03797339896846097, -0.0264306664466858, 0.18073278537372062 },
            medicine = { -0.09186137021077913, -0.18121802806854248, 0.16367426811675045 },
            flashlight = { -0.16000282433421262, 0.004465746947476267, -0.06936190240480249 },
        },
        chris = {
            hip = { -0.28032702062988335, 0.3138640489513165, 0.36382629248441845 },
            shoulder = { -0.1520686949958485, -0.037568839918572364, 0.014533467698119643 },
            knife = { 0.029207583665765924, -0.10679626464843749, 0.2704452345747086 },
            medicine = { -0.07630366090734242, 0.08892059326171875, 0.2498858266183106 },
            flashlight = { -0.16000282433421262, 0.004465746947476267, -0.06936190240480249 },
        },
        clancy = {
            hip = { -0.24957496712143068, 0.34659043220402697, 0.15094777712697272 },
            shoulder = { -0.1520686949958485, -0.037568839918572364, 0.014533467698119643 },
            knife = { 0.10730164479790005, 0.03405523300170898, 0.19803739430777512 },
            medicine = { -0.056025118971660966, 0.011517047882080068, 0.1291045371932853 },
            flashlight = { -0.16000282433421262, 0.004465746947476267, -0.06936190240480249 },
        },
        mia = {
            hip = { -0.24957496712143068, 0.34659043220402697, 0.15094777712697272 },
            shoulder = { -0.1520686949958485, -0.037568839918572364, 0.014533467698119643 },
            knife = { 0.06911828112038167, -0.06320995092391966, 0.19818798383914782 },
            medicine = { -0.09186137021077913, -0.18121802806854248, 0.16367426811675045 },
            flashlight = { -0.16000282433421262, 0.004465746947476267, -0.06936190240480249 },
        },
    },
}

function PROF.merge_fields(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for _, k in ipairs(PROFILE_KEYS) do
        if src[k] ~= nil then
            if k:find("^last_") then
                if type(src[k]) == "string" then
                    dst[k] = normalize_item_id(src[k]) or ""
                end
            elseif type(src[k]) == type(dst[k]) then
                dst[k] = src[k]
            elseif type(dst[k]) == "number" and tonumber(src[k]) then
                dst[k] = tonumber(src[k])
            end
        end
    end
end

function PROF.clone_from_default()
    local p = make_default_profile()
    local src = PROF.map.default
    if type(src) == "table" then
        PROF.merge_fields(p, src)
        p.last_pistol_id = ""
        p.last_longarm_id = ""
        p.last_chest_id = ""
        p.last_knife_id = ""
        p.last_medicine_id = ""
        p.last_utility_id = ""
    end
    return p
end

function PROF.ensure(key)
    key = vr_char.normalize_profile_name(key)
    if not PROF.map[key] then
        if key == "default" then
            PROF.map[key] = make_default_profile()
        else
            PROF.map[key] = PROF.clone_from_default()
        end
    end
    return PROF.map[key]
end

function PROF.current_key()
    return vr_char.get_active_profile_key(re8vr and re8vr.player or nil)
end

function PROF.get()
    local k = PROF.current_key()
    if k ~= PROF.key then
        local prev = PROF.key
        PROF.key = k
        local go_name = ""
        pcall(function()
            if re8vr and re8vr.player then
                go_name = re8vr.player:call("get_Name") or ""
            end
        end)
        PROF.pl = vr_char.extract_pl_id(go_name) or ""
    end
    return PROF.ensure(k)
end

function PROF.copy_default_offsets(P)
    if not P or P == PROF.map.default then return false end
    local src = PROF.map.default
    if type(src) ~= "table" then return false end
    for _, k in ipairs(PROFILE_KEYS) do
        if not k:find("^last_") and src[k] ~= nil then
            P[k] = src[k]
        end
    end
    return true
end

function PROF.sanitize_legacy()
    local eth = PROF.map.ethan
    if type(eth) ~= "table" then return end
    local up = tonumber(eth.hip_pistol_off_up) or 0
    local sy = tonumber(eth.shoulder_off_y) or 0
    if math.abs(up) > 0.75 or math.abs(sy) > 0.75 then
        PROF.map.ethan = nil
    end
end

local function get_profile()
    return PROF.get()
end

local function publish_holster_slot_enabled()
    rawset(_G, "__re8_holster_slot_enabled", {
        hip = CFG.enabled == true and CFG.hip_pistol_enabled ~= false and rawget(_G, "__visceral_holsters_on") ~= true,
        knife = CFG.enabled == true and CFG.knife_enabled ~= false,
        medicine = CFG.enabled == true and CFG.medicine_enabled ~= false,
    })
end

local function save_cfg()
    pcall(function()
        -- Preserve holster visual sections (hip_visual / knife_visual / medicine_visual
        -- and old *_probe_visual keys) plus any future top-level extension data.
        local data = json.load_file(CFG_PATH)
        if type(data) ~= "table" then data = {} end
        for k, v in pairs(CFG) do
            if type(v) ~= "table" then data[k] = v end
        end
        data.suppress_motion_layers = CFG.suppress_motion_layers
        data.profiles = PROF.map
        data.active_profile_hint = PROF.key
        data.zone_haptic_preset = 2
        json.dump_file(CFG_PATH, data)
        -- Bust visual offset cache used by mesh-aligned grab.
        rawset(_G, "__re8_holster_vis_cache_bust", true)
        publish_holster_slot_enabled()
    end)
end

function PROF.reset_slot_offsets(slot)
    local keys = PROF.slot_offset_keys[slot]
    if not keys then return false end
    local P = PROF.get()
    if type(P) ~= "table" then return false end
    local builtins = PROF.builtin_offsets
    local row = builtins[PROF.key]
    if type(row) ~= "table" then row = builtins.default end
    local vals = type(row) == "table" and row[slot] or nil
    if type(vals) ~= "table" then
        row = builtins.default
        vals = type(row) == "table" and row[slot] or nil
    end
    if type(vals) ~= "table" then return false end
    P[keys[1]] = vals[1]
    P[keys[2]] = vals[2]
    P[keys[3]] = vals[3]
    pcall(save_cfg)
    return true
end

local function apply_loaded_cfg(data)
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do
        if CFG[k] ~= nil and type(v) == type(CFG[k]) then
            CFG[k] = v
        end
    end
    if type(data.suppress_motion_layers) == "table" and #data.suppress_motion_layers > 0 then
        CFG.suppress_motion_layers = data.suppress_motion_layers
    end
    if type(data.profiles) == "table" then
        for char_key, char_data in pairs(data.profiles) do
            if type(char_data) == "table" then
                local pk = vr_char.normalize_profile_name(char_key)
                local skip = false
                -- Never let a corrupt "ethan" profile overwrite calibrated default.
                if char_key == "ethan" and pk == "default" then
                    local up = tonumber(char_data.hip_pistol_off_up) or 0
                    local sy = tonumber(char_data.shoulder_off_y) or 0
                    if math.abs(up) > 0.75 or math.abs(sy) > 0.75 then
                        skip = true
            end
        end
                if not skip then
                    PROF.merge_fields(PROF.ensure(pk), char_data)
                end
            end
        end
    end
    PROF.sanitize_legacy()
end

-- Apply continuous zone-indicator preset (saved JSON often kept enter-only).
local function migrate_zone_haptic_continuous_preset(data)
    if type(data) ~= "table" then data = {} end
    if tonumber(data.zone_haptic_preset) == 2 then
        return false
    end
    CFG.hip_zone_haptic_continuous = true
    CFG.knife_zone_haptic_continuous = true
    CFG.shoulder_zone_haptic_continuous = true
    CFG.chest_zone_haptic_continuous = true
    CFG.medicine_zone_haptic_continuous = true
    CFG.head_flash_zone_haptic_continuous = true
    -- Continuous zone indicator preset.
    CFG.zone_haptic_duration = 0.15
    CFG.zone_haptic_frequency = 58.883
    CFG.zone_haptic_amplitude = 0.05
    -- Retrigger often enough that OpenXR pulses overlap → constant feel.
    CFG.zone_haptic_frames = 2
    CFG.haptic_intensity = 1.0
    CFG.zone_haptic_enabled = true
    CFG.hip_zone_haptic_enabled = true
    CFG.knife_zone_haptic_enabled = true
    return true
end

local function sanitize_profile_slot_ids(P)
    if not P then return end
    local function clear_or_migrate(slot, key)
        local item_id = normalize_item_id(P[key])
        if not item_id or item_id == "" then
            P[key] = ""
            return
        end
        if slot == "chest" or not item_type_fits_holster_slot(item_id, slot) then
            local home = holster_slot_for_item_id(item_id)
            if home and home ~= slot then
                local home_key = HOLSTER_SLOTS[home] and HOLSTER_SLOTS[home].profile_key
                if home_key and (not P[home_key] or P[home_key] == "") then
                    P[home_key] = item_id
                end
            elseif slot == "chest" and weapon_type_for_item_id(item_id) == "MAG"
                and (not P.last_pistol_id or P.last_pistol_id == "") then
                P.last_pistol_id = item_id
            end
            P[key] = ""
        end
    end
    clear_or_migrate("pistol", "last_pistol_id")
    clear_or_migrate("longarm", "last_longarm_id")
    clear_or_migrate("knife", "last_knife_id")
    clear_or_migrate("chest", "last_chest_id")
    clear_or_migrate("medicine", "last_medicine_id")
    clear_or_migrate("utility", "last_utility_id")
end

local function load_cfg_from_disk()
    local data = json.load_file(CFG_PATH)
    if type(data) ~= "table" then
        json.dump_file(CFG_PATH, {
            enabled = CFG.enabled,
            profiles = PROF.map,
            suppress_motion_layers = CFG.suppress_motion_layers,
            zone_haptic_preset = 2,
        })
        return
    end
    apply_loaded_cfg(data)
    local migrated = migrate_zone_haptic_continuous_preset(data)
    for _, P in pairs(PROF.map) do
        P.last_pistol_id = normalize_item_id(P.last_pistol_id) or ""
        P.last_longarm_id = normalize_item_id(P.last_longarm_id) or ""
        P.last_chest_id = normalize_item_id(P.last_chest_id) or ""
        P.last_knife_id = normalize_item_id(P.last_knife_id) or ""
        P.last_medicine_id = normalize_item_id(P.last_medicine_id) or ""
        P.last_utility_id = normalize_item_id(P.last_utility_id) or ""
        sanitize_profile_slot_ids(P)
    end
    if migrated then
        save_cfg()
    end
end

load_cfg_from_disk()

-- One-time: old JSON kept Lua medicine forced off. Enable the right-chest holster.
if CFG.medicine_holster_v2 ~= true then
    CFG.medicine_enabled = true
    CFG.medicine_holster_v2 = true
    save_cfg()
end
-- v2 already stamped true, then later saves left medicine_enabled false while
-- visuals still spawn the chest mesh. Restore grab to match Backup.
if CFG.medicine_holster_v3 ~= true then
    CFG.medicine_enabled = true
    CFG.medicine_holster_v3 = true
    save_cfg()
end
if CFG.medicine_inject_tune_v2 ~= true then
    CFG.medicine_inject_m = 0.24
    CFG.medicine_inject_tune_v2 = true
    save_cfg()
end

if CFG.holster_follow_v1 ~= true then
    CFG.holster_mesh_follow_tight = true
    CFG.holster_mesh_smooth_enabled = true
    CFG.holster_mesh_smooth_deadzone_m = 0.008
    CFG.holster_mesh_smooth_tau_fast = 0.02
    CFG.holster_mesh_smooth_tau_slow = 0.035
    CFG.holster_mesh_smooth_snap_m = 0.55
    CFG.holster_zone_motion_sync = true
    CFG.holster_zone_waist_tau = 0.12
    CFG.holster_zone_chest_tau = 0.25
    CFG.holster_zone_yaw_tau = 0.10
    CFG.holster_follow_v1 = true
    save_cfg()
end

local function publish_holster_follow_cfg()
    rawset(_G, "__re8_holster_follow_cfg", {
        tight = CFG.holster_mesh_follow_tight ~= false,
        smooth_enabled = CFG.holster_mesh_smooth_enabled ~= false,
        deadzone = tonumber(CFG.holster_mesh_smooth_deadzone_m) or 0.008,
        tau_fast = tonumber(CFG.holster_mesh_smooth_tau_fast) or 0.02,
        tau_slow = tonumber(CFG.holster_mesh_smooth_tau_slow) or 0.035,
        snap = tonumber(CFG.holster_mesh_smooth_snap_m) or 0.55,
    })
end
publish_holster_follow_cfg()
publish_holster_slot_enabled()

local function holster_zone_lp_tau(kind)
    local tight = CFG.holster_mesh_follow_tight ~= false
    if kind == "waist" then
        if tight then return tonumber(CFG.holster_zone_waist_tau) or 0.12 end
        return 0.28
    end
    if kind == "chest" then
        if tight then return tonumber(CFG.holster_zone_chest_tau) or 0.25 end
        return 0.70
    end
    if kind == "yaw" then
        if tight then return tonumber(CFG.holster_zone_yaw_tau) or 0.10 end
        return 0.22
    end
    return 0.28
end

rawset(_G, "__vr_lua_holster_active", true)
rawset(_G, "__vr_lua_heal_override", CFG.medicine_enabled == true)

local COMPONENTS = {
    updater = nil,
    weapon_change = nil,
    equip_manager = nil,
    mesh_controller = nil,
    player_gun = nil,
    player_melee = nil,
    hand_light = nil,
    last_scan = 0,
    resolve_wc = "nil",
    resolve_em = "nil",
    resolve_mc = "nil",
    resolve_pg = "nil",
    resolve_up = "nil",
}

COMPONENTS.bind_muzzle = function(weapon)
    if not weapon then return false end
    local muz = nil
    pcall(function() muz = weapon:get_field("MuzzleJoint") end)
    if muz then return true end
    local go = nil
    pcall(function() go = weapon:call("get_owner") end)
    if not go then
        pcall(function() go = weapon:call("get_GameObject") end)
    end
    if go then
        pcall(function()
            if weapon:get_field("<owner>k__BackingField") == nil then
                weapon:set_field("<owner>k__BackingField", go)
            end
        end)
    end
    local tf = nil
    if go then
        pcall(function() tf = go:call("get_Transform") end)
    end
    if not tf then return false end
    local names = { "vfx_muzzle", "vfx_muzzle1", "vfx_muzzle2" }
    local i = 1
    while i <= #names do
        local j = nil
        pcall(function() j = tf:call("getJointByName", names[i]) end)
        if j then
            pcall(function() weapon:set_field("MuzzleJoint", j) end)
            return true
        end
        i = i + 1
    end
    return false
end


local function get_player_transform()
    if re8vr.transform then return re8vr.transform end
    if not re8vr.player or not managed_object_alive(re8vr.player) then return nil end
    return safe_call(re8vr.player, "get_Transform")
end

local function find_player_component(type_name)
    local player = re8vr.player
    if not player or not managed_object_alive(player) then return nil, "no_player" end

    local ok_gc, comp = pcall(function()
        return GameObject.get_component(player, type_name)
    end)
    if ok_gc and comp then return comp, "getComponent" end

    local tf = get_player_transform()
    local tdef = sdk.typeof(type_name)
    if tf and tdef then
        local ok, found = pcall(function() return tf:find(tdef) end)
        if ok and found then return found, "transform_find" end
    end

    if tdef then
        local ok, found = pcall(function() return player:call("getComponent(System.Type)", tdef) end)
        if ok and found then return found, "player_getComponent" end
    end

    return nil, "missing"
end

COMPONENTS.get_updater = function()
    if COMPONENTS.updater and managed_object_alive(COMPONENTS.updater) then
        return COMPONENTS.updater, COMPONENTS.resolve_up
    end
    local up, src = find_player_component("app.PlayerUpdaterFPS")
    if up then return up, src or "PlayerUpdaterFPS" end
    up, src = find_player_component("app.PlayerUpdaterPl2001")
    if up then return up, src or "PlayerUpdaterPl2001" end
    return nil, "missing"
end

COMPONENTS.call_updater = function(updater, method)
    if not updater then return nil end
    if VRZ.waiting(method) then return nil end -- Visceral RE8: failed a moment ago (loading)
    local obj = nil
    pcall(function() obj = updater:call(method) end)
    if obj and managed_object_alive(obj) then return obj end
    VRZ.failed(method)
    return nil
end

local function refresh_components(force)
    local now = os.clock()
    if not re8vr or not re8vr.player or not managed_object_alive(re8vr.player) then
        COMPONENTS.updater = nil
        COMPONENTS.weapon_change = nil
        COMPONENTS.equip_manager = nil
        COMPONENTS.mesh_controller = nil
        COMPONENTS.player_gun = nil
        COMPONENTS.player_melee = nil
        COMPONENTS.hand_light = nil
        return false
    end
    if not force and (now - COMPONENTS.last_scan) < 1.0 then
        if COMPONENTS.weapon_change and not managed_object_alive(COMPONENTS.weapon_change) then
            COMPONENTS.weapon_change = nil
        end
        if COMPONENTS.equip_manager and not managed_object_alive(COMPONENTS.equip_manager) then
            COMPONENTS.equip_manager = nil
        end
        if COMPONENTS.mesh_controller and not managed_object_alive(COMPONENTS.mesh_controller) then
            COMPONENTS.mesh_controller = nil
        end
        if COMPONENTS.player_gun and not managed_object_alive(COMPONENTS.player_gun) then
            COMPONENTS.player_gun = nil
        end
        if COMPONENTS.player_melee and not managed_object_alive(COMPONENTS.player_melee) then
            COMPONENTS.player_melee = nil
        end
        if COMPONENTS.updater and not managed_object_alive(COMPONENTS.updater) then
            COMPONENTS.updater = nil
        end
        return COMPONENTS.weapon_change ~= nil
    end
    COMPONENTS.last_scan = now

    local ok_scan = pcall(function()
        local updater, usrc = COMPONENTS.get_updater()
        COMPONENTS.updater = updater
        COMPONENTS.resolve_up = usrc or "nil"

        local wc = COMPONENTS.call_updater(updater, "get_playerWeaponChange")
        local em = COMPONENTS.call_updater(updater, "get_equipController")
        local mc = COMPONENTS.call_updater(updater, "get_playerMeshController")
        local pg = COMPONENTS.call_updater(updater, "get_playerGun")
        local pm = COMPONENTS.call_updater(updater, "get_playerMelee")
        local hl = COMPONENTS.call_updater(updater, "get_playerHandLight")

        local rwc, rem, rmc, rpg = "updater", "updater", "updater", "updater"
        if not wc then
            wc, rwc = find_player_component("app.PlayerWeaponChange")
            if not wc then
                wc, rwc = find_player_component("app.PlayerWeaponChangePl2001")
            end
        end
        if not em then
            em, rem = find_player_component("app.EquipController")
        end
        if not mc then
            mc, rmc = find_player_component("app.PlayerMeshController")
        end
        if not pg then
            pg, rpg = find_player_component("app.PlayerGun")
            if not pg then
                pg, rpg = find_player_component("app.PlayerGunPl2001")
            end
        end
        if not pm then
            pm = select(1, find_player_component("app.PlayerMelee"))
        end
        if not hl then
            hl = select(1, find_player_component("app.PlayerHandLight"))
        end

        COMPONENTS.weapon_change = wc
        COMPONENTS.equip_manager = em
        COMPONENTS.mesh_controller = mc
        COMPONENTS.player_gun = pg
        COMPONENTS.player_melee = pm
        COMPONENTS.hand_light = hl
        COMPONENTS.resolve_wc = rwc
        COMPONENTS.resolve_em = rem
        COMPONENTS.resolve_mc = rmc
        COMPONENTS.resolve_pg = rpg
    end)
    if not ok_scan then
        return COMPONENTS.weapon_change ~= nil
    end

    if not COMPONENTS.weapon_change then
        local miss_t = COMPONENTS.last_missing_log or 0
        if (now - miss_t) >= 5.0 then
            COMPONENTS.last_missing_log = now
        end
    end

    return COMPONENTS.weapon_change ~= nil
end

--- Authoritative equipped weapon: native D-pad can desync re8vr.weapon from EquipController.
local function get_active_weapon_object()
    refresh_components(false)
    local equip_manager = COMPONENTS.equip_manager
    if equip_manager then
        local em_w = safe_call(equip_manager, "get_equipWeaponRight")
        if em_w and managed_object_alive(em_w) and weapon_component_usable(em_w) then
            return em_w, "equip_manager"
        end
    end
    if re8vr.weapon and weapon_component_usable(re8vr.weapon) then
        return re8vr.weapon, "re8vr"
    end
    local player_gun = COMPONENTS.player_gun
    if not player_gun then
        player_gun = select(1, find_player_component("app.PlayerGun"))
            or select(1, find_player_component("app.PlayerGunPl2001"))
        COMPONENTS.player_gun = player_gun
    end
    if player_gun then
        local eq = safe_call(player_gun, "get_equipWeaponObject")
        if eq and managed_object_alive(eq) and weapon_component_usable(eq) then
            return eq, "player_gun"
        end
        local weapon_gun = safe_call(player_gun, "get_weaponGun")
        if weapon_gun then
            local owner = safe_call(weapon_gun, "get_owner")
            if not owner then
                pcall(function() owner = weapon_gun:get_field("<owner>k__BackingField") end)
            end
            if owner and managed_object_alive(owner) then
                return owner, "player_gun"
            end
        end
    end
    return nil, "none"
end

local function is_bare_hands()
    if not re8vr or not re8vr.can_use_hands then return true end
    if re8vr.player and not managed_object_alive(re8vr.player) then return true end
    -- After from-bare utility D-pad, EM can still report Hand/none while the
    -- saw is equipped. Treat a live equipped utility as armed so AnalogL ADS
    -- is not stripped as bare-hands aim.
    if re8vr.weapon then
        local eq = false
        pcall(function() eq = re8vr.weapon:call("get_isEquip") == true end)
        if eq then return false end
    end
    -- Avoid throwing from UpdateHID: use cached EquipController; soft-refresh only if missing.
    if not COMPONENTS.equip_manager then
        pcall(function() refresh_components(false) end)
    end
    local equip_manager = COMPONENTS.equip_manager
    if equip_manager then
        local ok, none = pcall(function() return equip_manager:call("get_isNoneEquiped") end)
        if ok and none == true then return true end
        local em_w = safe_call(equip_manager, "get_equipWeaponRight")
        if em_w then return false end
    end
    local ok_w, has_w = pcall(function() return get_active_weapon_object() ~= nil end)
    if ok_w and has_w then return false end
    return re8vr.weapon == nil
end

local function resolve_item_internal(entry)
    if not entry then return nil end
    local ok, td = pcall(function() return entry:get_type_definition() end)
    if ok and td then
        local ok2, is_item = pcall(function() return td:is_a("app.ItemCore") end)
        if ok2 and is_item then return entry end
    end
    for _, field in ipairs({ "Item", "<Item>k__BackingField", "<item>k__BackingField", "_Item", "_item" }) do
        local ok3, item = pcall(function() return entry:get_field(field) end)
        if ok3 and item then return item end
    end
    return entry
end

local function get_item_data_id(item_internal)
    if not item_internal then return nil end
    local n = safe_call(item_internal, "get_weaponName")
    if type(n) == "string" and n ~= "" then return normalize_item_id(n) end
    local owner = safe_call(item_internal, "get_owner")
    if not owner then
        pcall(function() owner = item_internal:get_field("<owner>k__BackingField") end)
    end
    if owner then
        local gn = safe_call(owner, "get_Name")
        if type(gn) == "string" and gn ~= "" then return normalize_item_id(gn) end
    end
    local work = nil
    pcall(function() work = item_internal:call("get_work") end)
    if work then
        local id = nil
        pcall(function() id = work:get_field("ItemID") end)
        if id ~= nil then return normalize_item_id(tostring(id)) end
    end
    return nil
end

local function get_item_weapon(item_internal)
    if not item_internal then return nil end
    local ok, td = pcall(function() return item_internal:get_type_definition() end)
    if ok and td then
        local ok_w, is_w = pcall(function() return td:is_a("app.WeaponCore") end)
        if ok_w and is_w then return item_internal end
        local ok_m, is_m = pcall(function() return td:is_a("app.ItemCore") end)
        if ok_m and is_m then return item_internal end
    end
    local w = safe_call(item_internal, "get_weapon")
    if w then return w end
    return item_internal
end

-- Short TTL cache: resolve/get_weapon_item_id can scan inventory many times per frame
-- while armed. Same-frame reuse is behavior-safe for ID lookups.
local INV_ROWS_CACHE = { t = 0, rows = nil }
local INV_ROWS_TTL = 0.25

local function inventory_rows()
    local now = os.clock()
    if INV_ROWS_CACHE.rows and (now - (INV_ROWS_CACHE.t or 0)) < INV_ROWS_TTL then
        return INV_ROWS_CACHE.rows
    end
    local out = {}
    local inv = re8vr.inventory
    if not inv or not managed_object_alive(inv) then
        local im = sdk.get_managed_singleton("app.InventoryManager")
        if im then
            pcall(function() inv = im:call("get_activeInventory") end)
        end
    end
    if not inv or not managed_object_alive(inv) then
        return out
    end
    local items_list = nil
    pcall(function() items_list = inv:call("get_items") end)
    if not items_list then
        pcall(function() items_list = inv:get_field("<items>k__BackingField") end)
    end
    if not items_list then
        return out
    end
    local items = nil
    pcall(function() items = items_list:get_field("mItems") end)
    if not items then
        pcall(function() items = items_list:get_field("_items") end)
    end
    -- Prefer List.Count (live items). mItems Length is capacity (often 128).
    local size = 0
    local list_indexed = false
    pcall(function() size = items_list:call("get_Count") end)
    if type(size) == "number" and size > 0 then
        list_indexed = true
    elseif items then
        size = 0
        pcall(function() size = items:get_size() end)
        if not size or size <= 0 then
            pcall(function() size = items:size() end)
        end
    end
    if not size or size <= 0 then return out end
    for i = 0, size - 1 do
        local entry = nil
        if list_indexed then
            pcall(function() entry = items_list:call("get_Item", i) end)
        else
            pcall(function() entry = items:get_element(i) end)
        end
        if entry then
            local item_internal = resolve_item_internal(entry)
            local item_id = get_item_data_id(item_internal)
            local weapon = get_item_weapon(item_internal)
            if item_internal and item_id then
                local wtype = classify_item_core(item_internal)
                if not wtype then wtype = classify_item_core(weapon) end
                if wtype then WEAPON_TYPE_BY_ID[item_id] = wtype end
                out[#out + 1] = {
                    entry = entry,
                    item_internal = item_internal,
                    item_id = item_id,
                    weapon = weapon,
                }
            end
        end
    end
    INV_ROWS_CACHE.t = now
    INV_ROWS_CACHE.rows = out
    rawset(_G, "__re8_holster_weapon_type", WEAPON_TYPE_BY_ID)
    return out
end

-- Short TTL cache: resolve/get_weapon_item_id can scan inventory many times per frame
-- while armed. Same-frame reuse is behavior-safe for ID lookups.

local function find_row_for_item_id(item_id)
    item_id = normalize_item_id(item_id)
    if not item_id then return nil end
    local rows = inventory_rows()
    for _, row in ipairs(rows) do
        if normalize_item_id(row.item_id) == item_id then return row end
    end
    -- Resolve by weapon GameObject name when weaponName / owner GO still miss.
    for _, row in ipairs(rows) do
        local w = row.weapon
        if w and weapon_component_usable(w) then
            local go_name = nil
            pcall(function()
                local go = w:call("get_GameObject")
                if go then go_name = go:call("get_Name") end
            end)
            if go_name and type(go_name) == "string" then
                if go_name == item_id or normalize_item_id(go_name) == item_id then
                    return row
                end
            end
        end
    end
    return nil
end

local resolve_equipped_item_id

local function item_id_allowed_for_holster_slot(item_id, slot)
    if not item_type_fits_holster_slot(item_id, slot) then return false end
    return find_row_for_item_id(item_id) ~= nil
end

local function get_weapon_item_id(weapon)
    if not weapon then return nil end
    for _, row in ipairs(inventory_rows()) do
        if row.weapon == weapon then return normalize_item_id(row.item_id) end
    end
    local go = safe_call(weapon, "get_GameObject")
    if not go then go = safe_call(weapon, "get_owner") end
    if not go then
        pcall(function() go = weapon:get_field("<owner>k__BackingField") end)
    end
    if go then
        local name = safe_call(go, "get_Name")
        if type(name) == "string" and name ~= "" then
            local mapped = normalize_item_id(name)
            if mapped and find_row_for_item_id(mapped) then return mapped end
            local row = find_row_for_item_id(name)
            if row then return normalize_item_id(row.item_id) end
        end
    end
    return nil
end

local function is_holster_excluded_weapon(weapon, item_id)
    item_id = normalize_item_id(item_id)
    if (not item_id) and weapon then
        item_id = get_weapon_item_id(weapon)
    end
    if item_id then
        if HOLSTER_EXCLUDED_IDS[item_id] then return true end
        local lower = item_id:lower()
        if lower:find("timebomb", 1, true)
            or lower:find("liquidbomb", 1, true)
            or lower:find("grenadebomb", 1, true)
            or lower:find("stangrenade", 1, true)
            or lower:find("thermatebomb", 1, true)
            or lower:find("circularsaw", 1, true)
            or lower:find("chainsaw", 1, true) then
            return true
        end
    end
    if weapon then
        local ok, td = pcall(function() return weapon:get_type_definition() end)
        if ok and td then
            local ok_t, is_t = pcall(function() return td:is_a("app.WeaponThrowableCore") end)
            if ok_t and is_t then return true end
        end
        if weapon_component_usable(weapon) then
            local has_append = false
            pcall(function()
                local go = weapon:call("get_GameObject")
                if not go then return end
                for _, tn in ipairs({
                    "app.WeaponTimebombAppend",
                    "app.WeaponCandleAppend",
                }) do
                    local atd = sdk.typeof(tn)
                    if atd then
                        local c = go:call("getComponent(System.Type)", atd)
                        if c then
                            has_append = true
                            return
                        end
                    end
                end
            end)
            if has_append then return true end
        end
        local em = COMPONENTS.equip_manager
        if em then
            local em_w = safe_call(em, "get_equipWeaponRight")
            if em_w == weapon then
                local ok_o, others = pcall(function() return em:call("get_isOthersEquipped") end)
                if ok_o and others == true and not holster_slot_for_item_id(item_id) then
                    return true
                end
            end
        end
    end
    return false
end

local function get_current_weapon_item_id()
    return resolve_equipped_item_id(get_active_weapon_object())
end

local function get_holster_slot_for_active_weapon()
    local weapon = get_active_weapon_object()
    if not weapon then return nil end
    local cur_id = resolve_equipped_item_id(weapon)
    return holster_slot_for_item_id(cur_id) or fallback_slot_from_weapon_type(weapon)
end

local function current_weapon_matches_holster_slot(slot)
    local weapon = get_active_weapon_object()
    if not weapon or not slot then return false end
    local cur_id = resolve_equipped_item_id(weapon)
    if cur_id and weapon_id_matches_holster_slot(cur_id, slot) then return true end
    return fallback_slot_from_weapon_type(weapon) == slot
end

local function active_weapon_for_slot_fallback()
    return get_active_weapon_object() or re8vr.weapon
end

--- Holster slot for the currently equipped weapon.
local function get_effective_holster_slot_for_cur_weapon()
    if is_bare_hands() then return nil end
        local cur_id = get_current_weapon_item_id()
    if not cur_id then return nil end
    return holster_slot_for_item_id(cur_id) or fallback_slot_from_weapon_type(active_weapon_for_slot_fallback())
end

--- Draw from bare hands, cross-slot holster swap, or non-holster item (burner) in hand.
local function can_holster_interact_draw(target_slot)
    if is_bare_hands() then return true end
    local cur_slot = get_effective_holster_slot_for_cur_weapon()
    if not cur_slot then return true end
    return cur_slot ~= target_slot
end

local function medicine_blocked_by_lh_weapon_support()
    if rawget(_G, "__re8_lh_weapon_support") == true then
        return true
    end
    local r = rawget(_G, "re8vr")
    if r ~= nil and r.was_gripping_weapon == true then
        return true
    end
    return false
end

--- Match pick_closest_holster_zone intent: cross-draw when armed in another slot, else stow/reassign.
--- Lua medicine hold is a virtual "medicine" slot so 8.15 cross-draw/stow rules apply.
local function resolve_grip_holster_action(closest, cur_id)
    if not closest then return nil end
    local cur_slot = holster_slot_for_item_id(cur_id)
        or fallback_slot_from_weapon_type(active_weapon_for_slot_fallback())
    if rawget(_G, "__re8_medicine_in_hand") == true then
        cur_slot = "medicine"
    end

    if is_bare_hands() and cur_slot ~= "medicine" then
        if closest.can_draw and can_holster_interact_draw(closest.slot) then return "draw" end
        return nil
    end

    if cur_id and is_holster_excluded_weapon(nil, cur_id) then
        if closest.can_draw and can_holster_interact_draw(closest.slot) then return "draw" end
        return nil
    end

    if cur_id and not cur_slot then
        if closest.can_stow then return "stow" end
        if closest.can_draw and can_holster_interact_draw(closest.slot) then return "draw" end
        return nil
    end

    if closest.can_draw and cur_slot and closest.slot ~= cur_slot
        and can_holster_interact_draw(closest.slot) then
        return "draw"
    end

    if closest.can_stow then return "stow" end

    if closest.can_draw and can_holster_interact_draw(closest.slot) then return "draw" end
    return nil
end

local function profile_has_stowed_for_slot(P, slot)
    local cfg = HOLSTER_SLOTS[slot]
    if not cfg then
    if slot == "chest" then return type(P.last_chest_id) == "string" and P.last_chest_id ~= "" end
    return false
    end
    local v = P[cfg.profile_key]
    return type(v) == "string" and v ~= ""
end

local function resolve_profile_item_id(P, slot)
    local cfg = HOLSTER_SLOTS[slot]
    if not cfg then
    if slot == "chest" then return normalize_item_id(P.last_chest_id) end
    return nil
    end
    return normalize_item_id(P[cfg.profile_key])
end

local function set_profile_slot_item(P, slot, item_id)
    local cfg = HOLSTER_SLOTS[slot]
    if not cfg then
        if slot == "chest" then P.last_chest_id = item_id or "" end
        return
    end
    P[cfg.profile_key] = item_id or ""
end

local function clear_item_from_other_slots(P, keep_slot, item_id)
    if not item_id then return end
    for slot_name, _ in pairs(HOLSTER_SLOTS) do
        if slot_name ~= keep_slot and normalize_item_id(P[HOLSTER_SLOTS[slot_name].profile_key]) == item_id then
            P[HOLSTER_SLOTS[slot_name].profile_key] = ""
        end
    end
    if keep_slot ~= "chest" and normalize_item_id(P.last_chest_id) == item_id then
        P.last_chest_id = ""
    end
end

local function cache_weapon_to_profile(P, item_id, preferred_slot)
    item_id = normalize_item_id(item_id)
    if not item_id then return end
    local slot = preferred_slot
    local home = holster_slot_for_item_id(item_id) or fallback_slot_from_weapon_type(re8vr.weapon)
    if home and slot and home ~= slot then
        slot = home
    elseif not slot then
        slot = home
    end
    if not slot or not item_id_allowed_for_holster_slot(item_id, slot) then return end
    local prev_p, prev_l, prev_c, prev_k = P.last_pistol_id, P.last_longarm_id, P.last_chest_id, P.last_knife_id
    local prev_m = P.last_medicine_id
    local prev_u = P.last_utility_id
    set_profile_slot_item(P, slot, item_id)
    clear_item_from_other_slots(P, slot, item_id)
    if P.last_pistol_id == prev_p and P.last_longarm_id == prev_l
        and P.last_chest_id == prev_c and P.last_knife_id == prev_k
        and P.last_medicine_id == prev_m
        and P.last_utility_id == prev_u then
        return
    end
end

local function reconcile_holster_slot_cache(P, slot)
    if slot == "chest" or slot == "utility" or profile_has_stowed_for_slot(P, slot) then return end
    for _, row in ipairs(inventory_rows()) do
        local row_id = normalize_item_id(row.item_id)
        if row_id and item_id_allowed_for_holster_slot(row_id, slot) then
            set_profile_slot_item(P, slot, row_id)
            return
        end
    end
end

local function slot_has_draw_candidate(P, slot)
    if slot == "chest" or slot == "utility" then return false end
    local item_id = resolve_profile_item_id(P, slot)
    if not item_id then
    reconcile_holster_slot_cache(P, slot)
        item_id = resolve_profile_item_id(P, slot)
    end
    if not item_id or not item_id_allowed_for_holster_slot(item_id, slot) then
        return false
    end
    -- Medicine: profile id alone is not enough — require a live inventory row
    -- so empty holsters stop zone rumble after the bottle is consumed.
    if slot == "medicine" then
        if find_row_for_item_id(item_id) ~= nil then return true end
        for _, row in ipairs(inventory_rows()) do
            if is_medicine_core(row.item_internal) or is_medicine_item_id(row.item_id) then
                return true
            end
        end
        return false
    end
    return true
end

local STOW = {
    lockout_until = 0,
    reassert_count = 0,
    native_suppress_until = 0,
    holster_unequip_id = "",
}
-- Reference fields: write via REFramework __newindex (handles old/new refcount).
-- Prefer typed setters for managed reference fields.
STOW.ref_fail = {}
STOW.set_ref_field = function(obj, name, value)
    if not obj then return false end
    local ok = pcall(function() obj[name] = value end)
    if not ok then
        -- __newindex unavailable: fall back to old raw write (baseline behavior).
        pcall(function() obj:set_field(name, value) end)
        if not STOW.ref_fail[name] then
            STOW.ref_fail[name] = true
            pcall(function() log.info("[re8_vr_holster] set_ref_field fallback (raw): " .. tostring(name)) end)
        end
    end
    return ok
end
STOW._equip_weapon_core_m = nil
STOW.call_equip_weapon = function(em, weapon)
    if not em or not weapon then return false end
    if not managed_object_alive(em) or not managed_object_alive(weapon) then return false end
    if not STOW._equip_weapon_core_m then
        local t = sdk.find_type_definition("app.EquipController")
        if t then
            STOW._equip_weapon_core_m = t:get_method("equipWeapon(app.WeaponCore)")
        end
    end
    local m = STOW._equip_weapon_core_m
    if not m then return false end
    local ok, err = pcall(function() m:call(em, weapon) end)
    return ok == true
end
STOW._notify_weapon_info_m = nil
STOW.notify_weapon_info = function(pg)
    if not pg then return false end
    if not STOW._notify_weapon_info_m then
        local t = sdk.find_type_definition("app.PlayerComponent")
        if t then
            STOW._notify_weapon_info_m = t:get_method("notifyWeaponInfoDisp(System.Boolean, System.Boolean)")
        end
    end
    local m = STOW._notify_weapon_info_m
    if not m then return false end
    local ok, err = pcall(function() m:call(pg, true, true) end)
    return ok == true
end
STOW.set_requested_item = function(wc, item)
    if not wc then return false end
    local ok, err = pcall(function() wc:call("set_RequestedItem", item) end)
    return ok == true
end
STOW.clear_unshootable = function(pg)
    if not pg then return end
    local ok_set = pcall(function() pg:call("set_isUnshootable", false) end)
    pcall(function() pg:set_field("IsUnshootableChecked", false) end)
    local after = nil
    pcall(function() after = pg:call("get_isUnshootable") end)
end
-- Set by killswitch while dead / game over. No flag = no-op.
STOW.player_dead = function()
    return rawget(_G, "__re8_player_dead") == true
end
local HOLSTER_CALIB = {
    target = nil,
    drag_active = false,
    drag_waiting = false,
    drag_updates = 0,
    drag_last_log_t = 0,
    drag_deadline = 0,
    hold_t0 = 0,
    hold_last_beep = -1,
    hold_target = nil,
    hold_cooldown_until = 0,
    hold_miss = 0,
    diag_last_t = 0,
    last_block = "",
}
-- After WeaponID.Hand stow, D-pad UI updates selection but EquipWeaponIdRight stays Hand.
-- Watch ItemSlotManager select index / QuickEquipMenu slot instead.
local NATIVE_WEAPON_SEL = {
    last_select_slot = nil,
    last_quick_slot = nil,
    last_apply_t = 0,
    last_applied_item = "",
    cleared_melee_dpad = "",
    allow_one_apply_quickslot = false,
    pending_gun_combat_fixup = false,
    gun_fixup_until = 0,
    equip_status_enum = nil,
    weapon_cat_enum = nil,
    override_slot = -1,
    equip_in_progress = false,
    equip_cooldown_until = 0,
    session_qs_repair = false,
    sess_pl = 0,
    sess_inv = 0,
    sess_dead_pl = 0,
    sess_dead_inv = 0,
    pending_bare_qs = nil,
    excluded_equip_in_progress = false,
    pending_excluded_inv_id = "",
    native_dpad_until = 0,
    wc_since = 0,
    wc_unstick_done = false,
    wc_unstick_stage = 0,
    motion0 = "",
    motion0_left = false,
    left_loop_since = 0,
    req_mismatch_id = "",
    req_mismatch_since = 0,
    req_finish_done_t = 0,
}

-- Holster draw activates weapon GO/mesh; native D-pad swaps bypass our equip chain.
local WEAPON_WATCH = {
    last_ptr = nil,
    last_id = "",
    our_equip_until = 0,
    dpad_target_id = "",
    dpad_old_ptr = nil,
    dpad_old_id = "",
    dpad_cleanup_until = 0,
    dpad_finalize_done = false,
    stow_lockout_weapon_id = "",
    stow_flash_weapon = nil,
    stow_flash_until = 0,
    draw_flash_weapon = nil,
    draw_flash_until = 0,
    orphan_hide_weapon = nil,
    orphan_hide_until = 0,
    re8vr_ptr_last_log_t = 0,
    validate_last_t = 0,
}

-- Re-assert holster weapon if native D-pad selection snaps back after draw.
local HOLSTER_GUARD = {
    item_id = "",
    dpad_was_active = false,
    watch_last_log_t = 0,
    watch_drift_count = 0,
    reassert_last_t = 0,
    reassert_in_progress = false,
    draw_native_suppress_until = 0,
    block_hold_until = 0,
    mesh_repair_weapon = nil,
    mesh_repair_until = 0,
    mesh_repair_last_t = 0,
    mesh_repair_started_at = 0,
    armed_at = 0,
}

local GRIP = {
    aim_prev = false,
    holster_was_grip = false,
    holster_prev = false,
    holster_ever_outside = false,
    holster_zone_prev = false,
    suppress_haptics_for_aim = false,
    menu_gui_time = 0.0,
    scene_block_until = 0.0,
    cine_since = 0.0,
}

-- Forward declare: used by cross-swap cleanup before definition below.
local hide_weapon_visuals

-- Cross-slot draw: stow clears active pointer but PlayerGun still owns previous weapon.
local CROSS_SWAP = {
    prev_weapon = nil,
    prev_id = "",
}

local function capture_cross_swap_prev(weapon, item_id)
    if weapon and managed_object_alive(weapon) then
        CROSS_SWAP.prev_weapon = weapon
        CROSS_SWAP.prev_id = normalize_item_id(item_id or get_weapon_item_id(weapon) or "")
    end
end

local function peek_cross_swap_prev()
    return CROSS_SWAP.prev_weapon, CROSS_SWAP.prev_id
end

local function clear_cross_swap_prev()
    CROSS_SWAP.prev_weapon = nil
    CROSS_SWAP.prev_id = ""
end

local function finalize_cross_swap_visuals(keep_weapon)
    local prev = CROSS_SWAP.prev_weapon
    if prev and prev ~= keep_weapon and managed_object_alive(prev) then
        hide_weapon_visuals(prev)
    end
end

local function clear_equip_weapon_timer()
    local wc = COMPONENTS.weapon_change
    if not wc then return end
    pcall(function()
        local timer = wc:get_field("EquipWeaponElapsedTimer")
        if timer then timer:call("clear") end
    end)
end

local function get_right_hand_enum()
    if HandEnum and HandEnum.Right ~= nil then return HandEnum.Right end
    return 0
end

local function read_player_gun_weapon_item_id(player_gun)
    if not player_gun then return nil end
    local eq = safe_call(player_gun, "get_equipWeaponObject")
    if eq then
        local id = get_weapon_item_id(eq)
        if id then return id end
    end
    local weapon_gun = safe_call(player_gun, "get_weaponGun")
    if weapon_gun then
        local owner = safe_call(weapon_gun, "get_owner")
        if owner then return get_weapon_item_id(owner) end
        pcall(function() owner = weapon_gun:get_field("<owner>k__BackingField") end)
        if owner then return get_weapon_item_id(owner) end
    end
    return nil
end

resolve_equipped_item_id = function(weapon)
    weapon = weapon or get_active_weapon_object() or re8vr.weapon
    refresh_components(false)
    local pg_id = read_player_gun_weapon_item_id(COMPONENTS.player_gun)
    if pg_id then
        pg_id = normalize_item_id(pg_id)
        local pg_row = find_row_for_item_id(pg_id)
        if pg_row then
            return normalize_item_id(pg_row.item_id)
        end
    end
    if weapon then
        for _, row in ipairs(inventory_rows()) do
            if row.weapon == weapon then
                return normalize_item_id(row.item_id)
            end
        end
        local guess = get_weapon_item_id(weapon)
        if guess then return guess end
    end
    return nil
end

rawset(_G, "__re8_resolve_equipped_item_id", resolve_equipped_item_id)

--- Sync PlayerGun shoot/reload/SFX layer (mesh/UI alone leaves stale WeaponGun).
local function sync_player_gun_combat(new_weapon, prev_weapon, source_tag)
    refresh_components(false)
    local player_gun = COMPONENTS.player_gun
    if not player_gun or not managed_object_alive(player_gun) then return false end
    if new_weapon and not managed_object_alive(new_weapon) then return false end
    if prev_weapon and not managed_object_alive(prev_weapon) then prev_weapon = nil end
    local new_id = new_weapon and get_weapon_item_id(new_weapon) or nil
    if is_holster_excluded_weapon(new_weapon, new_id) then return false end
    if new_id and weapon_type_for_item_id(new_id) == "MED" then
        return false
    end
    local chris_knife = STOW.is_chris_player() == true
        and new_weapon ~= nil
        and weapon_type_for_item_id(new_id) == "KNF"
    local before_id = read_player_gun_weapon_item_id(player_gun)
    pcall(function() player_gun:call("onEquipWeaponChanged", new_weapon, prev_weapon) end)
    if new_weapon then
        pcall(function()
            local item = nil
            for _, row in ipairs(inventory_rows()) do
                if row.weapon == new_weapon then
                    item = row.item_internal
                    break
                end
            end
            local em = COMPONENTS.equip_manager
            if em then
                pcall(function() em:set_field("EquipWeaponIdRight", new_weapon:call("get_weaponID")) end)
                pcall(function() em:call("set_isNoneEquipped", false) end)
            end
            local wc = COMPONENTS.weapon_change
            if wc then
                STOW.set_requested_item(wc, item)
            end
            if not NATIVE_WEAPON_SEL.weapon_cat_enum then
                NATIVE_WEAPON_SEL.weapon_cat_enum = statics.generate("app.WeaponCategory")
            end
            local cat = NATIVE_WEAPON_SEL.weapon_cat_enum
            if chris_knife then
                local melee_cat = 1
                if cat then
                    melee_cat = cat.Melee or cat.Knife or cat.MeleeWeapon or 1
                end
                pcall(function() new_weapon:set_field("WeaponCategory", melee_cat) end)
            elseif cat and cat.Gun ~= nil then
                pcall(function() new_weapon:set_field("WeaponCategory", cat.Gun) end)
            end
        end)
        pcall(function() player_gun:call("updateWeaponInfo") end)
        pcall(function() player_gun:call("setupGunActiveData") end)
        pcall(function() player_gun:call("setupGunFireData") end)
        STOW.notify_weapon_info(player_gun)
            if not chris_knife then
                pcall(function() player_gun:call("goActiveTriggerState") end)
            end
        STOW.clear_unshootable(player_gun)
    else
        pcall(function() player_gun:call("goIdleTriggerState") end)
    end
    local after_id = read_player_gun_weapon_item_id(player_gun)
    local expected_id = new_weapon and get_weapon_item_id(new_weapon) or nil
    local synced = true
    if expected_id then
        synced = after_id ~= nil
            and normalize_item_id(after_id) == normalize_item_id(expected_id)
    elseif new_weapon == nil then
        synced = after_id == nil or after_id == ""
    end
    return synced
end

--- Hip stow leaves PlayerGun owning the old weapon; must hard-clear before a different holster draw.
local function force_clear_player_gun_combat(prev_weapon, source_tag)
    refresh_components(false)
    local player_gun = COMPONENTS.player_gun
    if not player_gun then return false end
    local before_id = read_player_gun_weapon_item_id(player_gun)
    pcall(function() player_gun:call("onEquipWeaponChanged", nil, prev_weapon) end)
    pcall(function() player_gun:call("updateWeaponInfo") end)
    local after_id = read_player_gun_weapon_item_id(player_gun)
    local cleared = after_id == nil or after_id == ""
    return cleared
end

--- Native bare-hands via WeaponID.Hand.
--- CRITICAL order (runtime): after draw→restow, hide mesh BEFORE Hand equip.
--- Hand equip first remaps PlayerMeshController away from the gun mesh, leaving a visible orphan.
local function native_equip_bare_hands_id(prev_weapon)
    if STOW.player_dead() then return false end
    refresh_components(false)
    local equip_manager = COMPONENTS.equip_manager
    local weapon_change = COMPONENTS.weapon_change
    local mesh_controller = COMPONENTS.mesh_controller
    if not equip_manager and not weapon_change then return false end

    clear_equip_weapon_timer()

    local mesh_hidden = false
    local weapon_disp_off = false
    local mesh_active_before = nil
    local mesh_active_after = nil

    -- 1) Visual hide while mesh controller still points at the gun (matches C++ stow order).
    if prev_weapon then
        hide_weapon_visuals(prev_weapon)
    end
    if mesh_controller then
        if prev_weapon then
            pcall(function() mesh_controller:call("onEquipWeaponChanged", nil, prev_weapon) end)
        end
        pcall(function()
            local mesh_go = mesh_controller:call("get_weaponMeshObject")
            if mesh_go then
                pcall(function() mesh_active_before = mesh_go:call("get_Active") end)
                mesh_go:call("setActive", false)
                mesh_hidden = true
                pcall(function() mesh_active_after = mesh_go:call("get_Active") end)
            end
        end)
    end

    if weapon_change then
        pcall(function() weapon_change:call("setWeaponDisp", false) end)
    end

    if prev_weapon then
        pcall(function()
            prev_weapon:call("disp", false)
            weapon_disp_off = true
        end)
        -- Also deactivate weapon GameObject mesh attachments left on after holster draw.
        pcall(function()
            local wgo = prev_weapon:call("get_GameObject")
            if wgo then wgo:call("setActive", false) end
        end)
        sync_player_gun_combat(nil, prev_weapon, "stow_bare_hands")
    end

    if equip_manager then
        pcall(function()
            local cur = equip_manager:get_field("<equipWeaponRight>k__BackingField")
            if cur ~= nil and (prev_weapon == nil or cur == prev_weapon) then
                equip_manager:call("set_equipWeaponRight", nil)
            end
        end)
    end

    -- Inventory + native bare (clearEquip / removeWeaponWithNoAction).
    if re8vr.inventory then
        pcall(function() re8vr.inventory:call("removeEquip") end)
    end

    local equip_ok = false
    if weapon_change then
        pcall(function() weapon_change:call("removeWeaponWithNoAction") end)
        pcall(function() weapon_change:call("removeWeapon", false) end)
        equip_ok = true
    end
    if equip_manager then
        pcall(function() equip_manager:call("clearEquip") end)
        pcall(function() equip_manager:call("set_equipWeaponRight", nil) end)
        equip_ok = true
    end

    -- Re-assert mesh hide after bare switch (some draws recreate mesh refs).
    if mesh_controller then
        pcall(function()
            local mesh_go = mesh_controller:call("get_weaponMeshObject")
            if mesh_go then mesh_go:call("setActive", false) end
        end)
    end
    if prev_weapon then
        pcall(function() prev_weapon:call("disp", false) end)
    end
    if weapon_change then
        pcall(function() weapon_change:call("setWeaponDisp", false) end)
    end


    if re8vr then re8vr.weapon = nil end
    force_clear_player_gun_combat(prev_weapon, "stow_bare_hands_finalize")
    return equip_ok
end

STOW.arm_flash = function(weapon)
    if weapon and managed_object_alive(weapon) then
        WEAPON_WATCH.stow_flash_weapon = weapon
        WEAPON_WATCH.stow_flash_until = os.clock() + 0.4
    end
end

--- Hide orphan weapon GO only — never touch PlayerMeshController (avoids hand-over-weapon blend).
STOW.hide_orphan_visual = function(weapon)
    if not weapon or not managed_object_alive(weapon) then return end
    pcall(function()
        if not managed_object_alive(weapon) then return end
        weapon:call("disp", false)
    end)
    pcall(function()
        if not managed_object_alive(weapon) then return end
        local go = weapon:call("get_GameObject")
        if go then go:call("setActive", false) end
    end)
end

-- Native D-pad can leave the previous holster gun bound on RH via PMC/PlayerGun
-- even after the GO is deactivated. Detach without setWeaponDisp(false) (that
-- would blank the newly equipped weapon too).
-- Prefer onEquipWeaponChanged(cur, orphan) so PMC keeps the new gun bound;
-- (nil, orphan) can briefly bare the hand and let the orphan remount.
STOW.detach_orphan_from_hand = function(weapon)
    if not weapon or not managed_object_alive(weapon) then return false end
    STOW.hide_orphan_visual(weapon)
    refresh_components(false)
    local cur = get_active_weapon_object() or (re8vr and re8vr.weapon)
    if cur and cur == weapon then
        cur = nil
    end
    if cur and not managed_object_alive(cur) then
        cur = nil
    end
    local mc = COMPONENTS.mesh_controller
    local pg = COMPONENTS.player_gun
    local pm = COMPONENTS.player_melee
    if mc then
        if cur then
            pcall(function() mc:call("onEquipWeaponChanged", cur, weapon) end)
        else
            pcall(function() mc:call("onEquipWeaponChanged", nil, weapon) end)
        end
        pcall(function()
            local mesh_go = mc:call("get_weaponMeshObject")
            -- Only deactivate if it still belongs to the orphan weapon.
            if mesh_go and managed_object_alive(mesh_go) then
                local wgo = nil
                pcall(function() wgo = weapon:call("get_GameObject") or weapon:call("get_owner") end)
                if wgo and mesh_go == wgo then
                    mesh_go:call("setActive", false)
                end
            end
        end)
        if cur then
            pcall(function() mc:call("updateParts") end)
        end
    end
    if pg then
        if cur then
            pcall(function() pg:call("onEquipWeaponChanged", cur, weapon) end)
        else
            pcall(function() pg:call("onEquipWeaponChanged", nil, weapon) end)
        end
    end
    if pm then
        if cur then
            pcall(function() pm:call("onEquipWeaponChanged", cur, weapon) end)
        else
            pcall(function() pm:call("onEquipWeaponChanged", nil, weapon) end)
        end
    end
    return true
end

STOW.arm_orphan_hide = function(weapon)
    if not weapon or not managed_object_alive(weapon) then return end
    WEAPON_WATCH.orphan_hide_weapon = weapon
    WEAPON_WATCH.orphan_hide_until = os.clock() + 1.8
    STOW.detach_orphan_from_hand(weapon)
end

-- Capture outgoing gun for native D-pad / WC swaps so swap_fixup can detach it.
STOW.arm_dpad_orphan = function(old_weapon, old_id, target_id, reason)
    if target_id and target_id ~= "" then
        WEAPON_WATCH.dpad_target_id = normalize_item_id(target_id) or ""
    end
    if old_weapon and managed_object_alive(old_weapon) then
        local already = WEAPON_WATCH.dpad_old_ptr == old_weapon
            and os.clock() < (WEAPON_WATCH.orphan_hide_until or 0)
        WEAPON_WATCH.dpad_old_ptr = old_weapon
        WEAPON_WATCH.dpad_old_id = tostring(old_id or get_weapon_item_id(old_weapon) or "")
        WEAPON_WATCH.dpad_cleanup_until = os.clock() + 2.0
        if not already then
            WEAPON_WATCH.dpad_finalize_done = false
            STOW.arm_orphan_hide(old_weapon)
        else
            -- Keep the suppress window alive while sticky WC is still requesting.
            WEAPON_WATCH.orphan_hide_until = os.clock() + 1.8
        end
        return true
    end
    return false
end

STOW.tick_orphan_hide = function()
    if os.clock() >= (WEAPON_WATCH.orphan_hide_until or 0) then
        WEAPON_WATCH.orphan_hide_weapon = nil
        return
    end
    local weapon = WEAPON_WATCH.orphan_hide_weapon
    local cur = get_active_weapon_object() or (re8vr and re8vr.weapon)
    if not weapon or not managed_object_alive(weapon) then
        WEAPON_WATCH.orphan_hide_weapon = nil
        return
    end
    -- Never hide the currently equipped weapon.
    if cur and weapon == cur then
        WEAPON_WATCH.orphan_hide_weapon = nil
        return
    end
    STOW.detach_orphan_from_hand(weapon)
end

--- Clear VR hand-through depth flags on a via.render.Mesh (opaque opaque draw).
STOW.clear_mesh_hand_blend = function(mesh)
    if not mesh then return end
    pcall(function() mesh:call("set_Enabled", true) end)
    pcall(function() mesh:call("set_DrawDefault", true) end)
    pcall(function() mesh:call("set_IgnoreDepth", false) end)
    pcall(function() mesh:call("set_IgnoreDepthTransparentCorrection", false) end)
    pcall(function() mesh:call("set_IgnoreDepthStencilValueWrite", false) end)
    pcall(function() mesh:call("set_MaskIgnoreDepthMesh", false) end)
    pcall(function() mesh:call("set_ForceAlphaTest", false) end)
    pcall(function() mesh:call("set_TransparentBias", 0.0) end)
end

STOW._mesh_go_name = function(mesh)
    local n = nil
    pcall(function()
        if not mesh then return end
        local go = mesh:call("get_GameObject")
        if go then n = go:call("get_Name") end
    end)
    return n
end

STOW._is_holster_go_name = function(name)
    return type(name) == "string" and string.find(name, "HolsterMesh", 1, true) ~= nil
end

-- Native equipped Mesh only. Holster clones share the live MeshResource; never
-- treat holster clone meshes as the PlayerMeshController WeaponMesh.
STOW._weapon_native_mesh = function(weapon)
    local wmesh = nil
    pcall(function() wmesh = weapon:get_field("Mesh") end)
    if wmesh and not STOW._is_holster_go_name(STOW._mesh_go_name(wmesh)) then
        return wmesh
    end
    pcall(function()
        local go = weapon:call("get_GameObject")
        if not go then return end
        local t = go:call("get_Transform")
        if not t then return end
        local mesh_td = sdk.typeof("via.render.Mesh")
        if not mesh_td then return end
        local found = t:find(mesh_td)
        if found and not STOW._is_holster_go_name(STOW._mesh_go_name(found)) then
            wmesh = found
        end
    end)
    return wmesh
end

STOW.is_chris_player = function()
    local key = nil
    pcall(function()
        key = vr_char.get_active_profile_key(re8vr and re8vr.player or nil)
    end)
    return key == "chris"
end

STOW.set_mesh_ignore_depth = function(mesh, ignore)
    if not mesh then return end
    pcall(function() mesh:call("set_IgnoreDepth", ignore == true) end)
    pcall(function() mesh:call("set_IgnoreDepthTransparentCorrection", ignore == true) end)
    pcall(function() mesh:call("set_IgnoreDepthStencilValueWrite", false) end)
end

-- Body/holsters: normal depth so the torso occludes parked weapons.
-- Held/equipped meshes use apply_held_weapon_priority (IgnoreDepth on the item only).
STOW.sync_chris_depth = function(_bare)
    if not STOW.is_chris_player() then return false end
    refresh_components(false)
    local mc = COMPONENTS.mesh_controller
    if not mc then return false end
    local ub, lb, rarm, larm = nil, nil, nil, nil
    pcall(function() ub = mc:get_field("UpperBodyMesh") end)
    pcall(function() lb = mc:get_field("LowerBodyMesh") end)
    pcall(function() rarm = mc:get_field("RArmMesh") end)
    pcall(function() larm = mc:get_field("LArmMesh") end)
    STOW.set_mesh_ignore_depth(ub, false)
    STOW.set_mesh_ignore_depth(lb, false)
    STOW.set_mesh_ignore_depth(rarm, false)
    STOW.set_mesh_ignore_depth(larm, false)
    pcall(function() mc:set_field("IgnoreDepth", false) end)
    return true
end

-- Held and holstered items both use real depth: body occludes a gun behind the
-- torso; parked holsters stay consistent. IgnoreDepth on the gun draws it
-- through the body when it is below the chest.
STOW.apply_held_weapon_priority = function(_weapon)
    return false
end

-- Chris grenade/utility/syringe: same depth as longarm guns (item + arms).
-- Item-only IgnoreDepth=false left gloves not writing depth and the grenade
-- showed through the hand. Do not set PMC IgnoreDepth or strip blend flags.
STOW.fix_chris_held_item_opaque = function(weapon)
    if not STOW.is_chris_player() then return false end
    if not weapon or not managed_object_alive(weapon) then return false end
    local now = os.clock()
    if (now - (STOW._chris_held_t or 0)) < 0.20 then
        return true
    end
    STOW._chris_held_t = now
    local wmesh = STOW._weapon_native_mesh(weapon)
    if not wmesh then
        pcall(function() wmesh = weapon:get_field("Mesh") end)
    end
    if wmesh then
        STOW.set_mesh_ignore_depth(wmesh, false)
    end
    refresh_components(false)
    local mc = COMPONENTS.mesh_controller
    if mc then
        pcall(function()
            local pmc = mc:get_field("WeaponMesh")
            if pmc and not STOW._is_holster_go_name(STOW._mesh_go_name(pmc)) then
                STOW.set_mesh_ignore_depth(pmc, false)
            end
        end)
        local ub, lb, rarm, larm = nil, nil, nil, nil
        pcall(function() ub = mc:get_field("UpperBodyMesh") end)
        pcall(function() lb = mc:get_field("LowerBodyMesh") end)
        pcall(function() rarm = mc:get_field("RArmMesh") end)
        pcall(function() larm = mc:get_field("LArmMesh") end)
        STOW.set_mesh_ignore_depth(ub, false)
        STOW.set_mesh_ignore_depth(lb, false)
        STOW.set_mesh_ignore_depth(rarm, false)
        STOW.set_mesh_ignore_depth(larm, false)
    end
    return true
end

-- Chris torso writes depth so parked holsters do not show through the body
-- (bare hands after shoulder stow, and while longarm is out).
STOW.fix_chris_body_occlude_holsters = function()
    if not STOW.is_chris_player() then return false end
    local now = os.clock()
    if (now - (STOW._chris_body_t or 0)) < 0.25 then
        return true
    end
    STOW._chris_body_t = now
    refresh_components(false)
    local mc = COMPONENTS.mesh_controller
    if not mc then return false end
    local ub, lb = nil, nil
    pcall(function() ub = mc:get_field("UpperBodyMesh") end)
    pcall(function() lb = mc:get_field("LowerBodyMesh") end)
    STOW.set_mesh_ignore_depth(ub, false)
    STOW.set_mesh_ignore_depth(lb, false)
    return true
end

-- Chris longarm only: body occludes parked holsters; gun stays opaque vs hands.
-- Do not strip blend flags or PMC IgnoreDepth (that made the shotgun translucent
-- after stow/grab). Hip/knife/Ethan keep the always-on-top holster path.
STOW.fix_chris_longarm_opaque = function(weapon, pub_id)
    if not STOW.is_chris_player() then return false end
    if holster_slot_for_item_id(pub_id) ~= "longarm" then return false end
    if not weapon or not managed_object_alive(weapon) then return false end
    -- Throttle: these mesh flag writes every frame while longarm is out were costly.
    local now = os.clock()
    if (now - (STOW._chris_longarm_t or 0)) < 0.25 then
        return true
    end
    STOW._chris_longarm_t = now
    local wmesh = STOW._weapon_native_mesh(weapon)
    local ig0, ig1 = nil, nil
    if wmesh then
        pcall(function() ig0 = wmesh:call("get_IgnoreDepth") end)
        STOW.set_mesh_ignore_depth(wmesh, false)
        pcall(function() ig1 = wmesh:call("get_IgnoreDepth") end)
    end
    refresh_components(false)
    local mc = COMPONENTS.mesh_controller
    local r_ig, ub_ig = nil, nil
    if mc then
        pcall(function()
            local pmc = mc:get_field("WeaponMesh")
            if pmc and not STOW._is_holster_go_name(STOW._mesh_go_name(pmc)) then
                STOW.set_mesh_ignore_depth(pmc, false)
            end
        end)
        local ub, lb, rarm, larm = nil, nil, nil, nil
        pcall(function() ub = mc:get_field("UpperBodyMesh") end)
        pcall(function() lb = mc:get_field("LowerBodyMesh") end)
        pcall(function() rarm = mc:get_field("RArmMesh") end)
        pcall(function() larm = mc:get_field("LArmMesh") end)
        STOW.set_mesh_ignore_depth(ub, false)
        STOW.set_mesh_ignore_depth(lb, false)
        STOW.set_mesh_ignore_depth(rarm, false)
        STOW.set_mesh_ignore_depth(larm, false)
        pcall(function() if rarm then r_ig = rarm:call("get_IgnoreDepth") end end)
        pcall(function() if ub then ub_ig = ub:call("get_IgnoreDepth") end end)
    end
    return true
end

STOW.reassert_weapon_depth_flags = function(weapon)
    return STOW.apply_held_weapon_priority(weapon)
end

--- Force opaque weapon render after bare-hands holster draw (non-D-pad target).
STOW.finalize_equipped_mesh = function(weapon)
    if not weapon or not managed_object_alive(weapon) then return end
    refresh_components(false)
    local wc = COMPONENTS.weapon_change
    local mc = COMPONENTS.mesh_controller
    if wc then
        pcall(function() wc:call("setWeaponDisp", true) end)
    end
    pcall(function() weapon:call("disp", true) end)
    pcall(function()
        local go = weapon:call("get_GameObject")
        if go then go:call("setActive", true) end
    end)
    if mc then
        pcall(function() mc:call("onEquipWeaponChanged", weapon, nil) end)
        pcall(function()
            local mesh_go = mc:call("get_weaponMeshObject")
            if mesh_go then mesh_go:call("setActive", true) end
        end)
        pcall(function() mc:call("updateParts") end)
        local skip_pmc_ig = STOW.is_chris_player() == true
            and holster_slot_for_item_id(get_weapon_item_id(weapon) or rawget(_G, "__re8_active_weapon_id")) == "longarm"
        if not skip_pmc_ig then
            pcall(function() mc:set_field("IgnoreDepth", false) end)
        end
    end

    -- Equipped mesh: opaque, real depth vs body and holsters.
    local ignore_before, ignore_after = nil, nil
    pcall(function()
        local wmesh = weapon:get_field("Mesh")
        if wmesh then
            pcall(function() ignore_before = wmesh:call("get_IgnoreDepth") end)
        end
    end)
    local reg_nat, reg_pmc, reg_wmo = nil, nil, nil
    -- Same as Ethan: do not registerMesh / rewrite WeaponMesh / strip IgnoreDepth.
    -- Chris hip/knife/D-pad were coupling the holster clone to the equipped pass.
    pcall(function()
        local wmesh = weapon:get_field("Mesh")
        if wmesh then ignore_after = wmesh:call("get_IgnoreDepth") end
    end)
    -- Re-run mesh controller refresh after WeaponMesh rebind.
    if mc then
        pcall(function() mc:call("onEquipWeaponChanged", weapon, nil) end)
        pcall(function() mc:call("updateParts") end)
    end
    local mesh_active = nil
    if mc then
        pcall(function()
            local mesh_go = mc:call("get_weaponMeshObject")
            if mesh_go then mesh_active = mesh_go:call("get_Active") end
        end)
    end
end

--- Post-equip applyQuickSlot raced bare draws and was blocked by holster guard.
STOW.refresh_native_visual_after_bare_draw = function(_weapon)
    return false
end

STOW.arm_draw_flash = function(weapon)
    if weapon and managed_object_alive(weapon) then
        WEAPON_WATCH.draw_flash_weapon = weapon
        WEAPON_WATCH.draw_flash_until = os.clock() + 0.45
    end
end

STOW.prepare_bare_draw = function(target_id)
    if not target_id or target_id == "" then return end
    target_id = normalize_item_id(target_id)
    HOLSTER_GUARD.draw_native_suppress_until = os.clock() + 3.0
    WEAPON_WATCH.our_equip_until = os.clock() + 0.5

    local dpad_id = nil
    pcall(function()
        local ism = re8vr.inventory and re8vr.inventory:call("get_ItemSlotManager")
        if not ism then return end
        local qs = nil
        pcall(function() qs = ism:call("getQuickSlot") end)
        if qs == nil then
            pcall(function() qs = ism:call("getQuickSlotNo") end)
        end
        if qs == nil and NATIVE_WEAPON_SEL.last_quick_slot ~= nil then
            qs = NATIVE_WEAPON_SEL.last_quick_slot
        end
        if qs == nil then
            local select_slot = nil
            pcall(function() select_slot = ism:call("getSelectItemSlotNo") end)
            if select_slot ~= nil then
                pcall(function() qs = ism:call("itemSlotNo2QuickSlotNo", select_slot) end)
            end
        end
        if qs ~= nil then
            local _, qs_id = get_item_id_from_quickslot(qs)
            dpad_id = qs_id
        end
    end)

    if not dpad_id or normalize_item_id(dpad_id) == target_id then return end

    local row = find_row_for_item_id(dpad_id)
    local dpad_weapon = row and row.weapon or nil
    if dpad_weapon and managed_object_alive(dpad_weapon) then
        STOW.hide_orphan_visual(dpad_weapon)
        STOW.arm_draw_flash(dpad_weapon)
    end

    refresh_components(false)
    local pg_id = read_player_gun_weapon_item_id(COMPONENTS.player_gun)
    if pg_id and pg_id ~= "" and normalize_item_id(pg_id) ~= target_id then
        force_clear_player_gun_combat(nil, "bare_draw_prepare")
    end
end

STOW.tick_flash = function()
    if os.clock() < WEAPON_WATCH.stow_flash_until then
        local weapon = WEAPON_WATCH.stow_flash_weapon
        if weapon and managed_object_alive(weapon) then
            hide_weapon_visuals(weapon)
            if COMPONENTS.weapon_change then
                pcall(function() COMPONENTS.weapon_change:call("setWeaponDisp", false) end)
            end
        end
    else
        WEAPON_WATCH.stow_flash_weapon = nil
    end

    if os.clock() < WEAPON_WATCH.draw_flash_until then
        local weapon = WEAPON_WATCH.draw_flash_weapon
        if weapon and managed_object_alive(weapon) then
            STOW.hide_orphan_visual(weapon)
        end
    else
        WEAPON_WATCH.draw_flash_weapon = nil
    end
    STOW.tick_orphan_hide()
end

local function clear_stow_bare_locks()
    STOW.lockout_until = 0
    STOW.reassert_count = 0
end

local QuickEquipSlotEnum = nil
pcall(function()
    QuickEquipSlotEnum = statics.generate("app.InventoryManager.QuickEquipSlotNo")
end)
if not QuickEquipSlotEnum or QuickEquipSlotEnum.Up == nil then
    QuickEquipSlotEnum = {}
    pcall(function()
        local td = sdk.find_type_definition("app.QuickSlotName")
        if not td then return end
        local function slot_val(name)
            local f = td:get_field(name)
            return f and f:get_data(nil) or nil
        end
        QuickEquipSlotEnum.Up = slot_val("Up")
        QuickEquipSlotEnum.Down = slot_val("Down")
        QuickEquipSlotEnum.Left = slot_val("Left")
        QuickEquipSlotEnum.Right = slot_val("Right")
    end)
end

local function get_item_id_from_quickslot(slot_no)
    if not re8vr.inventory or slot_no == nil then return nil, nil end
    if not managed_object_alive(re8vr.inventory) then return nil, nil end
    local item = nil
    pcall(function() item = re8vr.inventory:call("getItemFromQuickSlot", slot_no, false) end)
    if not item then
        pcall(function() item = re8vr.inventory:call("getItemFromQuickSlot", slot_no, true) end)
    end
    if not item then
        pcall(function() item = re8vr.inventory:call("getQuickSlotItem", slot_no) end)
    end
    if not item then
        pcall(function()
            local ism = re8vr.inventory:call("get_ItemSlotManager")
            if ism and managed_object_alive(ism) then
                item = ism:call("getQuickSlotItem", slot_no)
            end
        end)
    end
    if not item or not managed_object_alive(item) then return nil, nil end
    local internal = resolve_item_internal(item) or item
    if internal and not managed_object_alive(internal) then return nil, nil end
    local item_id = get_item_data_id(internal)
    return internal, item_id
end

local function find_quickslot_for_item_id(item_id)
    if not item_id or not QuickEquipSlotEnum then return nil, nil end
    for _, name in ipairs({ "Up", "Down", "Left", "Right" }) do
        local qs = QuickEquipSlotEnum[name]
        if qs ~= nil then
            local _, qs_id = get_item_id_from_quickslot(qs)
            if qs_id and normalize_item_id(qs_id) == normalize_item_id(item_id) then
                return qs, name
            end
        end
    end
    return nil, nil
end

-- After checkpoint, native shoot/inventory/block stay dead until applyQuickSlot.
-- Hip pistol is often not on a D-pad slot; bind it to an empty slot first.
local function bind_item_to_quickslot(item_id, weapon)
    local qs = select(1, find_quickslot_for_item_id(item_id))
    if qs ~= nil then return qs, false end
    if not QuickEquipSlotEnum or not re8vr or not re8vr.inventory then return nil, false end
    local go = nil
    if weapon then pcall(function() go = weapon:call("get_GameObject") end) end
    if not go then
        local row = find_row_for_item_id(item_id)
        if row and row.weapon then
            pcall(function() go = row.weapon:call("get_GameObject") end)
        end
    end
    if not go then return nil, false end
    local assign = nil
    for _, name in ipairs({ "Up", "Down", "Left", "Right" }) do
        local slot = QuickEquipSlotEnum[name]
        if slot ~= nil then
            local _, id = get_item_id_from_quickslot(slot)
            if not id or id == "" then
                assign = slot
                break
            end
        end
    end
    if assign == nil then assign = QuickEquipSlotEnum.Up end
    if assign == nil then return nil, false end
    local ok = false
    pcall(function()
        ok = re8vr.inventory:call("setQuickSlot", assign, go) ~= false
    end)
    if not ok then return nil, false end
    return assign, true
end

--- Point native D-pad selection at the weapon we are equipping (prevents applyQuickSlot snap-back).
local function sync_native_dpad_selection_for_item(item_id)
    if not item_id or item_id == "" then return false end
    local qs, name = find_quickslot_for_item_id(item_id)
    if qs == nil then
        return false
    end
    local ism = re8vr.inventory and safe_call(re8vr.inventory, "get_ItemSlotManager") or nil
    if not ism or not managed_object_alive(ism) then return false end
    pcall(function() ism:call("setQuickSlot", qs) end)
    NATIVE_WEAPON_SEL.last_quick_slot = qs
    NATIVE_WEAPON_SEL.last_select_slot = nil
    return true
end

--- Point ISM inventory selection at equipped weapon (works even when item is not on D-pad).
local function sync_inventory_select_for_item(item_id)
    if not item_id or item_id == "" then return false end
    item_id = normalize_item_id(item_id)
    if not re8vr.inventory then return false end
    local ism = safe_call(re8vr.inventory, "get_ItemSlotManager")
    if not ism then return false end
    local items_list = nil
    pcall(function() items_list = re8vr.inventory:call("get_items") end)
    if not items_list then
        pcall(function() items_list = re8vr.inventory:get_field("<items>k__BackingField") end)
    end
    local items = items_list and items_list.get_field and (function()
        local arr = nil
        pcall(function() arr = items_list:get_field("mItems") end)
        if not arr then pcall(function() arr = items_list:get_field("_items") end) end
        return arr
    end)() or nil
    local size = 0
    local list_indexed = false
    if items then
        pcall(function() size = items:get_size() end)
        if not size or size <= 0 then
            pcall(function() size = items:size() end)
        end
    elseif items_list then
        pcall(function() size = items_list:call("get_Count") end)
        list_indexed = type(size) == "number" and size > 0
    end
    if not size or size <= 0 then return false end
    for i = 0, size - 1 do
        local entry = nil
        if list_indexed then
            pcall(function() entry = items_list:call("get_Item", i) end)
        else
            pcall(function() entry = items:get_element(i) end)
        end
        if entry then
            local item_internal = resolve_item_internal(entry)
            local row_id = get_item_data_id(item_internal)
            if row_id and normalize_item_id(row_id) == item_id then
                pcall(function() ism:call("setSelectItemSlotNo", i) end)
                NATIVE_WEAPON_SEL.last_select_slot = i
                return true
            end
        end
    end
    return false
end

local function read_active_dpad_quickslot()
    -- VR weapon dial / dpad emit via.hid.GamePadButton LUp/LDown/LLeft/LRight.
    if not vrmod then return nil end
    local left = nil
    local right = nil
    pcall(function() left = vrmod:get_left_joystick() end)
    pcall(function() right = vrmod:get_right_joystick() end)

    local function active(action_getter, joy)
        if not joy or not action_getter then return false end
        local ok, a = pcall(action_getter)
        if not ok or not a then return false end
        local ok2, on = pcall(function() return vrmod:is_action_active(a, joy) end)
        return ok2 and on == true
    end
    local function active_any(action_getter)
        return active(action_getter, left) or active(action_getter, right)
    end

    local dial = false
    -- Visceral RE8 (2026-10-24, Tefa): the quick-equip combo is the left thumb rest + right stick, not the weapon dial (LT);
    -- re8_vr.lua reads the thumb rest every frame (_G.__visceral_thumbrest_dpad)
    dial = rawget(_G, "__visceral_thumbrest_dpad") == true

    local Q = QuickEquipSlotEnum
    if dial then
        local axis = nil
        pcall(function() axis = vrmod:get_right_stick_axis() end)
        if axis then
            -- Visceral RE8 (2026-10-24): the diagonals, as re8_vr.lua and the holster spots (cross turned 45 degrees clockwise)
            if axis.x and axis.y and Q and axis.x * axis.x + axis.y * axis.y >= 0.30 then
                if axis.x >= 0 and axis.y >= 0 and Q.Up ~= nil then return Q.Up, "dial_up_right" end
                if axis.x >= 0 and axis.y < 0 and Q.Right ~= nil then return Q.Right, "dial_down_right" end
                if axis.x < 0 and axis.y < 0 and Q.Down ~= nil then return Q.Down, "dial_down_left" end
                if axis.x < 0 and axis.y >= 0 and Q.Left ~= nil then return Q.Left, "dial_up_left" end
            end
        end
    end

    if active_any(function() return vrmod:get_action_dpad_up() end) and Q and Q.Up ~= nil then
        return Q.Up, "dpad_up"
    end
    if active_any(function() return vrmod:get_action_dpad_down() end) and Q and Q.Down ~= nil then
        return Q.Down, "dpad_down"
    end
    if active_any(function() return vrmod:get_action_dpad_left() end) and Q and Q.Left ~= nil then
        return Q.Left, "dpad_left"
    end
    if active_any(function() return vrmod:get_action_dpad_right() end) and Q and Q.Right ~= nil then
        return Q.Right, "dpad_right"
    end
    local pad_src = nil
    pcall(function()
        if not Q then return end
        local padman = sdk.get_managed_singleton("app.PadManager")
        if not padman then return end
        local pad = padman:call("get_mergedPad") or padman:call("get_CurrentPad")
        if not pad then return end
        local device = pad:call("get_Device") or pad
        local btn = device:call("get_Button")
        if type(btn) ~= "number" then return end
        local lup, ldown, lleft, lright = 0, 0, 0, 0
        pcall(function() lup = via.hid.GamePadButton.LUp or 0 end)
        pcall(function() ldown = via.hid.GamePadButton.LDown or 0 end)
        pcall(function() lleft = via.hid.GamePadButton.LLeft or 0 end)
        pcall(function() lright = via.hid.GamePadButton.LRight or 0 end)
        if lup ~= 0 and (btn & lup) ~= 0 and Q.Up ~= nil then pad_src = "pad_up" end
        if ldown ~= 0 and (btn & ldown) ~= 0 and Q.Down ~= nil then pad_src = "pad_down" end
        if lleft ~= 0 and (btn & lleft) ~= 0 and Q.Left ~= nil then pad_src = "pad_left" end
        if lright ~= 0 and (btn & lright) ~= 0 and Q.Right ~= nil then pad_src = "pad_right" end
    end)
    if pad_src == "pad_up" then return Q.Up, pad_src end
    if pad_src == "pad_down" then return Q.Down, pad_src end
    if pad_src == "pad_left" then return Q.Left, pad_src end
    if pad_src == "pad_right" then return Q.Right, pad_src end
    return nil, nil
end

local function arm_holster_equip_guard(item_id)
    if not item_id or item_id == "" then return end
    HOLSTER_GUARD.item_id = normalize_item_id(item_id)
    HOLSTER_GUARD.dpad_was_active = false
    HOLSTER_GUARD.armed_at = os.clock()
end

local function holster_guard_active()
    return HOLSTER_GUARD.item_id ~= ""
end

local function clear_holster_equip_guard(reason)
    if HOLSTER_GUARD.item_id == "" then return end
    HOLSTER_GUARD.item_id = ""
    HOLSTER_GUARD.dpad_was_active = false
    HOLSTER_GUARD.mesh_repair_weapon = nil
    HOLSTER_GUARD.mesh_repair_until = 0
    HOLSTER_GUARD.mesh_repair_last_t = 0
    HOLSTER_GUARD.mesh_repair_started_at = 0
    HOLSTER_GUARD.armed_at = 0
end

local function yield_holster_guard_for_native_dpad(reason)
    if not holster_guard_active() then return false end
    local qs_no, src = read_active_dpad_quickslot()
    if qs_no == nil then return false end
    local _, target_id = get_item_id_from_quickslot(qs_no)
    if not target_id or target_id == "" then return false end
    target_id = normalize_item_id(target_id)
    local guard_id = HOLSTER_GUARD.item_id
    if normalize_item_id(guard_id) == target_id then return false end
    local old_row = find_row_for_item_id(guard_id)
    local old_weapon = (old_row and old_row.weapon) or WEAPON_WATCH.last_ptr or get_active_weapon_object()
    NATIVE_WEAPON_SEL.native_dpad_until = os.clock() + 1.8
    STOW.arm_dpad_orphan(old_weapon, guard_id, target_id, reason or "dpad_yield")
    clear_holster_equip_guard(reason or "dpad_press")
    return true
end

local function our_holster_swap_active()
    local fly = rawget(_G, "__re8_fly_api")
    if type(fly) == "table" and fly.active == true then return true end
    return false
end

local function native_dpad_swap_window()
    return os.clock() < (NATIVE_WEAPON_SEL.native_dpad_until or 0)
end

local function native_weapon_change_requested()
    local wc = COMPONENTS.weapon_change
    if not wc then
        refresh_components(false)
        wc = COMPONENTS.weapon_change
    end
    if not wc then return false end
    -- Visceral RE8: a question that failed a moment ago (loading) is skipped; nil (not true / false) = it failed
    local function ask(name)
        if VRZ.waiting(name) then return false end
        local r = nil
        pcall(function() r = wc:call(name) end)
        if r == nil then VRZ.failed(name) end
        return r == true
    end
    if ask("isShortWeaponEquipRequested") then return true end
    if ask("isLongWeaponEquipRequested") then return true end
    if ask("isRequestedBothHandToOneHand") then return true end
    if ask("isRequestedOneHandToBothHand") then return true end
    if ask("isRequestedBothHandToBothHand") then return true end
    return false
end

STOW.clear_pending_weapon_change = function(reason)
    local wc = COMPONENTS.weapon_change
    if not wc then
        refresh_components(false)
        wc = COMPONENTS.weapon_change
    end
    if not wc then return false end
    local before = native_weapon_change_requested()
    STOW.set_requested_item(wc, nil)
    pcall(function() wc:call("set_isGetWeapon", false) end)
    NATIVE_WEAPON_SEL.wc_since = 0
    NATIVE_WEAPON_SEL.wc_unstick_done = false
    return true
end

-- Point re8vr.player at the live player after checkpoint.
-- Do not nil hand IK transforms (that shifted IK offsets).
local function rebind_live_player(reason)
    if not re8vr then return false end
    local live = nil
    pcall(function()
        local props = sdk.get_managed_singleton("app.PropsManager")
        if not props then return end
        live = props:call("get_Player")
        if not live then live = props:get_field("<Player>k__BackingField") end
        if not live then live = props:get_field("Player") end
    end)
    if not live or not managed_object_alive(live) then return false end
    local live_a, cur_a = 0, 0
    pcall(function() live_a = live:get_address() or 0 end)
    pcall(function()
        if re8vr.player then cur_a = re8vr.player:get_address() or 0 end
    end)
    if live_a ~= 0 and live_a == cur_a then return false end
    re8vr.player = live
    pcall(function()
        local t = live:call("get_Transform")
        if t then re8vr.transform = t end
    end)
    pcall(function()
        local inv = select(1, find_player_component("app.Inventory"))
        if inv then re8vr.inventory = inv end
    end)
    if re8vr.weapon and not managed_object_alive(re8vr.weapon) then
        re8vr.weapon = nil
    end
    return true
end

-- Checkpoint/load recreates player + inventory; Lua tables survive. Drop only
-- combat/guard script state. Do not touch holster transforms or IK offsets.
local function reset_holster_combat_script_state(reason)
    pcall(rebind_live_player, reason or "session_reset")
    pcall(function()
        if not re8vr or not re8vr.player then return end
        local inv = select(1, find_player_component("app.Inventory"))
        if inv then re8vr.inventory = inv end
    end)
    NATIVE_WEAPON_SEL.session_qs_repair = true
    clear_holster_equip_guard(reason or "session_reset")
    NATIVE_WEAPON_SEL.equip_in_progress = false
    NATIVE_WEAPON_SEL.pending_gun_combat_fixup = false
    NATIVE_WEAPON_SEL.gun_fixup_until = 0
    NATIVE_WEAPON_SEL.allow_one_apply_quickslot = false
    COMPONENTS.weapon_change = nil
    COMPONENTS.equip_manager = nil
    COMPONENTS.mesh_controller = nil
    COMPONENTS.player_gun = nil
    COMPONENTS.updater = nil
    COMPONENTS.hand_light = nil
    COMPONENTS.last_scan = 0
    FLASH.clear()
    pcall(refresh_components, true)
    rawset(_G, "__vr_block_bare_hands_aim", false)
    rawset(_G, "__vr_block_hold_in_holster_zone", false)
    rawset(_G, "__vr_block_shoot_ready", false)
end
STOW.prepare_bare_draw = function(target_id)
    if not target_id or target_id == "" then return end
    target_id = normalize_item_id(target_id)
    NATIVE_WEAPON_SEL.cleared_melee_dpad = ""
    NATIVE_WEAPON_SEL.allow_one_apply_quickslot = false
    NATIVE_WEAPON_SEL.pending_gun_combat_fixup = false
    NATIVE_WEAPON_SEL.gun_fixup_until = 0

    -- Break native melee D-pad lock before holster firearm equip (knife on quickslot + bare hands).
    if weapon_type_for_item_id(target_id) ~= "KNF" then
        pcall(function()
            local ism = re8vr.inventory and re8vr.inventory:call("get_ItemSlotManager")
            if not ism then return end
            NATIVE_WEAPON_SEL.override_slot = -1
            local qs = NATIVE_WEAPON_SEL.last_quick_slot
            local qs_src = qs ~= nil and "last_quick_slot" or ""
            if qs == nil then
                local select_slot = nil
                pcall(function() select_slot = ism:call("getSelectItemSlotNo") end)
                if select_slot ~= nil then
                    pcall(function() qs = ism:call("itemSlotNo2QuickSlotNo", select_slot) end)
                    if qs ~= nil then qs_src = "ism_select" end
                end
            end
            if qs == nil and QuickEquipSlotEnum then
                for _, name in ipairs({ "Up", "Down", "Left", "Right" }) do
                    local try_qs = QuickEquipSlotEnum[name]
                    if try_qs ~= nil then
                        local _, try_id = get_item_id_from_quickslot(try_qs)
                        if try_id and weapon_type_for_item_id(try_id) == "KNF" then
                            qs = try_qs
                            qs_src = "scan_" .. name
                            break
                        end
                    end
                end
            end
            NATIVE_WEAPON_SEL.override_slot = qs or -1
            if qs == nil then return end
            local _, qs_id = get_item_id_from_quickslot(qs)
            if not qs_id or weapon_type_for_item_id(qs_id) ~= "KNF" then return end
            NATIVE_WEAPON_SEL.cleared_melee_dpad = normalize_item_id(qs_id) or ""
            if COMPONENTS.weapon_change then
                STOW.set_requested_item(COMPONENTS.weapon_change, nil)
            end
            if re8vr.inventory then
                pcall(function() re8vr.inventory:call("removeEquip") end)
            end
            -- Do not applyQuickSlot here. If the hip pistol is not on a D-pad
            -- slot, that call reapplies knife/empty and kills shoot/inventory/block
            -- on first load. native_equip will equipWeapon the holster item.
            sync_inventory_select_for_item(target_id)
            pcall(function()
                local row = find_row_for_item_id(NATIVE_WEAPON_SEL.cleared_melee_dpad)
                if not row or not row.weapon then return end
                local go = row.weapon:call("get_GameObject")
                if not go then return end
                local melee = GameObject.get_component(go, sdk.game_namespace("implement.Melee"))
                if not melee then return end
                if not NATIVE_WEAPON_SEL.equip_status_enum then
                    NATIVE_WEAPON_SEL.equip_status_enum = statics.generate(
                        sdk.game_namespace("EquipmentDefine.EquipStatus"))
                end
                local st = NATIVE_WEAPON_SEL.equip_status_enum
                if st and st.Unequiped ~= nil then
                    melee:set_field("_Status", st.Unequiped)
                elseif st and st.Unequipped ~= nil then
                    melee:set_field("_Status", st.Unequipped)
                end
            end)
        end)
    end

    -- Do not arm holster guard here. Skipping Inventory.applyQuickSlot during
    -- equipWeapon is what leaves first-load hip/knife combat dead. Guard is
    -- armed after verified holster_draw in native_equip.
    HOLSTER_GUARD.draw_native_suppress_until = os.clock() + 3.0
    WEAPON_WATCH.our_equip_until = os.clock() + 0.5
    STOW.native_suppress_until = os.clock() + 3.0

    local qs_ok = sync_native_dpad_selection_for_item(target_id)
    local sel_ok = sync_inventory_select_for_item(target_id)

    local dpad_id = nil
    pcall(function()
        local ism = re8vr.inventory and re8vr.inventory:call("get_ItemSlotManager")
        if not ism then return end
        local qs = NATIVE_WEAPON_SEL.last_quick_slot
        if qs == nil then
            local select_slot = nil
            pcall(function() select_slot = ism:call("getSelectItemSlotNo") end)
            if select_slot ~= nil then
                pcall(function() qs = ism:call("itemSlotNo2QuickSlotNo", select_slot) end)
            end
        end
        if qs ~= nil then
            local _, qs_id = get_item_id_from_quickslot(qs)
            dpad_id = qs_id
        end
    end)

    if dpad_id and normalize_item_id(dpad_id) ~= target_id then
        local row = find_row_for_item_id(dpad_id)
        local dpad_weapon = row and row.weapon or nil
        if dpad_weapon and managed_object_alive(dpad_weapon) then
            STOW.hide_orphan_visual(dpad_weapon)
            STOW.arm_draw_flash(dpad_weapon)
        end
    end

    refresh_components(false)
    local pg_id = read_player_gun_weapon_item_id(COMPONENTS.player_gun)
    if pg_id and pg_id ~= "" and normalize_item_id(pg_id) ~= target_id then
        force_clear_player_gun_combat(nil, "bare_draw_prepare")
    end
end

hide_weapon_visuals = function(weapon)
    if not weapon then return end
    if is_holster_excluded_weapon(weapon) then return end
    refresh_components(false)
    local mesh_controller = COMPONENTS.mesh_controller
    if mesh_controller then
        pcall(function() mesh_controller:call("onEquipWeaponChanged", nil, weapon) end)
        pcall(function()
            local mesh_go = mesh_controller:call("get_weaponMeshObject")
            if mesh_go then mesh_go:call("setActive", false) end
        end)
    end
    pcall(function() weapon:call("disp", false) end)
    pcall(function()
        local go = weapon:call("get_GameObject")
        if go then go:call("setActive", false) end
    end)
end

--- Hide prior weapon visuals for cross-slot swap without bare-hands combat sync.
local function teardown_for_cross_swap(prev_weapon)
    if not prev_weapon then return end
    if is_holster_excluded_weapon(prev_weapon) then return end
    refresh_components(false)
    hide_weapon_visuals(prev_weapon)
    pcall(function() prev_weapon:call("disp", false) end)
    pcall(function()
        local go = prev_weapon:call("get_GameObject")
        if go then go:call("setActive", false) end
    end)
end


--- Hide holster-draw orphan mesh when the game swaps weapons natively (e.g. D-pad while armed).
local function tick_weapon_swap_mesh_fixup()
    if native_dpad_swap_window() or NATIVE_WEAPON_SEL.motion0_left
        or (not our_holster_swap_active() and native_weapon_change_requested()) then
        local cur_swap = get_active_weapon_object() or re8vr.weapon
        local prev_swap = WEAPON_WATCH.dpad_old_ptr or WEAPON_WATCH.last_ptr
        if prev_swap and cur_swap and prev_swap ~= cur_swap and managed_object_alive(prev_swap) then
            local prev_id_swap = tostring(WEAPON_WATCH.dpad_old_id or WEAPON_WATCH.last_id or "")
            STOW.detach_orphan_from_hand(prev_swap)
            STOW.arm_orphan_hide(prev_swap)
            WEAPON_WATCH.last_ptr = cur_swap
            WEAPON_WATCH.last_id = get_weapon_item_id(cur_swap) or ""
        elseif WEAPON_WATCH.dpad_old_ptr and managed_object_alive(WEAPON_WATCH.dpad_old_ptr) then
            -- Swap in progress: keep suppressing the outgoing holster gun.
            STOW.detach_orphan_from_hand(WEAPON_WATCH.dpad_old_ptr)
        end
        return
    end
    if holster_guard_active() then
        if native_weapon_change_requested() and not our_holster_swap_active() then
            return
        end
        -- Option 3: re-run mesh init after bare draw (covers Frame 1 flash ruin).
        -- Full finalize is expensive (onEquipWeaponChanged/updateParts); keep it
        -- dense only for the first flash window, then throttle.
        if HOLSTER_GUARD.mesh_repair_until > 0 then
            local now = os.clock()
            if now < HOLSTER_GUARD.mesh_repair_until then
                local rw = HOLSTER_GUARD.mesh_repair_weapon
                if rw and weapon_component_usable(rw) then
                    local started = HOLSTER_GUARD.mesh_repair_started_at or 0
                    if started <= 0 then
                        started = now
                        HOLSTER_GUARD.mesh_repair_started_at = now
                    end
                    local age = now - started
                    local last = HOLSTER_GUARD.mesh_repair_last_t or 0
                    local due = (age < 0.12) or ((now - last) >= 0.12)
                    if due then
                        STOW.finalize_equipped_mesh(rw)
                        HOLSTER_GUARD.mesh_repair_last_t = now
                    end
                    if (now - (HOLSTER_GUARD.watch_last_log_t or 0)) > 0.12 then
                        HOLSTER_GUARD.watch_last_log_t = now
                    end
                end
            else
                HOLSTER_GUARD.mesh_repair_until = 0
                HOLSTER_GUARD.mesh_repair_weapon = nil
                HOLSTER_GUARD.mesh_repair_last_t = 0
                HOLSTER_GUARD.mesh_repair_started_at = 0
            end
        end
        if NATIVE_WEAPON_SEL.gun_fixup_until > 0 and os.clock() < NATIVE_WEAPON_SEL.gun_fixup_until then
            refresh_components(false)
            pcall(function()
                local pg = COMPONENTS.player_gun
                if not pg or not managed_object_alive(pg) then return end
                local rw = WEAPON_WATCH.last_ptr
                if rw and managed_object_alive(rw) then
                    pg:call("onEquipWeaponChanged", rw, nil)
                    pg:call("updateWeaponInfo")
                    pg:call("setupGunActiveData")
                    pg:call("setupGunFireData")
                end
                pg:call("goActiveTriggerState")
                STOW.clear_unshootable(pg)
            end)
        elseif NATIVE_WEAPON_SEL.gun_fixup_until > 0 then
            NATIVE_WEAPON_SEL.gun_fixup_until = 0
            NATIVE_WEAPON_SEL.pending_gun_combat_fixup = false
            NATIVE_WEAPON_SEL.cleared_melee_dpad = ""
        end
        local guard_id = HOLSTER_GUARD.item_id
        local guard_weapon = WEAPON_WATCH.last_ptr
        if (not guard_weapon) or (not managed_object_alive(guard_weapon)) then
            local row = find_row_for_item_id(guard_id)
            guard_weapon = row and row.weapon or nil
        end
        WEAPON_WATCH.last_ptr = guard_weapon or WEAPON_WATCH.last_ptr
        WEAPON_WATCH.last_id = guard_id
        return
    end
    if WEAPON_WATCH.dpad_target_id ~= "" then
        local now = os.clock()
        if now >= WEAPON_WATCH.dpad_cleanup_until then
            WEAPON_WATCH.dpad_target_id = ""
            WEAPON_WATCH.dpad_old_ptr = nil
            WEAPON_WATCH.dpad_old_id = ""
            WEAPON_WATCH.dpad_finalize_done = false
        else
            local cur = get_active_weapon_object() or re8vr.weapon
            local cur_id = cur and get_weapon_item_id(cur) or ""
            if cur_id ~= "" and normalize_item_id(cur_id) == normalize_item_id(WEAPON_WATCH.dpad_target_id) then
                local old = WEAPON_WATCH.dpad_old_ptr
                if old and old ~= cur and managed_object_alive(old) then
                    STOW.detach_orphan_from_hand(old)
                    STOW.arm_orphan_hide(old)
                end
                if cur and managed_object_alive(cur) and WEAPON_WATCH.dpad_finalize_done ~= true then
                    if not is_holster_excluded_weapon(cur, cur_id) then
                        STOW.finalize_equipped_mesh(cur)
                        sync_player_gun_combat(cur, old, "dpad_target_mesh_fixup")
                    end
                    WEAPON_WATCH.dpad_finalize_done = true
                end
                WEAPON_WATCH.last_ptr = cur
                WEAPON_WATCH.last_id = cur_id
            end
            return
        end
    end
    if os.clock() < WEAPON_WATCH.our_equip_until then
        local cur_skip = get_active_weapon_object() or re8vr.weapon
        if cur_skip then
            WEAPON_WATCH.last_ptr = cur_skip
            WEAPON_WATCH.last_id = get_weapon_item_id(cur_skip) or ""
        end
        return
    end
    refresh_components(false)
    local cur = get_active_weapon_object() or re8vr.weapon
    local cur_id = cur and get_weapon_item_id(cur) or ""
    local prev = WEAPON_WATCH.last_ptr
    local prev_id = WEAPON_WATCH.last_id or ""
    local ptr_changed = prev ~= nil and cur ~= prev
    local id_changed = prev_id ~= "" and cur_id ~= "" and normalize_item_id(prev_id) ~= normalize_item_id(cur_id)
    if prev and managed_object_alive(prev) and (ptr_changed or id_changed) then
        if HOLSTER_GUARD.item_id ~= ""
            and prev_id ~= ""
            and normalize_item_id(prev_id) == normalize_item_id(HOLSTER_GUARD.item_id)
            and (cur_id == "" or normalize_item_id(cur_id) ~= normalize_item_id(HOLSTER_GUARD.item_id)) then
            WEAPON_WATCH.last_ptr = prev
            WEAPON_WATCH.last_id = prev_id
            return
        end
        local cur_ex = cur and is_holster_excluded_weapon(cur, cur_id) or false
        STOW.hide_orphan_visual(prev)
        if cur and managed_object_alive(cur) then
            if not cur_ex then
                STOW.finalize_equipped_mesh(cur)
                sync_player_gun_combat(cur, prev, "native_swap_mesh_fixup")
            end
        elseif not cur and COMPONENTS.mesh_controller then
            pcall(function() COMPONENTS.mesh_controller:call("onEquipWeaponChanged", nil, prev) end)
            pcall(function()
                local mesh_go = COMPONENTS.mesh_controller:call("get_weaponMeshObject")
                if mesh_go then mesh_go:call("setActive", false) end
            end)
        end
    end
    WEAPON_WATCH.last_ptr = cur
    WEAPON_WATCH.last_id = cur_id
end

--- LockScene calls get_GameObject on re8vr.weapon; stale/deactivated refs throw.
local function weapon_safe_for_re8vr(weapon)
    return weapon_component_usable(weapon)
end

--- Must run before LockScene update_muzzle_data (no pcall on get_GameObject there).
local function protect_re8vr_weapon_for_lockscene()
    if not re8vr then return end
    if not re8vr.can_use_hands then
        re8vr.weapon = nil
        return
    end
    if re8vr.player and not managed_object_alive(re8vr.player) then
        re8vr.weapon = nil
        return
    end
    if re8vr.inventory and not managed_object_alive(re8vr.inventory) then
        re8vr.weapon = nil
        return
    end
    if os.clock() < (GRIP.scene_block_until or 0) then
        re8vr.weapon = nil
        return
    end
    if re8vr.weapon and not weapon_safe_for_re8vr(re8vr.weapon) then
        local active = get_active_weapon_object()
        if active and weapon_safe_for_re8vr(active) then
            re8vr.weapon = active
        else
            re8vr.weapon = nil
        end
    end
end

local function sanitize_re8vr_weapon_pointer()
    if not re8vr then return end
    if not re8vr.can_use_hands then
        re8vr.weapon = nil
        return
    end
    if re8vr.player and not managed_object_alive(re8vr.player) then
        re8vr.weapon = nil
        return
    end
    if re8vr.inventory and not managed_object_alive(re8vr.inventory) then
        re8vr.weapon = nil
        return
    end
    local before = re8vr.weapon
    if is_bare_hands() then
        local gun_on = false
        local pg_w = COMPONENTS.player_gun and safe_call(COMPONENTS.player_gun, "get_equipWeaponObject") or nil
        if COMPONENTS.equip_manager then
            pcall(function() gun_on = COMPONENTS.equip_manager:call("isGunEquip") == true end)
        end
        if gun_on and pg_w and managed_object_alive(pg_w) then
            re8vr.weapon = pg_w
            pcall(COMPONENTS.bind_muzzle, pg_w)
            return
        end
        if re8vr.weapon ~= nil then
            re8vr.weapon = nil
        end
        return
    end
    local active = get_active_weapon_object()
    if re8vr.weapon and not weapon_safe_for_re8vr(re8vr.weapon) then
        if active and weapon_safe_for_re8vr(active) then
            re8vr.weapon = active
        else
            re8vr.weapon = nil
        end
    elseif not re8vr.weapon and active and weapon_safe_for_re8vr(active) then
        re8vr.weapon = active
    elseif re8vr.weapon and active and re8vr.weapon ~= active
        and weapon_safe_for_re8vr(active) then
        re8vr.weapon = active
    end
    pcall(COMPONENTS.bind_muzzle, re8vr.weapon)
    if before ~= re8vr.weapon then
        local now = os.clock()
        if (now - WEAPON_WATCH.re8vr_ptr_last_log_t) > 0.25 then
            WEAPON_WATCH.re8vr_ptr_last_log_t = now
        end
    end
end

local function sync_re8vr_weapon_pointer(expected_weapon)
    if not re8vr then return end
    if is_bare_hands() then
        re8vr.weapon = nil
        return
    end
    refresh_components(false)
    local em = COMPONENTS.equip_manager
    local resolved = expected_weapon
    if em then
        local em_w = safe_call(em, "get_equipWeaponRight")
        if em_w and managed_object_alive(em_w) then
            resolved = em_w
        end
    end
    if resolved and weapon_safe_for_re8vr(resolved) then
        re8vr.weapon = resolved
    elseif expected_weapon == nil then
        re8vr.weapon = nil
    else
        re8vr.weapon = nil
    end
end

local function verify_equipped_weapon(item_id, weapon)
    item_id = normalize_item_id(item_id)
    sync_re8vr_weapon_pointer(weapon)
    local em_weapon = nil
    if COMPONENTS.equip_manager then
        em_weapon = safe_call(COMPONENTS.equip_manager, "get_equipWeaponRight")
    end
    local cur_id = get_current_weapon_item_id()
    local id_ok = (not item_id) or (cur_id and normalize_item_id(cur_id) == item_id)
    local ptr_ok = weapon and (re8vr.weapon == weapon or em_weapon == weapon)
    return id_ok and ptr_ok == true
end

local function teardown_active_weapon(weapon)
    if not weapon then return end
    if is_holster_excluded_weapon(weapon) then return end
    refresh_components(false)
    hide_weapon_visuals(weapon)
    if COMPONENTS.weapon_change then
        pcall(function() COMPONENTS.weapon_change:call("removeWeaponWithNoAction") end)
        pcall(function() COMPONENTS.weapon_change:call("removeWeapon", false) end)
        pcall(function() COMPONENTS.weapon_change:call("setWeaponDisp", false) end)
        STOW.set_requested_item(COMPONENTS.weapon_change, nil)
    end
    local em = COMPONENTS.equip_manager
    if em then
        pcall(function()
            local cur = em:get_field("<equipWeaponRight>k__BackingField")
            if cur == weapon then
                em:call("set_equipWeaponRight", nil)
            end
        end)
    end
    sync_player_gun_combat(nil, weapon, "teardown")
end

--- Clear WeaponID.Hand / none-equipped before equipping a real weapon.
local function clear_hand_equip_state_before_weapon(equip_manager)
    if not equip_manager then return end
    local needs_clear = false
    pcall(function()
        if equip_manager:call("get_isNoneEquiped") == true then
            needs_clear = true
        end
    end)
    if not needs_clear then
        local em_w = safe_call(equip_manager, "get_equipWeaponRight")
        if em_w == nil then needs_clear = true end
    end
    if not needs_clear then return end
    pcall(function() equip_manager:call("set_equipWeaponRight", nil) end)
    pcall(function() equip_manager:call("set_isNoneEquipped", false) end)
end

STOW._is_ads_melee_utility = function(weapon, item_id)
    item_id = normalize_item_id(item_id) or ""
    if item_id:find("CircularSaw", 1, true) or item_id:find("ChainSaw", 1, true)
        or item_id:find("circularsaw", 1, true) or item_id:find("chainsaw", 1, true) then
        return true
    end
    if not weapon then return false end
    local td = nil
    pcall(function() td = weapon:get_type_definition() end)
    if not td then return false end
    local ok, is_saw = pcall(function() return td:is_a("app.WpCircularSaw") end)
    if ok and is_saw then return true end
    ok, is_saw = pcall(function() return td:is_a("app.WpChainSaw") end)
    if ok and is_saw then return true end
    ok, is_saw = pcall(function() return td:is_a("app.WeaponChainSaw") end)
    if ok and is_saw then return true end
    return false
end

-- Saw ADS is PlayerMelee MeleeAimAttackLoop (IsWeaponSaw), not PlayerGun.
-- From-bare lua equip never called PlayerMelee.onEquipWeaponChanged.
STOW.bind_ads_melee_player_layer = function(weapon, prev, item_internal)
    if not weapon or not managed_object_alive(weapon) then return end
    refresh_components(false)
    local pm = COMPONENTS.player_melee
    if not pm or not managed_object_alive(pm) then
        pm = select(1, find_player_component("app.PlayerMelee"))
        COMPONENTS.player_melee = pm
    end
    if pm and managed_object_alive(pm) then
        local pm_prev = prev
        if pm_prev == weapon then pm_prev = nil end
        pcall(function() pm:call("onEquipWeaponChanged", weapon, pm_prev) end)
        pcall(function() pm:call("gatherComponents") end)
        pcall(function() pm:set_field("IsWeaponSaw", true) end)
        pcall(function()
            local wid = weapon:call("get_weaponID")
            if wid ~= nil then pm:set_field("_CurrentWeaponID", wid) end
        end)
        pcall(function() pm:call("setupMeleeActiveData") end)
        pcall(function() pm:call("setupMeleeHoldData") end)
        pcall(function() pm:call("goActiveTriggerState") end)
        pcall(function() pm:call("doStart") end)
    end
    local wc = COMPONENTS.weapon_change
    if wc and managed_object_alive(wc) then
        if item_internal then
            STOW.set_requested_item(wc, item_internal)
        end
        pcall(function() wc:call("equipWeapon", weapon, false) end)
        pcall(function() wc:call("processOnOwnerDelegateStarted") end)
    end
end

STOW._is_throwable_utility = function(weapon, item_id)
    item_id = normalize_item_id(item_id) or ""
    local lower = item_id:lower()
    if lower:find("grenadebomb", 1, true) or lower:find("stangrenade", 1, true)
        or lower:find("timebomb", 1, true) or lower:find("liquidbomb", 1, true)
        or lower:find("thermatebomb", 1, true) then
        return true
    end
    if not weapon then return false end
    local td = nil
    pcall(function() td = weapon:get_type_definition() end)
    if not td then return false end
    local ok, is_t = pcall(function() return td:is_a("app.WeaponThrowableCore") end)
    if ok and is_t then return true end
    return false
end

STOW.bind_throwable_player_layer = function(weapon, prev, item_internal)
    if not weapon or not managed_object_alive(weapon) then return end
    refresh_components(false)
    local td = nil
    pcall(function() td = weapon:get_type_definition() end)
    local is_thr = false
    if td then
        pcall(function() is_thr = td:is_a("app.WeaponThrowableCore") == true end)
    end
    if not is_thr then return end
    local layer_prev = prev
    if layer_prev == weapon then layer_prev = nil end
    local pg = COMPONENTS.player_gun
    if pg and managed_object_alive(pg) then
        pcall(function() pg:call("onEquipWeaponChanged", weapon, layer_prev) end)
    end
    local wc = COMPONENTS.weapon_change
    if wc and item_internal then
        pcall(function() wc:call("equipObject", safe_call(weapon, "get_owner") or safe_call(weapon, "get_GameObject")) end)
    end
end

STOW._has_puzzle_append = function(weapon)
    if not weapon or not weapon_component_usable(weapon) then return false end
    local hit = false
    pcall(function()
        local go = weapon:call("get_GameObject")
        if not go then return end
        local comps = go:call("get_Components")
        if not comps then return end
        local n = comps:call("get_Count") or 0
        if type(n) ~= "number" or n < 1 then return end
        if n > 48 then n = 48 end
        for i = 0, n - 1 do
            local comp = comps:call("get_Item", i)
            if comp then
                local td = comp:get_type_definition()
                local name = td and td:get_full_name() or ""
                if name:find("Append", 1, true)
                    and not name:find("Timebomb", 1, true)
                    and not name:find("Throwable", 1, true) then
                    hit = true
                    return
                end
            end
        end
    end)
    return hit
end

STOW.is_inventory_native_tool = function(weapon, item_id)
    if STOW._is_ads_melee_utility(weapon, item_id) then return false end
    if STOW._is_throwable_utility(weapon, item_id) then return false end
    item_id = normalize_item_id(item_id)
    local slot = item_id and holster_slot_for_item_id(item_id) or nil
    if slot and slot ~= "utility" then return false end
    local excluded = item_id and is_holster_excluded_weapon(nil, item_id) or false
    local append = STOW._has_puzzle_append(weapon)
    local id_s = tostring(item_id or ""):lower()
    local glasses = id_s:find("glasses", 1, true) ~= nil
    local ok = excluded == true or append == true or glasses == true
    return ok
end

STOW.start_weapon_behavior = function(weapon, from_bare)
    if not weapon or not managed_object_alive(weapon) then return false end
    local before = false
    pcall(function() before = weapon:call("get_isStarted") == true end)
    -- From-bare must re-run start/doStart even if the saw was already started
    -- this session; skipping it leaves ADS sfx/collision without AimAttackLoop.
    if from_bare or not before then
        pcall(function() weapon:call("start") end)
        pcall(function() weapon:call("doStart") end)
        pcall(function()
            if weapon:call("get_isStarted") ~= true then
                weapon:call("set_isStarted", true)
            end
        end)
        pcall(function()
            if weapon:call("get_Enabled") ~= true then
                weapon:call("set_Enabled", true)
            end
        end)
        pcall(function()
            local go = weapon:call("get_GameObject")
            if go then go:call("setActive", true) end
        end)
        pcall(function() weapon:call("disp", true) end)
    end
    if from_bare then
        local wc = COMPONENTS.weapon_change
        if wc and managed_object_alive(wc) then
            pcall(function() wc:call("processOnOwnerDelegateStarted") end)
        end
    end
    local after = false
    pcall(function() after = weapon:call("get_isStarted") == true end)
    return after
end

--- Full equip chain: PlayerWeaponChange first, then EquipController/inventory/mesh.
local function native_equip(item_internal, weapon, source_tag)
    if STOW.player_dead() then return false end
    if not re8vr or not re8vr.can_use_hands then return false end
    if re8vr.player and not managed_object_alive(re8vr.player) then return false end
    if re8vr.inventory and not managed_object_alive(re8vr.inventory) then return false end
    if os.clock() < (GRIP.scene_block_until or 0) then return false end
    if NATIVE_WEAPON_SEL.equip_in_progress then
        return false
    end
    if os.clock() < (NATIVE_WEAPON_SEL.equip_cooldown_until or 0) then return false end
    if not weapon or not managed_object_alive(weapon) then return false end
    if is_holster_excluded_weapon(weapon) then return false end
    if item_internal and not managed_object_alive(item_internal) then return false end
    NATIVE_WEAPON_SEL.equip_in_progress = true
    if not refresh_components(false) then
        NATIVE_WEAPON_SEL.equip_in_progress = false
        return false
    end
    if not item_internal or not weapon then
        NATIVE_WEAPON_SEL.equip_in_progress = false
        return false
    end
    local item_id = get_item_data_id(item_internal)
    if item_id and weapon_type_for_item_id(item_id) == "MED" then
        -- Medicine is a Lua hand mesh only; never native-equip as a weapon (AV risk).
        NATIVE_WEAPON_SEL.equip_in_progress = false
        return false
    end
    if is_medicine_core(item_internal) or is_medicine_core(weapon) then
        NATIVE_WEAPON_SEL.equip_in_progress = false
        return false
    end
    local weapon_row_id = get_weapon_item_id(weapon)
    if item_id and weapon_row_id and normalize_item_id(weapon_row_id) ~= normalize_item_id(item_id) then
        local fixed = find_row_for_item_id(item_id)
        if fixed and fixed.weapon and managed_object_alive(fixed.weapon) then
            weapon = fixed.weapon
            item_internal = fixed.item_internal
            weapon_row_id = item_id
        end
    end
    if not weapon_component_usable(weapon) then
        local live_row = item_id and find_row_for_item_id(item_id) or nil
        if live_row and weapon_component_usable(live_row.weapon) then
            weapon = live_row.weapon
            item_internal = live_row.item_internal
            weapon_row_id = item_id
        else
            NATIVE_WEAPON_SEL.equip_in_progress = false
            return false
        end
    end
    local weapon_change = COMPONENTS.weapon_change
    local equip_manager = COMPONENTS.equip_manager
    local mesh_controller = COMPONENTS.mesh_controller
    if not weapon_change or not managed_object_alive(weapon_change) then
        NATIVE_WEAPON_SEL.equip_in_progress = false
        return false
    end
    local equipped = false
    local hand = get_right_hand_enum()
    local drawing_from_bare = is_bare_hands()
    local source_is_holster = source_tag and source_tag:find("holster", 1, true) ~= nil
    if drawing_from_bare then
        STOW.set_requested_item(weapon_change, nil)
    end

    if source_is_holster and drawing_from_bare and item_id then
        STOW.prepare_bare_draw(item_id)
    end

    if source_tag and source_tag:find("holster", 1, true) then
        local pg_id = read_player_gun_weapon_item_id(COMPONENTS.player_gun)
        local target_norm = item_id and normalize_item_id(item_id) or nil
        if drawing_from_bare and pg_id and pg_id ~= ""
            and target_norm and normalize_item_id(pg_id) ~= target_norm then
            force_clear_player_gun_combat(nil, "bare_holster_draw_prepare")
        elseif not drawing_from_bare and pg_id and target_norm
            and normalize_item_id(pg_id) ~= target_norm then
            pcall(function()
                if COMPONENTS.player_gun then
                    COMPONENTS.player_gun:call("goIdleTriggerState")
                end
            end)
        end
    end

    local prev_weapon, prev_source = get_active_weapon_object()
    if not prev_weapon then prev_weapon = re8vr.weapon end
    if prev_weapon and not managed_object_alive(prev_weapon) then prev_weapon = nil end
    local cross_prev, cross_prev_id = peek_cross_swap_prev()
    if not prev_weapon and cross_prev and managed_object_alive(cross_prev) then
        prev_weapon = cross_prev
        prev_source = "cross_swap"
    end
    if not prev_source or prev_source == "none" then
        prev_source = prev_weapon and "re8vr_fallback" or "none"
    end
    local prev_id = prev_weapon and get_weapon_item_id(prev_weapon) or cross_prev_id or nil
    local leaving_excluded = prev_weapon ~= nil and prev_weapon ~= weapon
        and is_holster_excluded_weapon(prev_weapon, prev_id)
    local is_cross_swap = source_tag and source_tag:find("holster_draw_cross", 1, true) ~= nil
    -- Bare hip/knife draws used to clear EM to "not empty" with a nil weapon.
    -- Shoulder unstick is a cross-swap that skips this and native combat stays live.
    if not is_cross_swap and not source_is_holster then
        clear_hand_equip_state_before_weapon(equip_manager)
    end
    if prev_weapon and prev_weapon ~= weapon then
        if is_holster_excluded_weapon(prev_weapon, prev_id) then
            STOW.hide_orphan_visual(prev_weapon)
        elseif is_cross_swap then
            teardown_for_cross_swap(prev_weapon)
        elseif not drawing_from_bare then
            teardown_active_weapon(prev_weapon)
        end
    elseif not drawing_from_bare then
            pcall(function() weapon_change:call("removeWeaponWithNoAction") end)
            pcall(function() weapon_change:call("removeWeapon", false) end)
    end

    if drawing_from_bare and source_is_holster and item_id then
        local pre_melee = weapon_type_for_item_id(item_id) == "KNF"
        if not pre_melee then
            sync_native_dpad_selection_for_item(item_id)
            sync_inventory_select_for_item(item_id)
        end
    end

        pcall(function()
            -- bool true = event/no-anim path; it can leave Long/Short equip
            -- requested sticky with no HolsterToMove to clear it, which blocks
            -- the next native D-pad swap to any other weapon.
            local skip_swap_anim = source_tag
                and (source_tag:find("unstick", 1, true) ~= nil
                    or source_tag:find("orphan", 1, true) ~= nil
                    or source_tag:find("req_finish", 1, true) ~= nil)
            weapon_change:call("equipWeapon", weapon, skip_swap_anim == true)
            equipped = true
        end)

    if not equipped and equip_manager and weapon_component_usable(weapon) then
        if STOW.call_equip_weapon(equip_manager, weapon) then
            equipped = true
        end
    end

    if not equipped and equip_manager and weapon_component_usable(weapon) then
        pcall(function()
            local owner = safe_call(weapon, "get_owner") or safe_call(weapon, "get_GameObject")
            if owner then
                equip_manager:call("equipObject", owner)
                equipped = true
            end
        end)
    end

    if equipped then
        if equip_manager then
            pcall(function() equip_manager:call("set_equipWeaponRight", weapon) end)
            pcall(function()
                local wid = safe_call(weapon, "get_weaponID")
                if wid ~= nil then
                    pcall(function() equip_manager:set_field("EquipWeaponIdRight", wid) end)
                end
            end)
        end

        item_id = get_item_data_id(item_internal)
        if item_id then
        if re8vr.inventory then
            local wtype = weapon_type_for_item_id(item_id)
            local is_melee = (wtype == "KNF")
            local cat = nil
            pcall(function() cat = weapon:call("get_weaponCategory") end)
            if not is_melee then
                    sync_native_dpad_selection_for_item(item_id)
                    sync_inventory_select_for_item(item_id)
                end
                -- removeEquip after a Chris holster draw can finish a frame later
                -- as Hand while the holster probe is already hidden (ghost grip).
                -- From already-bare, removeEquip re-asserts Hand and defers
                -- equipWeapon until locomotion.
                if not drawing_from_bare
                    and not (source_is_holster and STOW.is_chris_player() == true) then
                    pcall(function() re8vr.inventory:call("removeEquip") end)
                end
            pcall(function() re8vr.inventory:call("equipWeapon", item_id) end)
                -- Bind holster firearms to a D-pad slot for later native swaps.
                -- Do not applyQuickSlot here: that starts HolsterToMove on top of
                -- the Lua holster equip and leaves the next D-pad swap unfinished.
                if source_is_holster and not is_melee then
                    NATIVE_WEAPON_SEL.session_qs_repair = false
                    bind_item_to_quickslot(item_id, weapon)
                    sync_inventory_select_for_item(item_id)
                    sync_native_dpad_selection_for_item(item_id)
                end
                -- Do not use WeaponCategory==1 as melee: guns also report 1.
                -- Holster firearms: do not applyQuickSlot (re-applies D-pad knife/empty)
                -- and do not start a gun_fixup window. Backup first-load worked because
                -- guns were misclassified as melee and skipped both. Extra
                -- goActiveTriggerState after equipWeapon leaves shoot/inventory/block dead
                -- while PlayerGun still looks equipped (ism_sel stays -1).
                if not is_melee and not source_is_holster and not drawing_from_bare then
                    local qs = find_quickslot_for_item_id(item_id)
                    if qs ~= nil then
                pcall(function() re8vr.inventory:call("applyQuickSlot") end)
                    end
                elseif not is_melee and source_is_holster and drawing_from_bare
                    and NATIVE_WEAPON_SEL.pending_gun_combat_fixup then
                    -- Knife was on D-pad; allow one applyQuickSlot only after pointing
                    -- selection at the holster firearm (same as backup).
                    local qs = find_quickslot_for_item_id(item_id)
                    local qs_ok = false
                    if qs ~= nil then
                        qs_ok = sync_native_dpad_selection_for_item(item_id)
                    end
                    sync_inventory_select_for_item(item_id)
                    if qs_ok then
                        NATIVE_WEAPON_SEL.allow_one_apply_quickslot = true
                        pcall(function() re8vr.inventory:call("applyQuickSlot") end)
                        NATIVE_WEAPON_SEL.allow_one_apply_quickslot = false
                    end
                end
            end
        end

            pcall(function() weapon_change:call("setWeaponDisp", true) end)

        if mesh_controller and managed_object_alive(mesh_controller) then
            pcall(function() mesh_controller:call("onEquipWeaponChanged", weapon, prev_weapon) end)
            pcall(function()
                local mesh_go = mesh_controller:call("get_weaponMeshObject")
                if mesh_go and managed_object_alive(mesh_go) then mesh_go:call("setActive", true) end
            end)
            pcall(function() mesh_controller:call("updateParts") end)
        end

        pcall(function() weapon:call("disp", true) end)
        pcall(function()
            local go = weapon:call("get_GameObject")
            if go and managed_object_alive(go) then go:call("setActive", true) end
        end)

        if drawing_from_bare or leaving_excluded then
            STOW.start_weapon_behavior(weapon, true)
        end

        if equip_manager and os.clock() >= (GRIP.scene_block_until or 0) then
            STOW.call_equip_weapon(equip_manager, weapon)
        end

        sync_player_gun_combat(weapon, prev_weapon, source_tag or "native_equip")
    end

    sync_re8vr_weapon_pointer(weapon)
    if is_bare_hands() then
        if weapon and weapon_safe_for_re8vr(weapon) then
            re8vr.weapon = weapon
        end
    else
        sanitize_re8vr_weapon_pointer()
    end

    local verified = verify_equipped_weapon(item_id, weapon)
    local hid_mesh = false
    local holster_draw = source_tag and source_tag:find("holster_draw", 1, true) ~= nil
    if equipped and not verified then
        if holster_draw or not source_is_holster then
            -- Verify often fails on Chris checkpoint (stale EM ptr) while
            -- holster fly already hid the probe. Hiding a D-pad draw leaves
            -- bare hands until locomotion finishes native equip.
            STOW.finalize_equipped_mesh(weapon)
            pcall(function() weapon:call("disp", true) end)
            pcall(function()
                local go = weapon:call("get_GameObject")
                if go then go:call("setActive", true) end
            end)
            verified = verify_equipped_weapon(item_id, weapon) or verified
        else
            hide_weapon_visuals(weapon)
            hid_mesh = true
        end
    end

    if drawing_from_bare and not source_is_holster and is_bare_hands() then
        WEAPON_WATCH.our_equip_until = 0
    else
        WEAPON_WATCH.our_equip_until = os.clock() + 0.45
    end
    WEAPON_WATCH.last_ptr = weapon
    WEAPON_WATCH.last_id = item_id or get_weapon_item_id(weapon) or ""

    if verified and source_tag and source_tag:find("holster_draw", 1, true) then
        STOW.lockout_until = 0
        STOW.reassert_count = 0
        NATIVE_WEAPON_SEL.last_applied_item = item_id or ""
        if source_tag:find("holster_draw_cross", 1, true) then
            finalize_cross_swap_visuals(weapon)
            clear_cross_swap_prev()
        end
        if drawing_from_bare then
            sync_player_gun_combat(weapon, nil, "bare_holster_draw_finalize")
            if NATIVE_WEAPON_SEL.pending_gun_combat_fixup then
                local skip_fixup = STOW.is_chris_player() == true
                    and weapon_type_for_item_id(item_id) == "KNF"
                if not skip_fixup then
                    refresh_components(false)
                    pcall(function()
                        local pg = COMPONENTS.player_gun
                        if not pg then return end
                        pg:call("goActiveTriggerState")
                        pg:call("setupGunActiveData")
                        pg:call("setupGunFireData")
                        STOW.clear_unshootable(pg)
                    end)
                end
                -- Keep gun_fixup_until so tick_weapon_swap_mesh_fixup can re-init
                -- PlayerGun for several frames after checkpoint.
                NATIVE_WEAPON_SEL.pending_gun_combat_fixup = false
                rawset(_G, "__vr_block_bare_hands_aim", false)
                rawset(_G, "__vr_block_shoot_ready", false)
            end
            if equip_manager and os.clock() >= (GRIP.scene_block_until or 0) then
                STOW.call_equip_weapon(equip_manager, weapon)
                pcall(function() equip_manager:call("set_isNoneEquipped", false) end)
            end
        end
        STOW.finalize_equipped_mesh(weapon)
        pcall(function()
            if not managed_object_alive(weapon) then
                return
            end
            if weapon:get_field("BulletBuf") == nil then
                return
            end
            weapon:call("setupBullet")
        end)
        WEAPON_WATCH.draw_flash_weapon = nil
        WEAPON_WATCH.draw_flash_until = 0
        if drawing_from_bare then
            HOLSTER_GUARD.mesh_repair_weapon = weapon
            HOLSTER_GUARD.mesh_repair_until = os.clock() + 2.0
            HOLSTER_GUARD.mesh_repair_started_at = os.clock()
            HOLSTER_GUARD.mesh_repair_last_t = 0
        end
    elseif verified and equipped and weapon and source_tag
        and not source_tag:find("holster", 1, true)
        and not source_tag:find("stow", 1, true) then
        STOW.finalize_equipped_mesh(weapon)
        WEAPON_WATCH.draw_flash_weapon = nil
        WEAPON_WATCH.draw_flash_until = 0
    elseif verified and source_tag and source_tag:find("holster", 1, true)
        and not source_tag:find("holster_guard", 1, true) then
        WEAPON_WATCH.our_equip_until = os.clock() + 0.45
    end

    NATIVE_WEAPON_SEL.equip_in_progress = false
    NATIVE_WEAPON_SEL.equip_cooldown_until = os.clock() + 0.15
    if verified and source_is_holster then
        STOW.clear_pending_weapon_change("holster_equip")
    end
    return verified
end

--- Bridge D-pad / holster draw through the single native equip chain.
local function read_hook_item_id_arg(arg)
    if arg == nil then return nil end
    if type(arg) == "string" then
        local n = normalize_item_id(arg)
        if n and not n:find("REManagedObject", 1, true) then return n end
        return nil
    end
    local ok, s = pcall(function()
        local mobj = sdk.to_managed_object(arg)
        if not mobj then return nil end
        local tname = nil
        pcall(function()
            local td = mobj:get_type_definition()
            if td then tname = td:get_full_name() end
        end)
        if tname == "System.String" then
            local okc, v = pcall(function() return mobj:call("ToString") end)
            if okc and type(v) == "string" and v ~= "" then return v end
        end
        -- Prefer real System.String contents; never trust tostring(managed).
        for _, field in ipairs({ "mString", "_string", "m_string" }) do
            local okf, v = pcall(function() return mobj:get_field(field) end)
            if okf and type(v) == "string" and v ~= "" then return v end
        end
        local okc, v2 = pcall(function() return mobj:call("ToString") end)
        if okc and type(v2) == "string" and v2 ~= "" and not v2:find("REManagedObject", 1, true) then
            return v2
        end
        return nil
    end)
    if not ok or type(s) ~= "string" or s == "" then return nil end
    if s:find("REManagedObject", 1, true) then return nil end
    return normalize_item_id(s)
end

local function fly_api()
    local fly = rawget(_G, "__re8_fly_api")
    if type(fly) == "table" then return fly end
    return nil
end

local function lua_medicine_busy()
    if rawget(_G, "__re8_medicine_in_hand") == true then return true end
    local fly = fly_api()
    if fly and fly.active == true and fly.slot == "medicine" then return true end
    local pub = rawget(_G, "__re8_holster_fly")
    return type(pub) == "table" and pub.active == true and pub.slot == "medicine"
end

STOW.equip_excluded_native = function(weapon, item_id)
    if STOW.player_dead() then return false end
    if NATIVE_WEAPON_SEL.excluded_equip_in_progress then return false end
    item_id = normalize_item_id(item_id)
    if not item_id then return false end
    if not is_holster_excluded_weapon(weapon, item_id) then return false end
    NATIVE_WEAPON_SEL.excluded_equip_in_progress = true
    local ok = false
    local from_bare_eq = false
    pcall(function()
        refresh_components(false)
        local row = find_row_for_item_id(item_id)
        local w = weapon
        if (not w or not managed_object_alive(w)) and row then
            w = row.weapon
        end
        if not w or not managed_object_alive(w) then return end
        local prev = re8vr and re8vr.weapon
        if prev and prev ~= w and managed_object_alive(prev) then
            STOW.hide_orphan_visual(prev)
        end
        local hand = get_right_hand_enum()
        local wc = COMPONENTS.weapon_change
        local em = COMPONENTS.equip_manager
        local mc = COMPONENTS.mesh_controller
        local item_internal = row and row.item_internal or nil
        local still_hand = is_bare_hands() == true
        if still_hand then
            clear_hand_equip_state_before_weapon(em)
            force_clear_player_gun_combat(prev, "excluded_from_bare")
            sync_native_dpad_selection_for_item(item_id)
            sync_inventory_select_for_item(item_id)
            if re8vr.inventory then
                pcall(function() re8vr.inventory:call("equipWeapon", item_id) end)
            end
        end
        if wc then
            pcall(function() wc:call("equipWeapon", w, false) end)
        end
        if em then
            STOW.call_equip_weapon(em, w)
            pcall(function() em:call("set_equipWeaponRight", w) end)
            pcall(function() em:call("set_isNoneEquipped", false) end)
        end
        local player_go = re8vr and re8vr.player
        if player_go then
            pcall(function() w:call("onEquip", player_go, hand) end)
        end
        pcall(function() w:call("set_isEquip", true) end)
        if re8vr and weapon_safe_for_re8vr(w) then
            re8vr.weapon = w
        end
        if wc then
            pcall(function() wc:call("setWeaponDisp", true) end)
        end
        if mc and managed_object_alive(mc) then
            local pmc_prev = prev
            if pmc_prev == w then pmc_prev = nil end
            pcall(function() mc:call("onEquipWeaponChanged", w, pmc_prev) end)
            pcall(function()
                local mesh_go = mc:call("get_weaponMeshObject")
                if mesh_go and managed_object_alive(mesh_go) then
                    mesh_go:call("setActive", true)
                end
            end)
            pcall(function() mc:call("updateParts") end)
        end
        pcall(function() w:call("disp", true) end)
        pcall(function()
            local go = w:call("get_GameObject")
            if go then go:call("setActive", true) end
        end)
        STOW.start_weapon_behavior(w, still_hand and not STOW.is_inventory_native_tool(w, item_id))
        if still_hand then
            from_bare_eq = true
            pcall(function() w:call("gatherComponents") end)
            pcall(function()
                local idle_id = nil
                local td = sdk.find_type_definition("app.Weapon.MotionID")
                if td then
                    local f = td:get_field("Idle")
                    if f then idle_id = f:get_data(nil) end
                end
                if not STOW.is_inventory_native_tool(w, item_id) then
                    if idle_id ~= nil then
                        w:call("requestMotion(app.Weapon.MotionID, System.Single)", idle_id, 0.0)
                    else
                        w:call("requestMotion(System.String, System.Single)", "Idle", 0.0)
                    end
                end
            end)
            if STOW.is_inventory_native_tool(w, item_id) then
            elseif STOW._is_ads_melee_utility(w, item_id) then
                STOW.bind_ads_melee_player_layer(w, prev, item_internal)
            elseif STOW._is_throwable_utility(w, item_id) then
                STOW.bind_throwable_player_layer(w, prev, item_internal)
            end
        end
        WEAPON_WATCH.last_ptr = w
        WEAPON_WATCH.last_id = item_id
        if re8vr and weapon_safe_for_re8vr(w) then
            re8vr.weapon = w
        end
        local P = get_profile()
        if P then
            P.last_utility_id = item_id
            clear_item_from_other_slots(P, "utility", item_id)
        end
        ok = true
        if STOW.is_chris_player() == true then
            STOW._chris_held_t = 0
            STOW.fix_chris_held_item_opaque(w)
        end
        if is_bare_hands() then
            WEAPON_WATCH.our_equip_until = 0
        else
            WEAPON_WATCH.our_equip_until = os.clock() + 0.45
        end
    end)
    NATIVE_WEAPON_SEL.excluded_equip_in_progress = false
    if ok and not is_bare_hands() then
        NATIVE_WEAPON_SEL.last_apply_t = os.clock()
        NATIVE_WEAPON_SEL.last_applied_item = item_id or ""
        NATIVE_WEAPON_SEL.pending_bare_qs = nil
    end
    return ok
end

STOW.try_finish_excluded_inv_equip = function(item_id)
    if NATIVE_WEAPON_SEL.excluded_equip_in_progress then return end
    item_id = normalize_item_id(item_id)
    if not item_id or not is_holster_excluded_weapon(nil, item_id) then return end
    local row = find_row_for_item_id(item_id)
    local w = row and row.weapon or nil
    local already = false
    if w and managed_object_alive(w) then
        pcall(function() already = w:call("get_isEquip") == true end)
    end
    local native_tool = STOW.is_inventory_native_tool(w, item_id)
    if native_tool then
        if already then
            WEAPON_WATCH.last_ptr = w
            WEAPON_WATCH.last_id = item_id
            if re8vr and weapon_safe_for_re8vr(w) then
                re8vr.weapon = w
            end
        end
        return
    end
    if already then
        WEAPON_WATCH.last_ptr = w
        WEAPON_WATCH.last_id = item_id
        if re8vr and weapon_safe_for_re8vr(w) then
            re8vr.weapon = w
        end
        return
    end
    if not is_bare_hands() then
        local cur = get_current_weapon_item_id()
        if not cur or normalize_item_id(cur) ~= item_id then return end
    end
    STOW.equip_excluded_native(w, item_id)
end

local function apply_dpad_weapon_equip(item_internal, item_id, slot_no, source)
    if not item_id or item_id == "" then return false end
    if not re8vr.inventory or not managed_object_alive(re8vr.inventory) then return false end
    if NATIVE_WEAPON_SEL.equip_in_progress then
        return false
    end
    if os.clock() < (NATIVE_WEAPON_SEL.equip_cooldown_until or 0) then return false end
    clear_stow_bare_locks()
    WEAPON_WATCH.stow_flash_until = 0
    WEAPON_WATCH.stow_flash_weapon = nil
    if item_internal and not managed_object_alive(item_internal) then return false end
    local weapon = get_item_weapon(item_internal)
    if not weapon or not weapon_component_usable(weapon) then
        local row = find_row_for_item_id(item_id)
        if row then
            weapon = row.weapon
            if row.item_internal then item_internal = row.item_internal end
        end
    end
    if not weapon or not weapon_component_usable(weapon) then return false end
    pcall(function()
        if weapon_type_for_item_id(item_id) == "MED" then return end
        if STOW.is_inventory_native_tool(weapon, item_id) then return end
        local fn = rawget(_G, "__re8_heal_abort_native_use")
        if type(fn) == "function" then fn() end
    end)
    local fly = fly_api()
    local med_busy = lua_medicine_busy()
    if med_busy then
        if fly and fly.active == true and fly.slot == "medicine" then
            fly._skip_med_attach = true
            fly.cancel("dpad_med")
        end
        rawset(_G, "__re8_medicine_in_hand", false)
        if fly and type(fly.clear_bridge) == "function" then
            fly.clear_bridge()
        end
    end

    local function after_med()
        if fly and type(fly.return_medicine_to_holster) == "function" then
            fly.return_medicine_to_holster("dpad_after_equip")
        elseif lua_medicine_busy() then
            rawset(_G, "__re8_medicine_in_hand", false)
            if fly and type(fly.clear_bridge) == "function" then
                fly.clear_bridge()
            end
        end
    end

    if is_holster_excluded_weapon(weapon, item_id) then
        local use_active = rawget(_G, "__re8_heal_is_native_use_active")
        if STOW.is_inventory_native_tool(weapon, item_id)
            and type(use_active) == "function" and use_active() == true then
            WEAPON_WATCH.last_ptr = weapon
            WEAPON_WATCH.last_id = item_id
            if re8vr and weapon_safe_for_re8vr(weapon) then
                re8vr.weapon = weapon
            end
            after_med()
            return true
        end
        local already = false
        pcall(function() already = weapon:call("get_isEquip") == true end)
        local ok = already
        if already then
            WEAPON_WATCH.last_ptr = weapon
            WEAPON_WATCH.last_id = item_id
            if re8vr and weapon_safe_for_re8vr(weapon) then
                re8vr.weapon = weapon
            end
        else
            ok = STOW.equip_excluded_native(weapon, item_id)
        end
        if ok and not is_bare_hands() then
            NATIVE_WEAPON_SEL.last_apply_t = os.clock()
            NATIVE_WEAPON_SEL.last_applied_item = item_id
            NATIVE_WEAPON_SEL.last_quick_slot = slot_no
            NATIVE_WEAPON_SEL.pending_bare_qs = nil
        elseif slot_no ~= nil then
            NATIVE_WEAPON_SEL.last_quick_slot = slot_no
        end
        after_med()
        return ok
    end

    local ok = native_equip(item_internal, weapon, source or "dpad")
    after_med()
    if ok and not is_bare_hands() then
        NATIVE_WEAPON_SEL.last_apply_t = os.clock()
        NATIVE_WEAPON_SEL.last_applied_item = item_id
        NATIVE_WEAPON_SEL.last_quick_slot = slot_no
        NATIVE_WEAPON_SEL.pending_bare_qs = nil
    elseif slot_no ~= nil then
        NATIVE_WEAPON_SEL.last_quick_slot = slot_no
    end
    return ok
end


local function try_armed_dpad_equip()
    local slot_no, source = read_active_dpad_quickslot()
    local wc_req = native_weapon_change_requested()
    local flags = ""
    local req_id = ""
    local ism_sel = nil
    local qs_sel = nil
    do
        local wc = COMPONENTS.weapon_change
        if wc then
            local function flag(name, key)
                if VRZ.waiting(name) then return end -- Visceral RE8: failed a moment ago (loading)
                local r = nil
                pcall(function() r = wc:call(name) end)
                if r == nil then VRZ.failed(name) end
                if r == true then flags = flags .. key end
            end
            flag("isShortWeaponEquipRequested", "S")
            flag("isLongWeaponEquipRequested", "L")
            flag("isRequestedBothHandToOneHand", "B1")
            flag("isRequestedOneHandToBothHand", "O2")
            flag("isRequestedBothHandToBothHand", "B2")
            flag("get_isGetWeapon", "G")
            pcall(function()
                local ri = wc:call("get_RequestedItem")
                if ri then req_id = tostring(get_item_data_id(ri) or "") end
            end)
        end
        pcall(function()
            if not re8vr.inventory then return end
            local ism = re8vr.inventory:call("get_ItemSlotManager")
            if not ism then return end
            ism_sel = ism:call("getSelectItemSlotNo")
            pcall(function() qs_sel = ism:call("getQuickSlotNo") end)
            if qs_sel == nil then
                pcall(function() qs_sel = ism:call("get_QuickSlotNo") end)
            end
            if qs_sel == nil and ism_sel ~= nil then
                pcall(function() qs_sel = ism:call("itemSlotNo2QuickSlotNo", ism_sel) end)
            end
        end)
    end
    -- ISM select edge: native D-pad often updates inventory selection without
    -- leaving a held VR action for Lua to see.
    if slot_no == nil and qs_sel ~= nil then
        local prev_qs = NATIVE_WEAPON_SEL.last_quick_slot
        if prev_qs ~= nil and qs_sel ~= prev_qs then
            slot_no = qs_sel
            source = "ism_qs_edge"
        end
    end
    if slot_no == nil and ism_sel ~= nil then
        local prev_sel = NATIVE_WEAPON_SEL.last_select_slot
        if prev_sel ~= nil and ism_sel ~= prev_sel then
            local mapped = nil
            pcall(function()
                local ism = re8vr.inventory and re8vr.inventory:call("get_ItemSlotManager")
                if ism then mapped = ism:call("itemSlotNo2QuickSlotNo", ism_sel) end
            end)
            if mapped ~= nil then
                slot_no = mapped
                source = "ism_sel_edge"
            end
        end
        NATIVE_WEAPON_SEL.last_select_slot = ism_sel
    end
    if is_bare_hands() then return false end
    if NATIVE_WEAPON_SEL.motion0_left then
        NATIVE_WEAPON_SEL.native_dpad_until = os.clock() + 0.6
        return true
    end
    -- Sticky swap: holster weapon still equipped, D-pad target in RequestedItem.
    -- This path used to return without arming orphan detach — that left the
    -- previous holster gun mesh stuck on RH after native equip of the new gun.
    if wc_req and req_id ~= "" then
        local cur0 = get_current_weapon_item_id() or ""
        if cur0 ~= "" and normalize_item_id(req_id) ~= normalize_item_id(cur0) then
            local old_weapon = get_active_weapon_object() or (re8vr and re8vr.weapon) or WEAPON_WATCH.last_ptr
            NATIVE_WEAPON_SEL.native_dpad_until = os.clock() + 1.8
            WEAPON_WATCH.our_equip_until = 0
            HOLSTER_GUARD.mesh_repair_until = 0
            clear_holster_equip_guard("armed_dpad_sticky")
            STOW.arm_dpad_orphan(old_weapon, cur0, req_id, "sticky_wc")
            return true
        end
    end
    local item_id = nil
    if slot_no ~= nil then
        item_id = select(2, get_item_id_from_quickslot(slot_no))
        if (not item_id or item_id == "") then
        end
    end
    local cur = get_current_weapon_item_id()
    local wants_other = item_id and item_id ~= "" and (not cur or normalize_item_id(cur) ~= normalize_item_id(item_id))
    if not wants_other then return false end
    local old_weapon = get_active_weapon_object() or (re8vr and re8vr.weapon) or WEAPON_WATCH.last_ptr
    local old_id = cur or WEAPON_WATCH.last_id or ""
    clear_holster_equip_guard("armed_dpad")
    HOLSTER_GUARD.draw_native_suppress_until = 0
    HOLSTER_GUARD.mesh_repair_until = 0
    WEAPON_WATCH.our_equip_until = 0
    STOW.native_suppress_until = 0
    NATIVE_WEAPON_SEL.native_dpad_until = os.clock() + 1.8
    STOW.arm_dpad_orphan(old_weapon, old_id, item_id, source or "armed_dpad")
    if slot_no ~= nil then
        NATIVE_WEAPON_SEL.last_quick_slot = slot_no
    end
    return true
end

local function tick_native_weapon_selection()
    if try_armed_dpad_equip() then return end
    local med_busy = lua_medicine_busy()
    local now_t = os.clock()
    local fly = fly_api()
    local fly_busy = fly and fly.active == true
    local fly_stow = fly_busy and fly.kind == "stow"
    local pending_unequip = type(STOW.holster_unequip_id) == "string" and STOW.holster_unequip_id ~= ""
    -- Stow fly still has the old weapon equipped; peek D-pad anyway so the
    -- press is not eaten by suppress / "not bare" and native equip can run.
    if is_bare_hands() or fly_stow or pending_unequip then
        local peek_qs = select(1, read_active_dpad_quickslot())
        if peek_qs ~= nil then
            NATIVE_WEAPON_SEL.pending_bare_qs = peek_qs
        end
    else
        NATIVE_WEAPON_SEL.pending_bare_qs = nil
    end
    local pending_once = (is_bare_hands() or fly_stow or pending_unequip)
        and NATIVE_WEAPON_SEL.pending_bare_qs ~= nil
    if fly_busy and not fly_stow then
        return
    end
    if not med_busy then
        if holster_guard_active() then return end
        if NATIVE_WEAPON_SEL.equip_in_progress then return end
        if now_t < STOW.native_suppress_until and not pending_once then return end
        if now_t < HOLSTER_GUARD.draw_native_suppress_until and not pending_once then return end
        if not pending_once and now_t < WEAPON_WATCH.our_equip_until then return end
    end
    if not re8vr.inventory or not managed_object_alive(re8vr.inventory) then return end
    -- D-pad must still run while lua medicine is held: the bottle can look like
    -- an active weapon object and would otherwise skip native slot apply.
    -- Bare + Hand ID can still have a stale EM pointer; do not treat that as armed.
    -- Stow fly is still "armed" with the weapon being holstered.
    if get_active_weapon_object() and not med_busy and not is_bare_hands()
        and not fly_stow and not pending_unequip then
        NATIVE_WEAPON_SEL.last_quick_slot = nil
        NATIVE_WEAPON_SEL.pending_bare_qs = nil
        return
    end
    if not is_bare_hands() and not med_busy and not fly_stow and not pending_unequip then
        return
    end
    if not med_busy then
        if not pending_once and now_t < STOW.lockout_until then
            return
        end
        if now_t - (NATIVE_WEAPON_SEL.last_apply_t or 0) < 0.40 then
            return
        end
    end

    local slot_no, source = read_active_dpad_quickslot()
    if slot_no ~= nil then
        if not med_busy and not pending_once
            and NATIVE_WEAPON_SEL.last_quick_slot == slot_no
            and (now_t - (NATIVE_WEAPON_SEL.last_apply_t or 0)) < 1.0 then
            return
        end
    elseif pending_once then
        slot_no = NATIVE_WEAPON_SEL.pending_bare_qs
        source = "pending_bare"
    else
        -- Edge: selection may change without our seeing press this frame; poll ISM as backup.
        local select_slot = nil
        pcall(function()
            local ism = re8vr.inventory and re8vr.inventory:call("get_ItemSlotManager")
            if ism then select_slot = ism:call("getSelectItemSlotNo") end
        end)
        if select_slot == nil then return end
        local changed = NATIVE_WEAPON_SEL.last_select_slot ~= nil
            and select_slot ~= NATIVE_WEAPON_SEL.last_select_slot
        NATIVE_WEAPON_SEL.last_select_slot = select_slot
        if not changed then return end
        local qs_no = nil
        pcall(function()
            local ism = re8vr.inventory:call("get_ItemSlotManager")
            if ism then qs_no = ism:call("itemSlotNo2QuickSlotNo", select_slot) end
        end)
        if qs_no == nil then
            return
        end
        slot_no = qs_no
        source = "ism_select"
    end

    local item_internal, item_id = get_item_id_from_quickslot(slot_no)
    if not item_id or item_id == "" then
        return
    end
    if weapon_type_for_item_id(item_id) == "MED" then return end

    apply_dpad_weapon_equip(item_internal, item_id, slot_no, source)
    NATIVE_WEAPON_SEL.pending_bare_qs = nil
end

--- Fallback manual de-equip if WeaponID.Hand equip fails.
local function native_stow_chain(weapon)
    if not weapon then return false end
    refresh_components(false)
    local weapon_change = COMPONENTS.weapon_change
    local equip_manager = COMPONENTS.equip_manager
    local mesh_controller = COMPONENTS.mesh_controller
    if not weapon_change then return false end

    pcall(function() weapon_change:call("removeWeaponWithNoAction") end)
    pcall(function() weapon_change:call("removeWeapon", false) end)

    if mesh_controller then
        pcall(function() mesh_controller:call("onEquipWeaponChanged", nil, weapon) end)
        pcall(function()
            local mesh_go = mesh_controller:call("get_weaponMeshObject")
            if mesh_go then mesh_go:call("setActive", false) end
        end)
    end

    if equip_manager then
        pcall(function()
            local cur = equip_manager:get_field("<equipWeaponRight>k__BackingField")
            if cur == weapon then
                equip_manager:call("set_equipWeaponRight", nil)
            end
        end)
    end

    pcall(function() weapon_change:call("setWeaponDisp", false) end)
    pcall(function() weapon:call("disp", false) end)
    native_equip_bare_hands_id(weapon)

    return true
end

-- Utility/saw/grenade must not use native_stow (PlayerGun). offEquip is
-- only for these excluded items — never holster guns/knives.
STOW.unequip_excluded_weapon = function(weapon)
    if not weapon then
        weapon = get_active_weapon_object() or (re8vr and re8vr.weapon)
    end
    if not weapon or not managed_object_alive(weapon) then
        return is_bare_hands() == true
    end
    local item_id = get_weapon_item_id(weapon)
    if not is_holster_excluded_weapon(weapon, item_id) then
        return false
    end
    pcall(function()
        if not managed_object_alive(weapon) then return end
        weapon:call("offEquip")
        weapon:call("set_isEquip", false)
    end)
    STOW.hide_orphan_visual(weapon)
    local ok = native_equip_bare_hands_id(weapon)
    if not is_bare_hands() then
        native_stow_chain(weapon)
        STOW.hide_orphan_visual(weapon)
    end
    if re8vr and re8vr.weapon == weapon then
        re8vr.weapon = nil
    end
    sanitize_re8vr_weapon_pointer()
    return is_bare_hands() or ok == true
end

local function native_stow_lockout_reassert(weapon)
    native_equip_bare_hands_id(weapon or get_active_weapon_object() or re8vr.weapon)
end

local function native_stow()
    if not refresh_components(false) then return false end
    local weapon = get_active_weapon_object() or re8vr.weapon
    if not weapon then return true end
    if is_holster_excluded_weapon(weapon) then return false end

    -- Capture weapon GO/mesh state before any Hand switch (draw leaves these Active).
    local mesh_was_active = nil
    local go_was_active = nil
    pcall(function()
        local mc = COMPONENTS.mesh_controller
        if mc then
            local mesh_go = mc:call("get_weaponMeshObject")
            if mesh_go then mesh_was_active = mesh_go:call("get_Active") end
        end
    end)
    pcall(function()
        local go = weapon:call("get_GameObject")
        if go then go_was_active = go:call("get_Active") end
    end)

    local stow_item_id = get_weapon_item_id(weapon) or ""
    WEAPON_WATCH.stow_lockout_weapon_id = stow_item_id
    STOW.arm_flash(weapon)
    local hand_id_primary = native_equip_bare_hands_id(weapon)
    if not hand_id_primary and not is_bare_hands() then
        native_stow_chain(weapon)
    end

    -- Hide before pointer refresh; update_pointers can briefly resurrect weapon refs.
    pcall(function() weapon:call("disp", false) end)
    pcall(function()
        local go = weapon:call("get_GameObject")
        if go then go:call("setActive", false) end
    end)
    if COMPONENTS.mesh_controller then
        pcall(function()
            local mesh_go = COMPONENTS.mesh_controller:call("get_weaponMeshObject")
            if mesh_go then mesh_go:call("setActive", false) end
        end)
    end
    if COMPONENTS.weapon_change then
        pcall(function() COMPONENTS.weapon_change:call("setWeaponDisp", false) end)
    end

    if re8vr.update_pointers then
        pcall(function() re8vr:update_pointers() end)
    end
    sync_re8vr_weapon_pointer(nil)
    sanitize_re8vr_weapon_pointer()

    -- Final hide pass after pointers refresh.
    hide_weapon_visuals(weapon)

    STOW.lockout_until = os.clock() + 0.5
    STOW.reassert_count = 0
    STOW.native_suppress_until = os.clock() + 1.25
    clear_holster_equip_guard("stow")
    NATIVE_WEAPON_SEL.last_quick_slot = nil
    NATIVE_WEAPON_SEL.last_select_slot = nil
    NATIVE_WEAPON_SEL.last_applied_item = ""
    return true
end

local function enforce_stow_lockout()
    if os.clock() >= STOW.lockout_until then return end
    if os.clock() < WEAPON_WATCH.our_equip_until then return end
    if os.clock() < STOW.native_suppress_until then return end
    if holster_guard_active() then return end
    if is_bare_hands() then return end
    if re8vr.weapon == nil then return end

    local weapon = get_active_weapon_object() or re8vr.weapon
    if not weapon then return end
    local cur_id = get_weapon_item_id(weapon) or ""
    if WEAPON_WATCH.stow_lockout_weapon_id == ""
        or cur_id == ""
        or normalize_item_id(cur_id) ~= normalize_item_id(WEAPON_WATCH.stow_lockout_weapon_id) then
        return
    end

    STOW.reassert_count = STOW.reassert_count + 1
    native_stow_lockout_reassert(weapon)

    if re8vr.update_pointers then
        pcall(function() re8vr:update_pointers() end)
    end
    sanitize_re8vr_weapon_pointer()
end

local unequip_current_to_bare_hands

local function equip_weapon_from_profile(P, slot, phase)
    if slot == "utility" then return false end
    local item_id = resolve_profile_item_id(P, slot)
    if not item_id then
        reconcile_holster_slot_cache(P, slot)
        item_id = resolve_profile_item_id(P, slot)
    end
    if not item_id then
        return false
    end

    local cur_id = get_current_weapon_item_id()
    local row = find_row_for_item_id(item_id)

    -- Checkpoint/load can report this weapon already equipped while the
    -- in-hand mesh is still hidden. Never skip native holster equip.

    if not row or not row.weapon then
        return false
    end

    local row_weapon_id = get_weapon_item_id(row.weapon)
    if row_weapon_id and item_id and normalize_item_id(row_weapon_id) ~= normalize_item_id(item_id) then
        return false
    end

    local function holster_equip_row(row_local, item_id_local, source_tag)
        clear_stow_bare_locks()
        return apply_dpad_weapon_equip(row_local.item_internal, item_id_local, nil, source_tag)
    end

    if phase == 2 then
        if STOW.is_chris_player() == true then
            local ok = holster_equip_row(row, item_id, "holster_draw_p1")
            if ok and row.weapon then STOW.finalize_equipped_mesh(row.weapon) end
            return ok
        end
        local cross_prev = peek_cross_swap_prev()
        if cross_prev and managed_object_alive(cross_prev) then
            hide_weapon_visuals(cross_prev)
        end
        local ok = holster_equip_row(row, item_id, "holster_draw_p2")
        if ok and row.weapon then STOW.finalize_equipped_mesh(row.weapon) end
        return ok
    end

    local active_weapon = get_active_weapon_object()
        local active_slot = get_holster_slot_for_active_weapon()
    local armed = active_weapon ~= nil and not is_bare_hands()
    local different_target = cur_id and item_id
        and normalize_item_id(cur_id) ~= normalize_item_id(item_id)
    -- Cross-swap whenever armed with a different weapon — even if home slot is unknown (burner/etc).
    local need_cross = armed and different_target
        and ((active_slot ~= nil and active_slot ~= slot) or active_slot == nil)
    if need_cross then
        if cur_id and (active_slot == "utility" or is_holster_excluded_weapon(active_weapon, cur_id)) then
            cache_weapon_to_profile(P, cur_id, "utility")
            STOW.unequip_excluded_weapon(active_weapon)
            local ok = holster_equip_row(row, item_id, "holster_draw_p1")
            if ok and row.weapon then STOW.finalize_equipped_mesh(row.weapon) end
            return ok
        end
        if cur_id then
            cache_weapon_to_profile(P, cur_id, active_slot)
        end
        if STOW.is_chris_player() == true then
            -- Chris checkpoint leaves a native gun in-hand. holster_draw_cross
            -- tears down PlayerMeshController WeaponMesh; the holster item
            -- verifies equipped but never shows in the VR hand.
            unequip_current_to_bare_hands(active_slot)
            -- Same-frame knife equip after shotgun stow leaves WeaponMesh empty.
            return "defer"
        end
        capture_cross_swap_prev(active_weapon, cur_id)
        local ok = holster_equip_row(row, item_id, "holster_draw_cross")
        clear_cross_swap_prev()
        if ok and row.weapon then STOW.finalize_equipped_mesh(row.weapon) end
        return ok
    end

    local ok = holster_equip_row(row, item_id, "holster_draw_p1")
    if ok and row.weapon then STOW.finalize_equipped_mesh(row.weapon) end
    return ok
end

unequip_current_to_bare_hands = function(preferred_slot)
    clear_holster_equip_guard("stow_intent")
    local weapon = get_active_weapon_object() or re8vr.weapon
    if not weapon then return false end
    local P = get_profile()
    local item_id = resolve_equipped_item_id(weapon)
    if not item_id then
        for _, row in ipairs(inventory_rows()) do
            if row.weapon == weapon then
                item_id = normalize_item_id(row.item_id)
                break
            end
        end
    end
    item_id = normalize_item_id(item_id)
    if item_id then
        cache_weapon_to_profile(P, item_id, preferred_slot)
        save_cfg()
    else
        local slot = preferred_slot or fallback_slot_from_weapon_type(weapon)
        if slot then
            reconcile_holster_slot_cache(P, slot)
        end
    end
    local ok = native_stow()
    return ok
end
-- Visceral RE8 (2026-10-25): visceral_re8_holsters.lua puts the gun away when the right grip lets go (Tefa: "RG needed to
-- actually hold the gun in hand"); it uses this proven stow instead of an untested one of its own.
rawset(_G, "__re8_holster_stow_to_bare", function(slot) return unequip_current_to_bare_hands(slot) == true end)
-- Visceral RE8 2026-10-31: the same proven native equip the D-pad path uses, for visceral_re8_holsters.lua's body spots
-- (its own set_RequestedItem never brought a gun out).
rawset(_G, "__re8_holster_equip_item", function(item_internal, source)
    local weapon = item_internal and get_item_weapon(item_internal)
    if not weapon then return false end
    return native_equip(item_internal, weapon, source or "visceral body spot") == true
end)

local HOLSTER_ACTION = { pending = nil, shoot_until = 0 }

-- Forward-declare: FLY methods close over these locals (filled below).
local HJ
local holster_transforms = {
    torso_pos = nil, right = nil, up = nil, fwd = nil, t = 0,
    src = "",
}

-- World-space holster fly (hip pistol + knife). Table methods keep locals under limit.
local FLY = {
    active = false,
    kind = nil,
    slot = nil,
    t0 = 0,
    dur = 0.20,
    sx = 0, sy = 0, sz = 0,
    sq = nil,
    eq = nil,
}
rawset(_G, "__re8_fly_api", FLY)

function FLY.slot_ok(slot)
    return slot == "pistol" or slot == "knife" or slot == "medicine" or slot == "longarm"
end

function FLY.clear_medicine_hold(_reason)
    if rawget(_G, "__re8_medicine_in_hand") ~= true then return false end
    rawset(_G, "__re8_medicine_in_hand", false)
    return true
end

function FLY.stow_weapon_before_medicine(_reason)
    if is_bare_hands() then return false end
    local weapon = get_active_weapon_object() or (re8vr and re8vr.weapon)
    local item_id = weapon and get_weapon_item_id(weapon) or get_current_weapon_item_id()
    if is_holster_excluded_weapon(weapon, item_id) then
        local P = get_profile()
        if item_id then
            cache_weapon_to_profile(P, item_id, "utility")
            save_cfg()
        end
        return STOW.unequip_excluded_weapon(weapon) == true
    end
    local slot = get_effective_holster_slot_for_cur_weapon()
    return unequip_current_to_bare_hands(slot) == true
end

function FLY.ease(t)
    local u = math.max(0.0, math.min(1.0, tonumber(t) or 0))
    local inv = 1.0 - u
    return 1.0 - inv * inv * inv
end

function FLY.lerp_pos(ax, ay, az, bx, by, bz, t)
    local u = math.max(0.0, math.min(1.0, t))
    return ax + (bx - ax) * u, ay + (by - ay) * u, az + (bz - az) * u
end

function FLY.quat_tbl(q)
    if not q then return nil end
    local w, x, y, z = nil, nil, nil, nil
    pcall(function()
        w, x, y, z = q.w, q.x, q.y, q.z
    end)
    if type(w) ~= "number" then return nil end
    return { w = w, x = x or 0, y = y or 0, z = z or 0 }
end

function FLY.nlerp(a, b, t)
    if not a then return b end
    if not b then return a end
    local u = math.max(0.0, math.min(1.0, t))
    local aw, ax, ay, az = a.w, a.x or 0, a.y or 0, a.z or 0
    local bw, bx, by, bz = b.w, b.x or 0, b.y or 0, b.z or 0
    if (aw * bw + ax * bx + ay * by + az * bz) < 0.0 then
        bw, bx, by, bz = -bw, -bx, -by, -bz
    end
    local w = aw + (bw - aw) * u
    local x = ax + (bx - ax) * u
    local y = ay + (by - ay) * u
    local z = az + (bz - az) * u
    local len = math.sqrt(w * w + x * x + y * y + z * z)
    if not len or len < 1e-8 then return { w = 1, x = 0, y = 0, z = 0 } end
    return { w = w / len, x = x / len, y = y / len, z = z / len }
end

function FLY.hand_rot()
    local q = nil
    pcall(function()
        if re8vr and re8vr.right_hand_ik_transform then
            q = re8vr.right_hand_ik_transform:call("get_Rotation")
        end
    end)
    if not q and vrmod then
        pcall(function()
            local m = vrmod:get_transform(HJ.rh_ctrl_idx())
            if m and m.to_quat then q = m:to_quat() end
        end)
    end
    return FLY.quat_tbl(q)
end

-- Sample candidate hand-end targets for fly (wrist/IK vs held weapon mesh).
function FLY.sample_hand_candidates()
    local hand, hand_src = HJ.get_right_hand_world()
    local out = {
        hand_src = hand_src or "none",
        has_hand = hand ~= nil and type(hand.x) == "number",
        hx = hand and hand.x or nil,
        hy = hand and hand.y or nil,
        hz = hand and hand.z or nil,
        has_wmo = false,
        has_wgo = false,
        d_hand_wmo = nil,
        d_hand_wgo = nil,
    }
    refresh_components(false)
    local mc = COMPONENTS.mesh_controller
    if mc and managed_object_alive(mc) then
        pcall(function()
            local mo = mc:call("get_weaponMeshObject")
            if not mo or not managed_object_alive(mo) then return end
            local active = mo:call("get_Active")
            local t = mo:call("get_Transform")
            local p = t and t:call("get_Position")
            if p and type(p.x) == "number" then
                out.has_wmo = true
                out.wmo_active = active == true
                out.wx, out.wy, out.wz = p.x, p.y, p.z
                if out.has_hand then
                    local dx = p.x - hand.x
                    local dy = p.y - hand.y
                    local dz = p.z - hand.z
                    out.d_hand_wmo = math.sqrt(dx * dx + dy * dy + dz * dz)
                    out.dx_wmo, out.dy_wmo, out.dz_wmo = dx, dy, dz
                end
            end
        end)
    end
    if re8vr and re8vr.weapon then
        pcall(function()
            local go = re8vr.weapon:call("get_GameObject")
            if not go then return end
            local t = go:call("get_Transform")
            local p = t and t:call("get_Position")
            if p and type(p.x) == "number" then
                out.has_wgo = true
                out.gx, out.gy, out.gz = p.x, p.y, p.z
                if out.has_hand then
                    local dx = p.x - hand.x
                    local dy = p.y - hand.y
                    local dz = p.z - hand.z
                    out.d_hand_wgo = math.sqrt(dx * dx + dy * dy + dz * dz)
                    out.dx_wgo, out.dy_wgo, out.dz_wgo = dx, dy, dz
                end
            end
        end)
    end
    -- Hand-local offset of WMO (if both exist) for later apply on bare-hand draw.
    if out.has_hand and out.has_wmo and re8vr and re8vr.right_hand_ik_transform then
        pcall(function()
            local tf = re8vr.right_hand_ik_transform
            local rx = tf:call("get_AxisX")
            local ry = tf:call("get_AxisY")
            local rz = tf:call("get_AxisZ")
            if rx and ry and rz then
                out.off_r = out.dx_wmo * rx.x + out.dy_wmo * rx.y + out.dz_wmo * rx.z
                out.off_u = out.dx_wmo * ry.x + out.dy_wmo * ry.y + out.dz_wmo * ry.z
                out.off_f = out.dx_wmo * rz.x + out.dy_wmo * rz.y + out.dz_wmo * rz.z
            end
        end)
    end
    return out, hand
end

-- Learned hand-local offsets (weapon pivot relative to RH IK), per slot.
FLY.hold_off = FLY.hold_off or {}

function FLY.learn_hold_off(slot, cand)
    if not cand or type(cand.off_r) ~= "number" then return end
    -- Ignore tiny / huge deltas (noise or wrong space).
    local d = cand.d_hand_wmo
    if type(d) ~= "number" or d < 0.02 or d > 0.35 then return end
    local key = slot or "_any"
    FLY.hold_off[key] = {
        r = cand.off_r,
        u = cand.off_u or 0,
        f = cand.off_f or 0,
        t = os.clock(),
    }
    FLY.hold_off._any = FLY.hold_off[key]
end

function FLY.hold_off_for(slot)
    local o = (slot and FLY.hold_off[slot]) or FLY.hold_off._any
    if o and type(o.r) == "number" then return o.r, o.u or 0, o.f or 0, "cached" end
    return tonumber(CFG.holster_fly_hold_off_r) or -0.10,
        tonumber(CFG.holster_fly_hold_off_u) or -0.03,
        tonumber(CFG.holster_fly_hold_off_f) or 0.02,
        "cfg"
end

-- World position where the held weapon pivot sits (not the wrist/IK origin).
function FLY.hand_weapon_world(slot)
    if slot == "medicine" then
        local fn = rawget(_G, "__re8_medicine_compute_hold")
        if type(fn) == "function" then
            local hp, rot = fn()
            if hp and type(hp.x) == "number" then
                return hp, "med_hold", { hold_q = FLY.quat_tbl(rot) }
            end
        end
        local hand = select(1, HJ.get_right_hand_world())
        if not hand or type(hand.x) ~= "number" then
            return nil, "none", nil
        end
        return { x = hand.x, y = hand.y, z = hand.z }, "hand_ik", nil
    end
    local cand, hand = FLY.sample_hand_candidates()
    if cand and cand.has_wmo and type(cand.wx) == "number" then
        FLY.learn_hold_off(slot, cand)
        return { x = cand.wx, y = cand.wy, z = cand.wz }, "wmo", cand
    end
    if not hand or type(hand.x) ~= "number" then
        return nil, "none", cand
    end
    local orr, ou, of, osrc = FLY.hold_off_for(slot)
    local rx, ry, rz = nil, nil, nil
    if re8vr and re8vr.right_hand_ik_transform then
        pcall(function()
            local tf = re8vr.right_hand_ik_transform
            rx = tf:call("get_AxisX")
            ry = tf:call("get_AxisY")
            rz = tf:call("get_AxisZ")
        end)
    end
    if rx and ry and rz and type(rx.x) == "number" then
        return {
            x = hand.x + rx.x * orr + ry.x * ou + rz.x * of,
            y = hand.y + rx.y * orr + ry.y * ou + rz.y * of,
            z = hand.z + rx.z * orr + ry.z * ou + rz.z * of,
        }, "hand+" .. osrc, cand
    end
    return { x = hand.x, y = hand.y, z = hand.z }, "hand_ik", cand
end

function FLY.mesh_key(slot)
    if slot == "pistol" then return "__re8_hip_mesh_world" end
    if slot == "medicine" then return "__re8_medicine_mesh_world" end
    return "__re8_knife_mesh_world"
end

function FLY.mesh_pub(slot)
    local key = FLY.mesh_key(slot)
    local m = rawget(_G, key)
    if m and type(m.x) == "number" and type(m.t) == "number" and (os.clock() - m.t) < 0.50 then
        return m
    end
    return nil
end

function FLY.holster_pos(slot)
    local m = FLY.mesh_pub(slot)
    if m and not FLY.active then
        return { x = m.x, y = m.y, z = m.z }, FLY.quat_tbl_from_pub(m)
    end
    local P = get_profile()
    local zone = HJ.slot_world_pos(slot, P)
    if not zone then return nil, nil end
    local tr, tu, tf = nil, nil, nil
    if holster_transforms then
        tr, tu, tf = holster_transforms.right, holster_transforms.up, holster_transforms.fwd
    end
    local computed = HJ.mesh_aligned_from_visual(zone, HJ.probe_visual_for_slot(slot), tr, tu, tf)
    local pos = computed or zone
    return pos, nil
end

function FLY.quat_tbl_from_pub(m)
    if not m or type(m.qw) ~= "number" then return nil end
    return { w = m.qw, x = m.qx or 0, y = m.qy or 0, z = m.qz or 0 }
end

function FLY.clear_pub()
    rawset(_G, "__re8_holster_fly_active", false)
    rawset(_G, "__re8_holster_fly", nil)
end

function FLY.clear_bridge()
    rawset(_G, "__re8_holster_fly_bridge", nil)
end

-- Bridge the one-frame gap after fly ends: draw must keep probe hidden until
-- equip lands; stow must keep probe visible at holster until unequip lands.
function FLY.set_bridge(mode, slot, x, y, z)
    rawset(_G, "__re8_holster_fly_bridge", {
        mode = mode,
        slot = slot,
        until_t = os.clock() + 0.45,
        x = x, y = y, z = z,
        t0 = os.clock(),
    })
end

function FLY.cancel(_reason)
    FLY.active = false
    FLY.kind = nil
    FLY.slot = nil
    FLY.sq = nil
    FLY.eq = nil
    FLY.rot_lerp = false
    FLY.clear_pub()
    if _reason ~= "done" then
        FLY.clear_bridge()
    end
end

function FLY.finish()
    local kind = FLY.kind
    local slot = FLY.slot
    local ex, ey, ez = FLY.ex, FLY.ey, FLY.ez
    FLY.cancel("done")
    if kind == "draw" and slot then
        if slot == "medicine" then
            if FLY._skip_med_attach == true then
                FLY._skip_med_attach = nil
                rawset(_G, "__re8_medicine_in_hand", false)
                FLY.clear_bridge()
                return
            end
            -- Medicine equipWeapon can start the use anim. Keep the bottle as a hand mesh.
            FLY.stow_weapon_before_medicine("fly_finish_med")
            rawset(_G, "__re8_medicine_in_hand", true)
            if FLY.note_med_grab then FLY.note_med_grab() end
            FLY.set_bridge("hold", slot, ex, ey, ez)
            return
        end
        FLY.clear_medicine_hold("fly_finish_" .. tostring(slot))
        -- Do not hide the holster probe here. Chris checkpoint draws can
        -- publish a weapon id before the hand mesh is actually attached.
        HOLSTER_ACTION.pending = { kind = "equip", slot = slot }
    elseif kind == "stow" and slot then
        if slot == "medicine" then
            rawset(_G, "__re8_medicine_in_hand", false)
            FLY.set_bridge("hold", slot, ex, ey, ez)
            return
        end
        -- Keep probe at final holster pose until unequip removes the in-hand mesh.
        FLY.set_bridge("hold", slot, ex, ey, ez)
        local expect_id = FLY.stow_item_id or get_current_weapon_item_id() or ""
        local cur_id = get_current_weapon_item_id()
        if not is_bare_hands() and expect_id ~= "" and cur_id
            and normalize_item_id(cur_id) ~= normalize_item_id(expect_id) then
            STOW.holster_unequip_id = ""
            return
        end
        STOW.holster_unequip_id = expect_id
        HOLSTER_ACTION.pending = { kind = "unequip", slot = slot, expect_id = expect_id }
    end
end

function FLY.publish(x, y, z, q, force_vis)
    local pub = {
        active = true,
        slot = FLY.slot,
        kind = FLY.kind,
        force_vis = force_vis == true,
        x = x, y = y, z = z,
        t = os.clock(),
    }
    if q then
        pub.qw, pub.qx, pub.qy, pub.qz = q.w, q.x, q.y, q.z
    end
    rawset(_G, "__re8_holster_fly_active", true)
    rawset(_G, "__re8_holster_fly", pub)
end

function FLY.start(kind, slot)
    if FLY.active then return false end
    if CFG.holster_fly_enabled == false then return false end
    if not FLY.slot_ok(slot) then return false end
    local hand_wp, hand_src, cand = FLY.hand_weapon_world(slot)
    if not hand_wp or type(hand_wp.x) ~= "number" then return false end
    local hpos, hrot_q = FLY.holster_pos(slot)
    if not hpos then
        -- Allow start from mesh pub even if FLY.active gate blocked holster_pos
        local m = rawget(_G, FLY.mesh_key(slot))
        if m and type(m.x) == "number" then
            hpos = { x = m.x, y = m.y, z = m.z }
            hrot_q = FLY.quat_tbl_from_pub(m)
        end
    end
    if not hpos then return false end
    local hold_q = hrot_q
    local sx, sy, sz, ex, ey, ez
    if kind == "draw" then
        sx, sy, sz = hpos.x, hpos.y, hpos.z
        ex, ey, ez = hand_wp.x, hand_wp.y, hand_wp.z
    elseif kind == "stow" then
        sx, sy, sz = hand_wp.x, hand_wp.y, hand_wp.z
        ex, ey, ez = hpos.x, hpos.y, hpos.z
        if slot == "medicine" then
            local m = FLY.mesh_pub(slot)
            if m and type(m.x) == "number" then
                sx, sy, sz = m.x, m.y, m.z
                if type(m.qw) == "number" then
                    hold_q = FLY.quat_tbl_from_pub(m) or hold_q
                end
            end
        end
    else
        return false
    end
    local sq, eq = hold_q, hold_q
    local rot_lerp = false
    if slot == "medicine" then
        local hq = cand and cand.hold_q
        if kind == "draw" then
            sq, eq = hrot_q, hq or hrot_q
        else
            sq, eq = hold_q, hrot_q
        end
        rot_lerp = (sq ~= nil and eq ~= nil)
    end
    local dur = tonumber(CFG.holster_fly_s) or 0.20
    if slot == "medicine" then
        dur = tonumber(CFG.medicine_fly_s) or 0.28
    end
    if dur < 0.05 then dur = 0.05 end
    if dur > 0.60 then dur = 0.60 end
    FLY._skip_med_attach = nil
    FLY.stow_item_id = nil
    if kind == "stow" then
        FLY.stow_item_id = get_current_weapon_item_id()
            or get_weapon_item_id(get_active_weapon_object() or (re8vr and re8vr.weapon))
            or ""
        local P = get_profile()
        if P and FLY.stow_item_id and FLY.stow_item_id ~= "" then
            cache_weapon_to_profile(P, FLY.stow_item_id, slot)
        end
    end
    FLY.active = true
    FLY.kind = kind
    FLY.slot = slot
    FLY.t0 = os.clock()
    FLY.dur = dur
    FLY.sx, FLY.sy, FLY.sz = sx, sy, sz
    FLY.ex, FLY.ey, FLY.ez = ex, ey, ez
    FLY.sq, FLY.eq = sq, eq
    FLY.rot_lerp = rot_lerp == true
    FLY._mid_logged = nil
    FLY.publish(sx, sy, sz, sq, true)
    local orr, ou, of = FLY.hold_off_for(slot)
    return true
end

function FLY.tick()
    if not FLY.active then return end
    if not re8vr or not re8vr.can_use_hands or re8vr.is_in_cutscene then
        FLY.cancel("scene")
        return
    end
    local age = os.clock() - (FLY.t0 or 0)
    local dur = FLY.dur or 0.20
    if dur < 0.05 then dur = 0.05 end
    local blend = FLY.ease(age / dur)

    -- Live end: draw tracks the palm/weapon; stow tracks the holster mesh.
    local ex, ey, ez = FLY.ex, FLY.ey, FLY.ez
    local eq = FLY.eq or FLY.sq
    local hand_src = nil
    if FLY.kind == "draw" then
        local hand_wp, src, cand = FLY.hand_weapon_world(FLY.slot)
        hand_src = src
        if hand_wp and type(hand_wp.x) == "number" then
            ex, ey, ez = hand_wp.x, hand_wp.y, hand_wp.z
        end
        if FLY.slot == "medicine" and cand and cand.hold_q then
            eq = cand.hold_q
        end
    else
        local P = get_profile()
        local zone = HJ.slot_world_pos(FLY.slot, P)
        if zone then
            local tr, tu, tf = nil, nil, nil
            if holster_transforms then
                tr, tu, tf = holster_transforms.right, holster_transforms.up, holster_transforms.fwd
            end
            local computed = HJ.mesh_aligned_from_visual(
                zone, HJ.probe_visual_for_slot(FLY.slot), tr, tu, tf)
            local hp = computed or zone
            ex, ey, ez = hp.x, hp.y, hp.z
        end
        hand_src = "holster"
    end
    FLY.ex, FLY.ey, FLY.ez = ex, ey, ez
    FLY.eq = eq

    local x, y, z = FLY.lerp_pos(FLY.sx, FLY.sy, FLY.sz, ex, ey, ez, blend)
    local q = FLY.sq
    if FLY.rot_lerp == true then
        q = FLY.nlerp(FLY.sq, eq, blend)
    end
    FLY.publish(x, y, z, q, true)

    if blend > 0.45 and blend < 0.55 and not FLY._mid_logged then
        FLY._mid_logged = true
        local cand = FLY.sample_hand_candidates()
    end

    if age >= dur then
        FLY._mid_logged = nil
        FLY.finish()
    end
end

local function arm_shoot_ready_suppress_after_holster_action()
    if not CFG.suppress_shoot_ready_after_holster_equip then return end
    local dur = tonumber(CFG.suppress_shoot_ready_after_holster_s) or 0.45
    if dur < 0.05 then dur = 0.05 end
    HOLSTER_ACTION.shoot_until = os.clock() + dur
    rawset(_G, "__vr_block_shoot_ready", true)
end

local function tick_shoot_ready_suppress()
    if HOLSTER_ACTION.shoot_until <= 0 then return end
    if not CFG.suppress_shoot_ready_after_holster_equip then
        HOLSTER_ACTION.shoot_until = 0
        rawset(_G, "__vr_block_shoot_ready", false)
        return
    end
    if os.clock() >= HOLSTER_ACTION.shoot_until then
        HOLSTER_ACTION.shoot_until = 0
        rawset(_G, "__vr_block_shoot_ready", false)
    else
        rawset(_G, "__vr_block_shoot_ready", true)
    end
end

local is_menu_blocking

local function execute_pending_action()
    local pa = HOLSTER_ACTION.pending
    if not pa then return end
    if is_menu_blocking() then
        HOLSTER_ACTION.pending = nil
        STOW.holster_unequip_id = ""
        return
    end
    if manual_reload_blocks_holster() then
        HOLSTER_ACTION.pending = nil
        STOW.holster_unequip_id = ""
        return
    end
    if not re8vr.can_use_hands or re8vr.is_in_cutscene then
        return
    end

    if pa.kind == "unequip" then
        HOLSTER_ACTION.pending = nil
        if pa.slot == "medicine" then
            STOW.holster_unequip_id = ""
            rawset(_G, "__re8_medicine_in_hand", false)
            FLY.clear_bridge()
            return
        end
        local expect_id = pa.expect_id or STOW.holster_unequip_id or ""
        local cur_id = get_current_weapon_item_id()
        if not is_bare_hands() and expect_id ~= "" and cur_id
            and normalize_item_id(cur_id) ~= normalize_item_id(expect_id) then
            STOW.holster_unequip_id = ""
            FLY.clear_bridge()
            return
        end
        local ok = unequip_current_to_bare_hands(pa.slot)
        STOW.holster_unequip_id = ""
        FLY.clear_bridge()
        if ok then
            arm_shoot_ready_suppress_after_holster_action()
        end
        return
    end

    if pa.kind == "equip" and pa.slot then
        if pa.slot == "medicine" then
            HOLSTER_ACTION.pending = nil
            FLY.stow_weapon_before_medicine("pending_med")
            rawset(_G, "__re8_medicine_in_hand", true)
            if FLY.note_med_grab then FLY.note_med_grab() end
            FLY.clear_bridge()
            return
        end
        if (pa.phase or 1) == 1 then
            FLY.clear_medicine_hold("pending_equip_" .. tostring(pa.slot))
        end
        local phase = pa.phase or 1
        if phase == 2 then
            clear_stow_bare_locks()
        end
        local ok = equip_weapon_from_profile(get_profile(), pa.slot, phase)
        if ok == "defer" then
            HOLSTER_ACTION.pending = { kind = "equip", slot = pa.slot, phase = 2 }
            return
        end
        HOLSTER_ACTION.pending = nil
        FLY.clear_bridge()
        if ok ~= true then
            clear_holster_equip_guard("equip_failed")
        end
        if ok == true then
            clear_stow_bare_locks()
            arm_shoot_ready_suppress_after_holster_action()
        end
        return
    end

    HOLSTER_ACTION.pending = nil
end

do
    local installed = false
    local td = sdk.find_type_definition("share.Startup")
    if td then
        local m = td:get_method("updateOnFrameHead")
        if m then
            sdk.hook(m, function() end, function(retval)
                pcall(execute_pending_action)
                return retval
            end)
            installed = true
        end
    end
    if not installed then
        log.warn("[re8_vr_holster] share.Startup.updateOnFrameHead hook missing; using on_frame defer only")
    end
end

local MENU_BLOCKING_GUI = {
    "PauseMenu", "MapMaskGUI", "MultiSubMenu", "FileMenu",
    "GUIInventory", "GUIInventoryMenu", "GUIMap", "GUIPause", "GUISaveLoad",
    "GUITitle", "GUITitleMenu", "GUIStartup", "GUIMessage", "GUIConfirm",
}
for _, v in ipairs(MENU_BLOCKING_GUI) do
    MENU_BLOCKING_GUI[v] = true
end

re.on_pre_gui_draw_element(function(element, context)
    local go = safe_call(element, "get_GameObject")
    if not go then return true end
    local name = safe_call(go, "get_Name")
    if type(name) == "string" and MENU_BLOCKING_GUI[name] then
        local active = false
        pcall(function() active = go:read_byte(0x10) == 1 end)
        if active then
            GRIP.menu_gui_time = os.clock()
            if name == "FileMenu" or name == "GUISaveLoad" or name == "PauseMenu"
                or name == "GUITitle" or name == "GUITitleMenu" or name == "GUIConfirm" then
                GRIP.scene_block_until = os.clock() + 10.0
            end
        end
    end
    return true
end)

function is_cinematic_blocking()
    local raw = false
    if re8vr and re8vr.is_in_cutscene then raw = true end
    if re8vr and re8vr.is_motion_play then raw = true end
    if re8vr and re8vr.is_arm_jacked then raw = true end
    if not raw then
        GRIP.cine_since = 0.0
    return false
    end
    local t = os.clock()
    if (tonumber(GRIP.cine_since) or 0) <= 0 then
        GRIP.cine_since = t
    end
    return (t - GRIP.cine_since) >= 0.12
end

function is_menu_blocking()
    if (os.clock() - GRIP.menu_gui_time) < 0.35 then return true end
    if os.clock() < (GRIP.scene_block_until or 0) then return true end
    if not re8vr or not re8vr.can_use_hands then return true end
    if re8vr.player and not managed_object_alive(re8vr.player) then return true end
    if re8vr.inventory and not managed_object_alive(re8vr.inventory) then return true end
    return false
end

rawset(_G, "__vr_is_menu_blocking", is_menu_blocking)
rawset(_G, "__vr_is_cinematic_blocking", is_cinematic_blocking)

do
    local td = sdk.find_type_definition("app.EquipController")
    local m = td and td:get_method("doOnDestroy")
    if m then
        sdk.hook(m, function(args)
            local em = nil
            pcall(function() em = sdk.to_managed_object(args[2]) end)
            if em == nil or em == COMPONENTS.equip_manager then
                COMPONENTS.equip_manager = nil
                COMPONENTS.weapon_change = nil
                COMPONENTS.mesh_controller = nil
                COMPONENTS.player_gun = nil
                COMPONENTS.player_melee = nil
                COMPONENTS.last_scan = 0
                GRIP.scene_block_until = os.clock() + 10.0
                NATIVE_WEAPON_SEL.equip_in_progress = false
                pcall(function() clear_holster_equip_guard("em_destroy") end)
            end
        end, function(retval)
            return retval
        end)
    end
end

local function purge_stale_equipped_weapon_state(reason)
    local cur = get_active_weapon_object()
    if cur and not weapon_component_usable(cur) then
        sync_re8vr_weapon_pointer(nil)
        if re8vr then re8vr.weapon = nil end
    end
    if holster_guard_active() then
        local gid = HOLSTER_GUARD.item_id
        if gid ~= "" and find_row_for_item_id(gid) == nil then
            clear_holster_equip_guard(reason or "inv_gone")
        end
    end
    if (HOLSTER_GUARD.mesh_repair_until or 0) > 0 then
        local rw = HOLSTER_GUARD.mesh_repair_weapon
        if not rw or not weapon_component_usable(rw) then
            HOLSTER_GUARD.mesh_repair_until = 0
            HOLSTER_GUARD.mesh_repair_weapon = nil
            HOLSTER_GUARD.mesh_repair_last_t = 0
            HOLSTER_GUARD.mesh_repair_started_at = 0
        end
    end
end
rawset(_G, "__re8_purge_stale_equipped_weapon", purge_stale_equipped_weapon_state)

--- Lightweight holster guard reassert: no applyQuickSlot, no full teardown.
local tick_holster_equip_guard
;(function()
    local function reassert_holster_guard_weapon()
        if STOW.player_dead() then return false end
        local guard_id = HOLSTER_GUARD.item_id
        if guard_id == "" then return false end
        if HOLSTER_GUARD.reassert_in_progress then return false end
        local now = os.clock()
        if (now - HOLSTER_GUARD.reassert_last_t) < 0.2 then return false end
        HOLSTER_GUARD.reassert_last_t = now
        HOLSTER_GUARD.reassert_in_progress = true

        local row = find_row_for_item_id(guard_id)
        if not row or not row.weapon or not managed_object_alive(row.weapon) then
            HOLSTER_GUARD.reassert_in_progress = false
            return false
        end

        refresh_components(false)
        sync_native_dpad_selection_for_item(guard_id)
        sync_inventory_select_for_item(guard_id)
        if re8vr.inventory then
            if STOW.is_chris_player() ~= true then
                pcall(function() re8vr.inventory:call("removeEquip") end)
            end
            pcall(function() re8vr.inventory:call("equipWeapon", guard_id) end)
        end

        local em = COMPONENTS.equip_manager
        local hand = get_right_hand_enum()
        if em then
            STOW.call_equip_weapon(em, row.weapon)
            pcall(function() em:call("set_equipWeaponRight", row.weapon) end)
            pcall(function()
                local wid = safe_call(row.weapon, "get_weaponID")
                if wid ~= nil then
                    em:set_field("EquipWeaponIdRight", wid)
                end
            end)
            pcall(function() em:call("set_isNoneEquipped", false) end)
        end

        sync_player_gun_combat(row.weapon, nil, "holster_guard_reassert")
        sync_re8vr_weapon_pointer(row.weapon)
        sanitize_re8vr_weapon_pointer()

        local cur_id = get_current_weapon_item_id() or ""
        local ok = cur_id ~= "" and normalize_item_id(cur_id) == normalize_item_id(guard_id)
        HOLSTER_GUARD.reassert_in_progress = false
        if ok then
            HOLSTER_GUARD.watch_drift_count = 0
            WEAPON_WATCH.last_ptr = row.weapon
            WEAPON_WATCH.last_id = guard_id
            WEAPON_WATCH.our_equip_until = os.clock() + 0.35
        end
        return ok
    end

    tick_holster_equip_guard = function()
        if is_menu_blocking() then return end
        local use_active = rawget(_G, "__re8_heal_is_native_use_active")
        if type(use_active) == "function" and use_active() == true then
            local cur_id = get_current_weapon_item_id() or ""
            if cur_id ~= "" and STOW.is_inventory_native_tool(nil, cur_id) then
                return
            end
        end
        purge_stale_equipped_weapon_state("guard_tick")
        if yield_holster_guard_for_native_dpad("guard_tick") then return end
        if not holster_guard_active() then return end
        if native_weapon_change_requested() and not our_holster_swap_active() then
            clear_holster_equip_guard("native_wc_request")
            return
        end
        local armed_at = HOLSTER_GUARD.armed_at or 0
        if armed_at > 0 and (os.clock() - armed_at) > 6.0 then
            clear_holster_equip_guard("guard_age_out")
            return
        end
        local guard_id = HOLSTER_GUARD.item_id
        if guard_id ~= "" and find_row_for_item_id(guard_id) == nil then
            clear_holster_equip_guard("guard_item_gone")
            return
        end
        local cur_id = get_current_weapon_item_id() or ""
        if cur_id ~= "" and STOW.is_inventory_native_tool(nil, cur_id) then
            clear_holster_equip_guard("native_tool")
            return
        end
        if cur_id ~= "" and normalize_item_id(cur_id) == normalize_item_id(guard_id) then
            HOLSTER_GUARD.watch_drift_count = 0
            return
        end
        local age = 0
        if armed_at > 0 then age = os.clock() - armed_at end
        clear_holster_equip_guard("native_swap")
    end
end)()

local function validate_cached_weapons(P)
    local now = os.clock()
    if (now - WEAPON_WATCH.validate_last_t) < 1.0 then return end
    WEAPON_WATCH.validate_last_t = now
    sanitize_profile_slot_ids(P)
    -- Guard on inventory *aliveness* (not row count). inventory_rows() returns {}
    -- both when the inventory object is not ready AND when it is genuinely empty,
    -- so an empty-inventory early return would skip the still_has clearing below and
    -- leave stale last_*_ids (e.g. last_medicine_id) intact. With an alive inventory
    -- the still_has block runs and clears ids that are no longer in the inventory.
    if not re8vr.inventory or not managed_object_alive(re8vr.inventory) then return end
    local function still_has(item_id)
        if not item_id or item_id == "" then return true end
        return find_row_for_item_id(item_id) ~= nil
    end
    if not still_has(P.last_pistol_id) then P.last_pistol_id = "" end
    if not still_has(P.last_longarm_id) then P.last_longarm_id = "" end
    if not still_has(P.last_chest_id) then P.last_chest_id = "" end
    if not still_has(P.last_knife_id) then P.last_knife_id = "" end
    if not still_has(P.last_medicine_id) then P.last_medicine_id = "" end
    if not still_has(P.last_utility_id) then P.last_utility_id = "" end
end

local function bootstrap_last_weapons(P)
    if profile_has_stowed_for_slot(P, "pistol")
        and profile_has_stowed_for_slot(P, "longarm")
        and profile_has_stowed_for_slot(P, "knife")
        and profile_has_stowed_for_slot(P, "medicine") then
        return
    end
    for _, row in ipairs(inventory_rows()) do
        local row_id = normalize_item_id(row.item_id)
        if row_id then
            if not profile_has_stowed_for_slot(P, "pistol")
                and item_id_allowed_for_holster_slot(row_id, "pistol") then
                P.last_pistol_id = row_id
            elseif not profile_has_stowed_for_slot(P, "longarm")
                and item_id_allowed_for_holster_slot(row_id, "longarm") then
                P.last_longarm_id = row_id
            elseif not profile_has_stowed_for_slot(P, "knife")
                and item_id_allowed_for_holster_slot(row_id, "knife") then
                P.last_knife_id = row_id
            elseif not profile_has_stowed_for_slot(P, "medicine")
                and item_id_allowed_for_holster_slot(row_id, "medicine") then
                P.last_medicine_id = row_id
            end
        end
    end
end

local function track_weapon()
    local P = get_profile()
    validate_cached_weapons(P)
    local prev_p, prev_l, prev_c, prev_k = P.last_pistol_id, P.last_longarm_id, P.last_chest_id, P.last_knife_id
    local prev_m = P.last_medicine_id
    local prev_u = P.last_utility_id
    -- Slot assignments only change on holster stow (hovered zone), not while merely equipped.
    bootstrap_last_weapons(P)
    if P.last_pistol_id ~= prev_p or P.last_longarm_id ~= prev_l
        or P.last_chest_id ~= prev_c or P.last_knife_id ~= prev_k
        or P.last_medicine_id ~= prev_m
        or P.last_utility_id ~= prev_u then
        save_cfg()
    end
end

local ANIM = { comp = nil, check_t = 0, layers = {} }

local function find_player_motion()
    local now = os.clock()
    if ANIM.comp and (now - ANIM.check_t) < 2.0 then return ANIM.comp end
    ANIM.check_t = now
    ANIM.comp = nil
    local tf = get_player_transform()
    if not tf or not motion_type then return nil end
    pcall(function()
        ANIM.comp = tf:find(motion_type)
    end)
    if not ANIM.comp and re8vr.player then
        pcall(function()
            ANIM.comp = re8vr.player:call("getComponent(System.Type)", motion_type)
        end)
    end
    return ANIM.comp
end

local function restore_skipped_motion_layers(mc)
    if not mc then return end
    for _, li in ipairs(CFG.suppress_motion_layers or { 0, 2, 3, 5 }) do
        if ANIM.layers[li] then
            local layer = safe_call(mc, "getLayer", li)
            if layer then
                pcall(function() layer:call("set_Speed", 1.0) end)
            end
            ANIM.layers[li] = false
        end
    end
end

local function suppress_holster_anims()
    local mc = find_player_motion()
    restore_skipped_motion_layers(mc)
    local name0 = ""
    local spd0 = ""
    local leftish = false
    if mc then
        local li = 0
        while li <= 6 do
            local layer = safe_call(mc, "getLayer", li)
            local node = layer and safe_call(layer, "get_HighestWeightMotionNode")
            local n = node and (safe_call(node, "get_MotionName") or "") or ""
            if type(n) == "string" and n ~= "" then
                if li == 0 then
                    name0 = n
                    if layer then
                        pcall(function() spd0 = tostring(layer:call("get_Speed")) end)
                    end
                end
                local low = n:lower()
                if n:find("Turn_Loop_L", 1, true)
                    or n:find("HolsterToMove", 1, true)
                    or low:find("getweapon", 1, true)
                    or (n:find("Hands_Turn", 1, true) and n:find("_L", 1, true)) then
                    name0 = n
                    leftish = true
                    break
                end
            end
            li = li + 1
        end
    end
    NATIVE_WEAPON_SEL.motion0 = tostring(name0 or "")
    NATIVE_WEAPON_SEL.motion0_left = leftish == true
end

re.on_pre_application_entry("UpdateScene", suppress_holster_anims)

STOW.tick_native_weapon_change_unstick = function()
    if our_holster_swap_active() then return end
    if is_bare_hands() then
        NATIVE_WEAPON_SEL.req_mismatch_id = ""
        NATIVE_WEAPON_SEL.req_mismatch_since = 0
        return
    end
    local now = os.clock()
    if now < (NATIVE_WEAPON_SEL.req_finish_done_t or 0) then return end
    if NATIVE_WEAPON_SEL.equip_in_progress then return end

    local wc = COMPONENTS.weapon_change
    if not wc then
        refresh_components(false)
        wc = COMPONENTS.weapon_change
    end
    local wc_req = native_weapon_change_requested()
    local req_item = nil
    local req_id = ""
    pcall(function()
        if not wc then return end
        req_item = wc:call("get_RequestedItem")
        if req_item then req_id = tostring(get_item_data_id(req_item) or "") end
    end)
    local cur_id = get_current_weapon_item_id() or ""
    local mismatch = wc_req and req_id ~= "" and cur_id ~= ""
        and normalize_item_id(req_id) ~= normalize_item_id(cur_id)

    if mismatch then
        if NATIVE_WEAPON_SEL.req_mismatch_id ~= req_id then
            NATIVE_WEAPON_SEL.req_mismatch_id = req_id
            NATIVE_WEAPON_SEL.req_mismatch_since = now
        end
        NATIVE_WEAPON_SEL.native_dpad_until = now + 0.8
        WEAPON_WATCH.our_equip_until = 0
        HOLSTER_GUARD.mesh_repair_until = 0
    else
        NATIVE_WEAPON_SEL.req_mismatch_id = ""
        NATIVE_WEAPON_SEL.req_mismatch_since = 0
        return
    end

    local age = now - (NATIVE_WEAPON_SEL.req_mismatch_since or now)
    local action = "wait"
    -- Logs: cur=holster weapon, req=dpad target, flags LB2, Stand_Loop.
    -- Native HolsterToMove never finishes; complete the requested equip in Lua.
    if age >= 0.20 then
        local row = find_row_for_item_id(req_id)
        local item_internal = req_item
        if (not item_internal or not managed_object_alive(item_internal)) and row then
            item_internal = row.item_internal
        end
        local weapon = row and row.weapon or nil
        if (not weapon or not managed_object_alive(weapon)) and item_internal then
            weapon = get_item_weapon(item_internal)
        end
        -- 2026-10-25 (Visceral RE8, Fable; both crashes of the day): this path "finished" a stalled native swap by forcing
        -- equipWeapon with whatever get_item_weapon handed back, and for the requested ri5003 / ri5052 that was an item that is
        -- no gun and no knife; the game's equipWeapon threw inside, and 1.5 s later requestMotion on that object killed the
        -- game. Only a gun or a knife is finished here; anything else is left to the game, said once in the log
        local kind = weapon and classify_item_core(weapon) or nil
        if kind == nil or kind == "UTIL" or kind == "MED" then
            NATIVE_WEAPON_SEL.req_finish_done_t = now + 2.0
            if NATIVE_WEAPON_SEL.refused_req_id ~= req_id then
                NATIVE_WEAPON_SEL.refused_req_id = req_id
                log.info(string.format("[re8_vr_holster] stalled swap to %s NOT finished by hand: the item is %s, not a gun or a knife (left to the game)", tostring(req_id), tostring(kind or "of no known kind")))
            end
            return
        end
        if item_internal and weapon and managed_object_alive(weapon) then
            local prev = get_active_weapon_object()
            local ok = native_equip(item_internal, weapon, "dpad_req_finish")
            if ok then
                if prev and prev ~= weapon and managed_object_alive(prev) then
                    STOW.hide_orphan_visual(prev)
                end
                STOW.clear_pending_weapon_change("req_finish")
                NATIVE_WEAPON_SEL.req_finish_done_t = now + 0.75
                NATIVE_WEAPON_SEL.req_mismatch_id = ""
                NATIVE_WEAPON_SEL.req_mismatch_since = 0
                action = "lua_req"
            else
                action = "lua_req_fail"
            end
        else
            action = "no_req_row"
        end
    end

end

local function vec3_dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function vec3_dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function haptic_pulse(joystick, duration, frequency, amplitude)
    local haptic_ok = false
    if joystick then
        local ok = pcall(function()
            vrmod:trigger_haptic_vibration(0.0, duration, frequency, amplitude, joystick)
        end)
        haptic_ok = ok == true
    end
    if not joystick then return end
end

local function holster_haptic_intensity()
    local v = tonumber(CFG.haptic_intensity)
    if v == nil then return 1.0 end
    return math.max(0, math.min(1, v))
end

local function holster_haptic_pulse(joystick, duration, frequency, amplitude)
    haptic_pulse(joystick, duration, frequency, (tonumber(amplitude) or 0) * holster_haptic_intensity())
end

-- Per-slot zone rumble (enter pulse + optional continuous).
STOW.zone_haptic_opts = function(slot)
    local enabled = CFG.zone_haptic_enabled ~= false
    local continuous = false
    if slot == "pistol" or slot == "hip" then
        enabled = enabled and CFG.hip_zone_haptic_enabled ~= false
        continuous = CFG.hip_zone_haptic_continuous == true
    elseif slot == "longarm" or slot == "shoulder" then
        enabled = enabled and CFG.shoulder_zone_haptic_enabled ~= false
        continuous = CFG.shoulder_zone_haptic_continuous == true
    elseif slot == "chest" then
        enabled = enabled and CFG.chest_zone_haptic_enabled ~= false
        continuous = CFG.chest_zone_haptic_continuous == true
    elseif slot == "knife" then
        enabled = enabled and CFG.knife_zone_haptic_enabled ~= false
        continuous = CFG.knife_zone_haptic_continuous == true
    elseif slot == "medicine" then
        enabled = enabled and CFG.medicine_zone_haptic_enabled ~= false
        continuous = CFG.medicine_zone_haptic_continuous == true
    elseif slot == "ammo_left" then
        -- Same zone indicator as other holsters (toggle in Ammo Holster UI).
        enabled = enabled and CFG.ammo_left_zone_haptic_enabled ~= false
        continuous = CFG.ammo_left_zone_haptic_continuous == true
    elseif slot == "head_flash" then
        enabled = enabled and CFG.head_flash_zone_haptic_enabled ~= false
        continuous = CFG.head_flash_zone_haptic_continuous == true
    end
    return enabled, continuous
end

-- Table methods (not local functions) keep the main chunk under Lua's 200-local limit.
STOW.ammo_can_grab = function()
    local api = rawget(_G, "__re8_ammo_drop_api")
    if type(api) == "table" and type(api.can_grab) == "function" then
        local ok, v = pcall(api.can_grab)
        if ok then return v == true end
    end
    return false
end

-- Live inventory medicine check (not stale last_medicine_id).
STOW.medicine_can_grab = function()
    if CFG.medicine_enabled == false then return false end
    if rawget(_G, "__re8_medicine_in_hand") == true then return false end
    local use_active = rawget(_G, "__re8_heal_is_native_use_active")
    if type(use_active) == "function" then
        local ok, v = pcall(use_active)
        if ok and v == true then return false end
    end
    if rawget(_G, "__re8_medicine_lua_hidden") == true then return false end
    for _, row in ipairs(inventory_rows()) do
        if is_medicine_core(row.item_internal) or is_medicine_item_id(row.item_id) then
            return true
        end
    end
    return false
end

STOW.maybe_zone_haptic = function(holster_state, joy, slot)
    -- RH aim-grip suppress is for right-hand weapon holsters only.
    -- Ammo pouch uses left hand / left joy — keep zone rumble while aiming.
    if GRIP.suppress_haptics_for_aim and slot ~= "ammo_left" then
        return
    end
    local zone_enabled, zone_continuous = STOW.zone_haptic_opts(slot)
    if not zone_enabled or not holster_state.in_zone or not joy then
        if not holster_state.in_zone then
            holster_state.haptic_pending_frames = 0
            holster_state.zone_enter_pulse = false
            holster_state._ammo_can_prev = false
            holster_state._med_can_prev = false
        end
        return
    end
    -- Ammo pouch: rumble only while can_grab (mag/shells available).
    if slot == "ammo_left" then
        local can = STOW.ammo_can_grab()
        local was = holster_state._ammo_can_prev == true
        holster_state._ammo_can_prev = can
        if can and not was then
            holster_state.zone_enter_pulse = true
        end
        if not can then
            holster_state.haptic_pending_frames = 0
            holster_state.zone_enter_pulse = false
            return
        end
    end
    -- Medicine chest: rumble only while a medicine item remains in inventory.
    if slot == "medicine" then
        local can = STOW.medicine_can_grab()
        local was = holster_state._med_can_prev == true
        holster_state._med_can_prev = can
        if can and not was then
            holster_state.zone_enter_pulse = true
        end
        if not can then
            holster_state.haptic_pending_frames = 0
            holster_state.zone_enter_pulse = false
            return
        end
    end
    if holster_state.zone_enter_pulse then
        holster_state.zone_enter_pulse = false
        holster_state.haptic_pending_frames = 0
        holster_haptic_pulse(joy, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
        return
    end
    if not zone_continuous then
        return
    end
    local interval = tonumber(CFG.zone_haptic_frames) or 2
    if interval < 1 then interval = 1 end
    holster_state.haptic_pending_frames = (holster_state.haptic_pending_frames or 0) + 1
    if holster_state.haptic_pending_frames >= interval then
        holster_state.haptic_pending_frames = 0
        holster_haptic_pulse(joy, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
    end
end

-- HMD-relative holster slot base position
-- Pistol/hip uses body joints so the zone stays on the waist when the HMD moves.
local HOLSTER_SLOT_BASE = {
    pistol = { right = 0.0, up = 0.0, forward = 0.0 },       -- joint-local (calibrate)
    longarm = { right = 0.0, up = 0.0, forward = 0.0 },
    chest = { right = 0.22, up = -0.36, forward = -0.08 },    -- RightChest (HMD)
    knife = { right = 0.0, up = 0.0, forward = 0.0 },         -- left-chest joint (calibrate)
    medicine = { right = 0.0, up = 0.0, forward = 0.0 },     -- right-chest joint (calibrate)
    ammo_left = { right = 0.0, up = 0.0, forward = 0.0 },     -- left-hip ammo (calibrate)
}

HJ = {
    names = {
        pistol = { "Hip" },
        ammo_left = { "Hip" },
        longarm = { "R_Shoulder", "R_UpperArm" },
        knife = { "Spine_2", "L_Shoulder", "Spine_1" },
        chest = { "Spine_2", "Spine_1" },
        medicine = { "Spine_2", "R_Shoulder" },
    },
    names_chris = {
        pistol = {},
        ammo_left = {},
        longarm = {},
        knife = {},
        chest = {},
        medicine = {},
    },
    CONTACT_NAMES = {
        "R_IndexF3", "R_MiddleF3", "R_Thumb3", "R_RingF3", "R_PinkyF3",
        "R_IndexF2", "R_MiddleF2",
        "R_Palm", "R_Hand",
    },
    contact_joints = nil,
    contact_joint_t = 0,
    last_joint_name = "",
    last_joint_src = "",
    diag_t = 0,
}

HJ.slot_names = function(slot_key)
    local chris = STOW.is_chris_player and STOW.is_chris_player() == true
    if chris then
        local names = HJ.names_chris[slot_key]
        if type(names) == "table" and #names > 0 then
            return names
        end
        if not HJ._chris_joint_fallback_logged then
            HJ._chris_joint_fallback_logged = true
            log.warn("[re8_vr_holster] Chris joints missing; using default list")
        end
    end
    return HJ.names[slot_key]
end

pcall(function()
    local data = json.load_file("re8_instructions/data/village_character_joints.json")
    if type(data) ~= "table" then return end
    local function apply(dst, src)
        if type(dst) ~= "table" or type(src) ~= "table" then return end
        if type(src.hip) == "table" and #src.hip > 0 then
            dst.pistol = src.hip
            dst.ammo_left = src.hip
        end
        if type(src.chest) == "table" and #src.chest > 0 then
            dst.knife = src.chest
        end
        if type(src.spine) == "table" and #src.spine > 0 then
            local chest = {}
            for _, n in ipairs(src.spine) do
                if n ~= "root" then
                    chest[#chest + 1] = n
                end
            end
            if #chest > 0 then
                dst.chest = chest
            end
        end
        if type(src.medicine) == "table" and #src.medicine > 0 then
            dst.medicine = src.medicine
        end
        if type(src.shoulder) == "table" and #src.shoulder > 0 then
            dst.longarm = src.shoulder
        end
    end
    apply(HJ.names, data.ethan)
    apply(HJ.names_chris, data.chris)
    for k, v in pairs(HJ.names) do
        if type(HJ.names_chris[k]) ~= "table" or #HJ.names_chris[k] == 0 then
            HJ.names_chris[k] = v
        end
    end
end)

local CALIB_TARGET_TO_SLOT = {
    hip = "pistol",
    ammo_left = "ammo_left",
    shoulder = "longarm",
    chest = "chest",
    knife = "knife",
    medicine = "medicine",
}

local SLOT_PROFILE_OFFSET = {
    pistol = { "hip_pistol_off_right", "hip_pistol_off_up", "hip_pistol_off_forward" },
    ammo_left = { "ammo_left_off_right", "ammo_left_off_up", "ammo_left_off_forward" },
    longarm = { "shoulder_off_x", "shoulder_off_y", "shoulder_off_z" },
    chest = { "chest_off_x", "chest_off_y", "chest_off_z" },
    knife = { "knife_off_x", "knife_off_y", "knife_off_z" },
    medicine = { "medicine_off_right", "medicine_off_up", "medicine_off_forward" },
}

local function make_holster_state()
    return {
        joint = nil,
        joint_name = "",
        in_zone = false,
        last_grab_t = -1.0,
        last_dist = 0.0,
        trigger_count = 0,
        haptic_pending_frames = 0,
        zone_enter_pulse = false,
    }
end

local hip = make_holster_state()
local shoulder = make_holster_state()
local chest = make_holster_state()
local knife = make_holster_state()
local medicine = make_holster_state()
HJ.ammo_left = make_holster_state()
HJ.ammo_mag_grab_ready_prev = false

local HEAL = {
    grip_began_inside = false,
    raw_was_grip = false,
    was_grip = false,
    was_trigger = false,
    cached_item = nil,
    cached_weapon = nil,
    last_grab_t = -1.0,
    remedy_equipped = false,
    lua_authorized = false,
    ARM_M = 0.18,
    pour_ok_since = nil,
    pour_fired = false,
}

FLY.note_med_grab = function()
    HEAL.last_grab_t = os.clock()
    HEAL._inject_lock_until = os.clock() + 0.85
end

-- After a successful native weapon equip, park the lua medicine mesh.
-- Do not cancel an in-progress grab fly or start a stow fly (that froze input
-- and left the bottle in the world).
FLY.return_medicine_to_holster = function(reason)
    local was = rawget(_G, "__re8_medicine_in_hand") == true
    local fly_med = FLY.active == true and FLY.slot == "medicine"
    if not was and not fly_med then return false end
    if fly_med then
        FLY._skip_med_attach = true
        FLY.cancel("med_return")
    end
    rawset(_G, "__re8_medicine_in_hand", false)
    FLY.clear_bridge()
    HEAL.in_hand = false
    HEAL.lua_authorized = false
    HEAL._inj_latched = false
    return true
end

local function get_right_joystick()
    if vrc_manager:has_controllers() then
        local rc = vrc_manager.controllers_list[2]
        if rc and rc.joystick then return rc.joystick end
    end
    local rj = nil
    pcall(function() rj = vrmod:get_right_joystick() end)
    return rj
end

local function get_right_grip_pressed()
    local rj = get_right_joystick()
    if rj then
        local action = safe_call(vrmod, "get_action_grip")
        if action then
            local ok, v = pcall(function() return vrmod:is_action_active(action, rj) end)
            if ok then return v == true end
        end
    end
    if vrc_manager:has_controllers() then
        local rc = vrc_manager.controllers_list[2]
        if rc then return rc:is_action_active(vrc_manager.Actions.GRIP) == true end
    end
    return false
end

local function get_right_trigger_pressed()
    local rj = get_right_joystick()
    if rj then
    local action = safe_call(vrmod, "get_action_trigger")
        if action then
    local ok, v = pcall(function() return vrmod:is_action_active(action, rj) end)
            if ok and v == true then return true end
        end
        -- Analog trigger axis (some OpenXR bindings never flip is_action_active).
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
    if vrc_manager and vrc_manager.has_controllers and vrc_manager:has_controllers() then
        local rc = vrc_manager.controllers_list and vrc_manager.controllers_list[2]
        if rc then
            local ok, v = pcall(function()
                if vrc_manager.Actions and vrc_manager.Actions.TRIGGER then
                    return rc:is_action_active(vrc_manager.Actions.TRIGGER)
                end
                return false
            end)
            if ok and v == true then return true end
            local axis = nil
            pcall(function()
                if rc.get_axis then axis = rc:get_axis(vrc_manager.Actions.TRIGGER) end
            end)
            if type(axis) == "number" and axis >= 0.65 then return true end
        end
    end
    return false
end

local function matrix_col(m, idx)
    if not m then return nil end
    local c = m[idx]
    if c and type(c.x) == "number" then return c end
    return nil
end

local function vec3_normalize(v)
    if not v then return nil end
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len < 1e-6 then return nil end
    return { x = v.x / len, y = v.y / len, z = v.z / len }
end

local function get_hmd_pose_local()
    local cam = sdk.get_primary_camera()
    if not cam then return nil end
    local ok, wm = pcall(function() return cam:call("get_WorldMatrix") end)
    if not ok or not wm then return nil end
    local pos = { x = wm[3].x, y = wm[3].y, z = wm[3].z }
    local function norm(v)
        local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        if len < 1e-6 then return nil end
        return { x = v.x / len, y = v.y / len, z = v.z / len }
    end
    local right = norm({ x = wm[0].x, y = wm[0].y, z = wm[0].z })
    local up = norm({ x = wm[1].x, y = wm[1].y, z = wm[1].z })
    local fwd = norm({ x = wm[2].x, y = wm[2].y, z = wm[2].z })
    if not right or not up or not fwd then return nil end
    return pos, right, up, fwd
end

local function get_hmd_pose_vr()
    local hmd_m = nil
    pcall(function() hmd_m = vrmod:get_transform(0) end)
    if hmd_m then
        local pos = matrix_col(hmd_m, 3)
        local right = vec3_normalize(matrix_col(hmd_m, 0))
        local up = vec3_normalize(matrix_col(hmd_m, 1))
        local fwd = vec3_normalize(matrix_col(hmd_m, 2))
        if pos and right and up and fwd then
            return pos, right, up, fwd
        end
    end
    return get_hmd_pose_local()
end

-- Joint-frame cache for hip/knife probes.
-- VR body follows HMD via IkLeg CenterOffset on the whole skeleton, so live
-- Waist/Chest joint world poses already include roomscale + crouch + turn.
-- Holsters parent 1:1 to those joints (no CenterOffset reconstruction).
-- (table created above before FLY so fly closures share the same upvalue)

local function cache_joint_frame(origin, right, up, fwd, src)
    if not origin then return end
    holster_transforms.torso_pos = origin
    holster_transforms.right = right
    holster_transforms.up = up
    holster_transforms.fwd = fwd
    holster_transforms.src = src or ""
    holster_transforms.t = os.clock()
end

holster_transforms.refresh = function()
    -- Kept for ImGui: resolve Waist as the shared torso joint.
    local probe = hip
    local origin, ax, ay, az = HJ.resolve_anchor(probe, { "Hip", "Spine_0", "root" })
    if origin then
        cache_joint_frame(origin, ax, ay, az, HJ.last_joint_name or "Hip")
        return origin, ax, ay, az
    end
    return nil
end

local function get_right_hand_pos()
    local source = "none"
    local pos = nil
    local rh_m = nil
    pcall(function() rh_m = vrmod:get_transform(HJ.rh_ctrl_idx()) end)
    if rh_m then
        pos = matrix_col(rh_m, 3)
        if pos then source = "vrmod_transform" end
    end
    if not pos and re8vr and re8vr.last_right_hand_position and type(re8vr.last_right_hand_position.x) == "number" then
        source = "re8vr_last_right_hand"
        pos = re8vr.last_right_hand_position
    end
    if not pos then
        local j = rawget(_G, "__vr_rh_joint_pos")
        if j and type(j.x) == "number" then
            source = "global_joint"
            pos = j
        end
    end
    if not pos then
        local w = rawget(_G, "__vr_rh_world")
        if w and type(w.x) == "number" then
            source = "global_world"
            pos = w
        end
    end
    return pos, source
end

HJ.rh_ctrl_idx = function()
    local controllers = nil
    pcall(function() controllers = vrmod:get_controllers() end)
    local idx = controllers and controllers[2]
    if idx == nil then idx = 2 end
    return idx
end

-- World-space right hand for joint holsters (must match joint get_Position space).
HJ.get_right_hand_world = function()
    local pos, src = nil, "none"
    if re8vr and re8vr.right_hand_ik_transform then
        pcall(function() pos = re8vr.right_hand_ik_transform:call("get_Position") end)
        if pos and type(pos.x) == "number" then src = "ik_transform" end
    end
    if not pos and re8vr and re8vr.last_right_hand_position
        and type(re8vr.last_right_hand_position.x) == "number" then
        pos = re8vr.last_right_hand_position
        src = "re8vr_last"
    end
    if not pos then
        local w = rawget(_G, "__vr_rh_world")
        if w and type(w.x) == "number" then pos = w; src = "global_world" end
    end
    if not pos then
        local tf = get_player_transform()
        if tf then
            local j = nil
            pcall(function() j = tf:call("getJointByName", "r_arm_wrist") end)
            if j then
                pcall(function() pos = j:call("get_Position") end)
                if pos then src = "wrist_joint" end
            end
        end
    end
    -- Project play-space controller into world via camera.
    if not pos and vrmod then
        local cam = nil
        pcall(function() cam = sdk.get_primary_camera() end)
        local wm = nil
        pcall(function()
            if cam then
                local go = cam:call("get_GameObject")
                local xf = go and go:call("get_Transform")
                if xf then wm = xf:call("get_WorldMatrix") end
            end
        end)
        local ctrl = nil
        local hmd = nil
        pcall(function() ctrl = vrmod:get_position(HJ.rh_ctrl_idx()) end)
        pcall(function() hmd = vrmod:get_position(0) end)
        if wm and ctrl and hmd and type(ctrl.x) == "number" then
            local dx, dy, dz = ctrl.x - hmd.x, ctrl.y - hmd.y, ctrl.z - hmd.z
            local r = vec3_normalize(matrix_col(wm, 0))
            local u = vec3_normalize(matrix_col(wm, 1))
            local f = vec3_normalize(matrix_col(wm, 2))
            local c = matrix_col(wm, 3)
            if r and u and f and c then
                -- Use HMD-local offset onto camera transform (full HMD axes, not yaw-flattened).
                pos = {
                    x = c.x + dx * r.x + dy * u.x + dz * f.x,
                    y = c.y + dx * r.y + dy * u.y + dz * f.y,
                    z = c.z + dx * r.z + dy * u.z + dz * f.z,
                }
                src = "cam_project"
            end
        end
    end
    return pos, src
end

-- World-space left hand for ammo hip zone (must match Hip joint get_Position space).
-- Do NOT use raw vrmod play-space transforms here — that mixed space produced
-- ~100m+ offsets and made the zone unreachable.
HJ.get_left_hand_world = function()
    local pos, src = nil, "none"
    if re8vr and re8vr.left_hand_ik_transform then
        pcall(function() pos = re8vr.left_hand_ik_transform:call("get_Position") end)
        if pos and type(pos.x) == "number" then src = "ik_transform" end
    end
    if not pos and re8vr and re8vr.last_left_hand_position
        and type(re8vr.last_left_hand_position.x) == "number" then
        pos = re8vr.last_left_hand_position
        src = "re8vr_last"
    end
    if not pos then
        local w = rawget(_G, "__vr_lh_world")
        if w and type(w.x) == "number" then pos = w; src = "global_world" end
    end
    if not pos then
        local tf = get_player_transform()
        if tf then
            local j = nil
            pcall(function() j = tf:call("getJointByName", "L_Hand") end)
            if not j then pcall(function() j = tf:call("getJointByName", "l_arm_wrist") end) end
            if j then
                pcall(function() pos = j:call("get_Position") end)
                if pos then src = "wrist_joint" end
            end
        end
    end
    if not pos and vrmod then
        local cam = nil
        pcall(function() cam = sdk.get_primary_camera() end)
        local wm = nil
        pcall(function()
            if cam then
                local go = cam:call("get_GameObject")
                local xf = go and go:call("get_Transform")
                if xf then wm = xf:call("get_WorldMatrix") end
            end
        end)
        local ctrl = nil
        local hmd = nil
        local lh_idx = 1
        pcall(function()
            local controllers = vrmod:get_controllers()
            if controllers and controllers[1] ~= nil then lh_idx = controllers[1] end
        end)
        pcall(function() ctrl = vrmod:get_position(lh_idx) end)
        pcall(function() hmd = vrmod:get_position(0) end)
        if wm and ctrl and hmd and type(ctrl.x) == "number" then
            local dx, dy, dz = ctrl.x - hmd.x, ctrl.y - hmd.y, ctrl.z - hmd.z
            local r = vec3_normalize(matrix_col(wm, 0))
            local u = vec3_normalize(matrix_col(wm, 1))
            local f = vec3_normalize(matrix_col(wm, 2))
            local c = matrix_col(wm, 3)
            if r and u and f and c then
                pos = {
                    x = c.x + dx * r.x + dy * u.x + dz * f.x,
                    y = c.y + dx * r.y + dy * u.y + dz * f.y,
                    z = c.z + dx * r.z + dy * u.z + dz * f.z,
                }
                src = "cam_project"
            end
        end
    end
    return pos, src
end

HJ.quat_from_matrix = function(m)
    if not m then return nil end
    local c0, c1, c2 = m[0], m[1], m[2]
    if not c0 or type(c0.x) ~= "number" or not c1 or not c2 then return nil end
    local m00, m01, m02 = c0.x, c0.y, c0.z
    local m10, m11, m12 = c1.x, c1.y, c1.z
    local m20, m21, m22 = c2.x, c2.y, c2.z
    local tr = m00 + m11 + m22
    local w, x, y, z
    if tr > 0.0 then
        local s = math.sqrt(tr + 1.0) * 2.0
        w = 0.25 * s
        x = (m12 - m21) / s
        y = (m20 - m02) / s
        z = (m01 - m10) / s
    elseif m00 > m11 and m00 > m22 then
        local s = math.sqrt(1.0 + m00 - m11 - m22) * 2.0
        w = (m12 - m21) / s
        x = 0.25 * s
        y = (m01 + m10) / s
        z = (m02 + m20) / s
    elseif m11 > m22 then
        local s = math.sqrt(1.0 + m11 - m00 - m22) * 2.0
        w = (m20 - m02) / s
        x = (m01 + m10) / s
        y = 0.25 * s
        z = (m12 + m21) / s
    else
        local s = math.sqrt(1.0 + m22 - m00 - m11) * 2.0
        w = (m01 - m10) / s
        x = (m02 + m20) / s
        y = (m12 + m21) / s
        z = 0.25 * s
    end
    local len = math.sqrt(w * w + x * x + y * y + z * z)
    if len < 1e-8 then return { w = 1.0, x = 0.0, y = 0.0, z = 0.0 } end
    return { w = w / len, x = x / len, y = y / len, z = z / len }
end

HJ.get_left_hand_world_pose = function()
    local pos, src = HJ.get_left_hand_world()
    local rot = nil
    if vrmod and FLASH and FLASH.lh_ctrl_idx then
        pcall(function()
            local m = vrmod:get_transform(FLASH.lh_ctrl_idx())
            rot = HJ.quat_from_matrix(m)
        end)
    end
    return pos, rot, src
end

HJ.collect_transforms = function()
    refresh_components(true)
    local out = {}
    local seen = {}
    local function add(tf, src)
        if not tf then return end
        local addr = nil
        pcall(function() addr = tf:get_address() end)
        local key = addr or tostring(tf)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { tf = tf, src = src or "?" }
    end
    add(get_player_transform(), "player")
    if re8vr and re8vr.player then
        add(safe_call(re8vr.player, "get_Transform"), "player_go")
    end
    local mc = COMPONENTS.mesh_controller
    if mc then
        for _, field in ipairs({ "UpperBodyMesh", "LowerBodyMesh", "LArmMesh", "RArmMesh" }) do
            local mesh = nil
            pcall(function() mesh = mc:get_field(field) end)
            if mesh then
                local go = safe_call(mesh, "get_GameObject")
                add(go and safe_call(go, "get_Transform"), field)
            end
        end
    end
    return out
end

HJ.find_joint = function(names)
    local transforms = HJ.collect_transforms()
    for _, entry in ipairs(transforms) do
        for _, name in ipairs(names or {}) do
            local j = safe_call(entry.tf, "getJointByName", name)
            if j then
                local pos = safe_call(j, "get_Position")
                if pos and type(pos.x) == "number" then
                    return j, name, entry.src
                end
            end
        end
    end
    return nil, "", ""
end

HJ.find_joint_transform = function(names)
    local transforms = HJ.collect_transforms()
    for _, entry in ipairs(transforms) do
        for _, name in ipairs(names or {}) do
            local j = safe_call(entry.tf, "getJointByName", name)
            if j then
                return entry.tf, entry.src or "?", name
            end
        end
    end
    return nil, nil, nil
end

HJ.refresh = function(holster_state, names)
    if not holster_state then return false end
    -- Never keep a fallback joint permanently — always re-prefer requested names.
    local cached_name = holster_state.joint_name or ""
    local is_fallback = cached_name:find("_fallback", 1, true) ~= nil
    local name_ok = false
    if cached_name ~= "" and not is_fallback then
        for _, want in ipairs(names or {}) do
            if want == cached_name then name_ok = true; break end
        end
    end
    if holster_state.joint and name_ok then
        local pos = safe_call(holster_state.joint, "get_Position")
        if pos and type(pos.x) == "number" then
            HJ.last_joint_name = cached_name
            return true
        end
    end
    holster_state.joint = nil
    holster_state.joint_name = ""
    local j, nm, src = HJ.find_joint(names)
    if j then
        holster_state.joint = j
        holster_state.joint_name = nm or ""
        HJ.last_joint_name = nm or ""
        HJ.last_joint_src = src or ""
        return true
    end
    return false
end

HJ.resolve_anchor = function(holster_state, names)
    if not holster_state then return nil end
    HJ.refresh(holster_state, names)
    if holster_state.joint then
        local origin = safe_call(holster_state.joint, "get_Position")
        if origin and type(origin.x) == "number" then
            if (os.clock() - (HJ.resolve_log_t or 0)) > 2.0 then
                HJ.resolve_log_t = os.clock()
            end
            return origin,
                safe_call(holster_state.joint, "get_AxisX"),
                safe_call(holster_state.joint, "get_AxisY"),
                safe_call(holster_state.joint, "get_AxisZ")
        end
        holster_state.joint = nil
        holster_state.joint_name = ""
    end

    -- Fallback: chest/spine before hip. Mark as fallback so next frame retries preferred.
    local transforms = HJ.collect_transforms()
    local pos, used, used_j, used_src = nil, "", nil, ""
    for _, entry in ipairs(transforms) do
        for _, nm in ipairs({ "Spine_2", "Spine_1", "Spine_0", "Hip" }) do
            local j = safe_call(entry.tf, "getJointByName", nm)
            if j then
                local p = safe_call(j, "get_Position")
                if p and type(p.x) == "number" then
                    pos = p
                    used = nm .. "_fallback"
                    used_j = j
                    used_src = entry.src
                    break
                end
            end
        end
        if pos then break end
    end
    if not pos then
        local tf = get_player_transform()
        pos = tf and safe_call(tf, "get_Position") or nil
        used = "root_fallback"
    end
    if not pos then return nil end

    holster_state.joint = used_j
    holster_state.joint_name = used
    HJ.last_joint_name = used
    HJ.last_joint_src = used_src

    if (os.clock() - (HJ.resolve_log_t or 0)) > 2.0 then
        HJ.resolve_log_t = os.clock()
        local tried = {}
        for _, entry in ipairs(transforms) do
            for _, name in ipairs(names or {}) do
                local j = safe_call(entry.tf, "getJointByName", name)
                local tag = "=miss"
                if j then
                    local p = safe_call(j, "get_Position")
                    tag = (p and type(p.x) == "number") and "=ok" or "=nopos"
                end
                tried[#tried + 1] = entry.src .. ":" .. name .. tag
            end
        end
    end

    if used_j then
        return pos,
            safe_call(used_j, "get_AxisX"),
            safe_call(used_j, "get_AxisY"),
            safe_call(used_j, "get_AxisZ")
    end
    local tf = get_player_transform()
    local rot = tf and safe_call(tf, "get_Rotation") or nil
    local right, up, fwd = nil, nil, nil
    if rot then
        pcall(function()
            local rv = rot * Vector3f.new(1, 0, 0)
            local uv = rot * Vector3f.new(0, 1, 0)
            local fv = rot * Vector3f.new(0, 0, 1)
            right = vec3_normalize({ x = rv.x, y = rv.y, z = rv.z })
            up = vec3_normalize({ x = uv.x, y = uv.y, z = uv.z })
            fwd = vec3_normalize({ x = fv.x, y = fv.y, z = fv.z })
        end)
    end
    return pos, right, up, fwd
end

local function holster_pos_with_offsets(origin, off_x, off_y, off_z, ax, ay, az, right, up, fwd)
    if not origin then return nil end
    if ax and ay and az then
        return {
            x = origin.x + ax.x * off_x + ay.x * off_y + az.x * off_z,
            y = origin.y + ax.y * off_x + ay.y * off_y + az.y * off_z,
            z = origin.z + ax.z * off_x + ay.z * off_y + az.z * off_z,
        }
    end
    if right and up and fwd then
        return {
            x = origin.x + off_x * right.x + off_y * up.x + off_z * fwd.x,
            y = origin.y + off_x * right.y + off_y * up.y + off_z * fwd.y,
            z = origin.z + off_x * right.z + off_y * up.z + off_z * fwd.z,
        }
    end
    return origin
end

local function get_profile_slot_offsets(P, slot_key)
    local keys = SLOT_PROFILE_OFFSET[slot_key]
    if not keys then return 0, 0, 0 end
    local off_r = P[keys[1]] or 0
    local off_u = P[keys[2]] or 0
    local off_f = P[keys[3]] or 0
    -- Corrupt ammo_left calib (mixed VR/joint space) wrote ~100m offsets.
    if slot_key == "ammo_left" then
        local mag = math.sqrt(off_r * off_r + off_u * off_u + off_f * off_f)
        if mag > 2.0 then
            off_r, off_u, off_f = -0.12, 0.0, 0.02
            P.ammo_left_off_right = off_r
            P.ammo_left_off_up = off_u
            P.ammo_left_off_forward = off_f
            pcall(save_cfg)
        end
    end
    return off_r, off_u, off_f
end

-- Synthetic torso frame retired. Weapon holsters parent to live skeleton joints
-- that already follow the HMD via IkLeg (Waist/Chest).
HJ.uses_torso = function(slot_key)
    return false
end

-- Hip pistol + left-chest knife + left ammo: live joint world pose (1:1).
HJ.uses_joint = function(slot_key)
    return slot_key == "pistol" or slot_key == "knife" or slot_key == "ammo_left"
        or slot_key == "medicine" or slot_key == "longarm"
end

-- Stable body facing axes from the player root (not the animated joint).
HJ.body_axes = function()
    local tf = get_player_transform()
    if not tf then return nil end
    local rot = safe_call(tf, "get_Rotation")
    if not rot then return nil end
    local right, up, fwd = nil, nil, nil
    pcall(function()
        local rv = rot * Vector3f.new(1, 0, 0)
        local uv = rot * Vector3f.new(0, 1, 0)
        local fv = rot * Vector3f.new(0, 0, 1)
        right = vec3_normalize({ x = rv.x, y = rv.y, z = rv.z })
        up = vec3_normalize({ x = uv.x, y = uv.y, z = uv.z })
        fwd = vec3_normalize({ x = fv.x, y = fv.y, z = fv.z })
    end)
    if not right or not up or not fwd then return nil end
    return right, up, fwd
end

-- Yaw-only body facing for weapon holster offsets.
-- Prefer player ROOT yaw (stable while strafe-leaning Hip/Chest). Fall back to Hip.
HJ.torso_yaw_axes = function()
    local fwd = nil
    local _, _, bf = HJ.body_axes()
    if bf then
        fwd = vec3_normalize({ x = bf.x, y = 0, z = bf.z })
    end
    if not fwd then
        local j = select(1, HJ.find_joint({ "Hip", "Spine_0", "root" }))
        if j then
            local az = safe_call(j, "get_AxisZ")
            if az and type(az.x) == "number" then
                fwd = vec3_normalize({ x = az.x, y = 0, z = az.z })
            end
        end
    end
    fwd = fwd or { x = 0, y = 0, z = 1 }
    local up = { x = 0, y = 1, z = 0 }
    local right = vec3_normalize({
        x = up.y * fwd.z - up.z * fwd.y,
        y = up.z * fwd.x - up.x * fwd.z,
        z = up.x * fwd.y - up.y * fwd.x,
    }) or { x = 1, y = 0, z = 0 }
    return right, up, fwd
end

-- Walk jiggle = live Waist/Chest world pos rewritten every frame (and zones
-- republished from LateUpdate + on_frame). Fix: rebuild as
--   root + R * LP(joint-root)
-- so character translation is exact and stride bob (local) is damped.
-- Knife: same waist-root LP, plus LP(Chest-Waist) height/offset.
-- Per-frame cache avoids double publish fighting the mesh the same frame.
HJ.stable_slot_origin = function(slot_key, joint_origin, br, bu, bf)
    if not joint_origin or not br or not bu or not bf then
        return joint_origin, br, bu, bf, ""
    end

    local tf = get_player_transform()
    local root = tf and safe_call(tf, "get_Position") or nil
    if not root or type(root.x) ~= "number" then
        return joint_origin, br, bu, bf, "no_root"
    end

    local now = os.clock()
    local dt = now - (holster_transforms.body_lp_t or now)
    if dt < 0 then dt = 0.016 end
    if dt > 0.1 then dt = 0.1 end
    -- Shared dt clock updated once per call chain; pistol/knife each keep own filter state.

    local waist_j = select(1, HJ.find_joint({ "Hip", "Spine_0", "root" }))
    local waist = (waist_j and safe_call(waist_j, "get_Position")) or joint_origin
    if not waist or type(waist.x) ~= "number" then waist = joint_origin end

    -- Body-local waist relative to root (filters walk bob; root carry is 1:1).
    local wdx = waist.x - root.x
    local wdy = waist.y - root.y
    local wdz = waist.z - root.z
    local wr = wdx * br.x + wdy * br.y + wdz * br.z
    local wu = wdx * bu.x + wdy * bu.y + wdz * bu.z
    local wf = wdx * bf.x + wdy * bf.y + wdz * bf.z

    if not holster_transforms.waist_lp then holster_transforms.waist_lp = {} end
    local W = holster_transforms.waist_lp
    -- BUGFIX (mesh-rootlp1): `not W.r` is true when W.r==0 in Lua, so the filter
    -- snapped to live every frame (logs: w_err≈0 always). Use nil checks only.
    local wjump = (W.r == nil)
        or (math.abs(wr - W.r) + math.abs(wu - (W.u or 0)) + math.abs(wf - (W.f or 0))) > 0.85
    if wjump then
        W = { r = wr, u = wu, f = wf }
    else
        -- mesh-rootlp3: heavier waist/chest/yaw LP for smoother loco mesh.
        local a = 1 - math.exp(-dt / holster_zone_lp_tau("waist"))
        W.r = W.r + (wr - W.r) * a
        W.u = W.u + (wu - W.u) * a
        W.f = W.f + (wf - W.f) * a
    end
    holster_transforms.waist_lp = W
    holster_transforms.body_lp_t = now

    local mode = "root_lp"
    if slot_key == "knife" or slot_key == "medicine" or slot_key == "longarm" then
        local chest = joint_origin
        if slot_key ~= "longarm" then
            local chest_j = select(1, HJ.find_joint({ "Spine_2", "Spine_1" }))
            chest = chest_j and safe_call(chest_j, "get_Position") or joint_origin
        end
        if chest and type(chest.x) == "number" then
            local cdx = chest.x - waist.x
            local cdy = chest.y - waist.y
            local cdz = chest.z - waist.z
            local cr = cdx * br.x + cdy * br.y + cdz * br.z
            local cu = cdx * bu.x + cdy * bu.y + cdz * bu.z
            local cf = cdx * bf.x + cdy * bf.y + cdz * bf.z
            local rel_key = "knife_rel"
            if slot_key == "medicine" then rel_key = "medicine_rel" end
            if slot_key == "longarm" then rel_key = "longarm_rel" end
            local C = holster_transforms[rel_key]
            local cjump = (C == nil) or (C.r == nil)
                or (math.abs(cr - C.r) + math.abs(cu - (C.u or 0)) + math.abs(cf - (C.f or 0))) > 0.75
            if cjump then
                C = { r = cr, u = cu, f = cf }
            else
                local ca = 1 - math.exp(-dt / holster_zone_lp_tau("chest"))
                C.r = C.r + (cr - C.r) * ca
                C.u = C.u + (cu - C.u) * ca
                C.f = C.f + (cf - C.f) * ca
            end
            holster_transforms[rel_key] = C
            mode = "root_lp+chest"
        end
    end

    -- Light body-yaw smooth so offset projection does not jitter with root facing noise.
    local Y = holster_transforms.smooth_yaw
    if not Y or Y.fx == nil then
        Y = { fx = bf.x, fz = bf.z }
    else
        local ya = 1 - math.exp(-dt / holster_zone_lp_tau("yaw"))
        Y.fx = Y.fx + (bf.x - Y.fx) * ya
        Y.fz = Y.fz + (bf.z - Y.fz) * ya
    end
    holster_transforms.smooth_yaw = Y
    local sfwd = vec3_normalize({ x = Y.fx, y = 0, z = Y.fz }) or bf
    local sup = { x = 0, y = 1, z = 0 }
    local sright = vec3_normalize({
        x = sup.y * sfwd.z - sup.z * sfwd.y,
        y = 0,
        z = -sup.y * sfwd.x,
    }) or br
    local origin = {
        x = root.x + sright.x * W.r + sup.x * W.u + sfwd.x * W.f,
        y = root.y + sright.y * W.r + sup.y * W.u + sfwd.y * W.f,
        z = root.z + sright.z * W.r + sup.z * W.u + sfwd.z * W.f,
    }
    if (slot_key == "knife" or slot_key == "medicine" or slot_key == "longarm") then
        local rel_key = "knife_rel"
        if slot_key == "medicine" then rel_key = "medicine_rel" end
        if slot_key == "longarm" then rel_key = "longarm_rel" end
        local C = holster_transforms[rel_key]
        if C and C.r ~= nil then
        origin = {
            x = origin.x + sright.x * C.r + sup.x * C.u + sfwd.x * C.f,
            y = origin.y + sright.y * C.r + sup.y * C.u + sfwd.y * C.f,
            z = origin.z + sright.z * C.r + sup.z * C.u + sfwd.z * C.f,
        }
        end
    end
    br, bu, bf = sright, sup, sfwd

    return origin, br, bu, bf, mode
end

HJ.state_for = function(slot_key)
    if slot_key == "pistol" then return hip end
    if slot_key == "ammo_left" then return HJ.ammo_left end
    if slot_key == "knife" then return knife end
    if slot_key == "medicine" then return medicine end
    if slot_key == "longarm" then return shoulder end
    if slot_key == "chest" then return chest end
    return { joint = nil }
end

HJ.slot_base_pos = function(slot_key)
    if HJ.uses_torso(slot_key) then
        local origin, right, up, fwd = holster_transforms.refresh()
        if not origin then return nil end
        return origin, right, up, fwd
    end
    if HJ.uses_joint(slot_key) then
        local names = HJ.slot_names(slot_key)
        local probe = HJ.state_for(slot_key)
        local origin, ax, ay, az = HJ.resolve_anchor(probe, names)
        if origin then
            if (os.clock() - (HJ.diag_t or 0)) > 2.0 then
                HJ.diag_t = os.clock()
            end
            return origin, ax, ay, az
        end
        return nil
    end
    local hmd, right, up, fwd = get_hmd_pose_vr()
    local base = HOLSTER_SLOT_BASE[slot_key]
    if not hmd or not base then return nil end
    return holster_pos_with_offsets(hmd, base.right, base.up, base.forward, nil, nil, nil, right, up, fwd),
        right, up, fwd
end

HJ.slot_world_pos = function(slot_key, P)
    local off_r, off_u, off_f = get_profile_slot_offsets(P, slot_key)
    -- Same-frame cache: LateUpdate suppress + on_frame both refresh zones; without
    -- this the mesh gets two different joint samples per frame (walk jigger).
    if slot_key == "pistol" or slot_key == "knife" or slot_key == "medicine" or slot_key == "longarm" then
        local cache = holster_transforms._pos_cache and holster_transforms._pos_cache[slot_key]
        local now = os.clock()
        if cache and cache.pos and (now - (cache.t or 0)) < 0.0008 then
            return cache.pos
        end
    end
    if HJ.uses_torso(slot_key) then
        local origin, right, up, fwd = holster_transforms.refresh()
        if not origin then return nil end
        local base = HOLSTER_SLOT_BASE[slot_key] or { right = 0, up = 0, forward = 0 }
        return holster_pos_with_offsets(
            origin,
            base.right + off_r,
            base.up + off_u,
            base.forward + off_f,
            nil, nil, nil, right, up, fwd)
    end
    if HJ.uses_joint(slot_key) then
        local names = HJ.slot_names(slot_key)
        local state = HJ.state_for(slot_key)
        local origin, ax, ay, az = HJ.resolve_anchor(state, names)
        if not origin then return nil end
        local base = HOLSTER_SLOT_BASE[slot_key] or { right = 0, up = 0, forward = 0 }
        -- Pistol/knife/medicine: joint POSITION (follows torso under HMD) + yaw-only body
        -- axes (does not spin with HMD look or Chest twist). Ammo keeps joint axes.
        if slot_key == "pistol" or slot_key == "knife" or slot_key == "medicine" or slot_key == "longarm" then
            local br, bu, bf = HJ.torso_yaw_axes()
            if br then
                local stab, sr, su, sf, mode = HJ.stable_slot_origin(slot_key, origin, br, bu, bf)
                if stab then origin = stab end
                if sr then br, bu, bf = sr, su, sf end
                local base = HOLSTER_SLOT_BASE[slot_key] or { right = 0, up = 0, forward = 0 }
                local pos = holster_pos_with_offsets(
                    origin,
                    base.right + off_r,
                    base.up + off_u,
                    base.forward + off_f,
                    nil, nil, nil, br, bu, bf)
                cache_joint_frame(pos or origin, br, bu, bf, (HJ.last_joint_name or slot_key) .. "+" .. (mode or "raw"))
                if pos then
                    if not holster_transforms._pos_cache then holster_transforms._pos_cache = {} end
                    holster_transforms._pos_cache[slot_key] = { pos = pos, t = os.clock() }
                end
                return pos
            end
        end
        return holster_pos_with_offsets(
            origin,
            base.right + off_r,
            base.up + off_u,
            base.forward + off_f,
            ax, ay, az, ax, ay, az)
    end
    local hmd, right, up, fwd = get_hmd_pose_vr()
    local base = HOLSTER_SLOT_BASE[slot_key]
    if not hmd or not base then return nil end
    return holster_pos_with_offsets(
        hmd,
        base.right + off_r,
        base.up + off_u,
        base.forward + off_f,
        nil, nil, nil, right, up, fwd)
end

STOW.hover_m = function()
    return tonumber(CFG.holster_weapon_hover_m) or 0.24
end

STOW.sync_weapon_hold_suppress = function(in_zone)
    local in_holster = in_zone == true
    if in_holster and shoulder.in_zone == true
        and hip.in_zone ~= true and chest.in_zone ~= true and knife.in_zone ~= true then
        if get_effective_holster_slot_for_cur_weapon() == "longarm" then
            in_holster = false
        end
    end
    local bare = CFG.enabled and is_bare_hands() == true
    rawset(_G, "__vr_in_holster_zone", in_holster)
    rawset(_G, "__vr_block_hold_in_holster_zone", in_holster or bare)
    rawset(_G, "__vr_block_bare_hands_aim", bare == true)
end

STOW.clear_weapon_hold_suppress = function()
    rawset(_G, "__vr_in_holster_zone", false)
    rawset(_G, "__vr_block_hold_in_holster_zone", false)
    rawset(_G, "__vr_block_bare_hands_aim", false)
end

HEAL.get_zone_pos = function(P)
    return HJ.slot_world_pos("medicine", P)
end

-- Holster visual mesh_off (from JSON) → world offset on top of zone. Used so grab
-- stays mesh-aligned even when the mesh publish is stale (Update order).
HJ.probe_visual_for_slot = function(slot_key)
    local live_g = "__re8_knife_visual_live"
    if slot_key == "pistol" then
        live_g = "__re8_hip_visual_live"
    elseif slot_key == "medicine" then
        live_g = "__re8_medicine_visual_live"
    end
    local live = rawget(_G, live_g)
    if type(live) == "table" then
        return live
    end
    local now = os.clock()
    if rawget(_G, "__re8_holster_vis_cache_bust") == true then
        holster_transforms._vis_t = 0
        holster_transforms._vis = nil
        rawset(_G, "__re8_holster_vis_cache_bust", nil)
    end
    if (now - (holster_transforms._vis_t or 0)) > 0.15 then
        local data = nil
        pcall(function() data = json.load_file(CFG_PATH) end)
        holster_transforms._vis = (type(data) == "table") and data or {}
        holster_transforms._vis_t = now
    end
    local vis = holster_transforms._vis
    local new_key = "knife_visual"
    local old_key = "knife_probe_visual"
    if slot_key == "pistol" then
        new_key = "hip_visual"
        old_key = "hip_probe_visual"
    elseif slot_key == "medicine" then
        new_key = "medicine_visual"
        old_key = "medicine_probe_visual"
    end
    local v = vis and vis[new_key]
    if type(v) ~= "table" then v = vis and vis[old_key] end
    return (type(v) == "table") and v or nil
end

-- Instant mesh-aligned grab volume for hip/knife/medicine.
-- Center follows live zone + visual mesh_off (not smoothed mesh publish).
-- Extents/orientation reuse the latest published mesh AABB when available.
-- While medicine is held, ignore in-hand bottle publish quat so put-back uses
-- the same park-oriented volume as grab-from-holster.
HJ.build_slot_grab_mesh = function(slot_key, holster_pos)
    if not holster_pos then return nil end
    local vis = HJ.probe_visual_for_slot(slot_key)
    local tr, tu, tf = holster_transforms.right, holster_transforms.up, holster_transforms.fwd
    local center = HJ.mesh_aligned_from_visual(holster_pos, vis, tr, tu, tf) or holster_pos
    local med_held = slot_key == "medicine" and rawget(_G, "__re8_medicine_in_hand") == true
    local mesh = nil
    if not med_held and type(FLY) == "table" and type(FLY.mesh_key) == "function" then
        mesh = rawget(_G, FLY.mesh_key(slot_key))
    end
    if type(mesh) == "table" and type(mesh.x) == "number" then
        local age = os.clock() - (tonumber(mesh.t) or 0)
        if age >= 0 and age < 0.20 then
            center = { x = mesh.x, y = mesh.y, z = mesh.z }
        end
    end
    local grab = {
        x = center.x, y = center.y, z = center.z,
        cx = center.x, cy = center.y, cz = center.z,
        t = os.clock(),
    }
    if type(mesh) == "table" then
        if type(mesh.ex) == "number" and type(mesh.ey) == "number" and type(mesh.ez) == "number" then
            grab.ex, grab.ey, grab.ez = mesh.ex, mesh.ey, mesh.ez
            grab.tight = true
        end
        if type(mesh.qw) == "number" then
            grab.qw = mesh.qw
            grab.qx = mesh.qx or 0
            grab.qy = mesh.qy or 0
            grab.qz = mesh.qz or 0
            grab.obb = true
        elseif mesh.obb == true then
            grab.obb = true
        end
        if type(mesh.r) == "number" then grab.r = mesh.r end
        if mesh.chris_aabb_shift == true
            and type(mesh.cx) == "number" and type(mesh.cy) == "number" and type(mesh.cz) == "number" then
            grab.x, grab.y, grab.z = mesh.cx, mesh.cy, mesh.cz
            grab.cx, grab.cy, grab.cz = mesh.cx, mesh.cy, mesh.cz
        else
            local lox = tonumber(mesh.lox) or 0
            local loy = tonumber(mesh.loy) or 0
            local loz = tonumber(mesh.loz) or 0
            if (lox * lox + loy * loy + loz * loz) > 0.0001 and type(grab.qw) == "number" then
                pcall(function()
                    local q = Quaternion.new(grab.qw, grab.qx or 0, grab.qy or 0, grab.qz or 0)
                    local wo = q * Vector3f.new(lox, loy, loz)
                    if wo and type(wo.x) == "number" then
                        grab.x = grab.x + wo.x
                        grab.y = grab.y + wo.y
                        grab.z = grab.z + wo.z
                        grab.cx, grab.cy, grab.cz = grab.x, grab.y, grab.z
                    end
                end)
            end
        end
    end
    if med_held and vis and tr and tu and tf then
        pcall(function()
            local bas = Matrix4x4f.new(
                tr.x, tr.y, tr.z, 0,
                tu.x, tu.y, tu.z, 0,
                tf.x, tf.y, tf.z, 0,
                0, 0, 0, 1):to_quat()
            local offset = Quaternion.new(Vector3f.new(
                math.rad(tonumber(vis.rot_pitch) or 0),
                math.rad(tonumber(vis.rot_yaw) or 0),
                math.rad(tonumber(vis.rot_roll) or 0)
            )):normalized()
            local q = bas * offset
            grab.qw, grab.qx, grab.qy, grab.qz = q.w, q.x, q.y, q.z
            grab.obb = true
        end)
    end
    if type(grab.ex) ~= "number" then
        if slot_key == "knife" then
            grab.ex, grab.ey, grab.ez = 0.05, 0.04, 0.14
        elseif slot_key == "medicine" then
            grab.ex, grab.ey, grab.ez = 0.05, 0.07, 0.05
        else
            grab.ex, grab.ey, grab.ez = 0.07, 0.06, 0.12
        end
    end
    return grab
end

HJ.mesh_grab_hit = function(hand_pos, mesh, scale, exit_pad)
    if not hand_pos or type(mesh) ~= "table" then
        return false, -1
    end
    local s = tonumber(scale) or 1.10
    if s < 0.50 then s = 0.50 end
    if s > 3.0 then s = 3.0 end
    local base_pad = 0.04
    if mesh.tight == true then
        base_pad = 0.008
        if s > 1.02 then s = 1.02 end
    end
    local pad = base_pad + (tonumber(exit_pad) or 0)
    local cx = tonumber(mesh.cx) or tonumber(mesh.x)
    local cy = tonumber(mesh.cy) or tonumber(mesh.y)
    local cz = tonumber(mesh.cz) or tonumber(mesh.z)
    if type(cx) ~= "number" then return false, -1 end
    local dx = hand_pos.x - cx
    local dy = hand_pos.y - cy
    local dz = hand_pos.z - cz
    local ex = tonumber(mesh.ex)
    local ey = tonumber(mesh.ey)
    local ez = tonumber(mesh.ez)
    local qw = tonumber(mesh.qw)
    if mesh.obb == true and type(qw) == "number"
        and type(ex) == "number" and type(ey) == "number" and type(ez) == "number" then
        local qx = tonumber(mesh.qx) or 0
        local qy = tonumber(mesh.qy) or 0
        local qz = tonumber(mesh.qz) or 0
        local ix, iy, iz, iw = -qx, -qy, -qz, qw
        local tx = 2.0 * (iy * dz - iz * dy + iw * dx)
        local ty = 2.0 * (iz * dx - ix * dz + iw * dy)
        local tz = 2.0 * (ix * dy - iy * dx + iw * dz)
        local lx = dx + (iy * tz - iz * ty)
        local ly = dy + (iz * tx - ix * tz)
        local lz = dz + (ix * ty - iy * tx)
        local hx = ex * s + pad
        local hy = ey * s + pad
        local hz = ez * s + pad
        local inside = math.abs(lx) <= hx and math.abs(ly) <= hy and math.abs(lz) <= hz
        local ox = math.abs(lx) - hx
        if ox < 0 then ox = 0 end
        local oy = math.abs(ly) - hy
        if oy < 0 then oy = 0 end
        local oz = math.abs(lz) - hz
        if oz < 0 then oz = 0 end
        return inside, math.sqrt(ox * ox + oy * oy + oz * oz)
    end
    if type(ex) == "number" and type(ey) == "number" and type(ez) == "number" then
        local hx = ex * s + pad
        local hy = ey * s + pad
        local hz = ez * s + pad
        local inside = math.abs(dx) <= hx and math.abs(dy) <= hy and math.abs(dz) <= hz
        local ox = math.abs(dx) - hx
        if ox < 0 then ox = 0 end
        local oy = math.abs(dy) - hy
        if oy < 0 then oy = 0 end
        local oz = math.abs(dz) - hz
        if oz < 0 then oz = 0 end
        return inside, math.sqrt(ox * ox + oy * oy + oz * oz)
    end
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    local r = tonumber(mesh.r)
    if type(r) ~= "number" or r < 0.06 then r = 0.12 end
    return d <= (r * s + pad), d
end

HJ.refresh_contact_joints = function()
    local now = os.clock()
    local cache = HJ.contact_joints
    if cache and (now - (HJ.contact_joint_t or 0)) < 1.25 then
        local ok = true
        for i = 1, #cache do
            local e = cache[i]
            if not e or not e.j or not managed_object_alive(e.j) then
                ok = false
                break
            end
        end
        if ok then return cache end
    end
    local out = {}
    local transforms = HJ.collect_transforms()
    for _, name in ipairs(HJ.CONTACT_NAMES) do
        for _, entry in ipairs(transforms) do
            local j = safe_call(entry.tf, "getJointByName", name)
            if j then
                out[#out + 1] = { j = j, name = name }
                break
            end
        end
    end
    HJ.contact_joints = out
    HJ.contact_joint_t = now
    return out
end

HJ.get_right_contact_points = function(fallback_pos)
    local f = HJ.frame or 0
    local pts = HJ._contact_pts
    if not (pts and HJ._contact_pts_f == f) then
        pts = {}
        local joints = HJ.refresh_contact_joints()
        for i = 1, #joints do
            local e = joints[i]
            local p = nil
            pcall(function() p = e.j:call("get_Position") end)
            if p and type(p.x) == "number" then
                pts[#pts + 1] = { x = p.x, y = p.y, z = p.z, name = e.name }
            end
        end
        HJ._contact_pts = pts
        HJ._contact_pts_f = f
    end
    if #pts == 0 and fallback_pos and type(fallback_pos.x) == "number" then
        return { { x = fallback_pos.x, y = fallback_pos.y, z = fallback_pos.z, name = "wrist_fallback" } }
    end
    return pts
end

HJ.mesh_grab_contact = function(points, mesh, scale, exit_pad)
    if type(points) ~= "table" or #points == 0 then
        return false, -1, "", 0
    end
    local best_d = 1e9
    local best_name = ""
    local hit = false
    for i = 1, #points do
        local p = points[i]
        local ok, d = HJ.mesh_grab_hit(p, mesh, scale, exit_pad)
        if type(d) == "number" and d < best_d then
            best_d = d
            best_name = tostring(p.name or "")
        end
        if ok then hit = true end
    end
    if best_d > 1e8 then best_d = -1 end
    return hit, best_d, best_name, #points
end

HJ.mesh_aligned_from_visual = function(zone_pos, vis, right, up, fwd)
    if not zone_pos or not vis then return nil end
    local lx = tonumber(vis.mesh_off_right) or 0
    local ly = tonumber(vis.mesh_off_up) or 0
    local lz = tonumber(vis.mesh_off_forward) or 0
    if lx == 0 and ly == 0 and lz == 0 then
        return { x = zone_pos.x, y = zone_pos.y, z = zone_pos.z }
    end
    local wo = nil
    if right and up and fwd then
        pcall(function()
            local bas = Matrix4x4f.new(
                right.x, right.y, right.z, 0,
                up.x, up.y, up.z, 0,
                fwd.x, fwd.y, fwd.z, 0,
                0, 0, 0, 1):to_quat()
            local offset = Quaternion.new(Vector3f.new(
                math.rad(tonumber(vis.rot_pitch) or 0),
                math.rad(tonumber(vis.rot_yaw) or 0),
                math.rad(tonumber(vis.rot_roll) or 0)
            )):normalized()
            local q = bas * offset
            wo = q * Vector3f.new(lx, ly, lz)
        end)
    end
    if wo and type(wo.x) == "number" then
        return { x = zone_pos.x + wo.x, y = zone_pos.y + wo.y, z = zone_pos.z + wo.z }
    end
    if right and up and fwd then
        return {
            x = zone_pos.x + right.x * lx + up.x * ly + fwd.x * lz,
            y = zone_pos.y + right.y * lx + up.y * ly + fwd.y * lz,
            z = zone_pos.z + right.z * lx + up.z * ly + fwd.z * lz,
        }
    end
    return nil
end

local function publish_holster_zone_world(slot_key, holster_pos, P)
    if not holster_pos or type(holster_pos.x) ~= "number" then return end
    if slot_key == "pistol" then
        local off_r, off_u, off_f = get_profile_slot_offsets(P, "pistol")
        local tr, tu, tf = holster_transforms.right, holster_transforms.up, holster_transforms.fwd
        rawset(_G, "__re8_hip_zone_world", {
            x = holster_pos.x, y = holster_pos.y, z = holster_pos.z,
            joint = (HJ.last_joint_name ~= "" and HJ.last_joint_name) or (holster_transforms.src ~= "" and holster_transforms.src) or "Hip",
            off_r = off_r, off_u = off_u, off_f = off_f,
            rx = tr and tr.x, ry = tr and tr.y, rz = tr and tr.z,
            ux = tu and tu.x, uy = tu and tu.y, uz = tu and tu.z,
            fx = tf and tf.x, fy = tf and tf.y, fz = tf and tf.z,
            t = os.clock(),
        })
    elseif slot_key == "knife" then
        local off_r, off_u, off_f = get_profile_slot_offsets(P, "knife")
        local tr, tu, tf = holster_transforms.right, holster_transforms.up, holster_transforms.fwd
        rawset(_G, "__re8_knife_zone_world", {
            x = holster_pos.x, y = holster_pos.y, z = holster_pos.z,
            joint = (HJ.last_joint_name ~= "" and HJ.last_joint_name) or (holster_transforms.src ~= "" and holster_transforms.src) or "Spine_2",
            off_r = off_r, off_u = off_u, off_f = off_f,
            rx = tr and tr.x, ry = tr and tr.y, rz = tr and tr.z,
            ux = tu and tu.x, uy = tu and tu.y, uz = tu and tu.z,
            fx = tf and tf.x, fy = tf and tf.y, fz = tf and tf.z,
            t = os.clock(),
        })
    elseif slot_key == "medicine" then
        local off_r, off_u, off_f = get_profile_slot_offsets(P, "medicine")
        local tr, tu, tf = holster_transforms.right, holster_transforms.up, holster_transforms.fwd
        rawset(_G, "__re8_medicine_zone_world", {
            x = holster_pos.x, y = holster_pos.y, z = holster_pos.z,
            joint = (HJ.last_joint_name ~= "" and HJ.last_joint_name) or (holster_transforms.src ~= "" and holster_transforms.src) or "Spine_2",
            off_r = off_r, off_u = off_u, off_f = off_f,
            rx = tr and tr.x, ry = tr and tr.y, rz = tr and tr.z,
            ux = tu and tu.x, uy = tu and tu.y, uz = tu and tu.z,
            fx = tf and tf.x, fy = tf and tf.y, fz = tf and tf.z,
            t = os.clock(),
        })
    end
end

STOW.publish_visual_mesh_zones = function()
    if CFG.holster_zone_motion_sync ~= true or CFG.enabled ~= true then return end
    local P = get_profile()
    local pos
    if CFG.hip_pistol_enabled and rawget(_G, "__visceral_holsters_on") ~= true then
        pos = HJ.slot_world_pos("pistol", P)
        if pos then publish_holster_zone_world("pistol", pos, P) end
    end
    if CFG.knife_enabled then
        pos = HJ.slot_world_pos("knife", P)
        if pos then publish_holster_zone_world("knife", pos, P) end
    end
    if CFG.medicine_enabled then
        pos = HJ.slot_world_pos("medicine", P)
        if pos then publish_holster_zone_world("medicine", pos, P) end
    end
    if CFG.shoulder_enabled and rawget(_G, "__visceral_holsters_on") ~= true then
        pos = HJ.slot_world_pos("longarm", P)
        if pos then publish_holster_zone_world("longarm", pos, P) end
    end
end
rawset(_G, "__re8_holster_publish_visual_zones", STOW.publish_visual_mesh_zones)

local function refresh_hmd_holster_zone(holster_state, slot_key, P, trigger_dist, release_dist, hand_pos, rj)
    if not hand_pos then
        holster_state.in_zone = false
        return
    end
    local holster_pos = HJ.slot_world_pos(slot_key, P)
    if not holster_pos then
        holster_state.in_zone = false
        return
    end
    if slot_key == "pistol" or slot_key == "knife" or slot_key == "medicine" or slot_key == "longarm" then
        publish_holster_zone_world(slot_key, holster_pos, P)
        if slot_key == "pistol" and (os.clock() - (HJ.zone_log_t or 0)) > 1.0 then
            HJ.zone_log_t = os.clock()
        elseif slot_key == "knife" and (os.clock() - (HJ.knife_zone_log_t or 0)) > 1.0 then
            HJ.knife_zone_log_t = os.clock()
        end
    end
    -- Mag-in-hand: keep zone world publishes (probe meshes use them) but
    -- skip finger mesh-grab. Grab is already suppressed for these slots.
    if slot_key ~= "ammo_left"
        and (manual_reload_blocks_holster() or (re8vr and re8vr.is_reloading == true)) then
        holster_state.in_zone = false
        return
    end
    -- Grab/stow tests against the same live mesh volume (hip/knife/medicine).
    -- Medicine put-back used to use wrist-sphere distance while grab used
    -- finger contact + OBB — same center, different feel. Both share this path.
    -- Shoulder + ammo keep sphere zones below.
    local grab_pos = holster_pos
    local grab_src = "zone"
    if slot_key == "pistol" or slot_key == "knife" or slot_key == "medicine" then
        local built = HJ.build_slot_grab_mesh(slot_key, holster_pos)
        if built then
            grab_pos = built
            grab_src = "mesh_live"
            if slot_key == "medicine" and rawget(_G, "__re8_medicine_in_hand") == true then
                grab_src = "mesh_live_stow"
            end
        end
        local scale = 1.10
        if slot_key == "pistol" then
            scale = tonumber(P and P.hip_pistol_grab_scale) or 1.10
            if grab_pos and grab_pos.tight == true and scale > 1.0 then
                scale = 1.0
            end
        elseif slot_key == "knife" then
            scale = tonumber(P and P.knife_grab_scale) or 1.10
            if STOW.is_chris_player() and scale > 1.05 then
                scale = 1.05
            end
            if grab_pos and grab_pos.tight == true and scale > 1.0 then
                scale = 1.0
            end
        else
            scale = tonumber(P and P.medicine_grab_scale) or 1.10
            if STOW.is_chris_player() == true and scale > 1.0 then
                scale = 1.0
            end
        end
        local pts = HJ.get_right_contact_points(hand_pos)
        if slot_key == "pistol" or slot_key == "knife" or slot_key == "medicine" then
            local finger_pts = {}
            for i = 1, #pts do
                local p = pts[i]
                local n = p and tostring(p.name or "") or ""
                if n ~= "" and n ~= "R_Hand" and n ~= "r_arm_wrist" and n ~= "R_Palm" then
                    finger_pts[#finger_pts + 1] = p
                end
            end
            if #finger_pts > 0 then pts = finger_pts end
        end
        local enter_hit, best_d, best_name, n_pts = HJ.mesh_grab_contact(pts, grab_pos, scale, 0)
        local exit_hit = HJ.mesh_grab_contact(pts, grab_pos, scale, 0.025)
        local gcx = tonumber(grab_pos.cx) or tonumber(grab_pos.x) or 0
        local gcy = tonumber(grab_pos.cy) or tonumber(grab_pos.y) or 0
        local gcz = tonumber(grab_pos.cz) or tonumber(grab_pos.z) or 0
        local d_wrist = vec3_dist(hand_pos, { x = gcx, y = gcy, z = gcz })
        local d_mesh = (type(best_d) == "number" and best_d >= 0) and best_d or d_wrist
        local d_zone = vec3_dist(hand_pos, holster_pos)
        holster_state.last_dist = d_mesh
        holster_state.last_dist_zone = d_zone
        holster_state.grab_src = grab_src
        holster_state._grab_scale = scale
        local was_in_zone = holster_state.in_zone == true
        if not holster_state.in_zone then
            if enter_hit then holster_state.in_zone = true end
        else
            if not exit_hit then holster_state.in_zone = false end
        end
        if holster_state.in_zone and not was_in_zone then
            holster_state.zone_enter_pulse = true
        end
        if not holster_state.in_zone then
            holster_state.haptic_pending_frames = 0
            holster_state.zone_enter_pulse = false
        elseif slot_key ~= "medicine" then
            STOW.maybe_zone_haptic(holster_state, rj, slot_key)
        end
        return
    end
    local d = vec3_dist(hand_pos, grab_pos)
    local d_zone = vec3_dist(hand_pos, holster_pos)
    holster_state.last_dist = d
    holster_state.last_dist_zone = d_zone
    holster_state.grab_src = grab_src
    local was_in_zone = holster_state.in_zone == true
    if not holster_state.in_zone then
        if d <= trigger_dist then holster_state.in_zone = true end
    else
        if d > release_dist then holster_state.in_zone = false end
    end
    if (slot_key == "pistol" or slot_key == "knife")
        and (os.clock() - (holster_state._zm_log_t or 0)) > 0.10 then
        holster_state._zm_log_t = os.clock()
        local mesh_zone_d = -1
        if grab_src ~= "zone" then
            mesh_zone_d = vec3_dist(grab_pos, holster_pos)
        end
        local edge = ""
        if holster_state.in_zone and not was_in_zone then edge = "enter"
        elseif (not holster_state.in_zone) and was_in_zone then edge = "exit" end
        local slack = (type(d) == "number" and type(trigger_dist) == "number") and (d - trigger_dist) or 0
    end
    if holster_state.in_zone and not was_in_zone then
        holster_state.zone_enter_pulse = true
    end
    if not holster_state.in_zone then
        holster_state.haptic_pending_frames = 0
        holster_state.zone_enter_pulse = false
    else
        STOW.maybe_zone_haptic(holster_state, rj, slot_key)
    end
    if slot_key == "ammo_left" and holster_state.in_zone and holster_state.zone_enter_pulse == false
        and (os.clock() - (HJ.ammo_hap_log_t or 0)) > 1.0 then
        HJ.ammo_hap_log_t = os.clock()
    end
    if slot_key == "ammo_left" then
        local off_r, off_u, off_f = get_profile_slot_offsets(P, "ammo_left")
        rawset(_G, "__re8_ammo_hip_zone_world", {
            x = holster_pos.x, y = holster_pos.y, z = holster_pos.z,
            joint = HJ.last_joint_name or "",
            off_r = off_r, off_u = off_u, off_f = off_f,
            in_zone = holster_state.in_zone == true,
            dist = holster_state.last_dist or 0.0,
            t = os.clock(),
        })
    end
end

local function find_remedy_row()
    local P = get_profile()
    local want = P and normalize_item_id(P.last_medicine_id)
    if want and want ~= "" then
        local matched = find_row_for_item_id(want)
        if matched and (is_medicine_core(matched.item_internal) or is_medicine_item_id(matched.item_id)) then
            return matched
        end
    end
    for _, row in ipairs(inventory_rows()) do
        if is_medicine_core(row.item_internal) then
            return row
        end
        if is_medicine_item_id(row.item_id) then
            return row
        end
    end
    return nil
end

local function is_remedy_equipped()
    local item_id = get_current_weapon_item_id()
    if item_id and weapon_type_for_item_id(item_id) == "MED" then return true end
    if HEAL.cached_weapon and re8vr.weapon == HEAL.cached_weapon then return true end
    return false
end

local function dequip_remedy()
    local remedy_row = HEAL.cached_item and {
        item_internal = HEAL.cached_item,
        weapon = HEAL.cached_weapon,
    } or find_remedy_row()
    if not remedy_row or not remedy_row.weapon then return end
    pcall(function() COMPONENTS.weapon_change:call("removeWeaponWithNoAction") end)
    pcall(function() COMPONENTS.weapon_change:call("removeWeapon", false) end)
    if COMPONENTS.mesh_controller then
        pcall(function()
            COMPONENTS.mesh_controller:call("onEquipWeaponChanged", nil, remedy_row.weapon)
        end)
    end
    HEAL.lua_authorized = false
    HEAL.remedy_equipped = false
    if re8vr.update_pointers then pcall(function() re8vr:update_pointers() end) end
end

local function strip_unauthorized_native_heal()
    if not refresh_components(false) then return end
    if not CFG.medicine_enabled then
        medicine.in_zone = false
        rawset(_G, "__vr_in_medicine_zone", false)
        HEAL.grip_began_inside = false
        if is_remedy_equipped() then
            dequip_remedy()
        end
        return
    end
    if is_remedy_equipped() then
        HEAL.lua_authorized = true
    else
        HEAL.lua_authorized = false
    end
end

function HEAL.sync()
    if not CFG.medicine_enabled then
        HEAL.remedy_equipped = false
        return
    end
    strip_unauthorized_native_heal()
    HEAL.in_hand = rawget(_G, "__re8_medicine_in_hand") == true
    if not HEAL.in_hand then
        HEAL.lua_authorized = false
    end
    local now = os.clock()
    local need_row = HEAL.in_hand or HEAL.cached_item == nil
        or ((now - (HEAL._row_poll_t or 0)) > 0.35)
    if need_row then
        HEAL._row_poll_t = now
        local remedy_row = find_remedy_row()
        if remedy_row and remedy_row.item_internal then
            HEAL.cached_item = remedy_row.item_internal
            HEAL.cached_weapon = remedy_row.weapon
        end
    end
    HEAL.remedy_equipped = HEAL.in_hand or is_remedy_equipped()
    if HEAL.use_check_t and os.clock() >= HEAL.use_check_t then
        HEAL.use_check_t = nil
        WEAPON_WATCH.validate_last_t = 0
        local P = get_profile()
        validate_cached_weapons(P)
        bootstrap_last_weapons(P)
        save_cfg()
    end
end

HEAL.axis_from_quat = function(qw, qx, qy, qz, axis)
    qw = tonumber(qw) or 1
    qx = tonumber(qx) or 0
    qy = tonumber(qy) or 0
    qz = tonumber(qz) or 0
    axis = tonumber(axis) or 1
    if axis <= 0 then
        return {
            x = 1.0 - 2.0 * (qy * qy + qz * qz),
            y = 2.0 * (qx * qy + qw * qz),
            z = 2.0 * (qx * qz - qw * qy),
        }
    end
    if axis >= 2 then
        return {
            x = 2.0 * (qx * qz + qw * qy),
            y = 2.0 * (qy * qz - qw * qx),
            z = 1.0 - 2.0 * (qx * qx + qy * qy),
        }
    end
    return {
        x = 2.0 * (qx * qy - qw * qz),
        y = 1.0 - 2.0 * (qx * qx + qz * qz),
        z = 2.0 * (qy * qz + qw * qx),
    }
end

HEAL.left_palm_world = function()
    local tf = get_player_transform()
    local j, pos = nil, nil
    local src = "none"
    pcall(function()
        if tf then j = tf:call("getJointByName", "L_Palm") end
    end)
    if j then
        pcall(function() pos = j:call("get_Position") end)
        if pos and type(pos.x) == "number" then src = "L_Palm" end
    end
    if not pos then
        j = nil
        pcall(function()
            if tf then j = tf:call("getJointByName", "L_Hand") end
        end)
        pcall(function()
            if j then pos = j:call("get_Position") end
        end)
        if pos and type(pos.x) == "number" then src = "L_Hand" end
    end
    if not pos then
        pos = select(1, HJ.get_left_hand_world())
        src = "lh"
    end
    if not (pos and type(pos.x) == "number") then return nil, src end
    local off = tonumber(CFG.medicine_pour_palm_m) or 0.10
    if off < 0 then off = 0 end
    local tip = nil
    pcall(function()
        if not tf then return end
        local tj = tf:call("getJointByName", "L_MiddleF1")
        if not tj then tj = tf:call("getJointByName", "L_IndexF1") end
        if not tj then tj = tf:call("getJointByName", "L_MiddleF2") end
        if tj then tip = tj:call("get_Position") end
    end)
    if tip and type(tip.x) == "number" then
        local vx = tip.x - pos.x
        local vy = tip.y - pos.y
        local vz = tip.z - pos.z
        local len = math.sqrt(vx * vx + vy * vy + vz * vz)
        if len > 0.005 then
            local s = off / len
            return {
                x = pos.x + vx * s,
                y = pos.y + vy * s,
                z = pos.z + vz * s,
            }, src .. "+fingers"
        end
    end
    local az = nil
    pcall(function()
        if j then az = j:call("get_AxisZ") end
        if not az then
            local ik = re8vr and re8vr.left_hand_ik_transform
            if ik then az = ik:call("get_AxisZ") end
        end
    end)
    if az and type(az.x) == "number" then
        return {
            x = pos.x + az.x * off,
            y = pos.y + az.y * off,
            z = pos.z + az.z * off,
        }, src .. "+Z"
    end
    return pos, src
end

HEAL.use_inject_gesture = function()
    if STOW.is_chris_player() == true then return true end
    local id = nil
    pcall(function()
        local P = get_profile()
        id = P and P.last_medicine_id or nil
    end)
    if type(id) ~= "string" or id == "" then
        id = get_current_weapon_item_id()
    end
    if type(id) ~= "string" then return false end
    -- Village syringe (ri1022) uses inject; bottles pour into left palm.
    if id == "ri1022" then return true end
    return id:find("Ampoule", 1, true) ~= nil
end

HEAL.eval_inject = function()
    local st = {
        ok = false,
        dist = -1,
        tgt = "",
        near_ok = false,
        above_ok = true,
        invert_ok = true,
        src = "inject",
        bottle_src = "multi",
    }
    local rh = select(1, HJ.get_right_hand_world())
    if not (rh and type(rh.x) == "number") then return st end
    local probes = { rh }
    local mesh = rawget(_G, "__re8_medicine_mesh_world")
    if type(mesh) == "table" and type(mesh.x) == "number" then
        probes[#probes + 1] = mesh
    end
    local ax, ay = nil, nil
    pcall(function()
        local tf = re8vr and re8vr.right_hand_ik_transform
        if not tf then return end
        ax = tf:call("get_AxisX")
        ay = tf:call("get_AxisY")
    end)
    local off = tonumber(CFG.medicine_inject_bottom_m) or 0.07
    if ay and type(ay.x) == "number" then
        probes[#probes + 1] = { x = rh.x - ay.x * off, y = rh.y - ay.y * off, z = rh.z - ay.z * off }
        probes[#probes + 1] = { x = rh.x + ay.x * off, y = rh.y + ay.y * off, z = rh.z + ay.z * off }
    end
    if ax and type(ax.x) == "number" then
        probes[#probes + 1] = { x = rh.x - ax.x * off, y = rh.y - ax.y * off, z = rh.z - ax.z * off }
    end
    local tf = get_player_transform()
    if not tf then return st end
    local names = {
        "L_Forearm", "L_UpperArm", "L_Arm", "l_arm_elbow", "L_Elbow",
        "l_arm_wrist", "L_Wrist",
    }
    local grab_age = os.clock() - (tonumber(HEAL.last_grab_t) or -99)
    local locked = grab_age < 0.85 or os.clock() < (tonumber(HEAL._inject_lock_until) or 0)
    local in_med_zone = medicine.in_zone == true
    if locked ~= true and in_med_zone ~= true then
        names[#names + 1] = "Spine_2"
    end
    local best, best_n = nil, ""
    for i = 1, #names do
        local j, p = nil, nil
        pcall(function() j = tf:call("getJointByName", names[i]) end)
        pcall(function()
            if j then p = j:call("get_Position") end
        end)
        if p and type(p.x) == "number" then
            for pi = 1, #probes do
                local tip = probes[pi]
                local dx, dy, dz = tip.x - p.x, tip.y - p.y, tip.z - p.z
                local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                if best == nil or d < best then
                    best = d
                    best_n = names[i]
                end
            end
        end
    end
    st.dist = best or -1
    st.tgt = best_n
    st.horiz = st.dist
    local need = tonumber(CFG.medicine_inject_m) or 0.24
    local release = need + 0.08
    if HEAL._inj_latched == true then
        st.near_ok = type(best) == "number" and best <= release
    else
        st.near_ok = type(best) == "number" and best <= need
    end
    st.ok = st.near_ok == true
    if locked or in_med_zone then
        st.ok = false
        st.near_ok = false
        HEAL._inj_latched = false
        st.bottle_src = locked and "lock" or "zone"
    else
        HEAL._inj_latched = st.ok == true
    end
    return st
end

HEAL.eval_pour = function()
    local st = {
        ok = false,
        dist = -1,
        horiz = -1,
        above = -1,
        invert_dot = 0,
        ax = 0, ay = 0, az = 0,
        near_ok = false,
        above_ok = false,
        invert_ok = false,
        src = "",
        palm_src = "",
        bottle_src = "",
        axis = tonumber(CFG.medicine_pour_axis) or 1,
    }
    local rh = HJ.get_right_hand_world()
    local palm, palm_src = HEAL.left_palm_world()
    st.palm_src = tostring(palm_src or "")
    local mesh = rawget(_G, "__re8_medicine_mesh_world")
    local bottle = rh
    st.bottle_src = "hand"
    if type(mesh) == "table" and type(mesh.x) == "number" then
        bottle = mesh
        st.bottle_src = "mesh"
    end
    if not (bottle and palm and type(bottle.x) == "number" and type(palm.x) == "number") then
        return st
    end
    local dx = bottle.x - palm.x
    local dy = bottle.y - palm.y
    local dz = bottle.z - palm.z
    st.dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    st.horiz = math.sqrt(dx * dx + dz * dz)
    st.above = dy
    local xy_m = tonumber(CFG.medicine_pour_xy_m) or 0.24
    local above_m = tonumber(CFG.medicine_pour_above_m) or 0.05
    local dot_need = tonumber(CFG.medicine_pour_dot) or -0.50
    st.near_ok = st.horiz <= xy_m
    st.above_ok = st.above >= above_m
    local axis = st.axis
    local sign = tonumber(CFG.medicine_pour_axis_sign) or 1.0
    if sign >= 0 then sign = 1.0 else sign = -1.0 end
    if type(mesh) == "table" and type(mesh.qw) == "number" then
        local a = HEAL.axis_from_quat(mesh.qw, mesh.qx, mesh.qy, mesh.qz, axis)
        st.ax, st.ay, st.az = a.x * sign, a.y * sign, a.z * sign
        st.src = "mesh"
    else
        local tf = re8vr and re8vr.right_hand_ik_transform
        local a = nil
        pcall(function()
            if not tf then return end
            if axis <= 0 then a = tf:call("get_AxisX")
            elseif axis >= 2 then a = tf:call("get_AxisZ")
            else a = tf:call("get_AxisY") end
        end)
        if a and type(a.x) == "number" then
            st.ax, st.ay, st.az = a.x * sign, a.y * sign, a.z * sign
            st.src = "ik"
        else
            st.src = "none"
        end
    end
    st.invert_dot = st.ay
    st.invert_ok = st.invert_dot <= dot_need
    st.ok = st.near_ok and st.above_ok and st.invert_ok
    return st
end

HEAL.world_ctrl = function(which)
    local key = (which == "left") and "__vr_lh_world" or "__vr_rh_world"
    local p = rawget(_G, key)
    if p ~= nil and type(p.x) == "number" then return p, "vr_world" end
    local pos = nil
    pcall(function()
        if not vrmod then return end
        local cam = sdk.get_primary_camera()
        if not cam then return end
        local go = cam:call("get_GameObject")
        local xf = go and go:call("get_Transform")
        local wm = xf and xf:call("get_WorldMatrix")
        if not wm then return end
        local idx = (which == "left") and 1 or 2
        local controllers = vrmod:get_controllers()
        if controllers and controllers[idx] ~= nil then idx = controllers[idx] end
        local ctrl = vrmod:get_position(idx)
        local hmd = vrmod:get_position(0)
        if not (ctrl and hmd and type(ctrl.x) == "number") then return end
        local dx, dy, dz = ctrl.x - hmd.x, ctrl.y - hmd.y, ctrl.z - hmd.z
        local r = vec3_normalize(matrix_col(wm, 0))
        local u = vec3_normalize(matrix_col(wm, 1))
        local f = vec3_normalize(matrix_col(wm, 2))
        local c = matrix_col(wm, 3)
        if not (r and u and f and c) then return end
        pos = {
            x = c.x + dx * r.x + dy * u.x + dz * f.x,
            y = c.y + dx * r.y + dy * u.y + dz * f.y,
            z = c.z + dx * r.z + dy * u.z + dz * f.z,
        }
    end)
    if pos and type(pos.x) == "number" then return pos, "cam_project" end
    return nil, "none"
end

HEAL.read_ik_gate = function()
    local g = {
        can_hands = re8vr and re8vr.can_use_hands == true,
        motion_play = re8vr and re8vr.is_motion_play == true,
        cut = re8vr and re8vr.is_in_cutscene == true,
        gripping = re8vr and re8vr.was_gripping_weapon == true,
        lgrip = re8vr and re8vr.is_holding_left_grip == true,
        wants_block = re8vr and re8vr.wants_block == true,
        wants_heal = re8vr and re8vr.wants_heal == true,
        l_trans = -1,
        r_trans = -1,
        rh_vs_ik = -1,
        lh_vs_ik = -1,
        lh_ctrl_vs_ik = -1,
        rh_ctrl_vs_ik = -1,
        skip_ik = false,
        override = type(rawget(_G, "__re8_arm_ik_update_override")) == "function",
    }
    g.skip_ik = g.can_hands ~= true
    pcall(function()
        local lik = re8vr and re8vr.left_hand_ik
        local rik = re8vr and re8vr.right_hand_ik
        if lik then g.l_trans = tonumber(lik:get_field("Transition")) or -1 end
        if rik then g.r_trans = tonumber(rik:get_field("Transition")) or -1 end
    end)
    local tf = get_player_transform()
    local function dist_ab(a, b)
        if not (a and b and type(a.x) == "number" and type(b.x) == "number") then return -1 end
        local dx = a.x - b.x
        local dy = a.y - b.y
        local dz = a.z - b.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end
    local function dist_joint(name, iktf)
        if not tf or not iktf then return -1 end
        local jp, ip = nil, nil
        pcall(function()
            local j = tf:call("getJointByName", name)
            if j then jp = j:call("get_Position") end
            ip = iktf:call("get_Position")
        end)
        return dist_ab(jp, ip)
    end
    g.rh_vs_ik = dist_joint("R_Hand", re8vr and re8vr.right_hand_ik_transform)
    g.lh_vs_ik = dist_joint("L_Hand", re8vr and re8vr.left_hand_ik_transform)
    local lc = select(1, HEAL.world_ctrl("left"))
    local rc = select(1, HEAL.world_ctrl("right"))
    local lip, rip = nil, nil
    pcall(function()
        if re8vr and re8vr.left_hand_ik_transform then
            lip = re8vr.left_hand_ik_transform:call("get_Position")
        end
        if re8vr and re8vr.right_hand_ik_transform then
            rip = re8vr.right_hand_ik_transform:call("get_Position")
        end
    end)
    g.lh_ctrl_vs_ik = dist_ab(lc, lip)
    g.rh_ctrl_vs_ik = dist_ab(rc, rip)
    return g
end

HEAL.read_native_use_state = function()
    local st = {
        action_id = -1,
        use_req = false,
        use_tried = false,
        heal_l = false,
        heal_r = false,
        wants_heal = re8vr and re8vr.wants_heal == true,
    }
    local wc = COMPONENTS.weapon_change
    if wc then
        pcall(function() st.action_id = tonumber(wc:call("get_actionID")) or -1 end)
        pcall(function() st.use_req = wc:call("get_isUseItemRequested") == true end)
        pcall(function() st.use_tried = wc:call("get_isUseItemTried") == true end)
    end
    pcall(function()
        if not vrmod then return end
        local act = vrmod.get_action_heal and vrmod:get_action_heal()
        if not act then return end
        local lj = vrmod.get_left_joystick and vrmod:get_left_joystick()
        local rj = vrmod.get_right_joystick and vrmod:get_right_joystick()
        if lj then st.heal_l = vrmod:is_action_active(act, lj) == true end
        if rj then st.heal_r = vrmod:is_action_active(act, rj) == true end
    end)
    return st
end

HEAL.persist_ik = function(hid, loc, msg, data)
    return
end

HEAL.should_keep_ik = function()
    if rawget(_G, "__re8_medicine_in_hand") == true then return true end
    local until_t = tonumber(HEAL._ik_until) or 0
    if until_t > 0 and os.clock() < until_t then return true end
    return false
end

HEAL.force_ik_trans = function()
    if not re8vr then return end
    pcall(function()
        local lik = re8vr.left_hand_ik
        local rik = re8vr.right_hand_ik
        if lik then
            lik:set_field("Transition", 1.0)
            lik:call("calc")
        end
        if rik then
            rik:set_field("Transition", 1.0)
            rik:call("calc")
        end
    end)
end

HEAL.apply_one_ik = function(ik, tf, pos, rot)
    if not ik or not tf or not pos or not rot then return false end
    pcall(function()
        if re8vr and re8vr.set_hand_joints_to_tpose then
            re8vr:set_hand_joints_to_tpose(ik)
        end
    end)
    pcall(function()
        tf:call("set_Position", Vector3f.new(pos.x, pos.y, pos.z))
    end)
    pcall(function()
        tf:call("set_Rotation", rot)
    end)
    pcall(function() ik:set_field("Transition", 1.0) end)
    pcall(function() ik:call("calc") end)
    return true
end

HEAL.apply_free_both = function()
    if re8vr == nil or not vrmod then return false end
    if not vrmod:is_hmd_active() or not vrmod:is_using_controllers() then return false end
    re8vr.can_use_hands = true
    local controllers = vrmod:get_controllers()
    if not controllers or not controllers[1] or not controllers[2] then return false end
    local left_m = vrmod:get_transform(controllers[1])
    local right_m = vrmod:get_transform(controllers[2])
    local hmd_m = vrmod:get_transform(0)
    local camera = sdk.get_primary_camera()
    if not left_m or not right_m or not hmd_m or not camera then return false end
    local cam_m = nil
    pcall(function() cam_m = camera:call("get_WorldMatrix") end)
    if not cam_m or not cam_m[3] then return false end
    local original_camera_rotation = cam_m:to_quat()
    local updated_camera_pos = Vector3f.new(cam_m[3].x, cam_m[3].y, cam_m[3].z)
    pcall(function()
        vrmod:apply_hmd_transform(original_camera_rotation, updated_camera_pos)
    end)
    local hmd_rotation = hmd_m:to_quat()
    original_camera_rotation = (original_camera_rotation * hmd_rotation:inverse()):normalized()
    local left_controller_rotation = left_m:to_quat()
    local right_controller_rotation = right_m:to_quat()
    local left_controller_offset = Vector3f.new(
        left_m[3].x - hmd_m[3].x,
        left_m[3].y - hmd_m[3].y,
        left_m[3].z - hmd_m[3].z)
    local right_controller_offset = Vector3f.new(
        right_m[3].x - hmd_m[3].x,
        right_m[3].y - hmd_m[3].y,
        right_m[3].z - hmd_m[3].z)
    local lh_roff = re8vr.left_hand_rotation_offset
    local rh_roff = re8vr.right_hand_rotation_offset
    local lh_poff = re8vr.left_hand_position_offset
    local rh_poff = re8vr.right_hand_position_offset
    if not lh_roff or not rh_roff or not lh_poff or not rh_poff then return false end
    local rh_rotation = (original_camera_rotation * right_controller_rotation * rh_roff):normalized()
    local rh_basis = (original_camera_rotation * right_controller_rotation):normalized()
    local rh_pos = updated_camera_pos
        + (original_camera_rotation * right_controller_offset)
        + (rh_basis * Vector3f.new(rh_poff.x, rh_poff.y, rh_poff.z))
    local lh_rotation = (original_camera_rotation * left_controller_rotation * lh_roff):normalized()
    local lh_basis = (original_camera_rotation * left_controller_rotation):normalized()
    local lh_pos = updated_camera_pos
        + (original_camera_rotation * left_controller_offset)
        + (lh_basis * Vector3f.new(lh_poff.x, lh_poff.y, lh_poff.z))
    local ok_l = HEAL.apply_one_ik(re8vr.left_hand_ik, re8vr.left_hand_ik_transform, lh_pos, lh_rotation)
    local ok_r = HEAL.apply_one_ik(re8vr.right_hand_ik, re8vr.right_hand_ik_transform, rh_pos, rh_rotation)
    if not (ok_l and ok_r) then return false end
    pcall(function() re8vr.was_gripping_weapon = false end)
    pcall(function()
        re8vr.last_left_hand_position = lh_pos
        re8vr.last_left_hand_rotation = lh_rotation
        re8vr.last_right_hand_position = rh_pos
        re8vr.last_right_hand_rotation = rh_rotation
    end)
    return true
end

HEAL.apply_keep_ik = function()
    if not HEAL.should_keep_ik() then
        rawset(_G, "__re8_medicine_keep_hand_ik", false)
        HEAL._free_ok = false
        return false
    end
    rawset(_G, "__re8_medicine_keep_hand_ik", true)
    if re8vr then
        re8vr.can_use_hands = true
        pcall(function() re8vr.was_gripping_weapon = false end)
    end
    local ok = HEAL.apply_free_both()
    HEAL._free_ok = ok == true
    if not ok then
        HEAL.force_ik_trans()
    end
    return true
end

HEAL.ammo_owns_ik = function()
    if rawget(_G, "__vr_ammo_insert_arm_follow") == true then return true end
    if rawget(_G, "__vr_ammo_insert_active") == true then return true end
    if rawget(_G, "__vr_iaf_releasing") == true then return true end
    if rawget(_G, "__vr_ammo_in_left_hand") == true then return true end
    if rawget(_G, "__vr_ammo_blocks_weapon_holster") == true then return true end
    return false
end

HEAL.release_ik_keep = function()
    local cur = rawget(_G, "__re8_arm_ik_update_override")
    if cur ~= nil and cur == HEAL._our_override then
        rawset(_G, "__re8_arm_ik_update_override", HEAL._prev_override)
    end
    HEAL._our_override = nil
    rawset(_G, "__re8_medicine_keep_hand_ik", false)
    HEAL._free_ok = false
end

HEAL.is_native_use_active = function()
    if os.clock() < (tonumber(HEAL._use_anim_until) or 0) then return true end
    if HEAL._lua_use_pending == true then return true end
    if HEAL._use_weapon ~= nil then return true end
    local wc = COMPONENTS.weapon_change
    if not wc then return false end
    local flag = false
    pcall(function() flag = wc:call("get_isUseItemRequested") == true end)
    if flag then return true end
    pcall(function() flag = wc:call("get_isUseItemTried") == true end)
    if flag then return true end
    return false
end

HEAL.hide_use_weapon = function()
    local w = HEAL._use_weapon
    if not w or not managed_object_alive(w) then return end
    STOW.hide_orphan_visual(w)
end

HEAL.clear_using_fields = function()
    local wc = COMPONENTS.weapon_change
    if not wc then return end
    pcall(function() wc:call("requestCancelUseItem") end)
    pcall(function() wc:call("set_isUseItemRequested", false) end)
    pcall(function() wc:call("set_isUseItemTried", false) end)
end

HEAL.abort_native_use = function()
    if not HEAL.is_native_use_active() then
        return false
    end
    refresh_components(false)
    HEAL.clear_using_fields()
    HEAL.hide_use_weapon()
    HEAL._use_anim_until = 0
    HEAL._ik_until = 0
    HEAL._use_weapon = nil
    HEAL._lua_use_pending = false
    HEAL.pour_ok_since = nil
    HEAL.pour_fired = false
    HEAL._deactivate_after = nil
    rawset(_G, "__re8_medicine_lua_hidden", false)
    HEAL.release_ik_keep()
    rawset(_G, "__re8_medicine_keep_hand_ik", false)
    rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
    return true
end

-- Visceral RE8 2026-10-31 (Tefa: "using a health potion should give a low constant rumble while the liquid is pouring out
-- for about 2 seconds and then fade in and out"): started when the use goes through (the pour / inject below)
local POUR_RUMBLE = { sec = 2.0, fade = 0.4, amp = 0.25, hz = 80.0, left = 0.6 }   -- left = the catching palm's share
HEAL._pour_rumble_t0 = nil
HEAL.pour_rumble_start = function() HEAL._pour_rumble_t0 = os.clock() end
re.on_frame(function()
    local t0 = HEAL._pour_rumble_t0
    if t0 == nil then return end
    local t = os.clock() - t0
    if t >= POUR_RUMBLE.sec then HEAL._pour_rumble_t0 = nil; return end
    local k = math.max(0.0, math.min(1.0, t / POUR_RUMBLE.fade, (POUR_RUMBLE.sec - t) / POUR_RUMBLE.fade))
    local amp = POUR_RUMBLE.amp * k
    pcall(function()
        haptic_pulse(vrmod:get_right_joystick(), 0.05, POUR_RUMBLE.hz, amp)
        haptic_pulse(vrmod:get_left_joystick(), 0.05, POUR_RUMBLE.hz, amp * POUR_RUMBLE.left)
    end)
end)

rawset(_G, "__re8_heal_abort_native_use", HEAL.abort_native_use)
rawset(_G, "__re8_heal_is_native_use_active", HEAL.is_native_use_active)

HEAL.ensure_ik_keep = function()
    if HEAL.ammo_owns_ik() or not HEAL.should_keep_ik() then
        HEAL.release_ik_keep()
        return
    end
    local cur = rawget(_G, "__re8_arm_ik_update_override")
    if cur == HEAL._our_override and type(cur) == "function" then return end
    HEAL._prev_override = cur
    HEAL._our_override = function()
        if HEAL.ammo_owns_ik() then
            local prev = HEAL._prev_override
            if type(prev) == "function" then
                local ok, handled = pcall(prev)
                if ok and handled == true then return true end
            end
            return false
        end
        if HEAL.should_keep_ik() then
            HEAL.apply_keep_ik()
            return true
        end
        local prev = HEAL._prev_override
        if type(prev) == "function" then
            local ok, handled = pcall(prev)
            if ok and handled == true then return true end
        end
        return false
    end
    rawset(_G, "__re8_arm_ik_update_override", HEAL._our_override)
end

HEAL.on_late_ik = function()
    if HEAL.ammo_owns_ik() or not HEAL.should_keep_ik() then
        HEAL.release_ik_keep()
        return
    end
    HEAL.ensure_ik_keep()
    HEAL.apply_keep_ik()
end

re.on_application_entry("LateUpdateBehavior", function()
    HEAL.on_late_ik()
end)
re.on_application_entry("PrepareRendering", function()
    HEAL.on_late_ik()
end)
re.on_application_entry("LockScene", function()
    HEAL.on_late_ik()
end)

-- Village (RE8VR.cpp): setActive + removeWeaponWithNoAction + equipObject(owner)
-- must run before requestUseItem, or the heal request is ignored.
HEAL.medicine_owner = function(med)
    if not med then return nil end
    local owner = nil
    pcall(function() owner = med:call("get_owner") end)
    if not owner then
        pcall(function() owner = med:get_field("<owner>k__BackingField") end)
    end
    if not owner then
        pcall(function() owner = med:call("get_GameObject") end)
    end
    return owner
end

HEAL.prep_native_medicine = function(med)
    local steps = {
        active = false,
        remove = false,
        equip = false,
        has_owner = false,
        usable = nil,
    }
    if not med then return steps end
    local owner = HEAL.medicine_owner(med)
    steps.has_owner = owner ~= nil
    pcall(function()
        if re8vr and re8vr.player then
            steps.usable = med:call("isUsable", re8vr.player) == true
        end
    end)
    pcall(function()
        med:call("setActive", true)
        steps.active = true
    end)
    if COMPONENTS.weapon_change then
        pcall(function()
            COMPONENTS.weapon_change:call("removeWeaponWithNoAction")
            steps.remove = true
        end)
    end
    local em = COMPONENTS.equip_manager
    if not em then
        refresh_components(false)
        em = COMPONENTS.equip_manager
    end
    if em and owner then
        pcall(function()
            em:call("equipObject", owner)
            steps.equip = true
        end)
    end
    HEAL._native_med = med
    HEAL._native_owner = owner
    return steps
end

HEAL.deactivate_native_medicine = function()
    local med = HEAL._native_med
    if not med then return end
    pcall(function() med:call("setActive", false) end)
    if COMPONENTS.weapon_change then
        pcall(function() COMPONENTS.weapon_change:call("removeWeaponWithNoAction") end)
    end
    HEAL._native_med = nil
    HEAL._native_owner = nil
end

-- Village rejects requestUseItem at full HP (MedicineCore.isUsable == false).
-- Dip 1 HP so the pour can consume the bottle; heal then restores to full.
HEAL.get_damage_controller = function()
    local dc = nil
    pcall(function()
        local st = re8vr and re8vr.status
        if st then dc = st:call("get_damageController") end
    end)
    if not dc and re8vr and re8vr.player then
        pcall(function()
            local ty = sdk.typeof("app.DamageController")
            if ty then dc = re8vr.player:call("getComponent(System.Type)", ty) end
        end)
    end
    return dc
end

HEAL.allow_use_at_max_health = function()
    local info = { dipped = false, hp = -1, max = -1, maxed = false }
    local dc = HEAL.get_damage_controller()
    if not dc then return info end
    local hp, maxh = nil, nil
    pcall(function() hp = dc:call("get_health") end)
    pcall(function() maxh = dc:call("get_maxHealth") end)
    info.hp = tonumber(hp) or -1
    info.max = tonumber(maxh) or -1
    if info.max <= 0 or info.hp < 0 then return info end
    if info.hp < (info.max - 0.05) then return info end
    info.maxed = true
    local target = math.max(1.0, info.max - 1.0)
    local ok = pcall(function()
        dc:call("setHealth", target, info.max)
    end)
    if ok then
        local after = nil
        pcall(function() after = dc:call("get_health") end)
        if after ~= nil and tonumber(after) < (info.max - 0.05) then
            info.dipped = true
            HEAL._hp_dip_restore = { hp = info.hp, max = info.max }
        end
    end
    if not info.dipped then
        local ok2 = pcall(function()
            dc:call("addManualDamage", re8vr.player, 1.0)
        end)
        if ok2 then
            local after = nil
            pcall(function() after = dc:call("get_health") end)
            if after ~= nil and tonumber(after) < (info.max - 0.05) then
                info.dipped = true
                HEAL._hp_dip_restore = { hp = info.hp, max = info.max }
            end
        end
    end
    return info
end

HEAL.undo_hp_dip = function()
    local r = HEAL._hp_dip_restore
    HEAL._hp_dip_restore = nil
    if not r then return end
    local dc = HEAL.get_damage_controller()
    if not dc then return end
    pcall(function()
        dc:call("setHealth", r.hp, r.max)
    end)
end

HEAL.restore_lua_medicine_hold = function(med, row)
    HEAL.deactivate_native_medicine()
    HEAL.undo_hp_dip()
    rawset(_G, "__re8_medicine_lua_hidden", false)
    rawset(_G, "__re8_medicine_in_hand", true)
    HEAL.in_hand = true
    HEAL.lua_authorized = true
    HEAL.remedy_equipped = true
    if row then
        HEAL.cached_item = row.item_internal or med
        HEAL.cached_weapon = row.weapon
    else
        HEAL.cached_item = med
    end
    HEAL.pour_fired = false
    HEAL.pour_ok_since = nil
    HEAL._lua_use_pending = false
    HEAL._use_anim_until = 0
    HEAL._use_weapon = nil
    HEAL._deactivate_after = nil
end

-- Hide Lua chest/in-hand clone while native use owns the bottle pose.
HEAL.hide_lua_medicine_mesh = function(reason)
    rawset(_G, "__re8_medicine_lua_hidden", true)
    rawset(_G, "__re8_medicine_in_hand", false)
    HEAL.in_hand = false
    -- Hide this frame — waiting for MED.update leaves one-frame hand flash.
    local force = rawget(_G, "__re8_medicine_force_hide")
    if type(force) == "function" then
        pcall(force)
    end
end

HEAL.clear_medicine_slot_if_empty = function()
    -- Force fresh inventory rows; TTL cache can keep a consumed bottle for ~0.25s.
    INV_ROWS_CACHE.t = 0
    INV_ROWS_CACHE.rows = nil
    local has = false
    local med_n = 0
    for _, row in ipairs(inventory_rows()) do
        if is_medicine_core(row.item_internal) or is_medicine_item_id(row.item_id) then
            has = true
            med_n = med_n + 1
        end
    end
    if has then
        return false
    end
    local P = get_profile()
    if P and (P.last_medicine_id or "") ~= "" then
        P.last_medicine_id = ""
        save_cfg()
    end
    medicine.in_zone = false
    medicine.zone_enter_pulse = false
    medicine.haptic_pending_frames = 0
    medicine._med_can_prev = false
    local destroy = rawget(_G, "__re8_medicine_force_destroy")
    if type(destroy) == "function" then
        pcall(destroy)
    end
    return true
end
rawset(_G, "__re8_medicine_clear_empty_slot", HEAL.clear_medicine_slot_if_empty)

function HEAL.tick_use()
    if HEAL._deactivate_after and os.clock() >= HEAL._deactivate_after then
        HEAL._deactivate_after = nil
        if not HEAL.is_native_use_active() then
            HEAL.deactivate_native_medicine()
        end
        rawset(_G, "__re8_medicine_lua_hidden", false)
        HEAL.clear_medicine_slot_if_empty()
    end
    if not CFG.medicine_enabled then
        HEAL.release_ik_keep()
        return
    end
    if not (HEAL.remedy_equipped or is_remedy_equipped()) then
        HEAL.pour_ok_since = nil
        HEAL.pour_fired = false
        if not HEAL.should_keep_ik() then
            HEAL.release_ik_keep()
        end
        if HEAL._native_med and not HEAL.is_native_use_active() then
            HEAL.deactivate_native_medicine()
        end
        return
    end
    HEAL.ensure_ik_keep()
    local inject = HEAL.use_inject_gesture() == true
    local st = inject and HEAL.eval_inject() or HEAL.eval_pour()
    local now = os.clock()
    local hold_s = inject and (tonumber(CFG.medicine_inject_hold_s) or 0.12)
        or (tonumber(CFG.medicine_pour_hold_s) or 0.12)
    if st.ok then
        if not HEAL.pour_ok_since then HEAL.pour_ok_since = now end
    else
        HEAL.pour_ok_since = nil
        HEAL.pour_fired = false
    end
    local held = HEAL.pour_ok_since ~= nil and (now - HEAL.pour_ok_since) >= hold_s
    local will_use = held and HEAL.pour_fired ~= true
    if st.near_ok == true then
        HEAL._ik_until = now + 0.35
    end
    HEAL.apply_keep_ik()
    if not will_use then return end
    local row = HEAL.cached_item and {
        item_internal = HEAL.cached_item,
        weapon = HEAL.cached_weapon,
    } or find_remedy_row()
    if not row or not row.item_internal then
        return
    end
    if not COMPONENTS.weapon_change then
        refresh_components(false)
    end
    if not COMPONENTS.weapon_change then
        return
    end
    local med = row.item_internal
    -- Hide Lua clone immediately — native equip owns hand pose during use.
    HEAL.hide_lua_medicine_mesh("pour_fire")
    -- H_MAX: isUsable is false at full HP — dip 1 so requestUseItem can run.
    local hp_info = HEAL.allow_use_at_max_health()
    local prep = HEAL.prep_native_medicine(med)
    HEAL.pour_fired = true
    HEAL._lua_use_pending = true
    HEAL._ik_until = os.clock() + 2.50
    HEAL._use_weapon = row.weapon or med
    HEAL._use_anim_until = os.clock() + 2.50
    local use_ok = false
    local use_via = "none"
    pcall(function()
        use_ok = COMPONENTS.weapon_change:call("requestUseItem", med, false, false) == true
        if use_ok then use_via = "requestUseItem" end
    end)
    if not use_ok then
        pcall(function()
            use_ok = COMPONENTS.weapon_change:call("tryUseItem") == true
            if use_ok then use_via = "tryUseItem" end
        end)
    end
    if not use_ok and re8vr and re8vr.player then
        pcall(function()
            use_ok = med:call("use", re8vr.player) == true
            if use_ok then use_via = "MedicineCore.use" end
        end)
    end
    if not use_ok then
        -- Failed use: undo native equip + HP dip so Lua bottle stays in hand.
        HEAL.restore_lua_medicine_hold(med, row)
        return
    end
    HEAL.pour_rumble_start()   -- Visceral RE8 2026-10-31: the low pouring rumble
    HEAL._hp_dip_restore = nil
    HEAL.lua_authorized = false
    HEAL.remedy_equipped = false
    HEAL.cached_item = nil
    HEAL.cached_weapon = nil
    HEAL.pour_ok_since = nil
    HEAL.use_check_t = os.clock() + 0.20
    -- Deactivate native medicine after the use window (matches RE8VR grip-release).
    HEAL._deactivate_after = os.clock() + 2.60
end

-- Firearm in RH overlapping the chest mesh must not look like a holster
-- zone: two-hand recoil, left-hand latch, and pump all read these flags.
HEAL.publish_zone_flag = function()
    local pub = medicine.in_zone == true
    if pub and rawget(_G, "__re8_medicine_in_hand") ~= true and not is_bare_hands() then
        pub = false
    end
    rawset(_G, "__vr_in_medicine_zone", pub)
end

pcall(function()
    local td = sdk.find_type_definition("app.PlayerWeaponChange")
    if not td then return end
    local m = td:get_method("requestUseItem(app.ItemCore, System.Boolean, System.Boolean)")
    if not m then m = td:get_method("requestUseItem") end
    if not m then return end
    sdk.hook(m,
        function(args)
            HEAL._lua_use_pending = false
        end,
        function(retval)
            return retval
        end)
end)

-- Head-zone flashlight via PlayerHandLight.IsContinuousOn (REF ManualFlashlight field).
-- Methods hang on FLASH to stay under Lua's 200-local limit.
local FLASH = {
    power = false,
    hand_light = nil,
    hand_light_typeof = nil,
    in_zone = false,
    last_dist = -1,
    last_grab_t = -1.0,
    grab_ready_prev = false,
    zone_enter_pulse = false,
    haptic_pending_frames = 0,
    calib_deadline = 0,
    calib_last_beep = -1,
    status = "",
}

FLASH.clear = function()
    FLASH.in_zone = false
    FLASH.last_dist = -1
    FLASH.grab_ready_prev = false
    FLASH.zone_enter_pulse = false
    FLASH.haptic_pending_frames = 0
    FLASH.calib_deadline = 0
    FLASH.calib_last_beep = -1
    FLASH.hand_light = nil
    FLASH.light = nil
    FLASH.ctrl = nil
    FLASH.beam_tf = nil
    FLASH.shaft_tf = nil
    FLASH.ies = nil
    FLASH.last_req = nil
    FLASH.power = false
    rawset(_G, "__vr_flashlight_power", nil)
    rawset(_G, "__vr_in_head_flashlight_zone", false)
end

FLASH.publish = function()
    rawset(_G, "__vr_flashlight_power", FLASH.power == true)
    rawset(_G, "__vr_in_head_flashlight_zone", FLASH.in_zone == true)
end

FLASH.get_left_joystick = function()
    if vrc_manager and vrc_manager.has_controllers and vrc_manager:has_controllers() then
        local lc = vrc_manager.controllers_list and vrc_manager.controllers_list[1]
        if lc and lc.joystick then return lc.joystick end
    end
    local lj = nil
    pcall(function() lj = vrmod:get_left_joystick() end)
    return lj
end

FLASH.get_left_grip = function()
    local result = false
    local left_act = false
    local right_act = false
    local left_act_ok = false
    local lj = FLASH.get_left_joystick()
    if lj and vrmod then
        local action = nil
        pcall(function() action = vrmod:get_action_grip() end)
        if action then
            local ok, v = pcall(function() return vrmod:is_action_active(action, lj) end)
            left_act_ok = ok == true
            if ok and v == true then
                left_act = true
                result = true
            end
            local rj = nil
            pcall(function() rj = vrmod:get_right_joystick() end)
            if rj then
                local rok, rv = pcall(function() return vrmod:is_action_active(action, rj) end)
                if rok and rv == true then right_act = true end
            end
        end
        local axis = nil
        pcall(function()
            if vrmod.get_action_grip_axis then
                axis = vrmod:get_action_grip_axis(lj)
            elseif vrmod.get_grip_axis then
                axis = vrmod:get_grip_axis(lj)
            end
        end)
        if type(axis) == "number" then
            -- Axis can mirror the other hand. Never promote left from axis
            -- when the right grip action is the one that is actually down.
            if (not left_act_ok or left_act) and (not right_act) and axis >= 0.65 then
                result = true
            end
        end
    end
    if vrc_manager and vrc_manager.has_controllers and vrc_manager:has_controllers() then
        local lc = vrc_manager.controllers_list and vrc_manager.controllers_list[1]
        if lc and vrc_manager.Actions and vrc_manager.Actions.GRIP then
            local ok, v = pcall(function() return lc:is_action_active(vrc_manager.Actions.GRIP) end)
            if ok and v == true then result = true end
        end
    end
    if right_act and not left_act then
        return false
    end
    return result
end

FLASH.lh_ctrl_idx = function()
    local controllers = nil
    pcall(function() controllers = vrmod:get_controllers() end)
    local idx = controllers and controllers[1]
    if idx == nil then idx = 1 end
    return idx
end

-- Left controller in the SAME space as the HMD zone (get_hmd_pose_vr uses
-- vrmod:get_transform(0)); mirror get_right_hand_pos so distances are sane.
FLASH.get_left_hand_world = function()
    local lh_m = nil
    pcall(function() lh_m = vrmod:get_transform(FLASH.lh_ctrl_idx()) end)
    if lh_m then
        local pos = matrix_col(lh_m, 3)
        if pos and type(pos.x) == "number" then return pos end
    end
    if re8vr and re8vr.last_left_hand_position
        and type(re8vr.last_left_hand_position.x) == "number" then
        return re8vr.last_left_hand_position
    end
    local w = rawget(_G, "__vr_lh_world")
    if w and type(w.x) == "number" then return w end
    return nil
end

HJ.get_left_trigger = function()
    local lj = FLASH.get_left_joystick()
    if lj and vrmod then
        local action = nil
        pcall(function() action = vrmod:get_action_trigger() end)
        if action then
            local ok, v = pcall(function() return vrmod:is_action_active(action, lj) end)
            if ok and v == true then return true end
        end
        local axis = nil
        pcall(function()
            if vrmod.get_action_trigger_axis then
                axis = vrmod:get_action_trigger_axis(lj)
            elseif vrmod.get_trigger_axis then
                axis = vrmod:get_trigger_axis(lj)
            end
        end)
        if type(axis) == "number" and axis >= 0.65 then return true end
    end
    return false
end

HJ.tick_ammo_left_zone = function(P)
    local zone = HJ.ammo_left
    if CFG.ammo_left_enabled ~= true then
        zone.in_zone = false
        rawset(_G, "__vr_in_ammo_holster_zone", false)
        return
    end
    -- Runtime (e06971 fps): trigger=0.24 + dist~0.37 + off_r=+0.34 never entered zone.
    -- Positive right offset parks ammo on the wrong side of the body; restore left-hip defaults.
    if HJ._ammo_calib_fixed ~= true and type(P) == "table" then
        HJ._ammo_calib_fixed = true
        local trig = tonumber(P.ammo_left_trigger_dist) or 0
        local off_r = tonumber(P.ammo_left_off_right) or 0
        local changed = false
        if trig > 0 and trig < 0.18 then
            P.ammo_left_trigger_dist = 0.24
            P.ammo_left_release_dist = 0.34
            changed = true
        end
        -- Only reset wildly corrupt offsets (>2m), not legitimate user calibrations.
        local mag = math.sqrt(off_r * off_r
            + (tonumber(P.ammo_left_off_up) or 0) ^ 2
            + (tonumber(P.ammo_left_off_forward) or 0) ^ 2)
        if mag > 2.0 then
            P.ammo_left_off_right = -0.12
            P.ammo_left_off_up = 0.0
            P.ammo_left_off_forward = 0.02
            changed = true
        end
        if changed then
            pcall(save_cfg)
        end
    end
    local hover = STOW.hover_m()
    local lj = FLASH.get_left_joystick()
    local lh = HJ.get_left_hand_world()
    refresh_hmd_holster_zone(zone, "ammo_left", P,
        P.ammo_left_trigger_dist or hover,
        P.ammo_left_release_dist or (hover + 0.10),
        lh, lj)
    rawset(_G, "__vr_in_ammo_holster_zone", zone.in_zone == true)
end

FLASH.zone_pos = function(P)
    local hmd, right, up, fwd = get_hmd_pose_vr()
    if not hmd then return nil end
    local ox = (P and P.head_flash_off_x) or -0.14
    local oy = (P and P.head_flash_off_y) or 0.12
    local oz = (P and P.head_flash_off_z) or 0.06
    local len = math.sqrt(ox * ox + oy * oy + oz * oz)
    if len < 0.04 then
        ox, oy, oz = -0.14, 0.12, 0.06
    end
    return holster_pos_with_offsets(hmd, ox, oy, oz, nil, nil, nil, right, up, fwd),
        hmd, right, up, fwd
end

FLASH.get_player = function()
    if re8vr and re8vr.player and managed_object_alive(re8vr.player) then
        return re8vr.player
    end
    local props = sdk.get_managed_singleton("app.PropsManager")
    if props == nil then return nil end
    local player = nil
    pcall(function() player = props:call("get_Player") end)
    if not player then
        pcall(function() player = props:get_field("Player") end)
    end
    return player
end

FLASH.get_hand_light = function()
    refresh_components(false)
    local live = COMPONENTS.hand_light
    if live and managed_object_alive(live) then
        if FLASH.hand_light ~= live then
            FLASH.hand_light = live
            FLASH.light = nil
            FLASH.ctrl = nil
            FLASH.beam_tf = nil
            FLASH.shaft_tf = nil
            FLASH.ies = nil
            FLASH.last_req = nil
        end
        return live
    end
    if FLASH.hand_light and managed_object_alive(FLASH.hand_light) then
        return FLASH.hand_light
    end
    FLASH.hand_light = nil
    FLASH.light = nil
    FLASH.ctrl = nil
    if FLASH.hand_light_typeof == nil then
        pcall(function() FLASH.hand_light_typeof = sdk.typeof("app.PlayerHandLight") end)
    end
    if FLASH.hand_light_typeof == nil then return nil end
    local player = FLASH.get_player()
    if player == nil then return nil end
    local hl = nil
    pcall(function()
        hl = player:call("getComponent(System.Type)", FLASH.hand_light_typeof)
    end)
    if hl then
        FLASH.hand_light = hl
        FLASH.last_req = nil
    end
    return hl
end

FLASH.get_light = function(hl)
    if FLASH.light and managed_object_alive(FLASH.light) then
        return FLASH.light, FLASH.ctrl
    end
    FLASH.light = nil
    FLASH.ctrl = nil
    FLASH.get_beam_tfs()
    if FLASH.ctrl and managed_object_alive(FLASH.ctrl) then
        local light = FLASH.ies
        FLASH.light = light
        return light, FLASH.ctrl
    end
    if hl == nil then return nil, nil end
    local ctrl = nil
    pcall(function() ctrl = hl:get_field("HandLightPowerController") end)
    if ctrl == nil then return nil, nil end
    local light = nil
    pcall(function() light = ctrl:call("get_Light") end)
    if light == nil then pcall(function() light = ctrl:get_field("HandLight") end) end
    FLASH.ctrl = ctrl
    FLASH.light = light
    return light, ctrl
end

FLASH.find_scene_go = function(name)
    local go = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local td = sdk.find_type_definition("via.SceneManager")
        if sm == nil or td == nil then return end
        local scene = sdk.call_native_func(sm, td, "get_CurrentScene()")
        if scene == nil then return end
        go = scene:call("findGameObject(System.String)", name)
    end)
    return go
end

FLASH.get_beam_tfs = function()
    if FLASH.beam_tf and managed_object_alive(FLASH.beam_tf) then
        return FLASH.beam_tf, FLASH.shaft_tf
    end
    FLASH.beam_tf = nil
    FLASH.shaft_tf = nil
    FLASH.ies = nil
    local go = FLASH.find_scene_go("HandLight")
    if go then
        pcall(function() FLASH.beam_tf = go:call("get_Transform") end)
        pcall(function()
            local t = sdk.typeof("app.HandLightPowerController")
            if t then FLASH.ctrl = go:call("getComponent(System.Type)", t) end
        end)
        pcall(function()
            local t = sdk.typeof("via.render.IESLight")
            if t then FLASH.ies = go:call("getComponent(System.Type)", t) end
        end)
        FLASH.light = FLASH.ies
    end
    local shaft = FLASH.find_scene_go("HandLightShaftLight")
    if shaft then
        pcall(function() FLASH.shaft_tf = shaft:call("get_Transform") end)
    end
    return FLASH.beam_tf, FLASH.shaft_tf
end

FLASH.quat_euler = function(pitch, yaw, roll)
    local hr = 0.008726646259971648
    local p = (tonumber(pitch) or 0) * hr
    local y = (tonumber(yaw) or 0) * hr
    local r = (tonumber(roll) or 0) * hr
    local sp, cp = math.sin(p), math.cos(p)
    local sy, cy = math.sin(y), math.cos(y)
    local sr, cr = math.sin(r), math.cos(r)
    return Quaternion.new(
        sp * cy * cr - cp * sy * sr,
        cp * sy * cr + sp * cy * sr,
        cp * cy * sr - sp * sy * cr,
        cp * cy * cr + sp * sy * sr)
end

FLASH.align_to_hmd = function()
    if FLASH.power ~= true then return end
    if not vrmod or not vrmod:is_hmd_active() then return end
    local tf, shaft = FLASH.get_beam_tfs()
    if not tf then return end
    local pos, rot = nil, nil
    pcall(function()
        local m = vrmod:get_last_render_matrix()
        if m and m[3] then
            pos = Vector3f.new(m[3].x, m[3].y, m[3].z)
            rot = m:to_quat()
        end
    end)
    if not pos then
        pcall(function()
            local m = vrmod:get_transform(0)
            if m and m[3] then
                pos = Vector3f.new(m[3].x, m[3].y, m[3].z)
                rot = m:to_quat()
            end
        end)
    end
    if not pos or not rot then return end
    local P = get_profile()
    local ox = tonumber(P.head_flash_beam_right) or 0
    local oy = tonumber(P.head_flash_beam_up) or 0
    local oz = tonumber(P.head_flash_beam_forward) or 0
    local yaw = tonumber(P.head_flash_beam_yaw) or 0
    local pitch = tonumber(P.head_flash_beam_pitch) or 0
    local roll = tonumber(P.head_flash_beam_roll) or 0
    local right = rot * Vector3f.new(1, 0, 0)
    local upv = rot * Vector3f.new(0, 1, 0)
    local look = rot * Vector3f.new(0, 0, -1)
    pos = Vector3f.new(
        pos.x + right.x * ox + upv.x * oy + look.x * oz,
        pos.y + right.y * ox + upv.y * oy + look.y * oz,
        pos.z + right.z * ox + upv.z * oy + look.z * oz)
    if yaw ~= 0 or pitch ~= 0 or roll ~= 0 then
        local extra = FLASH.quat_euler(pitch, yaw, roll)
        pcall(function() rot = (rot * extra):normalized() end)
    end
    pcall(function() tf:call("set_Position", pos) end)
    pcall(function() tf:call("set_Rotation", rot) end)
    if shaft and managed_object_alive(shaft) then
        pcall(function() shaft:call("set_Position", pos) end)
        pcall(function() shaft:call("set_Rotation", rot) end)
    end
end

re.on_application_entry("LockScene", function()
    if FLASH and FLASH.align_to_hmd then
        FLASH.align_to_hmd()
    end
end)

FLASH.install_power_hooks = function()
    if FLASH.hooks_installed then return end
    FLASH.hooks_installed = true
    local function reapply_on_lifecycle(evt)
        FLASH.last_req = nil
        FLASH.hand_light = nil
        FLASH.light = nil
        FLASH.ctrl = nil
        FLASH.beam_tf = nil
        FLASH.shaft_tf = nil
        FLASH.ies = nil
        COMPONENTS.hand_light = nil
    end
    local td = sdk.find_type_definition("app.PlayerHandLight")
    if not td then return end
    for _, nm in ipairs({ "awake", "start", "onLoad", "reset" }) do
        pcall(function()
            local m = td:get_method(nm)
            if m then
                sdk.hook(m, function(_args) end, function(retval)
                    reapply_on_lifecycle(nm)
                    return retval
                end)
            end
        end)
    end
end

FLASH.apply_power = function()
    local hl = FLASH.get_hand_light()
    if hl == nil then
        FLASH.status = "no_hand_light"
        return false
    end
    local want = FLASH.power == true
    pcall(function() hl:set_field("IsContinuousOn", want) end)
    pcall(function() hl:set_field("IsLightOn", want) end)
    if want then
        pcall(function() hl:set_field("EnterHandLightPowerOnZoneCount", 1) end)
    else
        pcall(function() hl:set_field("EnterHandLightPowerOnZoneCount", 0) end)
    end
    FLASH.get_beam_tfs()
    local native_on = nil
    pcall(function() native_on = hl:call("get_isHandLightOn") == true end)
    if native_on == nil then
        pcall(function() native_on = hl:get_field("IsLightOn") == true end)
    end
    local edge = FLASH.last_req ~= want
    if FLASH.ctrl and managed_object_alive(FLASH.ctrl) then
        pcall(function() FLASH.ctrl:call("set_power", want) end)
        pcall(function() FLASH.ctrl:set_field("Power", want) end)
        if edge then
            pcall(function() FLASH.ctrl:set_field("requestPowerOn", want) end)
            pcall(function() FLASH.ctrl:set_field("requestPowerOff", not want) end)
            pcall(function() FLASH.ctrl:call("updatePower") end)
        end
    end
    if edge then
        pcall(function() hl:call("controlHandLightPower") end)
    end
    FLASH.last_req = want
    FLASH.status = want and "on" or "off"
    FLASH.publish()
    return true
end

FLASH.start_calib = function()
    FLASH.calib_deadline = os.clock() + 5.0
    FLASH.calib_last_beep = -1
    local lj = FLASH.get_left_joystick()
    if lj then
        holster_haptic_pulse(lj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
    end
end

FLASH.tick_calib = function(P)
    if not FLASH.calib_deadline or FLASH.calib_deadline <= 0 then return end
    local now = os.clock()
    local remaining = FLASH.calib_deadline - now
    local lj = FLASH.get_left_joystick()
    if remaining > 0 then
        local int_s = math.ceil(remaining)
        if int_s ~= FLASH.calib_last_beep then
            FLASH.calib_last_beep = int_s
            if lj then haptic_pulse(lj, 0.06, 160.0, 0.6) end
        end
        return
    end
    FLASH.calib_deadline = 0
    FLASH.calib_last_beep = -1
    local hand = FLASH.get_left_hand_world()
    local zone, hmd, right, up, fwd = FLASH.zone_pos(P)
    if not hand or not hmd or not right then
        FLASH.status = "calib_fail_pose"
        if lj then haptic_pulse(lj, 0.35, 90.0, 1.0) end
        return
    end
    local off_x, off_y, off_z = HOLSTER_CALIB.decompose(hand, hmd, right, up, fwd)
    local len = math.sqrt(off_x * off_x + off_y * off_y + off_z * off_z)
    if len < 0.04 then
        FLASH.status = "calib_too_close"
        if lj then haptic_pulse(lj, 0.35, 90.0, 1.0) end
        return
    end
    P.head_flash_off_x = off_x
    P.head_flash_off_y = off_y
    P.head_flash_off_z = off_z
    save_cfg()
    FLASH.status = "calib_saved"
    if lj then haptic_pulse(lj, 0.25, 250.0, 1.0) end
end

FLASH.zone_haptic = function(lj)
    if not lj then return end
    if CFG.zone_haptic_enabled == false then return end
    if CFG.head_flash_zone_haptic_enabled == false then return end
    if FLASH.zone_enter_pulse then
        FLASH.zone_enter_pulse = false
        holster_haptic_pulse(lj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
        return
    end
    if CFG.head_flash_zone_haptic_continuous ~= true then return end
    local every = tonumber(CFG.zone_haptic_frames) or 3
    FLASH.haptic_pending_frames = (FLASH.haptic_pending_frames or 0) + 1
    if FLASH.haptic_pending_frames >= every then
        FLASH.haptic_pending_frames = 0
        holster_haptic_pulse(lj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
    end
end

FLASH.tick = function()
    FLASH.install_power_hooks()
    if CFG.head_flashlight_enabled == false then
        FLASH.in_zone = false
        FLASH.grab_ready_prev = false
        rawset(_G, "__vr_in_head_flashlight_zone", false)
        rawset(_G, "__vr_flashlight_power", nil)
        return
    end
    if is_menu_blocking and is_menu_blocking() then
        FLASH.in_zone = false
        FLASH.grab_ready_prev = false
        FLASH.apply_power()
        return
    end

    local P = get_profile()
    FLASH.tick_calib(P)

    local hand = FLASH.get_left_hand_world()
    local zone = FLASH.zone_pos(P)
    local lj = FLASH.get_left_joystick()
    if not hand or not zone then
        FLASH.in_zone = false
        FLASH.grab_ready_prev = false
        FLASH.apply_power()
        return
    end

    local d = vec3_dist(hand, zone)
    FLASH.last_dist = d
    local was_in = FLASH.in_zone == true
    local trig = tonumber(P.head_flash_trigger_dist) or 0.22
    local rel = tonumber(P.head_flash_release_dist) or 0.34
    if not FLASH.in_zone then
        if d <= trig then FLASH.in_zone = true end
    else
        if d > rel then FLASH.in_zone = false end
    end
    if FLASH.in_zone and not was_in then
        FLASH.zone_enter_pulse = true
        FLASH.haptic_pending_frames = 0
    end
    if FLASH.in_zone then
        FLASH.zone_haptic(lj)
    end

    local grip_now = FLASH.get_left_grip()
    local ready = FLASH.in_zone and grip_now
    local grab_edge = ready and not FLASH.grab_ready_prev
    FLASH.grab_ready_prev = ready
    if grab_edge then
        local now = os.clock()
        local cd = tonumber(P.head_flash_cooldown) or 0.5
        if now - (FLASH.last_grab_t or -1) >= cd then
            FLASH.last_grab_t = now
            FLASH.power = not FLASH.power
            FLASH.apply_power()
            if lj then
                holster_haptic_pulse(lj, CFG.grab_haptic_duration, CFG.grab_haptic_frequency, CFG.grab_haptic_amplitude)
            end
        end
    else
        -- Reassert authoritative power every frame while feature is on.
        FLASH.apply_power()
    end
    FLASH.publish()
end

-- Right index tip (R_IndexF3) touch left hand/wrist (L_Hand) while holding
-- right controller grip → open inventory. Grip gate avoids accidental opens.
-- Methods hang on INV to stay under Lua's 200-local limit.
local INV = {
    in_zone = false,
    open_ready_prev = false,
    last_dist = -1,
    last_open_t = -1.0,
    zone_enter_pulse = false,
    haptic_pending_frames = 0,
    status = "",
    src = "",
    index_joint = nil,
    wrist_joint = nil,
    index_name = "",
    wrist_name = "",
    joint_t = 0,
    INDEX_NAMES = { "R_IndexF3", "R_IndexF2", "R_IndexF1" },
    WRIST_NAMES = { "L_Hand", "L_Palm", "L_Forearm" },
    watch_until = 0,
    watch_last = 0,
    watch_open_t = 0,
    block_log_t = 0,
    last_cand = "RUp",
    inject_button = nil,
    inject_frames = 0,
    inject_edge = false,
}

-- Inventory input injection: OR RUp (Xbox Y) onto the merged pad device before
-- app.Pad:update consumes it. ButtonDown is set on the first injected frame only
-- to mimic a single press; Button remains held for the short input window.
INV.pad_device = function()
    local dev = nil
    pcall(function()
        local padman = sdk.get_managed_singleton("app.PadManager")
        if not padman then return end
        local mp = padman:call("get_activePad")
        if not mp then mp = padman:call("get_mergedPad") end
        if mp then dev = mp:get_field("Device") end
    end)
    return dev
end

INV.inject_pad = function()
    if (INV.inject_frames or 0) <= 0 or not INV.inject_button then return end
    if not vrmod or not vrmod:is_hmd_active() then return end
    local dev = INV.pad_device()
    if not dev then return end
    pcall(function()
        local cur = dev:call("get_Button") or 0
        dev:call("set_Button", cur | INV.inject_button)
        if INV.inject_edge then
            local curd = dev:call("get_ButtonDown") or 0
            dev:call("set_ButtonDown", curd | INV.inject_button)
            INV.inject_edge = false
        end
    end)
    INV.inject_frames = INV.inject_frames - 1
    rawset(_G, "__vr_inv_inject_frames", INV.inject_frames or 0)
end

pcall(function()
    sdk.hook(
        sdk.find_type_definition("app.Pad"):get_method("update"),
        function(args)
            pcall(INV.inject_pad)
        end,
        function(retval)
            return retval
        end
    )
end)

-- Post-open watch: after the gesture opens inventory, sample the native open state
-- (and right-hand inputs) every frame for a short window so we can see WHEN and WHY
-- it closes. Runs before INV.tick's early returns because opening inventory makes
-- is_menu_blocking() true (menu_gui_time), which would otherwise stop sampling.
INV.watch_tick = function()
    if not INV.watch_until or os.clock() >= INV.watch_until then return end
    local now = os.clock()
    if (now - (INV.watch_last or 0)) < 0.05 then return end
    INV.watch_last = now
    local mm = nil
    pcall(function() mm = sdk.get_managed_singleton("app.MenuManager") end)
    local is_open, is_can, is_pause, is_down = nil, nil, nil, nil
    if mm then
        pcall(function() is_open = mm:call("isOpenInventoryMenu") == true end)
        pcall(function() is_can = mm:call("isCanOpenInventoryScreen") == true end)
        pcall(function() is_pause = mm:call("isOpenPauseMenu") == true end)
        pcall(function() is_down = mm:call("isDownArm2inventory") == true end)
    end
    local grip, trig = false, false
    pcall(function() grip = get_right_grip_pressed() == true end)
    pcall(function() trig = get_right_trigger_pressed() == true end)
end

INV.clear = function()
    INV.in_zone = false
    INV.open_ready_prev = false
    INV.last_dist = -1
    INV.zone_enter_pulse = false
    INV.haptic_pending_frames = 0
    INV.index_joint = nil
    INV.wrist_joint = nil
    INV.index_name = ""
    INV.wrist_name = ""
    INV.src = ""
    INV.status = ""
    INV.inject_button = nil
    INV.inject_frames = 0
    INV.inject_edge = false
    rawset(_G, "__vr_inventory_gesture_inject", 0)
    rawset(_G, "__vr_in_inventory_gesture_zone", false)
end

INV.get_left_hand_fallback = function()
    local pos = nil
    if re8vr and re8vr.left_hand_ik_transform then
        pcall(function() pos = re8vr.left_hand_ik_transform:call("get_Position") end)
        if pos and type(pos.x) == "number" then return pos end
    end
    if re8vr and re8vr.last_left_hand_position
        and type(re8vr.last_left_hand_position.x) == "number" then
        return re8vr.last_left_hand_position
    end
    local w = rawget(_G, "__vr_lh_world")
    if w and type(w.x) == "number" then return w end
    return nil
end

INV.refresh_joints = function()
    local now = os.clock()
    if INV.joint_t and (now - INV.joint_t) < 1.0
        and INV.index_joint and managed_object_alive(INV.index_joint)
        and INV.wrist_joint and managed_object_alive(INV.wrist_joint) then
        return true
    end
    INV.joint_t = now
    local ij, iname = HJ.find_joint(INV.INDEX_NAMES)
    local wj, wname = HJ.find_joint(INV.WRIST_NAMES)
    INV.index_joint = ij
    INV.wrist_joint = wj
    INV.index_name = iname or ""
    INV.wrist_name = wname or ""
    return ij ~= nil and wj ~= nil
end

INV.get_points = function()
    if INV.refresh_joints() then
        local ip, wp = nil, nil
        pcall(function() ip = INV.index_joint:call("get_Position") end)
        pcall(function() wp = INV.wrist_joint:call("get_Position") end)
        if ip and wp and type(ip.x) == "number" and type(wp.x) == "number" then
            INV.src = "joints:" .. INV.index_name .. "/" .. INV.wrist_name
            return ip, wp
        end
    end
    local rh = select(1, HJ.get_right_hand_world())
    local lh = INV.get_left_hand_fallback()
    if rh and lh and type(rh.x) == "number" and type(lh.x) == "number" then
        INV.src = "ik_fallback"
        return rh, lh
    end
    INV.src = "none"
    return nil, nil
end

-- Palm/front axis of the left wrist. Prefer L_Hand AxisY (palm normal);
-- sign is CFG-tunable if a character skeleton flips it.
INV.wrist_front_axis = function()
    local ax, ay, az = nil, nil, nil
    if INV.wrist_joint and managed_object_alive(INV.wrist_joint) then
        pcall(function()
            ax = INV.wrist_joint:call("get_AxisX")
            ay = INV.wrist_joint:call("get_AxisY")
            az = INV.wrist_joint:call("get_AxisZ")
        end)
    end
    local sign = tonumber(CFG.inventory_wrist_front_sign) or 1.0
    if sign >= 0 then sign = 1.0 else sign = -1.0 end
    if ay and type(ay.x) == "number" then
        local n = vec3_normalize({ x = ay.x * sign, y = ay.y * sign, z = ay.z * sign })
        if n then return n, ax, ay, az end
    end
    return { x = 0, y = sign, z = 0 }, ax, ay, az
end

-- Touch target sits on the front/palm side of the wrist, not the joint center.
INV.wrist_touch_target = function(wrist_pos)
    if not wrist_pos then return nil, nil end
    local front = INV.wrist_front_axis()
    local off = tonumber(CFG.inventory_wrist_front_m) or 0.04
    if off < 0 then off = 0 end
    if off > 0.12 then off = 0.12 end
    return {
        x = wrist_pos.x + front.x * off,
        y = wrist_pos.y + front.y * off,
        z = wrist_pos.z + front.z * off,
    }, front
end

INV.try_open = function()
    local mm = nil
    pcall(function() mm = sdk.get_managed_singleton("app.MenuManager") end)
    if mm == nil then
        INV.status = "no_menu"
        return false
    end
    local was_open = false
    pcall(function() was_open = mm:call("isOpenInventoryMenu") == true end)
    -- A direct openInventoryMenu() opens the UI but the game's doUpdate drops it
    -- one frame later because its input poll (isDownArm2inventory) isn't satisfied.
    -- The game only sustains the inventory when the real inventory button is pressed.
    -- Runtime scan confirmed RUp (Xbox Y) opens and sustains inventory.
    -- Toggle test: inject RUp whether open or closed to see if it also closes.
    local btn = nil
    pcall(function() btn = via.hid.GamePadButton.RUp end)
    if btn == nil then
        INV.status = "no_inventory_button"
        return false
    end
    INV.inject_button = btn
    INV.inject_frames = 12
    INV.inject_edge = true
    -- VR pad maps right grip → LT aim; clear that and OR RUp in update_pad_device
    -- or isCanOpenInventoryScreen stays false while grip is held.
    rawset(_G, "__vr_inventory_gesture_inject", 12)
    rawset(_G, "__vr_inv_inject_frames", INV.inject_frames)
    INV.status = was_open and "close_requested" or "open_requested"
    local can_now = nil
    pcall(function() can_now = mm:call("isCanOpenInventoryScreen") == true end)
    INV.watch_open_t = os.clock()
    INV.watch_until = INV.watch_open_t + 1.6
    INV.watch_last = 0
    return true
end

INV.zone_haptic = function(rj)
    if not rj then return end
    if CFG.zone_haptic_enabled == false then return end
    if CFG.inventory_zone_haptic_enabled == false then return end
    if INV.zone_enter_pulse then
        INV.zone_enter_pulse = false
        holster_haptic_pulse(rj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
        return
    end
    if CFG.inventory_zone_haptic_continuous ~= true then return end
    local every = tonumber(CFG.zone_haptic_frames) or 3
    INV.haptic_pending_frames = (INV.haptic_pending_frames or 0) + 1
    if INV.haptic_pending_frames >= every then
        INV.haptic_pending_frames = 0
        holster_haptic_pulse(rj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
    end
end

INV.tick = function()
    INV.watch_tick()
    if CFG.inventory_gesture_enabled == false then
        INV.in_zone = false
        INV.open_ready_prev = false
        rawset(_G, "__vr_in_inventory_gesture_zone", false)
        return
    end
    if slide_dock_blocks_inventory_gesture() then
        INV.in_zone = false
        INV.open_ready_prev = false
        INV.status = "slide_dock"
        rawset(_G, "__vr_in_inventory_gesture_zone", false)
        return
    end
    if is_menu_blocking and is_menu_blocking() then
        -- Inventory open counts as menu-blocking; still allow the same grip+wrist
        -- gesture to toggle it closed (do not clear open_ready_prev or we re-fire).
        local inv_open = false
        pcall(function()
            local mm = sdk.get_managed_singleton("app.MenuManager")
            if mm then inv_open = mm:call("isOpenInventoryMenu") == true end
        end)
        if not inv_open then
            local now = os.clock()
            if now - (INV.block_log_t or 0) >= 0.1 then
                INV.block_log_t = now
                local mm, is_open = nil, false
                pcall(function() mm = sdk.get_managed_singleton("app.MenuManager") end)
                if mm then
                    pcall(function() is_open = mm:call("isOpenInventoryMenu") == true end)
                end
                local ip, wp = INV.get_points()
                local blocked_dist = -1
                if ip and wp then blocked_dist = vec3_dist(ip, wp) end
            end
            INV.in_zone = false
            INV.open_ready_prev = false
            rawset(_G, "__vr_in_inventory_gesture_zone", false)
            return
        end
    end
    if is_cinematic_blocking and is_cinematic_blocking() then
        INV.in_zone = false
        INV.open_ready_prev = false
        rawset(_G, "__vr_in_inventory_gesture_zone", false)
        return
    end
    if re8vr and re8vr.can_use_hands == false then
        local inv_open = false
        pcall(function()
            local mm = sdk.get_managed_singleton("app.MenuManager")
            if mm then inv_open = mm:call("isOpenInventoryMenu") == true end
        end)
        if not inv_open then
            INV.in_zone = false
            INV.open_ready_prev = false
            rawset(_G, "__vr_in_inventory_gesture_zone", false)
            return
        end
    end

    local P = get_profile()
    local index_pos, wrist_pos = INV.get_points()
    if not index_pos or not wrist_pos then
        INV.in_zone = false
        INV.open_ready_prev = false
        INV.status = "no_points"
        rawset(_G, "__vr_in_inventory_gesture_zone", false)
        return
    end

    local touch_pos, front_axis = INV.wrist_touch_target(wrist_pos)
    if not touch_pos then touch_pos = wrist_pos end
    local to_x = index_pos.x - wrist_pos.x
    local to_y = index_pos.y - wrist_pos.y
    local to_z = index_pos.z - wrist_pos.z
    local palm_dot = 0
    if front_axis then
        palm_dot = to_x * front_axis.x + to_y * front_axis.y + to_z * front_axis.z
    end
    local front_only = CFG.inventory_wrist_front_only ~= false
    local on_front = (not front_only) or (palm_dot >= -0.005)

    local d = vec3_dist(index_pos, touch_pos)
    INV.last_dist = d
    INV.last_palm_dot = palm_dot
    local was_in = INV.in_zone == true
    local trig = tonumber(P.inventory_trigger_dist) or 0.10
    local rel = tonumber(P.inventory_release_dist) or 0.16
    if not INV.in_zone then
        if on_front and d <= trig then INV.in_zone = true end
    else
        if d > rel or (front_only and palm_dot < -0.02) then
            INV.in_zone = false
        end
    end
    if INV.in_zone and not was_in then
        INV.haptic_pending_frames = 0
    end
    if (os.clock() - (INV._zm_log_t or 0)) > 0.12 then
        INV._zm_log_t = os.clock()
        local edge = ""
        if INV.in_zone and not was_in then edge = "enter"
        elseif (not INV.in_zone) and was_in then edge = "exit" end
        if edge ~= "" or d < (trig + 0.08) then
        end
    end

    local rj = get_right_joystick()
    -- No zone haptic on bare wrist contact — pulse only when inventory actually opens below.
    rawset(_G, "__vr_in_inventory_gesture_zone", INV.in_zone == true)

    -- Open on rising edge of (in zone + right grip). Close via native UI / same gesture.
    -- Order either way works: grip then touch, or touch then grip.
    local grip_now = get_right_grip_pressed() == true
    local open_ready = INV.in_zone == true and grip_now
    local open_edge = open_ready and not INV.open_ready_prev
    INV.open_ready_prev = open_ready
    if INV.in_zone and not grip_now then
        INV.status = "need_grip"
    end
    if open_edge then
        local now = os.clock()
        local cd = tonumber(P.inventory_cooldown) or 0.8
        if now - (INV.last_open_t or -1) >= cd then
            INV.last_open_t = now
            local ok = INV.try_open()
            if ok and rj then
                if CFG.zone_haptic_enabled ~= false and CFG.inventory_zone_haptic_enabled ~= false then
                    holster_haptic_pulse(rj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
                else
                    holster_haptic_pulse(rj, CFG.grab_haptic_duration, CFG.grab_haptic_frequency, CFG.grab_haptic_amplitude)
                end
            end
        else
            INV.status = "cooldown"
        end
    elseif (INV.inject_frames or 0) > 0 then
        local left = tonumber(rawget(_G, "__vr_inventory_gesture_inject")) or 0
        if left < INV.inject_frames then
            rawset(_G, "__vr_inventory_gesture_inject", INV.inject_frames)
        end
    end
end

STOW.pick_closest_from_list = function(list)
    local best = nil
    for _, c in ipairs(list) do
        if not best or (c.state.last_dist or 999) < (best.state.last_dist or 999) then
            best = c
        end
    end
    return best
end

STOW.chris_resolve_hip_knife_overlap = function()
    if not STOW.is_chris_player() then return end
    if not knife.in_zone then return end
    local hd = hip.last_dist
    local kd = knife.last_dist
    local hip_closer = hip.in_zone == true
    if type(hd) == "number" and type(kd) == "number" and hd <= (kd + 0.02) then
        hip_closer = true
    end
    if not hip_closer then return end
    knife.in_zone = false
end

STOW.resolve_knife_medicine_overlap = function(P)
    -- Knife chest offset often sits on the medicine bottle. When medicine can be
    -- drawn, never let the knife zone keep the hand — including "below bottle"
    -- where medicine mesh exit fires before knife exit.
    local med_draw = CFG.medicine_enabled ~= false
        and STOW.medicine_can_grab() == true
    local med_zone_on = med_draw and STOW.holster_zone_active(P, "medicine") == true
    local kd = tonumber(knife.last_dist)
    local md = tonumber(medicine.last_dist)
    if type(kd) ~= "number" then kd = 1e9 end
    if type(md) ~= "number" then md = 1e9 end

    local suppress_knife = false
    if med_zone_on and knife.in_zone then
        if medicine.in_zone then
            suppress_knife = true
        elseif md <= 0.08 then
            -- Soft claim: fingers still near medicine mesh while knife OBB owns the hand.
            suppress_knife = true
            medicine.in_zone = true
        end
    elseif knife.in_zone and medicine.in_zone then
        -- No med draw candidate: keep closer slot.
        suppress_knife = md <= (kd + 0.01)
        if not suppress_knife then
            medicine.in_zone = false
            medicine.zone_enter_pulse = false
            medicine.haptic_pending_frames = 0
        end
    end

    -- Empty medicine slot must never claim the hand (stops ghost can-grab rumble).
    if not med_draw then
        medicine.in_zone = false
        medicine.zone_enter_pulse = false
        medicine.haptic_pending_frames = 0
        medicine._med_can_prev = false
    end

    if suppress_knife then
        knife.in_zone = false
        knife.zone_enter_pulse = false
        knife.haptic_pending_frames = 0
    end

end

STOW.pick_closest_holster_zone = function(holster_zones, cur_item_id)
    local active = {}
    for _, c in ipairs(holster_zones) do
        if c.state.in_zone and (c.can_stow or c.can_draw) then
            active[#active + 1] = c
        end
    end
    if #active == 0 then return nil end

    local cur_slot = holster_slot_for_item_id(cur_item_id)
        or fallback_slot_from_weapon_type(re8vr.weapon)
    if rawget(_G, "__re8_medicine_in_hand") == true then
        cur_slot = "medicine"
    end
    if cur_item_id and not cur_slot and not is_bare_hands() then
        local excluded = is_holster_excluded_weapon(nil, cur_item_id)
        local stows, draws = {}, {}
        for _, c in ipairs(active) do
            if (not excluded) and c.can_stow then stows[#stows + 1] = c end
            if c.can_draw then draws[#draws + 1] = c end
        end
        if #stows > 0 then return STOW.pick_closest_from_list(stows) end
        if #draws > 0 then return STOW.pick_closest_from_list(draws) end
        if excluded then return nil end
        return STOW.pick_closest_from_list(active)
    end

    if cur_slot then
        local home_stow = {}
        local cross_draw = {}
        for _, c in ipairs(active) do
            if c.can_stow and c.slot == cur_slot then
                home_stow[#home_stow + 1] = c
            end
            if c.can_draw and c.slot ~= cur_slot then
                cross_draw[#cross_draw + 1] = c
            end
        end
        if cur_slot == "pistol" or cur_slot == "knife" or cur_slot == "longarm" then
            local weapon_draw = {}
            for _, c in ipairs(cross_draw) do
                if c.slot ~= "medicine" then
                    weapon_draw[#weapon_draw + 1] = c
                end
            end
            if #weapon_draw > 0 then
                cross_draw = weapon_draw
            end
        end
        local home_best = nil
        if #home_stow > 0 then
            home_best = STOW.pick_closest_from_list(home_stow)
        end
        local cross_best = nil
        if #cross_draw > 0 then
            cross_best = STOW.pick_closest_from_list(cross_draw)
        end
        local chosen = home_best or cross_best
        if home_best and cross_best then
            if (home_best.state.last_dist or 999) <= (cross_best.state.last_dist or 999) then
                chosen = home_best
            else
                chosen = cross_best
            end
        end
        if chosen then return chosen end
    end

    return STOW.pick_closest_from_list(active)
end

STOW.holster_zone_active = function(P, slot)
    if slot == "chest" or slot == "utility" then return false end
    -- Medicine zone only while a bottle still exists in inventory.
    if slot == "medicine" then
        return STOW.medicine_can_grab() == true
    end
    local cached_id = resolve_profile_item_id(P, slot)
    if cached_id and item_id_allowed_for_holster_slot(cached_id, slot) then return true end
    if not is_bare_hands() then
        local item_id = get_current_weapon_item_id()
        if item_id_allowed_for_holster_slot(item_id, slot) then return true end
        local cur_slot = get_effective_holster_slot_for_cur_weapon()
        if cur_slot and cur_slot ~= slot and slot_has_draw_candidate(P, slot) then return true end
        return current_weapon_matches_holster_slot(slot)
    end
    return slot_has_draw_candidate(P, slot)
end

STOW.can_stow_to_holster_zone = function(target_slot)
    if target_slot == "medicine" and rawget(_G, "__re8_medicine_in_hand") == true then
        return true
    end
    if is_bare_hands() or not target_slot or target_slot == "chest" or target_slot == "utility" then return false end
    local item_id = resolve_equipped_item_id(get_active_weapon_object())
    if is_holster_excluded_weapon(nil, item_id) then return false end
    return item_id_allowed_for_holster_slot(item_id, target_slot)
end

local apply_holster_vr_input_suppress
;(function()
    local KIND = nil
    pcall(function() KIND = statics.generate("app.InputDefine.Kind") end)
    local HOLD_BIT = (KIND and KIND.HOLD) or 64
    local ATTACK_BIT = (KIND and KIND.ATTACK) or 1
    local STRIP_RIGHT = HOLD_BIT | (KIND and KIND.UI_SHIFT_RIGHT or 536870912)
    local STRIP_ATTACK = ATTACK_BIT
    local BUTTON_OFF = { Down = 0x10, On = 0x18, Up = 0x20 }
    local LTRIG_BOTTOM = nil
    local RTRIG_BOTTOM = nil
    pcall(function() LTRIG_BOTTOM = via.hid.GamePadButton.LTrigBottom end)
    pcall(function() RTRIG_BOTTOM = via.hid.GamePadButton.RTrigBottom end)
    if type(LTRIG_BOTTOM) ~= "number" then LTRIG_BOTTOM = 0 end
    if type(RTRIG_BOTTOM) ~= "number" then RTRIG_BOTTOM = 0 end

    local function holster_qte_passthrough()
        if is_cinematic_blocking() then return true end
        if not re8vr or re8vr.can_use_hands ~= true or re8vr.is_in_cutscene == true then
            return true
        end
        local pass = false
        pcall(function()
            local eac = re8vr.event_action_controller
            if not eac or not managed_object_alive(eac) then return end
            local active = false
            local task = nil
            pcall(function() active = eac:call("get_isActive") == true end)
            pcall(function() task = eac:get_field("CurrentTask") end)
            if active or (task ~= nil and managed_object_alive(task)) then
                pass = true
            end
        end)
        return pass
    end

    local function read_u64_field(obj, field_name)
        local v = nil
        pcall(function() v = obj:get_field(field_name) end)
        if type(v) == "number" then return v end
        local off = BUTTON_OFF[field_name]
        if not off then return nil end
        local ok, val = pcall(function() return obj:read_uint64(off) end)
        return ok and val or nil
    end

    local function write_u64_field(obj, field_name, value)
        pcall(function() obj:set_field(field_name, value) end)
        local off = BUTTON_OFF[field_name]
        if off then pcall(function() obj:write_uint64(off, value) end) end
    end

    local function strip_input_mask(input_system, mask)
        if not input_system or not mask or mask == 0 then return end
        local ok, bb = pcall(function() return input_system:call("get_ButtonBits") end)
        if not ok or not bb then return end
        for _, field_name in ipairs({ "Down", "On", "Up" }) do
            local cur = read_u64_field(bb, field_name)
            if type(cur) == "number" and (cur & mask) ~= 0 then
                write_u64_field(bb, field_name, cur & ~mask)
            end
        end
    end

    apply_holster_vr_input_suppress = function()
        if holster_qte_passthrough() then return end
        local block_hold = rawget(_G, "__vr_block_hold_in_holster_zone") == true
        local block_bare = CFG.enabled and is_bare_hands() == true
        if not block_hold and not block_bare then return end
        local input_system = sdk.get_managed_singleton("app.InputSystem")
        if input_system then
            if block_hold then
                strip_input_mask(input_system, STRIP_RIGHT)
            end
            if block_bare then
                strip_input_mask(input_system, STRIP_ATTACK)
            end
        end
    end

    local function should_block_bare_aim()
        if holster_qte_passthrough() then return false end
        return CFG.enabled and is_bare_hands() == true
    end

    local function clear_device_bare_combat_input(device, pad)
        if not device then return false end
        local analog_l, analog_r = -1, -1
        local had_ltrig, had_rtrig = false, false
        pcall(function()
            local ok, al = pcall(function() return device:call("get_AnalogL") end)
            if ok and type(al) == "number" then analog_l = al end
            local okr, ar = pcall(function() return device:call("get_AnalogR") end)
            if okr and type(ar) == "number" then analog_r = ar end
            local okb, btn = pcall(function() return device:call("get_Button") end)
            if okb and type(btn) == "number" then
                if LTRIG_BOTTOM ~= 0 then
                    had_ltrig = (btn & LTRIG_BOTTOM) ~= 0
                    if had_ltrig then btn = btn & ~LTRIG_BOTTOM end
                end
                if RTRIG_BOTTOM ~= 0 then
                    had_rtrig = (btn & RTRIG_BOTTOM) ~= 0
                    if had_rtrig then btn = btn & ~RTRIG_BOTTOM end
                end
                if had_ltrig or had_rtrig then
                    pcall(function() device:call("set_Button", btn) end)
                    pcall(function() device:call("set_ButtonDown", btn) end)
                end
            end
            if (analog_l or 0) > 0.01 or had_ltrig then
                pcall(function() device:call("set_AnalogL", 0.0) end)
            end
            if (analog_r or 0) > 0.01 or had_rtrig then
                pcall(function() device:call("set_AnalogR", 0.0) end)
            end
            if pad then
                if (analog_l or 0) > 0.01 or had_ltrig then
                    pcall(function() pad:set_field("_TriggerLeftValue", 0.0) end)
                end
                if (analog_r or 0) > 0.01 or had_rtrig then
                    pcall(function() pad:set_field("_TriggerRightValue", 0.0) end)
                end
            end
        end)
        local did = (analog_l or 0) > 0.01 or (analog_r or 0) > 0.01 or had_ltrig or had_rtrig
        return did, analog_l, analog_r, had_ltrig, had_rtrig
    end

    local function resolve_pad_device(pad)
        if not pad then return nil end
        local device = nil
        pcall(function() device = pad:get_field("Device") end)
        if device then return device end
        pcall(function()
            local padman = sdk.get_managed_singleton(sdk.game_namespace("PadManager"))
            if not padman then return end
            local active = padman:call("get_activePad")
            local merged = padman:call("get_mergedPad")
            local mp = active or merged
            if mp == pad then device = mp:get_field("Device") end
        end)
        return device
    end

    -- Deferred install: runs after Pad:update pre so we clear combat input before Pad bakes triggers.
    local pad_aim_hook_installed = false
    local shoot_block_hook_installed = false
    local inventory_guard_hook_installed = false

    local function install_holster_snapback_block_hooks()
        if inventory_guard_hook_installed then return end
        inventory_guard_hook_installed = true

        local inv_td = sdk.find_type_definition("app.Inventory")
        if inv_td then
            local apply_m = inv_td:get_method("applyQuickSlot")
            if apply_m then
                sdk.hook(apply_m, function(args)
                    if NATIVE_WEAPON_SEL.allow_one_apply_quickslot then
                        NATIVE_WEAPON_SEL.allow_one_apply_quickslot = false
                        return nil
                    end
                    if yield_holster_guard_for_native_dpad("inv_applyQuickSlot") then
                        return nil
                    end
                    if not holster_guard_active() then return nil end
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end, function(retval)
                    if NATIVE_WEAPON_SEL.excluded_equip_in_progress then return retval end
                    if holster_guard_active() then return retval end
                    -- Native D-pad / quickslot apply while armed: open a short
                    -- yield window so mesh fixup does not fight HolsterToMove.
                    if not is_bare_hands() then
                        NATIVE_WEAPON_SEL.native_dpad_until = os.clock() + 1.6
                        WEAPON_WATCH.our_equip_until = 0
                        HOLSTER_GUARD.mesh_repair_until = 0
                    end
                    pcall(function()
                        if not is_bare_hands() and not is_menu_blocking() then return end
                        local id = nil
                        if re8vr.inventory then
                            local ism = safe_call(re8vr.inventory, "get_ItemSlotManager")
                            local sel = ism and safe_call(ism, "getSelectItemSlotNo")
                            local qs = (ism and sel ~= nil) and safe_call(ism, "itemSlotNo2QuickSlotNo", sel) or nil
                            if qs ~= nil then
                                local _, qs_id = get_item_id_from_quickslot(qs)
                                id = qs_id
                            end
                        end
                        if not id and NATIVE_WEAPON_SEL.last_quick_slot ~= nil then
                            local _, qs_id = get_item_id_from_quickslot(NATIVE_WEAPON_SEL.last_quick_slot)
                            id = qs_id
                        end
                        STOW.try_finish_excluded_inv_equip(id)
                    end)
                    return retval
                end)
            end

            local equip_m = inv_td:get_method("equipWeapon")
            if equip_m then
                sdk.hook(equip_m, function(args)
                    local target_id = read_hook_item_id_arg(args[3])
                    local excluded = target_id and is_holster_excluded_weapon(nil, target_id) or false
                    if target_id and excluded
                        and NATIVE_WEAPON_SEL.excluded_equip_in_progress ~= true then
                        NATIVE_WEAPON_SEL.pending_excluded_inv_id = normalize_item_id(target_id) or ""
                    end
                    if yield_holster_guard_for_native_dpad("inv_equipWeapon") then
                        return nil
                    end
                    if not holster_guard_active() then return nil end
                    local guard_id = HOLSTER_GUARD.item_id
                    -- Matching holster weapon: always allow.
                    if target_id and target_id ~= ""
                        and normalize_item_id(target_id) == normalize_item_id(guard_id) then
                        return nil
                    end
                    if target_id and target_id ~= ""
                        and is_holster_excluded_weapon(nil, target_id) then
                        return nil
                    end
                    -- Known foreign weapon: block (Frame 1 D-pad flash path).
                    if target_id and target_id ~= "" then
                        return sdk.PreHookResult.SKIP_ORIGINAL
                    end
                    -- Parse fail: always allow (never SKIP on unknown id).
                    return nil
                end, function(retval)
                    local id = NATIVE_WEAPON_SEL.pending_excluded_inv_id
                    NATIVE_WEAPON_SEL.pending_excluded_inv_id = ""
                    if id and id ~= "" then
                        pcall(STOW.try_finish_excluded_inv_equip, id)
                    end
                    return retval
                end)
            end
        end

        local ism_td = sdk.find_type_definition("app.ItemSlotManager")
        if ism_td then
            local ism_apply = ism_td:get_method("applyQuickSlot")
            if ism_apply then
                sdk.hook(ism_apply, function(args)
                    if NATIVE_WEAPON_SEL.allow_one_apply_quickslot then
                        NATIVE_WEAPON_SEL.allow_one_apply_quickslot = false
                        return nil
                    end
                    if yield_holster_guard_for_native_dpad("ism_applyQuickSlot") then
                        return nil
                    end
                    if not holster_guard_active() then return nil end
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end, function(retval)
                    if NATIVE_WEAPON_SEL.excluded_equip_in_progress then return retval end
                    if holster_guard_active() then return retval end
                    pcall(function()
                        if not is_bare_hands() and not is_menu_blocking() then return end
                        local ism = re8vr.inventory and safe_call(re8vr.inventory, "get_ItemSlotManager")
                        local sel = ism and safe_call(ism, "getSelectItemSlotNo")
                        local qs = (ism and sel ~= nil) and safe_call(ism, "itemSlotNo2QuickSlotNo", sel) or nil
                        local id = nil
                        if qs ~= nil then
                            local _, qs_id = get_item_id_from_quickslot(qs)
                            id = qs_id
                        end
                        STOW.try_finish_excluded_inv_equip(id)
                    end)
                    return retval
                end)
            end
        end
        -- NOTE: Do NOT hook EquipController / PlayerWeaponChange with SKIP_ORIGINAL.
        -- Avoid inventory walks inside equip hooks (reentrancy).
    end

    local function install_bare_hands_shoot_block()
        if shoot_block_hook_installed then return end
        local td = sdk.find_type_definition("app.WeaponGunCore")
        local shoot_m = td and td:get_method("shoot")
        if not shoot_m then return end
        shoot_block_hook_installed = true
        sdk.hook(shoot_m, function(args)
            if not should_block_bare_aim() then return nil end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, function(retval)
            return retval
        end)
    end

    local function install_pad_bare_aim_hook()
        if pad_aim_hook_installed then return end
        local pad_td = sdk.find_type_definition("app.Pad")
        local pad_update = pad_td and pad_td:get_method("update")
        if not pad_update then return end
        pad_aim_hook_installed = true
        sdk.hook(pad_update, function(args)
            if not should_block_bare_aim() then return nil end
            local pad = nil
            pcall(function() pad = sdk.to_managed_object(args[2]) end)
            local device = resolve_pad_device(pad)
            clear_device_bare_combat_input(device, pad)
            return nil
        end, function(retval)
            return retval
        end)
    end

    re.on_frame(function()
        if not pad_aim_hook_installed then
            install_pad_bare_aim_hook()
        end
        if not shoot_block_hook_installed then
            install_bare_hands_shoot_block()
        end
        if not inventory_guard_hook_installed then
            install_holster_snapback_block_hooks()
        end
    end)

    re.on_application_entry("UpdateHID", function()
        local pass = holster_qte_passthrough()
        if pass then
            rawset(_G, "__vr_block_bare_hands_aim", false)
            rawset(_G, "__vr_block_hold_in_holster_zone", false)
        elseif should_block_bare_aim() then
            rawset(_G, "__vr_block_bare_hands_aim", true)
            rawset(_G, "__vr_block_hold_in_holster_zone", true)
        elseif rawget(_G, "__vr_in_holster_zone") == true then
            rawset(_G, "__vr_block_hold_in_holster_zone", true)
            rawset(_G, "__vr_block_bare_hands_aim", false)
        else
            rawset(_G, "__vr_block_bare_hands_aim", false)
            rawset(_G, "__vr_block_hold_in_holster_zone", false)
        end
        apply_holster_vr_input_suppress()
    end)

    re.on_application_entry("LateUpdateBehavior", apply_holster_vr_input_suppress)
end)()

STOW.silence_zones = function()
    hip.in_zone = false
    shoulder.in_zone = false
    chest.in_zone = false
    knife.in_zone = false
    medicine.in_zone = false
end

STOW.refresh_zones_for_suppress = function()
    if not CFG.enabled or not CFG.suppress_shoot_ready_in_holster_zone then
        STOW.silence_zones()
        return false
    end
    if is_menu_blocking() or block_weapon_inputs_active() then
        STOW.silence_zones()
        return false
    end

    local P = get_profile()
    local hand_pos = get_right_hand_pos()
    local hand_world = HJ.get_right_hand_world()
    if not hand_pos and not hand_world then
        STOW.silence_zones()
        return false
    end

    local hover = STOW.hover_m()
    local in_any = false
    if CFG.hip_pistol_enabled and rawget(_G, "__visceral_holsters_on") ~= true then
        refresh_hmd_holster_zone(hip, "pistol", P,
            P.hip_pistol_trigger_dist or hover, P.hip_pistol_release_dist or (hover + 0.10),
            hand_world or hand_pos, nil)
        in_any = in_any or hip.in_zone
    else hip.in_zone = false end

    if CFG.shoulder_enabled and rawget(_G, "__visceral_holsters_on") ~= true then
        refresh_hmd_holster_zone(shoulder, "longarm", P,
            P.shoulder_trigger_dist or hover, P.shoulder_release_dist or (hover + 0.10),
            hand_world or hand_pos, nil)
        in_any = in_any or shoulder.in_zone
    else shoulder.in_zone = false end

    if CFG.chest_enabled then
        refresh_hmd_holster_zone(chest, "chest", P,
            P.chest_trigger_dist or hover, P.chest_release_dist or (hover + 0.10),
            hand_pos, nil)
        in_any = in_any or chest.in_zone
    else chest.in_zone = false end

    if CFG.knife_enabled and STOW.holster_zone_active(P, "knife") then
        refresh_hmd_holster_zone(knife, "knife", P,
            P.knife_trigger_dist or hover, P.knife_release_dist or (hover + 0.10),
            hand_world or hand_pos, nil)
        in_any = in_any or knife.in_zone
    else knife.in_zone = false end
    STOW.chris_resolve_hip_knife_overlap()
    STOW.resolve_knife_medicine_overlap(P)
    in_any = hip.in_zone or shoulder.in_zone or chest.in_zone or knife.in_zone

    return in_any
end

HOLSTER_CALIB.decompose = function(hand_pos, anchor_pos, right, up, fwd)
    local dx = hand_pos.x - anchor_pos.x
    local dy = hand_pos.y - anchor_pos.y
    local dz = hand_pos.z - anchor_pos.z
    return vec3_dot({ x = dx, y = dy, z = dz }, right),
        vec3_dot({ x = dx, y = dy, z = dz }, up),
        vec3_dot({ x = dx, y = dy, z = dz }, fwd)
end

HOLSTER_CALIB.clear_drag = function()
    HOLSTER_CALIB.target = nil
    HOLSTER_CALIB.drag_active = false
    HOLSTER_CALIB.drag_waiting = false
    HOLSTER_CALIB.drag_updates = 0
    HOLSTER_CALIB.drag_last_log_t = 0
    HOLSTER_CALIB.drag_deadline = 0
end

HOLSTER_CALIB.apply_offsets = function(P, target, off_x, off_y, off_z)
    if not P or not target then return false end
    if target == "medicine" then
        P.medicine_off_right = off_x
        P.medicine_off_up = off_y
        P.medicine_off_forward = off_z
    elseif target == "hip" then
        P.hip_pistol_off_right = off_x
        P.hip_pistol_off_up = off_y
        P.hip_pistol_off_forward = off_z
    elseif target == "ammo_left" then
        P.ammo_left_off_right = off_x
        P.ammo_left_off_up = off_y
        P.ammo_left_off_forward = off_z
    elseif target == "shoulder" then
        P.shoulder_off_x = off_x
        P.shoulder_off_y = off_y
        P.shoulder_off_z = off_z
    elseif target == "knife" then
        P.knife_off_x = off_x
        P.knife_off_y = off_y
        P.knife_off_z = off_z
    elseif target == "chest" then
        P.chest_off_x = off_x
        P.chest_off_y = off_y
        P.chest_off_z = off_z
    else
        return false
    end
    return true
end

-- Live hold-and-drag: RT for weapon holsters; LT for left-hip ammo holster.
HOLSTER_CALIB.tick_live_drag = function(P, rj)
    if not HOLSTER_CALIB.target then return end
    local now = os.clock()
    local ammo_calib = HOLSTER_CALIB.target == "ammo_left"
    local lt = false
    pcall(function() lt = HJ.get_left_trigger() == true end)
    local rt = get_right_trigger_pressed() == true
    local trig = ammo_calib and lt or rt
    local haptic_joy = rj
    if ammo_calib then
        haptic_joy = FLASH.get_left_joystick()
    end
    if HOLSTER_CALIB.drag_waiting then
        if trig then
            HOLSTER_CALIB.drag_waiting = false
            HOLSTER_CALIB.drag_active = true
            HOLSTER_CALIB.drag_deadline = now + 10.0
            if haptic_joy then haptic_pulse(haptic_joy, 0.08, 200.0, 0.7) end
        elseif now > (HOLSTER_CALIB.drag_deadline or 0) then
            HOLSTER_CALIB.clear_drag()
            HOLSTER_CALIB.last_block = "drag_timeout"
            HOLSTER_CALIB.hold_cooldown_until = now + 0.6
        end
        return
    end
    if not HOLSTER_CALIB.drag_active then
        HOLSTER_CALIB.clear_drag()
        return
    end

    local slot_key = CALIB_TARGET_TO_SLOT[HOLSTER_CALIB.target]
    local hand_pos, ax, ay, az, right, up, fwd, base_pos
    if ammo_calib then
        hand_pos = HJ.get_left_hand_world()
        base_pos, ax, ay, az = HJ.slot_base_pos("ammo_left")
        right, up, fwd = ax, ay, az
    elseif HOLSTER_CALIB.target == "hip" or HJ.uses_torso(slot_key)
        or (HJ.uses_joint(slot_key) and slot_key ~= "ammo_left") then
        hand_pos = HJ.get_right_hand_world()
        base_pos, ax, ay, az = HJ.slot_base_pos(slot_key or "pistol")
        right, up, fwd = ax, ay, az
    else
        hand_pos = get_right_hand_pos()
        local hmd
        hmd, right, up, fwd = get_hmd_pose_vr()
        base_pos = HJ.slot_base_pos(slot_key)
    end

    if hand_pos and base_pos and right and up and fwd and slot_key then
        local off_x, off_y, off_z = HOLSTER_CALIB.decompose(hand_pos, base_pos, right, up, fwd)
        if HOLSTER_CALIB.apply_offsets(P, HOLSTER_CALIB.target, off_x, off_y, off_z) then
            HOLSTER_CALIB.drag_updates = (HOLSTER_CALIB.drag_updates or 0) + 1
            if (now - (HOLSTER_CALIB.drag_last_log_t or 0)) > 0.35 then
                HOLSTER_CALIB.drag_last_log_t = now
            end
        end
    end

    if not trig then
        save_cfg()
        if haptic_joy then haptic_pulse(haptic_joy, 0.22, 240.0, 1.0) end
        HOLSTER_CALIB.last_block = "saved"
        HOLSTER_CALIB.hold_cooldown_until = now + 0.85
        HOLSTER_CALIB.clear_drag()
        return
    end

    if now > (HOLSTER_CALIB.drag_deadline or 0) then
        save_cfg()
        HOLSTER_CALIB.last_block = "drag_timeout_saved"
        HOLSTER_CALIB.hold_cooldown_until = now + 0.85
        HOLSTER_CALIB.clear_drag()
    end
end

HOLSTER_CALIB.start_capture = function(target)
    HOLSTER_CALIB.target = target
    local armed = false
    if target == "ammo_left" then
        armed = HJ.get_left_trigger() == true
    else
        armed = get_right_trigger_pressed() == true
    end
    HOLSTER_CALIB.drag_active = armed
    HOLSTER_CALIB.drag_waiting = not HOLSTER_CALIB.drag_active
    HOLSTER_CALIB.drag_updates = 0
    HOLSTER_CALIB.drag_last_log_t = 0
    HOLSTER_CALIB.drag_deadline = os.clock() + 10.0
    HOLSTER_CALIB.hold_t0 = 0
    HOLSTER_CALIB.hold_last_beep = -1
    HOLSTER_CALIB.hold_target = nil
end

HOLSTER_CALIB.clear_quick_hold = function()
    HOLSTER_CALIB.hold_t0 = 0
    HOLSTER_CALIB.hold_last_beep = -1
    HOLSTER_CALIB.hold_target = nil
    HOLSTER_CALIB.hold_miss = 0
end

HOLSTER_CALIB.note_block = function(reason)
    HOLSTER_CALIB.last_block = reason or ""
    local now = os.clock()
    if (now - (HOLSTER_CALIB.diag_last_t or 0)) < 0.45 then return end
    HOLSTER_CALIB.diag_last_t = now
end

-- Bare hands + RT held in zone for quick_calib_hold_s → start_capture (haptic countdown).
HOLSTER_CALIB.tick_quick_adjust = function(rj, hip_z, shoulder_z, knife_z, med_z)
    if CFG.quick_calib_enabled == false then
        HOLSTER_CALIB.clear_quick_hold()
        HOLSTER_CALIB.note_block("disabled")
        return
    end
    if HOLSTER_CALIB.target then
        HOLSTER_CALIB.clear_quick_hold()
        return
    end
    local now = os.clock()
    if now < (HOLSTER_CALIB.hold_cooldown_until or 0) then
        return
    end

    local bare = is_bare_hands() == true
        and rawget(_G, "__re8_medicine_in_hand") ~= true
    local trig = get_right_trigger_pressed() == true
    local target = nil
    local best_d = 1e9
    if hip_z and hip_z.in_zone and CFG.hip_pistol_enabled and rawget(_G, "__visceral_holsters_on") ~= true then
        local d = tonumber(hip_z.last_dist) or 0
        if d < best_d then best_d = d; target = "hip" end
    end
    if shoulder_z and shoulder_z.in_zone and CFG.shoulder_enabled and rawget(_G, "__visceral_holsters_on") ~= true then
        local d = tonumber(shoulder_z.last_dist) or 0
        if d < best_d then best_d = d; target = "shoulder" end
    end
    if knife_z and knife_z.in_zone and CFG.knife_enabled then
        local d = tonumber(knife_z.last_dist) or 0
        if d < best_d then best_d = d; target = "knife" end
    end
    if med_z and med_z.in_zone and CFG.medicine_enabled then
        local d = tonumber(med_z.last_dist) or 0
        if d < best_d then best_d = d; target = "medicine" end
    end

    if not bare or not trig or not target then
        if HOLSTER_CALIB.hold_t0 and HOLSTER_CALIB.hold_t0 > 0 then
            HOLSTER_CALIB.hold_miss = (HOLSTER_CALIB.hold_miss or 0) + 1
            -- Allow brief flicker (~8 frames) without resetting the 3s hold.
            if HOLSTER_CALIB.hold_miss <= 8 then
                return
            end
        end
        HOLSTER_CALIB.clear_quick_hold()
        if not bare then HOLSTER_CALIB.note_block("not_bare")
        elseif not trig then HOLSTER_CALIB.note_block("no_trigger")
        else HOLSTER_CALIB.note_block("not_in_zone") end
        return
    end

    HOLSTER_CALIB.hold_miss = 0
    HOLSTER_CALIB.last_block = "holding"

    local hold_need = tonumber(CFG.quick_calib_hold_s) or 3.0
    if HOLSTER_CALIB.hold_t0 == 0 or HOLSTER_CALIB.hold_target ~= target then
        HOLSTER_CALIB.hold_t0 = now
        HOLSTER_CALIB.hold_target = target
        HOLSTER_CALIB.hold_last_beep = -1
        if rj then
            holster_haptic_pulse(rj, CFG.zone_haptic_duration, CFG.zone_haptic_frequency, CFG.zone_haptic_amplitude)
        end
    end

    local remaining = hold_need - (now - HOLSTER_CALIB.hold_t0)
    if remaining > 0 then
        local int_s = math.ceil(remaining)
        if int_s ~= HOLSTER_CALIB.hold_last_beep then
            HOLSTER_CALIB.hold_last_beep = int_s
            if rj then haptic_pulse(rj, 0.06, 160.0, 0.55) end
        end
        return
    end

    HOLSTER_CALIB.clear_quick_hold()
    HOLSTER_CALIB.last_block = "dragging"
    if rj then haptic_pulse(rj, 0.14, 220.0, 0.95) end
    HOLSTER_CALIB.start_capture(target)
end

re.on_pre_application_entry("LockScene", function()
    protect_re8vr_weapon_for_lockscene()
end)

re.on_pre_application_entry("UpdateBehavior", function()
    if is_menu_blocking() then
        protect_re8vr_weapon_for_lockscene()
        purge_stale_equipped_weapon_state("menu_block")
        if FLY.active then FLY.cancel("menu") end
        if holster_guard_active() or NATIVE_WEAPON_SEL.equip_in_progress
            or HOLSTER_ACTION.pending ~= nil then
            if not re8vr or not re8vr.can_use_hands
                or (re8vr.player and not managed_object_alive(re8vr.player))
                or (re8vr.inventory and not managed_object_alive(re8vr.inventory))
                or os.clock() < (GRIP.scene_block_until or 0) then
                clear_holster_equip_guard("scene_unload")
                NATIVE_WEAPON_SEL.equip_in_progress = false
                NATIVE_WEAPON_SEL.pending_gun_combat_fixup = false
                NATIVE_WEAPON_SEL.gun_fixup_until = 0
                HOLSTER_ACTION.pending = nil
                if FLY.active then FLY.cancel("scene_unload") end
                if re8vr then re8vr.weapon = nil end
            end
        end
        return
    end
    if re8vr and re8vr.update_pointers then
        pcall(function() re8vr:update_pointers() end)
    end
    sanitize_re8vr_weapon_pointer()
    purge_stale_equipped_weapon_state("update_behavior")
    pcall(function()
        local function addr_of(obj)
            local a = 0
            if obj then pcall(function() a = obj:get_address() or 0 end) end
            return a
        end
        local pl_a = addr_of(re8vr and re8vr.player)
        local inv_a = addr_of(re8vr and re8vr.inventory)
        local function ptr_step(prev, addr, dead)
            if prev ~= 0 and addr == 0 then return false, prev end
            if prev ~= 0 and addr ~= 0 and addr ~= prev then return true, 0 end
            if prev == 0 and addr ~= 0 then
                if dead ~= 0 and addr ~= dead then return true, 0 end
                return false, 0
            end
            return false, dead
        end
        local rst_pl, dead_pl = ptr_step(NATIVE_WEAPON_SEL.sess_pl or 0, pl_a, NATIVE_WEAPON_SEL.sess_dead_pl or 0)
        local rst_inv, dead_inv = ptr_step(NATIVE_WEAPON_SEL.sess_inv or 0, inv_a, NATIVE_WEAPON_SEL.sess_dead_inv or 0)
        NATIVE_WEAPON_SEL.sess_dead_pl, NATIVE_WEAPON_SEL.sess_dead_inv = dead_pl, dead_inv
        if rst_pl or rst_inv then
            reset_holster_combat_script_state("session_ptr")
        end
        NATIVE_WEAPON_SEL.sess_pl = pl_a
        NATIVE_WEAPON_SEL.sess_inv = inv_a
    end)
    enforce_stow_lockout()
    STOW.tick_flash()
    FLY.tick()
    -- Publish authoritative in-hand weapon id. Also capture the mesh-controller weaponMeshObject name.
    pcall(function()
        local active_id = get_current_weapon_item_id()
        local wmo_name = nil
        refresh_components(false)
        local mc = COMPONENTS.mesh_controller
        if mc then
            local mesh_go = mc:call("get_weaponMeshObject")
            if mesh_go then wmo_name = mesh_go:call("get_Name") end
        end
        local wmo_id = normalize_item_id(wmo_name)
        -- Only probe EquipController name when primary resolvers miss (common path skips this).
        local raw_em_id = nil
        local need_em_fallback = (active_id == nil or active_id == "") and (wmo_id == nil or wmo_id == "")
        local em = COMPONENTS.equip_manager
        if em and need_em_fallback then
            local em_w = safe_call(em, "get_equipWeaponRight")
            if em_w then
                local go = safe_call(em_w, "get_GameObject")
                local raw_em_name = go and safe_call(go, "get_Name") or nil
                raw_em_id = normalize_item_id(raw_em_name)
            end
        end
        -- Publish authoritative in-hand id, now INCLUDING Hand-type melee (raw EM name).
        -- Bare hands must publish "Hand" (not "") so ammo HUD treats stow as melee hide.
        local bare = is_bare_hands() == true
        local publish_id = active_id or wmo_id or raw_em_id or ""
        if bare then
            publish_id = "Hand"
        end
        rawset(_G, "__re8_active_weapon_id", publish_id)
        rawset(_G, "__re8_active_wmo_id", wmo_id or "")
        rawset(_G, "__re8_bare_hands", bare)
        local pub_s = tostring(publish_id or "")
        local pub_gun = pub_s ~= "" and pub_s ~= "Hand"
            and weapon_type_for_item_id(pub_s) ~= "MED"
        if pub_gun and rawget(_G, "__re8_medicine_in_hand") == true
            and (os.clock() - (HEAL.last_grab_t or 0)) > 0.45 then
            if type(FLY.return_medicine_to_holster) == "function" then
                FLY.return_medicine_to_holster("in_hand_gun")
            else
                rawset(_G, "__re8_medicine_in_hand", false)
                FLY.clear_bridge()
            end
        end
        if pub_gun
            and (HEAL._lua_use_pending == true
                or HEAL._use_weapon ~= nil
                or os.clock() < (tonumber(HEAL._use_anim_until) or 0)) then
            HEAL.abort_native_use()
        end
        local did_reassert = false
        local is_chris = STOW.is_chris_player() == true
        local med_hold = rawget(_G, "__re8_medicine_in_hand") == true
        local using = os.clock() < (HEAL._use_anim_until or 0)
        if using == false then
            HEAL._use_weapon = nil
        end
        if is_chris then
            WEAPON_WATCH.last_chris_bare = bare
            local longarm_on = (not bare) and holster_slot_for_item_id(publish_id) == "longarm"
            rawset(_G, "__re8_chris_longarm_equipped", longarm_on == true)
            -- Grenade/utility must occlude parked holsters like longarm/bare.
            -- Body IgnoreDepth=false + holster always-on-top draws them over the vest.
            rawset(_G, "__re8_chris_occlude_holsters", (longarm_on or bare
                or is_holster_excluded_weapon(nil, publish_id)) == true)
            if longarm_on then
                local w = re8vr and re8vr.weapon
                STOW.fix_chris_longarm_opaque(w, publish_id)
            elseif bare then
                STOW.fix_chris_body_occlude_holsters()
            end
            if using and HEAL._use_weapon and not pub_gun then
                STOW.fix_chris_held_item_opaque(HEAL._use_weapon)
            elseif (not bare) and (not longarm_on)
                and is_holster_excluded_weapon(nil, publish_id) then
                STOW.fix_chris_held_item_opaque(re8vr and re8vr.weapon)
            end
        else
            rawset(_G, "__re8_chris_longarm_equipped", false)
            rawset(_G, "__re8_chris_occlude_holsters", false)
        end
        WEAPON_WATCH.last_pub_id = publish_id
        WEAPON_WATCH.depth_reasserted = did_reassert
    end)
    yield_holster_guard_for_native_dpad("frame")
    tick_holster_equip_guard()
    if NATIVE_WEAPON_SEL.equip_in_progress then return end
    tick_weapon_swap_mesh_fixup()
    STOW.tick_native_weapon_change_unstick()
    tick_native_weapon_selection()

    if not CFG.enabled or rawget(_G, "__vr_reloaded_master_enabled") == false then
        STOW.clear_weapon_hold_suppress()
    else
        local in_zone = false
        if CFG.suppress_shoot_ready_in_holster_zone then
            in_zone = STOW.refresh_zones_for_suppress()
        else
            STOW.silence_zones()
        end
        STOW.sync_weapon_hold_suppress(in_zone)
    end
    apply_holster_vr_input_suppress()
end)

re.on_frame(function()
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("holster.on_frame") end
    local function _pf()
        if _on then _p.finish("holster.on_frame") end
    end

    tick_shoot_ready_suppress()
    execute_pending_action()

    local pub = rawget(_G, "__re8_ammo_drop_publish_globals")
    if type(pub) == "function" then pcall(pub) end

    -- Head flashlight is independent of master holster enable (HMD zone + left grip).
    if rawget(_G, "__vr_reloaded_master_enabled") ~= false then
        if _on then _p.begin("holster.flash_inv") end
        FLASH.tick()
        -- Inventory gesture: right index + right grip near left wrist/hand (independent of holster master).
        INV.tick()
        if _on then _p.finish("holster.flash_inv") end
    end

    HJ.frame = (HJ.frame or 0) + 1

    local P = get_profile()
    local rj = get_right_joystick()
    HJ.tick_ammo_left_zone(P)
    rawset(_G, "__re8_holster_ammo_grab_haptic_enabled", CFG.ammo_grab_haptic_enabled ~= false)
    local ammo_mod = rawget(_G, "__re8_ammo_holster_mod")
    local ammo_in_zone = HJ.ammo_left.in_zone == true
    local holster_grab_fn = rawget(_G, "__re8_ammo_drop_tick_holster_grab")
    local inline_grab = rawget(_G, "__re8_mr_holster_grab_inline") == true
    if not inline_grab and type(holster_grab_fn) ~= "function" then
        if type(ammo_mod) == "table" and type(ammo_mod.tick_zone) == "function" then
            pcall(function() ammo_mod.tick_zone(ammo_in_zone) end)
        elseif type(ammo_mod) == "table" and type(ammo_mod.tick) == "function" then
            pcall(ammo_mod.tick)
        else
            local ammo_holster_tick = rawget(_G, "__re8_ammo_holster_tick")
            if type(ammo_holster_tick) == "function" then
                pcall(ammo_holster_tick)
            end
        end
    end
    rawset(_G, "__re8_ammo_holster_grip_live", FLASH.get_left_grip() == true)
    if type(holster_grab_fn) == "function" then
        do
            local ok_g, err_g = pcall(function() holster_grab_fn(ammo_in_zone) end)
            if not ok_g then
                pcall(function()
                    log.info("[re8_holster] grab_fn error: " .. tostring(err_g))
                end)
            end
        end
    end

    -- Live hold-and-drag calibration (replaces timed snapshot capture).
    HOLSTER_CALIB.tick_live_drag(P, rj)

    if not CFG.enabled or rawget(_G, "__vr_reloaded_master_enabled") == false then _pf(); return end
    if is_menu_blocking() or is_cinematic_blocking() then STOW.silence_zones(); _pf(); return end
    if not re8vr.can_use_hands or re8vr.is_reloading then STOW.silence_zones(); _pf(); return end

    track_weapon()
    if _on then _p.begin("holster.heal") end
    HEAL.sync()
    if _on then _p.finish("holster.heal") end

    if block_weapon_inputs_active() then
        STOW.silence_zones()
        if is_bare_hands() and get_right_trigger_pressed() then
            HOLSTER_CALIB.note_block("early_weapon_input_block")
        end
        _pf()
        return
    end
    -- Ammo in LH / inserting: keep probe mesh publishes (UpdateMotion). Skip
    -- finger mesh-grab here; grab is already suppressed below.
    local ammo_lock = manual_reload_blocks_holster()
    local holding_remedy = is_remedy_equipped()

    local hand_pos = get_right_hand_pos()
    local hand_world = HJ.get_right_hand_world()
    if not hand_pos and not hand_world then
        STOW.silence_zones()
        if is_bare_hands() and get_right_trigger_pressed() then
            HOLSTER_CALIB.note_block("early_no_hand_pos")
        end
        _pf()
        return
    end

    local grip_now = get_right_grip_pressed()
    local grip_was_held = GRIP.aim_prev
    GRIP.aim_prev = grip_now
    GRIP.suppress_haptics_for_aim = grip_now and grip_was_held

    local cur_id = get_current_weapon_item_id()
    local holster_zones = {}
    local hover = STOW.hover_m()

    if _on then _p.begin("holster.zones") end
    do
        local rec_t = os.clock()
        if (rec_t - (STOW._reconcile_t or 0)) >= 0.40 then
            STOW._reconcile_t = rec_t
            local cur_slot = cur_id and holster_slot_for_item_id(cur_id) or nil
            if cur_slot == "longarm" then
                reconcile_holster_slot_cache(P, "pistol")
                reconcile_holster_slot_cache(P, "knife")
                reconcile_holster_slot_cache(P, "medicine")
            elseif cur_slot == "pistol" then
                reconcile_holster_slot_cache(P, "longarm")
                reconcile_holster_slot_cache(P, "knife")
                reconcile_holster_slot_cache(P, "medicine")
            elseif cur_slot == "knife" then
                reconcile_holster_slot_cache(P, "pistol")
                reconcile_holster_slot_cache(P, "longarm")
                reconcile_holster_slot_cache(P, "medicine")
            elseif cur_slot == "medicine" then
                reconcile_holster_slot_cache(P, "pistol")
                reconcile_holster_slot_cache(P, "longarm")
                reconcile_holster_slot_cache(P, "knife")
            end
        end
    end

    if holding_remedy then
        hip.in_zone = false
        shoulder.in_zone = false
        knife.in_zone = false
    else
    if CFG.hip_pistol_enabled and rawget(_G, "__visceral_holsters_on") ~= true and STOW.holster_zone_active(P, "pistol") then
        -- Torso-anchored hip: world hand vs HMD yaw-only torso world position.
        refresh_hmd_holster_zone(hip, "pistol", P,
            P.hip_pistol_trigger_dist or hover, P.hip_pistol_release_dist or (hover + 0.10),
            hand_world or hand_pos, rj)
        holster_zones[#holster_zones + 1] = {
            slot = "pistol", state = hip, cooldown = P.hip_pistol_cooldown,
            can_stow = STOW.can_stow_to_holster_zone("pistol"),
            can_draw = slot_has_draw_candidate(P, "pistol")
                and can_holster_interact_draw("pistol"),
        }
    else hip.in_zone = false end

    if CFG.shoulder_enabled and rawget(_G, "__visceral_holsters_on") ~= true and STOW.holster_zone_active(P, "longarm") then
        refresh_hmd_holster_zone(shoulder, "longarm", P,
            P.shoulder_trigger_dist or hover, P.shoulder_release_dist or (hover + 0.10),
            hand_world or hand_pos, rj)
        holster_zones[#holster_zones + 1] = {
            slot = "longarm", state = shoulder, cooldown = P.shoulder_cooldown,
            can_stow = STOW.can_stow_to_holster_zone("longarm"),
            can_draw = slot_has_draw_candidate(P, "longarm")
                and can_holster_interact_draw("longarm"),
        }
    else shoulder.in_zone = false end

    chest.in_zone = false

    if CFG.knife_enabled and STOW.holster_zone_active(P, "knife") then
        -- Torso-anchored left chest: world hand vs HMD yaw-only torso world position.
        refresh_hmd_holster_zone(knife, "knife", P,
            P.knife_trigger_dist or hover, P.knife_release_dist or (hover + 0.10),
            hand_world or hand_pos, rj)
        holster_zones[#holster_zones + 1] = {
            slot = "knife", state = knife, cooldown = P.knife_cooldown,
            can_stow = STOW.can_stow_to_holster_zone("knife"),
            can_draw = slot_has_draw_candidate(P, "knife")
                and can_holster_interact_draw("knife"),
        }
    else
        knife.in_zone = false
    end
    end
    STOW.chris_resolve_hip_knife_overlap()

    if CFG.medicine_enabled and STOW.holster_zone_active(P, "medicine") then
        local med_blocked = medicine_blocked_by_lh_weapon_support()
        local med_can = STOW.medicine_can_grab()
        if med_blocked or not med_can then
            medicine.in_zone = false
            medicine.zone_enter_pulse = false
            medicine.haptic_pending_frames = 0
            medicine._med_can_prev = false
            STOW.resolve_knife_medicine_overlap(P)
        else
            refresh_hmd_holster_zone(medicine, "medicine", P,
                P.medicine_trigger_dist or hover, P.medicine_release_dist or (hover + 0.10),
                hand_world or hand_pos, rj)
            STOW.resolve_knife_medicine_overlap(P)
            if medicine.in_zone then
                STOW.maybe_zone_haptic(medicine, rj, "medicine")
            end
            holster_zones[#holster_zones + 1] = {
                slot = "medicine", state = medicine, cooldown = P.medicine_cooldown,
                can_stow = STOW.can_stow_to_holster_zone("medicine"),
                can_draw = (not med_blocked)
                    and (rawget(_G, "__re8_medicine_in_hand") ~= true)
                    and can_holster_interact_draw("medicine"),
            }
        end
    else
        medicine.in_zone = false
        medicine.zone_enter_pulse = false
        medicine.haptic_pending_frames = 0
        medicine._med_can_prev = false
        -- Medicine zone inactive, but knife may still sit on the bottle offset.
        STOW.resolve_knife_medicine_overlap(P)
    end
    HEAL.publish_zone_flag()
    if _on then _p.finish("holster.zones") end

    local in_weapon_holster_zone = hip.in_zone or shoulder.in_zone or knife.in_zone
    local was_in_weapon_holster_zone = GRIP.holster_zone_prev == true

    HOLSTER_CALIB.tick_quick_adjust(rj, hip, shoulder, knife, medicine)

    if in_weapon_holster_zone and not was_in_weapon_holster_zone then
        if grip_now and grip_was_held then
            GRIP.holster_prev = true
        else
            GRIP.holster_prev = false
        end
    end

    local closest = STOW.pick_closest_holster_zone(holster_zones, cur_id)
    local grab_ready = closest and closest.state.in_zone and grip_now
    -- Block holster grab while live-calibrating so RT-drag doesn't fight grip actions.
    local calibrating = HOLSTER_CALIB.target ~= nil
        or (HOLSTER_CALIB.hold_t0 and HOLSTER_CALIB.hold_t0 > 0)
    local grab_edge = grab_ready and not GRIP.holster_prev and not GRIP.suppress_haptics_for_aim
        and not calibrating and not FLY.active
    GRIP.holster_prev = grip_now
    local now = os.clock()

    if closest and grab_edge and not ammo_lock then
        if now - (closest.state.last_grab_t or -1) >= (closest.cooldown or 0.6) then
            closest.state.last_grab_t = now
            if rj then
                holster_haptic_pulse(rj, CFG.grab_haptic_duration, CFG.grab_haptic_frequency, CFG.grab_haptic_amplitude)
            end
            local grip_action = resolve_grip_holster_action(closest, cur_id)
            if grip_action == "draw" then
                if closest.slot == "medicine" then
                    -- Authorize Lua hold, fly mesh to hand; never native-equip MedicineCore.
                    HEAL.lua_authorized = true
                    HEAL.last_grab_t = os.clock()
                    HEAL._inject_lock_until = os.clock() + 0.85
                end
                local fly_ok = false
                if FLY.slot_ok(closest.slot) and CFG.holster_fly_enabled ~= false then
                    fly_ok = FLY.start("draw", closest.slot) == true
                end
                if fly_ok then
                    -- Equip deferred until fly finishes (medicine sets in_hand in FLY.finish).
                else
                    HOLSTER_ACTION.pending = { kind = "equip", slot = closest.slot }
                end
            elseif grip_action == "stow" then
                local stow_weapon = get_active_weapon_object() or re8vr.weapon
                if stow_weapon then
                    STOW.hide_orphan_visual(stow_weapon)
                    STOW.arm_flash(stow_weapon)
                end
                if FLY.slot_ok(closest.slot) and CFG.holster_fly_enabled ~= false
                    and FLY.start("stow", closest.slot) then
                    -- Unequip deferred until fly finishes.
                else
                    HOLSTER_ACTION.pending = { kind = "unequip", slot = closest.slot }
                    STOW.holster_unequip_id = cur_id or get_current_weapon_item_id() or ""
                    HOLSTER_ACTION.pending.expect_id = STOW.holster_unequip_id
                end
            end
        end
    end

    GRIP.holster_was_grip = grip_now
    GRIP.holster_zone_prev = in_weapon_holster_zone

    if _on then _p.begin("holster.heal") end
    HEAL.tick_use()
    if _on then _p.finish("holster.heal") end

    local wc_ok = COMPONENTS.weapon_change ~= nil
    local em_ok = COMPONENTS.equip_manager ~= nil
    local mc_ok = COMPONENTS.mesh_controller ~= nil

    STOW.sync_weapon_hold_suppress(hip.in_zone or shoulder.in_zone or chest.in_zone or knife.in_zone)
    apply_holster_vr_input_suppress()
    _pf()
end)

;(function()
-- Exit hysteresis: keep small so leaving the mesh drops in_zone quickly.
local RELEASE_MARGIN = 0.06

local function apply_profile_trigger(P, trigger_k, release_k, val)
    P[trigger_k] = val
    P[release_k] = math.max(val + RELEASE_MARGIN, val * 1.20)
end

local function draw_feature_enable_toggle(is_enabled, id, label)
    local changed, new_val = false, is_enabled
    if is_enabled then
        imgui.push_style_color(0, UI_ENABLE)
        if imgui.button("Enable##" .. id) then new_val = false; changed = true end
        imgui.pop_style_color(1)
    else
        imgui.push_style_color(0, UI_DISABLE)
        if imgui.button("Disable##" .. id) then new_val = true; changed = true end
        imgui.pop_style_color(1)
    end
    imgui.same_line()
    imgui.text(label)
    return changed, new_val
end

local function draw_holster_calibrate(cap_target, label)
    local trig_name = (cap_target == "ammo_left") and "LT" or "RT"
    if HOLSTER_CALIB.target == cap_target then
        if HOLSTER_CALIB.drag_waiting then
        imgui.text(string.format(
                ">>> %s armed — hold %s and drag, release to save", label, trig_name))
        else
            imgui.text(string.format(
                ">>> %s dragging live — move hand, release %s to save (%d updates)",
                label, trig_name, HOLSTER_CALIB.drag_updates or 0))
        end
        return
    end
    if HOLSTER_CALIB.hold_t0 and HOLSTER_CALIB.hold_t0 > 0 and HOLSTER_CALIB.hold_target == cap_target then
        local hold_need = tonumber(CFG.quick_calib_hold_s) or 3.0
        local left = math.max(0, hold_need - (os.clock() - HOLSTER_CALIB.hold_t0))
        imgui.text(string.format(
            ">>> Quick adjust %s: keep %s held %.1fs then drag (bare hands)",
            label, trig_name, left))
    end
    imgui.push_style_color(0, UI_BTN)
    if imgui.button(string.format("Calibrate %s (Hold+Drag)", label)) then
        HOLSTER_CALIB.start_capture(cap_target)
    end
    imgui.pop_style_color(1)
end

local function draw_holster_ui_block(id, label, enabled_key, cap_target, trigger_k, release_k, haptic_en_key, haptic_cont_key)
    local dirty = false
    local c, v = draw_feature_enable_toggle(CFG[enabled_key], "holster_" .. id, label)
    if c then CFG[enabled_key] = v; dirty = true end
    if not CFG[enabled_key] then return dirty end

    draw_holster_calibrate(cap_target, label)

    local P = get_profile()
    if id == "hip" or id == "knife" or id == "medicine" then
        local scale_k = "hip_pistol_grab_scale"
        if id == "knife" then scale_k = "knife_grab_scale"
        elseif id == "medicine" then scale_k = "medicine_grab_scale" end
        local cur = tonumber(P[scale_k]) or 1.10
        local sc, sv = imgui.slider_float(label .. " Grab Scale (x mesh)", cur, 0.70, 2.00, "%.2f")
        if sc then
            P[scale_k] = sv
            dirty = true
        end
        imgui.text("1.00 = mesh OBB; raise if grabs feel tight (mesh-only, no socket)")
    else
    local tdc, tdv = imgui.slider_float(label .. " Trigger Distance (m)", P[trigger_k], 0.10, 0.60, "%.2f")
    if tdc then
        apply_profile_trigger(P, trigger_k, release_k, tdv)
        dirty = true
        end
    end

    do
        local hi = 3
        if CFG[haptic_en_key] == false then hi = 1
        elseif CFG[haptic_cont_key] ~= true then hi = 2 end
        local hc, new_i = imgui.combo(label .. " Zone Haptics", hi, { "Off", "Tap (enter zone)", "Continuous" })
        if hc then
            if new_i == 1 then
                CFG[haptic_en_key] = false
                CFG[haptic_cont_key] = false
            elseif new_i == 2 then
                CFG[haptic_en_key] = true
                CFG[haptic_cont_key] = false
            else
                CFG[haptic_en_key] = true
                CFG[haptic_cont_key] = true
            end
            dirty = true
        end
    end

    if id == "ammo_left" then
        local gc, gv = imgui.checkbox("##holster_ammo_grab_haptic", CFG.ammo_grab_haptic_enabled ~= false)
        imgui.same_line()
        imgui.text("Grab haptic (pulse when mag grabs to hand)")
        if gc then CFG.ammo_grab_haptic_enabled = gv; dirty = true end
    end

    return dirty
end

-- 2026-10-29: the settings that matter, handed to the Visceral options window (visceral_re8_emporium.lua)
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
do
    local function holster_saved()
        rawset(_G, "__vr_lua_heal_override", CFG.medicine_enabled == true)
        if publish_holster_slot_enabled then publish_holster_slot_enabled() end
        if publish_holster_follow_cfg then publish_holster_follow_cfg() end
        save_cfg()
    end
    local function opt(order, key, label, help, default_on)
        table.insert(_G.VISCERAL_OPTIONS, { tab = "settings", order = order, kind = "check", label = label, help = help,
            get = function() if default_on then return CFG[key] ~= false end return CFG[key] == true end,
            set = function(v) CFG[key] = v == true; holster_saved() end })
    end
    opt(10, "enabled", "Holsters", "Guns and items kept on the body, taken with the grip.", false)
    opt(11, "hip_pistol_enabled", "    Hip holster", nil, true)
    opt(12, "shoulder_enabled", "    Shoulder holster", nil, true)
    opt(13, "knife_enabled", "    Left chest (knife)", nil, true)
    opt(14, "medicine_enabled", "    Right chest (healing)", nil, true)
    opt(15, "head_flashlight_enabled", "    Flashlight", nil, true)
    opt(16, "inventory_gesture_enabled", "    Inventory pocket", nil, true)
end

local function draw_holster_ui()
    if not imgui then return end
    if not imgui.tree_node("Holsters") then return end
    local dirty = false
    local function haptic_combo(label, id, en_key, cont_key)
        local hi = 3
        if CFG[en_key] == false then hi = 1
        elseif CFG[cont_key] ~= true then hi = 2 end
        local hc, new_i = imgui.combo(label .. "##holster_hap_" .. id, hi, { "Off", "Tap", "Continuous" })
        if hc then
            if new_i == 1 then
                CFG[en_key] = false
                CFG[cont_key] = false
            elseif new_i == 2 then
                CFG[en_key] = true
                CFG[cont_key] = false
            else
                CFG[en_key] = true
                CFG[cont_key] = true
            end
            return true
        end
        return false
    end
    local c, v = imgui.checkbox("Enable Holsters System##holster_master", CFG.enabled == true)
    if c then CFG.enabled = v; dirty = true end
    c, v = imgui.checkbox("Hip Holster##holster_hip", CFG.hip_pistol_enabled ~= false)
    if c then CFG.hip_pistol_enabled = v; dirty = true end
    if haptic_combo("Hip Holster Haptics", "hip", "hip_zone_haptic_enabled", "hip_zone_haptic_continuous") then dirty = true end
    if imgui.button("Reset to Default##holster_reset_hip") then PROF.reset_slot_offsets("hip") end
    c, v = imgui.checkbox("Shoulder Holster##holster_sh", CFG.shoulder_enabled ~= false)
    if c then CFG.shoulder_enabled = v; dirty = true end
    if haptic_combo("Shoulder Holster Haptics", "sh", "shoulder_zone_haptic_enabled", "shoulder_zone_haptic_continuous") then dirty = true end
    if imgui.button("Reset to Default##holster_reset_sh") then PROF.reset_slot_offsets("shoulder") end
    c, v = imgui.checkbox("Left Chest Holster##holster_knife", CFG.knife_enabled ~= false)
    if c then CFG.knife_enabled = v; dirty = true end
    if haptic_combo("Left Chest Haptics", "knife", "knife_zone_haptic_enabled", "knife_zone_haptic_continuous") then dirty = true end
    if imgui.button("Reset to Default##holster_reset_knife") then PROF.reset_slot_offsets("knife") end
    c, v = imgui.checkbox("Right Chest Holster##holster_med", CFG.medicine_enabled ~= false)
    if c then CFG.medicine_enabled = v; dirty = true end
    if haptic_combo("Right Chest Haptics", "med", "medicine_zone_haptic_enabled", "medicine_zone_haptic_continuous") then dirty = true end
    if imgui.button("Reset to Default##holster_reset_med") then PROF.reset_slot_offsets("medicine") end
    c, v = imgui.checkbox("Flashlight##holster_flash", CFG.head_flashlight_enabled ~= false)
    if c then CFG.head_flashlight_enabled = v; dirty = true end
    if haptic_combo("Flashlight Haptics", "flash", "head_flash_zone_haptic_enabled", "head_flash_zone_haptic_continuous") then dirty = true end
    if CFG.head_flashlight_enabled ~= false then
        local P = get_profile()
        local sc, sv
        sc, sv = imgui.slider_float("Beam Right (m)##holster_flash_br", tonumber(P.head_flash_beam_right) or 0, -2.00, 2.00, "%.3f")
        if sc then P.head_flash_beam_right = sv; dirty = true end
        sc, sv = imgui.slider_float("Beam Up (m)##holster_flash_bu", tonumber(P.head_flash_beam_up) or 0, -2.00, 2.00, "%.3f")
        if sc then P.head_flash_beam_up = sv; dirty = true end
        sc, sv = imgui.slider_float("Beam Forward (m)##holster_flash_bf", tonumber(P.head_flash_beam_forward) or 0, -2.00, 2.00, "%.3f")
        if sc then P.head_flash_beam_forward = sv; dirty = true end
        sc, sv = imgui.slider_float("Beam Yaw (deg)##holster_flash_yaw", tonumber(P.head_flash_beam_yaw) or 0, -360.0, 360.0, "%.1f")
        if sc then P.head_flash_beam_yaw = sv; dirty = true end
        sc, sv = imgui.slider_float("Beam Pitch (deg)##holster_flash_pitch", tonumber(P.head_flash_beam_pitch) or 0, -360.0, 360.0, "%.1f")
        if sc then P.head_flash_beam_pitch = sv; dirty = true end
        sc, sv = imgui.slider_float("Beam Roll (deg)##holster_flash_roll", tonumber(P.head_flash_beam_roll) or 0, -360.0, 360.0, "%.1f")
        if sc then P.head_flash_beam_roll = sv; dirty = true end
        imgui.push_style_color(0, UI_BTN)
        if imgui.button("Reset Beam Aim##holster_flash_reset") then
            P.head_flash_beam_right = 0
            P.head_flash_beam_up = 0
            P.head_flash_beam_forward = 0
            P.head_flash_beam_yaw = 0
            P.head_flash_beam_pitch = 0
            P.head_flash_beam_roll = 0
            dirty = true
        end
        imgui.pop_style_color(1)
    end
    c, v = imgui.checkbox("Inventory Pocket##holster_inv", CFG.inventory_gesture_enabled ~= false)
    if c then CFG.inventory_gesture_enabled = v; dirty = true end
    if dirty then
        rawset(_G, "__vr_lua_heal_override", CFG.medicine_enabled == true)
        if publish_holster_slot_enabled then publish_holster_slot_enabled() end
        if publish_holster_follow_cfg then publish_holster_follow_cfg() end
        save_cfg()
    end
    imgui.tree_pop()
end

_G.__vr_ui_callbacks = _G.__vr_ui_callbacks or {}
table.insert(_G.__vr_ui_callbacks, { order = 30, fn = draw_holster_ui })
end)()

if not _G.__vr_ui_master_installed then
    _G.__vr_ui_master_installed = true
    re.on_draw_ui(function()
        if not _G.__vr_ui_callbacks then return end
        table.sort(_G.__vr_ui_callbacks, function(a, b)
            return (a.order or 0) < (b.order or 0)
        end)
        for _, cb in ipairs(_G.__vr_ui_callbacks) do
            if cb.fn then pcall(cb.fn) end
        end
    end)
end

re.on_script_reset(function()
    HOLSTER_ACTION.shoot_until = 0
    HOLSTER_ACTION.pending = nil
    FLY.cancel("reset")
    GRIP.aim_prev = false
    GRIP.holster_was_grip = false
    GRIP.holster_ever_outside = false
    GRIP.holster_zone_prev = false
    GRIP.suppress_haptics_for_aim = false
    STOW.lockout_until = 0
    STOW.reassert_count = 0
    WEAPON_WATCH.stow_lockout_weapon_id = ""
    WEAPON_WATCH.stow_flash_weapon = nil
    WEAPON_WATCH.stow_flash_until = 0
    WEAPON_WATCH.draw_flash_weapon = nil
    WEAPON_WATCH.draw_flash_until = 0
    NATIVE_WEAPON_SEL.last_select_slot = nil
    NATIVE_WEAPON_SEL.last_quick_slot = nil
    NATIVE_WEAPON_SEL.last_applied_item = ""
    NATIVE_WEAPON_SEL.last_apply_t = 0
    WEAPON_WATCH.last_ptr = nil
    WEAPON_WATCH.last_id = ""
    WEAPON_WATCH.our_equip_until = 0
    WEAPON_WATCH.dpad_target_id = ""
    WEAPON_WATCH.dpad_old_ptr = nil
    WEAPON_WATCH.dpad_old_id = ""
    WEAPON_WATCH.dpad_cleanup_until = 0
    HOLSTER_GUARD.item_id = ""
    HOLSTER_GUARD.dpad_was_active = false
    HOLSTER_CALIB.clear_quick_hold()
    HOLSTER_CALIB.clear_drag()
    FLASH.clear()
    INV.clear()
    rawset(_G, "__vr_block_shoot_ready", false)
    STOW.clear_weapon_hold_suppress()
    rawset(_G, "__vr_in_medicine_zone", false)
end)

log.info("[re8_vr_holster] Loaded — config: " .. CFG_PATH)
rawset(_G, "__re8_holster_get_left_grip", function()
    return FLASH.get_left_grip()
end)
rawset(_G, "__re8_holster_get_right_grip", function()
    return get_right_grip_pressed()
end)
rawset(_G, "__re8_holster_get_right_trigger", function()
    return get_right_trigger_pressed()
end)
rawset(_G, "__re8_holster_get_right_joystick", function()
    return get_right_joystick()
end)
rawset(_G, "__re8_holster_get_left_hand_world", function()
    return HJ.get_left_hand_world()
end)
rawset(_G, "__re8_holster_get_left_hand_world_pose", function()
    return HJ.get_left_hand_world_pose()
end)
rawset(_G, "__re8_holster_collect_transforms", function()
    if HJ.collect_transforms then
        return HJ.collect_transforms()
    end
    return {}
end)
rawset(_G, "__re8_holster_find_joint_transform", function(names)
    if HJ.find_joint_transform then
        return HJ.find_joint_transform(names)
    end
    return nil, nil, nil
end)
rawset(_G, "__re8_holster_refresh_for_pose", function()
    refresh_components(true)
end)
rawset(_G, "__re8_holster_get_left_joystick", function()
    return FLASH.get_left_joystick()
end)
rawset(_G, "__re8_holster_lh_ctrl_idx", function()
    return FLASH.lh_ctrl_idx()
end)
rawset(_G, "__re8_holster_get_left_trigger", function()
    return HJ.get_left_trigger()
end)

if type(rawget(_G, "__re8_vr_overlay_bind")) ~= "table" then
    rawset(_G, "__re8_vr_overlay_bind", {})
end
rawget(_G, "__re8_vr_overlay_bind").holster = {
    push = function(api)
        api.set_bool("holster.enabled", CFG.enabled == true, false)
        api.set_bool("holster.hip", CFG.hip_pistol_enabled ~= false, false)
        api.set_bool("holster.shoulder", CFG.shoulder_enabled ~= false, false)
        api.set_bool("holster.knife", CFG.knife_enabled ~= false, false)
        api.set_bool("holster.medicine", CFG.medicine_enabled ~= false, false)
        api.set_bool("holster.flashlight", CFG.head_flashlight_enabled ~= false, false)
        api.set_bool("holster.inventory", CFG.inventory_gesture_enabled ~= false, false)
        do
            local function push_mode(store_key, en_key, cont_key)
                local mode = "continuous"
                if CFG[en_key] == false then mode = "off"
                elseif CFG[cont_key] ~= true then mode = "tap" end
                api.set_string(store_key, mode, false)
            end
            push_mode("holster.hip_haptic", "hip_zone_haptic_enabled", "hip_zone_haptic_continuous")
            push_mode("holster.shoulder_haptic", "shoulder_zone_haptic_enabled", "shoulder_zone_haptic_continuous")
            push_mode("holster.knife_haptic", "knife_zone_haptic_enabled", "knife_zone_haptic_continuous")
            push_mode("holster.medicine_haptic", "medicine_zone_haptic_enabled", "medicine_zone_haptic_continuous")
            push_mode("holster.flashlight_haptic", "head_flash_zone_haptic_enabled", "head_flash_zone_haptic_continuous")
            api.set_bool("holster.reset_hip", false, false)
            api.set_bool("holster.reset_shoulder", false, false)
            api.set_bool("holster.reset_knife", false, false)
            api.set_bool("holster.reset_medicine", false, false)
        end
    end,
    pull = function(api)
        CFG.enabled = api.get_bool("holster.enabled", CFG.enabled == true)
        CFG.hip_pistol_enabled = api.get_bool("holster.hip", CFG.hip_pistol_enabled ~= false)
        CFG.shoulder_enabled = api.get_bool("holster.shoulder", CFG.shoulder_enabled ~= false)
        CFG.knife_enabled = api.get_bool("holster.knife", CFG.knife_enabled ~= false)
        CFG.medicine_enabled = api.get_bool("holster.medicine", CFG.medicine_enabled ~= false)
        CFG.head_flashlight_enabled = api.get_bool("holster.flashlight", CFG.head_flashlight_enabled ~= false)
        CFG.inventory_gesture_enabled = api.get_bool("holster.inventory", CFG.inventory_gesture_enabled ~= false)
        do
            local function pull_mode(store_key, en_key, cont_key)
                local mode = api.get_string(store_key, "continuous")
                if mode == "off" then
                    CFG[en_key] = false
                    CFG[cont_key] = false
                elseif mode == "tap" then
                    CFG[en_key] = true
                    CFG[cont_key] = false
                else
                    CFG[en_key] = true
                    CFG[cont_key] = true
                end
            end
            pull_mode("holster.hip_haptic", "hip_zone_haptic_enabled", "hip_zone_haptic_continuous")
            pull_mode("holster.shoulder_haptic", "shoulder_zone_haptic_enabled", "shoulder_zone_haptic_continuous")
            pull_mode("holster.knife_haptic", "knife_zone_haptic_enabled", "knife_zone_haptic_continuous")
            pull_mode("holster.medicine_haptic", "medicine_zone_haptic_enabled", "medicine_zone_haptic_continuous")
            pull_mode("holster.flashlight_haptic", "head_flash_zone_haptic_enabled", "head_flash_zone_haptic_continuous")
            if api.get_bool("holster.reset_hip", false) then PROF.reset_slot_offsets("hip") end
            if api.get_bool("holster.reset_shoulder", false) then PROF.reset_slot_offsets("shoulder") end
            if api.get_bool("holster.reset_knife", false) then PROF.reset_slot_offsets("knife") end
            if api.get_bool("holster.reset_medicine", false) then PROF.reset_slot_offsets("medicine") end
        end
        rawset(_G, "__vr_lua_heal_override", CFG.medicine_enabled == true)
        publish_holster_slot_enabled()
        save_cfg()
    end,
}

return {}
