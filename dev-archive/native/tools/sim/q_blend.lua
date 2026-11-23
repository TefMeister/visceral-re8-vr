-- q_blend.lua: TEST ONLY, READ ONLY (2026-11-23). How a pose change of the LEFT hand plays out frame by frame (Tefa: "animations
-- blend from one to another"). While E.blend_rec is true, every frame (EndRendering, after every writer) records the left spot
-- and LT (bridge slots 153 and 3: stage = spot * 10 + LT), the pull (279) and the distance (cm) from the left wrist to the thumb's, index's and middle finger's last
-- joints. A blend shows as a run of small steps over Hand Poser's POSE_BLEND_SEC (0.15 s); a jump as one frame carrying most of it.
-- blend_probe.py sets E.blend = {} and E.blend_rec2; every call returns the record as "t spot pull thumb index middle" lines.
if not E.blend_on2 then
  E.blend_on2 = true; E.blend = {}
  re.on_application_entry("EndRendering", function()
    if not E.blend_rec2 then return end
    pcall(function()
      local b = _G.visceral_re8_bridge
      local sm = sdk.get_native_singleton("via.SceneManager")
      local sc = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
      local ptf = sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")):get_elements()[1]:call("get_GameObject"):call("get_Transform")
      local h = ptf:call("getJointByName", "L_Hand"):call("get_Position")
      local function d(j) return (ptf:call("getJointByName", j):call("get_Position") - h):length() * 100 end
      -- stage = spot * 10 + LT held (slot 3): LT changes the pose on a docked part with the spot unchanged ("ready on" -> its own)
      local st = (b and b.r(153) or -1) * 10 + ((b and (b.r(3) or 0) > 0.5) and 1 or 0)
      local e = { os.clock(), st, b and b.r(279) or -1, d("L_Thumb3"), d("L_IndexF3"), d("L_MiddleF3") }
      local l = E.blend[#E.blend]
      -- only frames where something changed (two EndRenderings a frame on Two Frame Sequential, and long still stretches)
      if l and l[2] == e[2] and math.abs(l[4] - e[4]) + math.abs(l[5] - e[5]) + math.abs(l[6] - e[6]) < 0.02 then return end
      E.blend[#E.blend + 1] = e
    end)
  end)
end
local o = {}
local t0 = E.blend[1] and E.blend[1][1] or 0
for _, e in ipairs(E.blend) do o[#o + 1] = string.format("%.4f %d %.3f %.2f %.2f %.2f", e[1] - t0, e[2], e[3], e[4], e[5], e[6]) end
return table.concat(o, "\n")
