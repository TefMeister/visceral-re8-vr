-- visceral_re8_menu.lua -- the settings of the ported Hands Off files: their menus, their saved files, and the numbers
-- they send to the plugin through the bridge (2026-10-15).
--
-- Each ported file keeps Andyalpa's saved file (same path, same keys), so settings made with the Lua pack carry over.
-- So far: haptics (re8_vr/re8_vr_haptics.json, menu "Weapon Shooting Haptics", src/haptics.cpp) and recoil
-- (re8_vr/re8_vr_recoil.json, menu "Weapon Recoil", src/recoil.cpp, which reads the file itself), and the ammo HUD
-- (re8_vr/re8_vr_ammo_hud.json, menu "Ammo HUD", src/ammo_hud.cpp, which reads the file itself; 2026-10-19).
-- Slot numbers must match src/bridge.h.

local TAG = "[visceral-re8-menu]"

-- haptics ------------------------------------------------------------------------------------------------------------
local S_HAP_SENT, S_HAP_ON, S_HAP_GATE_LEFT, S_HAP_SCALE, S_HAP_AUTO_PULSE = 48, 49, 50, 51, 52
local S_HAP_ON_S, S_HAP_OFF_S, S_HAP_MAX_DUR = 53, 54, 55
local S_AUTO_EXPOSURE_ON = 174   -- 2026-10-29: 1 = the game keeps its own automatic brightness (src/bridge.h, exposure.cpp)
local exposure = {game_auto = false}   -- never saved: every game starts with the game's automatic brightness OFF (steady light)

local HAP_PATH = "re8_vr/re8_vr_haptics.json"
local INTENSITY = { low = 0.45, medium = 0.80, high = 1.20 }
local HAP = {
    enabled = true,
    gate_left_shoot = false,   -- 2026-10-31 (Tefa): shots rumble both controllers, one-handed too
    intensity = "medium",
    auto_pulse = true,
    auto_pulse_on_s = 0.018,
    auto_pulse_off_s = 0.070,
    auto_pulse_max_dur = 0.018,
}

local function hap_save()
    pcall(function()
        json.dump_file(HAP_PATH, {
            enabled = HAP.enabled == true,
            gate_left_shoot = HAP.gate_left_shoot == true,
            intensity = HAP.intensity,
            auto_pulse = HAP.auto_pulse == true,
            auto_pulse_on_s = HAP.auto_pulse_on_s,
            auto_pulse_off_s = HAP.auto_pulse_off_s,
            auto_pulse_max_dur = HAP.auto_pulse_max_dur,
        })
    end)
end

-- re8_vr_haptics.lua load_cfg, including its migration of old overlapping pulse timings
local function hap_load()
    local data = nil
    pcall(function() data = json.load_file(HAP_PATH) end)
    if type(data) ~= "table" then return end
    if data.enabled ~= nil then HAP.enabled = data.enabled == true end
    if data.gate_left_shoot ~= nil then HAP.gate_left_shoot = data.gate_left_shoot == true end
    if type(data.intensity) == "string" and INTENSITY[data.intensity] ~= nil then HAP.intensity = data.intensity end
    if data.auto_pulse ~= nil then HAP.auto_pulse = data.auto_pulse == true end
    if type(data.auto_pulse_on_s) == "number" then HAP.auto_pulse_on_s = data.auto_pulse_on_s end
    if type(data.auto_pulse_off_s) == "number" then HAP.auto_pulse_off_s = data.auto_pulse_off_s end
    if type(data.auto_pulse_max_dur) == "number" then HAP.auto_pulse_max_dur = data.auto_pulse_max_dur end
    if (tonumber(HAP.auto_pulse_max_dur) or 0) >= 0.035 then HAP.auto_pulse_max_dur = 0.018 end
    if (tonumber(HAP.auto_pulse_off_s) or 0) < 0.050 then HAP.auto_pulse_off_s = 0.070 end
    if (tonumber(HAP.auto_pulse_on_s) or 0) > 0.025 then HAP.auto_pulse_on_s = 0.018 end
end

hap_load()

