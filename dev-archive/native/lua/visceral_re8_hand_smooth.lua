-- visceral_re8_hand_smooth.lua -- steadier hands: a One Euro filter on both controllers, put in where praydog's VR layer
-- turns the controllers into the game's hands (2026-11-01, Tefa: "is there a way to add some smoothing to the motion
-- controls ... to reduce the hand shakyness", then "yes for hand smoothing").
--
-- WHY THE SHAKE IS THE HAND: the Ghost Hand run of 2026-10-31 22:29 shows the game adds none of its own (the game's hand
-- wanders 0.5-0.8 cm at 95%, the same as the controller) [measured 2026-10-31]; a long gun makes a small wrist tremor big
-- at the muzzle.
--
-- HOW: REFramework's RE8VR::update_hand_ik (src/mods/vr/games/RE8VR.cpp) builds each hand as
--     rot = C * Rc * Qoff        pos = cam + C * (Pc - Phmd) + C * Rc * Poff
-- from the controller (Rc, Pc), the camera turn C, and the hand offsets re8vr.<side>_hand_rotation_offset / _position_offset.
-- To get the hand of a SMOOTHED controller (Rs, Ps) instead, the offsets are set, right before each update_hand_ik, to
--     Qoff' = Rc^-1 * Rs * Qoff          Poff' = Rc^-1 * ((Ps - Pc) + Rs * Poff)
-- so everything after it (the grip, the reloads, the muzzle, the bullet, the scope) sees the steadier hand.
-- The hook is re8_vr.lua's __re8_arm_ik_update_override, chained (the holster script's heal hold chains it too).
--
-- ONE EURO FILTER (Casiez, Roussel, Vogel 2012): steady when the hand moves slowly, no drag when it moves fast, because the
-- cut-off rises with speed. Filtered in the tracking space, so turning, walking and the head do not smear it.
--
-- PROVES ITSELF: every 10 s the log says how much frame-to-frame turn the gun hand had while held still, raw and smoothed.
-- Menu: "Visceral RE8 hand smoothing" (on / off, strength, which hands). Saved in visceral_re8/hand_smooth.json.
--
-- PER GUN (2026-11-08, Tefa: "a system that allows me to switch on and off hand smoothing on guns individually, both left,
-- right or both hands"): cfg.guns[<gun id>] = "off" | "left" | "right" | "both"; a gun with no entry follows the default
-- (cfg.left / cfg.right). Set for the gun in hand from the Visceral Emporium (Comfort: "Smoothing on the <gun>") or the
-- REFramework menu; each gun remembers its own. Melee and bare hands stay raw whatever is set (the 2026-11-02 rule).

local TAG = "[visceral-re8-smooth]"
local FILE = "visceral_re8/hand_smooth.json"

-- strength 0..10 -> the cut-off when still: 12 Hz * 0.65^strength (4 = 2.1 Hz, about 75 ms of settling; 10 = 0.16 Hz)
local CUTOFF_TOP_HZ, CUTOFF_STEP = 12.0, 0.65
-- the cut-off's rise with speed, at strength 0; each strength step keeps BETA_STEP of it, so a heavy setting stays heavy
-- while aiming slowly (2026-11-01, first wear: "i don't think the hand smoothing works"; strength 0 and 10 logged alike)
local BETA_ROT = 6.0          -- per rad/s of turn: at strength 4 a 3 rad/s flick is still followed at ~9 Hz
local BETA_POS = 20.0         -- per m/s of move
local BETA_STEP = 0.8
local D_CUTOFF_HZ = 1.0       -- the speed estimate's own cut-off (the paper's 1 Hz)
local SNAP_M, SNAP_RAD = 0.5, 1.0   -- a jump bigger than this in one frame (recentre, tracking lost) is taken as it is
local DT_MIN, DT_MAX = 1 / 500, 0.1
local STILL_RAD_S = 0.35      -- "held still" for the proof line: the raw hand turning slower than this
local REPORT_S = 10.0

