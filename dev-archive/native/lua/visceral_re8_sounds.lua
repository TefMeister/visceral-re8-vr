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
-- through the same call with the context it was heard with (see "second wear" below).
-- 2026-10-24, Tefa: "can you just use the normal game sounds for racking, pumping and racking the bolt, i mean all weapons".
-- So each gun LEARNS its own handling sounds from the game's own motions, as they play: every run of an upper-body motion is
-- recorded (the ids in order, with the held gun's number), and the fire (24xx) and reload (25xx) runs are kept per gun.
-- From the END of the run, because a run may start with other foley: pump back / forward = the fire run's last two (the
-- game pumps after the shot); bolt up / back / forward / down = the fire run's last four; the slide going home = the reload
-- run's last (the slide release). The handgun's reload is skipped by our manual reload, so the menu's Experiments has "let the
-- game do its own reload" for one reload per gun. A job set by hand in the menu still wins.
-- Settings: reframework/data/visceral_re8/sounds.json ({"jobs": {"6": id}, "learned": {"3046": {"24": [ids], "25": [ids]}}}).
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

-- 2026-10-24 third wear: the weapon-motion UInt32 is 1 or 2 for EVERY motion, so it is not the sound. The sound is the
-- tracks argument (app.WwiseWeaponTriggerTracks and kin, from via.wwise.WwiseTriggerTracks): get_TriggerId() and
-- get_TriggerIdName() give the game's own Wwise trigger, which is the same in every run (looked up live with the
-- REFramework MCP type dump). So a sound is keyed "wwise:<trigger id>", kept with its name, and played with
-- via.wwise.WwiseContainer.trigger(id) on the object it was heard on (the weapon, else the player): learned once, in flat or
-- in VR, it plays in any later session. Container sounds are "container:<id>" (also Wwise trigger ids).
local S_WEAPON_NUM = 97
local RUN_QUIET_SEC = 2.0      -- a motion run ends when its motion changes, or after this long with no sound
local FAM_FIRE, FAM_RELOAD = 24, 25

local jobs = {}                -- code -> sound key, set by hand in the menu
local names = {}               -- "wwise:<id>" -> the game's own trigger name
local on_player = {}           -- "wwise:<id>" -> true when the game plays it on the player (OnCharacter), not the weapon
local learned = {}             -- "3036" -> { ["24"] = { keys }, ["25"] = { keys } }
pcall(function()
    local d = json.load_file(SOUNDS_FILE)
    if type(d) ~= "table" then return end
    if type(d.jobs) == "table" then for k, v in pairs(d.jobs) do if tonumber(k) and type(v) == "string" and not v:find("Trigger:") then jobs[tonumber(k)] = v end end end
    if type(d.names) == "table" then names = d.names end
    if type(d.on_player) == "table" then on_player = d.on_player end
    if type(d.learned) == "table" then
        for w, g in pairs(d.learned) do   -- only the keyed form (the first learned lists were bare slot numbers: dropped)
            if type(g) == "table" then
                for f, keys in pairs(g) do   -- only Wwise trigger keys last between runs
                    if type(keys) == "table" and type(keys[1]) == "string" and keys[1]:find("^wwise:") then learned[w] = learned[w] or {}; learned[w][f] = keys end
                end
            end
        end
    end
end)
local function save()
    pcall(function()
        local o = {}
        for k, v in pairs(jobs) do o[tostring(k)] = v end
        json.dump_file(SOUNDS_FILE, { jobs = o, learned = learned, names = names, on_player = on_player })
    end)
end
local function weapon_num()
    local b = rawget(_G, "visceral_re8_bridge")
    local n = b and b.ready() and b.r(S_WEAPON_NUM)
    return n and math.floor(n + 0.5) or 0
end

local heard, heard_order = {}, {}   -- key -> { n, where, how, motion, t }
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

local run = nil                    -- the motion run being recorded: { motion, weapon, keys, last }
local replaying = false            -- our own replay is heard by the same hook: never part of a run
local ctx = {}                     -- key -> the newest { name, this, go, layer, tracks, slot } it was heard with
local seq_m = {}                   -- call name -> method

