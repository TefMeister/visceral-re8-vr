-- visceral_re8_doors.lua -- Village's doors open when the HAND reaches them, not when Ethan walks near (2026-11-19, b143).
-- Tefa, after wearing b142: "i can hear the door opening sound from far away, when the door opened before about a meter or
-- more from ethan, but when i get close to it, i cannot open it at all, not by pressin A or pushing with my hands. the door
-- opening sound, it has to come after the hand is actually on the door".
-- Found on the simulator 2026-11-19 (modding-notes/2026-11-19-doors-open-at-the-hand.md):
--   1. Walking near a door, its "push" sensor (app.InteractDoor.OnOverlapDoorPushCollider, the ColliderPlayerPush shape,
--      1-3 m out) starts the game's own open: the sound plays and the game counts the door OPEN, so A does nothing after.
--      Here that call is skipped: the game never opens a door by itself as Ethan walks up.
--   2. The game's own door start (app.InteractDoor.StartInteractDoor(player), A's path) opens a leaf with Ethan beside it.
--      The plugin (doors.cpp) sees a hand or the gun moving into a shut leaf and counts it in bridge slot 266 with the leaf's
--      hinge in 276-278; this script then calls that start on the leaf's InteractFront / InteractBehind nearer the player.
--   3. The leaf's collision follows the angle doors.cpp draws (1 degree when the game opens it, then pushed by the hands and
--      the body): Ethan walking into it was stopped dead (~1 m in 3 s). The game itself counts the door open at 90 degrees,
--      where it is out of the way, so while a near door is open (LittleOpen / LittleOpened / Opening / Opened / Push) the
--      leaf's own solid parts are switched off (see (3) below); back on when it is no longer open.
-- A real A press still opens a door the game's own way. Locked doors: doors.cpp sends no touch (no rattle from brushing).

