-- q_sleeve.lua: TEST ONLY (2026-11-23). Switches the player's BODY mesh (jacket, sleeves) off or on, so pictures show the hands:
-- the hands are their own meshes (pl1000HandL / pl1000HandR) and stay. rv.py "E.body=false" -f q_sleeve.lua hides; E.body=true shows.
local sm = sdk.get_native_singleton("via.SceneManager")
local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
local go = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject")
local m = go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
local on = E.body == true
for i = 0, m:call("get_MaterialNum") - 1 do m:call("setMaterialsEnable", i, on) end
return "body " .. (on and "shown" or "hidden")
