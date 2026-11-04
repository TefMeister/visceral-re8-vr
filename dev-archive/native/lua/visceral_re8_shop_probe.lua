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

re.on_frame(function()
    frames = frames + 1
    if frames % CHECK_EVERY_FRAMES ~= 0 then return end
    local ok, data = pcall(json.load_file, CMD_FILE)
    if not ok or type(data) ~= "table" or type(data.cmd) ~= "string" then return end
    if data.cmd:sub(1, 5) == "done:" then return end
    local ok2, err = pcall(run, data.cmd)
    if not ok2 then L("command failed: " .. tostring(err)); write_back(data.cmd, "failed: " .. tostring(err)) end
end)

L("shop probe loaded; write " .. CMD_FILE)