local function hap_send(b)
    b.w(S_HAP_ON, HAP.enabled and 1 or 0)
    b.w(S_HAP_GATE_LEFT, HAP.gate_left_shoot and 1 or 0)
    b.w(S_HAP_SCALE, INTENSITY[HAP.intensity] or INTENSITY.medium)
    b.w(S_HAP_AUTO_PULSE, HAP.auto_pulse and 1 or 0)
    b.w(S_HAP_ON_S, tonumber(HAP.auto_pulse_on_s) or 0.018)
    b.w(S_HAP_OFF_S, tonumber(HAP.auto_pulse_off_s) or 0.070)
    b.w(S_HAP_MAX_DUR, tonumber(HAP.auto_pulse_max_dur) or 0.018)
    b.w(S_HAP_SENT, 1)
end

-- the in-headset overlay's hook-up, as re8_vr_haptics.lua left it
if type(rawget(_G, "__re8_vr_overlay_bind")) ~= "table" then rawset(_G, "__re8_vr_overlay_bind", {}) end
rawget(_G, "__re8_vr_overlay_bind").haptics = {
    push = function(api) api.set_bool("haptics.enabled", HAP.enabled == true, false) end,
    pull = function(api)
        HAP.enabled = api.get_bool("haptics.enabled", HAP.enabled == true)
        hap_save()
    end,
}

-- sending ------------------------------------------------------------------------------------------------------------
re.on_pre_application_entry("UpdateBehavior", function()   -- after the bridge's UpdateHID pass, before the plugin's frame
    local b = rawget(_G, "visceral_re8_bridge")
    if not b or not b.ready() then return end
    hap_send(b)
    b.w(S_AUTO_EXPOSURE_ON, exposure.game_auto and 1 or 0)
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Weapon Shooting Haptics##re8_vr_hap") then return end
    local ce, ve = imgui.checkbox("Enabled##re8_vr_hap_en", HAP.enabled == true)
    if ce then
        HAP.enabled = ve == true
        hap_save()
    end
    imgui.tree_pop()
end)

-- recoil -------------------------------------------------------------------------------------------------------------
-- src/recoil.cpp reads re8_vr/re8_vr_recoil.json itself whenever it changes; this part keeps re8_vr_recoil.lua's
-- menu, its first-run defaults and its saving, word for word (2026-10-15). The catalog below must stay in step with
-- recoil.cpp's CATALOG_TYPE (names live only here, for the menu).
local function safe_call(fn) local ok, v = pcall(fn); if ok then return v end; return nil end
local REC_PATH = "re8_vr/re8_vr_recoil.json"
local REC_TYPE_INTENSITY = { handgun = 1.22, revolver = 1.38, smg = 1.75, rifle = 1.48, shotgun = 2.55, magnum = 2.90,
    launcher = 2.45, flamethrower = 1.52, electric = 1.68, rpg = 3.90, minigun = 3.20 }
local REC_NO_RECOIL = { ri3022_Inventory = true, ri3044_Inventory = true }
local REC_AUTO = { ri3049_Inventory = true, ri3125_Inventory = true, ri3129_Inventory = true }
local REC_CATALOG = {
    ri3008_Inventory = { "M1851 Wolfsbane", "magnum" }, ri3021_Inventory = { "W870 TAC", "shotgun" },
    ri3023_Inventory = { "GM 79", "launcher" }, ri3036_Inventory = { "M1897", "shotgun" },
    ri3040_Inventory = { "M1911", "handgun" }, ri3042_Inventory = { "F2 Rifle", "rifle" },
    ri3046_Inventory = { "LEMI", "handgun" }, ri3047_Inventory = { "V61 Custom", "handgun" },
    ri3048_Inventory = { "SYG-12", "shotgun" }, ri3049_Inventory = { "WCX", "rifle" },
    ri3050_Inventory = { "S.T.A.K.E", "magnum" }, ri3115_Inventory = { "Rocket Pistol", "handgun" },
    ri3116_Inventory = { "Handcannon PZ", "magnum" }, ri3122_Inventory = { "Samurai Edge - AW Model-01", "handgun" },
    ri3124_Inventory = { "USM-AI", "handgun" }, ri3125_Inventory = { "Dragoon", "rifle" },
    ri3135_Inventory = { "LEMI - Shadows of Rose", "handgun" }, ri3147_Inventory = { "M1897 - Shadows of Rose", "shotgun" },
    ri3081_Inventory = { "LEMI - Mercenaries", "handgun" }, ri3082_Inventory = { "M1911 - Mercenaries", "handgun" },
    ri3083_Inventory = { "V61 Custom - Mercenaries", "handgun" }, ri3084_Inventory = { "M1897 - Mercenaries", "shotgun" },
    ri3085_Inventory = { "W870 TAC - Mercenaries", "shotgun" }, ri3086_Inventory = { "SYG-12 - Mercenaries", "shotgun" },
    ri3087_Inventory = { "F2 Rifle - Mercenaries", "rifle" }, ri3129_Inventory = { "Dragoon - Mercenaries", "rifle" },
    ri3130_Inventory = { "USM-AI - Mercenaries", "handgun" },
}
local REC = {   -- re8_vr_recoil.lua CFG, Andyalpa's defaults
    enabled = true, use_native_recoil = false, suppress_native_recoil = false, suppress_camera_recoil = false,
    intensity = 2.0, attack_duration = 0.005, spring_stiffness = 50.0, spring_damping = 5.0, sustained_damping = 10.0,
    spring_settle_mult = 4.5, sustained_window = 0.125, substep_dt = 0.008, position_intensity = 0.006,
    position_up_ratio = 1.0, position_back_ratio = 0.0, rotation_intensity = 0.01, wrist_pitch_sign = -1.0,
    yaw_intensity = 0.171, wrist_yaw_sign = 1.0, apply_yaw_rotation = true, horizontal_spread = 0.0,
    vertical_spread = 0.0, randomness = 0.347, mult_exponent = 0.1, stack_cap = 2.0, auto_scale = 0.25,
    two_hand_scale = 0.55, one_hand_light = 1.18, one_hand_heavy = 1.90, weapons = {},
}

