-- Pins remain-ammo HUD to the right-hand world pose (manual mode + keep_open).
--
--   - Manual RH world matrix attach + ViewType World with REF-style child recenter
--   - Keep open while armed; soft-hide on melee/bare (pre_gui suppress)
--   - Full driver reset recover after inventory / show_edge / HMD resume
--   - Holster publishes Hand / __re8_bare_hands for bare-hands hide

if reframework:get_game_name() ~= "re8" then
    return {}
end

local statics = nil
pcall(function() statics = require("utility/Statics") end)

local CFG_PATH = "re8_vr/re8_vr_ammo_hud.json"
local LOG_TAG = "[re8_vr_ammo_hud]"

local ETHAN_REMAIN_AMMO_HASH = 1927694450

local CFG = {
    display = "weapon",
    mode = "manual",
    keep_open = true,
    force_open_interval_s = 2.0,
    set_world_view = true,
    off_right = 0.04,
    off_up = -0.02,
    off_forward = 0.08,
    rot_yaw = 0.0,
    rot_pitch = 0.0,
    rot_roll = 0.0,
    scale = 0.55,
    poll_s = 0.35,
}

local function display_mode()
    local d = tostring(CFG.display or "weapon")
    if d == "default" or d == "weapon" or d == "off" then return d end
    return "weapon"
end

local function effective_display()
    return display_mode()
end

local function is_weapon_mode()
    return effective_display() == "weapon"
end

local STATE = {
    status = "init",
    gui_mgr = nil,
    wig = nil,
    go = nil,
    xform = nil,
    gui_comp = nil,
    go_name = "GUIRemainAmmo",
    is_open = false,
    load_text = "",
    stack_text = "",
    rh_index = nil,
    hand_src = "",
    last_poll_t = 0,
    last_open_t = 0,
    last_draw_t = 0,
    last_pos = nil,
    apply_count = 0,
    draw_count = 0,
    last_err = "",
    menu_blocking = false,
    menu_was_blocking = false,
    recover_t = 0,
    active_weapon_id = "",
    weapon_id_src = "",
    hide_reason = "",
    show_ammo = false,
    was_show_ammo = false,
    lost_show_t = 0,
    last_recover_t = 0,
    recover_reason = "",
    pause_gui_time = 0,
    last_ammo_id = "",
    last_ammo_t = 0,
    recover_draw_count = 0,
    pre_menu_ammo_id = "",
    pre_menu_show = false,
    hmd_was = nil,
}

local function log_info(msg)
    if log and log.info then
        pcall(function() log.info(LOG_TAG .. " " .. tostring(msg)) end)
    end
end

local function managed_alive(obj)
    if obj == nil then return false end
    local ok, alive = pcall(function()
        if obj.get_address then
            return obj:get_address() ~= 0
        end
        return true
    end)
    return ok and alive == true
end

local function obj_addr(obj)
    if not managed_alive(obj) then return 0 end
    local a = 0
    pcall(function()
        if obj.get_address then a = obj:get_address() or 0 end
    end)
    return tonumber(a) or 0
end

local PAUSE_GUI_EXACT = {
    GUIPause = true,
    GUIInventoryMenu = true,
    GUISaveLoad = true,
    GUIInventory = true,
    GUIInventoryTreasure = true,
    GUIInventoryCraft = true,
    GUIInventoryKeyItem = true,
    GUIMainMenu = true,
    GUIDialog = true,
}

local function is_blocking_menu()
    local fn = rawget(_G, "__vr_is_interaction_blocked")
    if type(fn) == "function" then
        local ok, v = pcall(fn)
        if ok and v == true then
            return true
        end
    end
    local now = os.clock()
    if (now - (STATE.pause_gui_time or 0)) < 0.50 then
        return true
    end
    return false
end

local function safe_call(obj, method, ...)
    if not managed_alive(obj) then return nil end
    local ok, res = pcall(function(...)
        return obj:call(method, ...)
    end, ...)
    if ok then return res end
    return nil
end

local function read_str(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local s = nil
    pcall(function()
        if v.to_string then
            s = v:to_string()
        elseif v.call then
            s = v:call("ToString")
        end
    end)
    if type(s) == "string" then return s end
    return tostring(v)
end

local function load_cfg()
    local data = nil
    pcall(function() data = json.load_file(CFG_PATH) end)
    if type(data) ~= "table" then
        pcall(function() json.dump_file(CFG_PATH, CFG) end)
        return
    end
    for k, v in pairs(data) do
        if CFG[k] ~= nil and type(v) == type(CFG[k]) then
            CFG[k] = v
        end
    end
    CFG.mode = "manual"
    if type(data.display) ~= "string" then
        if data.enabled == false then
            CFG.display = "default"
        elseif data.attach == false then
            CFG.display = "default"
        else
            CFG.display = "weapon"
        end
    elseif data.display ~= "default" and data.display ~= "weapon" and data.display ~= "off" then
        CFG.display = "weapon"
    end
    pcall(function() json.dump_file(CFG_PATH, CFG) end)
end

local function save_cfg()
    pcall(function() json.dump_file(CFG_PATH, CFG) end)
end

load_cfg()

local function matrix_col(m, idx)
    if not m then return nil end
    local c = nil
    pcall(function() c = m[idx] end)
    if c and type(c.x) == "number" then return c end
    return nil
end

local function vec3_normalize(v)
    if not v or type(v.x) ~= "number" then return nil end
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len < 1e-8 then return nil end
    return { x = v.x / len, y = v.y / len, z = v.z / len }
end

local function quat_from_ypr(yaw_deg, pitch_deg, roll_deg)
    local q = nil
    pcall(function()
        q = Quaternion.new(Vector3f.new(
            math.rad(tonumber(pitch_deg) or 0.0),
            math.rad(tonumber(yaw_deg) or 0.0),
            math.rad(tonumber(roll_deg) or 0.0)
        )):normalized()
    end)
    if q then return q end
    local hy = math.rad(tonumber(yaw_deg) or 0.0) * 0.5
    local hp = math.rad(tonumber(pitch_deg) or 0.0) * 0.5
    local hr = math.rad(tonumber(roll_deg) or 0.0) * 0.5
    local qz = Quaternion.new(math.cos(hy), 0, 0, math.sin(hy))
    local qy = Quaternion.new(math.cos(hp), 0, math.sin(hp), 0)
    local qx = Quaternion.new(math.cos(hr), math.sin(hr), 0, 0)
    return (qz * qy * qx):normalized()
end

local function write_vec4(obj, vec, offset)
    if not obj or not vec then return end
    pcall(function()
        obj:write_float(offset, vec.x or 0)
        obj:write_float(offset + 4, vec.y or 0)
        obj:write_float(offset + 8, vec.z or 0)
        obj:write_float(offset + 12, vec.w or 0)
    end)
end

local function clear_hud_children()
    STATE.go = nil
    STATE.xform = nil
    STATE.gui_comp = nil
end

local function clear_refs()
    STATE.wig = nil
    clear_hud_children()
end

local function get_component(go, type_name)
    if not managed_alive(go) then return nil end
    local comp = nil
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then return end
        local rt = td:get_runtime_type()
        if not rt then return end
        comp = go:call("getComponent(System.Type)", rt)
    end)
    if managed_alive(comp) then return comp end
    return nil
