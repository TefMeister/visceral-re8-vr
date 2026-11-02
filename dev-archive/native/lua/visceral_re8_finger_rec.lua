-- visceral_re8_finger_rec.lua -- records the game's own finger animations (2026-11-02, new code).
--
-- Tefa, 2026-11-02: "default hand animations, just the hand and fingers, so wrists are not locked and hands can still be
-- naturally moved in vr. can you run through every default game reloading, grip and docked pose for hands and fingers
-- and record them somehow, so then we can use these hand grip poses when gripping weapons in VR". Step 1 of that job:
-- while the game plays its own reload / grip / idle animations, write every finger joint's LOCAL rotation, every frame,
-- labelled by gun and by the animation each motion layer is playing. Wrists are written too, as a reference only.
--
-- Driven by a command file so nobody has to touch the game window:
--   reframework/data/finger_rec/command.txt, one line:
--     start <label>   begin a take (file finger_rec/<label>__<gun>__<n>.csv)
--     stop            end the take
--     empty           empty the held gun (so the next reload is the full one); the gun's record, as player.cpp does
--     fill            fill the held gun to capacity
--     probe           write finger_rec/probe.txt: which transforms carry finger joints, which carry a motion
--     guns            write finger_rec/guns.txt: every gun the inventory holds, by id (2026-11-02)
--     equip <id>      take that gun out (e.g. equip ri3051) with Andyalpa's proven native equip (re8_vr_holster.lua)
-- The file is deleted once read. Status goes to finger_rec/status.txt and the REFramework log ("[finger-rec]").
-- Off when no command comes: it costs nothing until a take starts.

if reframework:get_game_name() ~= "re8" then return end

local TAG = "[finger-rec]"
local DIR = "finger_rec"
local CMD = DIR .. "/command.txt"
local FINGERS = { "IndexF1", "IndexF2", "IndexF3", "MiddleF1", "MiddleF2", "MiddleF3", "RingF1", "RingF2", "RingF3",
                  "PinkyF1", "PinkyF2", "PinkyF3", "Thumb1", "Thumb2", "Thumb3" }
local WRISTS = { "L_Hand", "R_Hand" }
local motion_t = sdk.typeof("via.motion.Motion")

local rec = { on = false, f = nil, label = "", n = 0, frames = 0, t0 = 0, last_poll = 0, takes = 0 }

local function say(s) print(TAG .. " " .. s); pcall(function() log.info(TAG .. " " .. s) end) end
local function safe(fn) local ok, v = pcall(fn); if ok then return v end return nil end

local function status(s)
    local f = safe(function() return io.open(DIR .. "/status.txt", "w") end)
    if f then f:write(os.date("%H:%M:%S") .. " " .. s .. "\n"); f:close() end
    print(TAG .. " " .. s)
end

-- ---------------------------------------------------------------- the player, the gun, the transforms with fingers
local function player()
    local pm = safe(function() return sdk.get_managed_singleton("app.PropsManager") end)
    return pm and safe(function() return pm:get_field("<Player>k__BackingField") end)
end

local function updater(pl)
    for _, tn in ipairs({ "app.PlayerUpdater", "app.PlayerUpdaterFPS" }) do
        local t = safe(function() return sdk.typeof(tn) end)
        local u = t and safe(function() return pl:call("getComponent(System.Type)", t) end)
        if u then return u end
    end
    return nil
end

local function gun_and_name(pl)
    local u = pl and updater(pl)
    local pg = u and safe(function() return u:call("get_playerGun") end)
    local w = pg and safe(function() return pg:call("get_equipWeaponObject") end)
    local go = w and (safe(function() return w:call("get_GameObject") end) or safe(function() return w:get_field("<owner>k__BackingField") end))
    local nm = go and safe(function() return go:call("get_Name") end)
    return w, nm and tostring(nm) or "none", pg
end

