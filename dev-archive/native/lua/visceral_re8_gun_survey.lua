-- visceral_re8_gun_survey.lua -- every gun the player owns, surveyed once per session with nothing equipped: its joints
-- (magazine, slide, bolt, pump, shell, with each one's parent) and which of its handling sounds the game knows.
-- 2026-10-24, Tefa: "can you do all the other guns in the game as well, or do you need me to equip them one by one?"
-- Why it works without equipping: every owned gun is its own game object under the player ("pl1000/ri3042_Inventory"), each
-- with its own via.wwise.WwiseContainer (headset log 2026-10-24). A container cannot list its sound names
-- (get_TriggerIdNameList came back empty) but answers exists(id) for one. A sound id is the RE Engine name hash:
-- murmur3_32 of the UTF-16LE name, seed 0xFFFFFFFF (39 of 39 known names, checked 2026-10-24). So every name pattern seen
-- so far is asked of every gun, and the ones a gun knows are written to reframework/data/visceral_re8/gun_survey.json and
-- the log. A wrong guess costs one "no". Only the gun in hand is an object (2026-10-24 live): each gun is surveyed when held.
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

-- the name patterns (v2, 2026-10-24, from the reader's names-to-try.lua): the 110 first actions, new actions read from
-- the joints the first survey found, every gun's number asked of every gun, more family words and prefixes; most
-- likely first, ~9800 names per gun
local M = {}

-- every gun number seen (the 16 story guns + the Mercenaries / Shadows of Rose copies in weapons.cpp)
M.NUMBERS = { "3008", "3021", "3023", "3036", "3040", "3042", "3046", "3047", "3048", "3049", "3050", "3115", "3116",
              "3122", "3124", "3125", "3081", "3082", "3083", "3084", "3085", "3086", "3087", "3129", "3130", "3135", "3147" }

-- the actions already asked (copied from visceral_re8_gun_survey.lua, so this file stands alone)
local OLD = {}
for _, base in ipairs({ "RELOAD_", "MVT_RELOAD_", "HAND_RELOAD_", "HAND_GUARD_", "MVT_GUARD_", "PICKUP_" }) do
    for c = string.byte("A"), string.byte("L") do OLD[#OLD + 1] = base .. string.char(c) end
end
for _, a in ipairs({ "RELOAD_END", "MVT_RELOAD_END", "HAND_RELOAD_END", "TAKE_SHELL", "SHELL", "MVT_PUMP", "MVT_WALK",
    "MVT_AIM", "MVT_BACK_DEFAULT", "MVT_BACK_DEFAULT2", "BACK_DEFAULT", "BACK_DEFAULT2", "HAND", "HAND_WEAK",
    "MVT_READY_HAND", "MVT_SMALL", "MVT_MIDDLE", "MVT_LARGE", "GRAB_LEVER", "HAND_MAGAZINE", "TAKE_MAGAZINE", "COCK",
    "HAMMER", "SLIDE", "BOLT", "LEVER", "OPEN", "CLOSE", "CYLINDER_OPEN", "CYLINDER_CLOSE", "BARREL_OPEN", "BARREL_CLOSE",
    "MAGAZINE_IN", "MAGAZINE_OUT", "PUMP", "CHARGE", "LOAD", "EJECT" }) do OLD[#OLD + 1] = a end

-- new actions, by the parts the survey found
local NEW = {
    -- pistols (S.T.A.K.E has a MagCatch joint)
    "SLIDE_BACK", "SLIDE_RELEASE", "SLIDE_STOP", "SLIDE_FORWARD", "MAG_IN", "MAG_OUT", "MAG_CATCH", "MAGAZINE_RELEASE",
    "MAGAZINE_CATCH", "HAMMER_COCK", "DECOCK", "TAKE_BULLET", "HAND_SLIDE", "GRAB_SLIDE",
    -- revolvers (Cylinder, Lid) and the GM 79 (Carrier, Lever)
    "CYLINDER", "CYLINDER_IN", "CYLINDER_OUT", "CYLINDER_SWING", "CYLINDER_ROLL", "CYLINDER_SPIN", "LID", "LID_OPEN",
    "LID_CLOSE", "EJECTOR", "EJECT_SHELL", "SPEED_LOADER", "BULLET_IN", "SHELL_IN", "LOAD_BULLET", "LOAD_SHELL",
    "CARRIER", "CARRIER_OPEN", "CARRIER_CLOSE", "BREAK_OPEN", "BREAK_CLOSE", "GRAB_CARRIER",
    -- the Rocket Pistol (Lid, Lever, Bullet00/01)
    "LEVER_UP", "LEVER_DOWN", "LEVER_OPEN", "LEVER_CLOSE", "ROCKET", "ROCKET_IN", "LOAD_ROCKET", "TAKE_ROCKET",
    -- WCX (Handle, Bolt < Handle, Selecter) and Dragoon (Lever, Selector)
    "HANDLE", "HANDLE_BACK", "HANDLE_RELEASE", "GRAB_HANDLE", "CHARGING_HANDLE", "BOLT_BACK", "BOLT_RELEASE",
    "BOLT_FORWARD", "SELECTOR", "SELECTER", "GRAB_LEVER_B", "HAND_MAGAZINE_B",
}
-- letters past L, numbered forms and empty / tactical reload forms, on the bases the found names use
for _, base in ipairs({ "RELOAD_", "PICKUP_", "HAND_RELOAD_", "MVT_RELOAD_" }) do
    for c = string.byte("M"), string.byte("P") do NEW[#NEW + 1] = base .. string.char(c) end
end
for _, base in ipairs({ "RELOAD_", "PICKUP_" }) do
    for i = 0, 12 do NEW[#NEW + 1] = string.format("%s%02d", base, i); NEW[#NEW + 1] = base .. i end
end
for c = string.byte("A"), string.byte("H") do
    local l = string.char(c)
    NEW[#NEW + 1] = "RELOAD_EMPTY_" .. l; NEW[#NEW + 1] = "EMPTY_RELOAD_" .. l; NEW[#NEW + 1] = "RELOAD_" .. l .. "_EMPTY"
    NEW[#NEW + 1] = "TAC_RELOAD_" .. l; NEW[#NEW + 1] = "RELOAD_TAC_" .. l
end
M.NEW = NEW

-- shared families: the ones asked plus new words (the found shared ones are only SHOTGUN_ and the bare MVT_SMALL)
M.FAMILIES = { "", "SHOTGUN_", "HANDGUN_", "RIFLE_", "MAGNUM_", "SNIPER_", "MACHINEGUN_", "GRENADE_", "REVOLVER_",
               "PISTOL_", "HG_", "SG_", "MG_", "AR_", "RF_", "SMG_", "ASSAULT_", "ASSAULTRIFLE_", "HANDCANNON_",
               "ROCKET_", "LAUNCHER_", "GL_", "LONG_", "SMALL_" }

-- the names for one gun container. Order: cheapest likely wins first, so a cut-short run still learns the most.
function M.names_for(num)
    local out, seen = {}, {}
    local function put(n) if not seen[n] then seen[n] = true; out[#out + 1] = n end end
    for _, a in ipairs(OLD) do put("SND_MOT_RI" .. num .. "_SE_" .. a) end                          -- 1. as before
    for _, a in ipairs(NEW) do put("SND_MOT_RI" .. num .. "_SE_" .. a) end                          -- 2. new actions, own number
    for _, n in ipairs(M.NUMBERS) do                                                                 -- 3. every other gun's number
        if n ~= num then for _, a in ipairs(OLD) do put("SND_MOT_RI" .. n .. "_SE_" .. a) end end
    end
    for _, f in ipairs(M.FAMILIES) do                                                                -- 4. shared families
        for _, a in ipairs(OLD) do put("SND_MOT_RI_SE_" .. f .. a) end
        for _, a in ipairs(NEW) do put("SND_MOT_RI_SE_" .. f .. a) end
    end
    for _, a in ipairs(OLD) do put("SND_MOT_RI" .. num .. "_" .. a); put("SND_MOT_PL1000_SE_" .. a) end   -- 5. other prefixes
    return out
end

local names_for = M.names_for

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

-- 2026-10-24 first live run: only the gun IN HAND is an object under the player (1 found, the LEMI), so the guns not held
-- are not there to ask. Now the survey keeps watching: every RESCAN_SEC it looks again, and each gun object not surveyed
-- yet (this run or an earlier one: the file is read back) is surveyed once. Equipping each gun once, by hand, by the pad
-- or by the game's own call, surveys them all.
local RESCAN_SEC = 2.0
local SURVEY_VERSION = 2      -- a gun surveyed with an older name list is asked again
local state = nil   -- nil = idle, else { g, ni, names, cont }
local seen_player_at, last_scan = nil, 0
local result = {}
pcall(function()
    local d = json.load_file(SURVEY_FILE)
    if type(d) == "table" then for k, v in pairs(d) do if type(v) == "table" and type(v.sounds) == "table" then result[k] = v end end end
end)

re.on_frame(function()
    if not SURVEY_ON then return end
    local pgo = player_go()
    if pgo == nil then seen_player_at = nil return end
    seen_player_at = seen_player_at or os.clock()
    if os.clock() - seen_player_at < START_AFTER_SEC then return end
    if state == nil then
        if os.clock() - last_scan < RESCAN_SEC then return end
        last_scan = os.clock()
        local guns = {}
        gun_objects(pgo, guns, 0)
        for _, g in ipairs(guns) do
            if result[g.name] == nil or (tonumber(result[g.name].v) or 1) < SURVEY_VERSION then
                state = { g = g, ni = 1, names = names_for(g.num), cont = container_of(g.go) }
                result[g.name] = { joints = joints_of(g.go), sounds = {}, container = state.cont ~= nil, v = SURVEY_VERSION }
                L(string.format("new gun object %s: surveying (joints + known sounds)", g.name))
                for _, j in ipairs(result[g.name].joints) do L(g.name .. " joint " .. j) end
                if state.cont == nil then L(g.name .. ": no sound container") end
                break
            end
        end
        if state == nil then return end
    end
    local g = state.g
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
        pcall(function() json.dump_file(SURVEY_FILE, result) end)
        state = nil
    end
end)

L("loaded" .. (SURVEY_ON and ": every gun object is surveyed once, the first time it is in hand" or " (off)"))