local function note(key, where, how, motion)
    local h = heard[key]
    if h == nil then
        if #heard_order >= HEARD_MAX then heard[table.remove(heard_order, 1)] = nil end
        h = { n = 0 }
        heard[key] = h
        heard_order[#heard_order + 1] = key
    end
    h.n = h.n + 1
    h.where, h.how, h.motion, h.t = where, how, motion, os.clock()
    if h.n <= LOG_PER_ID then L(string.format("heard %s '%s' on %s (upper motion %s), #%d", key, tostring(names[key] or "?"), tostring(where), tostring(motion), h.n)) end
end

local function finish_run()
    local r = run
    run = nil
    if r == nil or #r.keys == 0 or r.weapon == 0 then return end
    local fam = math.floor(r.motion / 100)
    if fam ~= FAM_FIRE and fam ~= FAM_RELOAD then return end
    local w, f = tostring(r.weapon), tostring(fam)
    learned[w] = learned[w] or {}
    local old = learned[w][f]
    if old ~= nil and #old >= #r.keys then return end   -- keep the fullest run seen (an empty-gun reload has the most)
    learned[w][f] = r.keys
    save()
    L(string.format("learned gun %s's %s sounds: %s", w, fam == FAM_FIRE and "after-the-shot" or "reload", table.concat(r.keys, " ")))
end

local function record(key, motion)   -- one sound of a weapon motion: part of the run of that motion
    if motion == nil or replaying then return end
    local now = os.clock()
    if run ~= nil and (run.motion ~= motion or now - run.last > RUN_QUIET_SEC) then finish_run() end
    if run == nil then run = { motion = motion, weapon = weapon_num(), keys = {}, last = now } end
    run.last = now
    if run.keys[#run.keys] ~= key then run.keys[#run.keys + 1] = key end
end

-- a context is kept alive (add_ref) only while it is the newest for its key; the one it replaces is let go (release)
local function same(a, b) return a == b or (a ~= nil and b ~= nil and safe(function() return a:get_address() == b:get_address() end)) end
local function hold(c) for _, k in ipairs({ "this", "go", "layer", "tracks" }) do local o = c[k]; if o ~= nil then pcall(function() o:add_ref() end) end end end
local function drop(c) for _, k in ipairs({ "this", "go", "layer", "tracks" }) do local o = c[k]; if o ~= nil then pcall(function() o:release() end) end end end
local function store(key, c)
    local o = ctx[key]
    if o ~= nil and same(o.this, c.this) and same(o.go, c.go) and same(o.layer, c.layer) and same(o.tracks, c.tracks) then return end
    if o ~= nil then drop(o) end
    hold(c)
    ctx[key] = c
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
                        note("container:" .. id, (gname == pname) and "player" or gname, name, upper_motion())
                    end, function(r) return r end)
                end)
                if ok then n = n + 1 end
            end
        end
        L("listening on " .. n .. " WwiseContainer trigger method(s)")
    end
    local sq = sdk.find_type_definition("app.WwiseWeaponMotionSequence")
    if sq == nil then L("no app.WwiseWeaponMotionSequence type: the weapon handling sounds cannot be heard") return end
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
                    local motion = layer and safe(function() return layer:call("get_MotionID") end)
                    local tid = tracks and safe(function() return tracks:call("get_TriggerId") end)
                    if tid == nil or tid == 0 then return end
                    local key = "wwise:" .. tostring(tid)
                    if names[key] == nil then
                        names[key] = tostring(safe(function() return tracks:call("get_TriggerIdName") end) or "?")
                    end
                    local onchar = safe(function() return tracks:get_field("OnCharacter") end)
                    if go ~= nil and not onchar then store(key, { go = go }) end   -- heard on the weapon: played there
                    if onchar and not on_player[key] then on_player[key] = true end
                    note(key, onchar and "the player" or "the weapon", name, motion)
                    record(key, motion)
                end, function(r) return r end)
            end)
            if ok then n = n + 1 end
        end
    end
    L("listening on " .. n .. " WwiseWeaponMotionSequence trigger method(s) (the weapon handling sounds)")
end
pcall(hook)

local function container_of(go)
    return go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.wwise.WwiseContainer")) end)
end
local function play(key)
    local id = key and tonumber(key:match("^%a+:(%d+)$"))
    if id == nil then return false, "no sound" end
    if trigger_m == nil then return false, "no WwiseContainer.trigger" end
    local c = ctx[key]
    local wcont = c and container_of(c.go)
    if wcont == nil then   -- the weapon in hand now (a later run, or a sound learned in flat)
        local w = rawget(_G, "re8vr") and re8vr.weapon
        wcont = container_of(w and safe(function() return w:call("get_GameObject") end))
    end
    local pcont = container_of(player_go())
    local order = on_player[key] and { pcont or false, wcont or false } or { wcont or false, pcont or false }
    for _, cont in ipairs(order) do
        if cont and pcall(function() trigger_m:call(cont, id) end) then
            played = played + 1
            return true, (cont == pcont) and "on the player" or "on the weapon"
        end
    end
    return false, "no sound container"
end

