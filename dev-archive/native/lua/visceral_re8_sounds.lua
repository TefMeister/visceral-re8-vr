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
-- 2026-10-24 first wear: nothing was heard through WwiseContainer (0 ids). The scope mod's notes (re-village-scope-vr
-- dev-archive/recon/2026-09-27d) say why: the weapon clicks are played by app.WwiseWeaponMotionSequence.weaponTrigger(GameObject,
-- TreeLayer, tracks, UInt32) / manualTrigger(TreeLayer, tracks, UInt32), from the upper-body motion: 21xx ready (fainter
-- click), 23xx lowered (louder click), 2422 fire + bolt, 2500 reload. So those two are heard too, and a sound is replayed
-- through the same call with the newest context it was seen with (that id's own, else any), the container as a last try.
-- With no job set, the bolt / slide / pump take the removed clicks by themselves once heard: back = a lowered (23xx) click,
-- forward = a ready (21xx) click.
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

local AUTO_BACK = { 1, 3, 6 }      -- jobs that take the lowered click when none is set
local AUTO_FWD = { 2, 4, 7 }       -- jobs that take the ready click
local auto = {}                    -- code -> id picked by itself this session
local ctx = {}                     -- method name -> the newest { this, go, layer, tracks } it was called with
local ctx_by_id = {}               -- id -> the same, for that id's own newest call
local seq_m = {}                   -- method name -> method

local function note(id, where, how, motion)
    local h = heard[id]
    if h == nil then
        if #heard_order >= HEARD_MAX then heard[table.remove(heard_order, 1)] = nil end
        h = { n = 0 }
        heard[id] = h
        heard_order[#heard_order + 1] = id
    end
    h.n = h.n + 1
    h.where, h.how, h.motion, h.t = where, how, motion, os.clock()
    if h.n <= LOG_PER_ID then L(string.format("heard id %d via %s on %s (upper motion %s), #%d", id, how, tostring(where), tostring(motion), h.n)) end
    -- the removed clicks, given to the handling sounds that have none
    if motion ~= nil and (how == "weaponTrigger" or how == "manualTrigger") then
        local fam = math.floor(motion / 100)
        local list = (fam == 23) and AUTO_BACK or (fam == 21) and AUTO_FWD or nil
        if list then
            for _, code in ipairs(list) do
                if jobs[code] == nil and auto[code] == nil then
                    auto[code] = id
                    L(string.format("job %d takes game sound %d by itself (a %s click, motion %d)", code, id, fam == 23 and "lowered" or "ready", motion))
                end
            end
        end
    end
end

-- a context is kept alive (add_ref) only while it is the newest; the one it replaces is let go (release)
local function same(a, b) return a == b or (a ~= nil and b ~= nil and safe(function() return a:get_address() == b:get_address() end)) end
local function hold(c) for _, k in ipairs({ "this", "go", "layer", "tracks" }) do local o = c[k]; if o ~= nil then pcall(function() o:add_ref() end) end end end
local function drop(c) for _, k in ipairs({ "this", "go", "layer", "tracks" }) do local o = c[k]; if o ~= nil then pcall(function() o:release() end) end end end
local function store(tbl, key, name, this, go, layer, tracks)
    local c = tbl[key]
    if c ~= nil and c.name == name and same(c.this, this) and same(c.go, go) and same(c.layer, layer) and same(c.tracks, tracks) then return end
    if c ~= nil then drop(c) end
    c = { name = name, this = this, go = go, layer = layer, tracks = tracks }
    hold(c)
    tbl[key] = c
end

local function hook()
    local td = sdk.find_type_definition("via.wwise.WwiseContainer")
    if td == nil then L("no via.wwise.WwiseContainer type") else
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
                        note(id, (gname == pname) and "player" or gname, name, upper_motion())
                    end, function(r) return r end)
                end)
                if ok then n = n + 1 end
            end
        end
        L("listening on " .. n .. " WwiseContainer trigger method(s)")
    end
    local sq = sdk.find_type_definition("app.WwiseWeaponMotionSequence")
    if sq == nil then L("no app.WwiseWeaponMotionSequence type: the weapon clicks cannot be heard") return end
    local n = 0
    for _, m in ipairs(sq:get_methods()) do
        local name = m:get_name()
        if name == "weaponTrigger" or name == "manualTrigger" then
            seq_m[name] = m
            local wt = name == "weaponTrigger"
            local ok = pcall(function()
                sdk.hook(m, function(args)
                    local this = sdk.to_managed_object(args[2])
                    local go = wt and sdk.to_managed_object(args[3]) or nil
                    local layer = sdk.to_managed_object(args[wt and 4 or 3])
                    local tracks = sdk.to_managed_object(args[wt and 5 or 4])
                    local id = sdk.to_int64(args[wt and 6 or 5]) & 0xFFFFFFFF
                    local motion = layer and safe(function() return layer:call("get_MotionID") end)
                    if this ~= nil and layer ~= nil and tracks ~= nil then
                        store(ctx, name, name, this, go, layer, tracks)
                        store(ctx_by_id, id, name, this, go, layer, tracks)
                    end
                    note(id, "the weapon motion sounds", name, motion)
                end, function(r) return r end)
            end)
            if ok then n = n + 1 end
        end
    end
    L("listening on " .. n .. " WwiseWeaponMotionSequence trigger method(s) (the weapon clicks)")
