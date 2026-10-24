-- visceral_re8_sounds.lua -- the handling sounds of Visceral RE8's slide, pump and bolt, played with the game's own
-- sounds (2026-10-24, Tefa: "using LG + LT to rack makes no gun sounds"; "pumping makes no sound"; for the bolt "you can
-- use the sounds we removed for it, the sounds that played when gun was held with 2 hands and pointed at the ground or at
-- eye height").
--
-- Two jobs:
--   LISTEN: every sound the game fires from the player or a gun (a via.wwise.WwiseContainer trigger) is written to the
--           log once per sound id, with the player's upper-body motion at that moment (the scope mod's probe, made
--           general), and listed in the menu with a Play button, so each sound can be heard and given a job.
--   PLAY:   the plugin asks for a handling sound by number (src/bridge.h Sfx) through the shared array; if a game sound
--           is set for it here, it is fired on the container that last played it (else the player's own).
-- Settings: reframework/data/visceral_re8/sounds.json ({"6": 123456789, ...}: handling sound number -> game sound id).
-- Needs visceral_re8_bridge.lua (the shared array). Reloads live with "Reset scripts".

local TAG = "[visceral-re8-sounds]"
local S_SFX_CODE, S_SFX_SEQ, S_SFX_LUA_HAS = 61, 62, 63
local SOUNDS_FILE = "visceral_re8/sounds.json"
local UPPER_LAYER = 1          -- the player's upper-body motion layer (scope mod probe, 2026-09-27)
local LOG_PER_ID = 3           -- log lines per game sound id
local HEARD_MAX = 60           -- rows kept in the menu list
local JOBS = {
    { code = 1, name = "slide pulled back" }, { code = 2, name = "slide goes home" },
    { code = 3, name = "pump pulled back" }, { code = 4, name = "pump pushed forward" },
    { code = 5, name = "bolt turned up" }, { code = 6, name = "bolt back (click)" },
    { code = 7, name = "bolt forward (click)" }, { code = 8, name = "bolt turned down" },
}

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

local jobs = {}                -- code -> game sound id
pcall(function()
    local d = json.load_file(SOUNDS_FILE)
    if type(d) == "table" then for k, v in pairs(d) do if tonumber(k) and tonumber(v) then jobs[tonumber(k)] = tonumber(v) end end end
end)
local function save() pcall(function() local o = {}; for k, v in pairs(jobs) do o[tostring(k)] = v end; json.dump_file(SOUNDS_FILE, o) end) end

local heard, heard_order = {}, {}   -- id -> { n, where, motion, t }
local played, seq_seen = 0, nil
local trigger_m = nil

local function player_go()
    local v = rawget(_G, "re8vr")
    local tf = v and v.transform
    return tf and safe(function() return tf:call("get_GameObject") end)
end
local function upper_motion()
    local go = player_go()
    local mo = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    local l = mo and safe(function() return mo:call("getLayer", UPPER_LAYER) end)
    return l and safe(function() return l:call("get_MotionID") end)
end
local function interesting(name, pname)
    if name == nil then return false end
    local n = name:lower()
    return name == pname or n:find("wp") ~= nil or n:find("ri3") ~= nil or n:find("weapon") ~= nil or n:find("gun") ~= nil
end

local function hook()
    local td = sdk.find_type_definition("via.wwise.WwiseContainer")
    if td == nil then L("no via.wwise.WwiseContainer type: no game sounds") return end
    trigger_m = td:get_method("trigger(System.UInt32)")
    local n = 0
    for _, m in ipairs(td:get_methods()) do
        local name = m:get_name()
        if name:sub(1, 7) == "trigger" and m:get_num_params() >= 1 then
            if trigger_m == nil and m:get_num_params() == 1 then trigger_m = m end
            local ok = pcall(function()
                sdk.hook(m, function(args)
                    local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
                    local cont = sdk.to_managed_object(args[2])
                    local go = cont and safe(function() return cont:call("get_GameObject") end)
                    local gname = go and safe(function() return go:call("get_Name") end)
                    local pgo = player_go()
                    local pname = pgo and safe(function() return pgo:call("get_Name") end) or ""
                    if not interesting(gname, pname) then return end
                    local h = heard[id]
                    if h == nil then
                        if #heard_order >= HEARD_MAX then heard[table.remove(heard_order, 1)] = nil end
                        h = { n = 0 }
                        heard[id] = h
                        heard_order[#heard_order + 1] = id
                    end
                    h.n = h.n + 1
                    h.where = (gname == pname) and "player" or gname
                    h.motion = upper_motion()
                    h.t = os.clock()
                    if h.n <= LOG_PER_ID then
                        L(string.format("heard id %d via %s on '%s' (upper motion %s), #%d", id, name, tostring(gname), tostring(h.motion), h.n))
                    end
                end, function(r) return r end)
            end)
            if ok then n = n + 1 end
        end
    end
    L("listening on " .. n .. " WwiseContainer trigger method(s); play with " .. (trigger_m and trigger_m:get_name() or "NOTHING"))
end
pcall(hook)

local function play(id)
    if trigger_m == nil or id == nil then return false end
    -- on the gun when it was heard on the gun, else on the player (containers are looked up fresh: a kept one can die)
    local h = heard[id]
    local go = nil
    if h and h.where ~= "player" then
        local w = rawget(_G, "re8vr") and re8vr.weapon
        go = w and safe(function() return w:call("get_GameObject") end)
    end
    go = go or player_go()
    local cont = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.wwise.WwiseContainer")) end)
    if cont == nil and go ~= player_go() then
        local pgo = player_go()
        cont = pgo and safe(function() return pgo:call("getComponent(System.Type)", sdk.typeof("via.wwise.WwiseContainer")) end)
    end
    if cont == nil then return false end
    local ok = pcall(function() trigger_m:call(cont, id) end)
    if ok then played = played + 1 end
    return ok
end

re.on_pre_application_entry("UpdateHID", function()
    local b = rawget(_G, "visceral_re8_bridge")
    if not b or not b.ready() then return end
    local mask = 0
    for code, _ in pairs(jobs) do mask = mask | (1 << code) end
    b.w(S_SFX_LUA_HAS, mask)
    local seq = b.r(S_SFX_SEQ)
    if seq_seen == nil then seq_seen = seq return end
    if seq == seq_seen then return end
    seq_seen = seq
    local code = math.floor(b.r(S_SFX_CODE) + 0.5)
    local id = jobs[code]
    if id then
        local ok = play(id)
        L(string.format("handling sound %d -> game sound %d %s", code, id, ok and "played" or "FAILED"))
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 sounds") then return end
    imgui.text(string.format("handling sounds played: %d", played))
    for _, j in ipairs(JOBS) do
        local id = jobs[j.code]
        imgui.text(string.format("%d. %s: %s", j.code, j.name, id and tostring(id) or "(none)"))
        imgui.same_line()
        if imgui.button("clear##" .. j.code) then jobs[j.code] = nil; save() end
    end
    imgui.text("Heard from the player and the guns (newest last). Play, then give it a job:")
    for i = #heard_order, 1, -1 do
        local id = heard_order[i]
        local h = heard[id]
        if h then
            imgui.text(string.format("%d  %s  motion %s  x%d", id, tostring(h.where), tostring(h.motion), h.n))
            imgui.same_line()
            if imgui.button("Play##" .. id) then play(id) end
            for _, j in ipairs(JOBS) do
                imgui.same_line()
                if imgui.button(j.code .. "##" .. id) then jobs[j.code] = id; save(); L(string.format("job %d (%s) = game sound %d", j.code, j.name, id)) end
            end
        end
    end
    imgui.tree_pop()
end)

L("loaded: " .. (next(jobs) and "game sounds set for some handling sounds" or "no game sounds set yet"))