end

local function driver_type_name(drv)
    local n = ""
    pcall(function()
        local td = drv:get_type_definition()
        if td then n = tostring(td:get_full_name() or "") end
    end)
    return n
end

local function is_remain_ammo_driver(drv)
    if not managed_alive(drv) then return false end
    local n = driver_type_name(drv)
    if n == "app.GUIRemainAmmo" then return true end
    if n == "app.GUIPl4000RemainAmmo" then return true end
    return false
end

local function weapon_go_from_obj(weapon)
    if not managed_alive(weapon) then return nil end
    local go = nil
    pcall(function() go = weapon:get_field("<owner>k__BackingField") end)
    if not managed_alive(go) then
        pcall(function() go = weapon:call("get_owner") end)
    end
    if not managed_alive(go) then
        pcall(function() go = weapon:call("get_GameObject") end)
    end
    if managed_alive(go) then return go end
    return nil
end

local function get_re8vr()
    return rawget(_G, "re8vr")
end

local function re8vr_ok(re8vr)
    return re8vr ~= nil
end

local function weapon_id_from_core(weapon, src)
    if not managed_alive(weapon) then
        return nil, nil
    end
    local melee = false
    pcall(function()
        local td = weapon:get_type_definition()
        if td and (td:is_a("app.WeaponMeleeCore") or td:is_a("app.WeaponThrowableCore")) then
            melee = true
        end
    end)
    if melee then
        return "melee_type", "type"
    end
    local n = nil
    pcall(function()
        local go = weapon_go_from_obj(weapon)
        if go then n = go:call("get_Name") end
    end)
    if type(n) == "string" and n ~= "" then
        return n, src or "weapon"
    end
    return "armed", src or "weapon"
end

local function resolve_player_go(re8vr)
    if not re8vr_ok(re8vr) then return nil end
    local player = nil
    pcall(function()
        if re8vr.get_localplayer then
            player = re8vr:get_localplayer()
        end
    end)
    if not managed_alive(player) then
        pcall(function() player = re8vr.player end)
    end
    if managed_alive(player) then return player end
    return nil
end

local function resolve_weapon_core(re8vr)
    if not re8vr_ok(re8vr) then
        return nil, "no_re8vr"
    end
    if managed_alive(re8vr.weapon) then
        return re8vr.weapon, "re8vr"
    end
    local player = resolve_player_go(re8vr)
    local w = nil
    if managed_alive(player) then
        pcall(function()
            if re8vr.get_weapon_object then
                w = re8vr:get_weapon_object(player)
            end
        end)
        if managed_alive(w) then
            return w, "get_weapon_object"
        end
    end
    local gun = nil
    pcall(function()
        if managed_alive(re8vr.order) then
            gun = re8vr.order:call("get_playerGun")
        end
    end)
    if not managed_alive(gun) and managed_alive(player) then
        gun = get_component(player, "app.PlayerGun")
        if not managed_alive(gun) then
            gun = get_component(player, "app.PlayerGunPl2001")
        end
    end
    if managed_alive(gun) then
        pcall(function() w = gun:call("get_equipWeaponObject") end)
        if managed_alive(w) then
            return w, "player_gun"
        end
        pcall(function() w = gun:call("get_weaponGun") end)
        if managed_alive(w) then
            return w, "weapon_gun"
        end
    end
    local ec = nil
    if managed_alive(player) then
        ec = get_component(player, "app.EquipController")
    end
    if not managed_alive(ec) and managed_alive(gun) then
        pcall(function() ec = gun:call("get_equipController") end)
    end
    if managed_alive(ec) then
        local none = false
        pcall(function() none = ec:call("get_isNoneEquiped") == true end)
        if none then
            return nil, "ec_none"
        end
        local melee = false
        pcall(function()
            melee = ec:call("isMeleeEquip") == true
                or ec:call("isThrowableEquip") == true
        end)
        if melee then
            return nil, "ec_melee"
        end
        pcall(function() w = ec:call("currentPlayerWeapon") end)
        if not managed_alive(w) then
            pcall(function() w = ec:call("get_equipWeaponRight") end)
        end
        if managed_alive(w) then
            return w, "equip_ctrl"
        end
        local is_gun = false
        pcall(function() is_gun = ec:call("isGunEquip") == true end)
        if is_gun then
            return nil, "ec_gun_flag"
        end
        return nil, "ec_empty"
    end
    return nil, "none"
