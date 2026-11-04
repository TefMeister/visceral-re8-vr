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
-- the fourth card, the Duke's Kitchen (shown once the game's cooking is unlocked): REFramework's own full menu
-- (Tefa 2026-11-04: "the kitchen can be reframework full ui")
local KITCHEN_TITLE = "Every Setting"
local KITCHEN_MOTTO = "REFramework's full menu"
local MENU_KEY_SLOT = 185          -- src/bridge.h S_MENU_KEY: the plugin presses REFramework's menu key (menukey.cpp)
local MENU_KEY_AFTER_FRAMES = 45
local SWALLOW_S = 0.6
local DUKE_STOCK = 1481905281      -- the Duke's stock at the village (assortmentHash read at a real visit, 2026-11-04)              -- one B reaches the shop twice (its order, then the screen); the second is swallowed   -- after the shop has finished closing, so the menu opens over the game
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
local ui = { open = false, level = "tabs", tab = 1, page = 1, cards = {}, menu = nil, top = nil, render_in = 0, closing = false, game_closing = false, wait_menu = 0,
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
    set_texts(view, "si_list3", "m_name0", KITCHEN_TITLE)
    set_texts(view, "si_list3", "m_name1", KITCHEN_MOTTO)
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
    -- THE GAME'S OWN WAY IN (recorded at a real Duke 2026-11-04 19:20): createGUI("Shop"), then app.GUIShop.openShop with
    -- an app.GUIShopOrder.GUIRequestOpenShopParameter { mode = Menu, cursorIndex = 0, existMerchant, result }. The game
    -- then makes the money, the wall and the cards itself, and its own close (GUIShop.onHide / onFinishedHide) hands
    -- the player back. Making the wall and the cards by hand skipped that, and the player could not walk afterwards.
    ui.top = create("Shop")
    local sd = driver_of(ui.top)
    if sd == nil then L("could not make the shop's top screen"); return end
    -- THE GAME'S ORDER (2026-11-04 19:50): every screen's driver has an order object (get_order); the top screen's is an
    -- app.GUIShopOrder with openShop(mode, cursorIndex, existMerchant, result). Calling the driver's openShop directly
    -- showed the shop but skipped the order bookkeeping, so the game never closed the top screen after the cards
    -- (the wall stayed, no walking; n=3 runs, with and without picks).
    local order = safe(function() return sd:call("get_order") end)
    if order == nil then L("the top screen has no order object"); return end
    local mode_td = sdk.find_type_definition("app.GUIShopMode")
    local menu_mode = mode_td and safe(function() return mode_td:get_field("Menu"):get_data(nil) end)
    local res_td = sdk.find_type_definition("app.GUIShop.OperationResult")
    local result = safe(function() return sdk.create_instance("app.GUIShop.OperationResult") end)
                   or (res_td and safe(function() return res_td:create_instance() end))
    if result then
        local ctor = res_td and res_td:get_method(".ctor()")
        if ctor then pcall(function() ctor:call(result) end) end
        result = safe(function() return result:add_ref() end) or result
    end
    ui.result = result
    local ok, err = pcall(function()
        order:call("openShop(app.GUIShopMode.Value, System.Int32, System.Boolean, app.OperationResultBase)", menu_mode, 0, true, result)
    end)
    L("order.openShop -> ok=" .. tostring(ok) .. " " .. tostring(err or "") .. (result and "" or " (no result object)"))
    ui.open, ui.level, ui.tab, ui.page = true, "tabs", 1, 1
    ui.menu, ui.wait_menu = nil, 0
    L("opening")
end

-- the card screen is made by the game a frame or more after openShop: find it through the top screen's menuHandle,
-- then dress it (all cards the first kind to the game; our words)
local function adopt_menu()
    local sd = driver_of(ui.top)
    local h = sd and safe(function() return sd:get_field("<menuHandle>k__BackingField") end)
    local md = driver_of(h)
    if md == nil then return false end
    ui.menu = h
    -- every card is the first card's kind to the game (ShopIds = the mode each card opens): a pick on the third card
    -- (the game's Sell) left the menu taking no more keys, a pick on the first never did (2026-11-04 18:40-18:50);
    -- which card it really was we read ourselves (lit_card)
    local ids = safe(function() return md:get_field("ShopIds") end)
    local n = ids and safe(function() return ids:call("get_Count") end) or 0
    local first = n > 0 and safe(function() return ids:call("get_Item", 0) end) or nil
    if first ~= nil then
        for i = 1, n - 1 do pcall(function() ids:call("set_Item", i, first) end) end
    end
    render()
    ui.render_in = RENDER_AGAIN_FRAMES
    L("opened: the cards are ours (" .. tostring(n) .. " made the first kind)")
    return true
end

local function exclusive_state(m)
    return tostring(safe(function() return m:call("isExclusiveMode") end))
end

-- THE GAME'S OWN WAY OUT (recorded 2026-11-04 19:25): hide on the card screen's driver, after which the game runs
-- GUIShopMenu.onHide, GUIShop.onHide and GUIShop.onFinishedHide (which leaves exclusive mode and brings the HUD back)
-- closes the way the game's own B does on the groups (recorded 2026-11-04 19:56): the TOP shop screen hides, then the
-- game runs GUIShop.onHide / onFinishedHide (leaves exclusive mode, brings the HUD back); our onFinishedHide hook marks
-- us closed. ui.closing keeps our Back catch out of the way until then.
local function close()
    if not ui.open then return end
    ui.closing = true
    local sd = driver_of(ui.top)
    local order = sd and safe(function() return sd:call("get_order") end)
    local ok = false
    if order then
        ok = pcall(function() order:call("hide(System.Boolean, System.Boolean, System.Boolean, System.String)", false, false, false, "") end)
    end
    if not ok and sd then
        local p = safe(function() return sdk.create_instance("app.GUIRequest.Parameter"):add_ref() end)
        ok = pcall(function() sd:call("hide(app.GUIRequest.Parameter)", p) end)
    end
    if not ok then   -- nothing of ours to hide: the blunt way, so nothing stays on screen
        local m = gm()
        if m then pcall(function() m:call("suicideGUIShop") end) end
        ui.open, ui.menu, ui.top, ui.closing = false, nil, nil, false
    end
    ui.close_deadline = os.clock() + 3.0
    L("closing (" .. (ok and "the top shop screen's own hide" or "suicideGUIShop") .. ")")
end

local function pick(idx)
    if idx == 3 then   -- the kitchen: close the shop, then REFramework's full menu
        ui.want_full_ui = true
        close()
        return
    end
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

-- the shop's results say which sub-screen to open next; our skipped picks left them pointing at one, and the game then
-- waited for it on the way out (the wall stayed, no walking, 2026-11-04 19:40). Cleared before every close.
function clear_results()
    if ui.result then pcall(function() ui.result:call("clear") end) end
    local sd = driver_of(ui.top)
    local child = sd and safe(function() return sd:get_field("<childOperationResult>k__BackingField") end)
    if child then pcall(function() child:call("clear") end) end
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
            -- the game opens the card menu itself with mode Menu (V = 0) on the way in: that one must run
            local mode_obj = safe(function() return sdk.to_managed_object(args[3]) end)
            local v = mode_obj and safe(function() return mode_obj:get_field("V") end)
            if v == nil or v == 0 then return end
            -- opened the game's own way, the mode IS the card: Buy 1, Customize 2, Sell 3, Recipe 4 (the kitchen) `[verified-live
            -- 2026-11-04]`; the lit-card reading only knows the three-card list and misreads with the kitchen showing
            ui.mode_card = (v >= 1 and v <= 4) and (v - 1) or nil
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
            if ui.mode_card ~= nil then idx = ui.mode_card end
            if ui.real_screens and ui.level == "tabs" and v >= 1 and v <= 3 then
                local this = safe(function() return sdk.to_managed_object(args[2]) end)
                local ah = this and safe(function() return this:get_field("<assortmentHash>k__BackingField") end)
                if this and (ah == nil or ah == 0) then
                    pcall(function() this:set_field("<assortmentHash>k__BackingField", DUKE_STOCK) end)
                end
                L(string.format("real screen %d passed through (assortment %s)", v, tostring(ah)))
                ui.in_real = v
                ui.tab = v            -- the card IS the group: 1 Comfort, 2 Graphics, 3 Settings
                ui.level = "real"
                return
            end
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
                    return sdk.PreHookResult.SKIP_ORIGINAL      -- no pause over us
                end
            end, function(retval) return retval end)
        elseif m:get_name() == "hide" then
            -- the game's B goes straight to the card screen's hide (not through its order, 2026-11-04 19:52): on one of
            -- our pages that is "back to the groups"
            sdk.hook(m, function(args)
                local this = safe(function() return sdk.to_managed_object(args[2]) end)
                local tn = this and type_name(this) or ""
                if ui.open and tn:find("Shop") then
                    L(string.format("hide seen on %s: open=%s closing=%s level=%s", tn, tostring(ui.open), tostring(ui.closing), ui.level))
                end
                if not ui.open or ui.closing then return end
                local fresh = os.clock() < (ui.swallow_until or 0)
                if ui.level ~= "page" and not fresh then return end
                -- B on a page hides the TOP shop screen (app.GUIShop), on the groups the cards (2026-11-04 19:56)
                if tn == "app.GUIShopMenu" or tn == "app.GUIShop" then
                    -- one B reaches us twice (the order, then the screen): the second must not close the shop
                    if not fresh then ui.want_back = true end
                    ui.swallow_until = os.clock() + SWALLOW_S
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end, function(retval) return retval end)
        end
    end
    -- the game's own Back (B, and whatever key it maps) asks the card screen's ORDER to hide: on one of our pages that
    -- is "back to the groups", so the request is dropped; on the groups it goes ahead and the game closes the shop
    local order_td = sdk.find_type_definition("app.GUIOrder")
    for _, m in ipairs(order_td and order_td:get_methods() or {}) do
        if m:get_name() == "hide" then
            sdk.hook(m, function(args)
                if not ui.open or ui.closing then return end
                local this = safe(function() return sdk.to_managed_object(args[2]) end)
                local d = this and safe(function() return this:call("get_driver") end)
                local dn = d and type_name(d) or ""
                local fresh = os.clock() < (ui.swallow_until or 0)
                if (dn == "app.GUIShopMenu" or dn == "app.GUIShop") and (ui.level == "page" or fresh) then
                    if not fresh then ui.want_back = true end
                    ui.swallow_until = os.clock() + SWALLOW_S
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end, function(retval) return retval end)
        end
    end
    -- the game finished closing the shop (its own path): we are closed too
    local shop_td = sdk.find_type_definition("app.GUIShop")
    local finished = shop_td and shop_td:get_method("onFinishedHide")
    if finished then
        sdk.hook(finished, nil, function(retval)
            if ui.open then
                ui.open, ui.menu, ui.top, ui.game_closing, ui.closing = false, nil, nil, false, false
                L("closed (the game's own close ran to the end)")
            end
            return retval
        end)
    end
end

-- ===== THE SUPPLIES SCREEN AS THE ON / OFF SCREEN (Tefa 2026-11-04: "in the shop screen can have a red lint in the corner
-- for off, green for on and a description on the right hand side for a description of what the setting does") =====
-- A group card opens the game's own Buy screen (the Duke's stock, so it builds its grid); its unit list is cut to the
-- group's on/off settings, each tile then shows one: "On" / "Off" where the price was, the red Sold Out banner reading
-- "Off" when off, the corner marker red or green; the name, the group and the help line go in the description panel.
-- A on a tile flips the setting instead of buying (the buy steps are skipped). [hypothesis] until seen.
local GREEN, RED = 0xFF40C040, 0xFF3030D0          -- via.Color rgba as 0xAABBGGRR
local buy_drv = nil
local function checks_for_group()
    local out = {}
    for _, e in ipairs(entries_for(TABS[ui.tab].tab)) do
        if e.kind == "check" or e.kind == "button" then out[#out + 1] = e end
    end
    return out
end
local function control_named(root, name)
    local found = nil
    local function visit(c, d)
        if c == nil or d > 12 or found then return end
        if safe(function() return c:call("get_Name") end) == name then found = c return end
        local ch = safe(function() return c:call("get_Child") end)
        while ch ~= nil and not found do visit(ch, d + 1); ch = safe(function() return ch:call("get_Next") end) end
    end
    visit(root, 0)
    return found
end
local function set_text(c, t) if c then pcall(function() c:call("set_Message", t) end) end end
local function set_visible(c, v) if c then pcall(function() c:call("set_Visible", v) end) end end
local function set_color(c, rgba)
    if c == nil then return end
    local col = safe(function()
        local vt = ValueType.new(sdk.find_type_definition("via.Color"))
        vt:set_field("rgba", rgba)
        return vt
    end)
    if col then pcall(function() c:call("set_Color", col) end) end
end
local function buy_grid()
    local go = buy_drv and safe(function() return buy_drv:call("get_GameObject") end)
    local gui = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI")) end)
    local view = gui and safe(function() return gui:call("get_View") end)
    return view and control_named(view, "sg_list")
end
local function render_buy()
    if not (ui.open and ui.level == "real" and buy_drv) then return end
    local list = checks_for_group()
    local grid = buy_grid()
    if grid == nil then return end
    for k = 1, 16 do
        local tile = control_named(grid, "item" .. k)
        local e = list[k]
        if tile and e then
            local on = value_text(e) == "On"
            local price = control_named(tile, "c_price")
            if price then
                set_text(control_named(price, "m_num"), e.kind == "button" and "Use" or (on and "On" or "Off"))
                set_visible(control_named(price, "icon_parts"), false)
                set_visible(control_named(price, "t_bg_soldout"), e.kind ~= "button" and not on)
                local so = control_named(price, "m_soldout")
                set_visible(so, e.kind ~= "button" and not on)
                set_text(so, "Off")
            end
            local new = control_named(tile, "c_new")
            if new then
                set_visible(new, true)
                set_visible(control_named(new, "c_type0"), true)
                set_visible(control_named(new, "c_type1"), false)
                set_color(control_named(new, "Texture0"), on and GREEN or RED)
            end
        end
    end
    -- the description panel: the lit tile's name, the group, the help line
    local idx = (tonumber(safe(function() return buy_drv:get_field("<lastIndex>k__BackingField") end)) or 0) + 1
    local e = list[idx]
    if e then
        set_text(safe(function() return buy_drv:get_field("<itemNameText>k__BackingField") end), e.label or "?")
        set_text(safe(function() return buy_drv:get_field("<itemCategoryText>k__BackingField") end), TABS[ui.tab].name)
        set_text(safe(function() return buy_drv:get_field("<itemDescriptionText>k__BackingField") end),
                 (e.help and e.help ~= "") and e.help or ("Now: " .. value_text(e) .. ". Press to change."))
        set_text(safe(function() return buy_drv:get_field("<stockText>k__BackingField") end), value_text(e))
    end
end
do
    local bt = sdk.find_type_definition("app.GUIShopBuy")
    local function hook(name, pre, post)
        for _, m in ipairs(bt and bt:get_methods() or {}) do
            if m:get_name() == name then pcall(sdk.hook, m, pre, post or function(r) return r end) end
        end
    end
    -- the unit list cut to our settings (after the game built it from the Duke's stock)
    hook("collectBuyUnits", function(args)
        if ui.open and ui.level == "real" then buy_drv = safe(function() return sdk.to_managed_object(args[2]) end) end
    end, function(retval)
        if ui.open and ui.level == "real" and buy_drv then
            local units = safe(function() return buy_drv:get_field("<buyUnits>k__BackingField") end)
            local n = units and safe(function() return units:call("get_Count") end) or 0
            local want = math.max(1, #checks_for_group())
            if n > want then pcall(function() units:call("RemoveRange", want, n - want) end) end
        end
        return retval
    end)
    for _, name in ipairs({ "setupScrollGrid", "scrollGridSelectionChanged", "onChangeScrollGrid" }) do
        hook(name, nil, function(retval)
            if ui.open and ui.level == "real" then ui.render_buy_in = 2 end
            return retval
        end)
    end
    -- A on a tile: our flip, never a purchase
    -- A on a tile first asks canBuyItem (needUnitSelectDialog, isSoldOutByUnit run with it, 2026-11-04 20:15); our tiles
    -- have no real item behind them, so the game says no and stops there: the flip happens in that question instead
    for _, name in ipairs({ "canBuyItem", "buyItem", "decideBuyItem", "createBuyDecideDialog", "createBuyUnitDecideDialog" }) do
        hook(name, function(args)
            if not (ui.open and ui.level == "real") then return end
            local idx = (tonumber(safe(function() return buy_drv:get_field("<lastIndex>k__BackingField") end)) or 0) + 1
            local e = checks_for_group()[idx]
            if e and os.clock() > (ui.flip_quiet_until or 0) then
                ui.flip_quiet_until = os.clock() + 0.3
                if e.kind == "check" and e.set then
                    local okg, cur = pcall(e.get)
                    pcall(e.set, not (okg and cur == true))
                elseif e.kind == "button" and e.press then pcall(e.press) end
                L("flipped on the Supplies screen: " .. tostring(e.label) .. " -> " .. value_text(e))
                ui.render_buy_in = 1
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end)
    end
    -- leaving the Buy screen (B): back to our groups
    hook("onHide", nil, function(retval)
        if ui.open and ui.level == "real" then ui.level, buy_drv = "tabs", nil; ui.render_in = 6 end
        return retval
    end)
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
-- a Back key we saw ourselves counts only if the game's own Back (the hide hook) did not come within a few frames,
-- so one press is never two Backs
local KEY_BACK_WAIT_FRAMES = 8
local key_back_at = nil
local frames = 0
local function watch_back()
    local down = back_down()
    if ui.open and down and not back_was_down then key_back_at = frames end
    back_was_down = down
    if ui.want_back then key_back_at = nil end
    if key_back_at and frames - key_back_at >= KEY_BACK_WAIT_FRAMES then
        key_back_at = nil
        if ui.open and not ui.game_closing then ui.want_back = true end
    end
end

-- ===== the frame =====
re.on_frame(function()
    frames = frames + 1
    watch_buttons()
    watch_back()
    if ui.open and ui.menu == nil and not ui.closing then
        ui.wait_menu = (ui.wait_menu or 0) + 1
        if adopt_menu() then ui.wait_menu = 0
        elseif ui.wait_menu > 300 then L("the card screen never came; closing"); pcall(close) end
    end
    if ui.want_pick ~= nil then
        local i = ui.want_pick; ui.want_pick = nil
        local ok, err = pcall(pick, i)
        if not ok then L("pick " .. tostring(i) .. " failed: " .. tostring(err)) end
    end
    if ui.open and ui.closing and ui.close_deadline and os.clock() > ui.close_deadline then
        ui.close_deadline = nil
        local m = gm()
        if m then pcall(function() m:call("suicideGUIShop") end) end
        ui.open, ui.menu, ui.top, ui.closing = false, nil, nil, false
        L("the close did not finish in 3 s: suicideGUIShop")
    end
    if ui.want_full_ui and not ui.open then
        ui.full_ui_in = (ui.full_ui_in or MENU_KEY_AFTER_FRAMES) - 1
        if ui.full_ui_in <= 0 then
            ui.want_full_ui, ui.full_ui_in = false, nil
            local b = rawget(_G, "visceral_re8_bridge")
            if b and b.ready() then b.w(MENU_KEY_SLOT, 1); L("REFramework's menu asked for (the kitchen card)")
            else L("the kitchen card: no bridge to the plugin, so REFramework's menu cannot be opened from here") end
        end
    end
    if ui.want_back then
        ui.want_back = false
        local ok, err = pcall(back)
        if not ok then L("back failed: " .. tostring(err)) end
    end
    if ui.render_buy_in and ui.render_buy_in > 0 then
        ui.render_buy_in = ui.render_buy_in - 1
        if ui.render_buy_in == 0 then
            local ok, err = pcall(render_buy)
            if not ok then L("render_buy failed: " .. tostring(err)) end
        end
    end
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
            elseif line == "kill" then   -- rescue: everything of the shop off, every exclusive holder let go
                local m = gm()
                if m then pcall(function() m:call("suicideGUIShop") end) end
                local arr = m and safe(function() return m:get_field("exclusiveArray") end)
                for i = 0, 15 do
                    local d = arr and safe(function() return arr:get_element(i) end)
                    if d ~= nil then pcall(function() m:call("leaveExclusive(app.IGUIDriver)", d) end) end
                end
                ui.open, ui.menu, ui.top, ui.closing, ui.game_closing = false, nil, nil, false, false
                L("kill: shop off, exclusive now " .. (m and exclusive_state(m) or "?"))
            elseif line == "realbuy" then ui.real_screens = true; L("experiment: the cards open the game's real screens")
            elseif line == "ownpages" then ui.real_screens = false; L("the cards open our own pages again")
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
