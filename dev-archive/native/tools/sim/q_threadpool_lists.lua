-- q_threadpool_lists.lua (rv.py -f): every app.ThreadPoolList / ThreadPoolDictionary type the game has, and where each
-- one's merge method lives (RE8-080: which list can hold the dead entry of the +0x4151C23 crash).
local tdb = sdk.get_tdb()
local n = tdb:get_num_types()
local out = {}
local base = nil
pcall(function() base = sdk.to_int64(sdk.get_native_singleton and 0 or 0) end)
for i = 0, n - 1 do
    local ok, td = pcall(function() return tdb:get_type(i) end)
    if ok and td then
        local ok2, name = pcall(function() return td:get_full_name() end)
        if ok2 and name and (name:find("ThreadPoolList", 1, true) or name:find("ThreadPoolDictionary", 1, true) or name:find("ThreadPoolMerge", 1, true)) then
            local addr = "?"
            pcall(function()
                local m = td:get_method("merge")
                if m then addr = string.format("%x", m:get_function():get_address()) end
            end)
            if addr == "?" then pcall(function() local m = td:get_method("merge"); if m then addr = tostring(m:get_function()) end end) end
            out[#out + 1] = name .. " merge@" .. addr
        end
    end
end
return #out .. " types: " .. table.concat(out, " | ")
