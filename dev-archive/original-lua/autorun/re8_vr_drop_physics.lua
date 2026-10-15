-- Village VR item drop physics (raycast gravity / bounce / settle).
-- Optional M.mesh is the floor clone for ammo.
-- Grab uses create() on the real item GO; create/begin/tick never spawn mesh clones.

if reframework:get_game_name() ~= "re8" then
    return {}
end

local M = {}
local MESH = {}
M.mesh = MESH

local STATE = {
    IDLE = "IDLE",
    FALLING = "FALLING",
    BOUNCING = "BOUNCING",
    RESTING = "RESTING",
}

local DEFAULTS = {
    gravity = 9.81,
    restitution = 0.28,
    restitution_jitter = 0.08,
    friction = 0.42,
    angular_damping = 3.2,
    linear_damping = 0.05,
    clearance = 0.025,
    release_lateral = 0.18,
    release_spin = 4.5,
    upright_spin = 0.35,
    impact_tumble = 1.15,
    surface_align = 8.0,
    rest_flatness = 0.96,
    -- Soft from-hand place: stand upright instead of ammo-style lie-flat.
    soft_place_enabled = 1.0,
    soft_place_speed = 0.35,
    soft_place_impact = 0.55,
    -- Only snap upright when nearly right-side-up (cos of angle from floor normal).
    soft_place_min_up_dot = 0.96,
    soft_place_max_tilt = 0.22,
    -- Pivot sits near mesh base for soft upright; keep larger clearance for flat ammo settle.
    soft_place_clearance = 0.003,
    upright_align = 10.0,
    rest_upright = 0.98,
    settle_lin = 0.12,
    settle_ang = 0.55,
    settle_hold = 0.12,
    max_lifetime = 4.5,
    max_bounces = 8,
    max_player_dist = 8.0,
    fixed_dt = 1.0 / 90.0,
    max_substeps = 4,
    cast_max = 3.5,
}

local CFG = {}
for k, v in pairs(DEFAULTS) do CFG[k] = v end

-- Single-frame multipass runs Lua ~1x per HMD present; two-frame/AFR ~2x.
-- Drop feel was calibrated on two-frame — scale dt only for multipass.
local VR_TECH = {
    t = 0.0,
    scale = 1.0,
    src = "default",
    locked = false,
    last_cb = nil,
    ema_cb = nil,
    infer_scale = 1.0,
}

local function infer_scale_from_callback_gap(now)
    local last = VR_TECH.last_cb
    VR_TECH.last_cb = now
    if type(last) ~= "number" then
        return VR_TECH.infer_scale or 1.0
    end
    local gap = now - last
    if gap < 0.002 or gap > 0.08 then
        return VR_TECH.infer_scale or 1.0
    end
    local ema = VR_TECH.ema_cb
    if type(ema) ~= "number" then
        ema = gap
    else
        ema = ema * 0.85 + gap * 0.15
    end
    VR_TECH.ema_cb = ema
    -- two-frame ~1/180 → scale 1; multipass ~1/90 → scale 2
    local fixed = 1.0 / 90.0
    local s = 2.0 * ema / fixed
    if s < 1.0 then s = 1.0 end
    if s > 2.0 then s = 2.0 end
    if s < 1.25 then
        s = 1.0
    elseif s > 1.75 then
        s = 2.0
    end
    VR_TECH.infer_scale = s
    return s
end

function M.note_vr_frame()
    local now = os.clock()
    infer_scale_from_callback_gap(now)
    if VR_TECH.locked ~= true then
        VR_TECH.scale = VR_TECH.infer_scale or 1.0
        VR_TECH.src = "infer_cb"
        VR_TECH.t = now
    end
end

local function read_vr_physics_dt_scale()
    local now = os.clock()
    if VR_TECH.locked == true and (now - (VR_TECH.t or 0)) < 1.0 then
        return VR_TECH.scale or 1.0
    end
    if VR_TECH.locked ~= true and (now - (VR_TECH.t or 0)) < 0.25 then
        return VR_TECH.scale or 1.0
    end
    VR_TECH.t = now
    local scale = 1.0
    local src = "default"
    local locked = false

    local vrmod = rawget(_G, "vrmod")
    if type(vrmod) == "table" or type(vrmod) == "userdata" then
        local multipass = nil
        pcall(function()
            if vrmod.is_using_multipass then
                multipass = vrmod:is_using_multipass() == true
            end
        end)
        if multipass == nil then
            pcall(function()
                if vrmod.get_rendering_technique then
                    multipass = (tonumber(vrmod:get_rendering_technique()) or -1) == 2
                end
            end)
        end
        if multipass == true then
            scale = 2.0
            src = "vrmod_multipass"
            locked = true
        elseif multipass == false then
            scale = 1.0
            src = "vrmod_two_frame"
            locked = true
        end
    end

    if locked ~= true then
        local paths = {
            "re2_fw_config.txt",
            "reframework/data/re2_fw_config.txt",
            "reframework/re2_fw_config.txt",
        }
        for i = 1, #paths do
            local f = nil
            pcall(function() f = io.open(paths[i], "r") end)
            if f then
                local body = f:read("*a") or ""
                f:close()
                local v = body:match("VR_RenderingTechnique_V2%s*=%s*([%d%.]+)")
                if not v then
                    v = body:match("RenderingTechnique_V2%s*=%s*([%d%.]+)")
                end
                if v ~= nil then
                    local n = tonumber(v)
                    if n == 2 then
                        scale = 2.0
                        src = "cfg_multipass"
                    else
                        scale = 1.0
                        src = "cfg_two_frame"
                    end
                    locked = true
                    break
                end
            end
        end
    end

    if locked ~= true then
        scale = VR_TECH.infer_scale or 1.0
        src = "infer_cb"
    end

    VR_TECH.scale = scale
    VR_TECH.src = src
    VR_TECH.locked = locked == true
    return scale
end

function M.vr_physics_dt_scale()
    return read_vr_physics_dt_scale()
end

local PHYS = {
    ready = false,
    system = nil,
    cast_method = nil,
    query = nil,
    result = nil,
    layers = {},
    layer_order = {},
    init_err = "",
}

local RNG = { s = 0xA5F15EED }

local SIM = {
    active = false,
    state = STATE.IDLE,
    joint = nil,
    px = 0.0, py = 0.0, pz = 0.0,
    vx = 0.0, vy = 0.0, vz = 0.0,
    qw = 1.0, qx = 0.0, qy = 0.0, qz = 0.0,
    wx = 0.0, wy = 0.0, wz = 0.0,
    rest_x = 0.0, rest_y = 0.0, rest_z = 0.0,
    rest_qw = 1.0, rest_qx = 0.0, rest_qy = 0.0, rest_qz = 0.0,
    bounce_count = 0,
    age = 0.0,
    settle_t = 0.0,
    floor_y = nil,
    floor_nx = 0.0, floor_ny = 1.0, floor_nz = 0.0,
    floor_layer = "",
    floor_dist = -1.0,
    cast_fails = 0,
    cast_hits = 0,
    last_speed = 0.0,
    last_ang_speed = 0.0,
    rest_reason = "",
    fallback_reason = "",
    seed_used = 0,
    supporting = false,
    ox = 0.0, oy = 0.0, oz = 0.0,
    release_tilt = 0.0,
    soft_place = false,
}

local function cfg_num(key, fallback)
    local v = tonumber(CFG[key])
    if v == nil then return fallback end
    return v