local function rec_known(id) return REC_CATALOG[id] ~= nil or REC_NO_RECOIL[id] or REC_AUTO[id] end
local function rec_canonical(id)
    if type(id) ~= "string" or id == "" then return "" end
    if rec_known(id) then return id end
    if rec_known(id .. "_Inventory") then return id .. "_Inventory" end
    return id
end
local function rec_clamp(v) v = tonumber(v) or 1.0; return math.max(1.0, math.min(4.0, v)) end
local function rec_type(id, weapon)
    local c = REC_CATALOG[rec_canonical(id)]
    if c then return c[2] end
    if weapon ~= nil then
        if safe_call(function() return weapon:call("isShortWeapon") end) == true then return "handgun" end
        if safe_call(function() return weapon:call("isLongWeapon") end) == true then return "rifle" end
    end
    return nil
end
local function rec_supported(id, weapon)
    id = rec_canonical(id)
    if id == "" or REC_NO_RECOIL[id] then return false end
    local t = rec_type(id, weapon)
    return t ~= nil and REC_TYPE_INTENSITY[t] ~= nil
end
local function rec_default(id)
    id = rec_canonical(id)
    if not rec_supported(id) then return nil end
    local t = rec_type(id)
    local e = { intensity = REC_TYPE_INTENSITY[t], type = t }
    if REC_CATALOG[id] then e.name = REC_CATALOG[id][1] end
    return e
end
local function rec_normalize(id, entry)   -- normalize_weapon_entry
    id = rec_canonical(id)
    if not rec_supported(id) then return nil end
    if type(entry) ~= "table" then return rec_default(id) end
    if entry.type == "utility" then return nil end
    local v = tonumber(entry.intensity)
    if v == nil then return rec_default(id) end
    local out = { intensity = rec_clamp(v), type = type(entry.type) == "string" and entry.type or rec_type(id) }
    if type(entry.name) == "string" and entry.name ~= "" then out.name = entry.name
    elseif REC_CATALOG[id] then out.name = REC_CATALOG[id][1] end
    return out
