-- q_storm_gui.lua (rv.py -f): RE8-080 test 2. The bridge's ammo counter refresh (the same three order calls, at the same
-- UpdateHID point) run EVERY FRAME, E.storm_per times a frame, while E.storm is true. Ask again with
-- "E.storm=false" to stop, "return E.storm_n .. ' ' .. E.storm_ok .. ' ' .. tostring(E.storm_err)" to read the counts.
E.storm = true
E.storm_per = E.storm_per or 1
E.storm_n, E.storm_ok, E.storm_err = 0, 0, nil
if not E.storm_hooked then
    E.storm_hooked = true
    re.on_pre_application_entry("UpdateHID", function()
        if not E.storm then return end
        for _ = 1, E.storm_per do
            E.storm_n = E.storm_n + 1
            local ok, err = pcall(function()
                local gm = sdk.get_managed_singleton("app.GUIManager")
                local h = gm and gm:call("findGUI", 1927694450)
                local drv = h and h:call("get_driver")
                if not drv then error("no driver") end
                pcall(function() drv:call("applyToUI") end)
                local order = nil
                pcall(function() order = drv:call("get_order") end)
                if not order then pcall(function() order = drv:get_field("guiOrder") end) end
                if not order then error("no order") end
                pcall(function() order:call("cancelHide") end)
                local mode, item = nil, nil
                pcall(function() mode = drv:call("get_mode") end)
                pcall(function() item = drv:call("get_itemID") end)
                if mode ~= nil and item ~= nil then order:call("showRemainAmmo", mode, item) end
                order:call("updateRemainAmmo", true)
            end)
            if ok then E.storm_ok = E.storm_ok + 1 else E.storm_err = tostring(err) end
        end
    end)
end
return "storm on, " .. E.storm_per .. " a frame"
