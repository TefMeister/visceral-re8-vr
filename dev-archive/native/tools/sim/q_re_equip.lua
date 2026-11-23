-- q_re_equip.lua: TEST ONLY (2026-11-23), RE2 / RE3: put the owned main weapon of WeaponType E.want in the hand
-- (rv.py "E.want=1 return 1", then rv.py -f q_re_equip.lua). E.want = nil lists the slots. E.fill = true also fills its magazine.
local im = sdk.get_managed_singleton(sdk.game_namespace("gamemastering.InventoryManager"))
local inv = im:get_field("<CurrentInventory>k__BackingField"); local slots = inv:get_field("_Slots")
local out = {}
for i = 0, slots:call("get_Count") - 1 do
  local s = slots:call("get_Item", i); local wt = s:call("get_WeaponType")
  if wt and wt > 0 then
    out[#out+1] = string.format("slot %d type %d rounds %s", i, wt, tostring(s:call("get_Number")))
    if E.want == wt then
      local ms = {}
      for _, m in ipairs(inv:get_type_definition():get_methods()) do if m:get_name():lower():find("equip") then ms[#ms+1] = m:get_name() end end
      -- (equipSlot(Int32) is accepted and does nothing; this one swaps the gun in the hand, about 3 s later, the window in front)
      local ok, err = pcall(function() inv:call("equipMainSlot(" .. sdk.game_namespace("inventory.Slot") .. ")", s) end)
      if E.fill then pcall(function() s:call("set_Number", E.fill) end) end
      return "slot " .. i .. " type " .. wt .. (ok and " equipped" or (" NOT equipped: " .. tostring(err) .. " | inventory methods: " .. table.concat(ms, " ")))
    end
  end
end
return (E.want and ("type " .. tostring(E.want) .. " not owned; ") or "") .. table.concat(out, "; ")
