-- visceral_re8_carry_rec.lua -- DEV RECORDER, rebuild 2 (2026-11-26). Not part of any package.
--
-- Why: on the bare base (REFramework nightly 01451 + praydog's re8_vr.lua, nothing of ours) Ethan carries Rose
-- upside down from the left hand while both hands follow the controllers (Tefa, picture, 2026-11-26 00:20).
-- praydog already lets the game's own arms play in the END-game events (re8_end_game_events, c32e390_01..09):
-- re8vr:update_hand_ik() is skipped there. To do the same for the prologue carry we need what the game calls it.
--
-- What it does: reads only. Twice a second it builds one line of state and writes it to the log when it differs
-- from the last line written:
--   the VR layer's flags, the running game event's name, and bank / motion id of the player's motion layers.
-- Rule set (design 2026-11-25d section 5): no joint write, no object made, no request, no hook; one on_frame
-- callback that returns at once on every frame but each 30th.

local TAG = "[visceral-re8-carry-rec]"
local EVERY_FRAMES = 30
local MAX_LAYERS = 12

if reframework:get_game_name() ~= "re8" then return end

local frame = 0
local last_line = ""
local motion_t = nil

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end

local function flag(v)
    if v == nil then return "?" end
    return v and "1" or "0"
end

local function event_name()
    local c = re8vr.game_event_action_controller
    if c == nil then return "no-controller" end
    local action = safe(function() return c:get_field("_GameEventAction") end)
    if action == nil then return "none" end
    return tostring(safe(function() return action:get_field("_EventName") end))
end

local function layers_text(player)
    motion_t = motion_t or sdk.typeof("via.motion.Motion")
    local motion = safe(function() return player:call("getComponent(System.Type)", motion_t) end)
    if motion == nil then return "no-motion" end
    local count = safe(function() return motion:call("getLayerCount") end) or 0
    if count > MAX_LAYERS then count = MAX_LAYERS end
    local parts = {}
    for i = 0, count - 1 do
        local layer = safe(function() return motion:call("getLayer", i) end)
        if layer ~= nil then
            local bank = safe(function() return layer:call("get_MotionBankID") end)
            local id = safe(function() return layer:call("get_MotionID") end)
            parts[#parts + 1] = string.format("L%d=%s/%s", i, tostring(bank), tostring(id))
        end
    end
    return table.concat(parts, " ")
end

-- v2 (2026-11-26 00:3x): the first run showed the carry has NO event and plays plain motion 0/0 on layer 0, from the
-- first frame of control until event c10e050_00 (the crib). So: who is the player object, what hangs under it, what
-- is layer 0's motion called. One slower line ("who"), written on change, checked every 2 s.
local WHO_EVERY_FRAMES = 120
local MAX_CHILDREN = 60
local last_who = ""

local function go_name(transform)
    local go = safe(function() return transform:call("get_GameObject") end)
    return go and tostring(safe(function() return go:call("get_Name") end)) or "?"
end

local function children_text(transform, depth, out)
    local child = safe(function() return transform:call("get_Child") end)
    while child ~= nil and #out < MAX_CHILDREN do
        out[#out + 1] = string.rep(">", depth) .. go_name(child)
        if depth < 2 then children_text(child, depth + 1, out) end
        child = safe(function() return child:call("get_Next") end)
    end
end

local function who_text(player)
    local name = tostring(safe(function() return player:call("get_Name") end))
    local transform = safe(function() return player:call("get_Transform") end)
    local parent = transform and safe(function() return transform:call("get_Parent") end)
    local kids = {}
    if transform then children_text(transform, 1, kids) end
    local node_name = "?"
    motion_t = motion_t or sdk.typeof("via.motion.Motion")
    local motion = safe(function() return player:call("getComponent(System.Type)", motion_t) end)
    local layer = motion and safe(function() return motion:call("getLayer", 0) end)
    local node = layer and safe(function() return layer:call("get_HighestWeightMotionNode") end)
    if node then node_name = tostring(safe(function() return node:call("get_MotionName") end)) end
    local scene_name = "?"
    local sm = sdk.get_native_singleton("via.SceneManager")
    local sm_t = sdk.find_type_definition("via.SceneManager")
    local scene = sm and sm_t and safe(function() return sdk.call_native_func(sm, sm_t, "get_CurrentScene") end)
    if scene then scene_name = tostring(safe(function() return scene:call("get_Name") end)) end
    return string.format("who player=%s parent=%s scene=%s L0name=%s kids=[%s]", name,
        parent and go_name(parent) or "none", scene_name, node_name, table.concat(kids, " "))
end

-- v3 (2026-11-26 01:0x): Tefa: in the patting scene on the stairs (ch01_0000_Baby_100_Dandle) "hands and body
-- disappear and then reappear after it's done". None of the VR layer's flags changes there. So: is each body part
-- drawn? One line ("draw"), on change, checked every 10 frames while anything hangs on the player or not.
local DRAW_EVERY_FRAMES = 10
local DRAW_PARTS = { "pl1000HandR", "pl1000HandL", "pl1000LowerBody", "ShadowBody", "pl5000" }
local last_draw = ""
local mesh_t = nil

local function part_text(go)
    mesh_t = mesh_t or sdk.typeof("via.render.Mesh")
    local draw_self = safe(function() return go:call("get_DrawSelf") end)
    local draw = safe(function() return go:call("get_Draw") end)
    local mesh = safe(function() return go:call("getComponent(System.Type)", mesh_t) end)
    local mesh_on = mesh and safe(function() return mesh:call("get_Enabled") end)
    local mesh_draw = mesh and safe(function() return mesh:call("get_DrawDefault") end)
    return string.format("%s%s%s%s", flag(draw_self), flag(draw), flag(mesh_on), flag(mesh_draw))
end

local function draw_text(player)
    local parts = { "self=" .. part_text(player) }
    local transform = safe(function() return player:call("get_Transform") end)
    local child = transform and safe(function() return transform:call("get_Child") end)
    local n = 0
    while child ~= nil and n < MAX_CHILDREN do
        local go = safe(function() return child:call("get_GameObject") end)
        local name = go and safe(function() return go:call("get_Name") end)
        for _, want in ipairs(DRAW_PARTS) do
            if name == want then parts[#parts + 1] = want .. "=" .. part_text(go) end
        end
        child = safe(function() return child:call("get_Next") end)
        n = n + 1
    end
    return table.concat(parts, " ")
end

-- v4 (2026-11-26 01:1x): Tefa: the carry bobs a lot walking forward and "how it should always be" walking back.
-- Layer 0 shows ONE motion id (0/1) for Hands_Walk / WalkB / WalkL / WalkR_HoldBaby_Loop [measured, n=1]: a blend.
-- So: once, the method names of the layer and node types that could show or steer a blend; and every half second
-- while a walk plays, each node of layer 0 with its name and weight ("tree"), on change.
local methods_logged = false
local last_tree = ""
local KEYS = { "Node", "Weight", "Blend", "Rate", "Speed" }

local function log_methods(type_name)
    local t = sdk.find_type_definition(type_name)
    if t == nil then log.info(TAG .. " methods " .. type_name .. ": no such type") return end
    local names = {}
    for _, m in ipairs(t:get_methods()) do
        local name = m:get_name()
        for _, key in ipairs(KEYS) do
            if string.find(name, key, 1, true) then names[#names + 1] = name break end
        end
    end
    log.info(TAG .. " methods " .. type_name .. ": " .. table.concat(names, " "))
end

local function tree_text(player)
    motion_t = motion_t or sdk.typeof("via.motion.Motion")
    local motion = safe(function() return player:call("getComponent(System.Type)", motion_t) end)
    local layer = motion and safe(function() return motion:call("getLayer", 0) end)
    if layer == nil then return "no-layer" end
    local count = safe(function() return layer:call("getMotionNodeCount") end)
        or safe(function() return layer:call("get_MotionNodeCount") end)
    if count == nil then return "no-node-count" end
    local parts = {}
    for i = 0, math.min(count, 120) - 1 do
        local node = safe(function() return layer:call("getMotionNode", i) end)
        if node ~= nil then
            local name = tostring(safe(function() return node:call("get_MotionName") end))
            local weight = safe(function() return node:call("get_Weight") end)
            local short = string.gsub(name, "ch01_0000_", "")
            if weight == nil or weight > 0.05 then
                parts[#parts + 1] = string.format("%s=%s", short, weight and string.format("%.1f", weight) or "?")
            end
        end
    end
    return table.concat(parts, " ")
end

-- v5 (2026-11-26 01:4x): THE BOB, MEASURED. Tefa: carrying Rose, walking forward and sideways she swings up to 30 cm,
-- backward "how it should always be"; ticking praydog's "Movement Shake" changed nothing [reported, n=1], so the
-- removed camera bob is not the cause. Which part moves against which? Every frame while something hangs on the
-- player: the height of the left hand, the head, the chest and the hip joints and of the eye camera. Once a second
-- one line ("bob"): how far each travelled up and down in that second against the camera, in centimetres, and the
-- motion that carried the most weight.
local BOB_JOINTS = { "L_Hand", "R_Hand", "Head", "Chest", "Hip" }
local BOB_EVERY_FRAMES = 90
local bob_min, bob_max, bob_n = {}, {}, 0

local function bob_reset()
    bob_min, bob_max, bob_n = {}, {}, 0
end

local function bob_take(key, v)
    if v == nil then return end
    if bob_min[key] == nil or v < bob_min[key] then bob_min[key] = v end
    if bob_max[key] == nil or v > bob_max[key] then bob_max[key] = v end
end

local function bob_sample(player)
    local transform = safe(function() return player:call("get_Transform") end)
    if transform == nil then return end
    local has_child = false
    local child = safe(function() return transform:call("get_Child") end)
    local n = 0
    while child ~= nil and n < MAX_CHILDREN do
        if go_name(child) == "pl5000" then has_child = true break end
        child = safe(function() return child:call("get_Next") end)
        n = n + 1
    end
    if not has_child then bob_reset() return end

    local camera = sdk.get_primary_camera()
    local cam_go = camera and safe(function() return camera:call("get_GameObject") end)
    local cam_tf = cam_go and safe(function() return cam_go:call("get_Transform") end)
    local cam_pos = cam_tf and safe(function() return cam_tf:call("get_Position") end)
    local base_pos = safe(function() return transform:call("get_Position") end)
    if cam_pos == nil or base_pos == nil then return end
    bob_take("cam-feet", cam_pos.y - base_pos.y)
    for _, name in ipairs(BOB_JOINTS) do
        local joint = safe(function() return transform:call("getJointByName", name) end)
        local pos = joint and safe(function() return joint:call("get_Position") end)
        if pos ~= nil then
            bob_take(name .. "-cam", pos.y - cam_pos.y)
            bob_take(name .. "-feet", pos.y - base_pos.y)
        end
    end
    bob_n = bob_n + 1
    if bob_n < BOB_EVERY_FRAMES then return end

    local keys = {}
    for k, _ in pairs(bob_min) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format("%s=%.0f", k, (bob_max[k] - bob_min[k]) * 100.0)
    end
    log.info(TAG .. " bob cm/" .. tostring(BOB_EVERY_FRAMES) .. "f " .. table.concat(parts, " ") .. " | " .. last_tree)
    bob_reset()
end

re.on_frame(function()
    frame = frame + 1
    if re8vr == nil then return end
    local player = re8vr.player
    if player == nil then return end

    pcall(bob_sample, player)

    if frame % DRAW_EVERY_FRAMES == 0 then
        local d = safe(draw_text, player) or "draw failed"
        if d ~= last_draw then
            last_draw = d
            log.info(TAG .. " draw (DrawSelf,Draw,meshEnabled,meshDrawDefault) " .. d)
        end
    end
    if frame % EVERY_FRAMES ~= 0 then return end

    if not methods_logged then
        methods_logged = true
        pcall(log_methods, "via.motion.TreeLayer")
        pcall(log_methods, "via.motion.MotionNodeCtrl")
        pcall(log_methods, "via.motion.Motion")
        -- v6 (2026-11-26 01:5x): Ethan has no head when a scene's view is outside his body (Tefa, the crib scene).
        -- Where is the head switched off? The names the mesh controller and the mesh offer, once.
        KEYS = { "Parts", "Visible", "Head", "Draw", "Mask", "Material" }
        pcall(log_methods, "via.render.Mesh")
        pcall(log_methods, "app.PlayerMeshController")
        pcall(function()
            local t = sdk.find_type_definition("app.PlayerMeshController")
            local names = {}
            for _, f in ipairs(t:get_fields()) do names[#names + 1] = f:get_name() end
            log.info(TAG .. " fields app.PlayerMeshController: " .. table.concat(names, " "))
        end)
    end
    local tree = safe(tree_text, player) or "tree failed"
    if tree ~= last_tree then
        last_tree = tree
        log.info(TAG .. " tree " .. tree)
    end

    if frame % WHO_EVERY_FRAMES == 0 then
        local who = safe(who_text, player) or "who failed"
        if who ~= last_who then
            last_who = who
            log.info(TAG .. " " .. who)
        end
    end

    local line = string.format("cut=%s hands=%s jacked=%s motionplay=%s endevent=%s event=%s | %s",
        flag(re8vr.is_in_cutscene), flag(re8vr.can_use_hands), flag(re8vr.is_arm_jacked),
        flag(re8vr.is_motion_play), flag(re8vr.in_re8_end_game_event), event_name(),
        safe(layers_text, player) or "layers-failed")

    if line ~= last_line then
        last_line = line
        log.info(TAG .. " " .. line)
    end
end)

log.info(TAG .. " loaded (reads only; one line per change, checked twice a second)")