-- the learned sound for a handling sound, for the gun in hand (counted from the end of the run)
-- 2026-10-24, flat run driven by the session (virtual pad, the game's own fire and reload): each gun's own handling sounds,
-- picked by NAME and timing (`[measured 2026-10-24, n=1-2 per gun]`, which one is which is `[hypothesis]` until heard):
--   LEMI empty reload, from the magazine release: E 0.0 s, TAKE_SHELL 0.2, B 0.6, A 0.7, C 1.1, D + F together 1.5,
--     HAND_WEAK 2.3 -> the slide back = C, the slide home = D + F.
--   M1897 after a shot (motion 2422): one sound, SHOTGUN_MVT_PUMP -> played as the pump comes back.
--   F2 Rifle after a shot (2422): GRAB_LEVER, PICKUP_I, PICKUP_H, HAND_RELOAD_A -> up, back, forward, down.
-- A trigger id is the RE Engine name hash: murmur3_32 of the UTF-16LE name, seed 0xFFFFFFFF (checked on three).
local GUN_SOUNDS = {
    ["3046"] = { [1] = { "wwise:3326354725" },                         -- SND_MOT_RI3046_SE_RELOAD_C
                 [2] = { "wwise:2079149791", "wwise:3043993691" } },   -- SND_MOT_RI3046_SE_RELOAD_D, _F
    ["3036"] = { [3] = { "wwise:3138231974" }, [4] = {} },            -- SND_MOT_RI_SE_SHOTGUN_MVT_PUMP (one sound, both ways)
    ["3042"] = { [5] = { "wwise:3835880431" },                         -- SND_MOT_RI3042_SE_GRAB_LEVER
                 [6] = { "wwise:3430096898" },                         -- SND_MOT_RI_SE_SHOTGUN_PICKUP_I
                 [7] = { "wwise:1762366329" },                         -- SND_MOT_RI_SE_SHOTGUN_PICKUP_H
                 [8] = { "wwise:3713528881" } },                       -- SND_MOT_RI_SE_SHOTGUN_HAND_RELOAD_A
}
local FROM_END = { [2] = { FAM_RELOAD, 1 }, [3] = { FAM_FIRE, 2 }, [4] = { FAM_FIRE, 1 },
                   [5] = { FAM_FIRE, 4 }, [6] = { FAM_FIRE, 3 }, [7] = { FAM_FIRE, 2 }, [8] = { FAM_FIRE, 1 } }
local function learned_key(code)
    local e = FROM_END[code]
    local g = e and learned[tostring(weapon_num())]
    local keys = g and g[tostring(e[1])]
    if type(keys) ~= "table" or #keys < e[2] then return nil end
    return keys[#keys - e[2] + 1]
end
-- the sounds for a handling sound: set by hand in the menu, else the gun's own (GUN_SOUNDS), else counted from the learned run
local function job_keys(code)
    if jobs[code] then return { jobs[code] } end
    local g = GUN_SOUNDS[tostring(weapon_num())]
    if g and g[code] then return g[code] end
    local k = learned_key(code)
    return k and { k } or nil
end
local function job_key(code) local k = job_keys(code); return k and k[1] or nil end

re.on_pre_application_entry("UpdateHID", function()
    local b = rawget(_G, "visceral_re8_bridge")
    if not b or not b.ready() then return end
    local mask = 0
    for code = 1, 8 do if job_key(code) then mask = mask | (1 << code) end end
    b.w(S_SFX_LUA_HAS, mask)
    if run ~= nil and os.clock() - run.last > RUN_QUIET_SEC then finish_run() end
    local seq = b.r(S_SFX_SEQ)
    if seq_seen == nil then seq_seen = seq return end
    if seq == seq_seen then return end
    seq_seen = seq
    local code = math.floor(b.r(S_SFX_CODE) + 0.5)
    for _, key in ipairs(job_keys(code) or {}) do
        local ok, how = play(key)
        L(string.format("handling sound %d -> %s '%s': %s (%s)", code, key, tostring(names[key] or "?"), ok and "played" or "FAILED", how))
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 sounds") then return end
    imgui.text(string.format("handling sounds played: %d", played))
    for _, j in ipairs(JOBS) do
        local key = job_key(j.code)
        imgui.text(string.format("%d. %s: %s%s", j.code, j.name, key or "(none)", (key and not jobs[j.code]) and " (learned)" or ""))
        imgui.same_line()
        if imgui.button("clear##" .. j.code) then jobs[j.code] = nil; save() end
    end
    local wn = tostring(weapon_num())
    local g = learned[wn]
    imgui.text(string.format("gun %s learned: after the shot %s | reload %s", wn,
        g and g["24"] and table.concat(g["24"], " ") or "(not yet: fire once)",
        g and g["25"] and table.concat(g["25"], " ") or "(not yet: one game reload)"))
    if g and imgui.button("forget this gun's learned sounds") then learned[wn] = nil; save(); L("forgot gun " .. wn .. "'s learned sounds") end
    imgui.text("Heard from the player and the guns (newest last). Play, then give it a job:")
    for i = #heard_order, 1, -1 do
        local key = heard_order[i]
        local h = heard[key]
        if h then
            imgui.text(string.format("%s  %s  motion %s  x%d", key, tostring(names[key] or "?"), tostring(h.motion), h.n))
            imgui.same_line()
            if imgui.button("Play##" .. key) then local ok, how = play(key); L(string.format("Play %s: %s (%s)", key, ok and "played" or "FAILED", how)) end
            for _, j in ipairs(JOBS) do
                imgui.same_line()
                if imgui.button(j.code .. "##" .. key) then jobs[j.code] = key; save(); L(string.format("job %d (%s) = %s", j.code, j.name, key)) end
            end
        end
    end
    imgui.tree_pop()
end)

L("loaded: " .. (next(jobs) and "game sounds set for some handling sounds" or "no game sounds set by hand"))
