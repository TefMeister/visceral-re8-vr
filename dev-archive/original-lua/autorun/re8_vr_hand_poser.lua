if reframework:get_game_name() ~= "re8" then
    return {}
end

local M = {}

local LEFT_HAND_BONES = {
    "L_IndexF1", "L_IndexF2", "L_IndexF3",
    "L_MiddleF1", "L_MiddleF2", "L_MiddleF3",
    "L_RingF1", "L_RingF2", "L_RingF3",
    "L_PinkyF1", "L_PinkyF2", "L_PinkyF3",
    "L_Thumb1", "L_Thumb2", "L_Thumb3",
}

local LOCAL_FROZEN = {}
local state = {
    xform = nil,
    src = "",
    capture_src = "",
    joints = {},
    joint_count = 0,
    rig_targets = {},
}

local sc_fn = nil
local collect_fn = nil

local function frozen_root()
    local g = rawget(_G, "frozen_joints")
    if type(g) == "table" then return g end
    return LOCAL_FROZEN
end

local function sc(obj, method, ...)
    if sc_fn then return sc_fn(obj, method, ...) end
    if not obj then return nil end
    local ok, val = pcall(function(...)
        return obj:call(method, ...)
    end, ...)
    if ok then return val end
    return nil
end

local function find_joint_on_tf(tf, bone_name)
    return sc(tf, "getJointByName", bone_name)
end

local function left_bone_to_right(left_bone)
    if type(left_bone) ~= "string" or left_bone:sub(1, 2) ~= "L_" then return nil end
    return "R_" .. left_bone:sub(3)
end

local function find_right_joint_for_left_bone(tf, left_bone)
    if not tf or not left_bone then return nil end
    local r_name = left_bone_to_right(left_bone)
    if r_name then
        return find_joint_on_tf(tf, r_name)
    end
    return nil
end

local function score_tf(tf)
    local n = 0
    for _, bone in ipairs(LEFT_HAND_BONES) do
        if find_joint_on_tf(tf, bone) then n = n + 1 end
    end
    return n
end

local function score_tf_right(tf)
    local n = 0
    for _, bone in ipairs(LEFT_HAND_BONES) do
        if find_right_joint_for_left_bone(tf, bone) then n = n + 1 end
    end
    return n
end

local function build_joint_map(tf)
    local map = {}
    for _, bone in ipairs(LEFT_HAND_BONES) do
        local j = find_joint_on_tf(tf, bone)
        if j then map[bone] = j end
    end
    return map
end

local function mirror_hand_euler(e, negate)
    if not e then return nil end
    negate = negate or {}
    local x = tonumber(e[1]) or 0.0
    local y = tonumber(e[2]) or 0.0
    local z = tonumber(e[3]) or 0.0
    if negate.x then x = -x end
    if negate.y then y = -y end
    if negate.z then z = -z end
    return { x, y, z }
end

local function src_priority(src)
    if src == "UpperBodyMesh" then return 110 end
    if src == "player" or src == "player_go" then return 105 end
    if src == "LArmMesh" then return 100 end
    if src == "RArmMesh" then return 50 end
    return 10
end

local function right_capture_priority(src)
    if src == "RArmMesh" then return 40 end
    if src == "UpperBodyMesh" then return 30 end
    if src == "player" or src == "player_go" then return 20 end
    if src == "LArmMesh" then return 5 end
    return 1
end

function M.init(deps)
    sc_fn = deps and deps.sc or nil
    collect_fn = deps and deps.collect_transforms or nil
    if type(rawget(_G, "frozen_joints")) ~= "table" then
        rawset(_G, "frozen_joints", LOCAL_FROZEN)
    end
end

function M.get_state()
    return state
end

