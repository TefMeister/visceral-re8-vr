-- visceral_re8_bridge.lua -- rebuild 2 (2026-11-26, design item 3): what the plugin cannot read itself, and
-- nothing else. The slots and how the plugin finds the array: native/src/bridge.h (keep the two in step).
--
-- One managed float array, made once per script start and held (add_ref) for the plugin to read. Its address and
-- a random sentinel go to reframework/data/visceral_re8/bridge.txt; the plugin checks both before it reads.
-- Written at UpdateHID (before the plugin's UpdateBehavior step reads it). No hook, no joint, no object besides
-- the array, no request (rule set, design 2026-11-25d section 5).

local TAG = "[visceral-re8-bridge]"
local FILE = "visceral_re8/bridge.txt"
local ARRAY_DATA_AT = 0x20          -- a managed array's first element
local S_FRAME, S_SENTINEL, S_ACTIVE, S_CUTSCENE, S_CAN_USE_HANDS, S_GAME_ARMS, S_WEAPON = 0, 1, 2, 3, 4, 5, 6
local S_TURN_OK, S_TURN_STAMP, S_HEAD_YAW, S_BASE_YAW, S_MOVE_TURN = 7, 8, 9, 10, 11
local S_LEFT_ASLEEP, S_RIGHT_ASLEEP = 12, 13
local ASLEEP_M = 0.0001             -- a controller that reports a position this close to 0 0 0 is asleep (measured
                                    -- 2026-11-26: exactly 0 0 0 from about 6 s after it is put down)
-- 2026-11-26, the recorders (native/src/rec.h) and the lean fix (native/src/leanfix.h):
local S_STICK_X, S_STICK_Y, S_STEP_ON = 14, 15, 16     -- the left stick as it was handed to the game; a room step runs
local S_HMD = 17                    -- 17..19 the headset's place, 20..23 its turn (x y z w), as the loader reports them
local S_LEFT_AT, S_RIGHT_AT = 24, 27   -- 24..26 / 27..29 the controllers' places, the same space
local S_LEAN, S_LEAN_APPLIED = 30, 31  -- 30 WRITTEN BY THE PLUGIN: metres the body should sit further back; 31 what
                                       -- body_place really used this frame (0 = nothing: off, or a real scene)
local S_SCRIPTBODY_OFF = 32         -- 1 = the script half of the body (its place, the steps) is switched off
local S_COUNT = 40
-- THE SCRIPT HALF'S OWN SWITCH (2026-11-26, the legs' halving test). off.txt's `frame` switches the plugin off, but
-- the body's place and the steps live in this script and stayed on. tools/legs-test.sh writes this file beside
-- off.txt when `scriptbody` is asked for: the loader's own placing and its own slide stand then.
local SCRIPTBODY_OFF = false
pcall(function()
    local f = json.load_file("visceral_re8/scriptbody-off.json")
    SCRIPTBODY_OFF = f ~= nil and tonumber(f.off) == 1
end)

if reframework:get_game_name() ~= "re8" then return end

local arr = sdk.create_managed_array("System.Single", S_COUNT)
if not arr then
    log.info(TAG .. " could not make the array; the plugin's parts stand down")
    return
end
arr:add_ref()

local function w(slot, v) arr:write_float(ARRAY_DATA_AT + slot * 4, v or 0.0) end
local function wb(slot, b) w(slot, b and 1.0 or 0.0) end

math.randomseed(os.time())
local sentinel = math.random(100000, 9999999)   -- a whole number a float holds exactly
for i = 0, S_COUNT - 1 do w(i, 0.0) end
w(S_SENTINEL, sentinel)
json.dump_file(FILE, { a_address = string.format("%d", arr:get_address()), b_sentinel = sentinel })

local frame = 0
re.on_pre_application_entry("UpdateHID", function()
    frame = (frame + 1) % 1000000
    w(S_FRAME, frame)
    local active = false
    pcall(function() active = vrmod:is_hmd_active() and vrmod:is_using_controllers() end)
    wb(S_ACTIVE, active)
    wb(S_CUTSCENE, re8vr.is_in_cutscene == true)
    wb(S_CAN_USE_HANDS, re8vr.can_use_hands == true)
    -- S_GAME_ARMS is the plugin's (native/src/gamearms.h); B.game_arms() below reads it for re8_vr.lua
    wb(S_WEAPON, re8vr.weapon ~= nil)
    -- sleeping controllers (native/src/sleephands.h): [1] is the left one, [2] the right, as re8_vr.lua takes them
    local left_asleep, right_asleep = false, false
    pcall(function()
        local list = vrmod:get_controllers()
        if list == nil then return end
        -- x, y, z by hand: the position comes as four numbers and the fourth is not part of it
        local function at_zero(i)
            local p = vrmod:get_position(i)
            return math.abs(p.x) < ASLEEP_M and math.abs(p.y) < ASLEEP_M and math.abs(p.z) < ASLEEP_M
        end
        if list[1] ~= nil then left_asleep = at_zero(list[1]) end
        if list[2] ~= nil then right_asleep = at_zero(list[2]) end
    end)
    wb(S_LEFT_ASLEEP, left_asleep)
    wb(S_RIGHT_ASLEEP, right_asleep)
    -- for the recorders: the headset and the controllers as the loader reports them (one space, metres)
    pcall(function()
        local p, q = vrmod:get_position(0), vrmod:get_rotation(0):to_quat()
        w(S_HMD, p.x) w(S_HMD + 1, p.y) w(S_HMD + 2, p.z)
        w(S_HMD + 3, q.x) w(S_HMD + 4, q.y) w(S_HMD + 5, q.z) w(S_HMD + 6, q.w)
        local list = vrmod:get_controllers()
        if list == nil then return end
        for n, slot in ipairs({ S_LEFT_AT, S_RIGHT_AT }) do
            if list[n] ~= nil then
                local c = vrmod:get_position(list[n])
                w(slot, c.x) w(slot + 1, c.y) w(slot + 2, c.z)
            end
        end
    end)
    w(S_LEAN_APPLIED, 0.0)          -- body_place writes what it used, later this frame
    wb(S_SCRIPTBODY_OFF, SCRIPTBODY_OFF)
end)

