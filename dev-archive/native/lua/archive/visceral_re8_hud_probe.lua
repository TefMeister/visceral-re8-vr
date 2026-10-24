-- visceral_re8_hud_probe.lua -- a probe (2026-10-24): the first time the quick-slot cross (app.GUIQuickEquip) updates, log
-- its panel tree (name, type, position, rotation, visibility) and its four texts, so the cross can be redrawn on the
-- diagonals with body-spot labels (Tefa idea 15). Logs once per script load; delete when the HUD work is done.

local TAG = "[visceral-re8-hud-probe]"
local function safe(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function L(s) log.info(TAG .. " " .. s) end
local MAX_NODES = 200

local function v3(v) return v and string.format("%.1f %.1f %.1f", v.x or 0, v.y or 0, v.z or 0) or "?" end

local function walk(node, depth, count)
    if node == nil or count[1] > MAX_NODES then return end
    count[1] = count[1] + 1
    local name = tostring(safe(function() return node:call("get_Name") end) or "?")
    local tn = tostring(safe(function() return node:get_type_definition():get_full_name() end) or "?")
    local pos = safe(function() return node:call("get_Position") end)
    local rot = safe(function() return node:call("get_Rotation") end)
    local vis = safe(function() return node:call("get_Visible") end)
    local msg = tn == "via.gui.Text" and tostring(safe(function() return node:call("get_Message") end) or "") or ""
    L(string.format("%s%s [%s] pos %s rot %s vis %s %s", string.rep("  ", depth), name, tn, v3(pos), v3(rot), tostring(vis), msg))
    local ch = safe(function() return node:call("get_Child") end)
    while ch ~= nil and count[1] <= MAX_NODES do
        walk(ch, depth + 1, count)
        ch = safe(function() return ch:call("get_Next") end)
    end
end

local done = false
local td = sdk.find_type_definition("app.GUIQuickEquip")
local m = td and td:get_method("onLateUpdate")
if m then
    sdk.hook(m, function(args)
        if done then return end
        local this = sdk.to_managed_object(args[2])
        if this == nil then return end
        done = true
        for _, f in ipairs({ "mainPanel", "modePanel", "layoutPanel" }) do
            local p = safe(function() return this:call("get_" .. f) end)
            L(string.format("== %s: %s", f, p and "found" or "nil"))
        end
        local main = safe(function() return this:call("get_mainPanel") end)
        local root = main
        for _ = 1, 6 do
            local up = root and safe(function() return root:call("get_Parent") end)
            if up == nil then break end
            root = up
        end
        L("== the tree from the top of mainPanel's parents")
        walk(root, 0, { 0 })
        for _, f in ipairs({ "upText", "rightText", "bottomText", "leftText" }) do
            local t = safe(function() return this:call("get_" .. f) end)
            local par = t and safe(function() return t:call("get_Parent") end)
            L(string.format("== %s: '%s' pos %s, parent %s", f, tostring(t and safe(function() return t:call("get_Message") end)),
                v3(t and safe(function() return t:call("get_Position") end)), tostring(par and safe(function() return par:call("get_Name") end))))
        end
    end, function(r) return r end)
    L("hooked app.GUIQuickEquip.onLateUpdate (logs the cross's layout once)")
else
    L("app.GUIQuickEquip.onLateUpdate NOT FOUND")
end
