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
    return string.format("camera y %s | head joint y %s | GAP camera-head %s m | body root y %s | IkLeg %s enabled %s centre-offset y %s | right IK target y %s, hand joint y %s, target-hand %s m",
        num(cam_y), num(head_y), num(gap), num(root_y), ik and "present" or "MISSING", tostring(ik_on), num(ik_off and ik_off.y),
        num(rt and rt.y), num(rhand_y), num(reach))
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
