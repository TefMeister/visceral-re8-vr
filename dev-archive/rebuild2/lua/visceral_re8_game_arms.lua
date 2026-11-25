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
local GAME_BODY_TOO = false   -- tried 2026-11-26 01:0x: the body IK skipped too. Tefa: "bobbing is still a lot moving
                              -- forward" [reported, n=1]; back to praydog's body IK. The switch stays for a later try.
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
    _G.__visceral_re8_game_body = (what ~= nil) and GAME_BODY_TOO   -- re8_vr.lua's update_body_ik reads it
    log.info(TAG .. " " .. (what and ("the game's arms: carrying " .. what) or "the controllers have the hands back"))
end

-- THE BODY STAYS DRAWN DURING A CARRY (2026-11-26). Tefa: in the patting scene on the stairs "hands and body
-- disappear and then reappear after it's done"; "Auto Hide Upper Body in Cutscenes" stays ON (his call), with a list
-- of exceptions; this is the first. How it is hidden [measured 2026-11-26, n=1 + REFramework's RE8VR.cpp, nightly
-- 01451, fix_player_shadow]: at pre-LockScene the base sets DrawDefault off on the player's body meshes whenever
-- the controllers are not in use or its cutscene flag is up (the patting scene raises the flag, with no event).
-- So: after LockScene's own work, while something is carried, DrawDefault goes back on for the same two meshes
-- (the player's own and pl1000LowerBody). A draw flag, not a joint; nothing made; no request.
local BODY_PARTS = { "pl1000LowerBody" }
local mesh_t = nil
local body_meshes, body_meshes_for = nil, nil

local function mesh_of(go)
    mesh_t = mesh_t or sdk.typeof("via.render.Mesh")
    return safe(function() return go:call("getComponent(System.Type)", mesh_t) end)
end

local function find_body_meshes(player)
    local found = {}
    local own = mesh_of(player)
    if own then found[#found + 1] = own end
    local transform = safe(function() return player:call("get_Transform") end)
    local child = transform and safe(function() return transform:call("get_Child") end)
    local n = 0
    while child ~= nil and n < MAX_CHILDREN do
        local go = safe(function() return child:call("get_GameObject") end)
        local name = go and safe(function() return go:call("get_Name") end)
        for _, want in ipairs(BODY_PARTS) do
            if name == want then
                local m = mesh_of(go)
                if m then found[#found + 1] = m end
            end
        end
        child = safe(function() return child:call("get_Next") end)
        n = n + 1
    end
    return found
end

re.on_application_entry("LockScene", function()
    if carrying == nil then body_meshes, body_meshes_for = nil, nil return end
    local player = re8vr and re8vr.player
    if player == nil then body_meshes, body_meshes_for = nil, nil return end
    if body_meshes_for ~= player then
        body_meshes = find_body_meshes(player)
        body_meshes_for = player
        log.info(TAG .. " the body stays drawn during the carry: " .. tostring(#body_meshes) .. " meshes")
    end
    for _, m in ipairs(body_meshes) do
        pcall(function() m:call("set_DrawDefault", true) end)
    end
end)

re.on_frame(function()
    frame = frame + 1
    if frame % CHECK_EVERY_FRAMES ~= 0 then return end
    local player = re8vr and re8vr.player
    if player == nil then set(nil) return end
    set(carried_child(player))
end)

log.info(TAG .. " loaded")
