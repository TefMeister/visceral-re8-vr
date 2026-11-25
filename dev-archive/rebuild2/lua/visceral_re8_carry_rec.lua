-- visceral_re8_carry_rec.lua -- DEV RECORDER, rebuild 2 (2026-11-26). Not part of any package.
--
-- Why: on the bare base (REFramework nightly 01451 + praydog's re8_vr.lua, nothing of ours) Ethan carries Rose
-- upside down from the left hand while both hands follow the controllers (Tefa, picture, 2026-11-26 00:20).
-- praydog already lets the game's own arms play in the END-game events (re8_end_game_events, c32e390_01..09):
-- re8vr:update_hand_ik() is skipped there. To do the same for the prologue carry we need what the game calls it.
--
-- What it does: reads only. Twice a second it builds one line of state and writes it to the log when it differs
-- from the last line written:
--   the VR layer's flags, the running game event's name, and bank / motion id of the player's motion layers.
-- Rule set (design 2026-11-25d section 5): no joint write, no object made, no request, no hook; one on_frame
-- callback that returns at once on every frame but each 30th.

local TAG = "[visceral-re8-carry-rec]"
local EVERY_FRAMES = 30
local MAX_LAYERS = 12

if reframework:get_game_name() ~= "re8" then return end

local frame = 0
local last_line = ""
local motion_t = nil

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end

local function flag(v)
    if v == nil then return "?" end
    return v and "1" or "0"
end

local function event_name()
    local c = re8vr.game_event_action_controller
    if c == nil then return "no-controller" end
    local action = safe(function() return c:get_field("_GameEventAction") end)
    if action == nil then return "none" end
    return tostring(safe(function() return action:get_field("_EventName") end))
end

local function layers_text(player)
    motion_t = motion_t or sdk.typeof("via.motion.Motion")
    local motion = safe(function() return player:call("getComponent(System.Type)", motion_t) end)
    if motion == nil then return "no-motion" end
    local count = safe(function() return motion:call("getLayerCount") end) or 0
    if count > MAX_LAYERS then count = MAX_LAYERS end
    local parts = {}
    for i = 0, count - 1 do
        local layer = safe(function() return motion:call("getLayer", i) end)
        if layer ~= nil then
            local bank = safe(function() return layer:call("get_MotionBankID") end)
            local id = safe(function() return layer:call("get_MotionID") end)
            parts[#parts + 1] = string.format("L%d=%s/%s", i, tostring(bank), tostring(id))
        end
    end
    return table.concat(parts, " ")
end

-- v2 (2026-11-26 00:3x): the first run showed the carry has NO event and plays plain motion 0/0 on layer 0, from the
-- first frame of control until event c10e050_00 (the crib). So: who is the player object, what hangs under it, what
-- is layer 0's motion called. One slower line ("who"), written on change, checked every 2 s.
local WHO_EVERY_FRAMES = 120
local MAX_CHILDREN = 60
local last_who = ""

local function go_name(transform)
    local go = safe(function() return transform:call("get_GameObject") end)
    return go and tostring(safe(function() return go:call("get_Name") end)) or "?"
end

local function children_text(transform, depth, out)
    local child = safe(function() return transform:call("get_Child") end)
    while child ~= nil and #out < MAX_CHILDREN do
        out[#out + 1] = string.rep(">", depth) .. go_name(child)
        if depth < 2 then children_text(child, depth + 1, out) end
        child = safe(function() return child:call("get_Next") end)
    end
end

local function who_text(player)
    local name = tostring(safe(function() return player:call("get_Name") end))
    local transform = safe(function() return player:call("get_Transform") end)
    local parent = transform and safe(function() return transform:call("get_Parent") end)
    local kids = {}
    if transform then children_text(transform, 1, kids) end
    local node_name = "?"
    motion_t = motion_t or sdk.typeof("via.motion.Motion")
    local motion = safe(function() return player:call("getComponent(System.Type)", motion_t) end)
    local layer = motion and safe(function() return motion:call("getLayer", 0) end)
    local node = layer and safe(function() return layer:call("get_HighestWeightMotionNode") end)
    if node then node_name = tostring(safe(function() return node:call("get_MotionName") end)) end
    local scene_name = "?"
    local sm = sdk.get_native_singleton("via.SceneManager")
    local sm_t = sdk.find_type_definition("via.SceneManager")
    local scene = sm and sm_t and safe(function() return sdk.call_native_func(sm, sm_t, "get_CurrentScene") end)
    if scene then scene_name = tostring(safe(function() return scene:call("get_Name") end)) end
    return string.format("who player=%s parent=%s scene=%s L0name=%s kids=[%s]", name,
        parent and go_name(parent) or "none", scene_name, node_name, table.concat(kids, " "))
end

re.on_frame(function()
    frame = frame + 1
    if frame % EVERY_FRAMES ~= 0 then return end
    if re8vr == nil then return end
    local player = re8vr.player
    if player == nil then return end

    if frame % WHO_EVERY_FRAMES == 0 then
        local who = safe(who_text, player) or "who failed"
        if who ~= last_who then
            last_who = who
            log.info(TAG .. " " .. who)
        end
    end

    local line = string.format("cut=%s hands=%s jacked=%s motionplay=%s endevent=%s event=%s | %s",
        flag(re8vr.is_in_cutscene), flag(re8vr.can_use_hands), flag(re8vr.is_arm_jacked),
        flag(re8vr.is_motion_play), flag(re8vr.in_re8_end_game_event), event_name(),
        safe(layers_text, player) or "layers-failed")

    if line ~= last_line then
        last_line = line
        log.info(TAG .. " " .. line)
    end
end)

log.info(TAG .. " loaded (reads only; one line per change, checked twice a second)")
