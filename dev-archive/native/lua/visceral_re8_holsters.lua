-- visceral_re8_holsters.lua -- four holster spots on the body, like Visceral RE2 (Tefa idea 15, 2026-10-24: "holsters like
-- re2 ... 4 diagonal points - LEFT SHOULDER, RIGHT SHOULDER, LEFT HIP, RIGHT HIP"). Each spot holds one of the game's four
-- quick slots, in Tefa's RE2 layout (2026-10-05): up = right shoulder, right = right hip, down = left hip, left = left
-- shoulder. That is the game's quick-slot cross turned 45 degrees clockwise, the same turn the thumb-rest D-pad uses
-- (re8_vr.lua: thumb rest + right stick up-right = up, and so on).
-- The right hand in a spot gets a short buzz; the right grip there takes that slot's gun out, or puts it away if it is
-- already in hand. While the right hand is in a spot the grip does not aim (re8_vr.lua reads __visceral_holster_zone).
-- Spots follow the headset's turn, never its tilt (RE2, Tefa 2026-10-05: "no tilt please, just left and right turn").
-- Andyalpa's own hip-pistol and shoulder zones step aside while this runs (re8_vr_holster.lua reads
-- __visceral_holsters_on); his knife, medicine, ammo and head flashlight stay.
-- Equipping: app.PlayerWeaponChange.set_RequestedItem(item) (proven 2026-10-24 by the gun cycler), the item from
-- the active inventory's getItemFromQuickSlot(slot, false) (Andyalpa's holster uses it). Putting away: [hypothesis],
-- see put_away().

local TAG = "[visceral-re8-holsters]"
local ON = true
_G.__visceral_holsters_on = ON
-- 2026-10-30 (Tefa: "the feature that i wanted, so that weapon is in hand only with the right grip held and when right grip is
-- released, the weapon also goes back to inventory. this is not working out and i wanted that idea scrapped"): off. The right
-- grip at a spot takes that slot's gun out, or puts it away if it is in hand; letting go of the grip does nothing.
local HOLD_TO_KEEP = false    -- true = the right grip must stay closed to keep a gun in the hand; letting go puts it away
-- Tefa 2026-10-25, before the first try: "we don't want the Aim state of shooting, we want the hip shooting throughout the
-- game with no aim button needed ... delete the binding for aim but not the code or the function from the game". So the
-- game's aim stays as it is and no button presses it: the grip no longer turns into LT (the only press of it in play; the
-- scope harness presses it only during a scope test). false = the grip presses the aim again, as praydog's mod did.
local AIM_OFF = true          -- re8_vr.lua reads __visceral_aim_off
local TAKE_ARRIVE_S = 2.0     -- how long a gun just asked for may take to arrive in the hand
_G.__visceral_aim_off = AIM_OFF

