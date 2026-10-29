-- visceral_re8_bodyprobe.lua -- does REFramework lift the body to the camera? (2026-10-30, Fable; Tefa: the gun sits low
-- and "the whole IK system is weird and janky, elbows don't work right", every launch now, a long-standing REFramework thing)
--
-- Read in REFramework's own code (src/mods/vr/games/RE8VR.cpp, update_body_ik / update_hand_ik):
-- - The camera is NOT attached to the body. Every frame the body is dragged to the camera through via.motion.IkLeg:
--   CenterOffset = camera position - the head joint's T-pose position (CenterPositionCtrl 2 = world offset,
--   GroundContactUpDistance 0). If IkLeg is missing it is created; with no controllers it is zeroed and destroyed.
-- - The hands are aimed at the controllers FROM THE CAMERA (hand IK targets = camera + controller offset), then the game's
--   arm IK pulls the hand joints to them. So if the body is not lifted all the way, the shoulders sit far below the
--   targets, the arms stretch, the hands stop short BELOW the targets and the elbows go wrong `[inferred-static 2026-10-30]`.
--
-- This probe logs, every 5 s and to its own per-launch file (reframework/data/visceral_re8/bodyprobe-<date>-<time>.txt):
--   camera y, head joint y, the gap (camera - head: should be ~0 when the body is lifted), the body root y,
--   IkLeg present / enabled / CenterOffset y, and for the right hand: the IK target y vs the hand joint y.
-- Read-only: it changes nothing.
local TAG = "[visceral-re8-bodyprobe]"
local EVERY_S = 5.0
local last, lines, path = 0, {}, nil

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function num(v) return type(v) == "number" and string.format("%.3f", v) or "?" end

local function joint_y(transform, name)
    local j = safe(function() return transform:call("getJointByName", name) end)
    if not j then return nil end
    local p = safe(function() return j:call("get_Position") end)
    return p and p.y or nil
end

