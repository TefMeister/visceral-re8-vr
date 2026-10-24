-- visceral_re8_gun_survey.lua -- every gun the player owns, surveyed once per session with nothing equipped: its joints
-- (magazine, slide, bolt, pump, shell, with each one's parent) and which of its handling sounds the game knows.
-- 2026-10-24, Tefa: "can you do all the other guns in the game as well, or do you need me to equip them one by one?"
-- Why it works without equipping: every owned gun is its own game object under the player ("pl1000/ri3042_Inventory"), each
-- with its own via.wwise.WwiseContainer (headset log 2026-10-24). A container cannot list its sound names
-- (get_TriggerIdNameList came back empty) but answers exists(id) for one. A sound id is the RE Engine name hash:
-- murmur3_32 of the UTF-16LE name, seed 0xFFFFFFFF (39 of 39 known names, checked 2026-10-24). So every name pattern seen
-- so far is asked of every gun, and the ones a gun knows are written to reframework/data/visceral_re8/gun_survey.json and
-- the log. A wrong guess costs one "no". Guns the save does not own are not there to ask (unlock-all first).
-- A probe: its own file (code-shape rule), read by nothing else; turn off with SURVEY_ON = false.

local TAG = "[visceral-re8-survey]"
local SURVEY_ON = true
local SURVEY_FILE = "visceral_re8/gun_survey.json"
local START_AFTER_SEC = 8.0      -- wait this long after the player appears (the inventory objects are made at load)
local ASKS_PER_FRAME = 120       -- exists() calls per frame, so the survey never hitches a frame
local MAX_DEPTH = 3              -- how deep under the player gun objects are looked for

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

-- ==== HASH (tested offline against the known names: dev-archive/native/tools/survey_hash_test.sh) ====
local function murmur3_utf16(s)
    local M = 0xFFFFFFFF
    local function rotl(x, r) return ((x << r) | (x >> (32 - r))) & M end
    local function mul(a, b) return (a * b) & M end
    local h = 0xFFFFFFFF
    local bytes = {}
    for i = 1, #s do bytes[#bytes + 1] = s:byte(i); bytes[#bytes + 1] = 0 end   -- ASCII names: UTF-16LE is byte, 0
    local n = #bytes
    local i = 1
    while i + 3 <= n do
        local k = bytes[i] | (bytes[i + 1] << 8) | (bytes[i + 2] << 16) | (bytes[i + 3] << 24)
        k = mul(k, 0xcc9e2d51); k = rotl(k, 15); k = mul(k, 0x1b873593)
        h = h ~ k; h = rotl(h, 13); h = (mul(h, 5) + 0xe6546b64) & M
        i = i + 4
    end
    local k, sh = 0, 0
    while i <= n do k = k | (bytes[i] << sh); sh = sh + 8; i = i + 1 end
    if sh > 0 then k = mul(k, 0xcc9e2d51); k = rotl(k, 15); k = mul(k, 0x1b873593); h = h ~ k end
    h = h ~ n
    h = h ~ (h >> 16); h = mul(h, 0x85ebca6b); h = h ~ (h >> 13); h = mul(h, 0xc2b2ae35); h = h ~ (h >> 16)
    return h
end
-- ==== END HASH ====

-- the name patterns: every action seen in the 39 known names, plus the obvious kin (letters run on past the ones seen)
local ACTS = {}
local function add(a) ACTS[#ACTS + 1] = a end
for _, base in ipairs({ "RELOAD_", "MVT_RELOAD_", "HAND_RELOAD_", "HAND_GUARD_", "MVT_GUARD_", "PICKUP_" }) do
    for c = string.byte("A"), string.byte("L") do add(base .. string.char(c)) end
end
for _, a in ipairs({ "RELOAD_END", "MVT_RELOAD_END", "HAND_RELOAD_END", "TAKE_SHELL", "SHELL", "MVT_PUMP", "MVT_WALK",
    "MVT_AIM", "MVT_BACK_DEFAULT", "MVT_BACK_DEFAULT2", "BACK_DEFAULT", "BACK_DEFAULT2", "HAND", "HAND_WEAK",
    "MVT_READY_HAND", "MVT_SMALL", "MVT_MIDDLE", "MVT_LARGE", "GRAB_LEVER", "HAND_MAGAZINE", "TAKE_MAGAZINE", "COCK",
    "HAMMER", "SLIDE", "BOLT", "LEVER", "OPEN", "CLOSE", "CYLINDER_OPEN", "CYLINDER_CLOSE", "BARREL_OPEN", "BARREL_CLOSE",
    "MAGAZINE_IN", "MAGAZINE_OUT", "PUMP", "CHARGE", "LOAD", "EJECT" }) do add(a) end
local FAMILIES = { "", "SHOTGUN_", "HANDGUN_", "RIFLE_", "MAGNUM_", "SNIPER_", "MACHINEGUN_", "GRENADE_", "REVOLVER_" }

local function names_for(num)   -- num = "3046": the gun's own names, then the shared families
    local out = {}
    for _, a in ipairs(ACTS) do out[#out + 1] = "SND_MOT_RI" .. num .. "_SE_" .. a end
    for _, f in ipairs(FAMILIES) do for _, a in ipairs(ACTS) do out[#out + 1] = "SND_MOT_RI_SE_" .. f .. a end end
    return out
end

local function player_go()
    local v = rawget(_G, "re8vr")
    local tf = v and v.transform
    return tf and safe(function() return tf:call("get_GameObject") end)
end
local function name_of(o) return tostring(safe(function() return o:call("get_Name") end) or "?") end

local function gun_objects(go, out, depth)   -- every "ri<digits>..." game object under the player
    if go == nil or depth > MAX_DEPTH then return end
    local n = name_of(go)
    local num = n:match("^ri(%d+)")
    if num then out[#out + 1] = { go = go, name = n, num = num } end
    local tf = safe(function() return go:call("get_Transform") end)
    local ch = tf and safe(function() return tf:call("get_Child") end)
    local k = 0
    while ch ~= nil and k < 64 do
        gun_objects(safe(function() return ch:call("get_GameObject") end), out, depth + 1)
        ch = safe(function() return ch:call("get_Next") end)
        k = k + 1
    end
end

local function joints_of(go)
    local out = {}
    local tf = safe(function() return go:call("get_Transform") end)
    local arr = tf and safe(function() return tf:call("get_Joints") end)
    local els = arr and safe(function() return arr:get_elements() end) or {}
    for i, j in ipairs(els) do
        local p = safe(function() return j:call("get_Parent") end)
        out[#out + 1] = string.format("%d %s < %s", i - 1, name_of(j), p and name_of(p) or "none")
    end
    return out
end

local function container_of(go)
    local comps = safe(function() return go:call("get_Components") end)
    for _, c in ipairs(comps and safe(function() return comps:get_elements() end) or {}) do
        if safe(function() return c:get_type_definition():is_a("via.wwise.WwiseContainer") end) then return c end
    end
    return nil
end

local state = nil   -- nil = waiting, then { guns, gi, ni, names, cont }, then "done"
local seen_player_at = nil
local result = {}

re.on_frame(function()
    if not SURVEY_ON or state == "done" then return end
    local pgo = player_go()
    if pgo == nil then seen_player_at = nil return end
    seen_player_at = seen_player_at or os.clock()
    if os.clock() - seen_player_at < START_AFTER_SEC then return end
    if state == nil then
        local guns = {}
        gun_objects(pgo, guns, 0)
        L(string.format("%d gun object(s) under the player: surveying each (joints + known sounds)", #guns))
        state = { guns = guns, gi = 1, ni = 1, names = nil }
    end
    local g = state.guns[state.gi]
    if g == nil then
        pcall(function() json.dump_file(SURVEY_FILE, result) end)
        L("survey done: written to reframework/data/" .. SURVEY_FILE)
        state = "done"
        return
    end
    if state.names == nil then
        state.names = names_for(g.num)
        state.cont = container_of(g.go)
        result[g.name] = { joints = joints_of(g.go), sounds = {}, container = state.cont ~= nil }
        for _, j in ipairs(result[g.name].joints) do L(g.name .. " joint " .. j) end
        if state.cont == nil then L(g.name .. ": no sound container") end
    end
    local r = result[g.name]
    local asked = 0
    while state.cont ~= nil and state.ni <= #state.names and asked < ASKS_PER_FRAME do
        local nm = state.names[state.ni]
        local id = murmur3_utf16(nm)
        if safe(function() return state.cont:call("exists(System.UInt32)", id) end) == true then
            r.sounds[nm] = id
            L(string.format("%s knows %s (wwise:%d)", g.name, nm, id))
        end
        state.ni = state.ni + 1
        asked = asked + 1
    end
    if state.cont == nil or state.ni > #state.names then
        local c = 0
        for _ in pairs(r.sounds) do c = c + 1 end
        L(string.format("%s: %d joints, %d of %d sound names known", g.name, #r.joints, c, #state.names))
        state.gi, state.ni, state.names, state.cont = state.gi + 1, 1, nil, nil
    end
end)

L("loaded" .. (SURVEY_ON and ": every owned gun is surveyed once, a few seconds after the player appears" or " (off)"))