end

local function resolve_active_weapon_id()
    if rawget(_G, "__re8_bare_hands") == true then
        return "Hand", "bare_flag"
    end
    local pub = rawget(_G, "__re8_active_weapon_id")
    if type(pub) == "string" and pub ~= "" then
        return pub, "pub"
    end
    local re8vr = get_re8vr()
    local weapon, path = resolve_weapon_core(re8vr)
    if path == "ec_none" then
        return "Hand", "bare"
    end
    if path == "ec_melee" then
        return "melee_type", "type"
    end
    if path == "ec_gun_flag" then
        return "armed", "ec_gun"
    end
    if managed_alive(weapon) then
        return weapon_id_from_core(weapon, path)
    end
    return "", "none"
end

local function is_explicit_melee_id(id)
    if id == nil or id == "" then return false end
    local s = tostring(id)
    if s == "melee_type" then return true end
    if s == "Hand" or s:find("BareHand", 1, true) then return true end
    if s == "ri3022_Inventory" or s == "ri3044_Inventory" then return true end
    return false
end

local function classify_weapon_for_ammo()
    if not is_weapon_mode() then
        STATE.active_weapon_id = ""
        STATE.weapon_id_src = ""
        STATE.hide_reason = "mode"
        return "melee"
    end
    local id, src = resolve_active_weapon_id()
    STATE.active_weapon_id = id or ""
    STATE.weapon_id_src = src or ""
    if src == "bare" or src == "hand" or src == "bare_flag" then
        STATE.hide_reason = "bare"
        return "melee"
    end
    if src == "type" or is_explicit_melee_id(id) then
        STATE.hide_reason = "melee"
        return "melee"
    end
    if id == nil or id == "" then
        STATE.hide_reason = "unknown"
        return "unknown"
    end
    STATE.hide_reason = ""
    return "ammo"
end

local function should_show_ammo_hud()
    local kind = classify_weapon_for_ammo()
    if kind == "ammo" then
        STATE.show_ammo = true
        return true
    end
    if kind == "melee" then
        STATE.show_ammo = false
        return false
    end
    return STATE.show_ammo == true
end

local function read_gui_text_obj(txt)
    if not managed_alive(txt) then return "" end
    local msg = safe_call(txt, "get_Message")
        or safe_call(txt, "get_Text")
        or safe_call(txt, "get_OutputText")
    return read_str(msg)
end

local function resolve_gui_comp_from_driver(drv)
    local ctrl = safe_call(drv, "get_selfGUIController")
    if not managed_alive(ctrl) then return nil end
    local gui = safe_call(ctrl, "get_Component")
    if managed_alive(gui) then return gui end
    return nil
end

local function find_remain_ammo_driver_from_handles(gui_mgr)
    local handles = safe_call(gui_mgr, "get_guiHandles")
    if not managed_alive(handles) then return nil end
    local items = nil
    pcall(function() items = handles:get_field("mItems") end)
    local size = 0
    pcall(function() size = tonumber(handles:get_field("mSize")) or 0 end)
    if items == nil or size <= 0 then
        pcall(function() size = tonumber(handles:call("get_Count")) or 0 end)
    end
    local i = 0
    while i < size do
        local h = nil
        if items ~= nil then
            pcall(function() h = items[i] end)
        end
        if not managed_alive(h) then
            pcall(function() h = handles:call("get_Item", i) end)
        end
        if managed_alive(h) then
            local drv = safe_call(h, "get_driver")
            if is_remain_ammo_driver(drv) then
                return drv
            end
        end
        i = i + 1
    end
    return nil
end

local function resolve_weapon_info(force_refresh)
    if not managed_alive(STATE.gui_mgr) then
        STATE.gui_mgr = sdk.get_managed_singleton("app.GUIManager")
    end
    if not managed_alive(STATE.gui_mgr) then
        STATE.status = "no_gui_manager"
        return false
    end

    local fresh = nil
    if force_refresh or not managed_alive(STATE.wig) then
        fresh = find_remain_ammo_driver_from_handles(STATE.gui_mgr)
        if not managed_alive(fresh) then
            local handle = nil
            pcall(function()
                handle = STATE.gui_mgr:call("findGUI", ETHAN_REMAIN_AMMO_HASH)
            end)
            if managed_alive(handle) then
                fresh = safe_call(handle, "get_driver")
            end
        end
        if not is_remain_ammo_driver(fresh) then
            STATE.status = "no_remain_ammo"
            clear_refs()
            return false
        end
        if force_refresh or obj_addr(STATE.wig) ~= obj_addr(fresh) then
            STATE.wig = fresh
            clear_hud_children()
        end
    end

    if not managed_alive(STATE.go) then
        STATE.go = safe_call(STATE.wig, "get_GameObject")
    end
    if managed_alive(STATE.go) then
        local n = ""
        pcall(function() n = tostring(STATE.go:call("get_Name") or "") end)
        if n ~= "" then
            STATE.go_name = n
        end
        if not managed_alive(STATE.xform) then
            STATE.xform = safe_call(STATE.go, "get_Transform")
        end
    end
    if managed_alive(STATE.wig) and not managed_alive(STATE.gui_comp) then
        STATE.gui_comp = resolve_gui_comp_from_driver(STATE.wig)
    end

    local drawn = safe_call(STATE.wig, "get_isDrawSelf") == true
    if not drawn and managed_alive(STATE.go) then
        drawn = safe_call(STATE.go, "get_Draw") == true
    end
    local suspended = safe_call(STATE.wig, "get_drawSuspend") == true
    local timer = tonumber(safe_call(STATE.wig, "get_displayTimer") or 0) or 0
    STATE.is_open = (not suspended) or drawn or (timer > 0.05)

    STATE.load_text = read_gui_text_obj(safe_call(STATE.wig, "get_stackCountText"))
    STATE.stack_text = read_gui_text_obj(safe_call(STATE.wig, "get_stackAllCountText"))

    if managed_alive(STATE.wig) and managed_alive(STATE.xform) then
        STATE.status = "ready"
        return true
    end
    STATE.status = "partial"
    return managed_alive(STATE.wig)