end
pcall(hook)

local function replay(id, c)
    local m = c and seq_m[c.name]
    if m == nil then return false end
    if c.name == "weaponTrigger" then return pcall(function() m:call(c.this, c.go, c.layer, c.tracks, id) end) end
    return pcall(function() m:call(c.this, c.layer, c.tracks, id) end)
end

local function play(id)
    if id == nil then return false, "no sound" end
    -- through the weapon motion sound player first: that id's own newest call, else any newest call of either kind
    for _, c in ipairs({ ctx_by_id[id] or false, ctx.manualTrigger or false, ctx.weaponTrigger or false }) do
        if c and replay(id, c) then played = played + 1 return true, "replayed through " .. c.name end
    end
    if trigger_m == nil then return false, "nothing to play it with yet" end
    local pgo = player_go()
    local cont = pgo and safe(function() return pgo:call("getComponent(System.Type)", sdk.typeof("via.wwise.WwiseContainer")) end)
    if cont == nil then return false, "no player sound container" end
    local ok = pcall(function() trigger_m:call(cont, id) end)
    if ok then played = played + 1 end
    return ok, "the player's sound container"
end

local function job_id(code) return jobs[code] or auto[code] end

re.on_pre_application_entry("UpdateHID", function()
    local b = rawget(_G, "visceral_re8_bridge")
    if not b or not b.ready() then return end
    local mask = 0
    for code = 1, 8 do if job_id(code) then mask = mask | (1 << code) end end
    b.w(S_SFX_LUA_HAS, mask)
    local seq = b.r(S_SFX_SEQ)
    if seq_seen == nil then seq_seen = seq return end
    if seq == seq_seen then return end
    seq_seen = seq
    local code = math.floor(b.r(S_SFX_CODE) + 0.5)
    local id = job_id(code)
    if id then
        local ok, how = play(id)
        L(string.format("handling sound %d -> game sound %d%s: %s (%s)", code, id, jobs[code] and "" or " (picked by itself)", ok and "played" or "FAILED", how))
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 sounds") then return end
    imgui.text(string.format("handling sounds played: %d", played))
    for _, j in ipairs(JOBS) do
        local id = job_id(j.code)
        imgui.text(string.format("%d. %s: %s%s", j.code, j.name, id and tostring(id) or "(none)", (id and not jobs[j.code]) and " (by itself)" or ""))
        imgui.same_line()
        if imgui.button("clear##" .. j.code) then jobs[j.code] = nil; save() end
    end
    imgui.text("Heard from the player and the guns (newest last). Play, then give it a job:")
    for i = #heard_order, 1, -1 do
        local id = heard_order[i]
        local h = heard[id]
        if h then
            imgui.text(string.format("%d  %s  motion %s  x%d", id, tostring(h.how), tostring(h.motion), h.n))
            imgui.same_line()
            if imgui.button("Play##" .. id) then local ok, how = play(id); L(string.format("Play %d: %s (%s)", id, ok and "played" or "FAILED", how)) end
            for _, j in ipairs(JOBS) do
                imgui.same_line()
                if imgui.button(j.code .. "##" .. id) then jobs[j.code] = id; save(); L(string.format("job %d (%s) = game sound %d", j.code, j.name, id)) end
            end
        end
    end
    imgui.tree_pop()
end)

L("loaded: " .. (next(jobs) and "game sounds set for some handling sounds" or "no game sounds set yet"))
