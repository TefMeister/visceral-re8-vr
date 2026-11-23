local out = {}
local im = sdk.get_managed_singleton("app.InventoryManager")
local inv = im:call("get_activeInventory")
local arr = inv:get_field("<items>k__BackingField"):call("ToArray"):get_elements()
for _, it in ipairs(arr) do
  local w = it:call("get_work"); local id = w and w:call("get_itemID")
  if id == 2576167331 then
    for _, m in ipairs(it:get_type_definition():get_methods()) do
      local n = m:get_name()
      if n == "getBulletItemID" or n == "getBulletNum" or n == "getBulletItemIDImple" then
        local ps = {}; for _, p in ipairs(m:get_param_types()) do ps[#ps+1] = p:get_full_name() end
        out[#out+1] = n .. "(" .. table.concat(ps, ", ") .. ")"
      end
    end
    for i = 0, 2 do
      local ok, v = pcall(function() return it:call("getBulletItemID(System.Int32)", i) end); out[#out+1] = "idx " .. i .. " -> " .. tostring(v)
    end
    local ok, v = pcall(function() return it:call("getBulletItemID()") end); out[#out+1] = "now -> " .. tostring(v)
    out[#out+1] = "usable " .. tostring(it:call("get_usableBulletNum")) .. " using idx " .. tostring(it:call("get_usingBulletIndex"))
  end
end
return table.concat(out, "\n")