end

local function is_ammo_go_name(name)
    local n = tostring(name or "")
    if n == "" then return false end
    if STATE.go_name and n == STATE.go_name then return true end
    if n == "GUIRemainAmmo" then return true end
    if n == "GUIPl4000RemainAmmo" then return true end
    return false
end

local function fix_screen_children_for_world(view)
    if not managed_alive(view) then return 0 end
    local hw, hh = 0.0, 0.0
    pcall(function()
        local sz = view:call("get_ScreenSize")
        if sz ~= nil then
            local w = sz.w
            local h = sz.h
            if type(w) ~= "number" then pcall(function() w = sz:get_field("w") end) end
            if type(h) ~= "number" then pcall(function() h = sz:get_field("h") end) end
            hw = (tonumber(w) or 0) * 0.5
            hh = (tonumber(h) or 0) * 0.5
        end
    end)
    local child = safe_call(view, "get_Child")
    local n = 0
    while managed_alive(child) and n < 64 do
        n = n + 1
        pcall(function()
            child:call("set_Position", Vector3f.new(hw, hh, 0.0))
        end)
        local nxt = nil
        pcall(function() nxt = child:call("get_Next") end)
        child = nxt
    end
    return n
end

local function ensure_world_view(gui_comp)
    if not CFG.set_world_view then return end
    if not managed_alive(gui_comp) then return end
    local view = safe_call(gui_comp, "get_View")
    if not managed_alive(view) then return end
    pcall(function() view:call("set_ViewType", 1) end)
    pcall(function() view:call("set_Overlay", true) end)
    pcall(function() view:call("set_Detonemap", true) end)
    pcall(function() view:call("set_DepthTest", true) end)
    fix_screen_children_for_world(view)
end

local function refresh_open_state()
    if not managed_alive(STATE.wig) then
        STATE.is_open = false
        return false
    end
    local suspended = safe_call(STATE.wig, "get_drawSuspend") == true
    local timer = tonumber(safe_call(STATE.wig, "get_displayTimer") or 0) or 0
    local drawn = safe_call(STATE.wig, "get_isDrawSelf") == true
    if not drawn and managed_alive(STATE.go) then
        drawn = safe_call(STATE.go, "get_Draw") == true
    end
    STATE.is_open = (not suspended) or drawn or (timer > 0.05)
    return STATE.is_open
end

local function keep_ammo_drawn()
    if not managed_alive(STATE.wig) then return end
    pcall(function() STATE.wig:call("setViewDrawState", true) end)
    pcall(function() STATE.wig:call("set_drawSuspend", false) end)
    pcall(function() STATE.wig:call("set_updateSuspend", false) end)
    pcall(function() STATE.wig:call("set_displayTimer", 30.0) end)
    pcall(function() STATE.wig:set_field("<drawSuspend>k__BackingField", false) end)
    pcall(function() STATE.wig:set_field("<updateSuspend>k__BackingField", false) end)
    pcall(function() STATE.wig:set_field("<displayTimer>k__BackingField", 30.0) end)
    pcall(function()
        if managed_alive(STATE.gui_comp) then
            STATE.gui_comp:call("set_Enabled", true)
        end
    end)
    pcall(function()
        if managed_alive(STATE.go) then
            STATE.go:call("set_DrawSelf", true)
            STATE.go:call("set_UpdateSelf", true)
            STATE.go:call("set_Draw", true)
            STATE.go:call("set_Update", true)
        end
    end)
    pcall(function()
        if managed_alive(STATE.wig) then
            STATE.wig:call("applyToUI")
        end
    end)
    refresh_open_state()
end

local function force_open_ammo_hud(hard, bypass_weapon)
    if not is_weapon_mode() then
        return
    end
    if not bypass_weapon and not should_show_ammo_hud() then
        return
    end
    if not CFG.keep_open then return end
    if is_blocking_menu() then
        return
    end
    if not managed_alive(STATE.gui_mgr) then return end
    if not managed_alive(STATE.wig) then
        resolve_weapon_info(true)
    end
    if not managed_alive(STATE.wig) then
        return
    end

    -- Always clear suspend/timer first; Village get_isDrawSelf stays false even when shown.
    keep_ammo_drawn()

    local now = os.clock()
    if (not hard) and (now - (STATE.last_open_t or 0)) < (tonumber(CFG.force_open_interval_s) or 2.0) then
        return
    end
    STATE.last_open_t = now

    local order = safe_call(STATE.wig, "get_order")
    if not managed_alive(order) then
        pcall(function() order = STATE.wig:get_field("guiOrder") end)
    end
    if managed_alive(order) then
        pcall(function() order:call("cancelHide") end)
        pcall(function() order:call("show", true) end)
        local mode = safe_call(STATE.wig, "get_mode")
        local item_id = safe_call(STATE.wig, "get_itemID")
        if mode ~= nil and item_id ~= nil then
            pcall(function() order:call("showRemainAmmo", mode, item_id) end)
        end
    end

    if not managed_alive(STATE.gui_comp) then
        STATE.gui_comp = resolve_gui_comp_from_driver(STATE.wig)
    end
    ensure_world_view(STATE.gui_comp)
    keep_ammo_drawn()
end

local function force_hide_ammo_hud(destructive)
    if not managed_alive(STATE.wig) then
        resolve_weapon_info(false)
    end
    if not managed_alive(STATE.wig) then return end
    if destructive then
        pcall(function() STATE.wig:call("setViewDrawState", false) end)
        pcall(function() STATE.wig:call("set_displayTimer", 0.0) end)
        STATE.is_open = false
    end
