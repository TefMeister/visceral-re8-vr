-- visceral_re8_game_arms.lua -- rebuild 2 (2026-11-26): the game's own arms while Ethan carries Rose.
--
-- Tefa (2026-11-26, the bare base): Rose hangs upside down from the left hand while the hands follow the
-- controllers; "the idle pose for ethan when the controllers are down goes into the pose where he is holding rose
-- the correct way - if there is a way to have that hold for entire time Ethan is holding Rose?"
--
-- How the carry is known [measured 2026-11-26, n=1, visceral_re8_carry_rec.lua]: the game runs NO event for it and
-- sets none of the VR layer's flags. From the first frame of control until the crib event (c10e050_00) the object
-- "pl5000" (Rose) is a first-level child of the player's transform (pl1000), and layer 0 plays the
-- ch01_0000_Baby_* / *_HoldBaby_* motions. The child is gone the moment the crib event's motion starts.
--
-- What it does: sets _G.__visceral_re8_game_arms while a child named in CARRIED hangs on the player. re8_vr.lua
-- (praydog's, our one dated line in update_hand_ik) then skips the hand IK, the same way praydog skips it in the
-- end-game events, so the arms play the game's hold-baby motions.
--
-- Rule set (design 2026-11-25d section 5): reads only; no joint write, no object, no request, no hook.
-- TO MOVE: this check becomes a "game arms" reason in the native frame's player-ready part when the frame exists
-- (rule 11: per-frame work is native). Until then it is this one callback, working every 10th frame.

local TAG = "[visceral-re8-game-arms]"
local CHECK_EVERY_FRAMES = 10
local MAX_CHILDREN = 80
local CARRIED = { pl5000 = "Rose" }   -- child object name -> what it is (for the log)

if reframework:get_game_name() ~= "re8" then return end

local frame = 0
local carrying = nil

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end

local function carried_child(player)
    local transform = safe(function() return player:call("get_Transform") end)
    local child = transform and safe(function() return transform:call("get_Child") end)
    local n = 0
    while child ~= nil and n < MAX_CHILDREN do
        local go = safe(function() return child:call("get_GameObject") end)
        local name = go and safe(function() return go:call("get_Name") end)
        if name ~= nil and CARRIED[name] ~= nil then return CARRIED[name] end
        child = safe(function() return child:call("get_Next") end)
        n = n + 1
    end
    return nil
end

local function set(what)
    if what == carrying then return end
    carrying = what
    _G.__visceral_re8_game_arms = what ~= nil
    log.info(TAG .. " " .. (what and ("the game's arms: carrying " .. what) or "the controllers have the hands back"))
end

re.on_frame(function()
    frame = frame + 1
    if frame % CHECK_EVERY_FRAMES ~= 0 then return end
    local player = re8vr and re8vr.player
    if player == nil then set(nil) return end
    set(carried_child(player))
end)

log.info(TAG .. " loaded")
