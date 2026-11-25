-- visceral_re8_origin.lua -- rebuild 2 (2026-11-26): the standing height right from the start (design item 11).
--
-- Tefa (2026-11-26, the bare base): "ethan's hands now sit lower than they should be, that got fixed in our old
-- build, with the menus that start too low and need a meta button recenter".
--
-- Why it happens (read from REFramework's src/mods/VR.cpp and measured on b178, 2026-10-25): REFramework takes the
-- headset's position at launch as the standing origin. With the headset on a desk or a sitting head at launch,
-- everything sits low. The headset's own recenter lifts the picture but REFramework keeps its old origin, so the
-- body and the hands then disagree with the view. REFramework's "Set Standing Origin" does
-- set_standing_origin(get_position(0)); this does the same by itself.
--
-- Written fresh for rebuild 2 with the b178 file (dev-archive/native/lua/visceral_re8_origin.lua) as the reference:
-- the three moments are the same, the menu and the options-window parts are not carried over yet.
--   1. the first frame the headset is active with the controllers in use (title screens included);
--   2. the headset's position jumping JUMP_M in one frame (a system recenter: a head never does that);
--   3. once per player object, SETTLE_S after gameplay starts with the headset worn (it has moved in the last 2 s).
--
-- Rule set (design 2026-11-25d section 5): no joint, no object, no request, no hook. It calls REFramework's own VR
-- functions only. Stays Lua: the calls it needs are on REFramework's Lua "vrmod", not in the plugin API.

local TAG = "[visceral-re8-origin]"
local SETTLE_S = 3.0          -- seconds of worn gameplay before the per-load set
local WORN_MOVE_M = 0.02      -- the headset moved this much: a head wears it
local WORN_WINDOW_S = 2.0     -- ... within this long
local JUMP_M = 0.25           -- one-frame jump that can only be a system recenter

if reframework:get_game_name() ~= "re8" then return end

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end

local function set_now(why)
    local p = safe(function() return vrmod:get_position(0) end)
    if p == nil then
        log.info(TAG .. " NOT set (" .. why .. "): the headset's position could not be read")
        return
    end
    local ok = pcall(function() vrmod:set_standing_origin(p) end)
    if not ok then
        log.info(TAG .. " NOT set (" .. why .. "): set_standing_origin failed")
        return
    end
    pcall(function() vrmod:recenter_view() end)
    log.info(string.format("%s set (%s): headset at %.2f %.2f %.2f; view recentered", TAG, why, p.x, p.y, p.z))
end

local first_done = false
local prev_pos = nil
local done_for = nil            -- the player object the per-load set was made for
local last_pos, last_move = nil, nil
local since = nil

re.on_frame(function()
    if not safe(function() return vrmod:is_hmd_active() end) then since = nil return end
    local pos = safe(function() return vrmod:get_position(0) end)
    if pos == nil then return end
    local using = safe(function() return vrmod:is_using_controllers() end)

    if prev_pos ~= nil then
        local jump = (pos - prev_pos):length()
        if jump > JUMP_M then set_now(string.format("the headset jumped %.2f m in one frame", jump)) end
    end
    prev_pos = pos

    if not first_done and using then
        first_done = true
        set_now("the headset first active")
    end

    local player = re8vr and re8vr.player
    if player == nil or not using or re8vr.can_use_hands ~= true then since = nil return end
    if done_for == player then return end

    local now = os.clock()
    if last_pos == nil or (pos - last_pos):length() > WORN_MOVE_M then last_pos = pos; last_move = now end
    if last_move == nil or now - last_move > WORN_WINDOW_S then since = nil return end
    since = since or now
    if now - since < SETTLE_S then return end
    done_for = player
    set_now("gameplay started, headset worn")
end)

log.info(TAG .. " loaded")