end

local function recover_after_menu(reason)
    clear_refs()
    if not managed_alive(STATE.gui_mgr) then
        pcall(function() STATE.gui_mgr = sdk.get_managed_singleton("app.GUIManager") end)
    end
    resolve_weapon_info(true)
    if managed_alive(STATE.wig) then
        pcall(function() STATE.wig:call("reset") end)
        resolve_weapon_info(true)
    end
    STATE.last_open_t = 0
    STATE.last_recover_t = os.clock()
    STATE.recover_t = 0

    local r = tostring(reason or "")
    local must_open = (r == "menu_close" or r == "show_edge" or r == "draw_watchdog"
        or r == "no_resolve" or r == "pause_close" or r == "hmd_edge")
    local kind_now = classify_weapon_for_ammo()
    local armed = (kind_now == "ammo")
        or (kind_now == "unknown" and (STATE.pre_menu_ammo_id or "") ~= "" and r == "menu_close")
        or (kind_now == "unknown" and (STATE.last_ammo_id or "") ~= "" and (os.clock() - (STATE.last_ammo_t or 0)) < 0.40)
    if must_open and armed then
        if (STATE.last_ammo_id or "") == "" and (STATE.pre_menu_ammo_id or "") ~= "" then
            STATE.last_ammo_id = STATE.pre_menu_ammo_id
            STATE.last_ammo_t = os.clock()
        end
        STATE.show_ammo = true
        STATE.was_show_ammo = true
        STATE.hide_reason = "recover_force"
        force_open_ammo_hud(true, true)
        pcall(function()
            if managed_alive(STATE.gui_comp) then
                ensure_world_view(STATE.gui_comp)
            end
        end)
    elseif must_open and not armed then
        STATE.show_ammo = false
        STATE.hide_reason = "recover_skip_melee"
    elseif should_show_ammo_hud() then
        force_open_ammo_hud(true)
        pcall(function()
            if managed_alive(STATE.gui_comp) then
                ensure_world_view(STATE.gui_comp)
            end
        end)
    else
        force_hide_ammo_hud(false)
    end

    log_info("recovered remain ammo HUD (" .. tostring(reason or "menu") .. ")")
end

local function schedule_recover(delay_s, reason, force)
    local now = os.clock()
    local when = now + (tonumber(delay_s) or 0.05)
    if not force and (now - (STATE.last_recover_t or 0)) < 1.25 then
        return
    end
    if STATE.recover_t and STATE.recover_t > 0 and STATE.recover_t <= when then
        STATE.recover_reason = tostring(reason or STATE.recover_reason or "watchdog")
        return
    end
    STATE.recover_t = when
    STATE.recover_reason = tostring(reason or "watchdog")
    STATE.recover_draw_count = STATE.draw_count or 0
end

local function rh_ctrl_idx()
    local controllers = nil
    pcall(function()
        if vrmod then controllers = vrmod:get_controllers() end
    end)
    local idx = controllers and controllers[2]
    if idx == nil then idx = 2 end
    STATE.rh_index = idx
    return idx
end

local function right_hand_world_pose()
    local re8vr = get_re8vr()
    local pos, rot, src = nil, nil, "none"

    if re8vr and re8vr.right_hand_ik_transform then
        pcall(function() pos = re8vr.right_hand_ik_transform:call("get_Position") end)
        pcall(function() rot = re8vr.right_hand_ik_transform:call("get_Rotation") end)
        if pos and type(pos.x) == "number" then src = "ik_transform" end
    end

    if (not pos) and re8vr and re8vr.last_right_hand_position
        and type(re8vr.last_right_hand_position.x) == "number" then
        pos = re8vr.last_right_hand_position
        src = "re8vr_last"
        if re8vr.last_right_hand_rotation then
            rot = re8vr.last_right_hand_rotation
        end
    end

    if not pos then
        local w = rawget(_G, "__vr_rh_world")
        if w and type(w.x) == "number" then
            pos = w
            src = "global_world"
        end
    end

    if (not pos or not rot) and vrmod then
        local idx = rh_ctrl_idx()
        local cam = nil
        local wm = nil
        pcall(function() cam = sdk.get_primary_camera() end)
        pcall(function()
            if cam then
                local cgo = cam:call("get_GameObject")
                local xf = cgo and cgo:call("get_Transform")
                if xf then wm = xf:call("get_WorldMatrix") end
            end
        end)

        local ctrl = nil
        local hmd = nil
        local ctrl_rot = nil
        pcall(function() ctrl = vrmod:get_position(idx) end)
        pcall(function() hmd = vrmod:get_position(0) end)
        pcall(function() ctrl_rot = vrmod:get_rotation(idx) end)

        if not pos and wm and ctrl and hmd and type(ctrl.x) == "number" then
            local dx, dy, dz = ctrl.x - hmd.x, ctrl.y - hmd.y, ctrl.z - hmd.z
            local r = vec3_normalize(matrix_col(wm, 0))
            local u = vec3_normalize(matrix_col(wm, 1))
            local f = vec3_normalize(matrix_col(wm, 2))
            local c = matrix_col(wm, 3)
            if r and u and f and c then
                pos = {
                    x = c.x + dx * r.x + dy * u.x + dz * f.x,
                    y = c.y + dx * r.y + dy * u.y + dz * f.y,
                    z = c.z + dx * r.z + dy * u.z + dz * f.z,
                }
                src = "cam_project"
            end
        end

        if not rot and ctrl_rot then
            local cam_rot = nil
            pcall(function()
                if cam then
                    local cgo = cam:call("get_GameObject")
                    local xf = cgo and cgo:call("get_Transform")
                    if xf then cam_rot = xf:call("get_Rotation") end
                end
            end)
            if cam_rot then
                local ok, q = pcall(function() return cam_rot * ctrl_rot end)
                if ok and q then
                    rot = q
                else
                    rot = ctrl_rot
                end
            else
                rot = ctrl_rot
            end
            if src == "none" then src = "vrmod_rot" end
        end
    end

    STATE.hand_src = src
    if not pos or type(pos.x) ~= "number" then
        return nil, nil, src
    end
    return pos, rot, src