-- spot offsets from the headset (m): side (+ right), up (+ up), forward (+ forward); Visceral RE2's numbers
local SPOTS = {
    { name = "right shoulder", slot = "Up",    side =  0.28, up = -0.22, fwd = -0.08 },
    { name = "right hip",      slot = "Right", side =  0.20, up = -0.62, fwd =  0.02 },
    { name = "left hip",       slot = "Down",  side = -0.20, up = -0.62, fwd =  0.02 },
    { name = "left shoulder",  slot = "Left",  side = -0.28, up = -0.22, fwd = -0.08 },
}
-- 2026-11-02 (Tefa: "the holster spot seemed to move a little every time ... or maybe the activation area is just too small"):
-- bigger, 0.15 / 0.22 before
local ENTER_M, LEAVE_M = 0.20, 0.28          -- in a spot under ENTER, out again past LEAVE (no flicker at the edge)
local BUZZ_ENTER = { sec = 0.05, amp = 0.35 } -- a tick on entering a spot
local BUZZ_GRAB = { sec = 0.08, amp = 0.70 }  -- a stronger one on grabbing there
local BUZZ_HZ = 1.0
local BUZZ_ON = true
-- 2026-10-31 (Tefa: "i dont want the constant vibration that lets me know i'm at the activation zone ... what i do want is
-- holster spots to give a nice short buzz when i actually use them"): no tick on entering a spot, the grab buzz stays
local BUZZ_ON_ENTER = false

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

local statics = require("utility/Statics")
local SLOT = safe(function() return statics.generate("app.InventoryManager.QuickEquipSlotNo") end)
if type(SLOT) ~= "table" or SLOT.Up == nil then
    SLOT = {}
    pcall(function()
        local td = sdk.find_type_definition("app.QuickSlotName")
        for _, n in ipairs({ "Up", "Down", "Left", "Right" }) do SLOT[n] = td:get_field(n):get_data(nil) end
    end)
end

local function pos_of(m) local c = m[3]; return Vector3f.new(c.x, c.y, c.z) end
local function dist(a, b) local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z; return math.sqrt(dx * dx + dy * dy + dz * dz) end

-- headset position + offset turned by the headset's yaw only (OpenXR room space: +X right, +Y up, -Z forward)
-- 2026-11-02 (Tefa: "do you know if holster spots are tied to the player body or always fixed with HMD?" ... "the holster
-- spot seemed to move a little every time"): they turned with the HEAD, so glancing aside while reaching moved them. Village's
-- drawn body faces wherever the head looks (the RE2-style body turn was dropped in the 2026-10-31 rebuild), so there is no
-- separate body to follow. Instead the spots keep their OWN facing, the way RE2's body turns: it stays put while the head
-- looks less than SPOT_DEADZONE_DEG away, and once past that it comes round to the head at SPOT_CATCH_DEG_S until it is
-- within SPOT_SETTLE_DEG (the simulator check: a 25 degree head turn must leave the right hip spot where it was).
local SPOT_DEADZONE_DEG, SPOT_CATCH_DEG_S, SPOT_SETTLE_DEG = 45.0, 120.0, 5.0
local facing = { yaw = nil, t = -1, catching = false, logged = -10 }
local function wrap(a) while a > math.pi do a = a - 2 * math.pi end; while a < -math.pi do a = a + 2 * math.pi end; return a end
local function spot_facing(head_yaw)   -- updated once a frame; every spot_pos call in that frame gets the same answer
    local now = os.clock()
    if facing.yaw == nil then facing.yaw, facing.t = head_yaw, now; return facing.yaw end
    if now - facing.t < 0.002 then return facing.yaw end
    local dt = math.min(0.1, now - facing.t)
    facing.t = now
    local diff = wrap(head_yaw - facing.yaw)
    if math.abs(diff) > math.rad(SPOT_DEADZONE_DEG) then facing.catching = true end
    if facing.catching then
        local step = math.rad(SPOT_CATCH_DEG_S) * dt
        if math.abs(diff) <= math.max(step, math.rad(SPOT_SETTLE_DEG)) then facing.catching = false
        else facing.yaw = wrap(facing.yaw + (diff > 0 and step or -step)) end
    end
    if now - facing.logged > 10 then
        facing.logged = now
        log.info(string.format("%s spots face %.0f deg from where the head looks%s", TAG, math.deg(wrap(facing.yaw - head_yaw)), facing.catching and " (coming round)" or ""))
    end
    return facing.yaw
end

local function spot_pos(hmd, s)
    local p = pos_of(hmd)
    local z = hmd[2]
    local fx, fz = -z.x, -z.z
    local len = math.sqrt(fx * fx + fz * fz)
    if len < 1e-4 then fx, fz = 0.0, -1.0 else fx, fz = fx / len, fz / len end
    local y = spot_facing(math.atan(fx, fz))   -- the spots' own facing, not the head's (above)
    fx, fz = math.sin(y), math.cos(y)
    local rx, rz = -fz, fx
    return Vector3f.new(p.x + rx * s.side + fx * s.fwd, p.y + s.up, p.z + rz * s.side + fz * s.fwd)
end

local function weapon_change()
    local v = rawget(_G, "re8vr")
    local p = v and v.player
    if p == nil then return nil end
    for _, t in ipairs({ "app.PlayerUpdaterFPS", "app.PlayerUpdater", "app.PlayerUpdaterPl2001" }) do
        local rt = safe(function() return sdk.typeof(t) end)
        local up = rt and safe(function() return p:call("getComponent(System.Type)", rt) end)
        local c = up and safe(function() return up:call("get_playerWeaponChange") end)
        if c then return c end
    end
    return nil
end

local function slot_item(name)
    local v = rawget(_G, "re8vr")
    local inv = v and v.inventory
    local slot = SLOT[name]
    if inv == nil or slot == nil then return nil end
    return safe(function() return inv:call("getItemFromQuickSlot", slot, false) end)
        or safe(function() return inv:call("getItemFromQuickSlot", slot, true) end)
end

local function item_id(item)
    local w = item and safe(function() return item:call("get_work") end)
    return w and safe(function() return w:call("get_itemID") end) or nil
end

local function held_id()
    local v = rawget(_G, "re8vr")
    local w = v and v.weapon
    -- the weapon in hand: its own item id, else by its game object name (riNNNN -> the RE Engine hash is not needed:
    -- compare the item objects instead)
    return w and (item_id(w) or safe(function() return w:get_address() end)) or nil
end

-- [hypothesis] putting the gun away: ask the weapon change for "no item"; logged so the first try says whether it works
local function put_away(wc)
    local ok = pcall(function() wc:call("set_RequestedItem", nil) end)
    return ok
end

local function buzz(joy, b)
    if not BUZZ_ON then return end
    pcall(function() vrmod:trigger_haptic_vibration(0.0, b.sec, BUZZ_HZ, b.amp, joy) end)
end

-- The right grip holds the gun (Tefa 2026-10-25: "RG needed to actually hold the gun in hand, that means disabling the AIM
-- function all together"): letting go puts the gun away, with Andyalpa's proven stow (re8_vr_holster.lua exports it as
-- __re8_holster_stow_to_bare); the old guess (set_RequestedItem nil) is only the fall-back. The knife is left alone.
-- Let go before a gun just asked for has arrived: it is put away when it arrives, within TAKE_ARRIVE_S.
local function stow()
    local f = rawget(_G, "__re8_holster_stow_to_bare")
    if type(f) == "function" then
        local ok, r = pcall(f, nil)
        return ok and r == true, "Andyalpa's stow"
    end
    local wc = weapon_change()
    return wc ~= nil and put_away(wc), "set_RequestedItem(nil), Andyalpa's stow not found"
end

local function held_is_knife()
    local v = rawget(_G, "re8vr")
    local w = v and v.weapon
    if w == nil then return false end
    local r = rawget(_G, "__re8_resolve_equipped_item_id")
    local id = type(r) == "function" and safe(function() return r(w) end) or nil
    return type(id) == "string" and id:find("Knife", 1, true) ~= nil
end

local inside = {}
local grip_was = false
local logged_slots = false
local take_until = 0.0        -- a gun was just asked for (TAKE OUT) and may not be in the hand yet
local stow_when_here = false  -- the grip let go before it arrived

-- 2026-11-01 (Tefa: "holding it with LG on the fron part then holding LT makes it possible to press RG and the right hand goes on
-- the bolt to rack it"): an RG pressed while the left hand holds the gun (LG, docked) with LT held is the bolt
-- (rack_right.cpp), never a holster grab or Andyalpa's inventory gesture, until RG is let go again
local rack_rg = false
local function rack_combo(v)
    local lj = vrmod:get_left_joystick()
    return v ~= nil and v.was_gripping_weapon == true and vrmod:is_action_active(vrmod:get_action_grip(), lj) == true
        and vrmod:is_action_active(vrmod:get_action_trigger(), lj) == true
end
_G.__visceral_right_rack = function() return rack_rg end

-- 2026-11-09 (b104, Tefa: Hand Poser must "read all the grip zones we have in the game for all the guns and holster zones for both
-- left and right hand"): which holster spot each hand is inside, for Hand Poser only (bridge slots 214 left, 215 right; 0 none,
-- 1 right shoulder, 2 right hip, 3 left hip, 4 left shoulder = the SPOTS order). The left hand's spots take nothing out: report only
local S_LEFT_HOLSTER, S_RIGHT_HOLSTER = 214, 215
-- 2026-11-09 evening (Tefa: holster spots should show up for a hand only "if there is something that an LG press does in that
-- spot"; "yeas please on the holsters"): a hand registers at a holster spot only where its grip does something there. The right
-- grip takes a gun out at all four; LG does nothing at any of them today, so the left hand registers at none. When LG gets a job
-- at a spot, set that spot true here
local LEFT_GRIP_DOES = { ["right shoulder"] = false, ["right hip"] = false, ["left hip"] = false, ["left shoulder"] = false }
local inside_l = {}
local told = { -1, -1 }
local function publish(l, r)
    local b = rawget(_G, "visceral_re8_bridge")
    if b == nil or not b.ready() then return end
    pcall(function() b.w(S_LEFT_HOLSTER, l); b.w(S_RIGHT_HOLSTER, r) end)
    if l ~= told[1] or r ~= told[2] then
        told[1], told[2] = l, r
        local nm = function(i) return i > 0 and SPOTS[i].name or "none" end
        L(string.format("holster spot for Hand Poser: left hand %s, right hand %s", nm(l), nm(r)))
    end
end
local function which_spot(hand, hmd, ins)   -- the same enter / leave distances as the right hand's grabs
    local found = 0
    for i, s in ipairs(SPOTS) do
        local d = dist(hand, spot_pos(hmd, s))
        if not ins[s.name] and d < ENTER_M then ins[s.name] = true
        elseif ins[s.name] and d > LEAVE_M then ins[s.name] = false end
        if ins[s.name] and found == 0 and LEFT_GRIP_DOES[s.name] == true then found = i end   -- (only the left hand uses this)
    end
    return found
end

re.on_pre_application_entry("UpdateBehavior", function()
    _G.__visceral_holster_zone = false
    if not ON or not vrmod:is_hmd_active() then publish(0, 0) return end
    local v = rawget(_G, "re8vr")
    if v == nil or v.player == nil or v.is_in_cutscene == true then publish(0, 0) return end
    local ctrls = safe(function() return vrmod:get_controllers() end)
    local hmd = safe(function() return vrmod:get_transform(0) end)
    local rm = ctrls and ctrls[2] and safe(function() return vrmod:get_transform(ctrls[2]) end)
    if hmd == nil or rm == nil then publish(0, 0) return end
    do
        local lm = ctrls[1] and safe(function() return vrmod:get_transform(ctrls[1]) end)
        local lspot = lm ~= nil and which_spot(pos_of(lm), hmd, inside_l) or 0
        local rspot = 0
        for i, s in ipairs(SPOTS) do if inside[s.name] and rspot == 0 then rspot = i end end   -- last frame's (updated below)
        publish(lspot, rspot)
    end
    local hand = pos_of(rm)
    local rj = vrmod:get_right_joystick()
    local grip = vrmod:is_action_active(vrmod:get_action_grip(), rj) == true
    local pressed = grip and not grip_was
    local released = grip_was and not grip
    grip_was = grip
    if pressed and rack_combo(v) then rack_rg = true; L("RG with LG + LT on the gun: the bolt, not a holster") end
    -- 2026-11-01 (Tefa's Wolfsbane plan): the right hand takes rounds from the left-hip pouch while the left hand holds the gun
    if pressed and rawget(_G, "re8_gate_hold") ~= nil and _G.re8_gate_hold() then rack_rg = true; L("RG while the Wolfsbane is held by the left hand: rounds, not a holster") end
    if not grip then rack_rg = false end
    if HOLD_TO_KEEP then
        local now = os.clock()
        if grip then stow_when_here = false end
        if released then
            if v.weapon ~= nil and not held_is_knife() then
                local ok, how = stow()
                L(string.format("grip let go: gun PUT AWAY (%s) -> %s", how, ok and "done" or "FAILED"))
            elseif now < take_until then
                stow_when_here = true
            end
        end
        if stow_when_here then
            if v.weapon ~= nil and not held_is_knife() then
                stow_when_here = false
                local ok, how = stow()
                L(string.format("grip let go before the gun arrived: PUT AWAY on arrival (%s) -> %s", how, ok and "done" or "FAILED"))
            elseif now >= take_until then
                stow_when_here = false
            end
        end
    end
    if not logged_slots then
        logged_slots = true
        L(string.format("spots on: quick slots Up %s, Right %s, Down %s, Left %s", tostring(SLOT.Up), tostring(SLOT.Right),
            tostring(SLOT.Down), tostring(SLOT.Left)))
    end
    if os.clock() - (facing.spot_logged or -10) > 10 then   -- 2026-11-02: proof the spots stay put when only the head turns
        facing.spot_logged = os.clock()
        local rp = spot_pos(hmd, SPOTS[2])
        log.info(string.format("%s right hip spot at %.2f %.2f %.2f (room)", TAG, rp.x, rp.y, rp.z))
    end
    for _, s in ipairs(SPOTS) do
        local d = dist(hand, spot_pos(hmd, s))
        if not inside[s.name] and d < ENTER_M then inside[s.name] = true; if BUZZ_ON_ENTER then buzz(rj, BUZZ_ENTER) end
        elseif inside[s.name] and d > LEAVE_M then inside[s.name] = false end
        if inside[s.name] then
            _G.__visceral_holster_zone = true
            if pressed and not rack_rg then
                local item = slot_item(s.slot)
                local wc = weapon_change()
                if item == nil then
                    L(string.format("grab at %s: quick slot %s is empty", s.name, s.slot))
                elseif wc == nil then
                    L(string.format("grab at %s: no weapon change found", s.name))
                else
                    buzz(rj, BUZZ_GRAB)
                    local id = item_id(item)
                    -- 2026-10-31: "already in the hand" told by the WEAPON object (the id compare missed: a held gun was taken out
                    -- again and came out invisible); put away with Andyalpa's proven stow
                    local iw = rawget(_G, "__re8_holster_item_weapon")
                    local wpn = type(iw) == "function" and safe(function() return iw(item) end) or nil
                    local held = (wpn ~= nil and v.weapon ~= nil and safe(function() return wpn:get_address() == v.weapon:get_address() end) == true)
                        or (id ~= nil and id == held_id())
                    if held then
                        local ok, how = stow()
                        L(string.format("grab at %s: PUT AWAY item %s (%s) -> %s", s.name, tostring(id), how, ok and "done" or "FAILED"))
                    else
                        -- Andyalpa's proven native equip (the D-pad path), exported by re8_vr_holster.lua; the old
                        -- set_RequestedItem only as the fall-back (it never brought a gun out, 2026-10-31)
                        local eq = rawget(_G, "__re8_holster_equip_item")
                        local ok, how = false, "set_RequestedItem"
                        if type(eq) == "function" then
                            local pok, r = pcall(eq, item, "visceral " .. s.name)
                            ok, how = pok and r == true, "Andyalpa's native equip"
                        end
                        if not ok and how == "set_RequestedItem" then ok = pcall(function() wc:call("set_RequestedItem", item) end) end
                        if ok then take_until = os.clock() + TAKE_ARRIVE_S end
                        L(string.format("grab at %s: TAKE OUT item %s (quick slot %s) by %s -> %s", s.name, tostring(id), s.slot, how, ok and "done" or "FAILED"))
                    end
                end
            end
        end
    end
end)

L("loaded: " .. (ON and "four spots (right shoulder = up, right hip = right, left hip = down, left shoulder = left)" or "off"))
