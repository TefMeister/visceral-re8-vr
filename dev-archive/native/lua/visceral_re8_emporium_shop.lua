-- visceral_re8_emporium_shop.lua -- the Visceral options ON THE DUKE'S OWN SHOP SCREEN, seen in the headset (2026-11-04).
--
-- Tefa (2026-10-30): "can you design it using the game's own Duke's shop interface, that the player can actually see in
-- VR? and has all our settings on it and looks like this, spaceous and everything". The imgui window
-- (visceral_re8_emporium.lua) draws on the monitor only; this one borrows the game's own screens, which the headset shows.
--
-- How (all found live 2026-11-04, modding-notes/2026-11-04-the-dukes-shop-by-name.md; dossier section 6):
--   * a GUI screen is made by app.GUIManager.createGUI(hash(name), true), hash = the RE Engine name hash (murmur3_32 of
--     the UTF-16LE name, seed 0xFFFFFFFF). "Shop" first (ShopMenu only answers after it), then "ShopBg" (the wall, a 3D
--     mesh: drawSuspend off + onShow(true) shows it) and "ShopMenu" (the three cards: the driver's show(Parameter) with a
--     fresh Parameter shows it; the call throws AFTER doing its work).
--   * our words go on with via.gui.Text.set_Message: header m_header / m_header_desc, per card (si_list0..2, in both
--     l_list and l_list_add) m_name0 = title, m_name1 = motto.
--   * Left / Right move the game's own selection (simpleListSelectionChanged; the list's get_SelectedIndex says which);
--     F / A on a card calls app.GUIShopMenu.openMenu, which we SKIP (it would open the Buy screen with no shop data
--     behind it, which crashed the game) and use as "pick".
--   * Esc / Start opens the game's pause menu even over the shop; while we are open we skip that show and use it as "Back".
--   * app.GUIManager.suicideGUIShop() takes the cards off cleanly.
--
-- THE SCREENS
--   tabs:  "The Visceral Emporium" over Comfort / Graphics / Settings (the mottos as on the imgui window).
--   page:  the tab's name over three cards; each card is one setting: its name on top, its value below. Pick changes it
--          (a tick box flips, a choice steps on, a slider steps up and wraps, a button runs). More than three settings:
--          two per page and a third card "More..." that turns the page.
--   Back:  page -> tabs -> closed.
-- OPENING: X + A held 0.5 s in the headset (as before); flat: the REFramework menu's button, or
-- reframework/data/visceral_re8/emporium_cmd.json, {"cmd": "open"} (for driving it with nobody at the PC). The settings come from
-- _G.VISCERAL_OPTIONS, which every Visceral script fills (see visceral_re8_emporium.lua's header for the shape).
-- [verified-live 2026-11-04 for each call above, flat]; this script as a whole: [hypothesis] until seen in the game.

local TAG = "[visceral-emporium]"
local CMD_FILE = "visceral_re8/emporium_cmd.json"   -- { "cmd": "open" | "close" | "back" | "pick <0-2>" }
local HOLD_S = 0.5                 -- X + A held this long opens or closes it
local CMD_EVERY_FRAMES = 30        -- how often the command file is read
local RENDER_AGAIN_FRAMES = 3      -- our words are put back this many frames after the game re-lays the cards
local SLIDER_STEPS = 10            -- a slider's range is walked in this many steps by "pick"
local PER_PAGE_WITH_MORE = 2       -- with more than three settings: two settings and a "More..." card per page

local TITLE = "VR Options Emporium"   -- Tefa 2026-11-04: "the Visceral emporium needs to be called VR Options Emporium"
local MOTTO = "No one's a stranger to the Emporium"
local TABS = {
    { tab = "comfort", name = "Comfort", motto = "Easy on the stomach!" },
    { tab = "graphics", name = "Graphics", motto = "A feast for the eyes!" },
    { tab = "settings", name = "Settings", motto = "Everything in its place!" },
}
local MORE_TITLE = "More..."
local EMPTY_TEXT = "Nothing here yet"

local function L(s) log.info(TAG .. " " .. tostring(s)) end
local function safe(f, ...) local ok, v = pcall(f, ...); if ok then return v end; return nil end
local function type_name(obj)
    local td = safe(function() return obj:get_type_definition() end)
    return td and td:get_full_name() or "?"
end

-- the RE Engine name hash (the same one item and sound ids use; tested against 39 known names 2026-10-24)
local function name_hash(s)
    local M = 0xFFFFFFFF
    local function rotl(x, r) return ((x << r) | (x >> (32 - r))) & M end
    local function mul(a, b) return (a * b) & M end
    local h = 0xFFFFFFFF
    local bytes = {}
    for i = 1, #s do bytes[#bytes + 1] = s:byte(i); bytes[#bytes + 1] = 0 end
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

_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}