end

local function apply_xform(xform, pos, rot)
    if not managed_alive(xform) or not pos then return false end
    local s = tonumber(CFG.scale) or 0.55

    if rot then
        local mat = nil
        pcall(function() mat = rot:to_mat4() end)
        if mat then
            local sx = s
            write_vec4(xform, {
                x = (mat[0] and mat[0].x or 1) * sx,
                y = (mat[0] and mat[0].y or 0) * sx,
                z = (mat[0] and mat[0].z or 0) * sx,
                w = 0,
            }, 0x80)
            write_vec4(xform, {
                x = (mat[1] and mat[1].x or 0) * sx,
                y = (mat[1] and mat[1].y or 1) * sx,
                z = (mat[1] and mat[1].z or 0) * sx,
                w = 0,
            }, 0x90)
            write_vec4(xform, {
                x = (mat[2] and mat[2].x or 0) * sx,
                y = (mat[2] and mat[2].y or 0) * sx,
                z = (mat[2] and mat[2].z or 1) * sx,
                w = 0,
            }, 0xA0)
            write_vec4(xform, {
                x = pos.x, y = pos.y, z = pos.z, w = 1,
            }, 0xB0)
            return true
        end
    end
    write_vec4(xform, { x = pos.x, y = pos.y, z = pos.z, w = 1 }, 0xB0)
    return true
end

local function compute_attach_pose()
    local pos, rot, src = right_hand_world_pose()
    if not pos then
        STATE.last_err = "no_right_hand (" .. tostring(src) .. ")"
        return nil
    end

    if not rot then
        pcall(function()
            rot = Quaternion.new(0, 0, 0, 1)
        end)
    end
    if not rot then
        STATE.last_err = "no_right_rot (" .. tostring(src) .. ")"
        return nil
    end

    local ox = tonumber(CFG.off_right) or 0.0
    local oy = tonumber(CFG.off_up) or 0.0
    local oz = tonumber(CFG.off_forward) or 0.0
    local world_off = nil
    pcall(function()
        world_off = rot * Vector3f.new(ox, oy, oz)
    end)
    if not world_off then
        world_off = { x = ox, y = oy, z = oz }
    end

    local final_pos = {
        x = pos.x + (world_off.x or 0),
        y = pos.y + (world_off.y or 0),
        z = pos.z + (world_off.z or 0),
    }

    local extra = quat_from_ypr(CFG.rot_yaw, CFG.rot_pitch, CFG.rot_roll)
    local final_rot = rot
    if extra then
        local ok, q = pcall(function() return rot * extra end)
        if ok and q then final_rot = q end
    end

    return final_pos, final_rot, src
end

local function apply_manual_attach()
    local pos, rot, src = compute_attach_pose()
    if not pos then
        return false
    end

    ensure_world_view(STATE.gui_comp)

    if not apply_xform(STATE.xform, pos, rot) then
        STATE.last_err = "xform_write_failed"
        return false
    end

    STATE.last_pos = pos
    STATE.apply_count = (STATE.apply_count or 0) + 1
    STATE.last_err = ""
    STATE.hand_src = src or STATE.hand_src
    return true
end

local function tick_attach()
    if not is_weapon_mode() then return end
    apply_manual_attach()
end

