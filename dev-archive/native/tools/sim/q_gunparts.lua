-- q_gunparts.lua -- a live question (rv.py -f, RE2 / RE3 with RV_GAME_DIR): what does the gun in hand offer for showing or
-- hiding the rounds in its magazine? Its joints (name, parent, local position), how many mesh part switches are off, its
-- materials, and every field of the gun whose name speaks of parts, magazines, bullets or vanishing (2026-11-11).
-- E.gp_mode = "joints" | "parts" | "mats" | "fields" picks one list (the default is a short summary of all four).
local function first(...) for _, n in ipairs({...}) do local s = sdk.get_managed_singleton(n); if s then return s, n end end end
local pm, pmn = first("app.ropeway.PlayerManager", "offline.PlayerManager")
if not pm then return "no PlayerManager" end
local ns = pmn:gsub("PlayerManager$", "")
local pl = pm:call("get_CurrentPlayer"); if not pl then return "no player" end
local eq = pl:call("getComponent(System.Type)", sdk.typeof(ns .. "survivor.Equipment"))
local gun = eq and eq:get_field("<EquipWeapon>k__BackingField"); if not gun then return "no gun in hand" end
local go = gun:call("get_GameObject"); local tf = go:call("get_Transform")
local mesh = go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
E.gp_gun, E.gp_tf, E.gp_mesh = gun, tf, mesh
local mode, o = E.gp_mode or "all", {}
o[#o + 1] = go:call("get_Name") .. " <" .. gun:get_type_definition():get_full_name() .. "> loaded " .. tostring(gun:call("getBulletNumber"))
if mode == "all" or mode == "joints" then
  local js = tf:call("get_Joints"); local n = js:get_size()
  o[#o + 1] = n .. " joints:"
  for i = 0, n - 1 do
    local j = js:get_element(i); local p = j:call("get_Parent"); local lp = j:call("get_LocalPosition"); local s = j:call("get_LocalScale")
    o[#o + 1] = string.format("  %s < %s  p %.3f %.3f %.3f  s %.2f", j:call("get_Name"), p and p:call("get_Name") or "-", lp.x, lp.y, lp.z, s.x)
  end
end
if (mode == "all" or mode == "parts") and mesh then
  local off = {}
  for i = 0, 255 do local ok, on = pcall(function() return mesh:call("getPartsEnable", i) end); if ok and on == false then off[#off + 1] = i end end
  o[#o + 1] = "mesh parts switched OFF: [" .. table.concat(off, " ") .. "]"
end
if (mode == "all" or mode == "mats") and mesh then
  local n = mesh:call("get_MaterialNum"); local m = {}
  for i = 0, n - 1 do m[#m + 1] = i .. ":" .. tostring(mesh:call("getMaterialName", i)) .. (mesh:call("getMaterialsEnable", i) and "" or "(off)") end
  o[#o + 1] = "materials: " .. table.concat(m, "  ")
end
if mode == "all" or mode == "fields" then
  local td = gun:get_type_definition()
  while td and td:get_full_name() ~= "via.Behavior" and td:get_full_name() ~= "System.Object" do
    for _, f in ipairs(td:get_fields()) do
      local nm = f:get_name(); local l = nm:lower()
      if mode == "fields" or l:find("part") or l:find("magaz") or l:find("bullet") or l:find("vanish") or l:find("disp") or l:find("cartridge") or l:find("empty") then
        local ok, v = pcall(function() return gun:get_field(nm) end)
        o[#o + 1] = "  " .. td:get_name() .. "." .. nm .. " = " .. (ok and show(v, 1) or "?")
      end
    end
    td = td:get_parent_type()
  end
end
return table.concat(o, "\n")
