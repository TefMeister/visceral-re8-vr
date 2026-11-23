-- q_re_index.lua: TEST ONLY, READ ONLY (2026-11-23), RE2 / RE3: the right index finger as drawn, read at EndRendering (after
-- every writer): its three joints' local Euler angles (degrees) and how far its last joint is from the wrist and from the
-- knuckle (cm; shorter = more bent). First call installs the reader. E.side = "l" for the left hand.
local side = E.side or "r"
if not E.idx_on then
  E.idx_on = true; E.idx = {}
  re.on_application_entry("EndRendering", function()
    pcall(function()
      local pl = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager")):call("get_CurrentPlayer")
      local tf = pl:call("get_Transform")
      for _, s in ipairs({ "l", "r" }) do
        local w = tf:call("getJointByName", s .. "_arm_wrist"):call("get_Position")
        local o = {}
        for i = 0, 2 do
          local j = tf:call("getJointByName", s .. "_hand_index_" .. i)
          local e = j:call("get_LocalEulerAngle"); o[#o + 1] = string.format("%d: %6.1f %6.1f %6.1f", i, math.deg(e.x), math.deg(e.y), math.deg(e.z))
          if i == 0 then o.k = j:call("get_Position") end
          if i == 2 then local p = j:call("get_Position"); o[#o + 1] = string.format("last joint: %.1f cm from the wrist, %.1f from the knuckle", (p - w):length() * 100, (p - o.k):length() * 100) end
        end
        o.k = nil; E.idx[s] = table.concat(o, "\n")
      end
    end)
  end)
  return "reader installed: ask again"
end
return E.idx[side] or "nothing yet"
