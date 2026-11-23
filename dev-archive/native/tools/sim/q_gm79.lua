local out = {}
local im = sdk.get_managed_singleton("app.InventoryManager")
local inv = im:call("get_activeInventory")
local arr = inv:get_field("<items>k__BackingField"):call("ToArray"):get_elements()
for _, it in ipairs(arr) do
  local tn = it:get_type_definition():get_full_name()
  local w = it:call("get_work"); local id = w and w:call("get_itemID")
  if id == 2576167331 then
    out[#out+1] = "GM79 core type " .. tn
    local td = it:get_type_definition()
    while td do
      for _, m in ipairs(td:get_methods()) do local n = m:get_name(); if n:lower():find("ammo") or n:lower():find("bullet") or n:lower():find("load") then out[#out+1] = "m " .. n end end
      for _, f in ipairs(td:get_fields()) do local n = f:get_name(); if n:lower():find("ammo") or n:lower():find("bullet") or n:lower():find("load") then out[#out+1] = "f " .. n end end
      td = td:get_parent_type()
    end
  elseif tn ~= "app.WeaponGunCore" then
    out[#out+1] = tn .. " " .. tostring(id) .. " x" .. tostring(w and pcall(function() return w:call("get_stackSize") end) and w:call("get_stackSize") or "?")
  end
end
return table.concat(out, "\n")
