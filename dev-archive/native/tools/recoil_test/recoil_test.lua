-- recoil_test.lua -- runs Andyalpa's ORIGINAL re8_vr_recoil.lua (dev-archive/original-lua, read unchanged; only its
-- last line `return {}` is swapped for a table of its own local functions) through the same shot sequences as
-- recoil_test.cpp, with REFramework stubbed. Prints the same CSV. 2026-10-15.
--   lua recoil_test.lua <path to re8_vr_recoil.lua>

local path = arg[1]
local src = assert(io.open(path, "rb")):read("a")
local tail = "return {}"
local cut = src:find(tail, #src - 32, true)
assert(cut, "the file no longer ends with `return {}`")
src = src:sub(1, cut - 1) .. [[
return { apply = apply_recoil_kickback, update = update_recoil, eff = get_effective_recoil_offsets,
         cancel = cancel_recoil_state, fade = m_recoil_fadeout }
]]

-- ---- stubs ---------------------------------------------------------------------------------------------------------
local clock, frame, lgrip = 1.0, 0, false
os.clock = function() return clock end           -- uptime_now falls back to os.clock (no via.Application here)
math.random = function() return 0.5 end          -- randomness and spreads cancel at 0.5 (both sides)
local function vec(x, y, z) return { x = x, y = y, z = z } end
Vector3f = { new = vec }
Quaternion = { identity = function() return {} end }
log = { info = function() end, warn = function() end, error = function() end }
json = { load_file = function() return { randomness = 0.0 } end, dump_file = function() end }
re = { on_pre_application_entry = function() end, on_frame = function() end, on_draw_ui = function() end,
       get_frame_count = function() return frame end }
imgui = {}
sdk = { typeof = function() return nil end, find_type_definition = function() return nil end,
        get_native_singleton = function() return nil end, hook = function() end, PreHookResult = {} }
reframework = { get_game_name = function() return "re8" end }
vrmod = { is_hmd_active = function() return true end, is_using_controllers = function() return true end,
          get_action_grip = function() return "grip" end, get_left_joystick = function() return "lj" end,
          is_action_active = function(_, a, j) return lgrip and a == "grip" and j == "lj" end,
          get_controllers = function() return nil end }
local WEAPON_ID = ""
local owner = { call = function(_, m) if m == "get_Name" then return WEAPON_ID end end }
local WEAPON = { get_field = function(_, f) if f == "<owner>k__BackingField" then return owner end end,
                 call = function() return nil end, get_type_definition = function() return nil end }
re8vr = { can_use_hands = true, is_reloading = false, was_gripping_weapon = false,
          get_weapon_object = function() return WEAPON end }
package.preload["utility/RE8"] = function() return { get_localplayer = function() return {} end } end

local R = assert(load(src, "=re8_vr_recoil.lua"))()

local function run(name, weapon_id, two, shots, frames, dt)
    WEAPON_ID, lgrip, clock = weapon_id, two, clock + 10.0
    R.cancel(nil, "test")
    local shot_at = {}
    for _, f in ipairs(shots) do shot_at[f] = true end
    for f = 0, frames - 1 do
        frame = frame + 1
        if shot_at[f] then R.apply(WEAPON) end
        R.update(dt)
        local p, y, a, b = R.eff()
        print(string.format("%s,%d,%.9g,%.9g,%.9g,%.9g,%d", name, f, p, y, a, b, R.fade.active and 1 or 0))
        clock = clock + dt
    end
end

run("handgun_one_hand", "ri3040_Inventory", false, { 0 }, 120, 1.0 / 90.0)
run("shotgun_two_hands", "ri3021_Inventory", true, { 0 }, 120, 1.0 / 90.0)
run("auto_rifle_burst", "ri3049_Inventory", true, { 0, 6, 12, 18 }, 150, 1.0 / 90.0)
run("magnum_one_hand_60hz", "ri3008", false, { 0 }, 90, 1.0 / 60.0)