-- THE BODY TURN (native/src/bodyturn.h). re8_vr.lua calls camera_step right after the loader's camera fix (one dated
-- line there): the head's flat yaw as the loader wrote it to the camera controller, and the same with the headset's
-- own turn taken out. The plugin keeps the body's direction and writes back how far to turn the left stick.
local FORWARD = Vector3f.new(0, 0, 1)
local function yaw_of(q) local f = q * FORWARD; return math.atan(f.x, f.z) end
local turn_stamp = 0
local B = {}
_G.__visceral_re8_bridge = B

-- THE BODY'S PLACE (2026-11-26). Tefa: "looking down and moving my head, it feels like Ethan's body is literally
-- 'hanging' on the headset, following every little move the head makes - left right backwards or forward, every
-- little shake. can we put a deadzone on this as well, a separate one from the body rotation?" ... "and everything
-- moves with it, legs hands and body, not just torso".
-- Why it hangs [read from the loader's source, RE8VR.cpp update_body_ik, 2026-11-26]: every frame the loader sets
-- the leg solver's centre offset to (the head's place - the body's own head joint), so the whole body sits exactly
-- under the headset. The lever: the same call, made again right after the loader's (the later one stands), with a
-- place for the head that WE keep: it follows the head from behind (see below; dead_cm > 0 would hold it until
-- the head is that far away, level distance). Height is never held (crouching follows).
-- back_cm moves the whole body back from the head (Tefa asked for that too; 0 = as the loader places it).
-- This runs in the script, not the plugin: the call is the loader's script-side object (re8vr), which the plugin
-- cannot reach. Numbers: reframework/data/visceral_re8/bodyplace.json, read again every few seconds in play.
local PLACE_FILE = "visceral_re8/bodyplace.json"
local PLACE_FILE_EVERY_FRAMES = 180
-- The numbers as Tefa tuned them in play, 2026-11-26 (bodyplace.json): dead zone 1 cm ("this feels right", after 3, 6
-- and 15), follow 0.9 s, neck 9 cm + back 2 cm ("the 10 body backwards is ideal"), steps from 12 cm to 6 cm at a push
-- of 0.18 ("that is great"; 0.5 was "a dash almost", 0.3 "still too fast").
-- 2026-11-26 evening: follow 0.05 s and no dead zone are the built-in numbers now (worn live through bodyplace.json
-- for the body-at-a-stop tests; Tefa, standing still: "still fine", twice, and when asked: "standing still felt
-- fine"). `lean`: 1 = the plugin's lean fix (native/src/leanfix.h) moves the body; 0 = it only measures.
local PLACE = { lean = 0.0, dead_cm = 0.0, follow_s = 0.05, back_cm = 2.0, steps = 1.0, step_start_cm = 12.0, step_stop_cm = 6.0, step_push = 0.18, neck_cm = 9.0, pin = 0.0 }
-- THE BODY PINNED BY THE REAL HEAD (2026-11-26). Tefa, in the village: "when i run and stop, Ethan's whole body
-- get's pushed forward so for less than a second i'm looking through his body, like from the centre of it"; the
-- same at a vault and when a cutscene hands control back. Switching the follow lag off changed nothing (his
-- answer, same hour). Why [read, RE8VR.cpp update_body_ik]: the loader places the body so that the head of the
-- STANDING STRAIGHT pose is under the view (plus its look-down shift); whatever a motion leans the upper body
-- by, the torso swings into the view by that much. So: each frame the REAL Head joint is compared with where
-- the loader's sum says the head should be, and the level difference is added, bit by bit, to the place handed
-- to the loader (it settles within a few frames; standing straight the difference is nothing, so the standing
-- feel Tefa tuned stays). bodyplace.json "pin": 0 switches it off in play. (That first design was WRONG in one
-- assumption: see SECOND DESIGN in body_place.)
local PIN_GAIN = 0.3                  -- how much of the difference is taken in per frame
local PIN_MAX_M = 0.35                -- never more than this
local PIN_JOINTS = { "Neck_0", "Neck_1", "Spine_2" }   -- the first one found is watched (NOT "Head": see below)
local PIN_LEARN_FRAMES = 45           -- standing still this long before the standing offset is first taken
local PIN_ADAPT_FRAMES = 120          -- standing still this long: the standing offset follows slowly
local PIN_ADAPT = 0.02
local PIN_LOOKDOWN, PIN_FORWARD = 0.1, 0.025   -- the loader's own look-down shift and forward shift (its numbers)
local pin_x, pin_z, pin_joint, pin_for, pin_frames = 0.0, 0.0, nil, nil, 0
local pin_base, pin_still, pin_last, pin_name, pin_peak = nil, 0, nil, "none", 0.0
local PLACE_SETTLE_M = 0.01           -- a move ends this close to the head
local PLACE_JUMP_M = 1.0              -- the head this far from the kept place: a load or a teleport, start again
local place_at, place_moving, place_t, place_frames = nil, false, nil, 0
local body_error_told = false
local BACK = Vector3f.new(0, 0, 1)    -- the camera looks along -Z: this is "behind the view"

-- Worn 13:2x with a dead zone of 8 cm, then Tefa: "here is where we can't really have a dead zone and need a lag
-- instead, so the body starts moving the headset's direction 0.5 sec behind and always settles where the headset
-- is, starting slow, then speeding up and finishing slow and smooth". So: a damped follow (it keeps a speed of its
-- own, so it starts slow, catches up and lands softly, about follow_s behind), and no dead zone by default.
local place_vx, place_vz = 0.0, 0.0
local PLACE_SETTLE_SPEED = 0.02       -- metres a second: with a dead zone set, a move ends once it is this slow
local function smooth(at, to, speed, dt)
    local omega = 2.0 / math.max(0.02, PLACE.follow_s)
    local x = omega * dt
    local decay = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
    local change = at - to
    local temp = (speed + omega * change) * dt
    return to + (change + temp) * decay, (speed - omega * temp) * decay
end

local function place_numbers()
    place_frames = place_frames + 1
    if place_frames % PLACE_FILE_EVERY_FRAMES ~= 1 then return end
    local f = json.load_file(PLACE_FILE) or {}
    local d, fo, b = tonumber(f.dead_cm) or 0.0, tonumber(f.follow_s) or 0.05, tonumber(f.back_cm) or 2.0
    PLACE.lean_back = tonumber(f.lean_back)      -- nil = the same strength as "lean"
    local re_ = tonumber(f.runend_threshold)
    if re_ ~= PLACE.runend then
        PLACE.runend = re_
        log.info(TAG .. " run end: " .. (re_ and string.format("the jog-end threshold is asked to be %.3f", re_) or "the game's own threshold"))
    end
    local sh = tonumber(f.shoulders) or 0.0
    if sh ~= PLACE.shoulders then
        PLACE.shoulders = sh
        log.info(TAG .. " shoulders: " .. (sh > 0.5 and "held in their standing pose before the hands are solved" or "off, the game's motion has them"))
    end
    local co = tonumber(f.camoff) or 0.0
    if co ~= PLACE.camoff then
        PLACE.camoff = co
        log.info(TAG .. " camera offset: " .. (co > 0.5 and "a jump of the camera when the game hands it over (no event running) is glided out" or "off, the camera snaps as the game has it"))
    end
    local ln = tonumber(f.lean) or 0.0
    if ln ~= PLACE.lean then
        PLACE.lean = ln
        log.info(TAG .. " lean fix: " .. (ln > 0.01 and string.format("moves the body, by %.0f%% of what a motion leans it", math.min(ln, 1.0) * 100.0) or "measures only"))
    end
    local bl = tonumber(f.blip) or 0.0
    if bl ~= PLACE.blip then
        PLACE.blip = bl
        log.info(TAG .. " blip: " .. (bl > 0.5 and "a cutscene flag with no event running counts as play (hands stay on the controllers)" or "off, the loader's flag stands"))
    end
    local st, s1, s0, sp = tonumber(f.steps) or 1.0, tonumber(f.step_start_cm) or 12.0, tonumber(f.step_stop_cm) or 6.0,
        tonumber(f.step_push) or 0.18
    local nk = tonumber(f.neck_cm) or 9.0
    -- OFF unless the file says 1 (2026-11-26: both designs moved the body wrongly on Tefa; the joints read at this
    -- point of the frame are not the posed body. native/src/leanrec.h measures at the right point first.)
    local pn = tonumber(f.pin) or 0.0
    if pn ~= PLACE.pin then
        PLACE.pin = pn
        pin_for = nil
        log.info(TAG .. " body pin: " .. (pn > 0.5 and "on" or "off"))
    end
    if nk ~= PLACE.neck_cm then
        PLACE.neck_cm = nk
        log.info(TAG .. string.format(" body place: the neck is %.0f cm behind the eyes", nk))
    end
    if d ~= PLACE.dead_cm or fo ~= PLACE.follow_s or b ~= PLACE.back_cm or st ~= PLACE.steps
        or s1 ~= PLACE.step_start_cm or s0 ~= PLACE.step_stop_cm or sp ~= PLACE.step_push then
        PLACE.dead_cm, PLACE.follow_s, PLACE.back_cm = d, fo, b
        PLACE.steps, PLACE.step_start_cm, PLACE.step_stop_cm, PLACE.step_push = st, s1, s0, sp
        log.info(TAG .. string.format(" body place: dead zone %.0f cm, follow %.2f s, back %.0f cm; steps %s (start %.0f cm, stop %.0f cm, push %.2f)",
            d, fo, b, st > 0.5 and "on" or "off", s1, s0, sp))
    end
end

local function body_place()
    place_numbers()
    local player_tf = re8vr.transform
    local camera = sdk.get_primary_camera()
    if player_tf == nil or camera == nil then place_at = nil return end
    local cam_tf = camera:call("get_GameObject"):call("get_Transform")
    local cam, rot, base = cam_tf:call("get_Position"), cam_tf:call("get_Rotation"), player_tf:call("get_Position")
    local now = os.clock()
    local dt = place_t and math.min(0.1, math.max(0.0005, now - place_t)) or 0.011
    place_t = now
    -- the head against the player's own spot (walking with the stick moves both, so that changes nothing here)
    -- (the NECK against it, not the eyes: see the neck_cm note below. Worn 14:0x with the neck shift added AFTER
    -- the soft follow: Tefa: "it's back to just being constant and instant, i look down left and the whole body
    -- posture leans right": the shift swung at once while the follow was still half a second behind. The neck is
    -- what is followed now, so a head that only turns asks for no move at all.)
    local head_back = rot * BACK
    local hl = math.sqrt(head_back.x * head_back.x + head_back.z * head_back.z)
    local nx, nz = 0.0, 0.0
    if hl > 0.001 then nx, nz = head_back.x / hl * PLACE.neck_cm * 0.01, head_back.z / hl * PLACE.neck_cm * 0.01 end
    local hx, hz = cam.x + nx - base.x, cam.z + nz - base.z
    if place_at == nil then place_at = { x = hx, z = hz } place_moving = false end
    local dx, dz = hx - place_at.x, hz - place_at.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist > PLACE_JUMP_M then
        place_at.x, place_at.z, place_moving, dist = hx, hz, false, 0.0
        place_vx, place_vz = 0.0, 0.0
    elseif not place_moving and dist > PLACE.dead_cm * 0.01 then
        place_moving = true
    end
    if PLACE.dead_cm <= 0.0 then place_moving = true end
    if place_moving then
        place_at.x, place_vx = smooth(place_at.x, hx, place_vx, dt)
        place_at.z, place_vz = smooth(place_at.z, hz, place_vz, dt)
        local left = math.sqrt((hx - place_at.x) ^ 2 + (hz - place_at.z) ^ 2)
        local speed = math.sqrt(place_vx * place_vx + place_vz * place_vz)
        if PLACE.dead_cm > 0.0 and left < PLACE_SETTLE_M and speed < PLACE_SETTLE_SPEED then place_moving = false end
    else
        place_vx, place_vz = 0.0, 0.0
    end
    -- "Behind" is behind the BODY, not behind the head. Worn 13:4x with the head's: Tefa: "when i look left and
    -- right with my head still, just rotating ... ethan's whole body seems to move in the opposite direction, it is
    -- subtle". That was this: the back shift (and the loader's own look-down shift, which uses the rotation handed
    -- to it) swung round with the head, 10 cm at the end of it. So the rotation is turned back by (head - body),
    -- the same angle the stick is turned by, before it is used here and handed on.
    -- Worn 13:5x with everything behind the body: Tefa: "when i look down at Ethan's body, and look left, the body
    -- now shifts to the right, but like it has a dead zone now before it does it". Read: the headset is the EYES,
    -- about a hand's width in front of the neck the head turns on, so a head turned left carries the eyes left; the
    -- hips belong under the NECK. So two shifts: neck_cm behind the HEAD (eyes -> neck: this one must turn with the
    -- head, it is what keeps the hips still under a turning head), then back_cm behind the BODY (Tefa's "body
    -- back", which must not swing with the head).
    local off = arr:read_float(ARRAY_DATA_AT + S_MOVE_TURN * 4)
    if off ~= nil and off == off and math.abs(off) > 0.0005 then
        rot = Quaternion.new(math.cos(-off * 0.5), 0.0, math.sin(-off * 0.5), 0.0) * rot
    end
    local back = rot * BACK
    local bl = math.sqrt(back.x * back.x + back.z * back.z)
    local bx, bz = 0.0, 0.0
    if bl > 0.001 then bx, bz = back.x / bl * PLACE.back_cm * 0.01, back.z / bl * PLACE.back_cm * 0.01 end
    local tx, tz = place_at.x + bx, place_at.z + bz          -- the place handed over, from the player's own spot
    -- THE LEAN FIX (native/src/leanfix.h): the plugin measured, on the body as it was drawn, how far a motion
    -- leaned the neck toward the eyes, and asks for the body to sit that far back, behind the HEAD (the direction
    -- it measured in). What was used goes back to it, so it knows what the next picture already holds.
    -- 2026-11-26 late, Tefa with "lean": 1: "it works ... after running the body does go back a bit too much":
    -- `lean` is a strength now (0 = measures only, 1 = all of it, 0.6 = 60% of what the plugin asks).
    if PLACE.lean > 0.01 and hl > 0.001 then
        local lean = arr:read_float(ARRAY_DATA_AT + S_LEAN * 4)
        -- 2026-11-26 late: both ways. A negative ask = the motion swung the body BACK, so it sits further forward.
        if lean ~= nil and lean == lean and lean ~= 0.0 and math.abs(lean) < 0.45 then
            lean = lean * math.min(lean > 0.0 and PLACE.lean or (PLACE.lean_back or PLACE.lean), 1.0)
            tx, tz = tx + head_back.x / hl * lean, tz + head_back.z / hl * lean
            w(S_LEAN_APPLIED, lean)
        end
    end
    -- SECOND DESIGN, 2026-11-26 17:1x. The first one took the Head joint for the head: in VR that joint read 72 cm
    -- off while Tefa stood still, and the body was dragged 63 cm back ("ethan is like more than 50cm befing me").
    -- Now nothing is assumed about where the joint sits: while the player stands still its offset from the place
    -- the loader aims at is LEARNED (in the body's own front / side, so turning does not change it), and only what
    -- a motion adds on top of that is taken out. Nothing is corrected before the offset is learned; never more
    -- than PIN_MAX_M.
    if PLACE.pin > 0.5 and bl > 0.001 then
        if pin_for ~= player_tf then
            pin_for, pin_x, pin_z, pin_base, pin_still, pin_last = player_tf, 0.0, 0.0, nil, 0, nil
            pin_joint, pin_name = nil, "none"
            for _, name in ipairs(PIN_JOINTS) do
                local j = player_tf:call("getJointByName", name)
                if j ~= nil then pin_joint, pin_name = j, name break end
            end
            log.info(TAG .. " body pin: watching the joint " .. pin_name)
        end
        if pin_joint ~= nil then
            local kx, kz = back.x / bl, back.z / bl                 -- behind the body, level
            local sx, sz = kz, -kx                                  -- to its side
            local shift = PIN_LOOKDOWN * math.abs(back.y) - PIN_FORWARD   -- the loader's own shifts, along "behind"
            local h = pin_joint:call("get_Position")
            -- the joint from the place aimed at, our own correction taken out again
            local rx, rz = (h.x - base.x) - pin_x - (tx + kx * shift), (h.z - base.z) - pin_z - (tz + kz * shift)
            local r_back, r_side = rx * kx + rz * kz, rx * sx + rz * sz
            local moved = pin_last == nil or math.abs(base.x - pin_last.x) + math.abs(base.z - pin_last.z) > 0.002
            pin_last = { x = base.x, z = base.z }
            pin_still = moved and 0 or pin_still + 1
            if math.abs(r_back) > PLACE_JUMP_M or math.abs(r_side) > PLACE_JUMP_M * 2 then
                pin_x, pin_z = 0.0, 0.0                              -- a teleport or a load: start again
            elseif pin_base == nil then
                if pin_still > PIN_LEARN_FRAMES then
                    pin_base = { back = r_back, side = r_side }
                    log.info(TAG .. string.format(" body pin: standing, the joint sits %.0f cm behind and %.0f cm beside the aim; leans are measured from here", r_back * 100.0, r_side * 100.0))
                end
            else
                if pin_still > PIN_ADAPT_FRAMES then                 -- standing for a while: the standing offset drifts with the pose
                    pin_base.back = pin_base.back + (r_back - pin_base.back) * PIN_ADAPT
                    pin_base.side = pin_base.side + (r_side - pin_base.side) * PIN_ADAPT
                end
                local l_back, l_side = r_back - pin_base.back, r_side - pin_base.side
                local wx, wz = -(l_back * kx + l_side * sx), -(l_back * kz + l_side * sz)
                pin_x, pin_z = pin_x + (wx - pin_x) * PIN_GAIN, pin_z + (wz - pin_z) * PIN_GAIN
                local pl = math.sqrt(pin_x * pin_x + pin_z * pin_z)
                if pl > PIN_MAX_M then pin_x, pin_z = pin_x / pl * PIN_MAX_M, pin_z / pl * PIN_MAX_M end
                pin_frames = pin_frames + 1
                local lean = math.sqrt(l_back * l_back + l_side * l_side)
                if lean > pin_peak then pin_peak = lean end
                if pin_frames % 180 == 0 then
                    if pin_peak > 0.06 then
                        log.info(TAG .. string.format(" body pin: a motion leaned the joint up to %.0f cm in the last 2 s; now %.0f cm back, %.0f cm side; the body is moved %.0f cm", pin_peak * 100.0, l_back * 100.0, l_side * 100.0, pl * 100.0))
                    end
                    pin_peak = 0.0
                end
            end
        end
    else
        pin_x, pin_z = 0.0, 0.0
    end
    re8vr:update_body_ik(rot, Vector4f.new(base.x + tx + pin_x, cam.y, base.z + tz + pin_z, 1.0))
end

-- THE "CUTSCENE" THAT IS NO SCENE (2026-11-26, measured). Tefa: "when i run and stop, Ethan's whole body get's
-- pushed forward so for less than a second i'm looking through his body, like from the centre of it"; "cutscenes
-- still end with the torso being pushed forward a little". The recorder (native/src/leanrec.h), three stops from
-- a run: the neck went from 17 cm behind the eyes to 9 cm IN FRONT of them, and each time the loader's cutscene
-- flag was up [measured 2026-11-26, n=3 stops; kept log re8-2026-11-26-1735-b185]. Why [read, RE8VR.cpp
-- update_player / update_body_ik]: the flag is "the camera controller is not the fully controllable one", and it
-- stays up one second longer; while it is up the loader takes the body's placing away (centre offset 0), so the
-- body jumps to where the game has it: under the eyes. The game switches that controller for a moment when a run
-- stops, and the extra second follows every real scene.
-- So: when the flag is up and the game runs NO event (no _GameEventAction), it is no scene: the body's place and
-- the body's turn carry on. The flag is put down only around our own call of the loader's body placing, and put
-- back as it was. A real scene (an event runs) is left to the loader as before.
local blip_was, blip_count = nil, 0
local function event_name()
    local c = re8vr.game_event_action_controller
    if c == nil then return nil end
    local ok, action = pcall(c.get_field, c, "_GameEventAction")
    if not ok or action == nil then return nil end
    local ok2, name = pcall(action.get_field, action, "_EventName")
    return (ok2 and name ~= nil and tostring(name)) or "?"
end


-- THE CAMERA OFFSET THROUGH A BLIP (2026-11-26 night, RE8-098). Tefa: "after the vault, just before i get camera
-- handed back to me, i see a quick flick of what seems to be the view from the chest area outwards ... the same
-- flick happens when jumping down from a ledge or climbing up one, right after i get control back". The walk
-- file of 23:27: about 0.8 s after every landing the eyes jump 17 to 19 cm against the body in ONE picture, and
-- the body takes five pictures to follow. Read in the loader (RE8VR::fix_player_camera): it adds the game's
-- PostureParam.CameraOffset (level part) to the camera ONLY while the camera's type is 0, so the offset drops out
-- when a jump, a climb, a vault or a running stop takes the camera, and snaps back in when it is handed back.
-- Here, right after the loader's camera fix: with the type not 0 and NO event running, the same offset is added
-- to what the loader set (the drawn joint and the transform). A real scene is left alone. Every change of the
-- camera's type is logged with the offset's size, so the next log says whether the sum is right.
local cam_type_was, cam_type_told = nil, 0
local GLIDE_S = 0.12          -- the taken-out jump fades with this time constant (gone in about three of them)
local GLIDE_MIN_M, GLIDE_MAX_M = 0.055, 0.60   -- smaller is nothing; bigger is a teleport, left alone
local GLIDE_WINDOW_FRAMES = 4
local glide_x, glide_z, glide_was, glide_kind, glide_t, glide_told = 0.0, 0.0, nil, nil, nil, 0
local camoff_error_told = false
local function camera_offset_step(player_camera, blip)
    local solver = player_camera:get_field("BaseTransSolver")
    local t = solver and solver:get_field("<currentType>k__BackingField")
    local kind = t and t:get_field("Value")
    if kind == nil then return end
    local pc = player_camera:get_field("_CurrentParamContainer") or player_camera:get_field("CurrentParamContainer")
    local pp = pc and pc:get_field("PostureParam")
    local o = pp and pp:get_field("CameraOffset")
    local on = (PLACE.camoff or 0.0) > 0.5
    if kind ~= cam_type_was then
        cam_type_told = cam_type_told + 1
        if cam_type_told <= 80 then
            log.info(string.format("%s camera type %s -> %s (%s); the game's camera offset: %s; kept on: %s", TAG, tostring(cam_type_was),
                tostring(kind), blip and "no event" or (re8vr.is_in_cutscene and "a real scene" or "play"),
                o and string.format("%.1f cm level (x %.3f, y %.3f, z %.3f)", math.sqrt(o.x * o.x + o.z * o.z) * 100.0, o.x, o.y, o.z) or "not found",
                on and "glide" or "no"))
        end
        cam_type_was = kind
    end
end

-- THE CAMERA GLIDE (2026-11-27 00:1x, RE8-098), fourth design; the first three are in the notes (2026-11-26f).
-- What was measured (probe, six hand-overs): through a running stop, a jump, a climb or a vault the game's camera
-- drifts 28 to 43 cm off the player's spot and comes back in ONE picture (20 to 33 cm), a picture before the
-- camera's type goes back to 0; then the loader's own offset (8.3 cm, added only at type 0) snaps in as well.
-- Third design: the jump was taken out AFTER the loader's camera fix, on the joint and the transform. Tefa: the
-- flicker is gone, "camera like starts from just tiny bit further away and comes closer to me" (the glide, as
-- meant), but "hands still jank back a little ... like a quick pull-back": the loader's hands are solved from a
-- camera that did not hold the shift (17 cm against the controllers on the hand-over picture, walk file 23:57).
-- So the shift goes in BEFORE the loader's camera fix, on the position the loader reads as the game's camera:
-- everything the loader works out from it (the drawn camera, the hands, the body's place) then agrees.
-- re8_vr.lua calls this right before re8vr:fix_player_camera. bodyplace.json "camoff": 0 switches it off.
local function glide_reset() glide_x, glide_z, glide_was = 0.0, 0.0, nil end
function B.camera_pre(player_camera)
    if (PLACE.camoff or 0.0) <= 0.5 or not vrmod:is_hmd_active() or not vrmod:is_using_controllers() then glide_reset() return end
    if event_name() ~= nil or re8vr.is_arm_jacked then glide_reset() return end       -- a real scene: left alone
    local solver = player_camera:get_field("BaseTransSolver")
    local t = solver and solver:get_field("<currentType>k__BackingField")
    local kind = t and t:get_field("Value")
    local camera, player_tf = sdk.get_primary_camera(), re8vr.transform
    if kind == nil or camera == nil or player_tf == nil then glide_reset() return end
    local cam_tf = camera:call("get_GameObject"):call("get_Transform")
    local cp, pp2 = cam_tf:call("get_Position"), player_tf:call("get_Position")
    -- where the loader will put the camera: the game's spot, plus the game's level offset while the type is 0
    local ex, ez = cp.x, cp.z
    if kind == 0 then
        local pc = player_camera:get_field("_CurrentParamContainer") or player_camera:get_field("CurrentParamContainer")
        local pp = pc and pc:get_field("PostureParam")
        local o = pp and pp:get_field("CameraOffset")
        if o ~= nil then
            local off = cam_tf:call("get_Rotation") * Vector3f.new(o.x, 0.0, o.z)
            ex, ez = ex + off.x, ez + off.z
        end
    end
    local dx, dz = ex - pp2.x, ez - pp2.z                     -- the camera against the player's spot, level
    local now = os.clock()
    local dt = glide_t and math.min(0.1, math.max(0.0005, now - glide_t)) or 0.011
    glide_t = now
    -- a one-picture jump against the player's spot counts when the camera itself moved that far in the world (at a
    -- landing the player's spot is pulled a metre under a camera that stays put: the spot moving, left alone)
    if glide_was ~= nil then
        local jx, jz = dx - glide_was.x, dz - glide_was.z
        local size = math.sqrt(jx * jx + jz * jz)
        local wx, wz = ex - glide_was.wx, ez - glide_was.wz
        local moved = math.sqrt(wx * wx + wz * wz)
        if size > GLIDE_MIN_M and size < GLIDE_MAX_M and moved > GLIDE_MIN_M then
            glide_x, glide_z = glide_x - jx, glide_z - jz
            glide_told = glide_told + 1
            if glide_told <= 120 then
                log.info(string.format("%s camera glide: type %s, the camera jumped %.1f cm against the player in one picture; taken out over %.2f s (now held: %.1f cm)", TAG, tostring(kind), size * 100.0, GLIDE_S * 3.0, math.sqrt(glide_x * glide_x + glide_z * glide_z) * 100.0))
            end
        end
    end
    glide_was = { x = dx, z = dz, wx = ex, wz = ez }
    local keep = math.exp(-dt / GLIDE_S)
    glide_x, glide_z = glide_x * keep, glide_z * keep
    if math.abs(glide_x) + math.abs(glide_z) < 0.001 then glide_x, glide_z = 0.0, 0.0 return end
    cam_tf:call("set_Position", Vector3f.new(cp.x + glide_x, cp.y, cp.z + glide_z))
end

-- THE SHOULDERS HELD STILL (2026-11-27 00:3x, RE8-096), a first try, switched by bodyplace.json "shoulders".
-- Tefa at a running stop: "hands still jank back a little ... a quick pull-back", "more teleporty than not ... and
-- then sort of smooth out". The walk file (00:06, eight stops): the wrists stay within 3 cm of the controllers, but
-- the ELBOWS pop 2 to 6 cm in one picture when the motion changes (run -> stop, stop -> idle about 0.6 s later,
-- idle -> run), the body's place steady. The loader puts the arm's own three joints in a set pose before it
-- solves the hand, so what still comes from the motion is the collar bone above them. Here both collar bones are
-- put in the pose they had while the player STOOD (learned in play), right before the loader's last hand solve
-- (re8_vr.lua, PrepareRendering pre; our own joint writer runs after it, which would drag the hands). Script
-- because of that order; if it works it is rebuilt in the plugin with a call at the same place.
local SHOULDER_NAMES = { "L_Shoulder", "R_Shoulder" }
local SHOULDER_LEARN_S = 0.7
local sh_owner, sh_joints, sh_ref, sh_still_since, sh_told = nil, {}, {}, nil, false
function B.pre_hands()
    if (PLACE.shoulders or 0.0) <= 0.5 then return end
    local tf = re8vr.transform
    if tf == nil or not re8vr.can_use_hands or not vrmod:is_hmd_active() or not vrmod:is_using_controllers() then return end
    if event_name() ~= nil or re8vr.is_arm_jacked then return end                    -- a real scene: the game's
    if sh_owner ~= tf then
        sh_owner, sh_joints, sh_ref, sh_still_since, sh_told = tf, {}, {}, nil, false
        for i, name in ipairs(SHOULDER_NAMES) do sh_joints[i] = tf:call("getJointByName", name) end
    end
    if sh_joints[1] == nil or sh_joints[2] == nil then return end
    -- learning: the stick at rest and no blip for SHOULDER_LEARN_S, once per player object
    if sh_ref[1] == nil then
        local sx = arr:read_float(ARRAY_DATA_AT + S_STICK_X * 4) or 1.0
        local sy = arr:read_float(ARRAY_DATA_AT + S_STICK_Y * 4) or 1.0
        local still = math.abs(sx) + math.abs(sy) < 0.05 and blip_was == nil
        local now = os.clock()
        if not still then sh_still_since = nil return end
        if sh_still_since == nil then sh_still_since = now end
        if now - sh_still_since < SHOULDER_LEARN_S then return end
        for i = 1, 2 do sh_ref[i] = sh_joints[i]:call("get_LocalRotation") end
        if not sh_told then sh_told = true log.info(TAG .. " shoulders: the standing pose is learned; held from here") end
    end
    for i = 1, 2 do sh_joints[i]:call("set_LocalRotation", sh_ref[i]) end
end

-- NO RUNNING-STOP MOTION (2026-11-27 00:4x, RE8-096/097), a first try, bodyplace.json "runend_threshold".
-- Tefa: "can we just eliminate these animations as we did with re2". The walk file (00:12, ten stops): on the
-- picture the player's motion goes from 1 (run) to 2 (the stop) the body pops 3 cm against the eyes, an elbow 4 to
-- 5 cm and the right hand 3 cm off its controller; the collar bones held still changed nothing ("no difference").
-- The stop is app.PlayerMovement.processRunEnd, and the class asks get_JogEndThreshold() to decide on it [read in
-- the type database, no game]. RE2's fix was the same idea (the jog mode hook). Here the getter's answer is
-- replaced with the number from the file while the headset and the controllers are in use; no number = the
-- game's own. Which way the threshold works is NOT known: the first answer the game gives is logged, and the
-- number can be changed while Tefa plays.
-- SECOND TRY, 00:5x: the getter is never called (two stops, no line): the game reads the number itself. It is a
-- field, app.PlayerMovementConfiguration...Base.JogEndThreshold, reached from the movement object's get_config().
-- The movement object is caught as `this` of processMove (runs while the player moves); the field is written there
-- when the file gives a number, and put back to the game's own when the number is taken out of the file.
do
    local cfg_told, own, set_to = false, nil, nil
    local ok, e = pcall(function()
        local m = sdk.find_type_definition("app.PlayerMovement"):get_method("processMove")
        sdk.hook(m, function(args)
            local okh, eh = pcall(function()
                local this = sdk.to_managed_object(args[2])
                if this == nil then return end
                local cfg = this:call("get_config")
                if cfg ~= nil then cfg = cfg:get_field("playerMovementConfig") end
                if cfg == nil then return end
                local now = cfg:get_field("JogEndThreshold")
                if not cfg_told then
                    cfg_told = true
                    own = now
                    log.info(string.format("%s run end: the movement settings are a %s; the game's own: JogEndThreshold %s, DeccelSec %s, AccelSec %s, WalkSpeed %s, SprintSpeed %s", TAG,
                        cfg:get_type_definition():get_full_name(), tostring(now), tostring(cfg:get_field("DeccelSec")), tostring(cfg:get_field("AccelSec")),
                        tostring(cfg:get_field("WalkSpeed")), tostring(cfg:get_field("SprintSpeed"))))
                end
                local want = PLACE.runend
                if want ~= nil and vrmod:is_hmd_active() and vrmod:is_using_controllers() then
                    if now ~= want then cfg:set_field("JogEndThreshold", want) end
                    if set_to ~= want then set_to = want log.info(string.format("%s run end: JogEndThreshold set to %.3f (the game's own %s)", TAG, want, tostring(own))) end
                elseif set_to ~= nil and own ~= nil then
                    cfg:set_field("JogEndThreshold", own)
                    set_to = nil
                    log.info(TAG .. " run end: JogEndThreshold back to the game's own " .. tostring(own))
                end
            end)
            if not okh and not cfg_told then cfg_told = true log.info(TAG .. " run end: failed inside the hook: " .. tostring(eh)) end
        end, function(retval) return retval end)
    end)
    log.info(TAG .. " run end: the hook on the player's move step " .. (ok and "is in" or ("FAILED: " .. tostring(e))))
end

function B.camera_step(player_camera)
    local blip = false
    if re8vr.is_in_cutscene then
        local event = event_name()
        blip = event == nil and not re8vr.is_arm_jacked
        local now = blip and "no scene" or ("scene " .. tostring(event))
        if now ~= blip_was then
            blip_was = now
            blip_count = blip_count + 1
            if blip_count <= 60 then
                log.info(TAG .. " the loader's cutscene flag is up: " .. (blip and "no event runs, so the body's place and turn carry on" or ("a real scene (" .. tostring(event) .. "), left to the loader")))
            end
        end
    else
        blip_was = nil
    end
    local okc, ec = pcall(camera_offset_step, player_camera, blip)
    if not okc and not camoff_error_told then
        camoff_error_told = true
        log.info(TAG .. " camera offset: failed, left to the loader: " .. tostring(ec))
    end
    if (re8vr.is_in_cutscene and not blip) or not vrmod:is_hmd_active() then wb(S_TURN_OK, false) return end
    local solver = player_camera:get_field("BaseTransSolver")
    local c = solver and (solver:get_field("CurrentController") or solver:get_field("<CurrentController>k__BackingField"))
    if c == nil then wb(S_TURN_OK, false) return end
    local head = yaw_of(c:get_field("<Rotation>k__BackingField"))
    w(S_HEAD_YAW, head)
    w(S_BASE_YAW, head - yaw_of(vrmod:get_rotation(0):to_quat()))
    turn_stamp = (turn_stamp + 1) % 1000000
    w(S_TURN_STAMP, turn_stamp)
    wb(S_TURN_OK, true)
    if SCRIPTBODY_OFF then return end          -- the halving test: the loader's own placing stands
    if blip then pcall(function() re8vr.is_in_cutscene = false end) end
    local ok, e = pcall(body_place)
    -- 2026-11-26 late (RE8-096), bodyplace.json "blip": 1: the flag STAYS down for the rest of the frame, so the
    -- loader's hands (which read it later) stay on the controllers through a running stop and the second after it.
    -- Tefa: "when stopping running, then hands do this second long animation that should not be there". The loader
    -- raises the flag again in its camera fix every frame, so this is decided anew each frame. 0 = put back up.
    if blip and (PLACE.blip or 0.0) <= 0.5 then pcall(function() re8vr.is_in_cutscene = true end) end
    if not ok and not body_error_told then
        body_error_told = true
        log.info(TAG .. " body place: failed, the loader's own placing stands: " .. tostring(e))
    end
end

-- STEPS INSTEAD OF SLIDING (2026-11-26). Tefa: "when i look down and lean left or right, feet just drag along the
-- floor with roomscale i think, Ethan doesn't take a sidestep left or right, or a little step forward or back, he
-- just slides on the floor following the headset".
-- Why they drag [read, re8_vr.lua's UnlockScene block]: when the headset is off its standing origin the loader's
-- script moves the origin a little toward the headset every frame and SETS the player's position by the same
-- amount: the player is slid, no walk motion plays.
-- What this does instead (the loader's block asks room_step first and leaves its slide out while this is on):
-- up to step_start_cm the player is not moved at all (the body's place above leans the hips over planted feet);
-- past it, with the left stick at rest, the stick is pushed toward the headset (in the head's own left/right and
-- forward/back, then through turned_stick like a real push), so the GAME walks the player there with its own
-- step motions and its own collision; every frame the origin is moved toward the headset by as far as the player
-- really went, so the view never moves. It stops within step_stop_cm, or after STEP_GIVE_UP_S without getting
-- there (a table, a wall), and then waits until the head is back near.
local STEP_GIVE_UP_S = 1.5
local STEP_STICK_REST = 0.15          -- the real left stick under this: at rest
local STEP_FRAME_MAX_M = 0.2          -- the player moved more than this in a frame: a teleport, not a step
local step_on, step_blocked, step_since = false, false, 0.0
local step_x, step_y = 0.0, 0.0       -- the push, in the head's frame (x right, y forward)
local step_last = nil
local step_count = 0
local step_neck = nil               -- the "eyes to neck" arrow when the head was last at the origin

function B.room_step()
    wb(S_STEP_ON, step_on)
    if SCRIPTBODY_OFF or PLACE.steps < 0.5 then step_on = false step_last = nil return false end
    local origin, hmd = vrmod:get_standing_origin(), vrmod:get_position(0)
    -- The NECK's way off, not the eyes' (worn 14:08: Tefa: "there is still a dead zone after which the body smoothly
    -- but quickly jumps to the opposite side"; the log: a step started while he only turned his head, looking
    -- down). The eyes swing round the neck when the head turns; the neck stays. So the eyes' way off the origin is
    -- corrected by how far the "eyes to neck" arrow has swung since the last time the head was at the origin.
    local m = vrmod:get_rotation(0)
    local kx, kz = m[2].x, m[2].z                       -- the headset's own "behind", level (its space: +Z is behind)
    local kl = math.sqrt(kx * kx + kz * kz)
    if kl > 0.001 then kx, kz = kx / kl * PLACE.neck_cm * 0.01, kz / kl * PLACE.neck_cm * 0.01 else kx, kz = 0.0, 0.0 end
    if step_neck == nil then step_neck = { x = kx, z = kz } end
    local function way_off()
        local x, z = hmd.x - origin.x + kx - step_neck.x, hmd.z - origin.z + kz - step_neck.z
        return x, z, math.sqrt(x * x + z * z)
    end
    local ox, oz, dist = way_off()
    local pos = re8vr.transform:call("get_Position")
    if step_on and step_last ~= nil and dist > 0.0001 then
        local mx, mz = pos.x - step_last.x, pos.z - step_last.z
        local went = math.sqrt(mx * mx + mz * mz)
        if went > 0.0 and went < STEP_FRAME_MAX_M then
            -- as far as the player really went, also when that is a little past the head (the game's walk does not
            -- stop on the centimetre): the view must not move by the difference
            local k = went / dist
            origin.x, origin.z = origin.x + ox * k, origin.z + oz * k
            vrmod:set_standing_origin(origin)
            ox, oz, dist = way_off()
        end
    end
    step_last = { x = pos.x, z = pos.z }
    local now = os.clock()
    if step_blocked then
        if dist < PLACE.step_stop_cm * 0.01 then step_blocked = false end
        step_on = false
    elseif not step_on and dist > PLACE.step_start_cm * 0.01 then
        step_on, step_since = true, now
        step_count = step_count + 1
        if step_count <= 20 or step_count % 50 == 0 then
            log.info(TAG .. string.format(" steps: a step starts, the head is %.0f cm off (number %d)", dist * 100.0, step_count))
        end
    elseif step_on and dist < PLACE.step_stop_cm * 0.01 then
        step_on = false
        -- the step is done: what is left of the way off is taken as "at the origin" for the neck's arrow
        step_neck = { x = kx, z = kz }
    elseif step_on and now - step_since > STEP_GIVE_UP_S then
        step_on, step_blocked = false, true
        log.info(TAG .. string.format(" steps: gave up after %.1f s, still %.0f cm off (something is in the way)", STEP_GIVE_UP_S, dist * 100.0))
    end
    if step_on and dist > 0.0001 then
        -- the headset's own right and forward, level (its space: +X right, -Z forward)
        local rx, rz, fx, fz = m[0].x, m[0].z, -m[2].x, -m[2].z
        local rl, fl = math.sqrt(rx * rx + rz * rz), math.sqrt(fx * fx + fz * fz)
        if rl > 0.001 and fl > 0.001 then
            step_x = (ox * rx + oz * rz) / (dist * rl) * PLACE.step_push
            step_y = (ox * fx + oz * fz) / (dist * fl) * PLACE.step_push
        else
            step_on = false
        end
    end
    return true
end

-- the game's own arms are showing (Rose is carried): decided by the plugin (native/src/gamearms.h). re8_vr.lua's
-- update_hand_ik asks this and leaves the arms to the game's motions.
function B.game_arms()
    local v = arr:read_float(ARRAY_DATA_AT + S_GAME_ARMS * 4)
    return v ~= nil and v > 0.5
end

-- for the dev recorder: how far the head is turned off the body, radians
function B.head_off() return arr:read_float(ARRAY_DATA_AT + S_MOVE_TURN * 4) end

-- the left stick, turned so that stick forward walks where the head looks (re8_vr.lua, at its set_AxisL)
function B.turned_stick(axis)
    if step_on and math.abs(axis.x) < STEP_STICK_REST and math.abs(axis.y) < STEP_STICK_REST then
        axis = Vector2f.new(step_x, step_y)
    end
    local a = arr:read_float(ARRAY_DATA_AT + S_MOVE_TURN * 4)
    if a == nil or a ~= a or math.abs(a) < 0.001 then w(S_STICK_X, axis.x) w(S_STICK_Y, axis.y) return axis end
    local s, co = math.sin(a), math.cos(a)
    w(S_STICK_X, axis.x * co - axis.y * s) w(S_STICK_Y, axis.y * co + axis.x * s)
    -- which way round: worn 2026-11-26 12:2x with the other sign, Tefa: "when i look left ethan seems to move
    -- diagonally more to the right, and left when i look right". So this one.
    return Vector2f.new(axis.x * co - axis.y * s, axis.y * co + axis.x * s)
end

log.info(TAG .. " loaded: the array is ready" .. (SCRIPTBODY_OFF and "; SCRIPTBODY OFF (scriptbody-off.json): the loader places the body and slides it" or ""))
