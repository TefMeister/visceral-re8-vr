-- zz_test_short2.lua -- TEST ONLY (RE2, 2026-11-01): lets a test session look at and call the player's Inventory component, to
-- put a gun in hand without the game's menus. Requests in reframework/data/zz_short.json:
--   {"list": "<word>"}                    log the Inventory component's methods whose names contain <word>
--   {"call": "<method signature>", "args": [ints]}   call it on the Inventory component and log the result
local F = "zz_short.json"
local function inv()
    local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
    local go = pm and pm:call("get_CurrentPlayer")
    return go and go:call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.Inventory"))
end
re.on_frame(function()
    local r = json.load_file(F); if not r or (not r.list and not r.call and not r.gift and not r.joints) then return end
    json.dump_file(F, {})
    local ok, err = pcall(function()
        if r.gift then   -- {"gift": "wp4100", "count": n}: gives that gun into the hand (memory only; the game saves at typewriters)
            local wt = sdk.find_type_definition("app.ropeway.EquipmentDefine.WeaponType"):get_field(r.gift):get_data(nil)
            local im = sdk.get_managed_singleton("app.ropeway.gamemastering.InventoryManager")
            log.info("[test-short2] gift " .. r.gift .. " (" .. tostring(wt) .. "): " .. tostring(im:call("addAndEquipMainWeapon", wt, r.count or 1, r.item or 0)))
            return
        end
        if r.joints then   -- {"joints": 1}: the gun in hand's joint names
            local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
            local eq = pm:call("get_CurrentPlayer"):call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.Equipment"))
            local arm = eq:call("get_EquipWeapon"); local tf = arm:call("get_GameObject"):call("get_Transform")
            local names = {}; for _, j in ipairs(tf:call("get_Joints"):get_elements()) do names[#names + 1] = j:call("get_Name") end
            log.info("[test-short2] gun " .. tostring(arm:call("get_GameObject"):call("get_Name")) .. " joints: " .. table.concat(names, ", "))
            return
        end
        local o = inv(); if not o then log.info("[test-short2] no Inventory component"); return end
        if r.list then
            local td, out = o:get_type_definition(), {}
            while td do
                for _, m in ipairs(td:get_methods()) do local n = m:get_name()
                    if n:lower():find(r.list:lower()) then
                        local ps = {}; for _, p in ipairs(m:get_param_types() or {}) do ps[#ps + 1] = p:get_full_name() end
                        out[#out + 1] = n .. "(" .. table.concat(ps, ", ") .. ")" end end
                td = td:get_parent_type(); if td and td:get_full_name():find("^via") then break end
            end
            log.info("[test-short2] Inventory methods with '" .. r.list .. "': " .. table.concat(out, " | "))
        else
            local a = r.args or {}
            log.info("[test-short2] " .. r.call .. " -> " .. tostring(o:call(r.call, table.unpack(a))))
        end
    end)
    if not ok then log.info("[test-short2] failed: " .. tostring(err)) end
end)
