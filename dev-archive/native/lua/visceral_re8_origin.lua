-- visceral_re8_origin.lua -- the standing origin set by itself once gameplay starts (Tefa 2026-10-25: "the game starting low
-- down and only when i recenter view the 2d screen pops up to my eye level, but the gun handling is weird after that, guns
-- do not sit right in my hand").
-- REFramework takes the headset's position at launch as the standing origin (where the floor reference is); with the headset
-- on the desk or on a sitting head at launch, everything sits low. "Recenter View" lifts the picture but the body and the
-- hands are placed against the origin, so they disagree with the view afterwards. REFramework's own "Set Standing Origin"
-- button does set_standing_origin(get_position(0)) (src/mods/VR.cpp): the headset's position NOW becomes the reference, so
-- the view, the body and the hands agree again. This does that by itself ORIGIN_DELAY_S after the player is in gameplay
-- with the headset on, once per load, then recenters the view; and the Visceral RE8 reload menu has a button to do it again.

local TAG = "[visceral-re8-origin]"
local ORIGIN_DELAY_S = 3.0        -- seconds in gameplay before the origin is set (the headset is on by then)
local ON = true

local function L(s) log.info(TAG .. " " .. s) end
local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end

local done_for = nil     -- the player object the origin was set for (a new load gets a new one)
local since = nil
local last_hp, last_move = nil, nil   -- the headset's last position and when it last moved

local function set_now(why)
    local p = safe(function() return vrmod:get_position(0) end)
    if p == nil then L("standing origin NOT set (" .. why .. "): the headset's position could not be read") return false end
    local before = safe(function() return vrmod:get_standing_origin() end)
    local ok, err = pcall(function() vrmod:set_standing_origin(p) end)
    if not ok then L("standing origin NOT set (" .. why .. "): " .. tostring(err)) return false end
    pcall(function() vrmod:recenter_view() end)
    L(string.format("standing origin set (%s): headset at %.2f %.2f %.2f, origin was %s; view recentered", why, p.x, p.y, p.z,
        before and string.format("%.2f %.2f %.2f", before.x, before.y, before.z) or "?"))
    return true
end

-- 03:15 (Tefa: "automatic height fix did not work, can it somehow check the height as the very first thing before the game
-- starts?"): REFramework's recenter is yaw only, so what lifts the picture is the HEADSET's own recenter, which moves the
-- whole tracking space while REFramework keeps its old origin: the body then sits higher than the hands. Two more triggers:
-- the first frames the headset is active at all (title screens included), and any sudden jump of the headset's position
-- between two frames (a system recenter; a head never moves JUMP_M in one frame)
local JUMP_M = 0.25
local early_done = false
local prev_hp = nil
re.on_frame(function()
    if not ON then return end
    if not safe(function() return vrmod:is_hmd_active() end) then since = nil return end
    local hp0 = safe(function() return vrmod:get_position(0) end)
    if hp0 ~= nil then
        if prev_hp ~= nil and (hp0 - prev_hp):length() > JUMP_M then set_now(string.format("the headset jumped %.2f m in one frame: a system recenter", (hp0 - prev_hp):length())) end
        prev_hp = hp0
        if not early_done and safe(function() return vrmod:is_using_controllers() end) then early_done = true set_now("the headset first active") end
    end
    local v = rawget(_G, "re8vr")
    if v == nil then since = nil return end
    local player = safe(function() return v.player end)
    if player == nil or safe(function() return v.can_use_hands end) ~= true then since = nil return end
    if done_for == player then return end
    -- 02:43 (the first run: set while the headset lay on the desk, "player" being there before the title screen): it waits
    -- until the controllers are in use and the headset has MOVED (a head wears it; a desk does not), then ORIGIN_DELAY_S more
    if not safe(function() return vrmod:is_using_controllers() end) then since = nil return end
    local hp = safe(function() return vrmod:get_position(0) end)
    if hp == nil then return end
    local now = os.clock()
    if last_hp == nil or (hp - last_hp):length() > 0.02 then last_hp = hp; last_move = now end
    if last_move == nil or now - last_move > 2.0 then since = nil return end   -- still for 2 s: not worn (or not yet)
    since = since or now
    if now - since < ORIGIN_DELAY_S then return end
    done_for = player
    set_now("gameplay started, headset worn")
end)

-- 2026-10-29: the settings that matter, handed to the Visceral options window (visceral_re8_emporium.lua)
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
table.insert(_G.VISCERAL_OPTIONS, { tab = "settings", order = 40, kind = "button",
    label = "Set my standing height now", help = "Stand the way you play first: the view, body and hands go to eye level.",
    press = function() set_now("the Visceral options") end })

re.on_draw_ui(function()
    if imgui.tree_node("Visceral RE8 standing origin") then
        imgui.text("Set by itself " .. ORIGIN_DELAY_S .. " s after gameplay starts, once per load. Stand as you play, then:")
        if imgui.button("Set the standing origin now (view, body and hands to eye level)") then set_now("the menu button") end
        imgui.tree_pop()
    end
end)

L("loaded: the standing origin is set " .. ORIGIN_DELAY_S .. " s after gameplay starts, and from the menu")