end

local function rng_u32()
    local x = RNG.s
    x = x ~ ((x << 13) & 0xFFFFFFFF)
    x = x ~ ((x >> 17) & 0xFFFFFFFF)
    x = x ~ ((x << 5) & 0xFFFFFFFF)
    RNG.s = x & 0xFFFFFFFF
    if RNG.s == 0 then RNG.s = 0xA5F15EED end
    return RNG.s
end

local function rng_unit()
    return (rng_u32() % 1000001) / 1000000.0
end

local function rng_signed(amp)
    return (rng_unit() * 2.0 - 1.0) * (amp or 1.0)
end

local function vec_len(x, y, z)
    return math.sqrt((x or 0.0) * (x or 0.0) + (y or 0.0) * (y or 0.0) + (z or 0.0) * (z or 0.0))
end

local function vec_norm(x, y, z)
    local L = vec_len(x, y, z)
    if L < 1e-8 then return 0.0, 1.0, 0.0, 0.0 end
    return x / L, y / L, z / L, L
end

local function quat_normalize(w, x, y, z)
    local L = math.sqrt(w * w + x * x + y * y + z * z)
    if L < 1e-8 then return 1.0, 0.0, 0.0, 0.0 end
    return w / L, x / L, y / L, z / L
end

local function quat_mul(aw, ax, ay, az, bw, bx, by, bz)
    return aw * bw - ax * bx - ay * by - az * bz,
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw
end

local function quat_rotate(w, x, y, z, vx, vy, vz)
    local tx = 2.0 * (y * vz - z * vy)
    local ty = 2.0 * (z * vx - x * vz)
    local tz = 2.0 * (x * vy - y * vx)
    return vx + w * tx + (y * tz - z * ty),
        vy + w * ty + (z * tx - x * tz),
        vz + w * tz + (x * ty - y * tx)
end

local function quat_from_to(ax, ay, az, bx, by, bz)
    ax, ay, az = vec_norm(ax, ay, az)
    bx, by, bz = vec_norm(bx, by, bz)
    local dot = ax * bx + ay * by + az * bz
    if dot > 0.99999 then return 1.0, 0.0, 0.0, 0.0 end
    if dot < -0.99999 then
        local rx, ry, rz = 0.0, -az, ay
        if vec_len(rx, ry, rz) < 1e-5 then
            rx, ry, rz = -az, 0.0, ax
        end
        rx, ry, rz = vec_norm(rx, ry, rz)
        return 0.0, rx, ry, rz
    end
    local cx = ay * bz - az * by
    local cy = az * bx - ax * bz
    local cz = ax * by - ay * bx
    return quat_normalize(1.0 + dot, cx, cy, cz)
end

local function quat_nlerp(aw, ax, ay, az, bw, bx, by, bz, t)
    local dot = aw * bw + ax * bx + ay * by + az * bz
    if dot < 0.0 then
        bw, bx, by, bz = -bw, -bx, -by, -bz
    end
    return quat_normalize(
        aw + (bw - aw) * t,
        ax + (bx - ax) * t,
        ay + (by - ay) * t,
        az + (bz - az) * t)
end

local function flat_target_quat(nx, ny, nz)
    nx, ny, nz = vec_norm(nx, ny, nz)
    local xx, xy, xz = quat_rotate(SIM.qw, SIM.qx, SIM.qy, SIM.qz, 1.0, 0.0, 0.0)
    local zx, zy, zz = quat_rotate(SIM.qw, SIM.qx, SIM.qy, SIM.qz, 0.0, 0.0, 1.0)
    local xdot = xx * nx + xy * ny + xz * nz
    local zdot = zx * nx + zy * ny + zz * nz
    local fx, fy, fz, sign
    if math.abs(xdot) >= math.abs(zdot) then
        fx, fy, fz = xx, xy, xz
        sign = xdot >= 0.0 and 1.0 or -1.0
    else
        fx, fy, fz = zx, zy, zz
        sign = zdot >= 0.0 and 1.0 or -1.0
    end
    local dw, dx, dy, dz = quat_from_to(fx, fy, fz, nx * sign, ny * sign, nz * sign)
    return quat_mul(dw, dx, dy, dz, SIM.qw, SIM.qx, SIM.qy, SIM.qz)
end

-- Stand on base: align local +Y to floor normal (right-side-up only).
local function upright_target_quat(nx, ny, nz)
    nx, ny, nz = vec_norm(nx, ny, nz)
    local yx, yy, yz = quat_rotate(SIM.qw, SIM.qx, SIM.qy, SIM.qz, 0.0, 1.0, 0.0)
    local dw, dx, dy, dz = quat_from_to(yx, yy, yz, nx, ny, nz)
    return quat_mul(dw, dx, dy, dz, SIM.qw, SIM.qx, SIM.qy, SIM.qz)
end

-- True only for soft place that is nearly vertical AND right-side-up.
-- Tilted / upside-down → false so flat tumble settle runs instead.
local function want_upright_align()
    if SIM.soft_place ~= true then return false end
    if cfg_num("soft_place_enabled", 1.0) < 0.5 then return false end
    local max_tilt = cfg_num("soft_place_max_tilt", 0.22)
    if (SIM.release_tilt or 0.0) > max_tilt then return false end
    local nx, ny, nz = vec_norm(SIM.floor_nx, SIM.floor_ny, SIM.floor_nz)
    local yx, yy, yz = quat_rotate(SIM.qw, SIM.qx, SIM.qy, SIM.qz, 0.0, 1.0, 0.0)
    local up_dot = yx * nx + yy * ny + yz * nz
    local min_dot = cfg_num("soft_place_min_up_dot", 0.96)
    return up_dot >= min_dot
end

local function contact_clearance()
    if want_upright_align() then
        return cfg_num("soft_place_clearance", 0.003)
    end
    return cfg_num("clearance", 0.025)
end

local function align_to_surface(dt, final)
    local tw, tx, ty, tz
    local t
    if want_upright_align() then
        tw, tx, ty, tz = upright_target_quat(SIM.floor_nx, SIM.floor_ny, SIM.floor_nz)
        if final then
            t = cfg_num("rest_upright", 0.98)
        else
            t = math.min(1.0, cfg_num("upright_align", 10.0) * dt)
        end
    else
        tw, tx, ty, tz = flat_target_quat(SIM.floor_nx, SIM.floor_ny, SIM.floor_nz)
        t = cfg_num("rest_flatness", 0.96)
        if not final then
            t = math.min(1.0, cfg_num("surface_align", 8.0) * dt)
        end
    end
    if t < 0.0 then t = 0.0 end
    if t > 1.0 then t = 1.0 end
    SIM.qw, SIM.qx, SIM.qy, SIM.qz = quat_nlerp(
        SIM.qw, SIM.qx, SIM.qy, SIM.qz, tw, tx, ty, tz, t)
end

local function quat_from_axis_angle(ax, ay, az, angle)
    local nx, ny, nz = vec_norm(ax, ay, az)
    local h = angle * 0.5
    local s = math.sin(h)
    return math.cos(h), nx * s, ny * s, nz * s
end