re.on_frame(function()
    if rawget(_G, "__vr_reloaded_master_enabled") == false then
        return
    end
    local now = os.clock()

    local hmd = false
    pcall(function()
        local vm = rawget(_G, "vrmod")
        if vm and vm.is_hmd_active then hmd = vm:is_hmd_active() == true end
    end)
    local disp = effective_display()
    if hmd and STATE.hmd_was == false and disp == "weapon" then
        schedule_recover(0.25, "hmd_edge", true)
    end
    STATE.hmd_was = hmd

    local blocking = is_blocking_menu()
    STATE.menu_blocking = blocking

    local kind = "melee"
    if disp == "weapon" then
        kind = classify_weapon_for_ammo()
    else
        STATE.hide_reason = "mode"
    end

    local show_ammo = false
    if blocking then
        if kind == "ammo" then
            STATE.lost_show_t = 0
            STATE.last_ammo_id = tostring(STATE.active_weapon_id or "")
            STATE.last_ammo_t = now
        end
        if (STATE.last_ammo_id or "") == "" and (STATE.pre_menu_ammo_id or "") ~= "" then
            STATE.last_ammo_id = STATE.pre_menu_ammo_id
            STATE.last_ammo_t = now
        end
        show_ammo = (STATE.last_ammo_id or "") ~= ""
            or STATE.pre_menu_show == true
            or STATE.was_show_ammo == true
        STATE.hide_reason = "menu_freeze"
    elseif kind == "ammo" then
        STATE.lost_show_t = 0
        STATE.last_ammo_id = tostring(STATE.active_weapon_id or "")
        STATE.last_ammo_t = now
        show_ammo = true
    elseif kind == "unknown" then
        if STATE.last_ammo_id ~= "" and (now - (STATE.last_ammo_t or 0)) < 0.40 then
            show_ammo = true
            STATE.hide_reason = "unknown_grace"
        else
            show_ammo = false
            STATE.hide_reason = "unknown_hide"
        end
    else
        STATE.last_ammo_id = ""
        if STATE.was_show_ammo then
            if (STATE.lost_show_t or 0) == 0 then
                STATE.lost_show_t = now
            end
            if (now - STATE.lost_show_t) < 0.12 then
                show_ammo = true
            end
        end
    end

    if show_ammo and not STATE.was_show_ammo and disp == "weapon" and not blocking then
        schedule_recover(0.10, "show_edge", true)
    end
    STATE.was_show_ammo = show_ammo
    STATE.show_ammo = show_ammo

    if blocking and not STATE.menu_was_blocking then
        STATE.menu_was_blocking = true
        STATE.last_err = "menu_open_yield"
        STATE.pre_menu_ammo_id = (STATE.last_ammo_id ~= "" and STATE.last_ammo_id)
            or tostring(STATE.active_weapon_id or "")
        STATE.pre_menu_show = show_ammo == true
            or (STATE.last_ammo_id or "") ~= ""
            or kind == "ammo"
    elseif (not blocking) and STATE.menu_was_blocking then
        STATE.menu_was_blocking = false
        if disp == "weapon" then
            schedule_recover(0.35, "menu_close", true)
        end
    end

    if STATE.recover_t and STATE.recover_t > 0 and now >= STATE.recover_t then
        local reason = tostring(STATE.recover_reason or "timer")
        local draw_age = now - (STATE.last_draw_t or 0)
        local drew_since = (STATE.draw_count or 0) - (STATE.recover_draw_count or 0)
        STATE.recover_t = 0
        STATE.recover_reason = ""
        local must = (reason == "menu_close" or reason == "show_edge" or reason == "no_resolve" or reason == "pause_close" or reason == "hmd_edge")
        local watchdog_needs = (reason == "draw_watchdog") and (drew_since < 5 or draw_age > 0.85)
        if disp == "weapon" and not is_blocking_menu() and (must or (show_ammo and watchdog_needs)) then
            recover_after_menu(reason)
        end
    end

    if STATE.recover_t and STATE.recover_t > 0 and now < STATE.recover_t then
        STATE.status = "recover_pending"
        return
    end

    if (now - (STATE.last_poll_t or 0)) >= (tonumber(CFG.poll_s) or 0.35) then
        STATE.last_poll_t = now
        if not resolve_weapon_info(false) then
            STATE.status = (disp == "default") and "default" or STATE.status
            if disp == "weapon" and show_ammo and not blocking
                and (now - (STATE.last_draw_t or 0)) > 1.25 then
                schedule_recover(0.05, "no_resolve")
            end
            -- Keep trying open/attach next frames; do not hard-return forever.
        end
    end

    if not managed_alive(STATE.wig) and disp == "weapon" and show_ammo then
        resolve_weapon_info(true)
    end
    if not managed_alive(STATE.wig) and disp ~= "default" then
        return
    end

    if blocking then
        STATE.status = "menu_yield"
        return
    end

    if disp == "off" then
        STATE.status = "off"
        force_hide_ammo_hud(true)
    elseif disp == "weapon" then
        if not show_ammo then
            STATE.status = "melee_hide"
            force_hide_ammo_hud(false)
        else
            keep_ammo_drawn()
            local draw_age = now - (STATE.last_draw_t or 0)
            if draw_age > 1.25 then
                schedule_recover(0.05, "draw_watchdog")
            elseif draw_age > 1.0 then
                force_open_ammo_hud(true)
            else
                force_open_ammo_hud(false)
            end
            tick_attach()
            if STATE.status ~= "ready" and STATE.status ~= "partial" then
                STATE.status = "weapon"
            end
        end
    else
        STATE.status = "default"
    end
end)

re.on_pre_gui_draw_element(function(element, context)
    local go = nil
    pcall(function() go = element:call("get_GameObject") end)
    if not managed_alive(go) then return true end

    local name = ""
    pcall(function() name = read_str(go:call("get_Name")) end)

    if PAUSE_GUI_EXACT[name] then
        STATE.pause_gui_time = os.clock()
    end

    if not is_ammo_go_name(name) then return true end

    local disp = effective_display()
    if disp == "off" then
        return false
    end
    if disp ~= "weapon" then
        return true
    end
    if STATE.show_ammo ~= true then
        return false
    end
    if STATE.menu_blocking or is_blocking_menu() then
        return false
    end
    if STATE.recover_t and STATE.recover_t > 0 then
        return false
    end

    if not managed_alive(STATE.go) or STATE.go ~= go then
        STATE.go = go
        STATE.go_name = name
        STATE.xform = safe_call(go, "get_Transform")
        if managed_alive(STATE.wig) then
            STATE.gui_comp = resolve_gui_comp_from_driver(STATE.wig)
        end
        if not managed_alive(STATE.gui_comp) then
            STATE.gui_comp = get_component(go, "via.gui.GUI")
        end
    end

    ensure_world_view(STATE.gui_comp)

    local pos, rot = compute_attach_pose()
    if pos then
        local xf = STATE.xform or safe_call(go, "get_Transform")
        if apply_xform(xf, pos, rot) then
            STATE.draw_count = (STATE.draw_count or 0) + 1
            STATE.last_draw_t = os.clock()
            STATE.last_pos = pos
            STATE.last_err = ""
        end
    end
    return true
end)

local function apply_rh_near_preset()
    CFG.off_right = 0.02
    CFG.off_up = 0.04
    CFG.off_forward = 0.06
    CFG.rot_yaw = 0.0
    CFG.rot_pitch = 0.0
    CFG.rot_roll = 0.0
    CFG.scale = 0.55
    CFG.display = "weapon"
    CFG.keep_open = true
    CFG.set_world_view = true
    save_cfg()
    STATE.last_open_t = 0
    STATE.is_open = false
    pcall(function()
        force_open_ammo_hud(true, true)
    end)
end