end
local function rec_save() pcall(function() json.dump_file(REC_PATH, REC) end) end
local function rec_load()   -- load_cfg_from_disk, then ensure_cfg_weapon_defaults (the Lua's first-run bootstrap)
    local data = nil
    pcall(function() data = json.load_file(REC_PATH) end)
    if type(data) == "table" then
        for k, v in pairs(data) do
            if k == "weapons" then
                if type(v) == "table" then
                    REC.weapons = {}
                    for id, entry in pairs(v) do
                        local n = rec_normalize(id, entry)
                        if n ~= nil then REC.weapons[rec_canonical(id)] = n end
                    end
                end
            elseif REC[k] ~= nil and type(v) == type(REC[k]) then
                REC[k] = v
            end
        end
    end
    local changed = false
    for id, _ in pairs(REC.weapons) do if not rec_supported(id) then REC.weapons[id] = nil; changed = true end end
    for id, _ in pairs(REC_CATALOG) do
        if REC.weapons[id] == nil then
            local e = rec_default(id)
            if e then REC.weapons[id] = e; changed = true end
        end
    end
    if changed then rec_save() end
end

-- the equipped weapon's recoil id: re8_vr_recoil.lua get_weapon_recoil_id on re8vr.weapon
local function rec_weapon_id(weapon)
    if weapon == nil then return "" end
    local owner = safe_call(function() return weapon:get_field("<owner>k__BackingField") end)
        or safe_call(function() return weapon:call("get_owner") end)
    local n = owner and safe_call(function() return owner:call("get_Name") end)
    if type(n) == "string" and n ~= "" then return rec_canonical(n) end
    local go = safe_call(function() return weapon:call("get_GameObject") end)
    n = go and safe_call(function() return go:call("get_Name") end)
    if type(n) == "string" and n ~= "" then return rec_canonical(n) end
    n = safe_call(function() return weapon:call("get_weaponName") end)
    if type(n) == "string" and n ~= "" then return rec_canonical(n) end
    local td = safe_call(function() return weapon:get_type_definition() end)
    n = td and safe_call(function() return td:get_full_name() end)
    return type(n) == "string" and rec_canonical(n) or ""
end
local function rec_equipped()
    local re8vr = rawget(_G, "re8vr")
    local weapon = re8vr and re8vr.weapon
    local id = rec_weapon_id(weapon)
    if weapon == nil or not rec_supported(id, weapon) then return nil end
    return id, weapon
end
local function rec_intensity(id, weapon)
    if not rec_supported(id, weapon) then return 0.0 end
    local e = REC.weapons[id]
    if e == nil then e = rec_default(id) end
    return e and rec_clamp(e.intensity) or 1.0
end
local function rec_set(id, v)   -- set_per_weapon_intensity
    if id == "" or not rec_supported(id) then return end
    local e = type(REC.weapons[id]) == "table" and REC.weapons[id] or rec_default(id)
    if e == nil then return end
    e.intensity = rec_clamp(v)
    REC.weapons[id] = e
end
local function rec_label(id)
    local e = REC.weapons[id]
    if type(e) == "table" and type(e.name) == "string" and e.name ~= "" then return e.name end
    return REC_CATALOG[id] and REC_CATALOG[id][1] or id
end

rec_load()

-- 2026-10-29: the settings that matter, handed to the Visceral options window (visceral_re8_emporium.lua)
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 40, kind = "check", label = "Gun shaking the controller",
    help = "A buzz in the hand with every shot.",
    get = function() return HAP.enabled == true end, set = function(v) HAP.enabled = v == true; hap_save() end })
table.insert(_G.VISCERAL_OPTIONS, { tab = "graphics", order = 30, kind = "check", label = "Let the game adjust the brightness by itself",
    help = "Village: the plugin's steady-light switch is OFF until the right lever is found (2026-10-29: the RE2 way gave a golden veil). NUM7 tries it; this tick forces the game's own.",
    get = function() return exposure.game_auto end,
    set = function(v) exposure.game_auto = v == true; log.info(TAG .. (exposure.game_auto and " automatic brightness: the game's own" or " automatic brightness: OFF (steady)")) end })
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 50, kind = "check", label = "Recoil",
    get = function() return REC.enabled == true end, set = function(v) REC.enabled = v == true; rec_save() end })
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 51, kind = "slider", label = "Recoil strength",
    min = 0.0, max = 3.0, fmt = "%.2f",
    get = function() return tonumber(REC.intensity) or 2.0 end, set = function(v) REC.intensity = v; rec_save() end })
local function draw_recoil_ui()   -- re8_vr_recoil.lua draw_recoil_ui, same labels and ids
    if not imgui.tree_node("Weapon Recoil") then return end
    local dirty = false
    local c, v = imgui.checkbox("Enable Recoil System##recoil_en", REC.enabled == true)
    if c then REC.enabled = v; dirty = true end
    c, v = imgui.slider_float("Global Recoil Intensity##recoil_g", tonumber(REC.intensity) or 2.0, 0.0, 3.0, "%.2f")
    if c then REC.intensity = v; dirty = true end
    local id, weapon = rec_equipped()
    if id then
        local label = rec_label(id)
        if label == "" then label = "Equipped" end
        c, v = imgui.slider_float("Equipped (" .. label .. ")##recoil_eq", rec_intensity(id, weapon), 1.0, 4.0, "%.2f")
        if c then rec_set(id, v); dirty = true end
    else
        imgui.text("Equipped Recoil: N/A")
    end
    if dirty then rec_save() end
    imgui.tree_pop()