function M.refresh_skeleton()
    pcall(function()
        local rf = rawget(_G, "__re8_holster_refresh_for_pose")
        if type(rf) == "function" then rf() end
    end)

    local best_tf, best_src, best_map, best_n, best_pri = nil, "", {}, 0, -1
    local rig_targets = {}
    local function consider(tf, src)
        if not tf then return end
        local n = score_tf(tf)
        local pri = src_priority(src or "")
        if n >= 3 then
            rig_targets[#rig_targets + 1] = {
                tf = tf,
                src = src or "?",
                joints = build_joint_map(tf),
                n = n,
            }
        end
        if n > best_n or (n == best_n and n >= 3 and pri > best_pri) then
            best_n = n
            best_pri = pri
            best_tf = tf
            best_src = src or "?"
            best_map = build_joint_map(tf)
        end
    end

    if collect_fn then
        local list = collect_fn()
        if type(list) == "table" then
            for _, entry in ipairs(list) do
                if entry and entry.tf then
                    consider(entry.tf, entry.src)
                end
            end
        end
    end

    state.xform = best_tf
    state.src = best_src
    state.joints = best_map
    state.joint_count = best_n
    state.rig_targets = rig_targets

    return best_n >= 3, best_n
end

local function read_euler(joint)
    if not joint then return nil end
    local e = sc(joint, "get_LocalEulerAngle")
    if e and type(e.x) == "number" then
        return { tonumber(e.x) or 0, tonumber(e.y) or 0, tonumber(e.z) or 0 }
    end
    local ok, rot = pcall(function() return joint:get_LocalRotation() end)
    if ok and rot then
        local eu = nil
        pcall(function()
            if rot.to_euler then eu = rot:to_euler() end
        end)
        if eu and type(eu.x) == "number" then
            return { tonumber(eu.x) or 0, tonumber(eu.y) or 0, tonumber(eu.z) or 0 }
        end
    end
    return nil
end

local function euler_to_emv_vec(e)
    return string.format("vec:%s %s %s",
        tostring(e[1] or 0), tostring(e[2] or 0), tostring(e[3] or 0))
end

local function parse_emv_vec(s)
    if type(s) ~= "string" then return nil end
    local nums = s:match("^vec:%s*(.+)$") or s:match("^vec:(.+)$")
    if not nums then return nil end
    local a, b, c = nums:match("([%-%d%.eE%+]+)%s+([%-%d%.eE%+]+)%s+([%-%d%.eE%+]+)")
    if not a then return nil end
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function rig_capture_priority(src)
    if src == "UpperBodyMesh" then return 30 end
    if src == "player" or src == "player_go" then return 20 end
    if src == "LArmMesh" then return 10 end
    if src == "RArmMesh" then return 5 end
    return 1
end

local function read_bone_euler_from_rigs(bone)
    local rigs = state.rig_targets
    if type(rigs) ~= "table" or #rigs == 0 then
        if state.xform and state.joints then
            rigs = { { tf = state.xform, src = state.src, joints = state.joints } }
        else
            return nil, nil
        end
    end
    local best_e, best_pri, best_src = nil, -1, ""
    for _, rig in ipairs(rigs) do
        local j = rig.joints and rig.joints[bone]
        local e = j and read_euler(j)
        if e then
            local pri = rig_capture_priority(rig.src)
            if pri > best_pri then
                best_pri = pri
                best_e = e
                best_src = rig.src or "?"
            end
        end
    end
    return best_e, best_src
end

local function sync_primary_joints_from_rig(src_want)
    if not src_want or type(state.rig_targets) ~= "table" then return end
    for _, rig in ipairs(state.rig_targets) do
        if rig.src == src_want then
            state.joints = rig.joints or build_joint_map(rig.tf)
            state.xform = rig.tf
            state.src = rig.src
            return
        end
    end
end

function M.capture_pl0000_pose()
    local ok, n = M.refresh_skeleton()
    if not ok or not state.xform then
        return nil, n or 0
    end

    local pose = {}
    local emv = {}
    local count = 0
    local src_used = {}
    for _, bone in ipairs(LEFT_HAND_BONES) do
        local e, src = read_bone_euler_from_rigs(bone)
        if e then
            pose[bone] = e
            emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(e) }
            count = count + 1
            src_used[src] = (src_used[src] or 0) + 1
        end
    end

    if count == 0 then
        return nil, 0
    end

    local primary_src = ""
    local primary_n = 0
    for src, c in pairs(src_used) do
        if c > primary_n then primary_n = c; primary_src = src end
    end
    state.capture_src = primary_src
    sync_primary_joints_from_rig(primary_src)

    return { pose = pose, emv = emv }, count
