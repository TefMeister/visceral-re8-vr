-- visceral_re8_hud.lua -- the quick-slot cross drawn as four diagonal points, labelled with the holster spots (Tefa idea 15,
-- 2026-10-24: "change the actual game hud to show 4 diagonal points - LEFT SHOULDER, RIGHT SHOULDER, LEFT HIP, RIGHT HIP").
-- The game's cross (app.GUIQuickEquip, panel c_layout) holds four slot panels c_top / c_right / c_bottom / c_left, 115 units
-- from its centre, and four key texts m_key_T / R / B / L (button icons, hidden on a pad) [measured 2026-10-24, the HUD
-- probe]. Every frame the cross updates, the slots are moved onto the diagonals (the cross turned 45 degrees clockwise,
-- as the holster spots and the thumb-rest D-pad: up = right shoulder, right = right hip, down = left hip, left = left
-- shoulder) and the key texts become the spot names, shown beside their slot.

local TAG = "[visceral-re8-hud]"
local ON = true
local R = 92.0          -- the slots' distance from the centre along each axis (115 on the straight cross; 92 = about 130 on the diagonal)
local LABEL_DY = 72.0   -- a label sits this far above an upper slot, below a lower one

local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end

-- slot panel, key text, the diagonal it moves to (x right, y down, as the GUI counts), the label
local LAYOUT = {
    { panel = "c_top",    key = "m_key_T", x =  R, y = -R, label = "RIGHT SHOULDER" },
    { panel = "c_right",  key = "m_key_R", x =  R, y =  R, label = "RIGHT HIP" },
    { panel = "c_bottom", key = "m_key_B", x = -R, y =  R, label = "LEFT HIP" },
    { panel = "c_left",   key = "m_key_L", x = -R, y = -R, label = "LEFT SHOULDER" },
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
local function apply(this)
    local layout = safe(function() return this:call("get_layoutPanel") end)
    if layout == nil or safe(function() return layout:call("get_Name") end) ~= "c_layout" then
        local main = safe(function() return this:call("get_mainPanel") end)
        local mode = main and child(main, "c_mode")
        layout = mode and child(mode, "c_layout") or layout
    end
    if layout == nil then return end
    local done = 0
    for _, s in ipairs(LAYOUT) do
        local p = child(layout, s.panel)
        if p then pcall(function() p:call("set_Position", Vector3f.new(s.x, s.y, 0.0)) end); done = done + 1 end
        local t = child(layout, s.key)
        if t then
            pcall(function()
                t:call("set_Message", s.label)
                t:call("set_Position", Vector3f.new(s.x, s.y + (s.y < 0 and -LABEL_DY or LABEL_DY), 0.0))
                t:call("set_Visible", true)
            end)
        end
    end
    if not told then told = true; L(string.format("cross redrawn on the diagonals (%d of 4 slot panels found)", done)) end
end

local td = sdk.find_type_definition("app.GUIQuickEquip")
local m = td and td:get_method("onLateUpdate")
if ON and m then
    -- the post hook has no 'this'; keep it from the pre hook
    local last = nil
    sdk.hook(m, function(args) last = sdk.to_managed_object(args[2]) end, function(r) if last then pcall(apply, last) end return r end)
    L("hooked app.GUIQuickEquip.onLateUpdate")
elseif ON then
    L("app.GUIQuickEquip.onLateUpdate NOT FOUND: the cross stays as the game draws it")
end
