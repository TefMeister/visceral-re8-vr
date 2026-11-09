local gm = S("app.GUIManager")
local out = {}
local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local comps = scene:call("findComponents(System.Type)", sdk.typeof("via.gui.GUI"))
E.gui = {}
for i = 0, comps:call("get_Count") - 1 do
  local g = comps:call("get_Item", i)
  local go = g:call("get_GameObject")
  local name = go:call("get_Name")
  local draw = go:call("get_DrawSelf")
  local en = g:call("get_Enabled")
  if string.find(name, "Shop") or string.find(name, "Bg") or string.find(name, "Fade") or string.find(name, "Black") or string.find(name, "Money") then
    out[#out+1] = name .. " draw=" .. tostring(draw) .. " enabled=" .. tostring(en)
    E.gui[name] = go
  end
end
return table.concat(out, "\n")