local TAG = "[visceral-re8-doors]"
local S_DOOR_PRESS_SEQ, S_DOOR_TOUCH_P = 266, 276
-- app.DoorBehavior.get_doorState = the murmur hash of the state's name (via.murmur_hash.calc32, read 2026-11-19; src/settings.h
-- DOORS_STATE_*). Only these count as open: Closed 474011919, Locked 3401490761 and Closing 3360157036 do not.
local OPEN_STATES = {
    [3407536511] = true,   -- LittleOpen (the game's 20-degree crack, starting)
    [171654102] = true,    -- LittleOpened (what the hand's StartInteractDoor gives the Duke's gate)
    [887278378] = true,    -- Opening
    [3232296810] = true,   -- Opened
    [396010129] = true,    -- Push
}
local NEAR_M = 4.0                      -- doors whose colliders this script looks after
local LEAF_PICK_M = 1.6                 -- an Interact part this close to the touched hinge belongs to that leaf
local COLLIDER_EVERY = 6                -- frames between collider passes

local cfg = { block_walk_open = true, touch_opens = true, colliders_off_while_open = true }

local GEN = {}
rawset(_G, "__visceral_doors_gen", GEN)
local function mine() return rawget(_G, "__visceral_doors_gen") == GEN end
local function safe(fn) local ok, v = pcall(fn); if ok then return v end; return nil end
local logs = 0
local function say(fmt, ...) if logs < 200 then logs = logs + 1; log.info(TAG .. " " .. string.format(fmt, ...)) end end

local function scene()
    local sm = sdk.get_native_singleton("via.SceneManager")
    return sm and sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
end
local function player_go()
    local re8vr = rawget(_G, "re8vr")
    return re8vr and re8vr.player
end
local function pos_of(comp)
    local p = safe(function() return comp:call("get_GameObject"):call("get_Transform"):call("get_Position") end)
    return p
end
local function d2(a, b) return (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 end

-- (1) no open by walking near
local blocked = 0
do
    local t = sdk.find_type_definition("app.InteractDoor")
    local m = t and t:get_method("OnOverlapDoorPushCollider")
    if m then
        sdk.hook(m, function(args)
            if not mine() or not cfg.block_walk_open then return end
            blocked = blocked + 1
            if blocked == 1 then say("a door's walk-in push skipped: doors open at the hand now") end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, function(r) return r end)
    else
        say("no app.InteractDoor.OnOverlapDoorPushCollider: doors still open by walking near")
    end
end

-- (2) the hand on a shut leaf: the game's own start on that leaf
local last_seq = nil
local function open_touched(b)
    local h = { x = b.r(S_DOOR_TOUCH_P), y = b.r(S_DOOR_TOUCH_P + 1), z = b.r(S_DOOR_TOUCH_P + 2) }
    local pl = player_go()
    local pp = pl and safe(function() return pl:call("get_Transform"):call("get_Position") end)
    local sc = scene()
    local list = sc and safe(function() return sc:call("findComponents(System.Type)", sdk.typeof("app.InteractDoor")) end)
    if not (pp and list) then say("a hand on a door, but no player or no door parts"); return end
    local best, best_d = nil, nil
    for i = 0, (safe(function() return list:call("get_Count") end) or 0) - 1 do
        local c = list:call("get_Item", i)
        local p = pos_of(c)
        if p and d2(p, h) < LEAF_PICK_M ^ 2 and math.abs(p.y - h.y) < 2.0 then
            local dp = d2(p, pp)
            if best_d == nil or dp < best_d then best, best_d = c, dp end
        end
    end
    if best == nil then say("a hand on a door, but no InteractFront / InteractBehind within %.1f m of its hinge", LEAF_PICK_M); return end
    local ok = pcall(function() best:call("StartInteractDoor(via.GameObject)", pl) end)
    say("a hand on a door: the game opens it (%s %.2f m from Ethan)%s",
        safe(function() return best:call("get_GameObject"):call("get_Name") end) or "?", math.sqrt(best_d), ok and "" or " -- the call FAILED")
end

-- (3) an open door's solid parts off, back on when it is no longer open. NOT app.DoorBehavior.SetDoorCollidersEnable: on
-- the simulator (2026-11-19) it left the leaf's own via.physics.Colliders on and Ethan still could not pass. Switched off
-- here: the leaf's own Colliders and those of its children (the chain padlocks hanging on a gate leaf), except the game's
-- sensors (Collider* children: push / in / passed) and the enemies' map (DoorAiMapCollider, AIMapBakeCollider). Only the
-- ones that were ON are switched, and only those go back on.
local COLLIDERS_T = sdk.typeof("via.physics.Colliders")
local function solid_parts(leaf_tf)
    local out = {}
    local function take(tf)
        local go = tf:call("get_GameObject")
        local c = go and go:call("getComponent(System.Type)", COLLIDERS_T)
        if c and c:call("get_Enabled") then out[#out + 1] = c end
    end
    take(leaf_tf)
    local ch = leaf_tf:call("get_Child")
    while ch do
        local nm = ch:call("get_GameObject"):call("get_Name") or ""
        if not (nm:find("^Collider") or nm:find("AiMap") or nm:find("AIMap")) then take(ch) end
        ch = ch:call("get_Next")
    end
    return out
end
local off = {}   -- address -> { door = the DoorBehavior, parts = the Colliders we switched off }
local seen_closed = {}   -- address -> true once seen Closed: a door found already open (left open earlier) is not touched
local frame_n = 0
local function colliders()
    local pl = player_go()
    local pp = pl and safe(function() return pl:call("get_Transform"):call("get_Position") end)
    if not pp then return end
    -- the ones we switched off: back on once no longer open (or gone)
    for addr, e in pairs(off) do
        local st = safe(function() return e.door:call("get_doorState") end)
        if st == nil or not OPEN_STATES[st] then
            for _, c in ipairs(e.parts) do pcall(function() c:call("set_Enabled", true) end) end
            off[addr] = nil
            say("a door no longer open (state %s): its collision back on (%d parts)", tostring(st), #e.parts)
        end
    end
    local sc = scene()
    local list = sc and safe(function() return sc:call("findComponents(System.Type)", sdk.typeof("app.DoorBehavior")) end)
    if not list then return end
    for i = 0, (safe(function() return list:call("get_Count") end) or 0) - 1 do
        local c = list:call("get_Item", i)
        local p = pos_of(c)
        if p and d2(p, pp) < NEAR_M ^ 2 and math.abs(p.y - pp.y) < 2.0 then
            local addr = c:get_address()
            local st = safe(function() return c:call("get_doorState") end)
            if st == 474011919 then seen_closed[addr] = true end
            if off[addr] == nil and seen_closed[addr] and st ~= nil and OPEN_STATES[st] and not safe(function() return c:call("IsLocked") end) then
                local parts = safe(function() return solid_parts(c:call("get_GameObject"):call("get_Transform")) end) or {}
                for _, part in ipairs(parts) do part:add_ref(); pcall(function() part:call("set_Enabled", false) end) end
                c:add_ref()
                off[addr] = { door = c, parts = parts }
                say("a door open (state %d): %d solid parts off while the hands and the body push it", st, #parts)
            end
        end
    end
end

re.on_frame(function()
    if not mine() then return end
    local b = rawget(_G, "visceral_re8_bridge")
    if b == nil or not b.ready() then return end
    if cfg.touch_opens then
        local seq = b.r(S_DOOR_PRESS_SEQ)
        if seq ~= nil and seq >= 0 and seq < 1e6 then
            if last_seq == nil then last_seq = seq
            elseif seq ~= last_seq then last_seq = seq; pcall(open_touched, b) end
        end
    end
    frame_n = frame_n + 1
    if cfg.colliders_off_while_open and frame_n % COLLIDER_EVERY == 0 then pcall(colliders) end
end)

say("loaded: no open by walking near; the hand opens a door the game's way; an open door's collision off")
