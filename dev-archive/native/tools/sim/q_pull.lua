-- q_pull.lua: TEST ONLY, READ ONLY (2026-11-23). Records, every frame while E.pull_rec is true, bridge slot 279 (S_MAG_PULL: 0 = no
-- magazine on the grip's line, else 1 + how far out 0..1) and slot 153 (S_LEFT_SPOT, the left hand's spot: 4 magazine, 13 magazine
-- in hand, 17 / 18 / 16 the spare stages). Written because hold_at.py's magpull<n> could not catch the "pulling" stage.
-- E.pull_rec = true starts recording (pull_probe.py clears E.pull first); every call returns the record so far as lines,
-- only the frames where something changed (with the count of frames it stayed).
if not E.pull_on then
  E.pull_on = true; E.pull = {}; E.pull_last = nil
  re.on_application_entry("EndRendering", function()
    if not E.pull_rec then return end
    local b = _G.visceral_re8_bridge
    if not b or not b.ready() then return end
    local p, s = b.r(279) or 0, b.r(153) or 0
    local key = string.format("%.2f %d", p, s)
    if key ~= E.pull_last then
      E.pull[#E.pull + 1] = { os.clock(), p, s, 1 }; E.pull_last = key
    elseif #E.pull > 0 then
      E.pull[#E.pull][4] = E.pull[#E.pull][4] + 1
    end
  end)
end
local o = {}
local t0 = E.pull[1] and E.pull[1][1] or 0
for _, e in ipairs(E.pull) do o[#o + 1] = string.format("%6.3f  pull %.2f  spot %d  (%d frames)", e[1] - t0, e[2], e[3], e[4]) end
return #o > 0 and table.concat(o, "\n") or "(nothing recorded)"
