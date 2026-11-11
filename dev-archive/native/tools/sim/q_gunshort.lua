-- q_gunshort.lua -- one line on the gun in hand: its joints and the mesh parts it really has (see q_gunparts.lua). 2026-11-11
local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager") or sdk.get_managed_singleton("offline.PlayerManager")
local ns = pm:get_type_definition():get_full_name():gsub("PlayerManager$", "")
local eq = pm:call("get_CurrentPlayer"):call("getComponent(System.Type)", sdk.typeof(ns .. "survivor.Equipment"))
local gun = eq:get_field("<EquipWeapon>k__BackingField"); if not gun then return "no gun" end
local go = gun:call("get_GameObject"); local tf = go:call("get_Transform"); local m = go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
E.gp_gun, E.gp_tf, E.gp_mesh = gun, tf, m
local js, jn, pn, mn = tf:call("get_Joints"), {}, {}, {}
for i = 0, js:get_size() - 1 do local n = js:get_element(i):call("get_Name"); if not n:find("vfx") and n ~= "root" then jn[#jn + 1] = n end end
for i = 0, m:call("getPartsEnableIndicesCount") - 1 do local p = m:call("getPartsEnableIndices", i); pn[#pn + 1] = p .. (m:call("getPartsEnable", p) and "+" or "-") end
for i = 0, m:call("get_MaterialNum") - 1 do mn[#mn + 1] = m:call("getMaterialName", i) end
return go:call("get_Name") .. " | joints " .. table.concat(jn, " ") .. " | parts " .. table.concat(pn, " ") .. " | mats " .. table.concat(mn, " ")