end
-- the pack's shared menu list (order 42, as before) and its one drawer, installed by whichever file runs first
_G.__vr_ui_callbacks = _G.__vr_ui_callbacks or {}
table.insert(_G.__vr_ui_callbacks, { order = 42, fn = draw_recoil_ui })
if not _G.__vr_ui_master_installed then
    _G.__vr_ui_master_installed = true
    re.on_draw_ui(function()
        if not _G.__vr_ui_callbacks then return end
        table.sort(_G.__vr_ui_callbacks, function(a, b) return (a.order or 0) < (b.order or 0) end)
        for _, cb in ipairs(_G.__vr_ui_callbacks) do if cb.fn then pcall(cb.fn) end end
    end)
end
-- the in-headset overlay's hook-up, as re8_vr_recoil.lua left it
rawget(_G, "__re8_vr_overlay_bind").recoil = {
    push = function(api)
        api.set_bool("recoil.enabled", REC.enabled == true, false)
        api.set_float("recoil.global", tonumber(REC.intensity) or 2.0, 0.0, 3.0, false)
        local id, weapon = rec_equipped()
        local label, intensity = "No weapon", 1.22
        if id then
            label = rec_label(id)
            if label == "" then label = "Equipped" end
            intensity = rec_intensity(id, weapon)
        end
        api.set_bool("recoil.equipped_ok", id ~= nil, false)
        api.set_string("recoil.equipped_label", label, false)
        api.set_float("recoil.equipped", intensity, 1.0, 4.0, false)
    end,
    pull = function(api)
        REC.enabled = api.get_bool("recoil.enabled", REC.enabled == true)
        REC.intensity = api.get_float("recoil.global", tonumber(REC.intensity) or 2.0)
        if api.get_bool("recoil.equipped_ok", false) then
            local id = rec_equipped()
            if id then rec_set(id, api.get_float("recoil.equipped", 1.22)) end
        end
        rec_save()
    end,
}

-- ammo HUD -----------------------------------------------------------------------------------------------------------
-- src/ammo_hud.cpp reads re8_vr/re8_vr_ammo_hud.json itself whenever it changes; this is re8_vr_ammo_hud.lua's menu
-- (same labels, ids and keys). Its buttons go to the plugin as a numbered command; the plugin sends its status back.
local S_HUD_CMD, S_HUD_CMD_SEQ, S_HUD_STATUS = 90, 91, 92
local HUD_PATH = "re8_vr/re8_vr_ammo_hud.json"
local HUD = {   -- re8_vr_ammo_hud.lua CFG, Andyalpa's defaults
    display = "weapon", mode = "manual", keep_open = true, force_open_interval_s = 2.0, set_world_view = true,
    off_right = 0.04, off_up = -0.02, off_forward = 0.08, rot_yaw = 0.0, rot_pitch = 0.0, rot_roll = 0.0,
    scale = 0.55, poll_s = 0.35,
}
local HUD_STATUS = { "init", "ready", "partial", "no_gui_manager", "no_remain_ammo", "recover_pending", "menu_yield",
                     "off", "melee_hide", "weapon", "default" }
local hud_seq = 0

local function hud_save() pcall(function() json.dump_file(HUD_PATH, HUD) end) end
local function hud_load()   -- load_cfg: keys of the right type, the old enabled / attach switches, then saved back
    local data = nil
    pcall(function() data = json.load_file(HUD_PATH) end)
    if type(data) ~= "table" then hud_save(); return end
    for k, v in pairs(data) do
        if HUD[k] ~= nil and type(v) == type(HUD[k]) then HUD[k] = v end
    end
    HUD.mode = "manual"
    if type(data.display) ~= "string" then
        HUD.display = (data.enabled == false or data.attach == false) and "default" or "weapon"
    elseif data.display ~= "default" and data.display ~= "weapon" and data.display ~= "off" then
        HUD.display = "weapon"
    end
    hud_save()
end
hud_load()

local function hud_cmd(code)
    local b = rawget(_G, "visceral_re8_bridge")
    if not b or not b.ready() then return end
    hud_seq = hud_seq + 1
    b.w(S_HUD_CMD, code)
    b.w(S_HUD_CMD_SEQ, hud_seq)
