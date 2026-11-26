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
local S_COUNT = 16

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
local PLACE = { dead_cm = 1.0, follow_s = 0.90, back_cm = 2.0, steps = 1.0, step_start_cm = 12.0, step_stop_cm = 6.0, step_push = 0.18, neck_cm = 9.0, pin = 0.0 }
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
    local d, fo, b = tonumber(f.dead_cm) or 1.0, tonumber(f.follow_s) or 0.90, tonumber(f.back_cm) or 2.0
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
    if blip then pcall(function() re8vr.is_in_cutscene = false end) end
    local ok, e = pcall(body_place)
    if blip then pcall(function() re8vr.is_in_cutscene = true end) end
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
    if PLACE.steps < 0.5 then step_on = false step_last = nil return false end
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
    if a == nil or a ~= a or math.abs(a) < 0.001 then return axis end
    local s, co = math.sin(a), math.cos(a)
    -- which way round: worn 2026-11-26 12:2x with the other sign, Tefa: "when i look left ethan seems to move
    -- diagonally more to the right, and left when i look right". So this one.
    return Vector2f.new(axis.x * co - axis.y * s, axis.y * co + axis.x * s)
end

log.info(TAG .. " loaded: the array is ready")