-- ===== state =====
local ui = { open = false, level = "tabs", tab = 1, page = 1, cards = {}, menu = nil, bg = nil, render_in = 0,
             want_back = false, want_pick = nil }

local function entries_for(tab)
    local out = {}
    for _, e in ipairs(_G.VISCERAL_OPTIONS) do
        if type(e) == "table" and e.tab == tab then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return out
end

local function value_text(e)
    local okg, cur = pcall(e.get or function() return nil end)
    if not okg then cur = nil end
    if e.kind == "check" then return cur == true and "On" or "Off" end
    if e.kind == "slider" then return string.format(e.fmt or "%.2f", tonumber(cur) or e.min or 0) end
    if e.kind == "choice" then return tostring((e.choices or {})[tonumber(cur) or 1] or "?") end
    if e.kind == "button" then return "Pick to use" end
    return ""
end

-- what each of the three cards is right now: { title, motto, entry or "tab" or "more" or nil }
local function layout()
    local cards = {}
    if ui.level == "tabs" then
        for i, t in ipairs(TABS) do cards[i] = { title = t.name, motto = t.motto, what = "tab", index = i } end
        return cards, TITLE, MOTTO
    end
    local t = TABS[ui.tab]
    local list = entries_for(t.tab)
    local pages, per = 1, 3
    if #list > 3 then per = PER_PAGE_WITH_MORE; pages = math.ceil(#list / per) end
    if ui.page > pages then ui.page = 1 end
    local first = (ui.page - 1) * per
    for i = 1, per do
        local e = list[first + i]
        if e then cards[#cards + 1] = { title = e.label or "?", motto = value_text(e), what = e } end
    end
    if pages > 1 then
        cards[#cards + 1] = { title = MORE_TITLE, motto = string.format("Page %d of %d", ui.page, pages), what = "more" }
    end
    if #list == 0 then cards[1] = { title = EMPTY_TEXT, motto = "", what = nil } end
    while #cards < 3 do cards[#cards + 1] = { title = "", motto = "", what = nil } end
    return cards, t.name, t.motto
end

-- ===== the game's screens =====
local function gm() return sdk.get_managed_singleton("app.GUIManager") end
local function driver_of(handle) return handle and safe(function() return handle:get_field("<driver>k__BackingField") end) end

local function view_of(handle)
    local d = driver_of(handle)
    local go = d and safe(function() return d:call("get_GameObject") end)
    local gui = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI")) end)
    return gui and safe(function() return gui:call("get_View") end)
end

-- set every Text called `cname` under the control named `under` (nil = anywhere) to `text`
local function set_texts(view, under, cname, text)
    local n = 0
    local function visit(ctrl, depth, inside)
        if ctrl == nil or depth > 14 then return end
        local name = safe(function() return ctrl:call("get_Name") end)
        local here = inside or under == nil or name == under
        if here and name == cname and type_name(ctrl):find("Text") then
            if pcall(function() ctrl:call("set_Message", text) end) then n = n + 1 end
        end
        local child = safe(function() return ctrl:call("get_Child") end)
        while child ~= nil do
            visit(child, depth + 1, here)
            child = safe(function() return child:call("get_Next") end)
        end
    end
    visit(view, 0, under == nil)
    return n
end

local function render()
    local view = view_of(ui.menu)
    if view == nil then return end
    local cards, head, desc = layout()
    ui.cards = cards
    set_texts(view, "header", "m_header", head)
    set_texts(view, "header", "m_header_desc", desc)
    for i = 1, 3 do
        local c = cards[i]
        set_texts(view, "si_list" .. (i - 1), "m_name0", c.title)
        set_texts(view, "si_list" .. (i - 1), "m_name1", c.motto)
    end
end

-- which card is lit: the SelectItem whose own "cursor" panel is visible (the shop's tree, dumped 2026-11-04: only the
-- lit card's cursor shows). The list's selection getter and openMenu's mode argument both read card 0 every time.
local function lit_card()
    local view = view_of(ui.menu)
    if view == nil then return nil end
    local found = nil
    local function visit(ctrl, depth, in_list, item)
        if ctrl == nil or depth > 10 or found ~= nil then return end
        local name = safe(function() return ctrl:call("get_Name") end) or ""
        local here_list = in_list or name == "l_list"
        local here_item = item
        if here_list and name:match("^si_list%d$") then here_item = tonumber(name:sub(8)) end
        if here_item ~= nil and name == "cursor" and safe(function() return ctrl:call("get_Visible") end) == true then
            found = here_item
            return
        end
        if name == "l_list_add" then return end
        local child = safe(function() return ctrl:call("get_Child") end)
        while child ~= nil and found == nil do
            visit(child, depth + 1, here_list, here_item)
            child = safe(function() return child:call("get_Next") end)
        end
    end
    visit(view, 0, false, nil)
    return found
end

local function selected_index()
    local lit = lit_card()
    if lit ~= nil then return lit end
    local d = driver_of(ui.menu)
    local list = d and safe(function() return d:get_field("<simpleList>k__BackingField") end)
    local i = list and (safe(function() return list:call("get_SelectedIndex") end) or safe(function() return list:call("get_selectedIndex") end))
    if i == nil then i = d and safe(function() return d:get_field("<lastIndex>k__BackingField") end) end
    return tonumber(i) or 0
end

local function open()
    if ui.open then return end
    local m = gm()
    if m == nil then L("no app.GUIManager yet"); return end
    local function create(name)
        local ok, h = pcall(function() return m:call("createGUI(System.UInt32, System.Boolean)", name_hash(name), true) end)
        return ok and h or nil
    end
    create("Shop")                                      -- ShopMenu answers only once a Shop exists
    ui.bg = create("ShopBg")
    local bgd = driver_of(ui.bg)
    if bgd then
        pcall(function() bgd:call("set_drawSuspend", false) end)
        pcall(function() bgd:call("onShow", true) end)
    end
    ui.menu = create("ShopMenu")
    local md = driver_of(ui.menu)
    if md == nil then L("could not make the shop's card screen"); return end
    local param = sdk.create_instance("app.GUIRequest.Parameter")
    if param then param = param:add_ref() end
    pcall(function() md:call("show(app.GUIRequest.Parameter)", param) end)   -- throws after showing; known
    -- every card is the first card's kind to the game (ShopIds = the mode each card opens): a pick on the third card
    -- (the game's Sell) left the menu taking no more keys, a pick on the first never did (2026-11-04 18:40-18:50);
    -- which card it really was we read ourselves (lit_card)
    local ids = safe(function() return md:get_field("ShopIds") end)
    local n = ids and safe(function() return ids:call("get_Count") end) or 0
    local first = n > 0 and safe(function() return ids:call("get_Item", 0) end) or nil
    if first ~= nil then
        for i = 1, n - 1 do pcall(function() ids:call("set_Item", i, first) end) end
    end
    L("cards' modes: " .. tostring(n) .. " made the first kind")
    pcall(function() m:call("enterExclusive(app.IGUIDriver)", md) end)
    ui.open, ui.level, ui.tab, ui.page = true, "tabs", 1, 1
    render()
    ui.render_in = RENDER_AGAIN_FRAMES
    L("opened")
end

local function exclusive_state(m)
    return tostring(safe(function() return m:call("isExclusiveMode") end))
end

local function close()
    if not ui.open then return end
    ui.open = false
    local m = gm()
    local md = driver_of(ui.menu)
    local before = m and exclusive_state(m) or "?"
    -- hand the controls back first: suicideGUIShop alone left the game in exclusive mode (no walking, no pause, 18:50)
    if m and md then pcall(function() m:call("leaveExclusive(app.IGUIDriver)", md) end) end
    if m then pcall(function() m:call("suicideGUIShop") end) end
    L("exclusive mode before " .. before .. ", after " .. (m and exclusive_state(m) or "?"))
    local bgd = driver_of(ui.bg)
    if bgd then
        pcall(function() bgd:call("set_drawSuspend", true) end)
        pcall(function() bgd:call("onHide", true) end)
    end
    ui.menu, ui.bg = nil, nil
    L("closed")
end

local function pick(idx)
    local c = ui.cards[idx + 1]
    if c == nil or c.what == nil then return end
    if c.what == "tab" then
        ui.level, ui.tab, ui.page = "page", c.index, 1
    elseif c.what == "more" then
        ui.page = ui.page + 1
    else
        local e = c.what
        local okg, cur = pcall(e.get or function() return nil end)
        if not okg then cur = nil end
        if e.kind == "check" and e.set then
            pcall(e.set, not (cur == true))
        elseif e.kind == "choice" and e.set then
            local n = #(e.choices or {})
            if n > 0 then pcall(e.set, ((tonumber(cur) or 1) % n) + 1) end
        elseif e.kind == "slider" and e.set then
            local lo, hi = e.min or 0.0, e.max or 1.0
            local step = (hi - lo) / SLIDER_STEPS
            local v = (tonumber(cur) or lo) + step
            if v > hi + step * 0.5 then v = lo end
            pcall(e.set, math.min(hi, v))
        elseif e.kind == "button" and e.press then
            pcall(e.press)
        end
        L("changed: " .. tostring(e.label) .. " -> " .. value_text(e))
    end
    render()
    ui.render_in = RENDER_AGAIN_FRAMES
end

local function back()
    if ui.level == "page" then
        ui.level = "tabs"
        render()
        ui.render_in = RENDER_AGAIN_FRAMES
    else
        close()
    end
end

-- ===== hooks: pick (openMenu) and back (the pause menu) =====
do
    local menu_td = sdk.find_type_definition("app.GUIShopMenu")
    local open_menu = menu_td and menu_td:get_method("openMenu")
    if open_menu then
        -- openMenu(app.GUIShopMode.Value mode, Boolean, OperationResultBase): the mode is the card the game was about to
        -- open (Buy = Supplies, Customize = Gunsmithy, Sell = The Duke's Purse); the card's place comes from it, not from
        -- the list's selection (which read 0 with the third card lit, 2026-11-04 18:36). The post returns false ("nothing
        -- opened"): left as whatever the skipped call held, the menu waited for a child screen and took no more keys.
        local skipping = false
        sdk.hook(open_menu, function(args)
            if not ui.open then return end
            -- the mode is an object (app.GUIShopMode.Value): compare its address with the game's own static Buy /
            -- Customize / Sell objects (2026-11-04: the raw argument read as a pointer, 2097698081168)
            local idx = selected_index()
            local addr = safe(function() return sdk.to_int64(args[3]) end)
            local mode_td = sdk.find_type_definition("app.GUIShopMode")
            local which = "?"
            for card, fname in ipairs({ "Buy", "Customize", "Sell" }) do
                local f = mode_td and mode_td:get_field(fname)
                local v = f and safe(function() return f:get_data(nil) end)
                local va = v and (safe(function() return v:get_address() end) or safe(function() return sdk.to_int64(v) end))
                if va ~= nil and addr ~= nil and va == addr then which = fname end   -- logged only: always Buy here
            end
            L(string.format("pick: mode %s (%s), list says %s -> card %d", tostring(addr), which, tostring(selected_index()), idx))
            ui.want_pick = idx
            skipping = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, function(retval)
            if skipping then skipping = false; return sdk.to_ptr(0) end
            return retval
        end)
    end
    local relay = menu_td and menu_td:get_method("setupSimpleList")
    if relay then   -- the game re-lays the cards on every move: put our words back a few frames later
        sdk.hook(relay, nil, function(retval)
            if ui.open then ui.render_in = RENDER_AGAIN_FRAMES end
            return retval
        end)
    end
    local drv_td = sdk.find_type_definition("app.GUIDriver")
    for _, m in ipairs(drv_td and drv_td:get_methods() or {}) do
        if m:get_name() == "show" then
            sdk.hook(m, function(args)
                if not ui.open then return end
                local this = safe(function() return sdk.to_managed_object(args[2]) end)
                local tn = this and type_name(this) or ""
                if tn == "app.GUIPauseMenu" or tn == "app.GUIEventPauseMenu" then
                    return sdk.PreHookResult.SKIP_ORIGINAL      -- no pause over us; Back itself is read in watch_back
                end
            end, function(retval) return retval end)
        end
    end
end

-- ===== the X + A hold (headset) =====
local hold_since, hold_done = nil, false
local function buttons_held()
    if not vrmod or not vrmod.is_hmd_active or not vrmod:is_hmd_active() then return false end
    local ok, held = pcall(function()
        local a = vrmod:get_action_a_button()
        return vrmod:is_action_active(a, vrmod:get_left_joystick()) and vrmod:is_action_active(a, vrmod:get_right_joystick())
    end)
    return ok and held == true
end
local function watch_buttons()
    if not buttons_held() then hold_since, hold_done = nil, false return end
    local now = os.clock()
    if hold_since == nil then hold_since = now end
    if not hold_done and now - hold_since >= HOLD_S then
        hold_done = true
        if ui.open then close() else open() end
    end
end

-- ===== Back, read by us: Esc or Backspace on the keyboard, B on the right controller =====
-- (the game's pause menu stops coming once a card has been picked, 2026-11-04 18:42, so Back cannot ride on it alone)
local VK_ESCAPE, VK_BACK = 0x1B, 0x08
local back_was_down = false
local function back_down()
    -- no "reframework.is_key_down" guard: a sol usertype's method does not show as a field (the guard hid it, 18:45)
    local down = (safe(function() return reframework:is_key_down(VK_ESCAPE) end) == true)
        or (safe(function() return reframework:is_key_down(VK_BACK) end) == true)
    if not down and vrmod and safe(function() return vrmod:is_hmd_active() end) then
        down = safe(function()
            return vrmod:is_action_active(vrmod:get_action_b_button(), vrmod:get_right_joystick())
        end) == true
    end
    return down
end
local function watch_back()
    local down = back_down()
    if ui.open and down and not back_was_down then ui.want_back = true end
    back_was_down = down
end

-- ===== the frame =====
local frames = 0
re.on_frame(function()
    frames = frames + 1
    watch_buttons()
    watch_back()
    if ui.want_pick ~= nil then local i = ui.want_pick; ui.want_pick = nil; pcall(pick, i) end
    if ui.want_back then ui.want_back = false; pcall(back) end
    if ui.open and ui.render_in > 0 then
        ui.render_in = ui.render_in - 1
        if ui.render_in == 0 then pcall(render) end
    end
    if frames % CMD_EVERY_FRAMES == 0 then
        -- the same file idiom as every Visceral script (json.load_file under reframework/data; proven by the probe)
        local ok, data = pcall(json.load_file, CMD_FILE)
        local line = ok and type(data) == "table" and type(data.cmd) == "string" and data.cmd or nil
        if line and line ~= "" and line:sub(1, 5) ~= "done:" then
            pcall(json.dump_file, CMD_FILE, { cmd = "done: " .. line })
            L("command: " .. line)
            if line == "status" then
                local m = gm()
                L("status: open=" .. tostring(ui.open) .. " exclusive=" .. (m and exclusive_state(m) or "?"))
                -- the GUI manager's input restraints (a dictionary hash -> app.GUIManager.Unit), and the locked ones
                for _, fname in ipairs({ "<restrains>k__BackingField", "<lockRestrains>k__BackingField" }) do
                    local dict = m and safe(function() return m:get_field(fname) end)
                    local entries = dict and safe(function() return dict:get_field("_entries") end)
                    local count = dict and safe(function() return dict:get_field("_count") end) or 0
                    L(fname .. ": " .. tostring(count) .. " slot(s)")
                    for i = 0, (count or 0) - 1 do
                        local e = entries and safe(function() return entries:get_element(i) end)
                        local k = e and safe(function() return e:get_field("key") end)
                        local v = e and safe(function() return e:get_field("value") end)
                        local shown = tostring(v)
                        if v ~= nil and type(v) == "userdata" then
                            local parts = {}
                            local td = safe(function() return v:get_type_definition() end)
                            for _, f in ipairs(td and td:get_fields() or {}) do
                                parts[#parts + 1] = f:get_name() .. "=" .. tostring(safe(function() return v:get_field(f:get_name()) end))
                            end
                            shown = table.concat(parts, " ")
                        end
                        if k ~= nil then L(string.format("  %u : %s", k, shown)) end
                    end
                end
            elseif line == "release" then   -- the controls back to the game whatever we think (a stuck exclusive mode)
                local m = gm()
                local arr = m and safe(function() return m:get_field("exclusiveArray") end)
                local n = 0
                for i = 0, 15 do
                    local d = arr and safe(function() return arr:get_element(i) end)
                    if d ~= nil then
                        L("exclusive holder " .. i .. ": " .. type_name(d))
                        pcall(function() m:call("leaveExclusive(app.IGUIDriver)", d) end); n = n + 1
                    end
                end
                L("release: " .. n .. " holder(s) let go; exclusive now " .. (m and exclusive_state(m) or "?"))
            elseif line == "open" then pcall(open) elseif line == "close" then pcall(close)
            elseif line == "back" then pcall(back) elseif line:sub(1, 5) == "pick " then pcall(pick, tonumber(line:sub(6)) or 0) end
        end
    end
end)

re.on_draw_ui(function()
    if imgui.tree_node("Visceral Emporium (on the Duke's own shop screen)") then
        if imgui.button(ui.open and "Close it" or "Open it") then
            if ui.open then pcall(close) else pcall(open) end
        end
        imgui.text("In the headset: hold X and A together for half a second.")
        imgui.tree_pop()
    end
end)

L("loaded; " .. #_G.VISCERAL_OPTIONS .. " setting(s) handed over so far; key reading "
  .. (safe(function() return reframework:is_key_down(VK_ESCAPE) end) ~= nil and "works" or "NOT available"))