re.on_draw_ui(function()
    if not imgui.tree_node("Ammo HUD") then return end
    local ok, err = pcall(function()
        local disp = display_mode()
        local ui_labels = { "Default", "On Weapon", "Off" }
        local cur_idx = 1
        if disp == "weapon" then cur_idx = 2
        elseif disp == "off" then cur_idx = 3 end
        local c_disp, new_idx = imgui.combo("Ammo HUD Display##ammo_hud_disp", cur_idx, ui_labels)
        if c_disp and type(new_idx) == "number" then
            local map = { "default", "weapon", "off" }
            local next_v = map[new_idx] or map[new_idx + 1]
            if next_v then
                CFG.display = next_v
                save_cfg()
                disp = next_v
            end
        end
        imgui.text("default = game | weapon = RH attach | off = hidden")

        imgui.text("Status: " .. tostring(STATE.status) .. "  (" .. tostring(disp) .. ")")
        if STATE.menu_blocking then
            imgui.text("Yielding while inventory/pause is open")
        end
        imgui.text(string.format(
            "Open=%s  Apply=%d  Draw=%d",
            tostring(STATE.is_open),
            STATE.apply_count or 0,
            STATE.draw_count or 0
        ))
        imgui.text("Hand src: " .. tostring(STATE.hand_src or ""))
        imgui.text("Weapon: " .. tostring(STATE.active_weapon_id or "")
            .. "  (" .. tostring(STATE.weapon_id_src or "") .. ")")
        imgui.text("Load: " .. tostring(STATE.load_text or "")
            .. "  Stack: " .. tostring(STATE.stack_text or ""))
        if STATE.last_err ~= "" then
            imgui.text("Err: " .. tostring(STATE.last_err))
        end
        if STATE.last_pos then
            imgui.text(string.format("Pos: %.3f %.3f %.3f",
                STATE.last_pos.x or 0, STATE.last_pos.y or 0, STATE.last_pos.z or 0))
        end

        if disp == "weapon" then
            imgui.spacing()
            if imgui.button("Snap near right hand##ammo_hud_snap") then
                apply_rh_near_preset()
            end
            imgui.text("Snap = small offsets, scale 0.55, rot 0 (visible start)")

            imgui.spacing()
            local kh, kv = imgui.checkbox("Keep HUD open##ammo_hud_keep", CFG.keep_open == true)
            if kh then CFG.keep_open = kv; save_cfg() end

            local wh, wv = imgui.checkbox("Force World ViewType##ammo_hud_world", CFG.set_world_view == true)
            if wh then CFG.set_world_view = wv; save_cfg() end

            imgui.spacing()
            local rc, rv = imgui.slider_float("Offset Right (m)##ammo_hud_or", tonumber(CFG.off_right) or 0.0, -2.00, 2.00, "%.3f")
            if rc then CFG.off_right = rv; save_cfg() end
            local uc, uv = imgui.slider_float("Offset Up (m)##ammo_hud_ou", tonumber(CFG.off_up) or 0.0, -2.00, 2.00, "%.3f")
            if uc then CFG.off_up = uv; save_cfg() end
            local fc, fv = imgui.slider_float("Offset Forward (m)##ammo_hud_of", tonumber(CFG.off_forward) or 0.0, -2.00, 2.00, "%.3f")
            if fc then CFG.off_forward = fv; save_cfg() end

            local yc, yv = imgui.slider_float("Rot Yaw (deg)##ammo_hud_yaw", tonumber(CFG.rot_yaw) or 0.0, -360.0, 360.0, "%.1f")
            if yc then CFG.rot_yaw = yv; save_cfg() end
            local pc, pv = imgui.slider_float("Rot Pitch (deg)##ammo_hud_pitch", tonumber(CFG.rot_pitch) or 0.0, -360.0, 360.0, "%.1f")
            if pc then CFG.rot_pitch = pv; save_cfg() end
            local oc, ov = imgui.slider_float("Rot Roll (deg)##ammo_hud_roll", tonumber(CFG.rot_roll) or 0.0, -360.0, 360.0, "%.1f")
            if oc then CFG.rot_roll = ov; save_cfg() end

            local sc, sv = imgui.slider_float("Scale##ammo_hud_scale", tonumber(CFG.scale) or 0.55, 0.001, 5.00, "%.3f")
            if sc then CFG.scale = sv; save_cfg() end
            imgui.text("Tip: start near Snap preset; huge Scale can fling UI off-screen")

            imgui.spacing()
            if imgui.button("Open HUD now##ammo_hud_open") then
                STATE.last_open_t = 0
                STATE.is_open = false
                force_open_ammo_hud(true, true)
            end
            imgui.same_line()
            if imgui.button("Recover after menu##ammo_hud_rec") then
                recover_after_menu("ui")
            end
            imgui.same_line()
            if imgui.button("Reset offsets##ammo_hud_reset") then
                apply_rh_near_preset()
            end
        end

        imgui.spacing()
        if imgui.button("Re-resolve##ammo_hud_res") then
            clear_refs()
            resolve_weapon_info(true)
        end
    end)
    imgui.tree_pop()
    if not ok then
        log_info("UI error: " .. tostring(err))
    end
end)

re.on_config_save(function()
    save_cfg()
end)

if type(rawget(_G, "__re8_vr_overlay_bind")) ~= "table" then
    rawset(_G, "__re8_vr_overlay_bind", {})
end
rawget(_G, "__re8_vr_overlay_bind").ammo_hud = {
    push = function(api)
        api.set_string("ammo_hud.display", display_mode(), false)
    end,
    pull = function(api)
        local d = api.get_string("ammo_hud.display", display_mode())
        if d == "default" or d == "weapon" or d == "off" then
            CFG.display = d
        end
        save_cfg()
    end,
}

log_info("loaded — ammo HUD RH attach (manual + keep_open)")

return {
    cfg = CFG,
    state = STATE,
    resolve = resolve_weapon_info,
}
