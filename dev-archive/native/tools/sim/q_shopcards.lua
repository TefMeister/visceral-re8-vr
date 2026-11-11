-- q_shopcards.lua: which of the Duke's three cards is lit? Every panel named "cursor" under the ShopMenu screen, with
-- the names above it and whether it shows; and what the screen's own list says. (rv.py -f q_shopcards.lua, 2026-11-11)
local out = {}
local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local comps = scene:call("findComponents(System.Type)", sdk.typeof("app.GUIShopMenu"))
local n = comps and comps:get_size() or 0
out[#out + 1] = "GUIShopMenu drivers: " .. n
for i = 0, n - 1 do
    local d = comps:get_element(i)
    local list = d:get_field("<simpleList>k__BackingField")
    out[#out + 1] = "list selected: " .. tostring(list and list:call("get_SelectedIndex")) .. "  lastIndex: " .. tostring(d:get_field("<lastIndex>k__BackingField"))
    local go = d:call("get_GameObject")
    local gui = go:call("getComponent(System.Type)", sdk.typeof("via.gui.GUI"))
    local view = gui and gui:call("get_View")
    local function visit(c, depth, path)
        if c == nil or depth > 14 then return end
        local name = tostring(c:call("get_Name"))
        local p = path .. "/" .. name
        if name == "cursor" or name:match("^si_list") then
            out[#out + 1] = string.format("%s  visible=%s", p, tostring(c:call("get_Visible")))
        end
        local ch = c:call("get_Child")
        while ch ~= nil do visit(ch, depth + 1, p); ch = ch:call("get_Next") end
    end
    visit(view, 0, "")
end
return table.concat(out, "\n")
