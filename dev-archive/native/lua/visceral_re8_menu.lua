-- visceral_re8_menu.lua -- the settings of the ported Hands Off files: their menus, their saved files, and the numbers
-- they send to the plugin through the bridge (2026-10-15).
--
-- Each ported file keeps Andyalpa's saved file (same path, same keys), so settings made with the Lua pack carry over.
-- So far: haptics (re8_vr/re8_vr_haptics.json, menu "Weapon Shooting Haptics", src/haptics.cpp).
-- Slot numbers must match src/bridge.h.

local TAG = "[visceral-re8-menu]"

-- haptics ------------------------------------------------------------------------------------------------------------
local S_HAP_SENT, S_HAP_ON, S_HAP_GATE_LEFT, S_HAP_SCALE, S_HAP_AUTO_PULSE = 48, 49, 50, 51, 52
local S_HAP_ON_S, S_HAP_OFF_S, S_HAP_MAX_DUR = 53, 54, 55

local HAP_PATH = "re8_vr/re8_vr_haptics.json"
local INTENSITY = { low = 0.45, medium = 0.80, high = 1.20 }
local HAP = {
    enabled = true,
    gate_left_shoot = true,
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

log.info(TAG .. " loaded: haptics settings")
