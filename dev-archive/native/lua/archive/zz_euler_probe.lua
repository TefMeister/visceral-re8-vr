-- zz_euler_probe.lua -- TEMPORARY (2026-11-05): for every finger joint of the player, the local rotation (quaternion) and the
-- engine's own local Euler angle (radians) at the same instant, 400 samples, written to data/visceral_re8/euler_probe.csv.
-- Tells us the engine's Euler convention, so finger poses cut from the takes can be written as Hand Poser files.
local FING = {"IndexF1","IndexF2","IndexF3","MiddleF1","MiddleF2","MiddleF3","RingF1","RingF2","RingF3","PinkyF1","PinkyF2","PinkyF3","Thumb1","Thumb2","Thumb3"}
local rows, done, frame, target, by_name = {}, false, 0, nil, {}
local function find_player()
    local sc = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    if not sc then return nil end
    local t = sdk.find_type_definition("app.PlayerUpdaterBase"); if not t then return nil end
    local ok, arr = pcall(function() return sc:call("findComponents(System.Type)", sdk.typeof("app.PlayerUpdaterBase")) end)
    if not ok or not arr then return nil end
    local els = arr:get_elements(); if not els or not els[1] then return nil end
    local ok2, go = pcall(function() return els[1]:call("get_GameObject") end)
    return ok2 and go or nil
end
local function link()
    local go = find_player(); if not go then return end
    local xf = go:call("get_Transform"); local arr = xf:call("get_Joints"); if not arr then return end
    by_name = {}
    for _, j in ipairs(arr:get_elements()) do by_name[j:call("get_Name")] = j end
    target = go
end
re.on_frame(function()
    if done then return end
    frame = frame + 1
    if frame % 4 ~= 0 then return end
    if not target then link(); return end
    for _, side in ipairs({"L_", "R_"}) do
        for _, f in ipairs(FING) do
            local j = by_name[side .. f]
            if j then
                local ok, q, e = pcall(function() return j:call("get_LocalRotation"), j:call("get_LocalEulerAngle") end)
                if ok and q and e then
                    rows[#rows + 1] = string.format("%d,%s%s,%.7f,%.7f,%.7f,%.7f,%.7f,%.7f,%.7f", frame, side, f, q.x, q.y, q.z, q.w, e.x, e.y, e.z)
                end
            end
        end
    end
    if #rows >= 30 * 400 then
        done = true
        fs.write("visceral_re8/euler_probe.csv", "frame,joint,qx,qy,qz,qw,ex,ey,ez\n" .. table.concat(rows, "\n") .. "\n")
        log.info("[euler-probe] written: " .. #rows .. " rows")
    end
end)