end

local function collect_tfs_for_right()
    local out = {}
    local seen = {}
    local function add(tf, src)
        if not tf then return end
        local key = tostring(src or "?")
        pcall(function()
            if tf.get_address then key = key .. ":" .. tostring(tf:get_address() or 0) end
        end)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { tf = tf, src = src or "?" }
    end
    if type(state.rig_targets) == "table" then
        for _, rig in ipairs(state.rig_targets) do
            if rig then add(rig.tf, rig.src) end
        end
    end
    if collect_fn then
        local list = collect_fn()
        if type(list) == "table" then
            for _, entry in ipairs(list) do
                if entry then add(entry.tf, entry.src) end
            end
        end
    end
    add(state.xform, state.src)
    return out
end

local function ang_wrap_deg(a)
    a = tonumber(a) or 0.0
    while a > 180.0 do a = a - 360.0 end
    while a < -180.0 do a = a + 360.0 end
    return a
end

local function ang_diff_deg(from_a, to_a)
    return ang_wrap_deg((tonumber(to_a) or 0.0) - (tonumber(from_a) or 0.0))
end

local function ang_add_deg(a, d)
    return ang_wrap_deg((tonumber(a) or 0.0) + (tonumber(d) or 0.0))
end

local function read_base_euler(joint)
    if not joint then return nil end
    local q = sc(joint, "get_BaseLocalRotation")
    if q and type(q.w) == "number" then
        local eu = nil
        pcall(function()
            if q.to_euler then eu = q:to_euler() end
        end)
        if eu and type(eu.x) == "number" then
            return { tonumber(eu.x) or 0, tonumber(eu.y) or 0, tonumber(eu.z) or 0 }
        end
    end
    return nil
end

local function same_tf_pair_priority(src)
    if src == "UpperBodyMesh" then return 100 end
    if src == "player" or src == "player_go" then return 90 end
    return 10
end

local function find_lr_joint_pair(left_bone)
    local best = nil
    local best_pri = -1
    for _, entry in ipairs(collect_tfs_for_right()) do
        local lj = find_joint_on_tf(entry.tf, left_bone)
        local rj = find_right_joint_for_left_bone(entry.tf, left_bone)
        if lj and rj then
            local pri = same_tf_pair_priority(entry.src) + right_capture_priority(entry.src)
            if pri > best_pri then
                best_pri = pri
                best = { tf = entry.tf, src = entry.src, left = lj, right = rj }
            end
        end
    end
    if best then return best end
    local left_j, left_src, right_j, right_src = nil, "", nil, ""
    local lp, rp = -1, -1
    for _, entry in ipairs(collect_tfs_for_right()) do
        local lj = find_joint_on_tf(entry.tf, left_bone)
        if lj then
            local pri = same_tf_pair_priority(entry.src)
            if pri > lp then lp = pri; left_j = lj; left_src = entry.src end
        end
        local rj = find_right_joint_for_left_bone(entry.tf, left_bone)
        if rj then
            local pri = right_capture_priority(entry.src)
            if pri > rp then rp = pri; right_j = rj; right_src = entry.src end
        end
    end
    if left_j and right_j then
        return {
            tf = nil,
            src = tostring(left_src) .. "+" .. tostring(right_src),
            left = left_j,
            right = right_j,
        }
    end
    return nil
end