local function probe()
    local re8vr = rawget(_G, "re8vr")
    if not re8vr or not re8vr.player or not re8vr.transform then return "no player yet" end
    local tf = re8vr.transform
    local cam = sdk.get_primary_camera()
    local cam_y = cam and safe(function() return cam:call("get_GameObject"):call("get_Transform"):get_position().y end) or nil
    local root_y = safe(function() return tf:get_position().y end)
    local head_y = joint_y(tf, "Head")
    local rhand_y = joint_y(tf, "R_Hand") or joint_y(tf, "r_hand")
    local go = safe(function() return tf:call("get_GameObject") end)
    local ik = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.motion.IkLeg")) end) or nil
    local ik_on = ik and safe(function() return ik:call("get_Enabled") end)
    local ik_off = ik and safe(function() return ik:call("get_CenterOffset") end)
    local rt = re8vr.right_hand_ik and safe(function() return re8vr.right_hand_ik:call("get_GameObject"):call("get_Transform"):get_position() end) or nil
    local gap = (cam_y and head_y) and (cam_y - head_y) or nil
    local reach = (rt and rhand_y) and (rt.y - rhand_y) or nil
    -- 00:10 Tefa: "the gun and hand in game are both low compared to my real hand". REAL (headset tracking) vs GAME:
    -- the right controller's height below the eyes and its distance from the head, against the game hand joint's height
    -- below the camera and its distance from the camera. Equal = the height is kept; different = where it is lost.
    local real, game = "?", "?"
    local vr = rawget(_G, "vrmod")
    if vr then
        local ok, txt = pcall(function()
            local cs = vr:get_controllers()
            local hp = vr:get_position(0)
            local rp = vr:get_position(cs[2])
            local so = vr:get_standing_origin()
            local d = rp - hp
            -- 00:30: the 13 cm "low" state began at the headset's reference-space change (00:11:25) amid a burst of
            -- INTERACTION_PROFILE_CHANGED events: if the controller's pose frame swaps (grip vs aim pose, a fallback
            -- profile), praydog's hand offset projects differently and the hand tilts. So: the right controller's pitch
            -- and the headset's, to catch a frame swap as a sudden constant change while the hand is held still.
            local rq = vr:get_rotation(cs[2]):to_quat()
            local fwd = rq * Vector3f.new(0, 0, -1)
            local pitch = math.deg(math.asin(math.max(-1, math.min(1, fwd.y))))
            local hq = vr:get_rotation(0):to_quat()
            local hf = hq * Vector3f.new(0, 0, -1)
            local hpitch = math.deg(math.asin(math.max(-1, math.min(1, hf.y))))
            return string.format("ctrl below eyes %.2f m, from head %.2f m (origin y %.2f, hmd y %.2f; ctrl pitch %+.0f deg, head pitch %+.0f deg)", -d.y, d:length(), so.y, hp.y, pitch, hpitch)
        end)
        if ok then real = txt end
    end
    local rj = safe(function() local j = tf:call("getJointByName", "R_Hand") or tf:call("getJointByName", "r_hand"); return j and j:call("get_Position") end)
    local cp = cam and safe(function() return cam:call("get_GameObject"):call("get_Transform"):get_position() end) or nil
    if rj and cp then local d = rj - cp; game = string.format("hand below camera %.2f m, from camera %.2f m", -d.y, d:length()) end
    -- 00:12 Tefa says "low" while REAL and GAME agree: so is the VIEW drawn from the camera transform? The eye's render
    -- position (vrmod:get_last_render_matrix) against the camera transform: a view above the camera makes everything look low.
    if vr and cp then
        local ok, txt = pcall(function()
            local rm = vr:get_last_render_matrix()
            local v = rm[3]
            local lh = re8vr.last_right_hand_position
            return string.format("view y - camera y %+.2f m (view-camera distance %.2f m); praydog rh_pos y - camera y %+.2f", v.y - cp.y, (Vector3f.new(v.x, v.y, v.z) - cp):length(), lh and (lh.y - cp.y) or -99)
        end)
        game = game .. " | " .. (ok and txt or ("view ? " .. tostring(txt)))
    end
    -- 00:15: the hand is either ON its target or a fixed ~0.40 m short, flipping during one run: that is praydog's hand IK
    -- being SKIPPED, not failing. What can skip it: the Lua global __re8_arm_ik_update_override (re8_vr.lua line 616;
    -- set by the holster script's heal gesture), re8vr.can_use_hands false, has_vehicle, in_cutscene, or no controllers.
    local ov = rawget(_G, "__re8_arm_ik_update_override")
    local flags = string.format("override %s | can_use_hands %s | has_vehicle %s | in_cutscene %s | reloading %s | gripping %s",
        ov ~= nil and type(ov) or "none", tostring(safe(function() return re8vr.can_use_hands end)), tostring(safe(function() return re8vr.has_vehicle end)),
        tostring(safe(function() return re8vr.is_in_cutscene end)), tostring(safe(function() return re8vr.is_reloading end)), tostring(safe(function() return re8vr.was_gripping_weapon end)))
    return string.format("camera y %s | head joint y %s | GAP camera-head %s m | body root y %s | IkLeg %s enabled %s centre-offset y %s | right IK target y %s, hand joint y %s, target-hand %s m | REAL %s | GAME %s | %s",
        num(cam_y), num(head_y), num(gap), num(root_y), ik and "present" or "MISSING", tostring(ik_on), num(ik_off and ik_off.y),
        num(rt and rt.y), num(rhand_y), num(reach), real, game, flags)
end

re.on_pre_application_entry("BeginRendering", function()
    local now = os.clock()
    if now - last < EVERY_S then return end
    last = now
    local ok, text = pcall(probe)
    if not ok then text = "probe error: " .. tostring(text) end
    local line = os.date("%H:%M:%S") .. " " .. text
    log.info(TAG .. " " .. text)
    lines[#lines + 1] = line
    if not path then path = "visceral_re8/bodyprobe-" .. os.date("%Y-%m-%d-%H%M") .. ".txt" end
    pcall(function() fs.write(path, table.concat(lines, "\n") .. "\n") end)
end)
