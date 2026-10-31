-- visceral_re8_quickslot_probe.lua -- PROBE, not for players (2026-10-31). Question: which game method takes a gun out of a
-- quick slot when the D-pad is used? The holster spots ask PlayerWeaponChange.set_RequestedItem and the game ignores it
-- (log 2026-10-31 11:09, five grabs, no gun). This lists every app.* method whose name has "quick" in it (outside the GUI),
-- hooks each with a log-only pre-hook, and logs the first 3 calls of each. Tefa takes a gun out with the D-pad once; the
-- method that fires is the one the holsters should call. Archive this file once answered.

local TAG = "[quickslot-probe]"
local MAX_HOOKS = 60
local function L(s) log.info(TAG .. " " .. s) end

local tdb = sdk.get_tdb and sdk.get_tdb() or nil
if tdb == nil then L("no sdk.get_tdb(): cannot list types"); return end

local found, hooked = {}, 0
local ok, err = pcall(function()
    local n = tdb:get_num_types()
    for i = 0, n - 1 do
        local td = tdb:get_type(i)
        local tn = td and td:get_full_name() or ""
        if tn:sub(1, 4) == "app." and not tn:find("GUI", 1, true) then
            for _, m in ipairs(td:get_methods() or {}) do
                local mn = m:get_name() or ""
                if mn:lower():find("quick", 1, true) then
                    local ps = {}
                    for _, p in ipairs(m:get_param_types() or {}) do ps[#ps + 1] = p:get_full_name() end
                    local sig = tn .. "." .. mn .. "(" .. table.concat(ps, ", ") .. ")"
                    found[#found + 1] = sig
                    if hooked < MAX_HOOKS and not mn:find("^get_") and not mn:find("^is") then
                        local calls = 0
                        local hok = pcall(function()
                            sdk.hook(m, function(args)
                                calls = calls + 1
                                if calls <= 3 then L("CALLED " .. sig .. " #" .. calls) end
                            end, function(r) return r end)
                        end)
                        if hok then hooked = hooked + 1 end
                    end
                end
            end
        end
    end
end)
if not ok then L("listing stopped: " .. tostring(err)) end
table.sort(found)
L(string.format("%d quick methods found, %d hooked (log-only)", #found, hooked))
for _, s in ipairs(found) do L("  " .. s) end