local function transfer_right_pose_to_left_euler(left_bone, negate)
    local pair = find_lr_joint_pair(left_bone)
    if not pair then return nil, nil, "no_pair" end

    local r_cur = read_euler(pair.right)
    if not r_cur then return nil, pair.src, "no_r_cur" end

    local r_base = read_base_euler(pair.right)
    local l_base = read_base_euler(pair.left)
    local mode = "rest_delta"

    if r_base and l_base then
        local dx = ang_diff_deg(r_base[1], r_cur[1])
        local dy = ang_diff_deg(r_base[2], r_cur[2])
        local dz = ang_diff_deg(r_base[3], r_cur[3])
        local delta = mirror_hand_euler({ dx, dy, dz }, negate)
        return {
            ang_add_deg(l_base[1], delta[1]),
            ang_add_deg(l_base[2], delta[2]),
            ang_add_deg(l_base[3], delta[3]),
        }, pair.src, mode
    end

    mode = "quat_mirror"
    local rq = sc(pair.right, "get_LocalRotation")
    if rq and type(rq.w) == "number" then
        local mw = tonumber(rq.w) or 1
        local mx = tonumber(rq.x) or 0
        local my = -(tonumber(rq.y) or 0)
        local mz = -(tonumber(rq.z) or 0)
        if negate then
            if negate.x then mx = -mx end
            if negate.y then my = -my end
            if negate.z then mz = -mz end
        end
        local eu = nil
        pcall(function()
            local q = Quaternion.new(mw, mx, my, mz)
            if q.to_euler then eu = q:to_euler() end
        end)
        if eu and type(eu.x) == "number" then
            local x, y, z = tonumber(eu.x) or 0, tonumber(eu.y) or 0, tonumber(eu.z) or 0
            if math.abs(x) <= 3.2 and math.abs(y) <= 3.2 and math.abs(z) <= 3.2 then
                return { math.deg(x), math.deg(y), math.deg(z) }, pair.src, mode
            end
            return { x, y, z }, pair.src, mode
        end
    end

    mode = "absolute"
    return mirror_hand_euler(r_cur, negate), pair.src, mode
end

function M.capture_pl0000_pose_from_right_mirrored(opts)
    opts = opts or {}
    local negate = opts.negate or { x = false, y = false, z = false }
    local ok, n = M.refresh_skeleton()
    local tfs = collect_tfs_for_right()
    local right_n = 0
    for _, entry in ipairs(tfs) do
        local sn = score_tf_right(entry.tf)
        if sn > right_n then right_n = sn end
    end
    if right_n < 3 and (not ok or not state.xform) then
        return nil, right_n
    end

    local pose = {}
    local emv = {}
    local count = 0
    local src_used = {}
    local mode_used = {}
    for _, bone in ipairs(LEFT_HAND_BONES) do
        local e, src, mode = transfer_right_pose_to_left_euler(bone, negate)
        if e then
            pose[bone] = e
            emv[bone] = { _LocalEulerAngle = euler_to_emv_vec(e) }
            count = count + 1
            src_used[src or "?"] = (src_used[src or "?"] or 0) + 1
            mode_used[mode or "?"] = (mode_used[mode or "?"] or 0) + 1
        end
    end

    if count == 0 then
        return nil, 0
    end

    local primary_src = ""
    local primary_n = 0
    for src, c in pairs(src_used) do
        if c > primary_n then primary_n = c; primary_src = src end
    end
    local primary_mode = "rest_delta"
    local mode_n = 0
    for m, c in pairs(mode_used) do
        if c > mode_n then mode_n = c; primary_mode = m end
    end
    state.capture_src = primary_src .. "|" .. primary_mode

    return { pose = pose, emv = emv, mirror_mode = primary_mode }, count
end

local function lerp_angle(a, b, t)
    local d = ((b - a + 540.0) % 360.0) - 180.0
    return a + d * t
end

local function write_joint_local_euler(joint, tx, ty, tz)
    if not joint then return false end
    local v = Vector3f.new(tx, ty, tz)
    local ok = false
    pcall(function()
        joint:call("set_LocalEulerAngle", v)
        ok = true
    end)
    return ok
end

local function rigs_for_apply()
    if type(state.rig_targets) == "table" and #state.rig_targets > 0 then
        return state.rig_targets
    end
    if state.xform and state.joint_count >= 3 then
        return { { tf = state.xform, src = state.src, joints = state.joints, n = state.joint_count } }
    end
    return {}
end

