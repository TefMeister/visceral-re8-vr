-- visceral_re8_shop_probe.lua -- the Duke's shop screen, read so the Visceral options can be dressed in it (2026-11-04,
-- Fable). Tefa (2026-10-30): "can you design it using the game's own Duke's shop interface, that the player can actually
-- see in VR? and has all our settings on it". A PROBE: its own file (code-shape rule), read by nothing else, taken out
-- of the game folder when its job is done.
--
-- Driven by one small file, reframework/data/visceral_re8/shop_probe.json, read once a second:
--   { "cmd": "names" }   log every GUI game object drawn from now on (one line each, once per name)
--   { "cmd": "manager" } log app.GUIManager's methods and fields whose names mention Shop / Duke / GUI
--   { "cmd": "open" }    call app.GUIManager.createGUIShopBuy() (the 2026-10-30 lead) and say what came back
--   { "cmd": "dump" }    the next time a GUI object whose name holds "Shop" is drawn, walk its whole view tree to the
--                        log: control type, name, and for text controls the text; plus the shop script's methods
--   { "cmd": "close" }   call app.GUIManager.suicideGUIShop()
-- When a command is done the file is rewritten as { "cmd": "done: <cmd>", "note": "..." }.

local TAG = "[visceral-re8-shop]"
local CMD_FILE = "visceral_re8/shop_probe.json"
local CHECK_EVERY_FRAMES = 60
local MAX_LINES_PER_DUMP = 1500
local MAX_DEPTH = 14

local function L(s) log.info(TAG .. " " .. tostring(s)) end
local function safe(f, ...) local ok, v = pcall(f, ...); if ok then return v end; return nil end

local frames = 0
local naming = false
local want_dump = false
local seen, dumped = {}, {}
local shop_handle = nil            -- what createGUIShopBuy() returned at the last "open"
local hooks_on, block_decide, hook_last = false, false, {}
local watch_on, live_drivers = false, {}

-- the RE Engine name hash (murmur3_32 of the UTF-16LE name, seed 0xFFFFFFFF; the same as the item and sound ids,
-- KNOWN.md 2026-10-24). createGUIShopBuy() makes the GUI whose alias hash is hash("ShopBuy") = 3474722425
-- [verified-live 2026-11-04], so every other screen can be asked for by its alias name through createGUI(hash, bool).
local function murmur3_utf16(s)
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

local function write_back(cmd, note)
    pcall(json.dump_file, CMD_FILE, { cmd = "done: " .. cmd, note = note or "" })
end

local function type_name(obj)
    local td = safe(function() return obj:get_type_definition() end)
    return td and td:get_full_name() or "?"
end

