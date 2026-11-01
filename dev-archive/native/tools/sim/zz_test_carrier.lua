-- zz_test_carrier.lua -- TEST ONLY (2026-11-01): turns a joint of the gun in hand by what visceral_re8/test_joint.json says,
-- {"joint": "Carrier", "axis": "x", "deg": 35}, after the animation each frame, to find a break-action's open turn live.
local FILE, cfg, t = "visceral_re8/test_joint.json", nil, 0
local function gun_tf()
    local v = rawget(_G, "re8vr"); local w = v and v.weapon
    if not w then return nil end
    local go = nil
    pcall(function() go = w:call("get_GameObject") end)
    if go == nil then pcall(function() go = w:get_field("<owner>k__BackingField") end) end
    return go and go:call("get_Transform")
end
local rest = {}
local function apply()
    if not cfg or not cfg.joint then return end
    local tf = gun_tf(); if not tf then return end
    local j = tf:call("getJointByName", cfg.joint); if not j then return end
    local key = tostring(cfg.joint)
    if not rest[key] then rest[key] = j:call("get_LocalRotation") end
    local h = math.rad(cfg.deg or 0) / 2
    local q = cfg.axis == "y" and Quaternion.new(math.cos(h), 0, math.sin(h), 0) or cfg.axis == "z" and Quaternion.new(math.cos(h), 0, 0, math.sin(h)) or Quaternion.new(math.cos(h), math.sin(h), 0, 0)
    j:call("set_LocalRotation", rest[key] * q)
end
re.on_frame(function()
    t = t + 1
    if t % 20 == 0 then local ok, c = pcall(json.load_file, FILE); if ok and type(c) == "table" then cfg = c end end
end)
re.on_application_entry("LateUpdateBehavior", function() pcall(apply) end)
re.on_pre_application_entry("PrepareRendering", function() pcall(apply) end)