function M.apply_pl0000_pose(pose_entry, factor)
    factor = tonumber(factor) or 1.0
    if factor <= 0.0001 then return 0 end
    if not state.xform or state.joint_count < 3 then
        M.refresh_skeleton()
    end
    local rigs = rigs_for_apply()
    if #rigs == 0 then return 0 end

    local pose = type(pose_entry) == "table" and pose_entry.pose or nil
    local emv = type(pose_entry) == "table" and pose_entry.emv or nil
    if not pose and not emv then return 0 end

    local function apply_once()
        local applied = 0
        local full = factor >= 0.9999
        for _, rig in ipairs(rigs) do
            local tf = rig.tf
            local joints = rig.joints or {}
            for _, bone in ipairs(LEFT_HAND_BONES) do
                local target = nil
                if type(pose) == "table" and type(pose[bone]) == "table" then
                    target = pose[bone]
                elseif type(emv) == "table" and type(emv[bone]) == "table" then
                    target = parse_emv_vec(emv[bone]._LocalEulerAngle)
                end
                if target then
                    local joint = joints[bone] or find_joint_on_tf(tf, bone)
                    if joint then
                        joints[bone] = joint
                        if rig == rigs[1] then
                            state.joints[bone] = joint
                        end
                        local tx = tonumber(target[1]) or 0
                        local ty = tonumber(target[2]) or 0
                        local tz = tonumber(target[3]) or 0
                        if not full then
                            local cur = read_euler(joint)
                            if cur then
                                tx = lerp_angle(cur[1], tx, factor)
                                ty = lerp_angle(cur[2], ty, factor)
                                tz = lerp_angle(cur[3], tz, factor)
                            end
                        end
                        if write_joint_local_euler(joint, tx, ty, tz) then
                            applied = applied + 1
                        end
                    end
                end
            end
            rig.joints = joints
        end
        return applied
    end

    local applied = apply_once()
    if applied == 0 then
        M.refresh_skeleton()
        rigs = rigs_for_apply()
        if #rigs > 0 then
            applied = apply_once()
        end
    end

    return applied
end

function M.clear_frozen()
    local xform = state.xform
    if xform then
        frozen_root()[xform] = nil
    end
end

-- Apply a left-hand-canonical pose onto the right-hand joints (mirrored eulers).
function M.apply_pose_to_right_mirrored(pose_entry, factor, opts)
    factor = tonumber(factor) or 1.0
    if factor <= 0.0001 then return 0 end
    opts = opts or {}
    local negate = opts.negate or { x = false, y = true, z = true }

    if not state.xform or state.joint_count < 3 then
        M.refresh_skeleton()
    end
    local rigs = rigs_for_apply()
    if #rigs == 0 then return 0 end

    local pose = type(pose_entry) == "table" and pose_entry.pose or nil
    local emv = type(pose_entry) == "table" and pose_entry.emv or nil
    if not pose and not emv then return 0 end

    local function apply_once()
        local applied = 0
        local full = factor >= 0.9999
        for _, rig in ipairs(rigs) do
            local tf = rig.tf
            for _, bone in ipairs(LEFT_HAND_BONES) do
                local target = nil
                if type(pose) == "table" and type(pose[bone]) == "table" then
                    target = pose[bone]
                elseif type(emv) == "table" and type(emv[bone]) == "table" then
                    target = parse_emv_vec(emv[bone]._LocalEulerAngle)
                end
                if target then
                    local mirrored = mirror_hand_euler(target, negate)
                    local joint = find_right_joint_for_left_bone(tf, bone)
                    if joint and mirrored then
                        local tx = tonumber(mirrored[1]) or 0
                        local ty = tonumber(mirrored[2]) or 0
                        local tz = tonumber(mirrored[3]) or 0
                        if not full then
                            local cur = read_euler(joint)
                            if cur then
                                tx = lerp_angle(cur[1], tx, factor)
                                ty = lerp_angle(cur[2], ty, factor)
                                tz = lerp_angle(cur[3], tz, factor)
                            end
                        end
                        if write_joint_local_euler(joint, tx, ty, tz) then
                            applied = applied + 1
                        end
                    end
                end
            end
        end
        return applied
    end

    local applied = apply_once()
    if applied == 0 then
        M.refresh_skeleton()
        rigs = rigs_for_apply()
        if #rigs > 0 then
            applied = apply_once()
        end
    end
    return applied
end

M.apply_pose = M.apply_pl0000_pose
M.capture_pose = M.capture_pl0000_pose
M.capture_pose_from_right_mirrored = M.capture_pl0000_pose_from_right_mirrored

return M