local function list_methods(type_full_name, filter)
    local td = sdk.find_type_definition(type_full_name)
    if not td then L("no type " .. type_full_name); return end
    L("methods of " .. type_full_name .. (filter and (" matching " .. filter) or "") .. ":")
    local n = 0
    for _, m in ipairs(td:get_methods()) do
        local name = m:get_name()
        if not filter or name:lower():find(filter:lower(), 1, true) then
            local params = {}
            for _, p in ipairs(safe(function() return m:get_param_types() end) or {}) do
                params[#params + 1] = p:get_full_name()
            end
            local rt = safe(function() return m:get_return_type():get_full_name() end) or "?"
            L(string.format("  %s(%s) -> %s", name, table.concat(params, ", "), rt))
            n = n + 1
            if n > 400 then L("  ... (cut)"); break end
        end
    end
    L("fields of " .. type_full_name .. ":")
    n = 0
    for _, f in ipairs(td:get_fields()) do
        local name = f:get_name()
        if not filter or name:lower():find(filter:lower(), 1, true) then
            L(string.format("  %s : %s", name, safe(function() return f:get_type():get_full_name() end) or "?"))
            n = n + 1
            if n > 200 then L("  ... (cut)"); break end
        end
    end
end

local function walk(ctrl, depth, counter)
    if ctrl == nil or depth > MAX_DEPTH or counter.n > MAX_LINES_PER_DUMP then return end
    local tn = type_name(ctrl)
    local name = safe(function() return ctrl:call("get_Name") end) or "?"
    local extra = ""
    if tn:find("Text") then
        local msg = safe(function() return ctrl:call("get_Message") end)
        if msg ~= nil then extra = extra .. ' text="' .. tostring(msg) .. '"' end
    end
    if tn:find("Texture") or tn:find("Material") then
        local path = safe(function() return ctrl:call("get_Path") end)
        if path ~= nil then extra = extra .. ' path=' .. tostring(path) end
    end
    local vis = safe(function() return ctrl:call("get_Visible") end)
    if vis ~= nil then extra = extra .. " visible=" .. tostring(vis) end
    L(string.rep("  ", depth) .. tn .. " '" .. tostring(name) .. "'" .. extra)
    counter.n = counter.n + 1
    local child = safe(function() return ctrl:call("get_Child") end)
    while child ~= nil and counter.n <= MAX_LINES_PER_DUMP do
        walk(child, depth + 1, counter)
        child = safe(function() return child:call("get_Next") end)
    end
end

local function dump_game_object(go, name)
    L("==== DUMP of GUI object '" .. name .. "' ====")
    local gui = safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI")) end)
    if gui == nil then L("no via.gui.GUI component found"); return end
    local view = safe(function() return gui:call("get_View") end)
    if view == nil then L("the GUI component has no view"); return end
    local counter = { n = 0 }
    walk(view, 0, counter)
    L("==== " .. counter.n .. " controls listed ====")
    -- the script components on the same object: their types, and the shop ones' methods
    local tf = safe(function() return go:call("get_Folder") end)
    for _, tname in ipairs({ "app.GUIShopBuy", "app.GUIShopCustomize", "app.GUIShop", "app.GUIShopBg",
                             "app.GUIShopTop", "app.GUIShopSell", "app.GUIShopBase" }) do
        local td = sdk.find_type_definition(tname)
        if td then
            local comp = safe(function() return go:call("getComponent(System.Type)", sdk.typeof(tname)) end)
            L("component " .. tname .. ": " .. (comp ~= nil and "PRESENT on this object" or "type exists, not on this object"))
            if comp ~= nil then list_methods(tname) end
        end
    end
end

re.on_pre_gui_draw_element(function(element, context)
    if not naming and not want_dump then return true end
    local go = safe(function() return element:call("get_GameObject") end)
    if go == nil then return true end
    local name = safe(function() return go:call("get_Name") end)
    if name == nil then return true end
    if naming and not seen[name] then
        seen[name] = true
        L("gui object drawn: " .. name .. "  (" .. type_name(element) .. ")")
    end
    if want_dump and name:find("Shop") and not dumped[name] then
        dumped[name] = true
        local ok, err = pcall(dump_game_object, go, name)
        if not ok then L("dump failed: " .. tostring(err)) end
        write_back("dump", "dumped " .. name)
    end
    return true
end)

local function run(cmd)
    L("command: " .. cmd)
    if cmd == "names" then
        naming = true; seen = {}
        write_back(cmd, "logging every GUI object drawn from now on")
    elseif cmd == "manager" then
        list_methods("app.GUIManager", "shop")
        list_methods("app.GUIManager", "duke")
        list_methods("app.GUIManager", "create")
        write_back(cmd, "see the log")
    elseif cmd == "open" or cmd == "close" then
        local gm = sdk.get_managed_singleton("app.GUIManager")
        if gm == nil then L("no app.GUIManager singleton"); write_back(cmd, "no GUIManager"); return end
        local method = cmd == "open" and "createGUIShopBuy" or "suicideGUIShop"
        local ok, r = pcall(function() return gm:call(method) end)
        if cmd == "open" and ok then shop_handle = r end
        L(method .. "() -> ok=" .. tostring(ok) .. " result=" .. tostring(r))
        local showing = safe(function() return gm:call("isShowingGUIShop") end)
        L("isShowingGUIShop() -> " .. tostring(showing))
        write_back(cmd, method .. " ok=" .. tostring(ok) .. " showing=" .. tostring(showing))
    elseif cmd == "dump" then
        want_dump = true; dumped = {}
        L("will dump the next GUI object whose name holds 'Shop'")
        write_back(cmd, "waiting for a GUI object whose name holds 'Shop' to be drawn")
    elseif cmd:sub(1, 5) == "call " then
        -- "call <method>" : any 0-argument method of app.GUIManager (enterShopEvent, leaveShopEvent, ...)
        local method = cmd:sub(6)
        local gm = sdk.get_managed_singleton("app.GUIManager")
        if gm == nil then L("no app.GUIManager singleton"); write_back(cmd, "no GUIManager"); return end
        local ok, r = pcall(function() return gm:call(method) end)
        L(method .. "() -> ok=" .. tostring(ok) .. " result=" .. tostring(r))
        write_back(cmd, method .. " ok=" .. tostring(ok) .. " result=" .. tostring(r))
    elseif cmd:sub(1, 5) == "type " then
        -- "type <full type name> [filter]" : every method and field of a type (own only)
        local rest = cmd:sub(6)
        local tname, filter = rest:match("^(%S+)%s*(.*)$")
        list_methods(tname, filter ~= "" and filter or nil)
        write_back(cmd, "see the log")
    elseif cmd:sub(1, 7) == "create " then
        -- "create <alias>" : app.GUIManager.createGUI(hash(alias), true); the handle becomes the one "inspect" reads
        local alias = cmd:sub(8)
        local gm = sdk.get_managed_singleton("app.GUIManager")
        if gm == nil then L("no app.GUIManager singleton"); write_back(cmd, "no GUIManager"); return end
        local h = murmur3_utf16(alias)
        local ok, r = pcall(function() return gm:call("createGUI(System.UInt32, System.Boolean)", h, true) end)
        local valid = (ok and r ~= nil) and safe(function() return r:call("isValid") end) or nil
        local driver = (ok and r ~= nil) and safe(function() return r:get_field("<driver>k__BackingField") end) or nil
        L(string.format("createGUI('%s' = %u) -> ok=%s result=%s valid=%s driver=%s", alias, h, tostring(ok), tostring(r),
                        tostring(valid), driver ~= nil and type_name(driver) or "nil"))
        if ok and r ~= nil and driver ~= nil then shop_handle = r end
        write_back(cmd, string.format("valid=%s driver=%s", tostring(valid), driver ~= nil and type_name(driver) or "nil"))
    elseif cmd == "openshop" then
        -- the game's own way in: app.GUIShop.openShop(app.GUIRequest.Parameter) on the top screen's driver
        local gm = sdk.get_managed_singleton("app.GUIManager")
        if shop_handle == nil or type_name(safe(function() return shop_handle:get_field("<driver>k__BackingField") end) or {}) ~= "app.GUIShop" then
            local ok, r = pcall(function() return gm:call("createGUI(System.UInt32, System.Boolean)", murmur3_utf16("Shop"), true) end)
            if ok and r ~= nil then shop_handle = r end
        end
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver == nil then L("no Shop driver"); write_back(cmd, "no Shop driver"); return end
        local param = sdk.create_instance("app.GUIRequest.Parameter")
        if param == nil then L("could not make app.GUIRequest.Parameter"); write_back(cmd, "no parameter"); return end
        param = param:add_ref()
        for _, f in ipairs(sdk.find_type_definition("app.GUIRequest.Parameter"):get_fields()) do
            L("parameter field " .. f:get_name() .. " = " .. tostring(safe(function() return param:get_field(f:get_name()) end)))
        end
        local ok, r = pcall(function() return driver:call("openShop(app.GUIRequest.Parameter)", param) end)
        L("openShop(param) -> ok=" .. tostring(ok) .. " result=" .. tostring(r))
        L("isShowingGUIShop() -> " .. tostring(safe(function() return gm:call("isShowingGUIShop") end)))
        write_back(cmd, "openShop ok=" .. tostring(ok) .. " result=" .. tostring(r))
    elseif cmd == "modes" then
        -- app.GUIShopMode's static hashes (Menu, Buy, Customize, Sell, Recipe): are they the GUI aliases?
        local td = sdk.find_type_definition("app.GUIShopMode")
        for _, n in ipairs({ "MenuHash", "BuyHash", "CustomizeHash", "SellHash", "RecipeHash", "CountOf" }) do
            local f = td:get_field(n)
            local v = f and safe(function() return f:get_data(nil) end)
            local nm = v and safe(function() return sdk.call_native_func(nil, td, "getName", v) end)
            L(string.format("%s = %s  (ShopBuy hash is %u; name by getName: %s)", n, tostring(v), murmur3_utf16("ShopBuy"), tostring(nm)))
        end
        write_back(cmd, "see the log")
    elseif cmd:sub(1, 11) == "createhash " then
        local h = tonumber(cmd:sub(12))
        local gm = sdk.get_managed_singleton("app.GUIManager")
        local ok, r = pcall(function() return gm:call("createGUI(System.UInt32, System.Boolean)", h, true) end)
        local driver = (ok and r ~= nil) and safe(function() return r:get_field("<driver>k__BackingField") end) or nil
        local go = driver and safe(function() return driver:call("get_GameObject") end)
        L(string.format("createGUI(%u) -> ok=%s result=%s driver=%s object='%s'", h, tostring(ok), tostring(r),
                        driver ~= nil and type_name(driver) or "nil",
                        tostring(go and safe(function() return go:call("get_Name") end) or "?")))
        if ok and r ~= nil and driver ~= nil then shop_handle = r end
        write_back(cmd, "driver=" .. (driver ~= nil and type_name(driver) or "nil"))
    elseif cmd == "show" then
        -- make the current handle's screen draw: drawSuspend off, onShow(true)
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver == nil then L("no handle"); write_back(cmd, "no handle"); return end
        local a = pcall(function() driver:call("set_drawSuspend", false) end)
        local b, err = pcall(function() driver:call("onShow", true) end)
        L("show: set_drawSuspend(false) ok=" .. tostring(a) .. "; onShow(true) ok=" .. tostring(b) .. " " .. tostring(err or ""))
        L("drawSuspend now " .. tostring(safe(function() return driver:call("get_drawSuspend") end)))
        write_back(cmd, "drawSuspend=" .. tostring(safe(function() return driver:call("get_drawSuspend") end)))
    elseif cmd == "unsuspend" then
        -- drawSuspend off only (no onShow: that crashed a dataless ShopBuy, 2026-11-04 17:34)
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver == nil then L("no handle"); write_back(cmd, "no handle"); return end
        local a = pcall(function() driver:call("set_drawSuspend", false) end)
        L("unsuspend: ok=" .. tostring(a) .. " drawSuspend now " .. tostring(safe(function() return driver:call("get_drawSuspend") end)))
        write_back(cmd, "drawSuspend=" .. tostring(safe(function() return driver:call("get_drawSuspend") end)))
    elseif cmd == "dumpnow" then
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        local go = driver and safe(function() return driver:call("get_GameObject") end)
        if go == nil then L("no object"); write_back(cmd, "no object"); return end
        local name = tostring(safe(function() return go:call("get_Name") end) or "?")
        dump_game_object(go, name)
        write_back(cmd, "dumped " .. name)
    elseif cmd:sub(1, 8) == "settext " then
        -- "settext <control name>|<text>" : every via.gui.Text of that name in the current handle's view gets the text
        local cname, text = cmd:sub(9):match("^(.-)|(.*)$")
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        local go = driver and safe(function() return driver:call("get_GameObject") end)
        local gui = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI")) end)
        local view = gui and safe(function() return gui:call("get_View") end)
        if view == nil or cname == nil then L("settext: no view, or bad form"); write_back(cmd, "no view"); return end
        local hits = 0
        local function visit(ctrl, depth)
            if ctrl == nil or depth > MAX_DEPTH then return end
            if type_name(ctrl):find("Text") and safe(function() return ctrl:call("get_Name") end) == cname then
                local ok, err = pcall(function() ctrl:call("set_Message", text) end)
                hits = hits + 1
                L(string.format("set_Message on '%s' #%d ok=%s %s; reads back: %s", cname, hits, tostring(ok), tostring(err or ""),
                                tostring(safe(function() return ctrl:call("get_Message") end))))
            end
            local child = safe(function() return ctrl:call("get_Child") end)
            while child ~= nil do
                visit(child, depth + 1)
                child = safe(function() return child:call("get_Next") end)
            end
        end
        visit(view, 0)
        write_back(cmd, hits .. " text control(s) set")
    elseif cmd == "aliasscan" then
        -- many likely screen names, ten a frame; only the ones that give a handle are logged (and left alone)
        local heads = { "Shop", "Duke", "Emporium", "Merchant", "Store", "Trade", "Vendor", "GUIShop", "ShopMenu", "Menu" }
        local tails = { "", "Menu", "Top", "Mode", "Select", "Main", "Title", "Entry", "Head", "Cover", "Card", "Cards",
                        "Tab", "Tabs", "Category", "Index", "Root", "Base", "Frame", "Window", "Panel", "List", "Mode",
                        "Selector", "Choice", "Home", "Front", "Start", "Lobby", "Hub", "Board", "Sign", "Modes", "Bg2" }
        local names = {}
        for _, h in ipairs(heads) do for _, t in ipairs(tails) do names[#names + 1] = h .. t end end
        alias_queue = names
        L("aliasscan: " .. #names .. " names queued")
        write_back(cmd, #names .. " names queued; hits go to the log as 'ALIAS HIT'")
    elseif cmd:sub(1, 10) == "exclusive " then
        -- "exclusive <alias> <mode>" : app.GUIManager.createExclusiveModeGUI(hash(alias), hash(mode)), the way the
        -- inventory and (likely) the shop are opened: a screen that takes the game's input
        local alias, mode = cmd:sub(11):match("^(%S+)%s+(%S+)$")
        local gm = sdk.get_managed_singleton("app.GUIManager")
        if alias == nil or gm == nil then L("exclusive: bad form or no manager"); write_back(cmd, "bad form"); return end
        local ok, r = pcall(function()
            return gm:call("createExclusiveModeGUI(System.UInt32, System.UInt32)", murmur3_utf16(alias), murmur3_utf16(mode))
        end)
        local driver = (ok and r ~= nil) and safe(function() return r:get_field("<driver>k__BackingField") end) or nil
        L(string.format("createExclusiveModeGUI('%s', '%s') -> ok=%s result=%s driver=%s exclusiveMode=%s", alias, mode,
                        tostring(ok), tostring(r), driver and type_name(driver) or "nil",
                        tostring(safe(function() return gm:call("isExclusiveMode") end))))
        if ok and r ~= nil and driver ~= nil then shop_handle = r end
        write_back(cmd, "driver=" .. (driver and type_name(driver) or "nil"))
    elseif cmd == "enterex" then
        -- app.GUIManager.enterExclusive(driver) on the current handle's driver
        local gm = sdk.get_managed_singleton("app.GUIManager")
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver == nil then L("no handle"); write_back(cmd, "no handle"); return end
        local ok, err = pcall(function() gm:call("enterExclusive(app.IGUIDriver)", driver) end)
        L("enterExclusive -> ok=" .. tostring(ok) .. " " .. tostring(err or "") .. "; exclusiveMode="
          .. tostring(safe(function() return gm:call("isExclusiveMode") end)))
        write_back(cmd, "ok=" .. tostring(ok))
    elseif cmd == "orders" then
        -- the order words a driver answers to: ExecuteDict's keys (hashes) matched against likely words
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        local dict = driver and safe(function() return driver:get_field("ExecuteDict") end)
        if dict == nil then L("no ExecuteDict"); write_back(cmd, "no dict"); return end
        local words = { "Show", "Hide", "SetSegment", "SetState", "Suicide", "SetAttachTarget", "EnterExclusive", "LeaveExclusive",
                        "OpenShop", "Open", "Close", "OpenMenu", "OpenBuy", "OpenSell", "OpenCustomize", "OpenRecipe", "Shop",
                        "ShopMenu", "Menu", "Buy", "Sell", "Customize", "Recipe", "Start", "Enter", "Leave", "Update", "Execute" }
        local by = {}
        for _, w in ipairs(words) do by[murmur3_utf16(w)] = w end
        local entries = safe(function() return dict:get_field("_entries") end)
        local count = safe(function() return dict:get_field("_count") end) or 0
        L("ExecuteDict: " .. tostring(count) .. " order(s)")
        if entries ~= nil then
            for i = 0, count - 1 do
                local e = safe(function() return entries:get_element(i) end)
                local k = e and safe(function() return e:get_field("key") end)
                if k ~= nil then L(string.format("  order hash %u = %s", k, by[k] or "?")) end
            end
        end
        write_back(cmd, "see the log")
    elseif cmd == "show2" or cmd == "exclusive2" or cmd:sub(1, 8) == "request " then
        -- the base driver's own entry points with a fresh Parameter: show(param), enterExclusive(param), or
        -- execute(GUIRequest{nameHash = hash(word), parameter}) for "request <word>"
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver == nil then L("no handle"); write_back(cmd, "no handle"); return end
        local param = sdk.create_instance("app.GUIRequest.Parameter"):add_ref()
        local ok, r
        if cmd == "show2" then
            ok, r = pcall(function() return driver:call("show(app.GUIRequest.Parameter)", param) end)
        elseif cmd == "exclusive2" then
            ok, r = pcall(function() return driver:call("enterExclusive(app.GUIRequest.Parameter)", param) end)
        else
            local word = cmd:sub(9)
            local req = sdk.create_instance("app.GUIRequest"):add_ref()
            req:set_field("<nameHash>k__BackingField", murmur3_utf16(word))
            req:set_field("<parameter>k__BackingField", param)
            ok, r = pcall(function() return driver:call("execute(app.GUIRequest)", req) end)
        end
        L(cmd .. " -> ok=" .. tostring(ok) .. " result=" .. tostring(r) .. "; drawSuspend="
          .. tostring(safe(function() return driver:call("get_drawSuspend") end)))
        write_back(cmd, "ok=" .. tostring(ok) .. " result=" .. tostring(r))
    elseif cmd:sub(1, 10) == "settextat " then
        -- "settextat <item name>|<control name>|<text>" : the text control under one named item only (si_list1 ...)
        local item, cname, text = cmd:sub(11):match("^(.-)|(.-)|(.*)$")
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        local go = driver and safe(function() return driver:call("get_GameObject") end)
        local gui = go and safe(function() return go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI")) end)
        local view = gui and safe(function() return gui:call("get_View") end)
        if view == nil or item == nil then L("settextat: no view, or bad form"); write_back(cmd, "no view"); return end
        local hits = 0
        local function visit(ctrl, depth, inside)
            if ctrl == nil or depth > MAX_DEPTH then return end
            local name = safe(function() return ctrl:call("get_Name") end)
            local here = inside or (name == item)
            if here and name == cname and type_name(ctrl):find("Text") then
                local ok = pcall(function() ctrl:call("set_Message", text) end)
                hits = hits + 1
                L(string.format("settextat %s/%s #%d ok=%s", item, cname, hits, tostring(ok)))
            end
            local child = safe(function() return ctrl:call("get_Child") end)
            while child ~= nil do
                visit(child, depth + 1, here)
                child = safe(function() return child:call("get_Next") end)
            end
        end
        visit(view, 0, false)
        write_back(cmd, hits .. " set")
    elseif cmd == "handles2" or cmd:sub(1, 5) == "pick " then
        -- every handle the manager holds (guiHandles): index, alias, driver type, object name; "pick <n>" makes one current
        local gm = sdk.get_managed_singleton("app.GUIManager")
        local list = gm and safe(function() return gm:get_field("<guiHandles>k__BackingField") end)
        local items = list and safe(function() return list:get_field("_items") end)
        local n = list and safe(function() return list:get_field("_size") end) or 0
        if items == nil then L("no guiHandles"); write_back(cmd, "no list"); return end
        local want = tonumber(cmd:sub(6) or "")
        for i = 0, n - 1 do
            local h = safe(function() return items:get_element(i) end)
            if h ~= nil then
                local d = safe(function() return h:get_field("<driver>k__BackingField") end)
                local go = d and safe(function() return d:call("get_GameObject") end)
                local nm = go and safe(function() return go:call("get_Name") end) or "?"
                if want == nil then
                    L(string.format("  [%d] alias=%s driver=%s object='%s' valid=%s", i,
                                    tostring(safe(function() return h:get_field("<aliasHash>k__BackingField") end)),
                                    d and type_name(d) or "nil", tostring(nm), tostring(safe(function() return h:call("isValid") end))))
                elseif want == i then
                    shop_handle = h
                    L(string.format("picked [%d] %s '%s'", i, d and type_name(d) or "nil", tostring(nm)))
                end
            end
        end
        write_back(cmd, want and ("picked " .. want) or (n .. " handle(s) listed"))
    elseif cmd:sub(1, 6) == "dcall " then
        -- "dcall <method>" : a 0-argument method on the current handle's driver (requestDestroy, onFinishedHide, ...)
        local method = cmd:sub(7)
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver == nil then L("no handle"); write_back(cmd, "no handle"); return end
        local ok, r = pcall(function() return driver:call(method) end)
        L("driver." .. method .. "() -> ok=" .. tostring(ok) .. " result=" .. tostring(r))
        write_back(cmd, "ok=" .. tostring(ok))
    elseif cmd == "hooks" then
        -- log every call of the shop screens' own methods (once each 0.25 s per method), to see what keys drive;
        -- with block_decide on, GUIShopMenu.openMenu is skipped (so F / A on a card opens nothing)
        if hooks_on then write_back(cmd, "already on"); return end
        hooks_on = true
        local plan = {
            ["app.GUIShopMenu"] = { "openMenu", "simpleListSelectionChanged", "mainStateFinished", "onCloseDialog",
                                    "onHide", "onShow", "onFinishedHide", "applyToGuide", "setupSimpleList" },
            ["app.GUIShop"] = { "openShop", "onHide", "onShow", "onFinishedHide" },
            ["app.GUIDriver"] = { "suicide", "hide", "show", "enterExclusive", "leaveExclusive", "requestDestroy" },
            ["app.GUIManager"] = { "suicideGUIShop", "leaveShopEvent", "enterShopEvent", "enterExclusive", "leaveExclusive" },
        }
        local n = 0
        for tname, methods in pairs(plan) do
            local td = sdk.find_type_definition(tname)
            for _, mname in ipairs(methods) do
                for _, m in ipairs(td and td:get_methods() or {}) do
                    if m:get_name() == mname then
                        local label = tname .. "." .. mname
                        local ok = pcall(sdk.hook, m, function(args)
                            local now = os.clock()
                            if (hook_last[label] or 0) + 0.25 < now then
                                hook_last[label] = now
                                local this = safe(function() return sdk.to_managed_object(args[2]) end)
                                L("CALL " .. label .. (this and (" on " .. type_name(this)) or ""))
                            end
                            if block_decide and label == "app.GUIShopMenu.openMenu" then
                                L("  openMenu skipped (block_decide)")
                                return sdk.PreHookResult.SKIP_ORIGINAL
                            end
                        end, function(retval) return retval end)
                        if ok then n = n + 1 end
                    end
                end
            end
        end
        L("hooks: " .. n .. " method(s) hooked")
        write_back(cmd, n .. " hooked")
    elseif cmd == "watchshop" then
        -- a REAL Duke visit, recorded: every open* / setup* / collect* / create* call on the shop screens and the GUI
        -- manager, with its arguments (type and fields, one level deep); each screen's driver kept for "dumpdrv"
        if watch_on then write_back(cmd, "already on"); return end
        watch_on = true
        local function describe(v)
            if v == nil then return "nil" end
            local tn = type_name(v)
            local parts = {}
            local td = safe(function() return v:get_type_definition() end)
            local k = 0
            while td ~= nil and k < 3 do
                for _, f in ipairs(td:get_fields()) do
                    if not f:is_static() then
                        local fv = safe(function() return v:get_field(f:get_name()) end)
                        local shown = tostring(fv)
                        if type(fv) == "userdata" then shown = type_name(fv) end
                        parts[#parts + 1] = f:get_name():gsub("<(.-)>k__BackingField", "%1") .. "=" .. shown
                    end
                end
                td = safe(function() return td:get_parent_type() end)
                k = k + 1
                if td and (td:get_full_name() == "System.Object" or td:get_full_name() == "via.Behavior") then break end
            end
            return tn .. " {" .. table.concat(parts, ", ") .. "}"
        end
        local wanted = { "app.GUIShop", "app.GUIShopMenu", "app.GUIShopBuy", "app.GUIShopCustomize", "app.GUIShopSell",
                         "app.GUIShopRecipe", "app.GUIShopBg", "app.GUIManager" }
        local n = 0
        for _, tname in ipairs(wanted) do
            local td = sdk.find_type_definition(tname)
            for _, m in ipairs(td and td:get_methods() or {}) do
                local mname = m:get_name()
                if mname:match("^open") or mname:match("^setup") or mname:match("^collect") or
                   (tname == "app.GUIManager" and (mname:match("^create") or mname:match("Shop"))) then
                    local label = tname .. "." .. mname
                    local np = safe(function() return m:get_num_params() end) or 0
                    local ok = pcall(sdk.hook, m, function(args)
                        local this = safe(function() return sdk.to_managed_object(args[2]) end)
                        if this and tname ~= "app.GUIManager" then live_drivers[tname] = this end
                        local shown = {}
                        for i = 1, math.min(np, 4) do
                            local raw = args[2 + i]
                            local obj = safe(function() return sdk.to_managed_object(raw) end)
                            if obj ~= nil then shown[#shown + 1] = describe(obj)
                            else shown[#shown + 1] = tostring(safe(function() return sdk.to_int64(raw) end)) end
                        end
                        L("WATCH " .. label .. "(" .. table.concat(shown, " | ") .. ")")
                    end, function(retval) return retval end)
                    if ok then n = n + 1 end
                end
            end
        end
        L("watchshop: " .. n .. " method(s) watched; talk to the Duke now")
        write_back(cmd, n .. " watched")
    elseif cmd:sub(1, 8) == "dumpdrv " then
        -- "dumpdrv <type>" : the live driver of that screen (kept by watchshop): its fields, and the first rows of its lists
        local d = live_drivers[cmd:sub(9)]
        if d == nil then L("no live driver for " .. cmd:sub(9)); write_back(cmd, "none"); return end
        local td = d:get_type_definition()
        for _, f in ipairs(td:get_fields()) do
            if not f:is_static() then
                local v = safe(function() return d:get_field(f:get_name()) end)
                local line = f:get_name() .. " = " .. tostring(v)
                if type(v) == "userdata" then
                    local vt = type_name(v)
                    line = line .. " (" .. vt .. ")"
                    if vt:find("List`1") then
                        local size = safe(function() return v:call("get_Count") end) or 0
                        line = line .. " count=" .. tostring(size)
                        local items = safe(function() return v:get_field("_items") end)
                        for i = 0, math.min(size, 3) - 1 do
                            local it = (items and safe(function() return items:get_element(i) end))
                                       or safe(function() return v:call("get_Item", i) end)
                            if it ~= nil and type(it) == "userdata" then
                                local parts = {}
                                local itd = safe(function() return it:get_type_definition() end)
                                for _, ff in ipairs(itd and itd:get_fields() or {}) do
                                    if not ff:is_static() then
                                        local fv = safe(function() return it:get_field(ff:get_name()) end)
                                        parts[#parts + 1] = ff:get_name() .. "=" .. (type(fv) == "userdata" and type_name(fv) or tostring(fv))
                                    end
                                end
                                line = line .. "\n      [" .. i .. "] " .. type_name(it) .. " {" .. table.concat(parts, ", ") .. "}"
                            else
                                line = line .. "\n      [" .. i .. "] " .. tostring(it)
                            end
                        end
                    end
                end
                L("  " .. line)
            end
        end
        write_back(cmd, "see the log")
    elseif cmd == "block on" or cmd == "block off" then
        block_decide = cmd == "block on"
        L("block_decide = " .. tostring(block_decide))
        write_back(cmd, "block_decide=" .. tostring(block_decide))
    elseif cmd == "selected" then
        -- which card the shop menu has selected now
        local driver = shop_handle and safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        local list = driver and safe(function() return driver:get_field("<simpleList>k__BackingField") end)
        local sel = list and (safe(function() return list:call("get_SelectedIndex") end) or safe(function() return list:call("get_selectedIndex") end))
        L("selected: simpleList=" .. tostring(list) .. " index=" .. tostring(sel) .. " lastIndex="
          .. tostring(driver and safe(function() return driver:get_field("<lastIndex>k__BackingField") end)))
        write_back(cmd, "index=" .. tostring(sel))
    elseif cmd == "handles" then
        -- what the shop handle points at: the GUIHandle's own methods, and the object it wraps
        list_methods("app.GUIHandle")
        write_back(cmd, "see the log")
    elseif cmd == "inspect" then
        -- the shop GUI object behind the handle from "open", drawn or not: is it there, enabled, drawing; its tree
        if shop_handle == nil then L("no shop handle: run open first"); write_back(cmd, "no handle"); return end
        local tn = type_name(shop_handle)
        L("shop handle type: " .. tn)
        list_methods(tn)
        local go = nil
        for _, getter in ipairs({ "get_GameObject", "get_Object", "get_gameObject", "get_GUI", "get_Target" }) do
            local v = safe(function() return shop_handle:call(getter) end)
            if v ~= nil then
                L(getter .. "() -> " .. tostring(v) .. " (" .. type_name(v) .. ")")
                if go == nil and type_name(v) == "via.GameObject" then go = v end
            end
        end
        for _, f in ipairs(sdk.find_type_definition(tn):get_fields()) do
            local v = safe(function() return shop_handle:get_field(f:get_name()) end)
            L("field " .. f:get_name() .. " = " .. tostring(v) .. (v ~= nil and type(v) == "userdata" and (" (" .. type_name(v) .. ")") or ""))
            if go == nil and v ~= nil and type(v) == "userdata" and type_name(v) == "via.GameObject" then go = v end
        end
        -- the driver (app.GUIShopBuy, 2026-11-04) is a component: its own and inherited methods, and its game object
        local driver = safe(function() return shop_handle:get_field("<driver>k__BackingField") end)
        if driver ~= nil then
            local dtn = type_name(driver)
            L("driver type: " .. dtn)
            local td = sdk.find_type_definition(dtn)
            local depth = 0
            while td ~= nil and depth < 6 do
                list_methods(td:get_full_name())
                td = safe(function() return td:get_parent_type() end)
                depth = depth + 1
                if td ~= nil and (td:get_full_name() == "via.Behavior" or td:get_full_name() == "via.Component"
                                  or td:get_full_name() == "System.Object") then break end
            end
            if go == nil then go = safe(function() return driver:call("get_GameObject") end) end
            -- the driver's own field values (handles to child screens, modes, panels)
            local dtd = sdk.find_type_definition(dtn)
            for _, f in ipairs(dtd:get_fields()) do
                local v = safe(function() return driver:get_field(f:get_name()) end)
                local shown = tostring(v)
                if v ~= nil and type(v) == "userdata" then
                    local vt = type_name(v)
                    shown = shown .. " (" .. vt .. ")"
                    if vt == "app.GUIHandle" then
                        local d2 = safe(function() return v:get_field("<driver>k__BackingField") end)
                        local go2 = d2 and safe(function() return d2:call("get_GameObject") end)
                        shown = shown .. " -> driver " .. (d2 and type_name(d2) or "nil") .. " object '"
                                .. tostring(go2 and safe(function() return go2:call("get_Name") end) or "?") .. "'"
                    end
                end
                L("driver field " .. f:get_name() .. " = " .. shown)
            end
            L("driver step=" .. tostring(safe(function() return driver:call("get_step") end))
              .. " drawSelf=" .. tostring(safe(function() return driver:call("get_isDrawSelf") end))
              .. " updateSelf=" .. tostring(safe(function() return driver:call("get_isUpdateSelf") end))
              .. " drawSuspend=" .. tostring(safe(function() return driver:call("get_drawSuspend") end)))
        end
        if go ~= nil then
            local name = safe(function() return go:call("get_Name") end) or "?"
            L("game object '" .. tostring(name) .. "' draw=" .. tostring(safe(function() return go:call("get_Draw") end))
              .. " drawSelf=" .. tostring(safe(function() return go:call("get_DrawSelf") end))
              .. " update=" .. tostring(safe(function() return go:call("get_UpdateSelf") end)))
            dump_game_object(go, tostring(name))
            write_back(cmd, "dumped " .. tostring(name))
        else
            write_back(cmd, "no game object found behind the handle; see the log for its type")
        end
    else
        write_back(cmd, "unknown command")
    end
end

alias_queue = nil

re.on_frame(function()
    frames = frames + 1
    if alias_queue and #alias_queue > 0 then
        local gm = sdk.get_managed_singleton("app.GUIManager")
        for _ = 1, 10 do
            local name = table.remove(alias_queue, 1)
            if name == nil then break end
            local h = murmur3_utf16(name)
            local ok, r = pcall(function() return gm:call("createGUI(System.UInt32, System.Boolean)", h, true) end)
            if ok and r ~= nil then
                local driver = safe(function() return r:get_field("<driver>k__BackingField") end)
                L(string.format("ALIAS HIT '%s' = %u -> driver %s", name, h, driver and type_name(driver) or "nil"))
            end
        end
        if #alias_queue == 0 then L("aliasscan done") end
    end
    if frames % CHECK_EVERY_FRAMES ~= 0 then return end
    local ok, data = pcall(json.load_file, CMD_FILE)
    if not ok or type(data) ~= "table" or type(data.cmd) ~= "string" then return end
    if data.cmd:sub(1, 5) == "done:" then return end
    local ok2, err = pcall(run, data.cmd)
    if not ok2 then L("command failed: " .. tostring(err)); write_back(data.cmd, "failed: " .. tostring(err)) end
end)

L("shop probe loaded; write " .. CMD_FILE)