local function integrate_quat(dt)
    local wx, wy, wz = SIM.wx, SIM.wy, SIM.wz
    local ang = vec_len(wx, wy, wz)
    if ang < 1e-6 or dt <= 0.0 then return end
    local dw, dx, dy, dz = quat_from_axis_angle(wx, wy, wz, ang * dt)
    local nw, nx, ny, nz = quat_mul(dw, dx, dy, dz, SIM.qw, SIM.qx, SIM.qy, SIM.qz)
    SIM.qw, SIM.qx, SIM.qy, SIM.qz = quat_normalize(nw, nx, ny, nz)
end

local function read_static_u32(type_name, field_name)
    local v = nil
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        if not td then return end
        local f = td:get_field(field_name)
        if not f then return end
        v = f:get_data(nil)
    end)
    if type(v) == "number" then return v & 0xFFFFFFFF end
    return nil
end

local function ensure_physics()
    if PHYS.ready then return true end
    PHYS.init_err = ""
    local ok, err = pcall(function()
        PHYS.system = sdk.get_native_singleton("via.physics.System")
        local td = sdk.find_type_definition("via.physics.System")
        if not PHYS.system or not td then
            error("missing via.physics.System")
        end
        PHYS.cast_method = td:get_method("castRay(via.physics.CastRayQuery, via.physics.CastRayResult)")
        if not PHYS.cast_method then
            error("missing castRay method")
        end
        PHYS.query = sdk.create_instance("via.physics.CastRayQuery")
        PHYS.result = sdk.create_instance("via.physics.CastRayResult")
        if not PHYS.query or not PHYS.result then
            error("failed to create CastRayQuery/Result")
        end
        pcall(function() PHYS.query:add_ref() end)
        pcall(function() PHYS.result:add_ref() end)

        local layer_type = "app.CollisionManager.Layer"
        local names = { "Terrain", "TerrainCheck", "Bullet", "Default", "Attack" }
        PHYS.layers = {}
        PHYS.layer_order = {}
        for _, n in ipairs(names) do
            local id = read_static_u32(layer_type, n)
            if id ~= nil then
                PHYS.layers[n] = id
                PHYS.layer_order[#PHYS.layer_order + 1] = n
            end
        end
        if #PHYS.layer_order == 0 then
            error("no collision layers resolved")
        end
    end)
    if not ok or not PHYS.system or not PHYS.cast_method or not PHYS.query or not PHYS.result then
        PHYS.ready = false
        if type(err) == "string" and err ~= "" then
            PHYS.init_err = err
        elseif PHYS.init_err == "" then
            PHYS.init_err = "physics init failed"
        end
        return false
    end
    PHYS.ready = true
    return true
end

local function cast_ray(sx, sy, sz, ex, ey, ez, layer_id)
    if not ensure_physics() then return nil end
    local hit = nil
    local ok = pcall(function()
        PHYS.query:call("setRay(via.vec3, via.vec3)",
            Vector3f.new(sx, sy, sz), Vector3f.new(ex, ey, ez))
        PHYS.query:call("clearOptions")
        PHYS.query:call("enableAllHits")
        PHYS.query:call("enableNearSort")
        local filter = PHYS.query:call("get_FilterInfo")
        if filter then
            filter:call("set_Group", 0)
            filter:call("set_MaskBits", 0xFFFFFFFF & ~1)
            filter:call("set_Layer", layer_id)
            PHYS.query:call("set_FilterInfo", filter)
        end
        PHYS.result:call("clear")
        PHYS.cast_method:call(PHYS.system, PHYS.query, PHYS.result)
        local n = tonumber(PHYS.result:call("get_NumContactPoints")) or 0
        if n <= 0 then return end
        local cp = PHYS.result:call("getContactPoint(System.UInt32)", 0)
        if not cp then return end
        local dist = tonumber(cp:get_field("Distance"))
        local normal = cp:get_field("Normal")
        if type(dist) ~= "number" then return end
        local dirx, diry, dirz = ex - sx, ey - sy, ez - sz
        local dx, dy, dz, L = vec_norm(dirx, diry, dirz)
        local px = sx + dx * dist
        local py = sy + dy * dist
        local pz = sz + dz * dist
        local nx, ny, nz = 0.0, 1.0, 0.0
        if normal then
            nx = tonumber(normal.x) or 0.0
            ny = tonumber(normal.y) or 1.0
            nz = tonumber(normal.z) or 0.0
            nx, ny, nz = vec_norm(nx, ny, nz)
        end
        hit = {
            dist = dist,
            px = px, py = py, pz = pz,
            nx = nx, ny = ny, nz = nz,
            ray_len = L,
        }
    end)
    if not ok then
        SIM.cast_fails = (SIM.cast_fails or 0) + 1
        return nil
    end
    if hit then
        SIM.cast_hits = (SIM.cast_hits or 0) + 1
    else
        SIM.cast_fails = (SIM.cast_fails or 0) + 1
    end
    return hit
end

local function probe_floor(from_x, from_y, from_z)
    local best = nil
    local best_name = ""
    local maxd = cfg_num("cast_max", 3.5)
    for _, name in ipairs(PHYS.layer_order) do
        local layer = PHYS.layers[name]
        if layer ~= nil then
            local hit = cast_ray(from_x, from_y, from_z,
                from_x, from_y - maxd, from_z, layer)
            if hit and hit.ny > 0.35 then
                if not best or hit.dist < best.dist then
                    best = hit
                    best_name = name
                end
            end
        end
    end
    if best then
        best.layer = best_name
    end
    return best
end

local function sweep_move(nx, ny, nz)
    local sx = SIM.px
    local sy = SIM.py + 0.01
    local sz = SIM.pz
    local ex, ey, ez = nx, ny, nz
    local dx, dy, dz = ex - sx, ey - sy, ez - sz
    local _, _, _, travel = vec_norm(dx, dy, dz)
    if travel < 1e-5 then
        return { hit = false, x = nx, y = ny, z = nz }
    end

    local best = nil
    local best_name = ""
    for _, name in ipairs(PHYS.layer_order) do
        local layer = PHYS.layers[name]
        if layer ~= nil then
            local hit = cast_ray(sx, sy, sz, ex, ey, ez, layer)
            if hit and hit.dist < travel then
                if not best or hit.dist < best.dist then
                    best = hit
                    best_name = name
                end
            end
        end
    end
    if not best then
        return { hit = false, x = nx, y = ny, z = nz }
    end
    best.layer = best_name
    local clear = contact_clearance()
    local px = best.px + best.nx * clear
    local py = best.py + best.ny * clear
    local pz = best.pz + best.nz * clear
    return {
        hit = true,
        x = px, y = py, z = pz,
        nx = best.nx, ny = best.ny, nz = best.nz,
        layer = best.layer,
        dist = best.dist,
    }
end

local function reflect_velocity(nx, ny, nz)
    local rest = cfg_num("restitution", 0.28)
        + rng_signed(cfg_num("restitution_jitter", 0.08))
    if rest < 0.05 then rest = 0.05 end
    if rest > 0.55 then rest = 0.55 end
    local fric = cfg_num("friction", 0.42)
    if fric < 0.0 then fric = 0.0 end
    if fric > 0.95 then fric = 0.95 end

    local vdot = SIM.vx * nx + SIM.vy * ny + SIM.vz * nz
    local nvx = nx * vdot
    local nvy = ny * vdot
    local nvz = nz * vdot
    local tvx = SIM.vx - nvx
    local tvy = SIM.vy - nvy
    local tvz = SIM.vz - nvz

    if vdot < 0.0 then
        SIM.vx = tvx * (1.0 - fric) - nvx * rest
        SIM.vy = tvy * (1.0 - fric) - nvy * rest
        SIM.vz = tvz * (1.0 - fric) - nvz * rest
    else
        SIM.vx = tvx * (1.0 - fric * 0.5)
        SIM.vy = tvy * (1.0 - fric * 0.5)
        SIM.vz = tvz * (1.0 - fric * 0.5)
    end

    local lx, ly, lz = quat_rotate(SIM.qw, SIM.qx, SIM.qy, SIM.qz, 0.0, -1.0, 0.0)
    local impulse = math.abs(vdot) * cfg_num("impact_tumble", 1.15)
    if SIM.soft_place == true and cfg_num("soft_place_enabled", 1.0) >= 0.5 then
        if want_upright_align() then
            -- Right-side-up soft place: no tumble (stay standing).
            impulse = 0.0
        else
            -- Tilted / upside-down soft place: keep tumble so it falls flat.
            local lim = cfg_num("soft_place_impact", 0.55)
            if math.abs(vdot) <= lim then
                impulse = math.max(impulse, 0.55)
            end
        end
    end
    if impulse > 1e-6 then
        local tx = ly * nz - lz * ny
        local ty = lz * nx - lx * nz
        local tz = lx * ny - ly * nx
        local jitter = 0.10 + 0.15 * (SIM.release_tilt or 0.0)
        SIM.wx = SIM.wx + tx * impulse + rng_signed(jitter)
        SIM.wy = SIM.wy + ty * impulse + rng_signed(jitter)
        SIM.wz = SIM.wz + tz * impulse + rng_signed(jitter)
    end

    SIM.bounce_count = (SIM.bounce_count or 0) + 1
    SIM.state = STATE.BOUNCING
    SIM.supporting = true
    SIM.floor_nx, SIM.floor_ny, SIM.floor_nz = nx, ny, nz
end

local function substep(dt)
    local g = cfg_num("gravity", 9.81)
    local ld = cfg_num("linear_damping", 0.05)
    local ad = cfg_num("angular_damping", 3.2)

    SIM.vy = SIM.vy - g * dt
    SIM.vx = SIM.vx * (1.0 - ld * dt)
    SIM.vy = SIM.vy * (1.0 - ld * dt)
    SIM.vz = SIM.vz * (1.0 - ld * dt)
    SIM.wx = SIM.wx * math.max(0.0, 1.0 - ad * dt)
    SIM.wy = SIM.wy * math.max(0.0, 1.0 - ad * dt)
    SIM.wz = SIM.wz * math.max(0.0, 1.0 - ad * dt)

    local nx = SIM.px + SIM.vx * dt
    local ny = SIM.py + SIM.vy * dt
    local nz = SIM.pz + SIM.vz * dt

    local sweep = sweep_move(nx, ny, nz)
    if sweep.hit then
        SIM.px, SIM.py, SIM.pz = sweep.x, sweep.y, sweep.z
        reflect_velocity(sweep.nx, sweep.ny, sweep.nz)
        if sweep.layer and sweep.layer ~= "" then
            SIM.floor_layer = sweep.layer
        end
        SIM.floor_y = sweep.y
        SIM.floor_dist = sweep.dist or SIM.floor_dist
    else
        SIM.px, SIM.py, SIM.pz = nx, ny, nz
        SIM.supporting = false
        if SIM.vy < 0.0 then
            local floor = probe_floor(SIM.px, SIM.py + 0.05, SIM.pz)
            if floor then
                SIM.floor_y = floor.py
                SIM.floor_nx, SIM.floor_ny, SIM.floor_nz = floor.nx, floor.ny, floor.nz
                SIM.floor_layer = floor.layer or SIM.floor_layer
                SIM.floor_dist = floor.dist
                local clear = contact_clearance()
                if SIM.py <= floor.py + clear then
                    SIM.px = floor.px + floor.nx * clear
                    SIM.py = floor.py + floor.ny * clear
                    SIM.pz = floor.pz + floor.nz * clear
                    reflect_velocity(floor.nx, floor.ny, floor.nz)
                end
            end
        end
    end

    integrate_quat(dt)
    if SIM.supporting then
        align_to_surface(dt, false)
    end
    SIM.last_speed = vec_len(SIM.vx, SIM.vy, SIM.vz)
    SIM.last_ang_speed = vec_len(SIM.wx, SIM.wy, SIM.wz)
end

local function force_rest(reason)
    SIM.state = STATE.RESTING
    SIM.active = true -- stay active so apply_pose keeps freezing
    SIM.vx, SIM.vy, SIM.vz = 0.0, 0.0, 0.0
    SIM.wx, SIM.wy, SIM.wz = 0.0, 0.0, 0.0
    if SIM.floor_y ~= nil then
        local clear = contact_clearance()
        SIM.py = SIM.floor_y + clear
    end
    align_to_surface(0.0, true)
    -- Re-apply height after orient (upright uses smaller clearance).
    if SIM.floor_y ~= nil then
        local clear = contact_clearance()
        SIM.py = SIM.floor_y + clear
    end
    SIM.rest_x, SIM.rest_y, SIM.rest_z = SIM.px, SIM.py, SIM.pz
    SIM.rest_qw, SIM.rest_qx, SIM.rest_qy, SIM.rest_qz = SIM.qw, SIM.qx, SIM.qy, SIM.qz
    SIM.rest_reason = reason or "forced_rest"
end

local function try_settle(dt)
    local lin = cfg_num("settle_lin", 0.12)
    local ang = cfg_num("settle_ang", 0.55)
    local hold = cfg_num("settle_hold", 0.12)
    local clear = contact_clearance()
    local on_support = SIM.supporting == true or (
        SIM.floor_y ~= nil and SIM.py <= (SIM.floor_y + clear + 0.01)
            and SIM.vy <= 0.15)

    if on_support and SIM.last_speed <= lin and SIM.last_ang_speed <= ang then
        SIM.settle_t = (SIM.settle_t or 0.0) + dt
    else
        SIM.settle_t = 0.0
    end

    if SIM.settle_t >= hold then
        force_rest(string.format(
            "settled bounces=%d layer=%s speed=%.3f",
            SIM.bounce_count or 0,
            SIM.floor_layer ~= "" and SIM.floor_layer or "?",
            SIM.last_speed or 0.0))
        return true
    end
    return false
end

function M.configure(opts)
    if type(opts) ~= "table" then return CFG end
    for k, _ in pairs(DEFAULTS) do
        if opts[k] ~= nil then
            local n = tonumber(opts[k])
            if n ~= nil then CFG[k] = n end
        end
    end
    return CFG
end

function M.get_config()
    local out = {}
    for k, v in pairs(CFG) do out[k] = v end
    return out
end

function M.is_ready()
    return ensure_physics()
end

function M.init_error()
    ensure_physics()
    return PHYS.init_err or ""
end

function M.reset(reason)
    SIM.active = false
    SIM.state = STATE.IDLE
    SIM.joint = nil
    SIM.fallback_reason = reason or ""
    SIM.rest_reason = ""
    SIM.supporting = false
    SIM.settle_t = 0.0
    SIM.age = 0.0
    SIM.soft_place = false
end

function M.begin(joint, wpos, wrot, opts)
    SIM.fallback_reason = ""
    SIM.rest_reason = ""
    opts = (type(opts) == "table") and opts or nil
    if not joint then
        SIM.fallback_reason = "no joint"
        return false, SIM.fallback_reason
    end
    if not wpos then
        SIM.fallback_reason = "no world pos"
        return false, SIM.fallback_reason
    end
    if not ensure_physics() then
        SIM.fallback_reason = PHYS.init_err ~= "" and PHYS.init_err or "physics unavailable"
        return false, SIM.fallback_reason
    end

    local seed = (math.floor(os.clock() * 1000) ~ 0x5EEDBEEF) & 0xFFFFFFFF
    if seed == 0 then seed = 0xA5F15EED end
    RNG.s = seed
    SIM.seed_used = seed

    SIM.joint = joint
    SIM.px, SIM.py, SIM.pz = wpos.x, wpos.y, wpos.z
    SIM.ox, SIM.oy, SIM.oz = SIM.px, SIM.py, SIM.pz
    if wrot then
        SIM.qw = tonumber(wrot.w) or 1.0
        SIM.qx = tonumber(wrot.x) or 0.0
        SIM.qy = tonumber(wrot.y) or 0.0
        SIM.qz = tonumber(wrot.z) or 0.0
        SIM.qw, SIM.qx, SIM.qy, SIM.qz = quat_normalize(SIM.qw, SIM.qx, SIM.qy, SIM.qz)
    else
        SIM.qw, SIM.qx, SIM.qy, SIM.qz = 1.0, 0.0, 0.0, 0.0
    end

    local ex, ey, ez = quat_rotate(SIM.qw, SIM.qx, SIM.qy, SIM.qz, 0.0, -1.0, 0.0)
    ex, ey, ez = vec_norm(ex, ey, ez)
    local tilt = math.sqrt(math.max(0.0, 1.0 - math.min(1.0, ey * ey)))
    SIM.release_tilt = tilt
    local hx, hz = ex, ez
    local hlen = math.sqrt(hx * hx + hz * hz)
    if hlen > 1e-5 then hx, hz = hx / hlen, hz / hlen end
    local hand_vx = opts and tonumber(opts.vx) or nil
    local hand_vy = opts and tonumber(opts.vy) or nil
    local hand_vz = opts and tonumber(opts.vz) or nil
    local hand_speed = 0.0
    if hand_vx and hand_vy and hand_vz then
        hand_speed = math.sqrt(hand_vx * hand_vx + hand_vy * hand_vy + hand_vz * hand_vz)
    end

    local soft_en = cfg_num("soft_place_enabled", 1.0) >= 0.5
    local soft_spd = cfg_num("soft_place_speed", 0.35)
    local from_hand = opts and opts.from_hand == true
    SIM.soft_place = false

    if from_hand and soft_en and hand_speed < soft_spd then
        -- Gentle place: keep release orientation, no synthetic tumble.
        SIM.soft_place = true
        SIM.vx = hand_vx or 0.0
        SIM.vy = hand_vy or 0.0
        SIM.vz = hand_vz or 0.0
        SIM.wx, SIM.wy, SIM.wz = 0.0, 0.0, 0.0
    elseif from_hand and hand_speed >= 0.05 then
        SIM.vx = hand_vx
        SIM.vy = hand_vy
        SIM.vz = hand_vz
        local hand_spin = cfg_num("upright_spin", 0.35) * 0.45
        SIM.wx = rng_signed(hand_spin)
        SIM.wy = rng_signed(hand_spin * 0.5)
        SIM.wz = rng_signed(hand_spin)
    else
        local lat = cfg_num("release_lateral", 0.18)
        local jitter = lat * (0.03 + tilt * 0.08)
        SIM.vx = hx * lat * tilt + rng_signed(jitter)
        SIM.vy = -0.04
        SIM.vz = hz * lat * tilt + rng_signed(jitter)
        local max_spin = cfg_num("release_spin", 4.5)
        local spin = cfg_num("upright_spin", 0.35)
            + (max_spin - cfg_num("upright_spin", 0.35)) * tilt
        SIM.wx = rng_signed(spin)
        SIM.wy = rng_signed(spin * 0.65)
        SIM.wz = rng_signed(spin)
    end

    SIM.bounce_count = 0
    SIM.age = 0.0
    SIM.settle_t = 0.0
    SIM.cast_fails = 0
    SIM.cast_hits = 0
    SIM.supporting = false
    SIM.floor_y = nil
    SIM.floor_layer = ""
    SIM.floor_dist = -1.0
    SIM.floor_nx, SIM.floor_ny, SIM.floor_nz = 0.0, 1.0, 0.0

    local floor = probe_floor(SIM.px, SIM.py + 0.02, SIM.pz)
    if floor then
        SIM.floor_y = floor.py
        SIM.floor_nx, SIM.floor_ny, SIM.floor_nz = floor.nx, floor.ny, floor.nz
        SIM.floor_layer = floor.layer or ""
        SIM.floor_dist = floor.dist
    else
        SIM.floor_dist = -1.0
    end

    SIM.state = STATE.FALLING
    SIM.active = true
    SIM.last_speed = vec_len(SIM.vx, SIM.vy, SIM.vz)
    SIM.last_ang_speed = vec_len(SIM.wx, SIM.wy, SIM.wz)
    return true, ""
end

function M.tick(dt)
    if SIM.active ~= true then return SIM.state end
    if SIM.state == STATE.RESTING then return SIM.state end
    if SIM.state ~= STATE.FALLING and SIM.state ~= STATE.BOUNCING then
        return SIM.state
    end

    dt = tonumber(dt) or 0.0
    if dt <= 0.0 then dt = cfg_num("fixed_dt", 1.0 / 90.0) end
    local scale = read_vr_physics_dt_scale()
    if scale ~= 1.0 then
        dt = dt * scale
    end
    local max_dt = 0.05 * math.max(1.0, scale)
    if dt > max_dt then dt = max_dt end

    SIM.age = (SIM.age or 0.0) + dt
    local max_life = cfg_num("max_lifetime", 4.5)
    local max_bounce = cfg_num("max_bounces", 8)

    local fixed = cfg_num("fixed_dt", 1.0 / 90.0)
    local steps = math.floor(dt / fixed + 0.5)
    if steps < 1 then steps = 1 end
    local max_steps = cfg_num("max_substeps", 4)
    if scale > 1.0 then
        max_steps = max_steps * 2
    end
    if steps > max_steps then steps = max_steps end
    local step_dt = dt / steps
    for _ = 1, steps do
        if SIM.state == STATE.RESTING then break end
        substep(step_dt)
        if try_settle(step_dt) then break end
        if (SIM.bounce_count or 0) >= max_bounce then
            SIM.supporting = true
            force_rest("max_bounces")
            break
        end
    end

    if SIM.state ~= STATE.RESTING and SIM.age >= max_life then
        force_rest("max_lifetime")
    end

    if SIM.state ~= STATE.RESTING then
        local max_dist = cfg_num("max_player_dist", 8.0)
        local dx = SIM.px - SIM.ox
        local dy = SIM.py - SIM.oy
        local dz = SIM.pz - SIM.oz
        if vec_len(dx, dy, dz) >= max_dist then
            force_rest("max_distance")
        end
    end

    return SIM.state
end

function M.apply_pose(joint)
    local j = joint or SIM.joint
    if not j then return false end
    if SIM.active ~= true then return false end
    if SIM.state ~= STATE.FALLING and SIM.state ~= STATE.BOUNCING and SIM.state ~= STATE.RESTING then
        return false
    end
    local x, y, z = SIM.px, SIM.py, SIM.pz
    local qw, qx, qy, qz = SIM.qw, SIM.qx, SIM.qy, SIM.qz
    if SIM.state == STATE.RESTING then
        x, y, z = SIM.rest_x, SIM.rest_y, SIM.rest_z
        qw, qx, qy, qz = SIM.rest_qw, SIM.rest_qx, SIM.rest_qy, SIM.rest_qz
    end
    local ok = false
    pcall(function()
        j:call("set_Position", Vector3f.new(x, y, z))
        j:call("set_Rotation", Quaternion.new(qw, qx, qy, qz))
        ok = true
    end)
    return ok
end

function M.is_active()
    return SIM.active == true
        and (SIM.state == STATE.FALLING or SIM.state == STATE.BOUNCING or SIM.state == STATE.RESTING)
end

function M.is_resting()
    return SIM.active == true and SIM.state == STATE.RESTING
end

function M.is_simulating()
    return SIM.active == true
        and (SIM.state == STATE.FALLING or SIM.state == STATE.BOUNCING)
end

function M.status()
    return {
        ready = PHYS.ready == true,
        init_err = PHYS.init_err or "",
        active = SIM.active == true,
        state = SIM.state,
        px = SIM.px, py = SIM.py, pz = SIM.pz,
        vx = SIM.vx, vy = SIM.vy, vz = SIM.vz,
        speed = SIM.last_speed,
        ang_speed = SIM.last_ang_speed,
        bounce_count = SIM.bounce_count or 0,
        age = SIM.age or 0.0,
        floor_y = SIM.floor_y,
        floor_dist = SIM.floor_dist,
        floor_layer = SIM.floor_layer,
        floor_ny = SIM.floor_ny,
        cast_hits = SIM.cast_hits or 0,
        cast_fails = SIM.cast_fails or 0,
        rest_reason = SIM.rest_reason,
        fallback_reason = SIM.fallback_reason,
        seed = SIM.seed_used,
        release_tilt = SIM.release_tilt,
        soft_place = SIM.soft_place == true,
        layers = #PHYS.layer_order,
    }
end

local function new_sim_state()
    return {
        active = false,
        state = STATE.IDLE,
        joint = nil,
        px = 0.0, py = 0.0, pz = 0.0,
        vx = 0.0, vy = 0.0, vz = 0.0,
        qw = 1.0, qx = 0.0, qy = 0.0, qz = 0.0,
        wx = 0.0, wy = 0.0, wz = 0.0,
        rest_x = 0.0, rest_y = 0.0, rest_z = 0.0,
        rest_qw = 1.0, rest_qx = 0.0, rest_qy = 0.0, rest_qz = 0.0,
        bounce_count = 0,
        age = 0.0,
        settle_t = 0.0,
        floor_y = nil,
        floor_nx = 0.0, floor_ny = 1.0, floor_nz = 0.0,
        floor_layer = "",
        floor_dist = -1.0,
        cast_fails = 0,
        cast_hits = 0,
        last_speed = 0.0,
        last_ang_speed = 0.0,
        rest_reason = "",
        fallback_reason = "",
        seed_used = 0,
        supporting = false,
        ox = 0.0, oy = 0.0, oz = 0.0,
        release_tilt = 0.0,
        soft_place = false,
    }
end

function M.create()
    local sim = new_sim_state()
    local api = {}

    local function call1(fn, a1)
        local prev = SIM
        SIM = sim
        local ok, r1 = pcall(fn, a1)
        SIM = prev
        if not ok then return nil end
        return r1
    end

    local function call4(fn, a1, a2, a3, a4)
        local prev = SIM
        SIM = sim
        local ok, r1, r2 = pcall(fn, a1, a2, a3, a4)
        SIM = prev
        if not ok then return false, tostring(r1) end
        return r1, r2
    end

    function api.begin(joint, wpos, wrot, opts)
        return call4(M.begin, joint, wpos, wrot, opts)
    end

    function api.tick(dt)
        return call1(M.tick, dt)
    end

    function api.apply_pose(joint)
        return call1(M.apply_pose, joint)
    end

    function api.reset(reason)
        return call1(M.reset, reason)
    end

    function api.is_active()
        return call1(M.is_active)
    end

    function api.is_resting()
        return call1(M.is_resting)
    end

    function api.is_simulating()
        return call1(M.is_simulating)
    end

    function api.status()
        return call1(M.status)
    end

    function api.configure(opts)
        return M.configure(opts)
    end

    function api.is_ready()
        return M.is_ready()
    end

    return api
end

MESH.DEFAULTS = {
    name_filters = { "mag", "clip", "cartridge" },
    material_index = -1,
    part_index = -1,
    offset_x = 0.0,
    offset_y = 0.0,
    offset_z = 0.0,
    disable_culling = true,
}

MESH.cfg = {}
for k, v in pairs(MESH.DEFAULTS) do MESH.cfg[k] = v end

MESH.rt = {
    mesh_type = nil,
    resolved = false,
}

-- Per-weapon floor mag instances. MESH.CURRENT_ID selects which slot spawn/set_pose use.
MESH.SPAWN_BY_ID = {}
MESH.CURRENT_ID = "_default"

function MESH._new_slot()
    return {
        go = nil,
        mesh = nil,
        active = false,
        material_count = 0,
        material_names = {},
        chosen_index = -1,
        part_count = 0,
        chosen_part = -1,
        last_error = "",
        pose_x = 0.0, pose_y = 0.0, pose_z = 0.0,
        held_refs = {},
    }
end

function MESH._norm_id(id)
    if type(id) == "string" and id ~= "" then return id end
    return MESH.CURRENT_ID or "_default"
end

function MESH._slot_of(id)
    id = MESH._norm_id(id)
    local s = MESH.SPAWN_BY_ID[id]
    if not s then
        s = MESH._new_slot()
        MESH.SPAWN_BY_ID[id] = s
    end
    return s, id
end

function MESH.set_context(id)
    MESH.CURRENT_ID = MESH._norm_id(id)
    return MESH.CURRENT_ID
end

function MESH.get_context()
    return MESH.CURRENT_ID
end

function MESH._cfg(key, fallback)
    local v = MESH.cfg[key]
    if v == nil then return fallback end
    return v
end

function MESH._managed_alive(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function()
        return obj:call("get_Valid")
    end)
    if ok and valid ~= nil then return valid == true end
    return true
end

function MESH._read_string(v)
    if type(v) == "string" then return v end
    if v == nil then return "" end
    local s = ""
    pcall(function() s = v:call("ToString") or "" end)
    if type(s) ~= "string" then return "" end
    return s
end

function MESH._ensure_rt()
    if MESH.rt.resolved then return MESH.rt.mesh_type ~= nil end
    MESH.rt.resolved = true
    pcall(function()
        local td = sdk.find_type_definition("via.render.Mesh")
        if td then MESH.rt.mesh_type = td:get_runtime_type() end
    end)
    return MESH.rt.mesh_type ~= nil
end

function MESH.configure(opts)
    if type(opts) ~= "table" then return MESH.cfg end
    for k, _ in pairs(MESH.DEFAULTS) do
        if opts[k] ~= nil then MESH.cfg[k] = opts[k] end
    end
    return MESH.cfg
end

function MESH.get_config()
    local out = {}
    for k, v in pairs(MESH.cfg) do out[k] = v end
    return out
end

function MESH._scan_materials(src_mesh)
    local names = {}
    local count = 0
    pcall(function() count = tonumber(src_mesh:call("get_MaterialNum")) or 0 end)
    for i = 0, count - 1 do
        local nm = ""
        pcall(function() nm = MESH._read_string(src_mesh:call("getMaterialName", i)) end)
        names[#names + 1] = nm
    end
    return count, names
end

function MESH._pick_material_index(count, names)
    local forced = tonumber(MESH._cfg("material_index", -1)) or -1
    if forced >= 0 and forced < count then return forced end
    local filters = MESH._cfg("name_filters", {})
    for i = 1, #names do
        local low = string.lower(names[i] or "")
        for _, f in ipairs(filters) do
            if f ~= "" and string.find(low, f, 1, true) then
                return i - 1
            end
        end
    end
    return -1
end

function MESH._scan_parts(src_mesh)
    local count = 0
    pcall(function() count = tonumber(src_mesh:call("getPartsEnableCount")) or 0 end)
    return count
end

function MESH._apply_part_mask(mesh, count, keep_index)
    -- Out-of-range keep_index would disable EVERY part → invisible floor mag.
    if keep_index < 0 or count <= 0 or keep_index >= count then return false end
    local ok = pcall(function()
        pcall(function() mesh:call("setPartsEnableCount", count) end)
        for i = 0, count - 1 do
            mesh:call("setPartsEnable", i, i == keep_index)
        end
    end)
    return ok
end

function MESH._apply_material_mask(mesh, count, keep_index)
    if keep_index < 0 or count <= 0 then return false end
    local ok = pcall(function()
        pcall(function() mesh:call("setMaterialsEnableCount", count) end)
        for i = 0, count - 1 do
            mesh:call("setMaterialsEnable", i, i == keep_index)
        end
    end)
    return ok
end

function MESH._apply_render_flags(mesh)
    pcall(function() mesh:call("set_Enabled", true) end)
    pcall(function() mesh:call("set_DrawDefault", true) end)
    -- Floor clones often spawn with get_Viewable()==false; force draw.
    pcall(function() mesh:call("set_Viewable", true) end)
    pcall(function() mesh:call("setVisible", true) end)
    pcall(function() mesh:call("disableJointMatrixUpdating", true) end)
    pcall(function() mesh:call("set_StaticMesh", true) end)
    if MESH._cfg("disable_culling", true) == true then
        pcall(function() mesh:call("set_FrustumCulling", false) end)
        pcall(function() mesh:call("set_OcclusionCulling", false) end)
    end
end

-- Re-assert world-mag draw flags without touching weapon joints.
function MESH._force_world_visible(slot)
    if not slot or not slot.mesh then return false end
    MESH._apply_render_flags(slot.mesh)
    local go = slot.go
    if MESH._managed_alive(go) then
        pcall(function() go:call("set_DrawSelf", true) end)
        pcall(function() go:call("set_UpdateSelf", true) end)
    end
    return true
end

function MESH._set_go_transform(go, x, y, z, rot)
    local tf = nil
    pcall(function() tf = go:call("get_Transform") end)
    if not tf then return false end
    -- Floor mags must stay as root world objects — never follow player/weapon.
    pcall(function()
        if tf.set_Parent then
            tf:call("set_Parent", nil)
        elseif tf.setParent then
            tf:call("setParent", nil)
        end
    end)
    pcall(function() tf:call("set_SameJointsConstraint", false) end)
    pcall(function() tf:call("set_Position", Vector3f.new(x, y, z)) end)
    if rot and rot.w ~= nil then
        pcall(function()
            tf:call("set_Rotation",
                Quaternion.new(rot.w, rot.x, rot.y, rot.z))
        end)
    end
    return true
end

function MESH._unparent_go(go)
    if not MESH._managed_alive(go) then return end
    pcall(function()
        local tf = go:call("get_Transform")
        if not tf then return end
        if tf.set_Parent then
            tf:call("set_Parent", nil)
        elseif tf.setParent then
            tf:call("setParent", nil)
        end
    end)
end

function MESH._hold_ref(slot, obj)
    if obj == nil or not slot then return end
    pcall(function() obj:add_ref() end)
    slot.held_refs[#slot.held_refs + 1] = obj
end

function MESH._release_refs(slot)
    if not slot then return end
    for i = #slot.held_refs, 1, -1 do
        local obj = slot.held_refs[i]
        slot.held_refs[i] = nil
        if obj then pcall(function() obj:release() end) end
    end
end

function MESH._despawn_slot(slot, id, reason)
    if slot.go then
        pcall(function()
            sdk.find_type_definition("via.GameObject")
                :get_method("destroy(via.GameObject)"):call(nil, slot.go)
        end)
    end
    MESH._release_refs(slot)
    slot.go = nil
    slot.mesh = nil
    slot.active = false
    slot.chosen_index = -1
end

-- despawn([id], [reason]) — id omitted uses MESH.CURRENT_ID.
function MESH.despawn(a, b)
    local id, reason
    if type(a) == "string" and (b ~= nil or MESH.SPAWN_BY_ID[a] ~= nil or a == MESH.CURRENT_ID) then
        if b == nil and MESH.SPAWN_BY_ID[a] == nil and a ~= MESH.CURRENT_ID and a ~= "_default" then
            -- despawn(reason) for current slot.
            id = MESH.CURRENT_ID
            reason = a
        else
            id = a
            reason = b
        end
    else
        id = MESH.CURRENT_ID
        reason = a
    end
    local slot, sid = MESH._slot_of(id)
    MESH._despawn_slot(slot, sid, reason)
end

function MESH.despawn_all(reason)
    for id, slot in pairs(MESH.SPAWN_BY_ID) do
        MESH._despawn_slot(slot, id, reason or "despawn_all")
    end
end

-- spawn([id], src_mesh, wpos, wrot) — id omitted uses MESH.CURRENT_ID.
function MESH.spawn(a, b, c, d)
    local id, src_mesh, wpos, wrot
    if type(a) == "string" and b ~= nil and type(b) ~= "number" then
        -- Heuristic: string + non-nil second that isn't a plain number → id form.
        -- Managed mesh objects are tables/userdata, not strings.
        local maybe_src = b
        local looks_like_src = maybe_src ~= nil and type(maybe_src) ~= "string"
        if looks_like_src then
            id, src_mesh, wpos, wrot = a, b, c, d
        else
            id, src_mesh, wpos, wrot = MESH.CURRENT_ID, a, b, c
        end
    else
        id, src_mesh, wpos, wrot = MESH.CURRENT_ID, a, b, c
    end

    local slot, sid = MESH._slot_of(id)
    MESH.CURRENT_ID = sid
    slot.last_error = ""

    if not MESH._managed_alive(src_mesh) then
        slot.last_error = "no source mesh"
        return false
    end
    if not wpos then
        slot.last_error = "no world pos"
        return false
    end
    if not MESH._ensure_rt() then
        slot.last_error = "no via.render.Mesh runtime type"
        return false
    end

    local count, names = MESH._scan_materials(src_mesh)
    slot.material_count = count
    slot.material_names = names
    local keep = MESH._pick_material_index(count, names)
    slot.chosen_index = keep
    local part_count = MESH._scan_parts(src_mesh)
    slot.part_count = part_count
    local part_keep = tonumber(MESH._cfg("part_index", -1)) or -1
    slot.chosen_part = part_keep

    MESH._despawn_slot(slot, sid, "respawn")

    local mesh_holder, mat_holder = nil, nil
    pcall(function() mesh_holder = src_mesh:call("getMesh") end)
    pcall(function() mat_holder = src_mesh:call("get_Material") end)
    if not mesh_holder or not mat_holder then
        slot.last_error = "missing mesh/material holder"
        return false
    end

    local go = nil
    pcall(function()
        go = sdk.find_type_definition("via.GameObject")
            :get_method("create(System.String)"):call(nil, "re8_ammo_drop_floor")
    end)
    if not MESH._managed_alive(go) then
        slot.last_error = "GameObject.create failed"
        return false
    end

    local mesh = nil
    pcall(function()
        mesh = go:call("createComponent(System.Type)", MESH.rt.mesh_type)
    end)
    if not mesh then
        pcall(function()
            sdk.find_type_definition("via.GameObject")
                :get_method("destroy(via.GameObject)"):call(nil, go)
        end)
        slot.last_error = "createComponent(Mesh) failed"
        return false
    end

    local shared_ok = false
    pcall(function()
        mesh:call("setMesh", mesh_holder)
        mesh:call("set_Material", mat_holder)
        shared_ok = true
    end)
    if not shared_ok then
        pcall(function()
            sdk.find_type_definition("via.GameObject")
                :get_method("destroy(via.GameObject)"):call(nil, go)
        end)
        slot.last_error = "share mesh/material failed"
        return false
    end

    MESH._hold_ref(slot, mesh_holder)
    MESH._hold_ref(slot, mat_holder)

    MESH._apply_render_flags(mesh)
    if keep >= 0 then
        MESH._apply_material_mask(mesh, count, keep)
    end
    if part_keep >= 0 then
        if part_keep < part_count then
            MESH._apply_part_mask(mesh, part_count, part_keep)
        else
            -- Keep all parts rather than blanking the mesh.
            slot.chosen_part = -1
            part_keep = -1
        end
    end

    local off_x = tonumber(MESH._cfg("offset_x", 0.0)) or 0.0
    local off_y = tonumber(MESH._cfg("offset_y", 0.0)) or 0.0
    local off_z = tonumber(MESH._cfg("offset_z", 0.0)) or 0.0
    slot.pose_x = wpos.x + off_x
    slot.pose_y = wpos.y + off_y
    slot.pose_z = wpos.z + off_z
    MESH._set_go_transform(go, slot.pose_x, slot.pose_y, slot.pose_z, wrot)

    slot.go = go
    slot.mesh = mesh
    slot.active = true
    MESH._unparent_go(go)
    -- Re-apply pose after unparent (parent clear can reset local→world).
    MESH._set_go_transform(go, slot.pose_x, slot.pose_y, slot.pose_z, wrot)
    MESH._force_world_visible(slot)
    return true
end

-- Read frozen world pose for a slot (nil if inactive).
function MESH.get_world_pose(id)
    local slot, sid = MESH._slot_of(id)
    if not slot.active or not MESH._managed_alive(slot.go) then return nil end
    local pos, rot = nil, nil
    pcall(function()
        local tf = slot.go:call("get_Transform")
        if not tf then return end
        pos = tf:call("get_Position")
        rot = tf:call("get_Rotation")
    end)
    if not pos then
        return {
            x = slot.pose_x, y = slot.pose_y, z = slot.pose_z,
            rw = 1.0, rx = 0.0, ry = 0.0, rz = 0.0,
        }
    end
    local out = {
        x = pos.x, y = pos.y, z = pos.z,
        rw = 1.0, rx = 0.0, ry = 0.0, rz = 0.0,
    }
    if rot then
        out.rw = rot.w or 1.0
        out.rx = rot.x or 0.0
        out.ry = rot.y or 0.0
        out.rz = rot.z or 0.0
    end
    return out
end

-- Re-pin an existing floor mag at a cached world pose. Never parents to player.
function MESH.freeze_world_pose(id, pose)
    local slot, sid = MESH._slot_of(id)
    if not slot.active or not MESH._managed_alive(slot.go) then return false end
    if type(pose) ~= "table" or type(pose.x) ~= "number" then return false end
    MESH._unparent_go(slot.go)
    local rot = nil
    if pose.rw ~= nil then
        rot = { w = pose.rw, x = pose.rx or 0.0, y = pose.ry or 0.0, z = pose.rz or 0.0 }
    end
    slot.pose_x, slot.pose_y, slot.pose_z = pose.x, pose.y, pose.z
    local ok = MESH._set_go_transform(slot.go, pose.x, pose.y, pose.z, rot)
    MESH._force_world_visible(slot)
    return ok
end

-- Explicit visibility refresh for parked floor mags (never touches weapon joints).
function MESH.force_visible(id)
    local slot = MESH._slot_of(id)
    if not slot.active or not MESH._managed_alive(slot.go) then return false end
    return MESH._force_world_visible(slot) == true
end

-- set_pose([id], wpos, wrot)
function MESH.set_pose(a, b, c)
    local id, wpos, wrot
    if type(a) == "string" and type(b) == "table" then
        id, wpos, wrot = a, b, c
    else
        id, wpos, wrot = MESH.CURRENT_ID, a, b
    end
    local slot = MESH._slot_of(id)
    if not slot.active or not slot.go then return false end
    if not wpos then return false end
    local off_x = tonumber(MESH._cfg("offset_x", 0.0)) or 0.0
    local off_y = tonumber(MESH._cfg("offset_y", 0.0)) or 0.0
    local off_z = tonumber(MESH._cfg("offset_z", 0.0)) or 0.0
    slot.pose_x = wpos.x + off_x
    slot.pose_y = wpos.y + off_y
    slot.pose_z = wpos.z + off_z
    return MESH._set_go_transform(slot.go, slot.pose_x, slot.pose_y, slot.pose_z, wrot)
end

function MESH.reapply_offset()
    local slot = MESH._slot_of(MESH.CURRENT_ID)
    if not slot.active or not slot.go then return end
    MESH._set_go_transform(slot.go, slot.pose_x, slot.pose_y, slot.pose_z, nil)
end

-- is_active([id])
function MESH.is_active(id)
    local slot = MESH._slot_of(id or MESH.CURRENT_ID)
    return slot.active == true and MESH._managed_alive(slot.go)
end

function MESH.status(id)
    local slot = MESH._slot_of(id or MESH.CURRENT_ID)
    local viewable, enabled, draw = nil, nil, nil
    if slot.mesh then
        pcall(function() viewable = slot.mesh:call("get_Viewable") == true end)
        pcall(function() enabled = slot.mesh:call("get_Enabled") == true end)
        pcall(function() draw = slot.mesh:call("get_DrawDefault") == true end)
    end
    return {
        id = MESH._norm_id(id or MESH.CURRENT_ID),
        active = slot.active == true,
        go_valid = MESH._managed_alive(slot.go),
        material_count = slot.material_count or 0,
        material_names = slot.material_names or {},
        chosen_index = slot.chosen_index,
        part_count = slot.part_count or 0,
        chosen_part = slot.chosen_part or -1,
        last_error = slot.last_error or "",
        held_refs = #slot.held_refs,
        viewable = viewable == true,
        enabled = enabled == true,
        draw = draw == true,
        pose = { x = slot.pose_x, y = slot.pose_y, z = slot.pose_z },
    }
end

return M
