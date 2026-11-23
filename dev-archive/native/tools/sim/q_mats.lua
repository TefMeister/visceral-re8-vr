-- q_mats.lua: TEST ONLY. Lists the player's mesh materials (rv.py -f). E.hide = { [name]=true } hides those; see q_sleeve.lua.
local out = {}
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local arr = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()
local go = arr[1]:call("get_GameObject")
local function walk(tf, depth)
  local g = tf:call("get_GameObject")
  local m = g:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
  if m then
    local n = m:call("get_MaterialNum")
    local names = {}
    for i = 0, n - 1 do names[#names+1] = i .. ":" .. tostring(m:call("getMaterialName", i)) .. (m:call("getMaterialsEnable", i) and "" or "(off)") end
    out[#out+1] = string.rep(" ", depth) .. g:call("get_Name") .. " [" .. table.concat(names, " ") .. "]"
  end
  local c = tf:call("get_Child")
  while c and depth < 3 do walk(c, depth + 1); c = c:call("get_Next") end
end
walk(go:call("get_Transform"), 0)
return table.concat(out, "\n")
