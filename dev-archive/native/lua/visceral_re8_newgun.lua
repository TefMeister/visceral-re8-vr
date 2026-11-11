-- visceral_re8_newgun.lua -- the game's own "new gun" move, shown in VR (2026-11-11).
--
-- Tefa (2026-11-08): "when finding a new gun in the game, the game takes over hands and plays the games original
-- animations in front of the player".
--
-- What plays (found and recorded 2026-11-08, modding-notes/2026-11-08-the-new-gun-animation.md): the arms' half is motion
-- 2007 of bank 0 on the player's layers 1, 2, 9 and 10; the gun's half is the gun's own GetWeapon motion on the gun's
-- layer 0 (Wolfsbane 0, SYG-12 2, every other gun 3). Started in the same frame the two run frame for frame.
--
-- How the hands are handed over while it plays:
--   * the arm IK is skipped (re8_vr.lua's __re8_arm_ik_update_override answers "handled"), so the arms follow the motion
--     and not the controllers;
--   * the plugin is told "cutscene" (_G.__visceral_newgun_playing, which visceral_re8_bridge.lua adds to the cutscene
--     slot), the switch every hand job of the plugin already stands down for.
-- It ends when the arm layer has left motion 2007, reached its end, or after MAX_S; the controllers have the hands back
-- the next frame.
--
-- WHEN: the first time a gun is in the hand (a list we keep in visceral_re8/newgun.json; the game's own first-pickup flag
-- was not found), a little after it is drawn. Every gun already on the save when this script first runs counts as seen
-- only once it has been in the hand, so each plays once. The Visceral Emporium (Comfort) has the switch and "Play it
-- again"; the desk: visceral_re8/newgun_cmd.json {"cmd": "play"} / {"cmd": "forget"}.

local TAG = "[visceral-re8-newgun]"
local FILE, CMD_FILE = "visceral_re8/newgun.json", "visceral_re8/newgun_cmd.json"
local ARM_LAYERS = { 1, 2, 9, 10 }
local ARM_BANK, ARM_MOTION = 0, 2007
local GUN_LAYER, GUN_BANK = 0, 0
local GUN_MOTION = { ri3008 = 0, ri3048 = 2 }   -- the gun's own GetWeapon motion; every other gun:
local GUN_MOTION_OTHER = 3
local BLEND_FRAMES = 6.0          -- blended in over this many frames
local INTERP_MODE, INTERP_CURVE = 2, 0   -- as played on 2026-11-08
local START_AFTER_S = 0.8         -- after the gun shows in the hand (its draw finishes first)
local MAX_S = 8.0                 -- never longer than this
local MIN_S = 0.5                 -- the layers are not asked "is it over?" before this
local END_MARGIN_FRAMES = 2.0
local CMD_EVERY_FRAMES = 30

local cfg = { on = false, seen = {} }   -- off until worn: on the simulator the arms pass very close to the eyes mid-move (2026-11-11)
pcall(function()
    local f = json.load_file(FILE)
    if type(f) == "table" then for k, v in pairs(f) do cfg[k] = v end end
end)
if type(cfg.seen) ~= "table" then cfg.seen = {} end
local function save() pcall(function() json.dump_file(FILE, cfg) end) end
local function L(s) log.info(TAG .. " " .. tostring(s)) end
local function safe(f, ...) local ok, v = pcall(f, ...); if ok then return v end; return nil end

local CHANGE_MOTION = "changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)"
local motion_t = nil
local function motion_of(go)
    motion_t = motion_t or sdk.typeof("via.motion.Motion")
    return go and motion_t and safe(function() return go:call("getComponent(System.Type)", motion_t) end)
end

-- the gun in the hand: its GameObject and short id ("ri3008"); nil with the knife or bare hands
local gun_core_t = nil
local function gun_in_hand()
    local go, id = nil, nil
    pcall(function()
        gun_core_t = gun_core_t or sdk.find_type_definition("app.WeaponGunCore")
        local pm = sdk.get_managed_singleton("app.PropsManager")
        local pl = pm and pm:get_field("<Player>k__BackingField")
        local u = nil
        for _, tn in ipairs({ "app.PlayerUpdater", "app.PlayerUpdaterFPS" }) do
            local t = sdk.typeof(tn)
            u = u or (t and pl and pl:call("getComponent(System.Type)", t))
        end
        local pg = u and u:call("get_playerGun")
        local w = pg and pg:call("get_equipWeaponObject")
        if w == nil or gun_core_t == nil or not w:get_type_definition():is_a(gun_core_t) then return end
        go = safe(function() return w:call("get_GameObject") end) or safe(function() return w:get_field("<owner>k__BackingField") end)
        local nm = go and tostring(go:call("get_Name")) or ""
        id = nm:match("^(ri%d+)")
    end)
    return go, id
end

-- the desk's command file must exist, or every look at it writes an error line into the game's log
if not pcall(function() assert(type(json.load_file(CMD_FILE)) == "table") end) then pcall(json.dump_file, CMD_FILE, { cmd = "done: -" }) end

local play = nil   -- { t0, gun, arm = layer 1 }
local function stop(why)
    if play == nil then return end
    L(string.format("over after %.2f s (%s); the hands are the controllers' again", os.clock() - play.t0, why))
    play = nil
    rawset(_G, "__visceral_newgun_playing", nil)
end
local function start(why)
    if play ~= nil then return false, "already playing" end
    if rawget(_G, "re8vr") == nil or re8vr.player == nil then return false, "no player" end
    local go, id = gun_in_hand()
    if go == nil or id == nil then return false, "no gun in the hand" end
    local pm = motion_of(re8vr.player)
    if pm == nil then return false, "the player has no motion" end
    local arm = nil
    for _, i in ipairs(ARM_LAYERS) do
        local l = safe(function() return pm:call("getLayer", i) end)
        if l == nil then return false, "no arm layer " .. i end
        local ok, err = pcall(function() l:call(CHANGE_MOTION, ARM_BANK, ARM_MOTION, 0.0, BLEND_FRAMES, INTERP_MODE, INTERP_CURVE) end)
        if not ok then return false, "the arm layer " .. i .. " refused: " .. tostring(err) end
        arm = arm or l
    end
    local gun_id = GUN_MOTION[id] or GUN_MOTION_OTHER
    local gm = motion_of(go)
    local gl = gm and safe(function() return gm:call("getLayer", GUN_LAYER) end)
    local gun_ok = gl ~= nil and pcall(function() gl:call(CHANGE_MOTION, GUN_BANK, gun_id, 0.0, BLEND_FRAMES, INTERP_MODE, INTERP_CURVE) end)
    play = { t0 = os.clock(), gun = id, arm = arm }
    rawset(_G, "__visceral_newgun_playing", true)
    L(string.format("playing the new-gun move for %s (%s): arms motion %d, the gun's own motion %d %s", id, why, ARM_MOTION, gun_id,
        gun_ok and "started" or "NOT started (the arms play alone)"))
    return true
end

-- the arm IK: skipped while it plays (chained, as the hand smoothing and the heal hold do)
local prev_override = rawget(_G, "__re8_arm_ik_update_override")
local function our_override()
    if type(prev_override) == "function" then
        local ok, handled = pcall(prev_override)
        if ok and handled == true then return true end
    end
    return play ~= nil
end
rawset(_G, "__re8_arm_ik_update_override", our_override)

local frames, seen_gun, seen_since = 0, nil, 0
re.on_frame(function()
    frames = frames + 1
    local now = os.clock()
    if play ~= nil then
        local age = now - play.t0
        local id = safe(function() return play.arm:call("get_MotionID") end)
        local fr = safe(function() return play.arm:call("get_Frame") end)
        local en = safe(function() return play.arm:call("get_EndFrame") end)
        if age > MAX_S then stop("the time limit")
        elseif age > MIN_S and id ~= nil and id ~= ARM_MOTION then stop("the game took the arm layers back")
        elseif age > MIN_S and fr ~= nil and en ~= nil and fr >= en - END_MARGIN_FRAMES then stop("the motion reached its end")
        elseif rawget(_G, "re8vr") == nil or re8vr.player == nil then stop("no player") end
    elseif cfg.on and frames % 6 == 0 and rawget(_G, "re8vr") ~= nil and re8vr.player ~= nil
        and safe(function() return vrmod:is_hmd_active() end) == true and re8vr.is_in_cutscene ~= true then
        -- a gun in the hand for the first time
        local _, id = gun_in_hand()
        if id ~= seen_gun then seen_gun, seen_since = id, now end
        if id ~= nil and cfg.seen[id] ~= true and now - seen_since >= START_AFTER_S
            and rawget(_G, "__visceral_reload_busy") ~= true then
            cfg.seen[id] = true; save()
            local ok, why = start("its first time in the hand")
            if not ok then L("not played for " .. id .. ": " .. tostring(why)) end
        end
    end
    if frames % CMD_EVERY_FRAMES == 0 then
        local ok, data = pcall(json.load_file, CMD_FILE)
        local line = ok and type(data) == "table" and type(data.cmd) == "string" and data.cmd or nil
        if line and line ~= "" and line:sub(1, 5) ~= "done:" then
            pcall(json.dump_file, CMD_FILE, { cmd = "done: " .. line })
            if line == "play" then
                local ok2, why = start("asked from the desk")
                if not ok2 then L("play refused: " .. tostring(why)) end
            elseif line == "forget" then cfg.seen = {}; save(); L("every gun is new again")
            elseif line == "state" and play ~= nil then
                L(string.format("state: %.2f s in, arm layer motion %s frame %s of %s", os.clock() - play.t0,
                    tostring(safe(function() return play.arm:call("get_MotionID") end)),
                    tostring(safe(function() return play.arm:call("get_Frame") end)),
                    tostring(safe(function() return play.arm:call("get_EndFrame") end))))
            elseif line == "state" then L("state: not playing")
            end
        end
    end
end)

re.on_script_reset(function()
    rawset(_G, "__visceral_newgun_playing", nil)
    if rawget(_G, "__re8_arm_ik_update_override") == our_override then rawset(_G, "__re8_arm_ik_update_override", prev_override) end
end)

-- ---- the Visceral Emporium (Comfort) ----------------------------------------------------------------------------------------
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 60, kind = "check", label = "The game's own new-gun move",
    help = "The first time a gun is in your hand the game shows it off with its own hand movement, then gives the hands back.",
    get = function() return cfg.on == true end, set = function(v) cfg.on = v == true; save() end })
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 60.1, kind = "button", label = "Play the new-gun move again",
    help = "For the gun in your hand, now.",
    press = function() local ok, why = start("asked from the Emporium"); if not ok then L("play refused: " .. tostring(why)) end end })

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 new-gun move") then return end
    local c, v = imgui.checkbox("Play it the first time a gun is in the hand", cfg.on == true)
    if c then cfg.on = v; save() end
    if imgui.button("Play it now for the gun in hand") then start("asked from the menu") end
    if imgui.button("Every gun is new again") then cfg.seen = {}; save() end
    imgui.text(play and "Playing." or "Not playing.")
    imgui.tree_pop()
end)

L("loaded (" .. (cfg.on and "on" or "off") .. ")")
