-- visceral_re8_hud.lua -- the quick-slot cross drawn as four diagonal points, labelled with the holster spots (Tefa idea 15,
-- 2026-10-24: "change the actual game hud to show 4 diagonal points - LEFT SHOULDER, RIGHT SHOULDER, LEFT HIP, RIGHT HIP").
-- The game's cross (app.GUIQuickEquip, panel c_layout) holds four slot panels c_top / c_right / c_bottom / c_left, 115 units
-- from its centre, and four key texts m_key_T / R / B / L (button icons, hidden on a pad) [measured 2026-10-24, the HUD
-- probe]. Every frame the cross updates, the slots are moved onto the diagonals (the cross turned 45 degrees clockwise,
-- as the holster spots and the thumb-rest D-pad: up = right shoulder, right = right hip, down = left hip, left = left
-- shoulder) and the key texts become the spot names, shown beside their slot.
-- 2026-10-24 later (Tefa: "make the thumb rest actually have the d-pad options visible while the thumb is on it", "make
-- the boxes and text a bit larger and move them all to the corners of the screen respectively - not to the very end
-- corners of the screen just further apart"): the cross sits in the middle of the view, the slots far out toward the
-- corners, scaled up; and while the left thumb rests (_G.__visceral_thumbrest_dpad, from re8_vr.lua) the cross is shown
-- (onShow) and the game's hide is refused (onHide skipped) until the thumb lifts.

local TAG = "[visceral-re8-hud]"
local ON = true
local CENTER_X, CENTER_Y = 960.0, 540.0   -- the cross's centre: the middle of the game's 1920 x 1080 GUI
local RX, RY = 560.0, 300.0               -- the slots' distance from the centre (the corners are 960 / 540 away)
local SLOT_SCALE = 1.35                   -- the slot boxes, larger
local LABEL_SCALE = 1.5                   -- the spot names, larger
local LABEL_DY = 110.0                    -- a label sits this far above an upper slot, below a lower one
local SHOW_WITH_THUMB = true

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

local function scale(o, s) pcall(function() o:call("set_Scale", Vector3f.new(s, s, 1.0)) end) end

local told = false
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
            scale(p, SLOT_SCALE)
            done = done + 1
        end
        local t = child(layout, s.key)
        if t then
            pcall(function()
                t:call("set_Message", s.label)
                t:call("set_Position", Vector3f.new(s.x, s.y + (s.y < 0 and -LABEL_DY or LABEL_DY), 0.0))
                t:call("set_Visible", true)
            end)
            scale(t, LABEL_SCALE)
        end
    end
    if not told then told = true; L(string.format("cross redrawn in the middle, slots toward the corners (%d of 4 slot panels found)", done)) end
end

-- the cross itself (a GUIDriver component), kept from its own updates, else looked for in the scene
local cross = nil
local function find_cross()
    if cross ~= nil and safe(function() return cross:get_address() end) then return cross end
    local sm = sdk.get_native_singleton("via.SceneManager")
    local smt = sdk.find_type_definition("via.SceneManager")
    local scene = sm and smt and safe(function() return sdk.call_native_func(sm, smt, "get_CurrentScene") end)
    local arr = scene and safe(function() return scene:call("findComponents(System.Type)", sdk.typeof("app.GUIQuickEquip")) end)
    local els = arr and safe(function() return arr:get_elements() end)
    cross = els and els[1] or nil
    return cross
end

local thumb_was = false
local hides_refused = 0

local td = sdk.find_type_definition("app.GUIQuickEquip")
local m = td and td:get_method("onLateUpdate")
if ON and m then
    -- the post hook has no 'this'; keep it from the pre hook
    local last = nil
    sdk.hook(m, function(args) last = sdk.to_managed_object(args[2]); cross = last end, function(r) if last then pcall(apply, last) end return r end)
    L("hooked app.GUIQuickEquip.onLateUpdate")
    local hide = td:get_method("onHide")
    if SHOW_WITH_THUMB and hide then
        sdk.hook(hide, function(args)
            if rawget(_G, "__visceral_thumbrest_dpad") == true then
                hides_refused = hides_refused + 1
                if hides_refused <= 3 then L("the cross wanted to close: kept open while the thumb rests") end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(r) return r end)
    end
elseif ON then
    L("app.GUIQuickEquip.onLateUpdate NOT FOUND: the cross stays as the game draws it")
end

-- the thumb on the rest: show the cross; lifted: let it close
re.on_frame(function()
    if not ON or not SHOW_WITH_THUMB then return end
    local thumb = rawget(_G, "__visceral_thumbrest_dpad") == true
    if thumb == thumb_was then return end
    thumb_was = thumb
    local c = find_cross()
    if c == nil then L("thumb " .. (thumb and "on" or "off") .. ": the cross object is not found yet") return end
    local ok, err = pcall(function() c:call(thumb and "onShow(System.Boolean)" or "onHide(System.Boolean)", true) end)
    L(string.format("thumb %s: the cross %s (%s)", thumb and "on the rest" or "lifted", thumb and "shown" or "let close", ok and "ok" or tostring(err)))
end)