local cfg = { on = true, strength = 4, right = true, left = true, guns = {} }
pcall(function()
    local f = json.load_file(FILE)
    if type(f) == "table" then for k, v in pairs(f) do cfg[k] = v end end
end)
if type(cfg.guns) ~= "table" then cfg.guns = {} end
-- 2026-11-09 (Tefa: "hand smoothing has to be individual on each gun ... aiming the Lemi is just "off" with hand smoothing, while
-- aiming the shotgun felt really good"): each gun may keep its own strength too, cfg.gun_strength[<gun id>] = 0..10; none =
-- the default strength
if type(cfg.gun_strength) ~= "table" then cfg.gun_strength = {} end
local cur_gun = nil   -- the short id of the gun in hand ("ri3008"), nil with the knife or bare hands (gun_in_hand)
local GUN_NAMES = { ri3008 = "M1851 Wolfsbane", ri3021 = "W870 TAC", ri3023 = "GM 79", ri3036 = "M1897", ri3040 = "M1911",
    ri3042 = "F2 Rifle", ri3046 = "LEMI", ri3047 = "V61 Custom", ri3048 = "SYG-12", ri3050 = "S.T.A.K.E",
    ri3122 = "Samurai Edge AW-01" }
local function gun_label(id) return id and (GUN_NAMES[id] or id) or "gun in hand" end
local MODES = { "default", "off", "left", "right", "both" }   -- the per-gun choice, in the menu's order
local function save() pcall(function() json.dump_file(FILE, cfg) end) end
local function strength_now()   -- the gun in hand's own strength, else the default
    local s = cur_gun and tonumber(cfg.gun_strength[cur_gun]) or nil
    return math.max(0, math.min(10, s or tonumber(cfg.strength) or 4))
end

-- ---- small maths ----------------------------------------------------------------------------------------------------------
local function alpha(cutoff_hz, dt) local tau = 1.0 / (2 * math.pi * cutoff_hz); return 1.0 / (1.0 + tau / dt) end
local function v3(v) return Vector3f.new(v.x, v.y, v.z) end
local function lerp3(a, b, t) return Vector3f.new(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t) end
local function len3(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function qdot(a, b) return a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z end
local function qangle(a, b) local d = math.min(1.0, math.abs(qdot(a, b))); return 2 * math.acos(d) end
local function nlerp(a, b, t)   -- the short way round; per-frame steps are small, so nlerp is as good as slerp here
    local s = qdot(a, b) < 0 and -1 or 1
    return Quaternion.new(a.w + (s * b.w - a.w) * t, a.x + (s * b.x - a.x) * t, a.y + (s * b.y - a.y) * t, a.z + (s * b.z - a.z) * t):normalized()
end
local function qsame(a, b) return a ~= nil and b ~= nil and math.abs(a.w - b.w) < 1e-6 and math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6 and math.abs(a.z - b.z) < 1e-6 end
local function vsame(a, b) return a ~= nil and b ~= nil and math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6 and math.abs(a.z - b.z) < 1e-6 end

-- ---- one hand ---------------------------------------------------------------------------------------------------------------
-- side: "left" / "right"; ci: 1 / 2 in vrmod:get_controllers()
local function new_hand(side, ci)
    return { side = side, ci = ci, have = false, rs = nil, ps = nil, wspeed = 0, vspeed = 0,
             q_int = nil, p_int = nil, q_out = nil, p_out = nil,   -- the offsets someone else wants (intended), and ours as written
             raw_sum = 0, out_sum = 0, still_n = 0 }
end
local hands = { new_hand("left", 1), new_hand("right", 2) }
local function default_wanted(h) return (h.side == "right" and cfg.right) or (h.side == "left" and cfg.left) end
local function wanted(h)
    local m = cur_gun and cfg.guns[cur_gun]
    if m == "off" then return false end
    if m == "both" then return true end
    if m == "left" or m == "right" then return h.side == m end
    return default_wanted(h)
end

local function offsets_get(h)
    local q, p = nil, nil
    pcall(function() q = re8vr[h.side .. "_hand_rotation_offset"]; p = re8vr[h.side .. "_hand_position_offset"] end)
    return q, p
end
local function offsets_set(h, q, p)
    pcall(function()
        re8vr[h.side .. "_hand_rotation_offset"] = q
        re8vr[h.side .. "_hand_position_offset"] = p
    end)
    h.q_out, h.p_out = offsets_get(h)   -- read back, so the next compare is against what is really stored
end
-- whoever else set the offsets (re8_vr.lua's own menu or its late OpenXR fix, the zones script's aim trim) is the intended
-- value: anything there that is not what we wrote last
local function track_intended(h)
    local q, p = offsets_get(h)
    if q == nil or p == nil then return false end
    if h.q_int == nil or not qsame(q, h.q_out) then h.q_int = Quaternion.new(q.w, q.x, q.y, q.z) end
    if h.p_int == nil or not vsame(p, h.p_out) then h.p_int = Vector4f.new(p.x, p.y, p.z, p.w or 0) end
    return true
end
local function restore(h)
    if h.q_int ~= nil and h.q_out ~= nil then offsets_set(h, h.q_int, h.p_int) end
    h.q_out, h.p_out, h.have = nil, nil, false
end

-- the filter: once a frame per hand
-- ⚠️ the speed is the CONTROLLER's own (this frame against the last), as in Casiez's reference code. The first build
-- (2026-11-01 00:05) took it from the gap between the smoothed hand and the controller: the harder it smoothed, the wider
-- the gap, the faster the hand looked, the more it let through, so every strength ended up about the same.
local function step(h, rc, pc, dt)
    if not h.have or h.raw_prev == nil then h.rs, h.ps, h.wspeed, h.vspeed, h.have, h.raw_prev, h.rawp_prev = rc, pc, 0, 0, true, rc, pc; return end
    local gap_ang, gap_dist = qangle(h.rs, rc), len3(Vector3f.new(pc.x - h.ps.x, pc.y - h.ps.y, pc.z - h.ps.z))
    local ang, dist = qangle(h.raw_prev, rc), len3(Vector3f.new(pc.x - h.rawp_prev.x, pc.y - h.rawp_prev.y, pc.z - h.rawp_prev.z))
    h.raw_prev, h.rawp_prev = rc, pc
    if gap_ang > SNAP_RAD or gap_dist > SNAP_M or ang > SNAP_RAD or dist > SNAP_M then h.rs, h.ps, h.wspeed, h.vspeed = rc, pc, 0, 0; return end
    local ad = alpha(D_CUTOFF_HZ, dt)
    h.wspeed = h.wspeed + (ang / dt - h.wspeed) * ad
    h.vspeed = h.vspeed + (dist / dt - h.vspeed) * ad
    local st = strength_now()
    local still_hz, beta_k = CUTOFF_TOP_HZ * CUTOFF_STEP ^ st, BETA_STEP ^ st
    local prev_rs = h.rs
    h.rs = nlerp(h.rs, rc, alpha(still_hz + BETA_ROT * beta_k * h.wspeed, dt))
    h.ps = lerp3(h.ps, pc, alpha(still_hz + BETA_POS * beta_k * h.vspeed, dt))
    -- the proof: frame-to-frame turn, raw and smoothed, while the hand is held still
    if ang / dt < STILL_RAD_S then
        h.raw_sum = h.raw_sum + ang
        h.out_sum = h.out_sum + qangle(prev_rs, h.rs)
        h.still_n = h.still_n + 1
        h.still_frame = true
    else
        h.still_frame = false
    end
end

-- the offsets that make update_hand_ik draw the smoothed controller (the formulas at the top)
local function apply(h, rc, pc)
    local ri = rc:inverse()
    local q = (ri * h.rs * h.q_int):normalized()
    local poff = v3(h.p_int)
    local rp = h.rs * poff
    local p = ri * Vector3f.new(h.ps.x - pc.x + rp.x, h.ps.y - pc.y + rp.y, h.ps.z - pc.z + rp.z)
    offsets_set(h, q, Vector4f.new(p.x, p.y, p.z, h.p_int.w or 0))
end

-- ---- the hook ---------------------------------------------------------------------------------------------------------------
local frame_id, stepped_frame = 0, -1
local last_t = os.clock()
local last_report = os.clock()
local errors = 0
re.on_frame(function() frame_id = frame_id + 1 end)

-- 2026-11-02, Tefa: "hand smoothing must always be off for melee weapons in any game, only option for guns. smooth melee
-- feels so bad in vr". A real gun (app.WeaponGunCore) in hand, looked up five times a second; the knife and bare hands are not.
local gun_cache = { t = -1, yes = false }
local gun_core_t = nil
local function gun_in_hand()
    local now = os.clock()
    if now - gun_cache.t < 0.2 then return gun_cache.yes end
    gun_cache.t = now
    local yes, id = false, nil
    pcall(function()
        gun_core_t = gun_core_t or sdk.find_type_definition("app.WeaponGunCore")
        local pm = sdk.get_managed_singleton("app.PropsManager")
        local pl = pm and pm:get_field("<Player>k__BackingField")
        local u = nil
        for _, tn in ipairs({ "app.PlayerUpdater", "app.PlayerUpdaterFPS" }) do
            local t = sdk.typeof(tn)
            u = u or (t and pl and pl:call("getComponent(System.Type)", t))
        end
        local pg = u and u:call("get_playerGun")
        local w = pg and pg:call("get_equipWeaponObject")
        yes = w ~= nil and gun_core_t ~= nil and w:get_type_definition():is_a(gun_core_t)
        if yes then
            local go = w:call("get_GameObject") or w:get_field("<owner>k__BackingField")
            local nm = go and tostring(go:call("get_Name")) or ""
            id = nm:match("^(ri%d+)") or (nm ~= "" and nm or nil)
        end
    end)
    if id ~= cur_gun then
        cur_gun = id
        if id then log.info(string.format("%s %s in hand: smoothing %s", TAG, gun_label(id), cfg.guns[id] or "as the default")) end
    end
    if yes ~= gun_cache.yes then log.info(TAG .. (yes and " working: a gun is in hand" or " paused: no gun in hand (knife, bare hands)")) end
    gun_cache.yes = yes
    return yes
end

local function run()
    if rawget(_G, "re8vr") == nil or vrmod == nil then return end
    local gun = gun_in_hand()   -- every time, so the menus always name the gun in hand
    local active = cfg.on and vrmod:is_hmd_active() and gun
    local ctl = nil
    if active then pcall(function() ctl = vrmod:get_controllers() end) end
    if ctl == nil or ctl[1] == nil or ctl[2] == nil then active = false end
    local new_frame = stepped_frame ~= frame_id
    local now = os.clock()
    local dt = math.max(DT_MIN, math.min(DT_MAX, now - last_t))
    if new_frame then stepped_frame = frame_id; last_t = now end
    -- the game's own right hand (drawn last frame), the number that matters: does the hand on screen turn less?
    if new_frame then
        local gq = nil
        pcall(function() local t = re8vr.right_hand_ik_transform; if t then gq = t:call("get_Rotation") end end)
        local r = hands[2]
        if gq ~= nil then
            gq = Quaternion.new(gq.w, gq.x, gq.y, gq.z)
            if r.game_prev ~= nil and r.still_frame then r.game_sum = (r.game_sum or 0) + qangle(r.game_prev, gq); r.game_n = (r.game_n or 0) + 1 end
            r.game_prev = gq
        end
    end
    for _, h in ipairs(hands) do
        if not track_intended(h) then
        elseif not active or not wanted(h) then
            if h.q_out ~= nil then restore(h) end
            if active and new_frame then   -- still measured while switched off, so on and off compare in the log
                local m = vrmod:get_transform(ctl[h.ci])
                step(h, m:to_quat():normalized(), v3(m[3]), dt)
            end
        else
            local m = vrmod:get_transform(ctl[h.ci])
            local rc = m:to_quat():normalized()
            local pc = v3(m[3])
            if new_frame then step(h, rc, pc, dt) end
            if h.have then apply(h, rc, pc) end
        end
    end
    if now - last_report > REPORT_S then
        last_report = now
        local r = hands[2]
        if r.still_n > 30 then
            local gn = r.game_n or 0
            log.info(string.format("%s gun hand held still (%d frames): controller turn %.4f deg a frame, smoothed %.4f (%.0f%% of the shake taken out), the game's hand %s; strength %s %s",
                TAG, r.still_n, math.deg(r.raw_sum / r.still_n), math.deg(r.out_sum / r.still_n),
                100 * (1 - (r.out_sum / math.max(1e-9, r.raw_sum))),
                gn > 0 and string.format("%.4f", math.deg(r.game_sum / gn)) or "not read",
                tostring(strength_now()) .. ((cur_gun and cfg.gun_strength[cur_gun]) and " (this gun's own)" or ""), (cfg.on and wanted(hands[2])) and "(on)" or "(OFF)"))
        end
        for _, h in ipairs(hands) do h.raw_sum, h.out_sum, h.still_n, h.game_sum, h.game_n = 0, 0, 0, 0, 0 end
    end
end

local prev_override = rawget(_G, "__re8_arm_ik_update_override")
local function our_override()
    local ok, err = pcall(run)
    if not ok then
        errors = errors + 1
        if errors <= 5 then log.info(TAG .. " error (smoothing skipped this time): " .. tostring(err)) end
        for _, h in ipairs(hands) do pcall(restore, h) end
    end
    if type(prev_override) == "function" then
        local ok2, handled = pcall(prev_override)
        if ok2 and handled == true then return true end
    end
    return false
end
rawset(_G, "__re8_arm_ik_update_override", our_override)

-- the zones script's aim trim lays itself over the offsets the VR layer wants, not over our smoothed ones
rawset(_G, "__re8_hand_smooth_intended", function(side)
    for _, h in ipairs(hands) do if h.side == side and h.q_out ~= nil then return h.q_int, h.p_int end end
    return nil
end)

re.on_script_reset(function()
    for _, h in ipairs(hands) do pcall(restore, h) end
    if rawget(_G, "__re8_arm_ik_update_override") == our_override then rawset(_G, "__re8_arm_ik_update_override", prev_override) end
    rawset(_G, "__re8_hand_smooth_intended", nil)
end)

-- ---- the menu ---------------------------------------------------------------------------------------------------------------
re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8 hand smoothing") then return end
    local c, v = imgui.checkbox("Smooth the hands", cfg.on)
    if c then cfg.on = v; save() end
    c, v = imgui.slider_int("Strength (0 = light, 10 = heavy)", math.floor(tonumber(cfg.strength) or 4), 0, 10)
    if c then cfg.strength = v; save() end
    c, v = imgui.checkbox("Right hand (the gun)", cfg.right)
    if c then cfg.right = v; save() end
    c, v = imgui.checkbox("Left hand", cfg.left)
    if c then cfg.left = v; save() end
    imgui.text("(the two boxes above are the default for guns without their own setting)")
    if cur_gun then
        local cur = 1
        for i, m in ipairs(MODES) do if (cfg.guns[cur_gun] or "default") == m then cur = i end end
        c, v = imgui.combo("This gun: " .. gun_label(cur_gun), cur, { "As the default", "Off", "Left hand only", "Right hand only", "Both hands" })
        if c then cfg.guns[cur_gun] = (v > 1) and MODES[v] or nil; save() end
        local own = cfg.gun_strength[cur_gun] ~= nil
        c, v = imgui.checkbox("Own strength for the " .. gun_label(cur_gun), own)
        if c then cfg.gun_strength[cur_gun] = v and math.floor(tonumber(cfg.strength) or 4) or nil; save() end
        if cfg.gun_strength[cur_gun] ~= nil then
            c, v = imgui.slider_int("Strength on the " .. gun_label(cur_gun), math.floor(tonumber(cfg.gun_strength[cur_gun]) or 4), 0, 10)
            if c then cfg.gun_strength[cur_gun] = v; save() end
        end
    else
        imgui.text("Take a gun out to set its own smoothing.")
    end
    imgui.text("Steady when the hand moves slowly; fast moves are followed at once.")
    imgui.tree_pop()
end)

-- ---- the Visceral Emporium (Comfort): this gun's smoothing, and the default -------------------------------------------------
_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
local this_gun = { tab = "comfort", order = 40, kind = "choice", label = "Smoothing on the gun in hand",
    choices = { "As the default", "Off", "Left hand only", "Right hand only", "Both hands" },
    help = "Each gun remembers its own. The knife and bare hands are never smoothed.",
    get = function()
        if not cur_gun then return 1 end
        for i, m in ipairs(MODES) do if (cfg.guns[cur_gun] or "default") == m then return i end end
        return 1
    end,
    set = function(v) if cur_gun then cfg.guns[cur_gun] = (v > 1) and MODES[v] or nil; save() end end }
table.insert(_G.VISCERAL_OPTIONS, this_gun)
-- 2026-11-09: this gun's own strength (1 = as the default, 2..12 = strength 0..10)
local STRENGTH_CHOICES = { "As the default", "0 (light)", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10 (heavy)" }
local this_strength = { tab = "comfort", order = 40.5, kind = "choice", label = "Smoothing strength on the gun in hand",
    choices = STRENGTH_CHOICES,
    help = "Each gun remembers its own; \"As the default\" uses the strength set in the REFramework menu.",
    get = function()
        local s = cur_gun and tonumber(cfg.gun_strength[cur_gun]) or nil
        return s and (math.floor(s) + 2) or 1
    end,
    set = function(v) if cur_gun then cfg.gun_strength[cur_gun] = (v > 1) and (v - 2) or nil; save() end end }
table.insert(_G.VISCERAL_OPTIONS, this_strength)
table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort", order = 41, kind = "choice", label = "Smoothing, the default",
    choices = { "Off", "Left hand only", "Right hand only", "Both hands" },
    help = "For every gun without its own setting.",
    get = function()
        if not cfg.on or (not cfg.left and not cfg.right) then return 1 end
        if cfg.left and cfg.right then return 4 end
        return cfg.left and 2 or 3
    end,
    set = function(v) cfg.on = true; cfg.left = (v == 2 or v == 4); cfg.right = (v == 3 or v == 4); save() end })
re.on_frame(function()   -- the row names the gun in hand
    this_gun.label = cur_gun and ("Smoothing on the " .. gun_label(cur_gun)) or "Smoothing on the gun in hand (none)"
    this_strength.label = cur_gun and ("Smoothing strength on the " .. gun_label(cur_gun)) or "Smoothing strength on the gun in hand (none)"
end)

log.info(TAG .. " loaded (" .. (cfg.on and ("on, strength " .. tostring(cfg.strength)) or "off") .. ")")