-- every transform worth reading: the player's own and the arm / body meshes the mesh controller owns
local function transforms(pl)
    local out = {}
    local tf = safe(function() return pl:call("get_Transform") end)
    if tf then out[#out + 1] = { tf = tf, src = "player" } end
    local u = updater(pl)
    local mc = u and safe(function() return u:call("get_playerMeshController") end)
    if mc then
        for _, field in ipairs({ "UpperBodyMesh", "LowerBodyMesh", "LArmMesh", "RArmMesh" }) do
            local mesh = safe(function() return mc:get_field(field) end)
            local go = mesh and safe(function() return mesh:call("get_GameObject") end)
            local t = go and safe(function() return go:call("get_Transform") end)
            if t then out[#out + 1] = { tf = t, src = field } end
        end
    end
    return out
end

local function joint(tf, name) return safe(function() return tf:call("getJointByName", name) end) end

-- the joints to write: for each transform that has them, L_ and R_ fingers plus the wrists
local cache = { pl = nil, list = nil, t = 0 }
local function joint_list(pl)
    if cache.pl == pl and cache.list and os.clock() - cache.t < 5 then return cache.list end
    local list = {}
    for _, e in ipairs(transforms(pl)) do
        for _, side in ipairs({ "L_", "R_" }) do
            for _, f in ipairs(FINGERS) do
                local j = joint(e.tf, side .. f)
                if j then list[#list + 1] = { j = j, name = e.src .. ":" .. side .. f } end
            end
        end
        for _, w in ipairs(WRISTS) do
            local j = joint(e.tf, w)
            if j then list[#list + 1] = { j = j, name = e.src .. ":" .. w } end
        end
    end
    cache.pl, cache.list, cache.t = pl, list, os.clock()
    return list
end

-- the motion layers playing on the player and on each mesh: bank id, motion id, frame
local function motions(pl)
    local out = {}
    for _, e in ipairs(transforms(pl)) do
        local go = safe(function() return e.tf:call("get_GameObject") end)
        local mo = go and motion_t and safe(function() return go:call("getComponent(System.Type)", motion_t) end)
        if mo then
            local n = safe(function() return mo:call("getLayerCount") end) or 0
            for i = 0, math.min(n, 6) - 1 do
                local L = safe(function() return mo:call("getLayer", i) end)
                if L then
                    local bank = safe(function() return L:call("get_MotionBankID") end) or -1
                    local id = safe(function() return L:call("get_MotionID") end) or -1
                    local fr = safe(function() return L:call("get_Frame") end) or -1
                    out[#out + 1] = string.format("%s.%d:%s:%s:%.1f", e.src, i, tostring(bank), tostring(id), tonumber(fr) or -1)
                end
            end
        end
    end
    return table.concat(out, "|")
end

-- ---------------------------------------------------------------- ammo, as player.cpp does it
local function set_loaded(w, n)
    local work = w and safe(function() return w:call("get_work") end)
    if not work then return false end
    local sub = (safe(function() return w:call("get_usingBulletIndex") end) or 0) == 1
    if n == nil then
        n = safe(function() return work:call("getMaxIncludeStackSize") end) or safe(function() return w:call("getMaxIncludeStackSize") end) or 6
    end
    local ok = pcall(function() work:call(sub and "set_includeStackSizeSub(System.Int32)" or "set_includeStackSize(System.Int32)", n) end)
    return ok, n
end

-- ---------------------------------------------------------------- takes
local function start(label)
    local pl = player()
    if not pl then status("no player: not started"); return end
    local _, gname = gun_and_name(pl)
    rec.n = rec.n + 1
    local path = string.format("%s/%s__%s__%d.csv", DIR, label, gname, rec.n)
    rec.f = safe(function() return io.open(path, "w") end)
    if not rec.f then status("could not open " .. path); return end
    local list = joint_list(pl)
    local head = { "t", "gun", "reloading", "motions" }
    for _, e in ipairs(list) do head[#head + 1] = e.name .. ".x"; head[#head + 1] = e.name .. ".y"; head[#head + 1] = e.name .. ".z"; head[#head + 1] = e.name .. ".w" end
    rec.f:write(table.concat(head, ",") .. "\n")
    rec.on, rec.label, rec.frames, rec.t0, rec.path = true, label, 0, os.clock(), path
    status(string.format("recording %s (%d joints)", path, #list))
end

local function stop()
    if rec.f then rec.f:close() end
    if rec.on then status(string.format("stopped %s: %d frames, %.1f s", rec.path or "?", rec.frames, os.clock() - rec.t0)) end
    rec.on, rec.f = false, nil
end

local function probe()
    local pl = player()
    local f = safe(function() return io.open(DIR .. "/probe.txt", "w") end)
    if not f then return end
    if not pl then f:write("no player\n"); f:close(); return end
    local w, gname = gun_and_name(pl)
    f:write("gun: " .. gname .. "\n")
    for _, e in ipairs(transforms(pl)) do
        local n = 0
        for _, side in ipairs({ "L_", "R_" }) do for _, fn in ipairs(FINGERS) do if joint(e.tf, side .. fn) then n = n + 1 end end end
        local go = safe(function() return e.tf:call("get_GameObject") end)
        local mo = go and motion_t and safe(function() return go:call("getComponent(System.Type)", motion_t) end)
        f:write(string.format("%s: %d finger joints, motion %s\n", e.src, n, mo and "yes" or "no"))
    end
    f:write("motions now: " .. motions(pl) .. "\n")
    f:close()
    status("probe written")
end

-- 2026-11-02: the guns the quick slots do not hold, for the takes. The inventory walk is re8_vr_holster.lua's
-- inventory_rows(), shortened; the equip is its exported __re8_holster_equip_item (the D-pad path).
local function inventory_guns()
    local out = {}
    local im = safe(function() return sdk.get_managed_singleton("app.InventoryManager") end)
    local inv = im and safe(function() return im:call("get_activeInventory") end)
    local list = inv and (safe(function() return inv:call("get_items") end) or safe(function() return inv:get_field("<items>k__BackingField") end))
    local n = list and safe(function() return list:call("get_Count") end) or 0
    local weapon_of = rawget(_G, "__re8_holster_item_weapon")
    for i = 0, (n or 0) - 1 do
        local e = safe(function() return list:call("get_Item", i) end)
        local item = e
        if e and not safe(function() return e:get_type_definition():is_a("app.ItemCore") end) then
            item = safe(function() return e:get_field("<Item>k__BackingField") end) or safe(function() return e:get_field("Item") end) or e
        end
        local id = item and safe(function() return item:call("get_weaponName") end)
        local w = item and type(weapon_of) == "function" and safe(function() return weapon_of(item) end)
        if id and tostring(id) ~= "" and w then out[#out + 1] = { id = tostring(id), item = item } end
    end
    return out
end

local function poll()
    local f = safe(function() return io.open(CMD, "r") end)
    if not f then return end
    local line = f:read("*l") or ""
    f:close()
    pcall(function() os.remove(CMD) end)
    pcall(function() fs.write(CMD, "") end)
    local cmd, arg = line:match("^%s*(%S+)%s*(.-)%s*$")
    if not cmd or cmd == "" then return end
    if cmd == "start" then stop(); start(arg ~= "" and arg or "take")
    elseif cmd == "stop" then stop()
    elseif cmd == "empty" or cmd == "fill" then
        local w = gun_and_name(player() or false)
        local ok, n = set_loaded(w, cmd == "empty" and 0 or nil)
        status(string.format("%s: %s (%s)", cmd, ok and "done" or "failed", tostring(n)))
    elseif cmd == "probe" then probe()
    elseif cmd == "guns" then
        local ids = {}
        for _, g in ipairs(inventory_guns()) do ids[#ids + 1] = g.id end
        pcall(function() fs.write(DIR .. "/guns.txt", table.concat(ids, "\n") .. "\n") end)
        status("guns: " .. #ids .. " (" .. table.concat(ids, " ") .. ")")
    elseif cmd == "equip" then
        local eq, done = rawget(_G, "__re8_holster_equip_item"), false
        for _, g in ipairs(inventory_guns()) do
            if g.id == arg and type(eq) == "function" then local ok, r = pcall(eq, g.item, "finger_rec"); done = ok and r == true end
        end
        status(string.format("equip %s: %s", arg, done and "done" or "FAILED (not owned, or no equip function)"))
    else status("unknown command: " .. line) end
end

re.on_frame(function()
    local now = os.clock()
    if now - rec.last_poll > 0.2 then rec.last_poll = now; pcall(poll) end
    if not rec.on or not rec.f then return end
    local pl = player()
    if not pl then return end
    local _, gname, pg = gun_and_name(pl)
    local reloading = safe(function() return pg and pg:call("get_isReload") end)
    local row = { string.format("%.4f", now - rec.t0), gname, tostring(reloading), motions(pl) }
    for _, e in ipairs(joint_list(pl)) do
        local q = safe(function() return e.j:call("get_LocalRotation") end)
        if q then
            row[#row + 1] = string.format("%.5f", q.x); row[#row + 1] = string.format("%.5f", q.y)
            row[#row + 1] = string.format("%.5f", q.z); row[#row + 1] = string.format("%.5f", q.w)
        else
            row[#row + 1] = ""; row[#row + 1] = ""; row[#row + 1] = ""; row[#row + 1] = ""
        end
    end
    rec.f:write(table.concat(row, ",") .. "\n")
    rec.frames = rec.frames + 1
    if rec.frames % 120 == 0 then rec.f:flush() end
end)

say("ready: write a command into reframework/data/" .. CMD)
