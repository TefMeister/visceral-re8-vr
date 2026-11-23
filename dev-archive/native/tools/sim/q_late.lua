-- q_late.lua: TEST ONLY, READ ONLY (2026-11-23). How closed each hand is AS DRAWN: the distance wrist -> middle finger's last joint
-- (cm; about 11 = a fist, about 16 = flat), read at three points of the frame, the last one after every writer (EndRendering).
-- An rv.py question is answered early in the frame and can see a pose that a later writer replaces before the picture.
-- First call installs the readers; every call prints what they saw last.
if not E.late_on then
  E.late_on = true; E.late = {}
  local function rd(tag)
    local ok = pcall(function()
      local sm = sdk.get_native_singleton("via.SceneManager")
      local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
      local ptf = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject"):call("get_Transform")
      for _, s in ipairs({ "L_", "R_" }) do
        local h = ptf:call("getJointByName", s .. "Hand"):call("get_Position"); local m = ptf:call("getJointByName", s .. "MiddleF3"):call("get_Position")
        E.late[tag .. " " .. s] = (m - h):length() * 100
      end
    end)
  end
  re.on_pre_application_entry("UpdateBehavior", function() rd("1 UpdateBehavior") end)
  re.on_application_entry("PrepareRendering", function() rd("2 PrepareRendering post") end)
  re.on_application_entry("BeginRendering", function() rd("3 BeginRendering post") end)
  re.on_application_entry("EndRendering", function() rd("4 EndRendering post") end)
  return "readers installed: ask again"
end
local k = {}; for n, _ in pairs(E.late) do k[#k + 1] = n end; table.sort(k)
local o = {}; for _, n in ipairs(k) do o[#o + 1] = string.format("%-28s %5.1f", n, E.late[n]) end
return table.concat(o, "\n")
