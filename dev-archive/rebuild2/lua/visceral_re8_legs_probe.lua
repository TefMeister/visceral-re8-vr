-- visceral_re8_legs_probe.lua -- rebuild 2, a PROBE (2026-11-26, RE8-091). Not part of the mod; comes out again.
--
-- Tefa: the legs glitch "only on uneven surface", with the stock game + praydog's VR too (March build and nightly
-- 01451, a true reinstall). The walk file: a foot pops up about 8 cm in ONE picture and sinks back over the next
-- four, the hip still. Suspect: the game's own leg fitting, via.motion.IkLeg (ground adjust by ray casts).
--
-- What this does: finds the player's via.motion.IkLeg, logs its numbers once, then holds whatever
-- reframework/data/visceral_re8/legs.json asks for. The file is read again every second, so a number can be
-- changed while Tefa walks. A key is the property's name, e.g. {"RayCastInterval": 0, "EnabledGroundAdjust": false}.
-- No file, or an empty one: nothing is changed (the first values are put back).
local TAG = "[visceral-re8-legs-probe]"
local FILE = "visceral_re8/legs.json"

-- name, kind (b = bool, f = float, u = unsigned)
local PROPS = {
    { "EnabledGroundAdjust", "b" }, { "GroundAdjustTwoRayCast", "b" }, { "SkipIkIfNoHitDetail", "b" },
    { "RayCastInterval", "u" }, { "RayCastSkipByDistance", "b" }, { "RayCastSkipDistance", "f" },
    { "RayCastSkipDetail", "b" }, { "BlendRate", "f" },
    { "AdjustFootDamping", "f" }, { "AdjustFootBottomRate", "f" }, { "AdjustFootUpwardRate", "f" },
    { "AdjustFootContactUpwardRate", "f" }, { "ForceContactUpwardAdjust", "b" }, { "AdjustFootRotRate", "f" },
    { "DistanceLimitRate", "f" }, { "CenterDampingRate", "f" }, { "CenterAdjustRate", "f" },
    { "CenterAdjustUpwardRate", "f" }, { "GroundContactUpDistance", "f" }, { "GroundContactDownDistance", "f" },
    { "GroundContactRotationAdjustDistance", "f" }, { "HealHeight", "f" }, { "ToeHeight", "f" },
    { "WallLimitAngle", "f" }, { "FootRollLimit", "f" }, { "FootLockInterpolationFrame", "f" },
    { "FootSkipFrame", "f" }, { "FootLockParentLocal", "b" }, { "ReflectPrevParentMove", "b" },
}
local KIND = {}
for _, p in ipairs(PROPS) do KIND[p[1]] = p[2] end

local ik, ik_owner = nil, nil
local first = {}          -- the game's own values, as found
local asked = {}          -- what legs.json asks for now
local last_read = -10.0
local said = {}

local function show(v)
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" then return string.format("%.4g", v) end
    return tostring(v)
end

local function find_ik()
    local player = re8vr ~= nil and re8vr.player or nil
    if player == nil then ik, ik_owner = nil, nil return end
    if ik ~= nil and ik_owner == player then return end
    ik, ik_owner, first, said = nil, player, {}, {}
    local ok, comp = pcall(function() return player:call("getComponent(System.Type)", sdk.typeof("via.motion.IkLeg")) end)
    if not ok or comp == nil then return end
    ik = comp
    local parts = {}
    for _, p in ipairs(PROPS) do
        local ok2, v = pcall(function() return ik:call("get_" .. p[1]) end)
        if ok2 and v ~= nil then first[p[1]] = v; parts[#parts + 1] = p[1] .. "=" .. show(v) end
    end
    log.info(TAG .. " the player's leg fitting found; as the game set it: " .. table.concat(parts, ", "))
    for _, m in ipairs({ "getFootLockMode", "getRayCastSkipOption", "getCenterAdjust", "getEffectorTarget" }) do
        local ok3, v = pcall(function() return ik:call(m) end)
        if ok3 then log.info(TAG .. " " .. m .. " = " .. tostring(v)) end
    end
end

local function read_file()
    local now = os.clock()
    if now - last_read < 1.0 then return end
    last_read = now
    local f = json.load_file(FILE)
    local new = {}
    if type(f) == "table" then
        for k, v in pairs(f) do if KIND[k] ~= nil then new[k] = v end end
    end
    -- a key that left the file goes back to the game's own value
    for k, _ in pairs(asked) do
        if new[k] == nil and first[k] ~= nil and ik ~= nil then
            pcall(function() ik:call("set_" .. k, first[k]) end)
            log.info(TAG .. " " .. k .. " back to the game's own " .. show(first[k]))
            said[k] = nil
        end
    end
    asked = new
end

re.on_pre_application_entry("UpdateMotion", function()
    local ok, e = pcall(function()
        find_ik()
        if ik == nil then return end
        read_file()
        for k, v in pairs(asked) do
            local val = v
            if KIND[k] == "b" then val = (v == true or v == 1) end
            if KIND[k] == "u" then val = math.floor(tonumber(v) or 0) end
            if KIND[k] == "f" then val = (tonumber(v) or 0) + 0.0 end
            ik:call("set_" .. k, val)
            if said[k] ~= show(val) then
                said[k] = show(val)
                log.info(TAG .. " " .. k .. " held at " .. show(val) .. " (the game's own: " .. show(first[k]) .. ")")
            end
        end
    end)
    if not ok and said.__err ~= tostring(e) then said.__err = tostring(e); log.info(TAG .. " failed: " .. tostring(e)) end
end)

log.info(TAG .. " loaded (a probe: holds the leg fitting's numbers from legs.json, read every second)")
