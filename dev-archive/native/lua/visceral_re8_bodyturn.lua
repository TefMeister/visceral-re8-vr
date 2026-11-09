-- visceral_re8_bodyturn.lua -- ETHAN'S BODY TURNS LIKE LEON'S (2026-11-10, Fable).
--
-- Tefa (2026-11-10): "ethan's body to be able to move it like Leon's body is rotating naturally, i did get to feel it
-- once, you made it work but it broke everything else around it, hands and aiming went all wrong because of it".
-- Tefa's rule (2026-10-25): the body comes round once the head is more than 60 degrees off standing, 45 walking,
-- 30 running, then turns to face the head.
--
-- WHY THE BODY WAS ONE CHUNK WITH THE HEAD [measured 2026-11-10, simulator]: the VR loader hands the headset's
-- direction to the game as its camera every frame, and the game's own movement part (app.PlayerMovement) points the
-- body at that camera at once: head turned 70 degrees, the player's yaw went from -59.7 to 10.3 with it;
-- PlayerMovement.destinationAngle() returned the head's yaw and calcAngleDiff() stayed 0.
--
-- THE LEVER: destinationAngle() is where the game asks "which way should the body face?". While this is on, its answer
-- is replaced by a direction kept here: the body's. Proved live the same night: with the answer held, the head looked
-- 40 degrees aside and the body stayed (-59.7), the view untouched (camera 160.3).
-- NOTHING ELSE IS TOUCHED: not the camera, not the VR view offset, not a single joint. The game turns the body itself
-- (legs and all), and the arms are solved afterwards from wherever the shoulders now are to the same hand targets, so
-- the hands stay on the controllers and the gun aims as before. (The 10-24 try, body.cpp, turned the DRAWN joints
-- after the arm solve, which hung the arms off turned shoulders and swung the body into the view; the 10-29 try,
-- turn.cpp, set the game's turn thresholds, which this game's first-person body never consults.)
-- Walking still goes where the head looks (the game's movement reads the camera, which is the head).
--
-- The body's direction: starts at the head's; turns with the stick (any change of the view that the headset itself
-- did not make is carried over whole); otherwise stays until the head is past the deadzone, then eases round to it.
--
-- Switch and numbers: _G.VISCERAL_BODY_TURN (on, deg_stand, deg_walk, deg_run, rate, rate_gain, settle), saved in
-- reframework/data/visceral_re8/bodyturn.json; the menu row is in _G.VISCERAL_OPTIONS (Comfort). Off = as shipped.

local TAG = "[visceral-bodyturn]"
local CFG = "visceral_re8/bodyturn.json"
local V = _G.VISCERAL_BODY_TURN or {}
_G.VISCERAL_BODY_TURN = V

local saved = json.load_file(CFG) or {}
V.on = saved.on ~= false               -- on unless switched off (Tefa asked for it 2026-11-10)
V.deg_stand = saved.deg_stand or 60.0     -- Tefa's deadzones, in degrees
V.deg_walk = saved.deg_walk or 45.0
V.deg_run = saved.deg_run or 30.0
V.rate = saved.rate or 140.0              -- degrees a second at the start of a turn...
V.rate_gain = saved.rate_gain or 2.5      -- ...plus this many per degree still to go (a turn that eases out)
V.settle = saved.settle or 1.0            -- a turn ends this close to the head
V.walk_speed = 0.4                        -- metres a second: above = walking
V.run_speed = 3.2                         -- above = running
V.turning = false
V.rel = 0.0                               -- the head's yaw off the body, degrees (for the log and the menu)
V.count = 0                               -- turns started
V.answers = 0                             -- destinationAngle answers replaced

local function save()
    json.dump_file(CFG, { on = V.on, deg_stand = V.deg_stand, deg_walk = V.deg_walk, deg_run = V.deg_run,
                          rate = V.rate, rate_gain = V.rate_gain, settle = V.settle })
end
V.save = save

local FORWARD = Vector3f.new(0, 0, 1)
local function yaw_of(q) local f = q * FORWARD; return math.atan(f.x, f.z) end
local function wrap(a)
    while a > math.pi do a = a - 2.0 * math.pi end
    while a < -math.pi do a = a + 2.0 * math.pi end
    return a
end

local body = nil            -- the body's yaw, radians, in the camera controller's own measure
local last_base = nil       -- the view's yaw with the headset's own turn taken out (changes only by the stick)
local last_t, last_pos, speed = nil, nil, 0.0
local fresh_t = -10.0       -- when the body's direction was last worked out

local function controller_of(player_camera)
    local solver = player_camera:get_field("BaseTransSolver")
    if solver == nil then return nil end
    return solver:get_field("CurrentController") or solver:get_field("<CurrentController>k__BackingField")
end

-- re8_vr.lua calls this right after the loader's camera fix, every frame in play
function V.after(player_camera)
    if re8vr.is_in_cutscene or not vrmod:is_hmd_active() then body = nil; last_base = nil; return end
    local c = controller_of(player_camera)
    if c == nil then return end
    local now = os.clock()
    local dt = last_t and math.min(0.1, math.max(0.0005, now - last_t)) or 0.011
    last_t = now

    local tf = re8vr.transform
    if tf ~= nil then
        local p = tf:get_position()
        if last_pos ~= nil then
            local dx, dz = p.x - last_pos.x, p.z - last_pos.z
            local v = math.sqrt(dx * dx + dz * dz) / dt
            if v < 20.0 then speed = speed + (v - speed) * 0.2 end
        end
        last_pos = p
    end
    V.speed = speed

    local head = yaw_of(c:get_field("<Rotation>k__BackingField"))       -- the loader just wrote the head's flat yaw here
    local base = wrap(head - yaw_of(vrmod:get_rotation(0):to_quat()))    -- the same with the headset's own turn out
    if body == nil or last_base == nil then
        body = head
        V.turning = false
    else
        body = wrap(body + wrap(base - last_base))                       -- the stick (or a re-centre) turned the view
    end
    last_base = base

    local rel = wrap(head - body)
    V.rel = math.deg(rel)
    local dead = math.rad(speed > V.run_speed and V.deg_run or (speed > V.walk_speed and V.deg_walk or V.deg_stand))
    if not V.turning and math.abs(rel) > dead then V.turning = true; V.count = V.count + 1 end
    if V.turning then
        local rate = math.rad(V.rate + V.rate_gain * math.abs(V.rel))
        local step = math.min(math.abs(rel), rate * dt) * (rel < 0 and -1.0 or 1.0)
        body = wrap(body + step)
        if math.abs(wrap(head - body)) < math.rad(V.settle) then V.turning = false end
    end
    V.body_deg = math.deg(body)
    fresh_t = now
end

-- the game asks which way the body should face
local dest = sdk.find_type_definition("app.PlayerMovement")
dest = dest and dest:get_method("destinationAngle")
if dest ~= nil then
    sdk.hook(dest, function(args) return sdk.PreHookResult.CALL_ORIGINAL end, function(retval)
        if not V.on then body = nil; last_base = nil; return retval end
        if V.body_deg == nil or os.clock() - fresh_t > 0.25 then return retval end   -- not worked out lately: the game's own
        V.answers = V.answers + 1
        return sdk.float_to_ptr(V.body_deg)
    end)
else
    log.info(TAG .. " app.PlayerMovement.destinationAngle NOT FOUND: the body turn cannot work")
end

-- the menu row (the Emporium and the monitor window both read this table)
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
table.insert(_G.VISCERAL_OPTIONS, {
    tab = "comfort", order = 5, kind = "check", label = "Body turns like Leon's",
    help = "Ethan's body stays put while you look around and comes round once you look far enough (60 degrees standing, 45 walking, 30 running).",
    get = function() return V.on end,
    set = function(v) V.on = v == true; save() end,
})

log.info(TAG .. " loaded, " .. (V.on and "ON" or "off") .. string.format(" (deadzones %.0f / %.0f / %.0f)", V.deg_stand, V.deg_walk, V.deg_run))
