-- visceral_re8_hud.lua -- the quick-slot cross drawn as four diagonal points, labelled with the holster spots (Tefa idea 15,
-- 2026-10-24: "change the actual game hud to show 4 diagonal points - LEFT SHOULDER, RIGHT SHOULDER, LEFT HIP, RIGHT HIP").
-- The game's cross (app.GUIQuickEquip, panel c_layout) holds four slot panels c_top / c_right / c_bottom / c_left, 115 units
-- from its centre, and four key texts m_key_T / R / B / L (button icons, hidden on a pad) [measured 2026-10-24, the HUD
-- probe]. Every frame the cross updates, the slots are moved onto the diagonals (the cross turned 45 degrees clockwise,
-- as the holster spots and the thumb-rest D-pad: up = right shoulder, right = right hip, down = left hip, left = left
-- shoulder) and the key texts become the spot names, shown beside their slot.
-- 2026-10-24 later (Tefa): the cross sits in the middle of the view.
-- 2026-10-25 (Tefa: "the d-pad menu doesn't appear when i put my thumb on the thumb rest ... all 4 options are visible, but
-- their boxes are small like squares ... after that, d-pad menu doesn't show at all"): the first version called the cross's
-- onShow / onHide itself and refused the game's onHide while the thumb rested, which left the game's own open / close state
-- wrong, and it set the slot panels' scale every frame against the game's own slot animation (the squares). Now: nothing is
-- called or refused on the cross, and the slots keep the game's own scale. The game opens the cross through
-- openQuickEquip(GUIRequestOpenQuickEquipParameter) (re8.exe names); its owner and the parameter's fields are listed in the
-- log the first time the cross is seen, so the thumb-rest door can be wired from the next run.
-- 2026-10-25 (Tefa: "the boxes have to be closer together ... it's more distracting to look in each corner separately. also
-- the text saying LEFT HIP and so on is different size and mostly too small to comfortably read in VR"): the slots sit
-- closer in, and every label gets the same font size (set on the text itself, not a scale of its own size) and no scale.

local TAG = "[visceral-re8-hud]"
local ON = true
local CENTER_X, CENTER_Y = 960.0, 540.0   -- the cross's centre: the middle of the game's 1920 x 1080 GUI
local RX, RY = 300.0, 170.0               -- the slots' distance from the centre (was 560 / 300: "too far apart")
local LABEL_FONT = 44.0                   -- one font size for all four labels (GUI units; the game's HUD text is ~28)
local LABEL_DY = 90.0                     -- a label sits this far above an upper slot, below a lower one

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

-- slot panel, key text, the diagonal it moves to (x right, y down, as the GUI counts), the label
local LAYOUT = {
    { panel = "c_top",    key = "m_key_T", x =  RX, y = -RY, label = "RIGHT SHOULDER" },
    { panel = "c_right",  key = "m_key_R", x =  RX, y =  RY, label = "RIGHT HIP" },
    { panel = "c_bottom", key = "m_key_B", x = -RX, y =  RY, label = "LEFT HIP" },
    { panel = "c_left",   key = "m_key_L", x = -RX, y = -RY, label = "LEFT SHOULDER" },
}

local function child(parent, name)
    local ch = safe(function() return parent:call("get_Child") end)
    local n = 0
    while ch ~= nil and n < 64 do
        if safe(function() return ch:call("get_Name") end) == name then return ch end
        ch = safe(function() return ch:call("get_Next") end)
        n = n + 1
    end
    return nil
end

local told = false
local font_told = false
local function apply(this)
    local layout = safe(function() return this:call("get_layoutPanel") end)
    if layout == nil or safe(function() return layout:call("get_Name") end) ~= "c_layout" then
        local main = safe(function() return this:call("get_mainPanel") end)
        local mode = main and child(main, "c_mode")
        layout = mode and child(mode, "c_layout") or layout
    end
    if layout == nil then return end
    pcall(function() layout:call("set_Position", Vector3f.new(CENTER_X, CENTER_Y, 0.0)) end)
    local done = 0
    for _, s in ipairs(LAYOUT) do
        local p = child(layout, s.panel)
        if p then
            pcall(function() p:call("set_Position", Vector3f.new(s.x, s.y, 0.0)) end)
            done = done + 1
        end
        local t = child(layout, s.key)
        if t then
            pcall(function()
                t:call("set_Message", s.label)
                t:call("set_Position", Vector3f.new(s.x, s.y + (s.y < 0 and -LABEL_DY or LABEL_DY), 0.0))
                t:call("set_Scale", Vector3f.new(1.0, 1.0, 1.0))
                t:call("set_Visible", true)
            end)
            local ok = pcall(function() t:call("set_FontSize", LABEL_FONT) end)
            if not font_told then
                font_told = true
                L(ok and string.format("labels: font size %.0f set on the texts", LABEL_FONT) or "labels: the text has no set_FontSize: sizes stay the game's")
            end
        end
    end
    if not told then told = true; L(string.format("cross redrawn in the middle, slots %d / %d from it (%d of 4 slot panels found)", RX, RY, done)) end
end

-- the door for "shown while the thumb rests": list, once, every QuickEquip-named method on the cross's type, its parents,
-- app.GUIManager and the order / parameter types, with their parameter types
local listed = false
local function method_lines(tdef, filter)
    local out = {}
    local seen = {}
    local td = tdef
    while td ~= nil do
        for _, m in ipairs(td:get_methods()) do
            local n = m:get_name()
            if not seen[n] and (filter == nil or n:lower():find(filter)) then
                seen[n] = true
                local ps = {}
                for _, p in ipairs(m:get_param_types() or {}) do ps[#ps + 1] = p:get_full_name() end
                out[#out + 1] = td:get_full_name() .. "." .. n .. "(" .. table.concat(ps, ", ") .. ")"
            end
        end
        td = td:get_parent_type()
    end
    table.sort(out)
    return out
end
local function list_doors(this)
    if listed then return end
    listed = true
    local ok, err = pcall(function()
        for _, f in ipairs({ "open", "show", "request", "hide", "close" }) do
            L("cross " .. f .. ": " .. table.concat(method_lines(this:get_type_definition(), f), " | "))
        end
        for _, tn in ipairs({ "app.GUIManager", "app.GUIQuickEquipOrder", "app.GUIRequestOpenQuickEquipParameter", "app.PlayerUpdater", "app.PlayerUpdaterFPS" }) do
            local td = sdk.find_type_definition(tn)
            if td then
                L(tn .. ": " .. table.concat(method_lines(td, "quickequip"), " | "))
                if tn:find("Parameter") or tn:find("Order") then
                    local fs = {}
                    for _, fd in ipairs(td:get_fields()) do fs[#fs + 1] = fd:get_name() .. ":" .. fd:get_type():get_full_name() end
                    L(tn .. " fields: " .. table.concat(fs, ", "))
                end
            else
                L(tn .. ": type not found")
            end
        end
    end)
    if not ok then L("door listing failed: " .. tostring(err)) end
end

local td = sdk.find_type_definition("app.GUIQuickEquip")
local m = td and td:get_method("onLateUpdate")
if ON and m then
    local last = nil
    sdk.hook(m, function(args) last = sdk.to_managed_object(args[2]) end, function(r)
        if last then pcall(apply, last); list_doors(last) end
        return r
    end)
    L("hooked app.GUIQuickEquip.onLateUpdate")
elseif ON then
    L("app.GUIQuickEquip.onLateUpdate NOT FOUND: the cross stays as the game draws it")
end