end
local function hud_snap()   -- apply_rh_near_preset
    HUD.off_right, HUD.off_up, HUD.off_forward = 0.02, 0.04, 0.06
    HUD.rot_yaw, HUD.rot_pitch, HUD.rot_roll = 0.0, 0.0, 0.0
    HUD.scale, HUD.display, HUD.keep_open, HUD.set_world_view = 0.55, "weapon", true, true
    hud_save()
    hud_cmd(1)
end

re.on_draw_ui(function()
    if not imgui.tree_node("Ammo HUD") then return end
    local labels, map = { "Default", "On Weapon", "Off" }, { "default", "weapon", "off" }
    local cur = HUD.display == "weapon" and 2 or HUD.display == "off" and 3 or 1
    local c, idx = imgui.combo("Ammo HUD Display##ammo_hud_disp", cur, labels)
    if c and map[idx] then HUD.display = map[idx]; hud_save() end
    imgui.text("default = game | weapon = RH attach | off = hidden")
    local b = rawget(_G, "visceral_re8_bridge")
    if b and b.ready() then
        imgui.text("Status: " .. (HUD_STATUS[math.floor(b.r(S_HUD_STATUS) + 0.5) + 1] or "?") .. "  (" .. HUD.display .. ")")
    end
    if HUD.display == "weapon" then
        imgui.spacing()
        if imgui.button("Snap near right hand##ammo_hud_snap") then hud_snap() end
        imgui.text("Snap = small offsets, scale 0.55, rot 0 (visible start)")
        imgui.spacing()
        local ch, v = imgui.checkbox("Keep HUD open##ammo_hud_keep", HUD.keep_open == true)
        if ch then HUD.keep_open = v; hud_save() end
        ch, v = imgui.checkbox("Force World ViewType##ammo_hud_world", HUD.set_world_view == true)
        if ch then HUD.set_world_view = v; hud_save() end
        imgui.spacing()
        local function slider(label, key, lo, hi, fmt)
            local sc, sv = imgui.slider_float(label, tonumber(HUD[key]) or 0.0, lo, hi, fmt)
            if sc then HUD[key] = sv; hud_save() end
        end
        slider("Offset Right (m)##ammo_hud_or", "off_right", -2.0, 2.0, "%.3f")
        slider("Offset Up (m)##ammo_hud_ou", "off_up", -2.0, 2.0, "%.3f")
        slider("Offset Forward (m)##ammo_hud_of", "off_forward", -2.0, 2.0, "%.3f")
        slider("Rot Yaw (deg)##ammo_hud_yaw", "rot_yaw", -360.0, 360.0, "%.1f")
        slider("Rot Pitch (deg)##ammo_hud_pitch", "rot_pitch", -360.0, 360.0, "%.1f")
        slider("Rot Roll (deg)##ammo_hud_roll", "rot_roll", -360.0, 360.0, "%.1f")
        slider("Scale##ammo_hud_scale", "scale", 0.001, 5.0, "%.3f")
        imgui.text("Tip: start near Snap preset; huge Scale can fling UI off-screen")
        imgui.spacing()
        if imgui.button("Open HUD now##ammo_hud_open") then hud_cmd(1) end
        imgui.same_line()
        if imgui.button("Recover after menu##ammo_hud_rec") then hud_cmd(2) end
        imgui.same_line()
        if imgui.button("Reset offsets##ammo_hud_reset") then hud_snap() end
    end
    imgui.spacing()
    if imgui.button("Re-resolve##ammo_hud_res") then hud_cmd(3) end
    imgui.tree_pop()
end)

re.on_config_save(function() hud_save() end)

rawget(_G, "__re8_vr_overlay_bind").ammo_hud = {   -- as re8_vr_ammo_hud.lua left it
    push = function(api) api.set_string("ammo_hud.display", HUD.display, false) end,
    pull = function(api)
        local d = api.get_string("ammo_hud.display", HUD.display)
        if d == "default" or d == "weapon" or d == "off" then HUD.display = d end
        hud_save()
    end,
}

log.info(TAG .. " loaded: haptics + recoil + ammo HUD settings")

-- 2026-10-29: the ammo counter's place, in the Visceral options window (visceral_re8_emporium.lua)
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
do
    local map = { "default", "weapon", "off" }
    table.insert(_G.VISCERAL_OPTIONS, { tab = "graphics", order = 20, kind = "choice", label = "Ammo counter",
        choices = { "Where the game puts it", "On the gun", "Off" },
        get = function() return HUD.display == "weapon" and 2 or HUD.display == "off" and 3 or 1 end,
        set = function(i) if map[i] then HUD.display = map[i]; hud_save() end end })
end
