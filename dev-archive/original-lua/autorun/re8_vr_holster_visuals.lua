-- Holster mesh visuals (hip pistol, left-chest knife, right-chest medicine).
-- Spawns visual mesh clones that follow holster-published grab zones.
-- Also keeps the glasses scope overlay in front of the view.
-- Deferred init: autorun may load before re8vr / vrmod exist.

if reframework:get_game_name() ~= "re8" then
    return {}
end

local GameObject = nil
pcall(function() GameObject = require("utility/GameObject") end)

local CFG_PATH = "re8_vr/re8_vr_holster.json"
local H = {}
local HIP = {}
local KNIFE = {}
local MED = {}
local RET = {}
local mk = { gameobj = nil, folder = nil }


pcall(function()
    local td = sdk.find_type_definition("via.GameObject")
    if td then
        mk.gameobj = td:get_method("create(System.String)")
        mk.folder = td:get_method("create(System.String, via.Folder)")
    end
end)

--------------------------------------------------
-- Shared helpers
--------------------------------------------------

H.ID_MAP = {
}

function H.chris_skip_ignore_depth()
    local n = ""
    pcall(function()
        if re8vr and re8vr.player then
            n = tostring(re8vr.player:call("get_Name") or "")
        end
    end)
    n = string.lower(n)
    return n:find("pl2001", 1, true) ~= nil
end

function H.get_updater()
    if not re8vr or not re8vr.player or not H.managed_alive(re8vr.player) then return nil end
    local up = nil
    if GameObject and GameObject.get_component then
        pcall(function() up = GameObject.get_component(re8vr.player, "app.PlayerUpdaterFPS") end)
        if up then return up end
        pcall(function() up = GameObject.get_component(re8vr.player, "app.PlayerUpdaterPl2001") end)
        if up then return up end
    end
    pcall(function()
        up = re8vr.player:call("getComponent(System.Type)", sdk.typeof("app.PlayerUpdaterFPS"))
    end)
    if up then return up end
    pcall(function()
        up = re8vr.player:call("getComponent(System.Type)", sdk.typeof("app.PlayerUpdaterPl2001"))
    end)
    return up
end

H._joint_file = nil
function H.sync_slot_joints()
    if H._joint_file == nil then
        local data = nil
        pcall(function()
            data = json.load_file("re8_instructions/data/village_character_joints.json")
        end)
        H._joint_file = (type(data) == "table") and data or false
    end
    local data = H._joint_file
    if type(data) ~= "table" then return end
    local src = H.chris_skip_ignore_depth() and data.chris or data.ethan
    if type(src) ~= "table" then src = data.ethan end
    if type(src) ~= "table" then return end
    if type(src.hip) == "table" and #src.hip > 0 and HIP.joints then
        HIP.joints = src.hip
    end
    if type(src.chest) == "table" and #src.chest > 0 and KNIFE.joints then
        KNIFE.joints = src.chest
    end
    if type(src.medicine) == "table" and #src.medicine > 0 and MED.joints then
        MED.joints = src.medicine
    end
end

function H.safe_call(obj, m, ...)
    if not obj then return nil end
    local ok, a, b, c = pcall(function(...) return obj:call(m, ...) end, ...)
    if not ok then return nil end
    return a, b, c
end

function H.managed_alive(obj)
    if not obj then return false end
    if sdk.is_valid_obj then
        local okv, valid = pcall(function() return sdk.is_valid_obj(obj) end)
        if okv and valid == false then return false end
    end
    local ok, addr = pcall(function() return obj:get_address() end)
    if not ok or addr == nil or addr == 0 then return false end
    local ok2, td = pcall(function() return obj:get_type_definition() end)
    return ok2 and td ~= nil
end

function H.normalize_item_id(id)
    if type(id) ~= "string" then return nil end
    id = id:gsub("^%s+", ""):gsub("%s+$", "")
    if id == "" then return nil end
    -- Inventory GO names are ri####_Inventory; keep the ri#### id.
    id = id:gsub("_Inventory$", ""):gsub("_Equipped$", "")
    return id
end

function H.item_game_object(core)
    if not core or not H.managed_alive(core) then return nil end
    local go = H.safe_call(core, "get_GameObject")
    if go and H.managed_alive(go) then return go end
    go = H.safe_call(core, "get_owner")
    if not go then
        pcall(function() go = core:get_field("<owner>k__BackingField") end)
    end
    if go and H.managed_alive(go) then return go end
    return nil
end

function H.weapon_usable(weapon)
    local fn = rawget(_G, "__re8_weapon_component_usable")
    if type(fn) == "function" then return fn(weapon) == true end
    if not weapon or not H.managed_alive(weapon) then return false end
    return H.item_game_object(weapon) ~= nil
end

function H.weapon_type(item_id)
    item_id = H.normalize_item_id(item_id)
    if not item_id then return nil end
    local m = rawget(_G, "__re8_holster_weapon_type")
    if type(m) == "table" and m[item_id] then return m[item_id] end
    -- Village meds only (RE8VR.cpp): ri1020 First Aid, ri1021, ri1022 syringe.
    if item_id == "ri1020" or item_id == "ri1021" or item_id == "ri1022" then return "MED" end
    if item_id:find("Handgun", 1, true) or item_id:find("Magnum", 1, true) then return "HG" end
    if item_id:find("Shotgun", 1, true) or item_id:find("Sniper", 1, true) then return "SG" end
    if item_id:find("Knife", 1, true) then return "KNF" end
    if item_id:find("Medicine", 1, true) or item_id:find("Herb", 1, true) then return "MED" end
    return nil
end

function H.read_system_string(s)
    if s == nil then return nil end
    if type(s) == "string" then return s end
    local ok, v = pcall(function() return s:gsub("%z.*", "") end)
    if ok and type(v) == "string" and v ~= "" then return v end
    ok, v = pcall(function()
        if s.call then return tostring(s:call("ToString")) end
        return tostring(s)
    end)
    if ok and type(v) == "string" then
        v = v:gsub("%z.*", "")
        if v ~= "" and not v:find("REManagedObject", 1, true) then return v end
    end
    return nil
end

function H.vec3_normalize(v)
    if not v then return nil end
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if not len or len < 1e-8 then return nil end
    return { x = v.x / len, y = v.y / len, z = v.z / len }
end

function H.vec3_dist(a, b)
    if not a or not b then return -1 end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function H.get_player_transform()
    if re8vr and re8vr.transform then return re8vr.transform end
    if re8vr and re8vr.player then
        local tf = nil
        pcall(function() tf = re8vr.player:call("get_Transform") end)
        return tf
    end
    return nil
end

function H.get_right_hand_world()
    if re8vr and re8vr.last_right_hand_position
        and type(re8vr.last_right_hand_position.x) == "number" then
        return re8vr.last_right_hand_position
    end
    local w = rawget(_G, "__vr_rh_world")
    if w and type(w.x) == "number" then return w end
    return nil
end

function H.body_axes()
    local tf = H.get_player_transform()
    if not tf then return nil end
    local rot = nil
    pcall(function() rot = tf:call("get_Rotation") end)
    if not rot then return nil end
    local right, up, fwd = nil, nil, nil
    pcall(function()
        local rv = rot * Vector3f.new(1, 0, 0)
        local uv = rot * Vector3f.new(0, 1, 0)
        local fv = rot * Vector3f.new(0, 0, 1)
        right = H.vec3_normalize({ x = rv.x, y = rv.y, z = rv.z })
        up = H.vec3_normalize({ x = uv.x, y = uv.y, z = uv.z })
        fwd = H.vec3_normalize({ x = fv.x, y = fv.y, z = fv.z })
    end)
    if not right or not up or not fwd then return nil end
    return right, up, fwd
end

function H.profile_key()
    local key = "default"
    pcall(function()
        if re8vr and re8vr.player then
            local n = tostring(re8vr.player:call("get_Name") or ""):lower()
            if n:find("pl2001", 1, true) or n:find("chris", 1, true) then
                key = "chris"
            end
        end
    end)
    return key
end

function H.visual_blob(data, new_key, old_key)
    if type(data) ~= "table" then return nil end
    local v = data[new_key]
    if type(v) ~= "table" then v = data[old_key] end
    return (type(v) == "table") and v or nil
end

function H.apply_visual_offsets(cfg, visual)
    if type(visual) ~= "table" then return end
    cfg.scale = tonumber(visual.scale) or cfg.scale
    cfg.rot_yaw = tonumber(visual.rot_yaw) or cfg.rot_yaw
    cfg.rot_pitch = tonumber(visual.rot_pitch) or cfg.rot_pitch
    cfg.rot_roll = tonumber(visual.rot_roll) or cfg.rot_roll
    cfg.mesh_off_right = tonumber(visual.mesh_off_right) or cfg.mesh_off_right
    cfg.mesh_off_up = tonumber(visual.mesh_off_up) or cfg.mesh_off_up
    cfg.mesh_off_forward = tonumber(visual.mesh_off_forward) or cfg.mesh_off_forward
end

function H.published_zone(key)
    local pub = rawget(_G, key)
    if not pub or type(pub.x) ~= "number" or type(pub.t) ~= "number" then return nil end
    if (os.clock() - pub.t) >= 0.5 then return nil end
    local pos = { x = pub.x, y = pub.y, z = pub.z }
    local right, up, fwd = nil, nil, nil
    if type(pub.rx) == "number" then right = { x = pub.rx, y = pub.ry, z = pub.rz } end
    if type(pub.ux) == "number" then up = { x = pub.ux, y = pub.uy, z = pub.uz } end
    if type(pub.fx) == "number" then fwd = { x = pub.fx, y = pub.fy, z = pub.fz } end
    return pos, right, up, fwd
end

function H.collect_upper_transforms()
    local out = {}
    local seen = {}
    local function add(tf, src)
        if not tf then return end
        local addr = nil
        pcall(function() addr = tf:get_address() end)
        local key = addr or tostring(tf)
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { tf = tf, src = src or "?" }
    end
    add(H.get_player_transform(), "player")
    if re8vr and re8vr.player then
        add(H.safe_call(re8vr.player, "get_Transform"), "player_go")
        local mc = nil
        pcall(function()
            local up = H.get_updater()
            if up then mc = up:call("get_playerMeshController") end
        end)
        if not mc then
            pcall(function()
                if GameObject and GameObject.get_component then
                    mc = GameObject.get_component(re8vr.player, "app.PlayerMeshController")
                end
            end)
        end
        if not mc then
            pcall(function()
                mc = re8vr.player:call("getComponent(System.Type)", sdk.typeof("app.PlayerMeshController"))
            end)
        end
        if mc then
            for _, field in ipairs({ "UpperBodyMesh", "LowerBodyMesh", "LArmMesh", "RArmMesh" }) do
                local mesh = nil
                pcall(function() mesh = mc:get_field(field) end)
                if mesh then
                    local go = H.safe_call(mesh, "get_GameObject")
                    add(go and H.safe_call(go, "get_Transform"), field)
                end
            end
        end
    end
    return out
end

function H.resolve_item_internal(entry)
    if not entry then return nil end
    local ok, td = pcall(function() return entry:get_type_definition() end)
    if ok and td then
        local ok2, is_item = pcall(function() return td:is_a("app.ItemCore") end)
        if ok2 and is_item then return entry end
    end
    for _, field in ipairs({ "Item", "<Item>k__BackingField", "<item>k__BackingField", "_Item", "_item" }) do
        local ok3, item = pcall(function() return entry:get_field(field) end)
        if ok3 and item then return item end
    end
    return entry
end

function H.get_item_data_id(item_internal)
    if not item_internal then return nil end
    local n = H.safe_call(item_internal, "get_weaponName")
    if type(n) == "string" and n ~= "" then return H.normalize_item_id(n) end
    local owner = H.safe_call(item_internal, "get_owner")
    if not owner then
        pcall(function() owner = item_internal:get_field("<owner>k__BackingField") end)
    end
    if owner then
        local gn = H.safe_call(owner, "get_Name")
        if type(gn) == "string" and gn ~= "" then return H.normalize_item_id(gn) end
    end
    local work = nil
    pcall(function() work = item_internal:call("get_work") end)
    if work then
        local id = nil
        pcall(function() id = work:get_field("ItemID") end)
        if id ~= nil then return H.normalize_item_id(tostring(id)) end
    end
    return nil
end

function H.get_item_weapon(item_internal)
    if not item_internal then return nil end
    local ok, td = pcall(function() return item_internal:get_type_definition() end)
    if ok and td then
        local ok_w, is_w = pcall(function() return td:is_a("app.WeaponCore") end)
        if ok_w and is_w then return item_internal end
        local ok_m, is_m = pcall(function() return td:is_a("app.ItemCore") end)
        if ok_m and is_m then return item_internal end
    end
    return item_internal
end

function H.inventory_rows()
    local out = {}
    local inv = re8vr and re8vr.inventory or nil
    if not inv or not H.managed_alive(inv) then
        local im = sdk.get_managed_singleton("app.InventoryManager")
        if im then
            pcall(function() inv = im:call("get_activeInventory") end)
        end
    end
    if not inv or not H.managed_alive(inv) then return out end
    local items_list = nil
    pcall(function() items_list = inv:call("get_items") end)
    if not items_list then
        pcall(function() items_list = inv:get_field("<items>k__BackingField") end)
    end
    if not items_list then return out end
    local items = nil
    pcall(function() items = items_list:get_field("mItems") end)
    if not items then
        pcall(function() items = items_list:get_field("_items") end)
    end
    -- Prefer List.Count (live items). mItems Length is capacity and can hide late slots.
    local size = 0
    local list_indexed = false
    pcall(function() size = items_list:call("get_Count") end)
    if type(size) == "number" and size > 0 then
        list_indexed = true
    elseif items then
        size = 0
        pcall(function() size = items:get_size() end)
        if not size or size <= 0 then
            pcall(function() size = items:size() end)
        end
    end
    if not size or size <= 0 then return out end
    for i = 0, size - 1 do
        local entry = nil
        if list_indexed then
            pcall(function() entry = items_list:call("get_Item", i) end)
        else
            pcall(function() entry = items:get_element(i) end)
        end
        if entry then
            local item_internal = H.resolve_item_internal(entry)
            local item_id = H.get_item_data_id(item_internal)
            local weapon = H.get_item_weapon(item_internal)
            if item_internal and item_id then
                out[#out + 1] = {
                    item_internal = item_internal,
                    item_id = item_id,
                    weapon = weapon,
                }
            end
        end
    end
    return out
end

function H.find_row_for_item_id(item_id)
    item_id = H.normalize_item_id(item_id)
    if not item_id then return nil end
    for _, row in ipairs(H.inventory_rows()) do
        if H.normalize_item_id(row.item_id) == item_id then return row end
    end
    for _, row in ipairs(H.inventory_rows()) do
        local w = row.weapon
        if w and H.weapon_usable(w) then
            local go_name = nil
            pcall(function()
                local go = w:call("get_GameObject")
                if go then go_name = go:call("get_Name") end
            end)
            if go_name and type(go_name) == "string" then
                if go_name == item_id or H.normalize_item_id(go_name) == item_id then
                    return row
                end
            end
        end
    end
    return nil
end

function H.holster_should_hide(st_item)
    if not st_item or st_item == "" then return false end
    local want = H.normalize_item_id(st_item)
    if not want then return false end
    local function match(id)
        id = H.normalize_item_id(id)
        if not id or id == "" or id == "Hand" then return false end
        if id == want then return true end
        if HIP.same_weapon and HIP.same_weapon(id, want) then return true end
        return false
    end
    if match(rawget(_G, "__re8_active_wmo_id")) then return true end
    if match(rawget(_G, "__re8_active_weapon_id")) then return true end
    -- Fallback only when holster hasn't published an armed id yet this frame.
    local pub = tostring(rawget(_G, "__re8_active_weapon_id") or "")
    if pub ~= "" and pub ~= "Hand" then return false end
    if match(H.current_equipped_item_id()) then return true end
    return false
end

function H.current_equipped_item_id()
    local id = nil
    if re8vr and re8vr.weapon and H.managed_alive(re8vr.weapon) then
        local go_name = nil
        pcall(function()
            local go = re8vr.weapon:call("get_GameObject")
            if go then go_name = go:call("get_Name") end
        end)
        if go_name then id = H.normalize_item_id(go_name) end
    end
    if not id and re8vr and re8vr.player then
        local em = nil
        pcall(function()
            local up = H.get_updater()
            if up then em = up:call("get_equipController") end
        end)
        if not em and GameObject then
            pcall(function()
                em = GameObject.get_component(re8vr.player, "app.EquipController")
            end)
        end
        if em then
            pcall(function()
                local w = em:call("get_equipWeaponRight")
                if not w then w = em:call("currentPlayerWeapon") end
                if w then
                    local go = w:call("get_GameObject")
                    if go then
                        id = H.normalize_item_id(go:call("get_Name"))
                    end
                end
                if not id then
                    local s = em:call("currentPlayerWeaponId")
                    id = H.normalize_item_id(H.read_system_string(s) or tostring(s or ""))
                end
            end)
        end
    end
    return id
end

function H.get_weapon_mesh_component(weapon)
    if not weapon or not H.managed_alive(weapon) then return nil end
    local mesh = nil
    pcall(function() mesh = weapon:get_field("Mesh") end)
    if mesh and H.managed_alive(mesh) then return mesh end
    local go = H.item_game_object(weapon)
    -- Do not call setActive on inventory items here (AV risk on MedicineCore).
    if go and GameObject then
        local ok, c = pcall(function() return GameObject.get_component(go, "via.render.Mesh") end)
        if ok and c then mesh = c end
    end
    if not mesh and go then
        local td = sdk.find_type_definition("via.render.Mesh")
        if td then
            pcall(function() mesh = go:call("getComponent(System.Type)", td:get_runtime_type()) end)
        end
    end
    if mesh and H.managed_alive(mesh) then return mesh end
    return nil
end

function H.resource_path_from_obj(obj)
    if not obj then return nil end
    local path = nil
    for _, m in ipairs({ "get_Path", "get_ResourcePath", "getPath", "ToString" }) do
        pcall(function()
            local v = obj:call(m)
            local s = H.read_system_string(v)
            if s and s ~= "" and not s:find("REManagedObject", 1, true) then
                path = s
            end
        end)
        if path then break end
    end
    if not path then
        pcall(function()
            local v = obj:get_field("Path") or obj:get_field("_Path")
            path = H.read_system_string(v)
        end)
    end
    return path
end

function H.create_resource_raw(resource_path, resource_type)
    if type(resource_path) ~= "string" or resource_path == "" then return nil end
    if not sdk.create_resource then return nil end
    local path = resource_path:lower()
    path = path:match("^.+%[@?(.+)%]") or path
    local res = nil
    pcall(function()
        res = sdk.create_resource(resource_type, path)
        if res then res = res:add_ref() end
    end)
    return res
end

function H.derive_mdf_candidates(mesh_path, mdf_path)
    local out = {}
    local function add(p)
        if type(p) == "string" and p ~= "" then
            p = p:lower()
            p = p:match("^.+%[@?(.+)%]") or p
            for _, e in ipairs(out) do
                if e == p then return end
            end
            out[#out + 1] = p
        end
    end
    if type(mesh_path) == "string" and mesh_path ~= "" then
        add(mesh_path:gsub("%.mesh$", ".mdf2"))
        add(mesh_path:gsub("%.mesh$", ".mdf"))
    end
    add(mdf_path)
    return out
end

function H.get_mesh_resources_from_weapon(weapon)
    local mesh = H.get_weapon_mesh_component(weapon)
    if not mesh then return nil, nil, nil, nil end
    local mesh_res = nil
    pcall(function() mesh_res = mesh:call("getMesh") end)
    if not mesh_res then
        pcall(function() mesh_res = mesh:call("get_Mesh") end)
    end
    if not mesh_res then
        pcall(function() mesh_res = mesh:get_field("Mesh") end)
    end
    local mat = nil
    pcall(function() mat = mesh:call("get_Material") end)
    if not mat then
        pcall(function() mat = mesh:get_field("Material") end)
    end
    local mesh_path = H.resource_path_from_obj(mesh_res)
    if type(mesh_path) == "string" then
        mesh_path = mesh_path:lower()
        mesh_path = mesh_path:match("^.+%[@?(.+)%]") or mesh_path
    end
    local mdf_path = H.resource_path_from_obj(mat)
    if type(mdf_path) == "string" then
        mdf_path = mdf_path:lower()
        mdf_path = mdf_path:match("^.+%[@?(.+)%]") or mdf_path
    end
    return mesh_res, mat, mesh_path, mdf_path
end

function H.find_spawn_folder()
    local scene = nil
    pcall(function()
        local sm = sdk.get_native_singleton("via.SceneManager")
        if sm then
            scene = sdk.call_native_func(sm, sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        end
    end)
    if not scene then return nil end
    local folder = nil
    for _, name in ipairs({ "ModdedTemporaryObjects", "Debug", "Master" }) do
        pcall(function() folder = scene:call("findFolder", name) end)
        if folder then return folder end
    end
    return nil
end

function H.clear_mesh_depth_ignore(mesh, ignore_depth)
    if not mesh then return nil, nil end
    local before = nil
    pcall(function() before = mesh:call("get_IgnoreDepth") end)
    pcall(function() mesh:call("set_Enabled", true) end)
    pcall(function() mesh:call("set_DrawDefault", true) end)
    pcall(function() mesh:call("set_IgnoreDepth", ignore_depth == true) end)
    pcall(function() mesh:call("set_IgnoreDepthTransparentCorrection", ignore_depth == true) end)
    pcall(function() mesh:call("set_IgnoreDepthStencilValueWrite", false) end)
    pcall(function() mesh:call("set_MaskIgnoreDepthMesh", false) end)
    pcall(function() mesh:call("set_ForceAlphaTest", false) end)
    pcall(function() mesh:call("set_TransparentBias", 0.0) end)
    local after = nil
    pcall(function() after = mesh:call("get_IgnoreDepth") end)
    return before == true, after == true
end

function H.get_player_mesh_controller()
    if not re8vr or not re8vr.player then return nil end
    local mc = nil
    pcall(function()
        local go = re8vr.player:call("get_GameObject")
        if go and GameObject then
            mc = GameObject.get_component(go, "app.PlayerMeshController")
        end
    end)
    if not mc then
        pcall(function() mc = re8vr.player:call("getComponent(System.Type)",
            sdk.find_type_definition("app.PlayerMeshController"):get_runtime_type()) end)
    end
    return mc
end

function H.destroy(slot)
    local st = slot.st
    if st.go and H.managed_alive(st.go) then
        pcall(function() st.go:call("setActive", false) end)
        pcall(function() st.go:call("set_DrawSelf", false) end)
        pcall(function() st.go:call("destroy", st.go) end)
    end
    st.go = nil
    st.xform = nil
    st.mesh = nil
    st.visible = false
    st.aabb_ext = nil
end

function H.set_visible(slot, vis)
    local st = slot.st
    local want = vis == true
    if st.visible == want and st.go and H.managed_alive(st.go) then
        return
    end
    st.visible = want
    if not st.go or not H.managed_alive(st.go) then return end
    pcall(function() st.go:call("setActive", st.visible) end)
    pcall(function() st.go:call("set_DrawSelf", st.visible) end)
    pcall(function() st.go:call("set_UpdateSelf", st.visible) end)
end

function H.apply_mesh_depth_priority(slot, mesh, reason)
    if not mesh then return false end
    -- Throttle tick reasserts; spawn/fly/in_hand still apply immediately.
    if reason == "tick" then
        local st = slot.st
        local now = os.clock()
        if (now - (st.depth_tick_t or 0)) < 0.20 then
            return false
        end
        st.depth_tick_t = now
    end
    local cfg = slot.cfg
    local st = slot.st
    local always = cfg.depth_always_on_top == true
    local chris = H.chris_skip_ignore_depth() == true
    local ignore = always == true
    -- Chris longarm, bare, and grenade/utility: parked holsters depth-test so
    -- the torso occludes them. Hip/knife while those are equipped stay as before.
    if chris and rawget(_G, "__re8_chris_occlude_holsters") == true then
        ignore = false
    end
    local held = reason == "in_hand" or reason == "fly"
        or (rawget(_G, "__re8_medicine_in_hand") == true
            and (slot.go_name or "") == "VR_MedicineHolsterMesh")
    -- Chris in-hand/fly (syringe) must depth-test vs gloves, not IgnoreDepth.
    if chris and held then
        ignore = false
    end
    local before, after = H.clear_mesh_depth_ignore(mesh, ignore)

    local arm_r_before, arm_r_after = nil, nil
    local arm_l_before, arm_l_after = nil, nil
    local mc_ignore_before, mc_ignore_after = nil, nil
    if cfg.depth_fix_arm == true then
        local mc = H.get_player_mesh_controller()
        if mc then
            pcall(function() mc_ignore_before = mc:get_field("IgnoreDepth") end)
            pcall(function() mc:set_field("IgnoreDepth", false) end)
            pcall(function() mc_ignore_after = mc:get_field("IgnoreDepth") end)
            local rarm, larm = nil, nil
            pcall(function() rarm = mc:get_field("RArmMesh") end)
            pcall(function() larm = mc:get_field("LArmMesh") end)
            arm_r_before, arm_r_after = H.clear_mesh_depth_ignore(rarm, false)
            arm_l_before, arm_l_after = H.clear_mesh_depth_ignore(larm, false)
        end
    end

    st.depth_last = {
        reason = reason or "",
        always = always,
        occlude = held ~= true,
        ignore_set = ignore,
        ignore_before = before == true,
        ignore_after = after == true,
        arm_r_before = arm_r_before == true,
        arm_r_after = arm_r_after == true,
        arm_l_before = arm_l_before == true,
        arm_l_after = arm_l_after == true,
        mc_ignore_before = mc_ignore_before == true,
        mc_ignore_after = mc_ignore_after == true,
        fix_arm = cfg.depth_fix_arm == true,
        held = held == true,
        t = os.clock(),
    }
    return true
end

function H.fill_mesh_world_aabb(slot, pub, mesh_comp)
    if type(pub) ~= "table" or not mesh_comp then return end
    local cfg = slot.cfg
    local st = slot.st
    local sc = tonumber(cfg.scale) or 1.0
    if sc < 0.05 then sc = 1.0 end
    local src = "none"
    local lex, ley, lez = 0, 0, 0
    local lox, loy, loz = 0, 0, 0
    local wex, wey, wez = 0, 0, 0
    local wcx, wcy, wcz = nil, nil, nil
    local use_cache = slot.aabb_cache == true
    local cache = st.aabb_ext
    local now = os.clock()
    local refresh = (not use_cache) or (not cache) or cache.mesh ~= mesh_comp
        or cache.sc ~= sc or ((now - (cache.t or 0)) > 1.0)
    if refresh then
        pcall(function()
            mesh_comp:call("updateBoundingBox")
            local la = mesh_comp:call("get_ModelLocalAABB")
            if la then
                local mn = la:get_field("minpos")
                local mx = la:get_field("maxpos")
                if mn and mx and type(mn.x) == "number" and type(mx.x) == "number" then
                    lex = math.abs(mx.x - mn.x) * 0.5 * sc
                    ley = math.abs(mx.y - mn.y) * 0.5 * sc
                    lez = math.abs(mx.z - mn.z) * 0.5 * sc
                    lox = (mn.x + mx.x) * 0.5
                    loy = (mn.y + mx.y) * 0.5
                    loz = (mn.z + mx.z) * 0.5
                    src = "local"
                end
            end
            local wa = mesh_comp:call("get_WorldAABB")
            if wa then
                local mn = wa:get_field("minpos")
                local mx = wa:get_field("maxpos")
                if mn and mx and type(mn.x) == "number" and type(mx.x) == "number" then
                    wcx = (mn.x + mx.x) * 0.5
                    wcy = (mn.y + mx.y) * 0.5
                    wcz = (mn.z + mx.z) * 0.5
                    wex = math.abs(mx.x - mn.x) * 0.5
                    wey = math.abs(mx.y - mn.y) * 0.5
                    wez = math.abs(mx.z - mn.z) * 0.5
                    if src == "none" then src = "world" end
                end
            end
        end)
        if use_cache then
            st.aabb_ext = {
                mesh = mesh_comp, sc = sc, t = now, src = src,
                lex = lex, ley = ley, lez = lez,
                lox = lox, loy = loy, loz = loz,
                wex = wex, wey = wey, wez = wez,
            }
        end
    else
        src = cache.src or "local"
        lex, ley, lez = cache.lex, cache.ley, cache.lez
        lox, loy, loz = cache.lox, cache.loy, cache.loz
        wex, wey, wez = cache.wex, cache.wey, cache.wez
    end
    local ldiag = math.sqrt(lex * lex + ley * ley + lez * lez)
    local wdiag = math.sqrt(wex * wex + wey * wey + wez * wez)
    local has_quat = type(pub.qw) == "number"
    if ldiag >= 0.04 and has_quat then
        pub.ex = math.max(0.02, lex)
        pub.ey = math.max(0.02, ley)
        pub.ez = math.max(0.02, lez)
        pub.r = ldiag
        pub.obb = true
        src = "local_obb"
    elseif wdiag >= 0.04 then
        pub.ex, pub.ey, pub.ez = wex, wey, wez
        pub.r = wdiag
        pub.obb = false
        src = "world"
    elseif ldiag >= 0.04 then
        pub.ex = math.max(0.02, lex)
        pub.ey = math.max(0.02, ley)
        pub.ez = math.max(0.02, lez)
        pub.r = ldiag
        pub.obb = false
        src = "local"
    else
        pub.ex, pub.ey, pub.ez = 0.06, 0.06, 0.10
        pub.r = 0.12
        pub.obb = false
        src = "floor"
    end
    pub.aabb_src = src
    pub.lcx, pub.lcy, pub.lcz = lex, ley, lez
    pub.lox, pub.loy, pub.loz = lox, loy, loz
    if type(wcx) == "number" then
        pub.wcx, pub.wcy, pub.wcz = wcx, wcy, wcz
    end

    local applied = false
    if slot.aabb_mode == "medicine" then
        local gx, gy, gz = pub.x, pub.y, pub.z
        if src == "world" and type(wcx) == "number" then
            gx, gy, gz = wcx, wcy, wcz
            applied = true
        elseif src ~= "none" and src ~= "floor" and type(pub.x) == "number" then
            local cd = lox * lox + loy * loy + loz * loz
            if cd > 0.0001 then
                local rot = slot.world_rot()
                if rot then
                    pcall(function()
                        local wo = rot * Vector3f.new(lox, loy, loz)
                        if wo and type(wo.x) == "number" then
                            gx = pub.x + wo.x
                            gy = pub.y + wo.y
                            gz = pub.z + wo.z
                            applied = true
                        end
                    end)
                end
            end
        end
        pub.chris_aabb_shift = applied
        if type(gx) == "number" then
            pub.cx, pub.cy, pub.cz = gx, gy, gz
        end
        return
    end

    -- Same as Ethan: leave pub.x on the visual pivot. Grab/stow OBB applies
    -- ModelLocalAABB in HJ.build_slot_grab_mesh. Mutating pub.x on Chris made
    -- the zone drift off the mesh while walking/turning.
    pub.chris_aabb_shift = false
    if type(pub.x) == "number" then
        pub.cx, pub.cy, pub.cz = pub.x, pub.y, pub.z
    end
end

function H.publish_mesh(slot, pub)
    H.fill_mesh_world_aabb(slot, pub, slot.st.mesh)
    rawset(_G, slot.mesh_g, pub)
end

function H.spawn_from_weapon(slot, weapon)
    H.destroy(slot)
    local st = slot.st
    if not mk.gameobj and not mk.folder then
        st.status = "no_create_api"
        return false
    end
    local mesh_res, mat, mesh_path, mdf_path = H.get_mesh_resources_from_weapon(weapon)
    if not mesh_res then
        st.status = "no_mesh_res"
        return false
    end

    local folder = H.find_spawn_folder()
    local go = nil
    pcall(function()
        if folder and mk.folder then
            go = mk.folder:call(nil, slot.go_name, folder)
        elseif mk.gameobj then
            go = mk.gameobj:call(nil, slot.go_name)
        end
    end)
    if not go then
        st.status = "create_failed"
        return false
    end
    pcall(function() go = go:add_ref() end)
    pcall(function() go:call(".ctor") end)

    local mesh_td = sdk.find_type_definition("via.render.Mesh")
    local mesh_comp = nil
    if mesh_td then
        pcall(function()
            mesh_comp = go:call("createComponent(System.Type)", mesh_td:get_runtime_type())
            if mesh_comp then
                mesh_comp = mesh_comp:add_ref()
                mesh_comp:call(".ctor()")
            end
        end)
    end
    if not mesh_comp then
        st.status = "mesh_comp_failed"
        pcall(function() go:call("destroy", go) end)
        return false
    end

    -- Share live Mesh holder first. Do not use EMV Holder write_qword (meshes stay invisible).
    local set_via = "none"
    local mat_via = "none"
    local ok_set = false
    local used_mdf = ""

    -- Inventory medicine mesh holders are often empty until equipped. Prefer path create
    -- for medicine so the chest clone has real geometry.
    local prefer_path = (slot == MED) and type(mesh_path) == "string" and mesh_path ~= ""
    if prefer_path then
        local created = H.create_resource_raw(mesh_path, "via.render.MeshResource")
        if created then
            ok_set = pcall(function() mesh_comp:call("setMesh", created) end)
            if ok_set then set_via = "create_raw" end
        end
    end
    if not ok_set then
        ok_set = pcall(function() mesh_comp:call("setMesh", mesh_res) end)
        if ok_set then set_via = "shared" end
    end
    if not ok_set and type(mesh_path) == "string" and mesh_path ~= "" then
        local created = H.create_resource_raw(mesh_path, "via.render.MeshResource")
        if created then
            ok_set = pcall(function() mesh_comp:call("setMesh", created) end)
            if ok_set then set_via = "create_raw" end
        end
    end
    -- Known Village First Aid Med path fallbacks when inventory Mesh has no Path yet.
    if not ok_set and slot == MED then
        local fallbacks = {
            "objectroot/setmodel/sm_item/sm_ri10/sm_ri1020/sm_ri1020.mesh",
            "objectroot/setmodel/sm_item/sm_ri1020/sm_ri1020.mesh",
            "item/ri1020/ri1020.mesh",
        }
        for _, fp in ipairs(fallbacks) do
            local created = H.create_resource_raw(fp, "via.render.MeshResource")
            if created then
                ok_set = pcall(function() mesh_comp:call("setMesh", created) end)
                if ok_set then
                    set_via = "fallback_path"
                    mesh_path = fp
                    break
                end
            end
        end
    end
    if not ok_set then
        st.status = "setMesh_failed"
        pcall(function() go:call("destroy", go) end)
        return false
    end

    local mat_ok = false
    if mat then
        mat_ok = pcall(function() mesh_comp:call("set_Material", mat) end)
        if mat_ok then
            mat_via = "shared"
            used_mdf = mdf_path or "(shared)"
        end
    end
    if not mat_ok then
        for _, cand in ipairs(H.derive_mdf_candidates(mesh_path, mdf_path)) do
            local mdf_res = H.create_resource_raw(cand, "via.render.MeshMaterialResource")
            if mdf_res then
                mat_ok = pcall(function() mesh_comp:call("set_Material", mdf_res) end)
                if mat_ok then
                    used_mdf = cand
                    mat_via = "create_raw"
                    break
                end
            end
        end
    end

    local mesh_after = nil
    local mat_after = nil
    local mat_after_path = ""
    local mat_num = -1
    pcall(function() mesh_after = mesh_comp:call("getMesh") end)
    pcall(function() mat_after = mesh_comp:call("get_Material") end)
    pcall(function() mat_num = mesh_comp:call("get_MaterialNum") or -1 end)
    if mat_after then
        mat_after_path = H.resource_path_from_obj(mat_after) or ""
    end

    pcall(function() mesh_comp:call("set_Enabled", true) end)
    pcall(function() go:call("setActive", true) end)
    pcall(function() go:call("set_DrawSelf", true) end)
    H.apply_mesh_depth_priority(slot, mesh_comp, "spawn")

    st.last_spawn = {
        set_via = set_via,
        mat_via = mat_via,
        mat_ok = mat_ok == true,
        has_mesh_after = mesh_after ~= nil,
        has_mat_after = mat_after ~= nil,
        mat_num = mat_num,
        mesh_path = mesh_path or "",
        used_mdf = used_mdf,
        mat_after_path = mat_after_path,
        src_mdf = mdf_path or "",
        has_src_mat = mat ~= nil,
    }

    local xform = H.safe_call(go, "get_Transform")
    local scale = tonumber(slot.cfg.scale) or 1.0
    if xform then
        pcall(function()
            xform:call("set_Scale", Vector3f.new(scale, scale, scale))
        end)
    end

    st.go = go
    st.xform = xform
    st.mesh = mesh_comp
    st.mesh_path = mesh_path or "(shared_resource)"
    st.mdf_path = used_mdf ~= "" and used_mdf or (mdf_path or "")
    st.status = mat_ok and "spawned" or "spawned_no_mat"
    H.set_visible(slot, true)
    return true
end

function H.rebuild_if_needed(slot, item_id)
    local st = slot.st
    item_id = H.normalize_item_id(item_id) or ""
    if item_id == "" then
        if st.item_id ~= "" then
            H.destroy(slot)
            st.item_id = ""
            st.status = "empty"
        end
        return
    end
    if item_id == st.item_id and st.go and H.managed_alive(st.go) then
        if not H.find_row_for_item_id(item_id) then
            H.destroy(slot)
            st.item_id = ""
            st.status = "empty"
        end
        return
    end
    local row = H.find_row_for_item_id(item_id)
    if not row or not row.weapon or not H.weapon_usable(row.weapon) then
        if st.item_id ~= "" or (st.go and H.managed_alive(st.go)) then
            H.destroy(slot)
            st.item_id = ""
            st.status = "empty"
        else
            st.status = "weapon_missing"
        end
        return
    end
    if H.spawn_from_weapon(slot, row.weapon) then
        st.item_id = item_id
    end
end

function H.smooth_mesh_pos(slot, pos)
    local st = slot.st
    local fc = rawget(_G, "__re8_holster_follow_cfg")
    local smooth_on = type(fc) ~= "table" or fc.smooth_enabled ~= false
    local deadzone = 0.04
    local tau_fast = 0.05
    local tau_slow = 0.16
    local snap_m = 0.55
    if type(fc) == "table" then
        if fc.tight == true then
            deadzone = tonumber(fc.deadzone) or 0.008
            tau_fast = tonumber(fc.tau_fast) or 0.02
            tau_slow = tonumber(fc.tau_slow) or 0.035
        end
        snap_m = tonumber(fc.snap) or snap_m
    end
    if not smooth_on then
        st.mesh_sm = { x = pos.x, y = pos.y, z = pos.z }
        local tf = H.get_player_transform()
        if tf then
            pcall(function()
                local root = tf:call("get_Position")
                if root and type(root.x) == "number" then
                    st.mesh_sm_root = { x = root.x, y = root.y, z = root.z }
                end
            end)
        end
        st.mesh_sm_t = os.clock()
        return st.mesh_sm
    end
    local now = os.clock()
    local dt = now - (st.mesh_sm_t or now)
    if dt < 0 then dt = 0.016 end
    if dt > 0.1 then dt = 0.1 end
    st.mesh_sm_t = now
    local root = nil
    local tf = H.get_player_transform()
    if tf then pcall(function() root = tf:call("get_Position") end) end
    local S = st.mesh_sm
    if not S then
        S = { x = pos.x, y = pos.y, z = pos.z }
    else
        if root and st.mesh_sm_root and type(root.x) == "number" then
            S.x = S.x + (root.x - st.mesh_sm_root.x)
            S.y = S.y + (root.y - st.mesh_sm_root.y)
            S.z = S.z + (root.z - st.mesh_sm_root.z)
        end
        local ex, ey, ez = pos.x - S.x, pos.y - S.y, pos.z - S.z
        local err = math.sqrt(ex * ex + ey * ey + ez * ez)
        if err > snap_m then
            S = { x = pos.x, y = pos.y, z = pos.z }
        else
            local tau_used = (err > deadzone) and tau_fast or tau_slow
            local a = 1 - math.exp(-dt / tau_used)
            S.x = S.x + ex * a
            S.y = S.y + ey * a
            S.z = S.z + ez * a
        end
    end
    st.mesh_sm = S
    if root and type(root.x) == "number" then
        st.mesh_sm_root = { x = root.x, y = root.y, z = root.z }
    end
    return S
end

function H.apply_xform(slot, pos, rot)
    local st = slot.st
    pcall(function()
        st.xform:call("set_Position", Vector3f.new(pos.x, pos.y, pos.z))
    end)
    if rot then
        pcall(function() st.xform:call("set_Rotation", rot) end)
    end
    local scale = tonumber(slot.cfg.scale) or 1.0
    pcall(function()
        st.xform:call("set_Scale", Vector3f.new(scale, scale, scale))
    end)
end

function H.publish_pose(slot, x, y, z, rot)
    local pub = { x = x, y = y, z = z, t = os.clock() }
    if rot then
        pcall(function()
            pub.qw, pub.qx, pub.qy, pub.qz = rot.w, rot.x, rot.y, rot.z
        end)
    end
    H.publish_mesh(slot, pub)
end

function H.try_fly(slot)
    local st = slot.st
    local fly = rawget(_G, "__re8_holster_fly")
    if not (fly and fly.active == true and fly.slot == slot.fly_slot and type(fly.x) == "number") then
        return false
    end
    H.set_visible(slot, true)
    pcall(function()
        st.xform:call("set_Position", Vector3f.new(fly.x, fly.y, fly.z))
    end)
    local rot = nil
    if slot.fly_use_pub_rot == true and type(fly.qw) == "number" then
        pcall(function()
            rot = Quaternion.new(fly.qw, fly.qx or 0, fly.qy or 0, fly.qz or 0)
        end)
    end
    if not rot then rot = slot.world_rot() end
    if rot then
        pcall(function() st.xform:call("set_Rotation", rot) end)
    end
    H.publish_pose(slot, fly.x, fly.y, fly.z, rot)
    st.mesh_sm = { x = fly.x, y = fly.y, z = fly.z }
    if slot.fly_depth == true then
        H.apply_mesh_depth_priority(slot, st.mesh, "fly")
    end
    return true
end

function H.try_bridge(slot)
    local st = slot.st
    local br = rawget(_G, "__re8_holster_fly_bridge")
    if not (br and br.slot == slot.fly_slot) then return false end
    if type(br.until_t) == "number" and os.clock() > br.until_t then
        rawset(_G, "__re8_holster_fly_bridge", nil)
        return false
    end
    if br.mode == "hide" then
        H.set_visible(slot, false)
        return true
    end
    if br.mode == "hold" and type(br.x) == "number" then
        H.set_visible(slot, true)
        pcall(function()
            st.xform:call("set_Position", Vector3f.new(br.x, br.y, br.z))
        end)
        local rot = slot.world_rot()
        if rot then
            pcall(function() st.xform:call("set_Rotation", rot) end)
        end
        st.mesh_sm = { x = br.x, y = br.y, z = br.z }
        H.publish_pose(slot, br.x, br.y, br.z, rot)
        return true
    end
    return false
end

function H.ensure_ready()
    if H.ready then return true end
    if not vrmod or not re8vr then return false end
    if not GameObject then
        pcall(function() GameObject = require("utility/GameObject") end)
    end
    H.ready = true
    if not H.load_logged then
        H.load_logged = true
        log.info("[re8_vr_holster_visuals] Ready — hip / knife / medicine meshes")
    end
    pcall(function() MED.init_rhp_poser() end)
    pcall(H.sync_slot_joints)
    return true
end

function H.scene_safe(slot)
    if not slot.cfg.enabled then return false end
    local flags = rawget(_G, "__re8_holster_slot_enabled")
    if type(flags) == "table" then
        if slot == HIP and flags.hip ~= true then return false end
        if slot == KNIFE and flags.knife ~= true then return false end
        if slot == MED and flags.medicine ~= true then return false end
    end
    if rawget(_G, "__vr_reloaded_master_enabled") == false then return false end
    if not re8vr or not re8vr.can_use_hands then return false end
    if re8vr.is_in_cutscene then return false end
    if re8vr.player and not H.managed_alive(re8vr.player) then return false end
    if re8vr.inventory and not H.managed_alive(re8vr.inventory) then return false end
    return true
end

function H.tick_slot(slot)
    if not H.ensure_ready() then return end
    if not H.scene_safe(slot) then
        H.set_visible(slot, false)
        return
    end
    H.rebuild_if_needed(slot, slot.poll())
    slot.update()
end

--------------------------------------------------
-- Hip
--------------------------------------------------

HIP.go_name = "VR_HipHolsterMesh"
HIP.fly_slot = "pistol"
HIP.zone_g = "__re8_hip_zone_world"
HIP.mesh_g = "__re8_hip_mesh_world"
HIP.json_new = "hip_visual"
HIP.json_old = "hip_probe_visual"
HIP.aabb_cache = true
HIP.aabb_mode = "chris"
HIP.joints = { "Hip" }
HIP.ids = {
}
HIP.cfg = {
    enabled = true,
    poll_s = 0.35,
    scale = 1.0,
    rot_yaw = 0.0,
    rot_pitch = 90.0,
    rot_roll = 0.0,
    mesh_off_right = 0.015,
    mesh_off_up = -0.03,
    mesh_off_forward = 0.40,
    depth_occlude = true,
    depth_always_on_top = true,
    depth_fix_arm = false,
    depth_normal_when_gun_held = false,
    depth_reassert = true,
}
HIP.st = {
    go = nil, xform = nil, mesh = nil, item_id = "", poll_item_id = "",
    mesh_path = "", mdf_path = "", visible = false, last_poll_t = 0,
    off_right = 0.0, off_up = 0.0, off_forward = 0.0, status = "waiting_deps",
    last_spawn = nil, joint = nil, joint_name = "",
    depth_last = nil, mesh_sm = nil, mesh_sm_t = 0, mesh_sm_root = nil,
}

function HIP.is_id(item_id)
    item_id = H.normalize_item_id(item_id)
    if not item_id then return false end
    if HIP.ids[item_id] then return true end
    local wtype = H.weapon_type(item_id)
    if wtype == "HG" or wtype == "MAG" then return true end
    if item_id:find("Handgun", 1, true) then return true end
    if item_id:find("Magnum", 1, true) then return true end
    return false
end

function HIP.same_weapon(a, b)
    a = H.normalize_item_id(a)
    b = H.normalize_item_id(b)
    if not a or not b or a == "" or b == "" then return false end
    if a == b then return true end
    if a:find("Magnum", 1, true) and b:find("Magnum", 1, true) then return true end
    if a:find("1140", 1, true) and b:find("1140", 1, true) then return true end
    return false
end

function HIP.refresh_joint()
    local st = HIP.st
    if st.joint then
        local pos = nil
        pcall(function() pos = st.joint:call("get_Position") end)
        if pos and type(pos.x) == "number" then return true end
        st.joint = nil
        st.joint_name = ""
    end
    local tf = H.get_player_transform()
    if not tf then return false end
    for _, name in ipairs(HIP.joints) do
        local j = nil
        pcall(function() j = tf:call("getJointByName", name) end)
        if j then
            local pos = nil
            pcall(function() pos = j:call("get_Position") end)
            if pos and type(pos.x) == "number" then
                st.joint = j
                st.joint_name = name
                return true
            end
        end
    end
    return false
end

function HIP.resolve_joint()
    if not HIP.refresh_joint() then return nil end
    local origin, ax, ay, az = nil, nil, nil, nil
    pcall(function() origin = HIP.st.joint:call("get_Position") end)
    pcall(function() ax = HIP.st.joint:call("get_AxisX") end)
    pcall(function() ay = HIP.st.joint:call("get_AxisY") end)
    pcall(function() az = HIP.st.joint:call("get_AxisZ") end)
    if not origin then return nil end
    return origin, ax, ay, az
end

function HIP.world_rot()
    local _, right, up, fwd = H.published_zone(HIP.zone_g)
    local bas = nil
    if right and up and fwd then
        pcall(function()
            bas = Matrix4x4f.new(
                right.x, right.y, right.z, 0,
                up.x, up.y, up.z, 0,
                fwd.x, fwd.y, fwd.z, 0,
                0, 0, 0, 1):to_quat()
        end)
    end
    if not bas and HIP.resolve_joint() then
        pcall(function()
            if HIP.st.joint then bas = HIP.st.joint:call("get_Rotation") end
        end)
    end
    local offset = nil
    pcall(function()
        offset = Quaternion.new(Vector3f.new(
            math.rad(HIP.cfg.rot_pitch or 0),
            math.rad(HIP.cfg.rot_yaw or 0),
            math.rad(HIP.cfg.rot_roll or 0)
        )):normalized()
    end)
    if bas and offset then
        local ok, q = pcall(function() return bas * offset end)
        if ok and q then return q end
    end
    return offset or bas
end

function HIP.zone_pos()
    local pos, right, up, fwd = H.published_zone(HIP.zone_g)
    if pos then
        return pos, right, up, fwd, pos
    end
    local origin, ax, ay, az = HIP.resolve_joint()
    if not origin then return nil end
    local r = HIP.st.off_right or 0
    local u = HIP.st.off_up or 0
    local f = HIP.st.off_forward or 0
    if ax and ay and az then
        return {
            x = origin.x + ax.x * r + ay.x * u + az.x * f,
            y = origin.y + ax.y * r + ay.y * u + az.y * f,
            z = origin.z + ax.z * r + ay.z * u + az.z * f,
        }, ax, ay, az, origin
    end
    return { x = origin.x, y = origin.y, z = origin.z }, nil, nil, nil, origin
end

function HIP.mesh_pos()
    local zone = HIP.zone_pos()
    if not zone then return nil end
    rawset(_G, "__re8_hip_visual_live", {
        mesh_off_right = HIP.cfg.mesh_off_right or 0,
        mesh_off_up = HIP.cfg.mesh_off_up or 0,
        mesh_off_forward = HIP.cfg.mesh_off_forward or 0,
        rot_yaw = HIP.cfg.rot_yaw or 0,
        rot_pitch = HIP.cfg.rot_pitch or 0,
        rot_roll = HIP.cfg.rot_roll or 0,
    })
    local lx = HIP.cfg.mesh_off_right or 0
    local ly = HIP.cfg.mesh_off_up or 0
    local lz = HIP.cfg.mesh_off_forward or 0
    if lx == 0 and ly == 0 and lz == 0 then return zone end
    local rot = HIP.world_rot()
    if rot then
        local wo = nil
        pcall(function() wo = rot * Vector3f.new(lx, ly, lz) end)
        if wo and type(wo.x) == "number" then
            return { x = zone.x + wo.x, y = zone.y + wo.y, z = zone.z + wo.z }
        end
    end
    local _, ax, ay, az = HIP.resolve_joint()
    if ax and ay and az then
        return {
            x = zone.x + ax.x * lx + ay.x * ly + az.x * lz,
            y = zone.y + ax.y * lx + ay.y * ly + az.y * lz,
            z = zone.z + ax.z * lx + ay.z * ly + az.z * lz,
        }
    end
    return zone
end

function HIP.first_inventory_id()
    for _, row in ipairs(H.inventory_rows()) do
        if HIP.is_id(row.item_id) then
            return H.normalize_item_id(row.item_id)
        end
    end
    return nil
end

function HIP.poll()
    local st = HIP.st
    local now = os.clock()
    if (now - (st.last_poll_t or 0)) < (HIP.cfg.poll_s or 0.35) then
        return st.poll_item_id or st.item_id
    end
    st.last_poll_t = now
    local item_id = nil
    local data = nil
    pcall(function() data = json.load_file(CFG_PATH) end)
    if type(data) == "table" and type(data.profiles) == "table" then
        H.apply_visual_offsets(HIP.cfg, H.visual_blob(data, HIP.json_new, HIP.json_old))
        local P = data.profiles[H.profile_key()]
        if type(P) ~= "table" then P = data.profiles.default or data.profiles["default"] end
        if type(P) == "table" then
            item_id = H.normalize_item_id(P.last_pistol_id)
            st.off_right = tonumber(P.hip_pistol_off_right) or 0
            st.off_up = tonumber(P.hip_pistol_off_up) or 0
            st.off_forward = tonumber(P.hip_pistol_off_forward) or 0
        end
    end
    local first_inv = HIP.first_inventory_id()
    if not item_id or item_id == "" then
        item_id = first_inv
    end
    local inv_has = false
    local hip_n = 0
    for _, row in ipairs(H.inventory_rows()) do
        if HIP.is_id(row.item_id) then
            hip_n = hip_n + 1
            if item_id and H.normalize_item_id(row.item_id) == H.normalize_item_id(item_id) then
                inv_has = true
            end
        end
    end
    if item_id and item_id ~= "" and not inv_has then
        item_id = first_inv
    end
    if hip_n == 0 then
        item_id = nil
    end
    st.poll_item_id = item_id or ""
    return item_id or ""
end

function HIP.update()
    local st = HIP.st
    if not st.go or not H.managed_alive(st.go) then return end
    if not st.xform or not H.managed_alive(st.xform) then
        st.xform = H.safe_call(st.go, "get_Transform")
    end
    if not st.xform then return end
    if H.try_fly(HIP) then return end
    if H.try_bridge(HIP) then return end
    rawset(_G, "__re8_hip_visual_live", {
        mesh_off_right = HIP.cfg.mesh_off_right or 0,
        mesh_off_up = HIP.cfg.mesh_off_up or 0,
        mesh_off_forward = HIP.cfg.mesh_off_forward or 0,
        rot_yaw = HIP.cfg.rot_yaw or 0,
        rot_pitch = HIP.cfg.rot_pitch or 0,
        rot_roll = HIP.cfg.rot_roll or 0,
    })
    -- When this slot's weapon is in-hand, skip joint/AABB work entirely.
    if st.item_id and st.item_id ~= "" and H.holster_should_hide(st.item_id) then
        H.set_visible(HIP, false)
        return
    end
    local pos = HIP.mesh_pos()
    if not pos then
        H.set_visible(HIP, false)
        return
    end
    H.set_visible(HIP, true)
    local rot = HIP.world_rot()
    if HIP.cfg.depth_reassert ~= false and st.mesh then
        H.apply_mesh_depth_priority(HIP, st.mesh, "tick")
    end
    pos = H.smooth_mesh_pos(HIP, pos)
    H.publish_pose(HIP, pos.x, pos.y, pos.z, rot)
    H.apply_xform(HIP, pos, rot)
end

--------------------------------------------------
-- Knife
--------------------------------------------------

KNIFE.go_name = "VR_KnifeHolsterMesh"
KNIFE.fly_slot = "knife"
KNIFE.zone_g = "__re8_knife_zone_world"
KNIFE.mesh_g = "__re8_knife_mesh_world"
KNIFE.json_new = "knife_visual"
KNIFE.json_old = "knife_probe_visual"
KNIFE.aabb_cache = true
KNIFE.aabb_mode = "chris"
KNIFE.joints = { "Spine_2", "L_Shoulder", "Spine_1" }
KNIFE.ids = {
}
KNIFE.cfg = {
    enabled = true,
    poll_s = 0.35,
    scale = 1.0,
    rot_yaw = 93.5,
    rot_pitch = -85.5,
    rot_roll = 0.0,
    mesh_off_right = 0.03,
    mesh_off_up = -0.05,
    mesh_off_forward = 0.0,
    depth_occlude = true,
    depth_always_on_top = true,
    depth_fix_arm = false,
    depth_normal_when_gun_held = false,
    depth_reassert = true,
}
KNIFE.st = {
    go = nil, xform = nil, mesh = nil, item_id = "", poll_item_id = "",
    mesh_path = "", mdf_path = "", visible = false, last_poll_t = 0,
    off_right = 0.0, off_up = 0.0, off_forward = 0.0, status = "waiting_deps",
    last_spawn = nil, joint = nil, joint_name = "",
    depth_last = nil, mesh_sm = nil, mesh_sm_t = 0, mesh_sm_root = nil,
}

function KNIFE.is_id(item_id)
    item_id = H.normalize_item_id(item_id)
    if not item_id then return false end
    if KNIFE.ids[item_id] then return true end
    if H.weapon_type(item_id) == "KNF" then return true end
    if item_id:find("Knife", 1, true) then return true end
    return false
end

function KNIFE.refresh_joint()
    local st = KNIFE.st
    local cached = st.joint_name or ""
    local is_fallback = cached:find("_fallback", 1, true) ~= nil
    local name_ok = false
    if cached ~= "" and not is_fallback then
        for _, want in ipairs(KNIFE.joints) do
            if want == cached then name_ok = true; break end
        end
    end
    if st.joint and name_ok then
        local pos = nil
        pcall(function() pos = st.joint:call("get_Position") end)
        if pos and type(pos.x) == "number" then return true end
    end
    st.joint = nil
    st.joint_name = ""
    local transforms = H.collect_upper_transforms()
    for _, entry in ipairs(transforms) do
        for _, name in ipairs(KNIFE.joints) do
            local j = nil
            pcall(function() j = entry.tf:call("getJointByName", name) end)
            if j then
                local pos = nil
                pcall(function() pos = j:call("get_Position") end)
                if pos and type(pos.x) == "number" then
                    st.joint = j
                    st.joint_name = name
                    return true
                end
            end
        end
    end
    for _, entry in ipairs(transforms) do
        for _, name in ipairs({ "Spine_2", "Spine_1", "Spine_0", "Hip" }) do
            local j = nil
            pcall(function() j = entry.tf:call("getJointByName", name) end)
            if j then
                local pos = nil
                pcall(function() pos = j:call("get_Position") end)
                if pos and type(pos.x) == "number" then
                    st.joint = j
                    st.joint_name = name .. "_fallback"
                    return true
                end
            end
        end
    end
    return false
end

function KNIFE.resolve_joint()
    if not KNIFE.refresh_joint() then return nil end
    local origin, ax, ay, az = nil, nil, nil, nil
    pcall(function() origin = KNIFE.st.joint:call("get_Position") end)
    pcall(function() ax = KNIFE.st.joint:call("get_AxisX") end)
    pcall(function() ay = KNIFE.st.joint:call("get_AxisY") end)
    pcall(function() az = KNIFE.st.joint:call("get_AxisZ") end)
    if not origin then return nil end
    return origin, ax, ay, az
end

function KNIFE.world_rot()
    local bas = nil
    local _, right, up, fwd = H.published_zone(KNIFE.zone_g)
    if right and up and fwd then
        pcall(function()
            bas = Matrix4x4f.new(
                right.x, right.y, right.z, 0,
                up.x, up.y, up.z, 0,
                fwd.x, fwd.y, fwd.z, 0,
                0, 0, 0, 1):to_quat()
        end)
    end
    if not bas then
        local tf = H.get_player_transform()
        if tf then pcall(function() bas = tf:call("get_Rotation") end) end
    end
    if not bas and KNIFE.st.joint then
        pcall(function() bas = KNIFE.st.joint:call("get_Rotation") end)
    end
    local offset = nil
    pcall(function()
        offset = Quaternion.new(Vector3f.new(
            math.rad(KNIFE.cfg.rot_pitch or 0),
            math.rad(KNIFE.cfg.rot_yaw or 0),
            math.rad(KNIFE.cfg.rot_roll or 0)
        )):normalized()
    end)
    if bas and offset then
        local ok, q = pcall(function() return bas * offset end)
        if ok and q then return q end
    end
    return offset or bas
end

function KNIFE.zone_pos()
    local pos, right, up, fwd = H.published_zone(KNIFE.zone_g)
    if pos then
        return pos, "torso_pub", right, up, fwd
    end
    local origin = KNIFE.resolve_joint()
    if not origin then return nil, "no_joint" end
    local r = KNIFE.st.off_right or 0
    local u = KNIFE.st.off_up or 0
    local f = KNIFE.st.off_forward or 0
    local br, bu, bf = H.body_axes()
    if br then
        return {
            x = origin.x + br.x * r + bu.x * u + bf.x * f,
            y = origin.y + br.y * r + bu.y * u + bf.y * f,
            z = origin.z + br.z * r + bu.z * u + bf.z * f,
        }, "fallback_body_axes", br, bu, bf
    end
    return { x = origin.x, y = origin.y, z = origin.z }, "joint_no_axes"
end

function KNIFE.mesh_pos()
    local zone, src, ax, ay, az = KNIFE.zone_pos()
    if not zone then return nil, src end
    rawset(_G, "__re8_knife_visual_live", {
        mesh_off_right = KNIFE.cfg.mesh_off_right or 0,
        mesh_off_up = KNIFE.cfg.mesh_off_up or 0,
        mesh_off_forward = KNIFE.cfg.mesh_off_forward or 0,
        rot_yaw = KNIFE.cfg.rot_yaw or 0,
        rot_pitch = KNIFE.cfg.rot_pitch or 0,
        rot_roll = KNIFE.cfg.rot_roll or 0,
    })
    local lx = KNIFE.cfg.mesh_off_right or 0
    local ly = KNIFE.cfg.mesh_off_up or 0
    local lz = KNIFE.cfg.mesh_off_forward or 0
    if lx == 0 and ly == 0 and lz == 0 then
        return zone, src, ax, ay, az
    end
    local rot = KNIFE.world_rot()
    if rot then
        local wo = nil
        pcall(function() wo = rot * Vector3f.new(lx, ly, lz) end)
        if wo and type(wo.x) == "number" then
            return {
                x = zone.x + wo.x, y = zone.y + wo.y, z = zone.z + wo.z,
            }, src, ax, ay, az
        end
    end
    if ax and ay and az then
        return {
            x = zone.x + ax.x * lx + ay.x * ly + az.x * lz,
            y = zone.y + ax.y * lx + ay.y * ly + az.y * lz,
            z = zone.z + ax.z * lx + ay.z * ly + az.z * lz,
        }, src, ax, ay, az
    end
    return zone, src, ax, ay, az
end

function KNIFE.first_inventory_id()
    for _, row in ipairs(H.inventory_rows()) do
        if KNIFE.is_id(row.item_id) then
            return H.normalize_item_id(row.item_id)
        end
    end
    return nil
end

function KNIFE.poll()
    local st = KNIFE.st
    local now = os.clock()
    if (now - (st.last_poll_t or 0)) < (KNIFE.cfg.poll_s or 0.35) then
        return st.poll_item_id or st.item_id
    end
    st.last_poll_t = now
    local item_id = nil
    local data = nil
    pcall(function() data = json.load_file(CFG_PATH) end)
    if type(data) == "table" and type(data.profiles) == "table" then
        H.apply_visual_offsets(KNIFE.cfg, H.visual_blob(data, KNIFE.json_new, KNIFE.json_old))
        local P = data.profiles[H.profile_key()]
        if type(P) ~= "table" then P = data.profiles.default or data.profiles["default"] end
        if type(P) == "table" then
            item_id = H.normalize_item_id(P.last_knife_id)
            st.off_right = tonumber(P.knife_off_x) or 0
            st.off_up = tonumber(P.knife_off_y) or 0
            st.off_forward = tonumber(P.knife_off_z) or 0
        end
    end
    if not item_id or item_id == "" then
        item_id = KNIFE.first_inventory_id()
    end
    local inv_has = false
    local knife_n = 0
    for _, row in ipairs(H.inventory_rows()) do
        if KNIFE.is_id(row.item_id) then
            knife_n = knife_n + 1
            if item_id and H.normalize_item_id(row.item_id) == H.normalize_item_id(item_id) then
                inv_has = true
            end
        end
    end
    if item_id and item_id ~= "" and not inv_has then
        item_id = KNIFE.first_inventory_id()
    end
    if knife_n == 0 then
        item_id = nil
    end
    st.poll_item_id = item_id or ""
    return item_id or ""
end

function KNIFE.update()
    local st = KNIFE.st
    if not st.go or not H.managed_alive(st.go) then return end
    if not st.xform or not H.managed_alive(st.xform) then
        st.xform = H.safe_call(st.go, "get_Transform")
    end
    if not st.xform then return end
    if H.try_fly(KNIFE) then return end
    if H.try_bridge(KNIFE) then return end
    rawset(_G, "__re8_knife_visual_live", {
        mesh_off_right = KNIFE.cfg.mesh_off_right or 0,
        mesh_off_up = KNIFE.cfg.mesh_off_up or 0,
        mesh_off_forward = KNIFE.cfg.mesh_off_forward or 0,
        rot_yaw = KNIFE.cfg.rot_yaw or 0,
        rot_pitch = KNIFE.cfg.rot_pitch or 0,
        rot_roll = KNIFE.cfg.rot_roll or 0,
    })
    if st.item_id and st.item_id ~= "" and H.holster_should_hide(st.item_id) then
        H.set_visible(KNIFE, false)
        return
    end
    local pos = KNIFE.mesh_pos()
    if not pos then
        H.set_visible(KNIFE, false)
        return
    end
    H.set_visible(KNIFE, true)
    local rot = KNIFE.world_rot()
    if KNIFE.cfg.depth_reassert ~= false and st.mesh then
        H.apply_mesh_depth_priority(KNIFE, st.mesh, "tick")
    end
    pos = H.smooth_mesh_pos(KNIFE, pos)
    H.publish_pose(KNIFE, pos.x, pos.y, pos.z, rot)
    H.apply_xform(KNIFE, pos, rot)
end

--------------------------------------------------
-- Medicine
--------------------------------------------------

MED.go_name = "VR_MedicineHolsterMesh"
MED.fly_slot = "medicine"
MED.zone_g = "__re8_medicine_zone_world"
MED.mesh_g = "__re8_medicine_mesh_world"
MED.json_new = "medicine_visual"
MED.json_old = "medicine_probe_visual"
MED.aabb_cache = false
MED.aabb_mode = "medicine"
MED.fly_use_pub_rot = true
MED.fly_depth = true
MED.joints = { "Spine_2", "R_Shoulder" }
MED.ids = { }
MED.cfg = {
    enabled = true,
    poll_s = 0.35,
    scale = 1.0,
    rot_yaw = 0.0,
    rot_pitch = 0.0,
    rot_roll = 0.0,
    mesh_off_right = 0.0,
    mesh_off_up = 0.0,
    mesh_off_forward = 0.0,
    hold_off_right = -0.095,
    hold_off_up = -0.065,
    hold_off_forward = -0.045,
    hold_by_item = {
        -- First Aid Med bottle (ri1020) in-hand hold defaults.
        default = { r = -0.095, u = -0.065, f = -0.045, yaw = -4.5, pitch = 77.5, roll = 0.0 },
        ri1020 = { r = -0.095, u = -0.065, f = -0.045, yaw = -4.5, pitch = 77.5, roll = 0.0 },
        ri1021 = { r = -0.095, u = -0.065, f = -0.045, yaw = -4.5, pitch = 77.5, roll = 0.0 },
    },
    hold_by_profile = {
        ethan = {
            default = { r = -0.0949999988079071, u = -0.06499999761581421, f = -0.04500000178813934, yaw = -4.5, pitch = 77.5, roll = 0.0 },
            ri1020 = { r = -0.0949999988079071, u = -0.06499999761581421, f = -0.04500000178813934, yaw = -4.5, pitch = 77.5, roll = 0.0 },
            ri1021 = { r = -0.0949999988079071, u = -0.06499999761581421, f = -0.04500000178813934, yaw = -4.5, pitch = 77.5, roll = 0.0 },
        },
        default = {
            default = { r = -0.0949999988079071, u = -0.06499999761581421, f = -0.04500000178813934, yaw = -4.5, pitch = 77.5, roll = 0.0 },
            ri1020 = { r = -0.0949999988079071, u = -0.06499999761581421, f = -0.04500000178813934, yaw = -4.5, pitch = 77.5, roll = 0.0 },
            ri1021 = { r = -0.0949999988079071, u = -0.06499999761581421, f = -0.04500000178813934, yaw = -4.5, pitch = 77.5, roll = 0.0 },
        },
        chris = {
        },
    },
    -- Chest holster mesh (not in-hand). Ethan bottle: zone offsets only.
    -- Chris Ampoules keep the upright park rotation.
    park_by_profile = {
        default = { r = 0.0, u = 0.0, f = 0.0, yaw = 0.0, pitch = 0.0, roll = 0.0 },
        ethan = { r = 0.0, u = 0.0, f = 0.0, yaw = 0.0, pitch = 0.0, roll = 0.0 },
        chris = { r = 0.0, u = 0.055, f = 0.0, yaw = -176.0, pitch = 89.5, roll = -1.0 },
    },
    depth_occlude = true,
    depth_always_on_top = true,
    depth_fix_arm = false,
    depth_normal_when_gun_held = false,
    depth_reassert = true,
    rhp = {
        apply_enabled = true,
        blend_sec = 0.12,
        preview_sec = 5.0,
        by_item = {},
    },
}
MED.st = {
    go = nil, xform = nil, mesh = nil, item_id = "", poll_item_id = "",
    mesh_path = "", mdf_path = "", visible = false, last_poll_t = 0,
    off_right = 0.0, off_up = 0.0, off_forward = 0.0, status = "waiting_deps",
    last_spawn = nil, joint = nil, joint_name = "",
    depth_last = nil, mesh_sm = nil, mesh_sm_t = 0, mesh_sm_root = nil,
    rhp = {
        status = nil, preview_until = 0, native_until = 0,
        last_n = 0, last_applied = 0, poser_inited = false,
    },
}
MED.poser = nil
rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
MED.rhp_groups = {
    { id = "index", label = "Index", bones = {
        "l_hand_index_0", "l_hand_index_1", "l_hand_index_2",
    }},
    { id = "middle", label = "Middle", bones = {
        "l_hand_middle_0", "l_hand_middle_1", "l_hand_middle_2",
    }},
    { id = "ring", label = "Ring", bones = {
        "l_hand_ring_0", "l_hand_ring_1", "l_hand_ring_2", "l_hand_ring_3",
    }},
    { id = "little", label = "Little", bones = {
        "l_hand_little_0", "l_hand_little_1", "l_hand_little_2", "l_hand_little_3",
    }},
    { id = "thumb", label = "Thumb", bones = {
        "l_hand_thumb_0", "l_hand_thumb_1", "l_hand_thumb_2",
    }},
}
MED.BODY_HAND_NAMES = { "R_Hand", "R_Palm" }
MED.body_hand = { joint = nil, name = "", src = "", last_t = 0 }

function MED.is_id(item_id)
    item_id = H.normalize_item_id(item_id)
    if not item_id then return false end
    if MED.ids[item_id] then return true end
    if item_id == "ri1020" or item_id == "ri1021" or item_id == "ri1022" then return true end
    if H.weapon_type(item_id) == "MED" then return true end
    if item_id:find("Medicine", 1, true) or item_id:find("Herb", 1, true) then return true end
    return false
end

function MED.is_core(core)
    if not core or not H.managed_alive(core) then return false end
    local ok, td = pcall(function() return core:get_type_definition() end)
    if not ok or not td then return false end
    local ok_m, is_m = pcall(function() return td:is_a("app.MedicineCore") end)
    return ok_m and is_m == true
end

function MED.refresh_joint()
    local st = MED.st
    local cached = st.joint_name or ""
    local is_fallback = cached:find("_fallback", 1, true) ~= nil
    local name_ok = false
    if cached ~= "" and not is_fallback then
        for _, want in ipairs(MED.joints) do
            if want == cached then name_ok = true; break end
        end
    end
    if st.joint and name_ok then
        local pos = nil
        pcall(function() pos = st.joint:call("get_Position") end)
        if pos and type(pos.x) == "number" then return true end
    end
    st.joint = nil
    st.joint_name = ""
    local transforms = H.collect_upper_transforms()
    for _, entry in ipairs(transforms) do
        for _, name in ipairs(MED.joints) do
            local j = nil
            pcall(function() j = entry.tf:call("getJointByName", name) end)
            if j then
                local pos = nil
                pcall(function() pos = j:call("get_Position") end)
                if pos and type(pos.x) == "number" then
                    st.joint = j
                    st.joint_name = name
                    return true
                end
            end
        end
    end
    for _, entry in ipairs(transforms) do
        for _, name in ipairs({ "Spine_2", "Spine_1", "Spine_0", "Hip" }) do
            local j = nil
            pcall(function() j = entry.tf:call("getJointByName", name) end)
            if j then
                local pos = nil
                pcall(function() pos = j:call("get_Position") end)
                if pos and type(pos.x) == "number" then
                    st.joint = j
                    st.joint_name = name .. "_fallback"
                    return true
                end
            end
        end
    end
    return false
end

function MED.resolve_joint()
    if not MED.refresh_joint() then return nil end
    local origin, ax, ay, az = nil, nil, nil, nil
    pcall(function() origin = MED.st.joint:call("get_Position") end)
    pcall(function() ax = MED.st.joint:call("get_AxisX") end)
    pcall(function() ay = MED.st.joint:call("get_AxisY") end)
    pcall(function() az = MED.st.joint:call("get_AxisZ") end)
    if not origin then return nil end
    return origin, ax, ay, az
end

function MED.park_row()
    local pk = H.profile_key() or "default"
    if type(MED.cfg.park_by_profile) ~= "table" then
        MED.cfg.park_by_profile = {}
    end
    local row = MED.cfg.park_by_profile[pk]
    if type(row) ~= "table" and pk == "default" then
        row = MED.cfg.park_by_profile.ethan
    end
    if type(row) ~= "table" then
        if pk == "chris" then
            row = { r = 0.0, u = 0.055, f = 0.0, yaw = -176.0, pitch = 89.5, roll = -1.0 }
        else
            row = { r = 0.0, u = 0.0, f = 0.0, yaw = 0.0, pitch = 0.0, roll = 0.0 }
        end
        MED.cfg.park_by_profile[pk] = row
    elseif pk ~= "chris" then
        -- Migrate Ampoules-style park left on Ethan/default bottle profiles.
        local pitch = tonumber(row.pitch) or 0
        if math.abs(pitch - 89.5) < 0.1 then
            row = { r = 0.0, u = 0.0, f = 0.0, yaw = 0.0, pitch = 0.0, roll = 0.0 }
            MED.cfg.park_by_profile[pk] = row
        end
    end
    rawset(_G, "__re8_medicine_park", row)
    return row
end

function MED.world_rot()
    local bas = nil
    local _, right, up, fwd = H.published_zone(MED.zone_g)
    if right and up and fwd then
        pcall(function()
            bas = Matrix4x4f.new(
                right.x, right.y, right.z, 0,
                up.x, up.y, up.z, 0,
                fwd.x, fwd.y, fwd.z, 0,
                0, 0, 0, 1):to_quat()
        end)
    end
    if not bas then
        local tf = H.get_player_transform()
        if tf then pcall(function() bas = tf:call("get_Rotation") end) end
    end
    if not bas and MED.st.joint then
        pcall(function() bas = MED.st.joint:call("get_Rotation") end)
    end
    local offset = nil
    local pr = MED.park_row()
    pcall(function()
        offset = Quaternion.new(Vector3f.new(
            math.rad(pr.pitch or 0),
            math.rad(pr.yaw or 0),
            math.rad(pr.roll or 0)
        )):normalized()
    end)
    local out = nil
    if bas and offset then
        local ok, q = pcall(function() return bas * offset end)
        if ok and q then out = q end
    end
    if not out then out = offset or bas end
    return out
end

function MED.zone_pos()
    local pos, right, up, fwd = H.published_zone(MED.zone_g)
    if pos then
        return pos, "torso_pub", right, up, fwd
    end
    local origin = MED.resolve_joint()
    if not origin then return nil, "no_joint" end
    local r = MED.st.off_right or 0
    local u = MED.st.off_up or 0
    local f = MED.st.off_forward or 0
    local br, bu, bf = H.body_axes()
    if br then
        return {
            x = origin.x + br.x * r + bu.x * u + bf.x * f,
            y = origin.y + br.y * r + bu.y * u + bf.y * f,
            z = origin.z + br.z * r + bu.z * u + bf.z * f,
        }, "fallback_body_axes", br, bu, bf
    end
    return { x = origin.x, y = origin.y, z = origin.z }, "joint_no_axes"
end

function MED.mesh_pos()
    local zone, src, ax, ay, az = MED.zone_pos()
    if not zone then return nil, src end
    local pr = MED.park_row()
    local lx = pr.r or 0
    local ly = pr.u or 0
    local lz = pr.f or 0
    rawset(_G, "__re8_medicine_visual_live", {
        mesh_off_right = lx,
        mesh_off_up = ly,
        mesh_off_forward = lz,
        rot_yaw = (pr.yaw ~= nil and pr.yaw) or (MED.cfg.rot_yaw or 0),
        rot_pitch = (pr.pitch ~= nil and pr.pitch) or (MED.cfg.rot_pitch or 0),
        rot_roll = (pr.roll ~= nil and pr.roll) or (MED.cfg.rot_roll or 0),
    })
    rawset(_G, "__re8_medicine_park", {
        r = lx, u = ly, f = lz,
        yaw = pr.yaw, pitch = pr.pitch, roll = pr.roll,
    })
    if lx == 0 and ly == 0 and lz == 0 then
        return zone, src, ax, ay, az
    end
    local rot = MED.world_rot()
    if rot then
        local wo = nil
        pcall(function() wo = rot * Vector3f.new(lx, ly, lz) end)
        if wo and type(wo.x) == "number" then
            return {
                x = zone.x + wo.x, y = zone.y + wo.y, z = zone.z + wo.z,
            }, src, ax, ay, az
        end
    end
    if ax and ay and az then
        return {
            x = zone.x + ax.x * lx + ay.x * ly + az.x * lz,
            y = zone.y + ax.y * lx + ay.y * ly + az.y * lz,
            z = zone.z + ax.z * lx + ay.z * ly + az.z * lz,
        }, src, ax, ay, az
    end
    return zone, src, ax, ay, az
end

function MED.hold_row_for(item_id)
    local id = item_id
    if type(id) ~= "string" or id == "" then id = MED.st.item_id end
    if type(id) ~= "string" or id == "" then id = "default" end
    id = H.normalize_item_id(id) or id
    local pk = H.profile_key() or "default"
    if type(MED.cfg.hold_by_profile) ~= "table" then MED.cfg.hold_by_profile = {} end
    if type(MED.cfg.hold_by_profile[pk]) ~= "table" then MED.cfg.hold_by_profile[pk] = {} end
    local bag = MED.cfg.hold_by_profile[pk]
    local function copy_seed(s)
        if type(s) ~= "table" then return nil end
        return {
            r = s.r, u = s.u, f = s.f, yaw = s.yaw, pitch = s.pitch, roll = s.roll,
        }
    end
    -- Seed missing item rows from ethan / default bottle hold.
    if type(bag[id]) ~= "table" then
        local ethan = MED.cfg.hold_by_profile.ethan
        local seeded = nil
        if type(ethan) == "table" then
            seeded = copy_seed(ethan[id]) or copy_seed(ethan.default)
        end
        if not seeded and type(MED.cfg.hold_by_profile.default) == "table" then
            local dbag = MED.cfg.hold_by_profile.default
            seeded = copy_seed(dbag[id]) or copy_seed(dbag.default)
        end
        if seeded then bag[id] = seeded end
    end
    local row = bag[id]
    if type(row) == "table" then
        -- Migrate flat pitch=0 bottle holds left from early defaults.
        local pitch = tonumber(row.pitch) or 0
        if (id == "ri1020" or id == "ri1021" or id == "default") and math.abs(pitch) < 0.1 then
            local ethan = MED.cfg.hold_by_profile.ethan
            local seed = (type(ethan) == "table" and (ethan[id] or ethan.default)) or nil
            if type(seed) == "table" and (tonumber(seed.pitch) or 0) > 1 then
                row.r = seed.r; row.u = seed.u; row.f = seed.f
                row.yaw = seed.yaw; row.pitch = seed.pitch; row.roll = seed.roll
            end
        end
    end
    if type(row) ~= "table" then
        local seed = nil
        if pk ~= "chris" and type(MED.cfg.hold_by_item) == "table" then
            seed = MED.cfg.hold_by_item[id] or MED.cfg.hold_by_item.default
        end
        row = {
            r = (seed and tonumber(seed.r)) or (MED.cfg.hold_off_right or -0.095),
            u = (seed and tonumber(seed.u)) or (MED.cfg.hold_off_up or -0.065),
            f = (seed and tonumber(seed.f)) or (MED.cfg.hold_off_forward or -0.045),
            yaw = (seed and tonumber(seed.yaw)) or -4.5,
            pitch = (seed and tonumber(seed.pitch)) or 77.5,
            roll = (seed and tonumber(seed.roll)) or 0,
        }
        bag[id] = row
    end
    if type(row.r) ~= "number" then row.r = MED.cfg.hold_off_right or -0.095 end
    if type(row.u) ~= "number" then row.u = MED.cfg.hold_off_up or -0.065 end
    if type(row.f) ~= "number" then row.f = MED.cfg.hold_off_forward or -0.045 end
    if type(row.yaw) ~= "number" then row.yaw = -4.5 end
    if type(row.pitch) ~= "number" then row.pitch = 77.5 end
    if type(row.roll) ~= "number" then row.roll = 0 end
    return row, id
end

function MED.resolve_body_hand_joint()
    local cache = MED.body_hand
    local now = os.clock()
    if cache.joint and (now - (cache.last_t or 0)) < 0.35 then
        local alive = false
        pcall(function()
            if cache.joint.get_address then
                alive = (cache.joint:get_address() or 0) ~= 0
            else
                alive = true
            end
        end)
        if alive then return cache.joint, cache.name, cache.src end
    end
    local names = MED.BODY_HAND_NAMES
    local best_j, best_name, best_src, best_pri = nil, "", "", -1
    local transforms = H.collect_upper_transforms()
    local prefer = {
        RArmMesh = 120,
        UpperBodyMesh = 110,
        player = 40,
        player_go = 40,
    }
    for i = 1, #transforms do
        local entry = transforms[i]
        local src = tostring(entry and entry.src or "")
        if src ~= "LowerBodyMesh" then
            local tf = entry and entry.tf
            if tf then
                for ni = 1, #names do
                    local nm = names[ni]
                    local j = nil
                    pcall(function() j = tf:call("getJointByName", nm) end)
                    if j then
                        local pos = nil
                        pcall(function() pos = j:call("get_Position") end)
                        if pos and type(pos.x) == "number" then
                            local pri = (prefer[src] or 10) - (ni * 0.1)
                            if pri > best_pri then
                                best_pri = pri
                                best_j = j
                                best_name = nm
                                best_src = src
                            end
                        end
                    end
                end
            end
        end
    end
    cache.joint = best_j
    cache.name = best_name
    cache.src = best_src
    cache.last_t = now
    return best_j, best_name, best_src
end

function MED.compute_hold_pose()
    local hp = H.get_right_hand_world()
    local rot, rx, ry, rz, ik_pos = nil, nil, nil, nil, nil
    local has_ik = false
    local hqw, hqx, hqy, hqz = nil, nil, nil, nil
    pcall(function()
        local tf = re8vr and re8vr.right_hand_ik_transform
        if not tf then return end
        has_ik = true
        ik_pos = tf:call("get_Position")
        rot = tf:call("get_Rotation")
        if rot then
            hqw, hqx, hqy, hqz = rot.w, rot.x, rot.y, rot.z
        end
        rx = tf:call("get_AxisX")
        ry = tf:call("get_AxisY")
        rz = tf:call("get_AxisZ")
    end)
    if ik_pos and type(ik_pos.x) == "number" then
        hp = ik_pos
    end
    local pos_src = "ik_transform"
    local body_name, body_src = "", ""
    local dist_ik_body = -1
    -- In-hand pose uses VR/IK hand. Body R_Hand is chest-space and looks like
    -- the holster, not the backup bottle-in-hand offsets.
    if not has_ik or type(hp.x) ~= "number" then
        local bj = nil
        bj, body_name, body_src = MED.resolve_body_hand_joint()
        if bj then
            local bpos, brot, brx, bry, brz = nil, nil, nil, nil, nil
            pcall(function()
                bpos = bj:call("get_Position")
                brot = bj:call("get_Rotation")
                brx = bj:call("get_AxisX")
                bry = bj:call("get_AxisY")
                brz = bj:call("get_AxisZ")
            end)
            if bpos and type(bpos.x) == "number" then
                hp = bpos
                pos_src = "body:" .. tostring(body_name or "?")
                if brot then
                    rot = brot
                    hqw, hqx, hqy, hqz = brot.w, brot.x, brot.y, brot.z
                end
                if brx and bry and brz and type(brx.x) == "number" then
                    rx, ry, rz = brx, bry, brz
                end
            end
        end
    end
    if not hp or type(hp.x) ~= "number" then
        return nil, nil, { has_ik = has_ik, rot_src = "none", pos_src = "none" }
    end
    local row, hid = MED.hold_row_for(MED.st.item_id)
    local orr = row.r or -0.10
    local ou = row.u or -0.03
    local of = row.f or 0.08
    if rx and ry and rz and type(rx.x) == "number" then
        hp = {
            x = hp.x + rx.x * orr + ry.x * ou + rz.x * of,
            y = hp.y + rx.y * orr + ry.y * ou + rz.y * of,
            z = hp.z + rx.z * orr + ry.z * ou + rz.z * of,
        }
    end
    local rot_src = pos_src
    if rot then
        -- Holster mesh rot (chest park) must not bake into in-hand pose.
        local yaw = row.yaw or 0
        local pitch = row.pitch or 0
        local roll = row.roll or 0
        local offset = nil
        pcall(function()
            offset = Quaternion.new(Vector3f.new(
                math.rad(pitch),
                math.rad(yaw),
                math.rad(roll)
            )):normalized()
        end)
        if offset then
            local ok, q = pcall(function() return rot * offset end)
            if ok and q then rot = q end
        end
    else
        rot = MED.world_rot()
        rot_src = "torso_fallback"
    end
    return hp, rot, {
        has_ik = has_ik,
        has_axes = rx ~= nil and type(rx.x) == "number",
        rot_src = rot_src,
        pos_src = pos_src,
        body_name = body_name,
        body_src = body_src,
        dist_ik_body = dist_ik_body,
        item_id = hid,
        hand_qw = hqw, hand_qx = hqx, hand_qy = hqy, hand_qz = hqz,
        hold_r = orr, hold_u = ou, hold_f = of,
        hold_yaw = row.yaw or 0,
        hold_pitch = row.pitch or 0,
        pk = H.profile_key(),
    }
end

rawset(_G, "__re8_medicine_compute_hold", MED.compute_hold_pose)

function MED.fly_active()
    local fly = rawget(_G, "__re8_holster_fly")
    return fly ~= nil and fly.active == true and fly.slot == "medicine"
end

function MED.apply_hold_visual(visual)
    if type(visual) ~= "table" then return end
    MED.cfg.hold_off_right = tonumber(visual.hold_off_right) or MED.cfg.hold_off_right
    MED.cfg.hold_off_up = tonumber(visual.hold_off_up) or MED.cfg.hold_off_up
    MED.cfg.hold_off_forward = tonumber(visual.hold_off_forward) or MED.cfg.hold_off_forward
    if type(visual.hold_by_item) == "table" then
        if type(MED.cfg.hold_by_item) ~= "table" then MED.cfg.hold_by_item = {} end
        for k, v in pairs(visual.hold_by_item) do
            if type(k) == "string" and type(v) == "table" then
                local row = MED.cfg.hold_by_item[k]
                if type(row) ~= "table" then
                    row = { r = -0.10, u = -0.03, f = 0.08, yaw = 0, pitch = 0, roll = 0 }
                    MED.cfg.hold_by_item[k] = row
                end
                if v.r ~= nil then row.r = tonumber(v.r) or row.r end
                if v.u ~= nil then row.u = tonumber(v.u) or row.u end
                if v.f ~= nil then row.f = tonumber(v.f) or row.f end
                if v.yaw ~= nil then row.yaw = tonumber(v.yaw) or row.yaw end
                if v.pitch ~= nil then row.pitch = tonumber(v.pitch) or row.pitch end
                if v.roll ~= nil then row.roll = tonumber(v.roll) or row.roll end
            end
        end
    end
    if type(visual.hold_by_profile) == "table" then
        if type(MED.cfg.hold_by_profile) ~= "table" then MED.cfg.hold_by_profile = {} end
        for pk, bag in pairs(visual.hold_by_profile) do
            if type(pk) == "string" and type(bag) == "table" then
                if type(MED.cfg.hold_by_profile[pk]) ~= "table" then
                    MED.cfg.hold_by_profile[pk] = {}
                end
                for k, v in pairs(bag) do
                    if type(k) == "string" and type(v) == "table" then
                        local row = MED.cfg.hold_by_profile[pk][k]
                        if type(row) ~= "table" then
                            row = { r = -0.10, u = -0.03, f = 0.08, yaw = 0, pitch = 0, roll = 0 }
                            MED.cfg.hold_by_profile[pk][k] = row
                        end
                        if v.r ~= nil then row.r = tonumber(v.r) or row.r end
                        if v.u ~= nil then row.u = tonumber(v.u) or row.u end
                        if v.f ~= nil then row.f = tonumber(v.f) or row.f end
                        if v.yaw ~= nil then row.yaw = tonumber(v.yaw) or row.yaw end
                        if v.pitch ~= nil then row.pitch = tonumber(v.pitch) or row.pitch end
                        if v.roll ~= nil then row.roll = tonumber(v.roll) or row.roll end
                    end
                end
            end
        end
    end
    if type(visual.park_by_profile) == "table" then
        if type(MED.cfg.park_by_profile) ~= "table" then MED.cfg.park_by_profile = {} end
        for pk, v in pairs(visual.park_by_profile) do
            if type(pk) == "string" and type(v) == "table" then
                MED.cfg.park_by_profile[pk] = {
                    r = tonumber(v.r) or tonumber(v.mesh_off_right) or 0,
                    u = tonumber(v.u) or tonumber(v.mesh_off_up) or 0,
                    f = tonumber(v.f) or tonumber(v.mesh_off_forward) or 0,
                    yaw = tonumber(v.yaw) or tonumber(v.rot_yaw) or 0,
                    pitch = tonumber(v.pitch) or tonumber(v.rot_pitch) or 0,
                    roll = tonumber(v.roll) or tonumber(v.rot_roll) or 0,
                }
            end
        end
    end
    if type(visual.right_hand_pose) == "table" then
        if type(MED.cfg.rhp) ~= "table" then
            MED.cfg.rhp = { apply_enabled = true, blend_sec = 0.12, preview_sec = 5.0, by_item = {} }
        end
        MED.cfg.rhp.apply_enabled = visual.right_hand_pose.apply_enabled ~= false
        MED.cfg.rhp.blend_sec = tonumber(visual.right_hand_pose.blend_sec) or MED.cfg.rhp.blend_sec
        MED.cfg.rhp.preview_sec = tonumber(visual.right_hand_pose.preview_sec) or MED.cfg.rhp.preview_sec
        MED.cfg.rhp.by_item = {}
        if type(visual.right_hand_pose.by_item) == "table" then
            for ik, ie in pairs(visual.right_hand_pose.by_item) do
                if type(ik) == "string" and type(ie) == "table" then
                    MED.cfg.rhp.by_item[ik] = {
                        apply_enabled = ie.apply_enabled ~= false,
                        pose = type(ie.pose) == "table" and ie.pose or {},
                        emv = type(ie.emv) == "table" and ie.emv or {},
                    }
                end
            end
        end
    end
end

function MED.first_inventory_id()
    for _, row in ipairs(H.inventory_rows()) do
        if MED.is_core(row.item_internal) then
            return H.normalize_item_id(row.item_id)
        end
    end
    for _, row in ipairs(H.inventory_rows()) do
        if MED.is_id(row.item_id) then
            return H.normalize_item_id(row.item_id)
        end
    end
    return nil
end

function MED.poll()
    local st = MED.st
    local now = os.clock()
    if (now - (st.last_poll_t or 0)) < (MED.cfg.poll_s or 0.35) then
        return st.poll_item_id or st.item_id
    end
    st.last_poll_t = now
    local item_id = nil
    local last_med = ""
    local data = nil
    pcall(function() data = json.load_file(CFG_PATH) end)
    if type(data) == "table" and type(data.profiles) == "table" then
        local visual = H.visual_blob(data, MED.json_new, MED.json_old)
        H.apply_visual_offsets(MED.cfg, visual)
        MED.apply_hold_visual(visual)
        local pr = MED.park_row()
        MED.cfg.mesh_off_right = pr.r or 0
        MED.cfg.mesh_off_up = pr.u or 0
        MED.cfg.mesh_off_forward = pr.f or 0
        MED.cfg.rot_yaw = pr.yaw or 0
        MED.cfg.rot_pitch = pr.pitch or 0
        MED.cfg.rot_roll = pr.roll or 0
        local P = data.profiles[H.profile_key()]
        if type(P) ~= "table" then P = data.profiles.default or data.profiles["default"] end
        if type(P) == "table" then
            item_id = H.normalize_item_id(P.last_medicine_id)
            last_med = tostring(item_id or "")
            st.off_right = tonumber(P.medicine_off_right) or 0
            st.off_up = tonumber(P.medicine_off_up) or 0
            st.off_forward = tonumber(P.medicine_off_forward) or 0
        end
    end
    local first_inv = MED.first_inventory_id()
    local used_fallback = false
    -- Prefer a live MedicineCore over a stale profile id.
    if first_inv and first_inv ~= "" then
        if not item_id or item_id == "" or item_id ~= first_inv then
            local row = item_id and H.find_row_for_item_id(item_id) or nil
            if not row or not MED.is_core(row.item_internal) then
                item_id = first_inv
                used_fallback = true
            end
        end
    elseif not item_id or item_id == "" then
        item_id = first_inv
        used_fallback = item_id ~= nil and item_id ~= ""
    end
    local inv_has = false
    local med_n = 0
    local med_td = ""
    for _, row in ipairs(H.inventory_rows()) do
        local is_med = MED.is_core(row.item_internal) or MED.is_id(row.item_id)
        if is_med then
            med_n = med_n + 1
            if med_td == "" then
                pcall(function()
                    local td = row.item_internal and row.item_internal:get_type_definition()
                    if td then med_td = td:get_full_name() or td:get_name() or "?" end
                end)
            end
            if item_id and H.normalize_item_id(row.item_id) == H.normalize_item_id(item_id) then
                inv_has = true
            end
        end
    end
    if med_n == 0 then
        item_id = nil
        if (st.item_id or "") ~= "" or st.go ~= nil then
            H.destroy(MED)
            st.item_id = ""
            st.status = "destroyed"
            rawset(_G, "__re8_medicine_visual_live", nil)
            rawset(_G, "__re8_medicine_mesh_world", nil)
            local clear_fn = rawget(_G, "__re8_medicine_clear_empty_slot")
            if type(clear_fn) == "function" then
                pcall(clear_fn)
            end
        end
    end
    st.poll_item_id = item_id or ""
    return item_id or ""
end

function MED.ensure_rhp_entry(item_id)
    if type(MED.cfg.rhp) ~= "table" then
        MED.cfg.rhp = { apply_enabled = true, blend_sec = 0.12, preview_sec = 5.0, by_item = {} }
    end
    MED.cfg.rhp.by_item = MED.cfg.rhp.by_item or {}
    item_id = H.normalize_item_id(item_id) or tostring(MED.st.item_id or "")
    if item_id == "" then return nil, "" end
    local e = MED.cfg.rhp.by_item[item_id]
    if type(e) ~= "table" then
        e = { apply_enabled = true, pose = {}, emv = {} }
        MED.cfg.rhp.by_item[item_id] = e
    end
    if type(e.pose) ~= "table" then e.pose = {} end
    if type(e.emv) ~= "table" then e.emv = {} end
    return e, item_id
end

function MED.init_rhp_poser()
    local poser = MED.poser
    if not poser or not poser.init then return false end
    if MED.st.rhp.poser_inited == true then return true end
    pcall(function()
        poser.init({
            sc = H.safe_call,
            collect_transforms = function()
                local fn = rawget(_G, "__re8_holster_collect_transforms")
                if type(fn) == "function" then return fn() end
                return H.collect_upper_transforms()
            end,
        })
    end)
    MED.st.rhp.poser_inited = true
    return true
end

function MED.play_native_heal()
    MED.init_rhp_poser()
    local fn = rawget(_G, "__re8_holster_play_native_heal_anim")
    local ok, reason, item_id = false, "no_holster_helper", tostring(MED.st.item_id or "")
    if type(fn) == "function" then
        ok, reason, item_id = fn()
    end
    MED.st.rhp.native_until = os.clock() + 8.0
    if type(item_id) == "string" and item_id ~= "" then
        MED.st.rhp.capture_item_id = item_id
    end
    if ok then
        MED.st.rhp.status = "Native heal pulsed — capture within 8s while fingers wrap"
    else
        MED.st.rhp.status = "Native heal failed: " .. tostring(reason or "?")
    end
    return ok == true
end

function MED.capture_rhp()
    MED.init_rhp_poser()
    local poser = MED.poser
    local rt = MED.st.rhp
    if not poser or not poser.capture_pose_right then
        rt.status = "poser missing capture_pose_right"
        return false
    end
    local entry, item_id = MED.ensure_rhp_entry(
        (MED.st.item_id ~= "" and MED.st.item_id) or rt.capture_item_id)
    if not entry then
        rt.status = "no medicine id"
        return false
    end
    local cap, n = poser.capture_pose_right()
    local st = poser.get_state and poser.get_state() or {}
    local max_mag = 0
    if cap and type(cap.pose) == "table" then
        max_mag = tonumber(cap.max_mag) or 0
        if max_mag <= 0 then
            for _, vec in pairs(cap.pose) do
                if type(vec) == "table" then
                    local mag = math.abs(tonumber(vec[1]) or 0)
                        + math.abs(tonumber(vec[2]) or 0)
                        + math.abs(tonumber(vec[3]) or 0)
                    if mag > max_mag then max_mag = mag end
                end
            end
        end
    end
    if not cap or not cap.pose then
        rt.status = string.format(
            "capture failed (src=%s n=%s)",
            tostring(st.capture_src or st.src or "?"), tostring(n or 0))
        return false
    end
    if max_mag < 0.25 then
        rt.status = string.format(
            "captured rest/open (mag=%.3f src=%s) — play native heal then capture mid-anim",
            max_mag, tostring(st.capture_src or "?"))
        return false
    end
    entry.pose = cap.pose
    entry.emv = cap.emv or {}
    entry.apply_enabled = true
    local bone_n = 0
    for _ in pairs(entry.pose) do bone_n = bone_n + 1 end
    rt.last_n = bone_n
    rt.native_until = 0
    rt.status = string.format("captured RH %d bones mag=%.2f for %s", bone_n, max_mag, item_id)
    H.save_visuals()
    return true
end

function MED.publish_rhp_active(active)
    rawset(_G, "__re8_medicine_hand_pose_rh_active", active == true)
end

function MED.tick_rhp()
    local rhp = MED.cfg.rhp
    local rt = MED.st.rhp
    if type(rhp) ~= "table" or type(rt) ~= "table" then
        MED.publish_rhp_active(false)
        return 0
    end
    if rhp.apply_enabled == false then
        MED.publish_rhp_active(false)
        return 0
    end
    local now = os.clock()
    local native_until = tonumber(rt.native_until) or 0
    if now < native_until then
        MED.publish_rhp_active(false)
        return 0
    end
    local preview_until = tonumber(rt.preview_until) or 0
    local in_hand = rawget(_G, "__re8_medicine_in_hand") == true
    if not in_hand and now >= preview_until then
        MED.publish_rhp_active(false)
        return 0
    end
    if MED.fly_active() then
        MED.publish_rhp_active(false)
        return 0
    end
    local entry = rhp.by_item and rhp.by_item[tostring(MED.st.item_id or "")]
    if type(entry) ~= "table" or entry.apply_enabled == false then
        MED.publish_rhp_active(false)
        return 0
    end
    if type(entry.pose) ~= "table" or next(entry.pose) == nil then
        MED.publish_rhp_active(false)
        return 0
    end
    local pose_mag = 0
    for _, vec in pairs(entry.pose) do
        if type(vec) == "table" then
            local mag = math.abs(tonumber(vec[1]) or 0)
                + math.abs(tonumber(vec[2]) or 0)
                + math.abs(tonumber(vec[3]) or 0)
            if mag > pose_mag then pose_mag = mag end
        end
    end
    if pose_mag < 0.25 then
        MED.publish_rhp_active(false)
        return 0
    end
    local poser = MED.poser
    if not poser or not poser.apply_pose_right then
        MED.publish_rhp_active(false)
        return 0
    end
    MED.init_rhp_poser()
    local n = poser.apply_pose_right(entry, 1.0) or 0
    rt.last_applied = n
    MED.publish_rhp_active(n > 0)
    return n
end

function MED.apply_in_hand_transform()
    if rawget(_G, "__re8_medicine_lua_hidden") == true then
        H.set_visible(MED, false)
        return false
    end
    if rawget(_G, "__re8_medicine_in_hand") ~= true then return false end
    local st = MED.st
    if not st.go or not H.managed_alive(st.go) then return false end
    if not st.xform or not H.managed_alive(st.xform) then
        st.xform = H.safe_call(st.go, "get_Transform")
    end
    if not st.xform then return false end
    local hp, rot, meta = MED.compute_hold_pose()
    if not hp or type(hp.x) ~= "number" then return false end
    H.set_visible(MED, true)
    pcall(function()
        st.xform:call("set_Position", Vector3f.new(hp.x, hp.y, hp.z))
    end)
    if rot then
        pcall(function() st.xform:call("set_Rotation", rot) end)
    end
    st.mesh_sm = { x = hp.x, y = hp.y, z = hp.z }
    H.publish_pose(MED, hp.x, hp.y, hp.z, rot)
    H.apply_mesh_depth_priority(MED, st.mesh, "in_hand")
    return true
end

-- Same-frame medicine mesh hide (avoids hand flash during pour).
rawset(_G, "__re8_medicine_force_hide", function()
    H.set_visible(MED, false)
end)
rawset(_G, "__re8_medicine_force_destroy", function()
    H.destroy(MED)
    MED.st.item_id = ""
    MED.st.poll_item_id = ""
    MED.st.status = "destroyed"
    rawset(_G, "__re8_medicine_visual_live", nil)
    rawset(_G, "__re8_medicine_mesh_world", nil)
end)

function MED.update()
    local st = MED.st
    if not st.go or not H.managed_alive(st.go) then return end
    if not st.xform or not H.managed_alive(st.xform) then
        st.xform = H.safe_call(st.go, "get_Transform")
    end
    if not st.xform then return end
    -- Native use owns the bottle pose; keep the Lua clone fully hidden.
    if rawget(_G, "__re8_medicine_lua_hidden") == true then
        H.set_visible(MED, false)
        return
    end
    local use_fn = rawget(_G, "__re8_heal_is_native_use_active")
    if type(use_fn) == "function" then
        local ok, using = pcall(use_fn)
        if ok and using == true then
            H.set_visible(MED, false)
            return
        end
    end
    if H.try_fly(MED) then return end
    if rawget(_G, "__re8_medicine_in_hand") ~= true then
        if H.try_bridge(MED) then return end
    end
    if rawget(_G, "__re8_medicine_in_hand") == true then
        if MED.apply_in_hand_transform() then
            return
        end
    end
    local pos = MED.mesh_pos()
    if not pos then
        H.set_visible(MED, false)
        return
    end
    local equipped = H.current_equipped_item_id()
    local published_active = rawget(_G, "__re8_active_weapon_id")
    if type(published_active) == "string" and published_active ~= ""
        and published_active ~= "Hand" then
        equipped = published_active
    end
    local hide = equipped ~= nil and equipped ~= "" and st.item_id ~= ""
        and H.normalize_item_id(equipped) == H.normalize_item_id(st.item_id)
    H.set_visible(MED, not hide)
    local rot = MED.world_rot()
    if not st.visible then
        H.publish_pose(MED, pos.x, pos.y, pos.z, rot)
        return
    end
    if MED.cfg.depth_reassert ~= false and st.mesh then
        H.apply_mesh_depth_priority(MED, st.mesh, "tick")
    end
    pos = H.smooth_mesh_pos(MED, pos)
    H.publish_pose(MED, pos.x, pos.y, pos.z, rot)
    H.apply_xform(MED, pos, rot)
end

function MED.draw_rhp_ui()
    if type(MED.cfg.rhp) ~= "table" then
        MED.cfg.rhp = { apply_enabled = true, blend_sec = 0.12, preview_sec = 5.0, by_item = {} }
    end
    local rhp = MED.cfg.rhp
    local rt = MED.st.rhp
    local dirty = false
    if not imgui.tree_node("Right hand pose (native heal capture)") then
        return false
    end
    imgui.text("Play native heal, then Capture within ~8s while the right hand wraps the bottle.")
    imgui.text("Saved per medicine id. Apply while Lua in-hand.")
    local ch_m, v_m = imgui.checkbox("Apply right hand pose##med_rhp", rhp.apply_enabled ~= false)
    if ch_m then rhp.apply_enabled = v_m; dirty = true end
    local blend = tonumber(rhp.blend_sec) or 0.12
    local c_bl, v_bl = imgui.drag_float("Pose blend sec##med_rhp_bl", blend, 0.01, 0.0, 0.5, "%.2f")
    if c_bl then rhp.blend_sec = v_bl; dirty = true end
    local prev_sec = tonumber(rhp.preview_sec) or 5.0
    local c_ps, v_ps = imgui.drag_float("Preview sec##med_rhp_ps", prev_sec, 0.1, 1.0, 15.0, "%.1f")
    if c_ps then rhp.preview_sec = v_ps; dirty = true end
    local entry, item_id = MED.ensure_rhp_entry(MED.st.item_id)
    imgui.text(string.format("Item: %s | poser: %s | in-hand: %s",
        tostring(item_id ~= "" and item_id or "(none)"),
        tostring(MED.poser ~= nil),
        tostring(rawget(_G, "__re8_medicine_in_hand") == true)))
    local bone_n = 0
    if entry and type(entry.pose) == "table" then
        for _ in pairs(entry.pose) do bone_n = bone_n + 1 end
    end
    imgui.text(string.format("bones: %d | last apply: %s | native window: %.1fs",
        bone_n,
        tostring(rt.last_applied or 0),
        math.max(0.0, (tonumber(rt.native_until) or 0) - os.clock())))
    if imgui.button("Play native heal anim##med_rhp_play") then
        MED.play_native_heal()
    end
    imgui.same_line()
    if imgui.button("Capture right hand now##med_rhp_cap") then
        MED.capture_rhp()
    end
    imgui.same_line()
    if imgui.button("Clear pose##med_rhp_clr") then
        if entry then
            entry.pose = {}
            entry.emv = {}
        end
        rt.status = "cleared " .. tostring(item_id)
        dirty = true
    end
    if imgui.button("Preview##med_rhp_prev") then
        rt.preview_until = os.clock() + (tonumber(rhp.preview_sec) or 5.0)
        rt.status = "preview"
    end
    imgui.same_line()
    if imgui.button("Stop preview##med_rhp_stop") then
        rt.preview_until = 0
        rt.status = "preview stopped"
    end
    if rt.status then
        imgui.text_colored(rt.status, 0xFF8888FF)
    end
    if (tonumber(rt.preview_until) or 0) > os.clock() then
        imgui.text_colored(string.format("Live preview %.1fs",
            (rt.preview_until or 0) - os.clock()), 0xFF88FF88)
    end
    if bone_n > 0 and entry and type(entry.pose) == "table" then
        local groups = MED.rhp_groups or {}
        for _, group in ipairs(groups) do
            if imgui.tree_node(group.label .. "##med_rhp_" .. group.id) then
                for _, bone in ipairs(group.bones) do
                    local vec = entry.pose[bone]
                    if vec then
                        imgui.text_colored(bone, 0xFF88CCFF)
                        imgui.indent(12)
                        local vx = tonumber(vec[1]) or 0.0
                        local vy = tonumber(vec[2]) or 0.0
                        local vz = tonumber(vec[3]) or 0.0
                        local suf = "##med_rhp_" .. tostring(item_id) .. "_" .. bone
                        local cx, nx = imgui.drag_float("X" .. suf, vx, 0.05, -180.0, 180.0, "%.2f")
                        if cx then vec[1] = nx; dirty = true end
                        local cy, ny = imgui.drag_float("Y" .. suf, vy, 0.05, -180.0, 180.0, "%.2f")
                        if cy then vec[2] = ny; dirty = true end
                        local cz, nz = imgui.drag_float("Z" .. suf, vz, 0.05, -180.0, 180.0, "%.2f")
                        if cz then vec[3] = nz; dirty = true end
                        imgui.unindent(12)
                    end
                end
                imgui.tree_pop()
            end
        end
    else
        imgui.text("No right-hand pose captured yet for this medicine.")
    end
    imgui.tree_pop()
    return dirty
end

--------------------------------------------------
-- JSON save (all three slots, one dump)
--------------------------------------------------

function H.base_visual(cfg)
    return {
        scale = cfg.scale,
        rot_yaw = cfg.rot_yaw,
        rot_pitch = cfg.rot_pitch,
        rot_roll = cfg.rot_roll,
        mesh_off_right = cfg.mesh_off_right,
        mesh_off_up = cfg.mesh_off_up,
        mesh_off_forward = cfg.mesh_off_forward,
    }
end

function H.save_visuals()
    local data = nil
    pcall(function() data = json.load_file(CFG_PATH) end)
    if type(data) ~= "table" then data = {} end
    local hip = H.base_visual(HIP.cfg)
    local knife = H.base_visual(KNIFE.cfg)
    local med = H.base_visual(MED.cfg)
    med.hold_off_right = MED.cfg.hold_off_right
    med.hold_off_up = MED.cfg.hold_off_up
    med.hold_off_forward = MED.cfg.hold_off_forward
    med.hold_by_item = {}
    if type(MED.cfg.hold_by_item) == "table" then
        for k, v in pairs(MED.cfg.hold_by_item) do
            if type(k) == "string" and type(v) == "table" then
                med.hold_by_item[k] = {
                    r = tonumber(v.r) or 0,
                    u = tonumber(v.u) or 0,
                    f = tonumber(v.f) or 0,
                    yaw = tonumber(v.yaw) or 0,
                    pitch = tonumber(v.pitch) or 0,
                    roll = tonumber(v.roll) or 0,
                }
            end
        end
    end
    med.hold_by_profile = {}
    if type(MED.cfg.hold_by_profile) == "table" then
        for pk, bag in pairs(MED.cfg.hold_by_profile) do
            if type(pk) == "string" and type(bag) == "table" then
                med.hold_by_profile[pk] = {}
                for k, v in pairs(bag) do
                    if type(k) == "string" and type(v) == "table" then
                        med.hold_by_profile[pk][k] = {
                            r = tonumber(v.r) or 0,
                            u = tonumber(v.u) or 0,
                            f = tonumber(v.f) or 0,
                            yaw = tonumber(v.yaw) or 0,
                            pitch = tonumber(v.pitch) or 0,
                            roll = tonumber(v.roll) or 0,
                        }
                    end
                end
            end
        end
    end
    med.park_by_profile = {}
    if type(MED.cfg.park_by_profile) == "table" then
        for pk, v in pairs(MED.cfg.park_by_profile) do
            if type(pk) == "string" and type(v) == "table" then
                med.park_by_profile[pk] = {
                    r = tonumber(v.r) or 0,
                    u = tonumber(v.u) or 0,
                    f = tonumber(v.f) or 0,
                    yaw = tonumber(v.yaw) or 0,
                    pitch = tonumber(v.pitch) or 0,
                    roll = tonumber(v.roll) or 0,
                }
            end
        end
    end
    local prs = MED.park_row()
    med.mesh_off_right = prs.r or 0
    med.mesh_off_up = prs.u or 0
    med.mesh_off_forward = prs.f or 0
    med.rot_yaw = prs.yaw or 0
    med.rot_pitch = prs.pitch or 0
    med.rot_roll = prs.roll or 0
    med.right_hand_pose = {
        apply_enabled = true,
        blend_sec = 0.12,
        preview_sec = 5.0,
        by_item = {},
    }
    if type(MED.cfg.rhp) == "table" then
        med.right_hand_pose.apply_enabled = MED.cfg.rhp.apply_enabled ~= false
        med.right_hand_pose.blend_sec = tonumber(MED.cfg.rhp.blend_sec) or 0.12
        med.right_hand_pose.preview_sec = tonumber(MED.cfg.rhp.preview_sec) or 5.0
        if type(MED.cfg.rhp.by_item) == "table" then
            for ik, ie in pairs(MED.cfg.rhp.by_item) do
                if type(ik) == "string" and type(ie) == "table" then
                    med.right_hand_pose.by_item[ik] = {
                        apply_enabled = ie.apply_enabled ~= false,
                        pose = type(ie.pose) == "table" and ie.pose or {},
                        emv = type(ie.emv) == "table" and ie.emv or {},
                    }
                end
            end
        end
    end
    data.hip_visual = hip
    data.knife_visual = knife
    data.medicine_visual = med
    data.hip_probe_visual = hip
    data.knife_probe_visual = knife
    data.medicine_probe_visual = med
    local ok = pcall(function() json.dump_file(CFG_PATH, data) end)
    return ok
end

--------------------------------------------------
-- UI
--------------------------------------------------

function H.draw_slot_ui(slot, title, id_label, pose_text, reset_fwd, extra)
    if not imgui.tree_node(title) then return end
    local cfg = slot.cfg
    local st = slot.st
    local suf = "##" .. slot.fly_slot
    local _
    _, cfg.enabled = imgui.checkbox("Enabled" .. suf, cfg.enabled == true)
    imgui.separator()
    imgui.text("Depth vs VR hand")
    _, cfg.depth_always_on_top = imgui.checkbox("Always on top (IgnoreDepth)" .. suf, cfg.depth_always_on_top == true)
    _, cfg.depth_occlude = imgui.checkbox("Occlude hand (depth test)" .. suf, cfg.depth_occlude ~= false)
    _, cfg.depth_fix_arm = imgui.checkbox("Fix arm IgnoreDepth too (breaks Albert SG)" .. suf, cfg.depth_fix_arm == true)
    _, cfg.depth_reassert = imgui.checkbox("Reassert depth each tick" .. suf, cfg.depth_reassert ~= false)
    if st.depth_last then
        imgui.text(string.format(
            "Gun IgnoreDepth set=%s after=%s | ArmR %s->%s (%s)",
            tostring(st.depth_last.ignore_set),
            tostring(st.depth_last.ignore_after),
            tostring(st.depth_last.arm_r_before),
            tostring(st.depth_last.arm_r_after),
            tostring(st.depth_last.reason)))
    end
    if imgui.button("Apply Depth Now" .. suf) then
        if st.mesh then H.apply_mesh_depth_priority(slot, st.mesh, "ui") end
    end
    imgui.separator()
    imgui.text("Status: " .. tostring(st.status))
    imgui.text("Ready: " .. tostring(H.ready == true))
    imgui.text(id_label .. ": " .. tostring(st.item_id ~= "" and st.item_id or "(none)"))
    if pose_text then imgui.text(pose_text) end
    imgui.text("Joint: " .. tostring(st.joint_name ~= "" and st.joint_name or "(none)"))
    imgui.text("Mesh: " .. tostring(st.mesh_path ~= "" and st.mesh_path or "(none)"))
    imgui.text("MDF: " .. tostring(st.mdf_path ~= "" and st.mdf_path or "(none)"))
    if st.last_spawn then
        imgui.text(string.format("Spawn: mesh=%s mat=%s mat_ok=%s num=%s",
            tostring(st.last_spawn.set_via),
            tostring(st.last_spawn.mat_via),
            tostring(st.last_spawn.mat_ok),
            tostring(st.last_spawn.mat_num)))
    end
    imgui.text("Visible: " .. tostring(st.visible == true))
    imgui.text(string.format("Joint offs R/U/F: %.3f / %.3f / %.3f",
        st.off_right or 0, st.off_up or 0, st.off_forward or 0))
    local visual_changed = false
    local changed = false
    changed, cfg.scale = imgui.drag_float("Scale" .. suf, cfg.scale or 1.0, 0.01, 0.1, 3.0)
    visual_changed = visual_changed or changed
    changed, cfg.rot_yaw = imgui.drag_float("Rot Yaw" .. suf, cfg.rot_yaw or 0, 0.5, -180, 180)
    visual_changed = visual_changed or changed
    changed, cfg.rot_pitch = imgui.drag_float("Rot Pitch" .. suf, cfg.rot_pitch or 0, 0.5, -180, 180)
    visual_changed = visual_changed or changed
    changed, cfg.rot_roll = imgui.drag_float("Rot Roll" .. suf, cfg.rot_roll or 0, 0.5, -180, 180)
    visual_changed = visual_changed or changed
    imgui.text("Mesh local pivot (after rot) — shifts mesh only, not grab zone")
    changed, cfg.mesh_off_right = imgui.drag_float("Mesh Off Right" .. suf, cfg.mesh_off_right or 0, 0.005, -0.4, 0.4)
    visual_changed = visual_changed or changed
    changed, cfg.mesh_off_up = imgui.drag_float("Mesh Off Up" .. suf, cfg.mesh_off_up or 0, 0.005, -0.4, 0.4)
    visual_changed = visual_changed or changed
    changed, cfg.mesh_off_forward = imgui.drag_float("Mesh Off Forward" .. suf, cfg.mesh_off_forward or 0, 0.005, -0.4, 0.4)
    visual_changed = visual_changed or changed
    if extra then
        local extra_dirty = extra()
        visual_changed = visual_changed or extra_dirty
    end
    local reset_label = "Reset Mesh Pivot (0)"
    local reset_fwd_val = 0.0
    if reset_fwd then
        reset_label = "Reset Mesh Pivot (0.14 fwd)"
        reset_fwd_val = 0.14
    end
    if imgui.button(reset_label .. suf) then
        cfg.mesh_off_right = 0.0
        cfg.mesh_off_up = 0.0
        cfg.mesh_off_forward = reset_fwd_val
        visual_changed = true
    end
    if visual_changed then
        if slot == MED then
            local pk = H.profile_key() or "default"
            if type(MED.cfg.park_by_profile) ~= "table" then MED.cfg.park_by_profile = {} end
            MED.cfg.park_by_profile[pk] = {
                r = tonumber(cfg.mesh_off_right) or 0,
                u = tonumber(cfg.mesh_off_up) or 0,
                f = tonumber(cfg.mesh_off_forward) or 0,
                yaw = tonumber(cfg.rot_yaw) or 0,
                pitch = tonumber(cfg.rot_pitch) or 0,
                roll = tonumber(cfg.rot_roll) or 0,
            }
        end
        H.save_visuals()
    end
    if imgui.button("Force Rebuild" .. suf) then
        st.item_id = ""
        if H.ensure_ready() then
            H.rebuild_if_needed(slot, slot.poll())
        end
    end
    if imgui.button("Destroy Mesh" .. suf) then
        H.destroy(slot)
        st.item_id = ""
        st.status = "destroyed"
    end
    imgui.tree_pop()
end

--------------------------------------------------
-- Native reticle (hide on bare / knife / medicine)
--------------------------------------------------

RET.go_names = {
    ReticleGUI = true,
    GUIReticle = true,
}

RET.cacher_fields = {
    "_ReticleGUI",
}

RET.menu_mgr = nil
RET.cacher = nil
RET.gui = nil
RET.hide = false
RET.applied_hide = false
RET.last_poll_t = 0

function RET.clear()
    RET.cacher = nil
    RET.gui = nil
    RET.menu_mgr = nil
    RET.last_poll_t = 0
    RET.armed_seen = false
    RET._hide_since = nil
    RET._applied_gui = nil
    RET._aiming = nil
end

function RET.is_hide_id(id)
    if id == nil or id == "" then return false end
    local s = tostring(id)
    if s == "Hand" or s:find("BareHand", 1, true) then return true end
    if H.weapon_type(s) == "KNF" or H.weapon_type(s) == "MED" then return true end
    if s:find("Knife", 1, true) then return true end
    local lower = s:lower()
    if lower:find("circularsaw", 1, true) or lower:find("chainsaw", 1, true)
        or lower:find("candle", 1, true) or lower:find("glasses", 1, true) then
        return true
    end
    return false
end

function RET.want_hide()
    if not re8vr or not re8vr.can_use_hands then
        return false
    end
    local id = tostring(rawget(_G, "__re8_active_weapon_id") or "")
    if RET.armed_seen ~= true then
        if id ~= "" and not RET.is_hide_id(id) then
            RET.armed_seen = true
        else
            return false
        end
    end
    if rawget(_G, "__re8_bare_hands") == true then return true end
    if rawget(_G, "__re8_medicine_in_hand") == true then return true end
    if RET.is_hide_id(id) then return true end
    if id == "" then return RET.hide end
    return false
end

function RET.resolve(force)
    local now = os.clock()
    if (not force) and H.managed_alive(RET.gui) then
        if (now - (RET.last_poll_t or 0)) < 0.5 then
            return H.managed_alive(RET.gui)
        end
    end
    RET.last_poll_t = now

    if not H.managed_alive(RET.menu_mgr) then
        RET.menu_mgr = nil
        pcall(function() RET.menu_mgr = sdk.get_managed_singleton("app.MenuManager") end)
    end
    if not H.managed_alive(RET.menu_mgr) then
        RET.cacher = nil
        RET.gui = nil
        return false
    end

    local fields = RET.cacher_fields

    if force or not H.managed_alive(RET.cacher) then
        RET.cacher = nil
        RET.gui = nil
        for i = 1, #fields do
            local cacher = nil
            pcall(function() cacher = RET.menu_mgr:get_field(fields[i]) end)
            if H.managed_alive(cacher) then
                local menu = H.safe_call(cacher, "get_Menu")
                if H.managed_alive(menu) then
                    RET.cacher = cacher
                    RET.gui = menu
                    break
                end
                if RET.cacher == nil then
                    RET.cacher = cacher
                end
            end
        end
    end

    if H.managed_alive(RET.cacher) then
        local fresh = H.safe_call(RET.cacher, "get_Menu")
        if H.managed_alive(fresh) then
            RET.gui = fresh
        end
    end
    return H.managed_alive(RET.gui)
end

function RET.find_controller()
    local player = re8vr and re8vr.player
    if not H.managed_alive(player) then return nil, "" end
    local names = {
        "app.PlayerReticleController",
    }
    for i = 1, #names do
        local c = nil
        pcall(function()
            if GameObject and GameObject.get_component then
                c = GameObject.get_component(player, names[i])
            end
        end)
        if not H.managed_alive(c) then
            pcall(function()
                c = player:call("getComponent(System.Type)", sdk.typeof(names[i]))
            end)
        end
        if H.managed_alive(c) then
            return c, names[i]
        end
    end
    return nil, ""
end

RET.ITEM_TO_GUI = {
}

function RET.map_item_to_gui(id)
    if type(id) ~= "string" or id == "" or id == "Hand" then return "" end
    local mapped = RET.ITEM_TO_GUI[id]
    if mapped then return mapped end
    if id:sub(1, 2) ~= "wp" then return id end
    local found = ""
    for k, v in pairs(H.ID_MAP) do
        if v == id then
            found = k
            if k:find("Albert", 1, true) then return k end
        end
    end
    if found ~= "" then return found end
    if id:find("Burner", 1, true) or id:find("Flame", 1, true) then
        return "Burner"
    end
    if id:find("MachineGun", 1, true) or id:find("Machinegun", 1, true) then
        return "MachineGun"
    end
    if id:find("Cannon", 1, true) or id:find("GrenadeLauncher", 1, true) then
        return "GrenadeLauncher"
    end
    if id:find("Magnum", 1, true) then
        return "Magnum_AWM"
    end
    return ""
end

function RET.weapon_gui_id(fallback)
    local name = ""
    pcall(function()
        if re8vr and re8vr.weapon then
            local go = re8vr.weapon:call("get_GameObject")
            if go then name = tostring(go:call("get_Name") or "") end
        end
    end)
    if name == "" or name == "nil" or name == "Hand" then
        pcall(function()
            if not re8vr or not re8vr.player or not GameObject then return end
            local mc = GameObject.get_component(re8vr.player, "app.PlayerMeshController")
            if not mc then return end
            local mesh_go = mc:call("get_weaponMeshObject")
            if mesh_go then name = tostring(mesh_go:call("get_Name") or "") end
        end)
    end
    local gui = RET.map_item_to_gui(name)
    if gui == "" then
        gui = RET.map_item_to_gui(fallback)
    end
    return gui
end

function RET.apply_type(gui_id)
    if not H.managed_alive(RET.gui) or gui_id == nil or gui_id == "" then
        return
    end
    pcall(function() RET.gui:call("setWeaponItemID", gui_id) end)
    pcall(function()
        local wt = RET.gui:call("findWeaponTypeData", gui_id)
        if not wt then return end
        RET.gui:call("setWeaponTypeData", wt)
        local state = tostring(wt:get_field("StateName") or "")
        if state == "" then return end
        local te = RET.gui:get_field("TypeElement")
        if not te then return end
        local panel = te:call("get_Element")
        if panel then
            panel:call("set_PlayState", state)
        end
    end)
    pcall(function()
        if not re8vr or not re8vr.weapon or not GameObject then return end
        local wgo = re8vr.weapon:call("get_GameObject")
        if not wgo then return end
        local ch = GameObject.get_component(wgo, "app.ReticleChanger")
        if not ch then return end
        ch:call("setupReticle")
        ch:call("updateReticleMesh")
    end)
end

function RET.is_aiming()
    local player = re8vr and re8vr.player
    if not H.managed_alive(player) then
        return false
    end
    local aiming = false
    pcall(function()
        local st = nil
        if GameObject and GameObject.get_component then
            st = GameObject.get_component(player, "app.PlayerStatus")
        end
        if not st then return end
        aiming = st:call("get_isGunAim") == true or st:call("get_IsAim") == true
    end)
    return aiming
end

function RET.sync_hold()
    local aiming = RET.is_aiming()
    if aiming == RET._aiming then
        return
    end
    RET._aiming = aiming
    if not H.managed_alive(RET.gui) then
        return
    end
    if aiming then
        pcall(function() RET.gui:call("notifyHold") end)
    else
        pcall(function() RET.gui:call("notifyNoHold") end)
    end
end

function RET.restore_show(id)
    local gui_id = RET.weapon_gui_id(id)
    local ctrl = select(1, RET.find_controller())
    if H.managed_alive(ctrl) then
        pcall(function() ctrl:call("set_DisableDraw", false) end)
        if gui_id ~= "" then
            pcall(function() ctrl:call("openReticle", gui_id) end)
        end
        pcall(function() ctrl:call("updateReticle") end)
    end
    RET.resolve(true)
    RET.apply_type(gui_id)
end

function RET.apply(want_hide)
    if want_hide then
        return
    end
    RET.resolve(true)
    local id = tostring(rawget(_G, "__re8_active_weapon_id") or "")
    RET.restore_show(id)
end

function RET.tick()
    local id = tostring(rawget(_G, "__re8_active_weapon_id") or "")
    local want = RET.want_hide() == true
    local now = os.clock()
    if want then
        if RET._hide_since == nil then
            RET._hide_since = now
        end
        if (now - RET._hide_since) < 0.15 then
            want = RET.hide
        end
    else
        RET._hide_since = nil
    end
    local gui_now = RET.weapon_gui_id(id)
    local id_changed = (not want) and gui_now ~= "" and gui_now ~= (RET._applied_gui or "")
    RET.hide = want
    if (want ~= RET.applied_hide) or id_changed then
        RET.apply(want)
        RET.applied_hide = want
        if want then
            RET._applied_gui = nil
            RET._aiming = nil
        elseif gui_now ~= "" then
            RET._applied_gui = gui_now
        end
    end
    if want ~= true then
        RET.sync_hold()
    end
end

--------------------------------------------------
-- Hooks
--------------------------------------------------

re.on_application_entry("UpdateMotion", function()
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("visuals.motion") end
    local pub_zones = rawget(_G, "__re8_holster_publish_visual_zones")
    if type(pub_zones) == "function" then
        pcall(pub_zones)
    end
    H.tick_slot(HIP)
    H.tick_slot(KNIFE)
    H.tick_slot(MED)
    RET.tick()
    if _on then _p.finish("visuals.motion") end
end)

re.on_application_entry("LateUpdateBehavior", function()
    if MED.cfg.enabled ~= true then
        rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
        return
    end
    if MED.fly_active() then
        rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
        return
    end
    if rawget(_G, "__vr_ammo_insert_arm_follow") == true
        or rawget(_G, "__vr_ammo_insert_active") == true
        or rawget(_G, "__vr_ammo_in_left_hand") == true
        or rawget(_G, "__vr_ammo_blocks_weapon_holster") == true then
        return
    end
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("visuals.late") end
    if rawget(_G, "__re8_medicine_in_hand") == true then
        pcall(function() MED.apply_in_hand_transform() end)
    end
    pcall(function() MED.tick_rhp() end)
    if _on then _p.finish("visuals.late") end
end)

re.on_application_entry("PrepareRendering", function()
    if MED.cfg.enabled ~= true then
        rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
        return
    end
    if MED.fly_active() then
        rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
        return
    end
    if rawget(_G, "__vr_ammo_insert_arm_follow") == true
        or rawget(_G, "__vr_ammo_insert_active") == true
        or rawget(_G, "__vr_ammo_in_left_hand") == true
        or rawget(_G, "__vr_ammo_blocks_weapon_holster") == true then
        return
    end
    local _p = rawget(_G, "__re8_perf")
    local _on = _p and _p.enabled == true
    if _on then _p.begin("visuals.prep") end
    if rawget(_G, "__re8_medicine_in_hand") == true then
        pcall(function() MED.apply_in_hand_transform() end)
    end
    pcall(function() MED.tick_rhp() end)
    if _on then _p.finish("visuals.prep") end
end)

re.on_frame(function()
    if not H.ready then
        H.ensure_ready()
    end
    RET.tick()
end)

re.on_pre_gui_draw_element(function(element, context)
    if RET.hide ~= true then
        return true
    end
    local go = nil
    pcall(function() go = element:call("get_GameObject") end)
    if not H.managed_alive(go) then
        return true
    end
    local name = nil
    pcall(function() name = go:call("get_Name") end)
    if type(name) == "string" and RET.go_names[name] then
        return false
    end
    return true
end)

re.on_draw_ui(function()
end)

re.on_script_reset(function()
    RET.clear()
    rawset(_G, "__re8_medicine_hand_pose_rh_active", false)
    H.destroy(HIP)
    H.destroy(KNIFE)
    H.destroy(MED)
    HIP.st.item_id = ""
    KNIFE.st.item_id = ""
    MED.st.item_id = ""
    HIP.st.mesh_path = ""
    KNIFE.st.mesh_path = ""
    MED.st.mesh_path = ""
    HIP.st.mdf_path = ""
    KNIFE.st.mdf_path = ""
    MED.st.mdf_path = ""
    H.ready = false
    H.load_logged = false
    HIP.st.status = "reset"
    KNIFE.st.status = "reset"
    MED.st.status = "reset"
end)

log.info("[re8_vr_holster_visuals] Parsed (hip / knife / medicine meshes; deferred ready)")


local function install_glasses_scope()
    local BIND_TTL = 0.35
    local SLOTS = {
        {
            field = "CameraEffectGameObject",
            draw = true,
            x = 0.003000000026077031,
            y = -0.0149999912828207,
            z = -0.06600000402331352,
            scale = 2.640000104904175,
        },
        {
            field = "VRLeftCameraEffectGameObject",
            draw = false,
            x = 0.029999999329447746,
            y = -0.004999999888241291,
            z = -0.09799999743700027,
            scale = 1.0299999713897705,
        },
        {
            field = "VRRightCameraEffectGameObject",
            draw = false,
            x = -0.029999999329447746,
            y = -0.004999999888241291,
            z = -0.09799999743700027,
            scale = 1.0,
        },
    }
    local PAUSE_GUI = {
        PauseMenu = true,
        GUIPause = true,
        MultiSubMenu = true,
        FileMenu = true,
        GUIConfirm = true,
        GUISaveLoad = true,
    }
    local LIVE = {
        append = nil,
        t = 0.0,
        pause_t = 0.0,
        pause_follow = false,
        menu_t = 0.0,
        menu_on = nil,
        scale_t = 0.0,
        scale_on = nil,
    }
    local HOLD = {}
    local TYPEOF = {}
    local OUT_ALL = 31
    local OUT_READY = false

    local function alive(obj)
        if obj == nil then return false end
        local ok, addr = pcall(function() return obj:get_address() end)
        return ok and addr ~= nil and addr ~= 0
    end

    local function read_system_string(s)
        if s == nil then return nil end
        if type(s) == "string" then
            if s == "" then return nil end
            return s
        end
        local ok, v = pcall(function() return s:call("ToString") end)
        if ok and type(v) == "string" and v ~= "" then return v end
        return nil
    end

    local function vec3_xyz(v)
        if v == nil then return nil end
        local x, y, z
        pcall(function()
            x = v.x
            y = v.y
            z = v.z
        end)
        if type(x) == "function" then
            pcall(function()
                x = v:x()
                y = v:y()
                z = v:z()
            end)
        end
        if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
            return nil
        end
        return x, y, z
    end

    local function typeof_of(name)
        if TYPEOF[name] ~= nil then
            if TYPEOF[name] == false then return nil end
            return TYPEOF[name]
        end
        local t = nil
        pcall(function() t = sdk.typeof(name) end)
        if t == nil then
            pcall(function()
                local td = sdk.find_type_definition(name)
                if td then t = td:get_runtime_type() end
            end)
        end
        TYPEOF[name] = t or false
        if t == nil then return nil end
        return t
    end

    local function get_comp(go, name)
        if not alive(go) then return nil end
        local t = typeof_of(name)
        if t == nil then return nil end
        local c = nil
        pcall(function() c = go:call("getComponent(System.Type)", t) end)
        if alive(c) then return c end
        return nil
    end

    local function is_glasses_id(id, go_name)
        local s = string.lower(tostring(id or ""))
        if string.find(s, "glasses", 1, true) then return true end
        local n = string.lower(tostring(go_name or ""))
        return string.find(n, "glasses", 1, true) ~= nil
    end

    local function append_from_go(go)
        return get_comp(go, "app.WeaponGlassesAppend")
    end

    local function find_append_inventory()
        local mgr = sdk.get_managed_singleton("app.InventoryManager")
        if not alive(mgr) then return nil end
        local inv = nil
        pcall(function() inv = mgr:call("get_activeInventory") end)
        if not alive(inv) then
            pcall(function() inv = mgr:get_field("_Inventory") end)
        end
        if not alive(inv) then return nil end
        local list = nil
        pcall(function() list = inv:call("get_items") end)
        if not alive(list) then
            pcall(function() list = inv:get_field("<items>k__BackingField") end)
        end
        if not alive(list) then return nil end
        local items = nil
        pcall(function() items = list:get_field("mItems") end)
        if not items then
            pcall(function() items = list:get_field("_items") end)
        end
        local n = 0
        local list_indexed = false
        if items then
            pcall(function() n = tonumber(items:get_size()) or 0 end)
            if n <= 0 then
                pcall(function() n = tonumber(items:size()) or 0 end)
            end
        else
            pcall(function() n = tonumber(list:call("get_Count")) or 0 end)
            list_indexed = n > 0
        end
        if n <= 0 then return nil end
        if n > 64 then n = 64 end
        local i = 0
        while i < n do
            local info = nil
            if list_indexed then
                pcall(function() info = list:call("get_Item", i) end)
            else
                pcall(function() info = items:get_element(i) end)
            end
            if alive(info) then
                local item = nil
                local owner = nil
                pcall(function() item = info:get_field("Item") end)
                if not alive(item) then item = info end
                pcall(function() owner = info:get_field("Owner") end)
                if not alive(owner) then
                    pcall(function() owner = info:get_field("<owner>k__BackingField") end)
                end
                local id = nil
                local go_name = nil
                if alive(item) then
                    pcall(function() id = item:call("get_weaponName") end)
                    if type(id) ~= "string" or id == "" then
                        pcall(function() id = read_system_string(item:get_field("ItemDataID")) end)
                    end
                    if (type(id) ~= "string" or id == "") then
                        pcall(function()
                            local go = item:call("get_GameObject")
                            if go then id = go:call("get_Name") end
                        end)
                    end
                end
                if alive(owner) then
                    pcall(function() go_name = owner:call("get_Name") end)
                end
                if is_glasses_id(id, go_name) then
                    local append = append_from_go(owner)
                    if alive(append) then return append end
                    if alive(item) then
                        local item_go = nil
                        pcall(function() item_go = item:call("get_GameObject") end)
                        append = append_from_go(item_go)
                        if alive(append) then return append end
                    end
                end
            end
            i = i + 1
        end
        return nil
    end

    local function find_append_scene()
        local sm = sdk.get_native_singleton("via.SceneManager")
        local td = sdk.find_type_definition("via.SceneManager")
        local t = typeof_of("app.WeaponGlassesAppend")
        if sm == nil or td == nil or t == nil then return nil end
        local sc = nil
        pcall(function() sc = sdk.call_native_func(sm, td, "get_CurrentScene()") end)
        if sc == nil then return nil end
        local arr = nil
        pcall(function() arr = sc:call("findComponents(System.Type)", t) end)
        if arr == nil then return nil end
        local n = 0
        pcall(function()
            if arr.get_size then n = tonumber(arr:get_size()) or 0 end
        end)
        if n <= 0 then
            pcall(function() n = tonumber(arr:call("get_Count")) or 0 end)
        end
        if n > 8 then n = 8 end
        local i = 0
        while i < n do
            local e = nil
            pcall(function()
                if arr.get_element then
                    e = arr:get_element(i)
                else
                    e = arr[i]
                end
            end)
            if alive(e) then return e end
            i = i + 1
        end
        return nil
    end

    local function bind_append()
        local now = os.clock()
        if alive(LIVE.append) and (now - (LIVE.t or 0)) < BIND_TTL then
            return LIVE.append
        end
        local append = find_append_inventory()
        if not alive(append) then
            append = find_append_scene()
        end
        LIVE.append = alive(append) and append or nil
        LIVE.t = now
        return LIVE.append
    end

    local function scope_on(append)
        if not alive(append) then return false end
        local scope = false
        pcall(function() scope = append:get_field("IsGlassesScopeEnabled") == true end)
        return scope == true
    end

    local function plane_go(append, field)
        if not alive(append) then return nil end
        local go = nil
        pcall(function() go = append:get_field(field) end)
        if alive(go) then return go end
        return nil
    end

    local function plane_transform(go)
        if not alive(go) then return nil end
        local tf = nil
        pcall(function() tf = go:call("get_Transform") end)
        if alive(tf) then return tf end
        return nil
    end

    local function read_draw(go)
        if not alive(go) then return false end
        local draw = false
        pcall(function() draw = go:call("get_Draw") == true end)
        if draw then return true end
        pcall(function() draw = go:call("get_DrawSelf") == true end)
        return draw == true
    end

    local function set_draw(go, want)
        if not alive(go) then return end
        pcall(function() go:call("set_DrawSelf", want == true) end)
        pcall(function() go:call("set_Draw", want == true) end)
    end

    local function set_local_pos(tf, x, y, z)
        if not alive(tf) then return end
        pcall(function()
            tf:call("set_LocalPosition", Vector3f.new(x, y, z))
        end)
    end

    local function set_local_scale(tf, s)
        if not alive(tf) then return end
        pcall(function()
            tf:call("set_LocalScale", Vector3f.new(s, s, s))
        end)
    end

    local function set_output_all(go)
        if OUT_READY ~= true then
            pcall(function()
                local et = sdk.find_type_definition("via.render.RenderOutputID")
                local f = et and et:get_field("All")
                local v = f and f:get_data(nil)
                if v ~= nil then OUT_ALL = v end
            end)
            OUT_READY = true
        end
        local mesh = get_comp(go, "via.render.Mesh")
        if not alive(mesh) then return end
        pcall(function() mesh:call("set_RenderOutputID", OUT_ALL) end)
    end

    local function menu_frozen()
        local now = os.clock()
        if (now - (LIVE.menu_t or 0)) < 0.12 and LIVE.menu_on ~= nil then
            return LIVE.menu_on == true
        end
        LIVE.menu_t = now
        local mm = sdk.get_managed_singleton("app.MenuManager")
        local on = false
        if alive(mm) then
            pcall(function() on = mm:get_field("FreezeMenuOpen") == true end)
            if not on then
                pcall(function()
                    on = mm:call("isOpenMultiSubMenu") == true
                end)
            end
        end
        LIVE.menu_on = on == true
        return LIVE.menu_on
    end

    local function scene_frozen()
        local now = os.clock()
        if (now - (LIVE.scale_t or 0)) < 0.12 and LIVE.scale_on ~= nil then
            return LIVE.scale_on == true
        end
        LIVE.scale_t = now
        local scale = nil
        pcall(function()
            local sm = sdk.get_native_singleton("via.SceneManager")
            local td = sdk.find_type_definition("via.SceneManager")
            if sm == nil or td == nil then return end
            local scene = sdk.call_native_func(sm, td, "get_CurrentScene()")
            if scene == nil then return end
            scale = scene:call("get_TimeScale()")
            if type(scale) ~= "number" then
                scale = scene:call("get_TimeScale")
            end
        end)
        LIVE.scale_on = type(scale) == "number" and scale < 0.001
        return LIVE.scale_on == true
    end

    local function pause_open()
        if (os.clock() - (LIVE.pause_t or 0)) < 0.50 then return true end
        if rawget(_G, "__vr_settings_menu_open") == true then return true end
        if menu_frozen() then return true end
        return scene_frozen()
    end

    local function head_pose()
        if vrmod == nil or vrmod.get_transform == nil then return nil end
        if vrmod.is_hmd_active and vrmod:is_hmd_active() ~= true then return nil end
        local m = nil
        pcall(function() m = vrmod:get_transform(0) end)
        if not m then return nil end
        local q = nil
        pcall(function()
            if m.to_quat then q = m:to_quat() end
        end)
        local off = nil
        pcall(function()
            if vrmod.get_rotation_offset then off = vrmod:get_rotation_offset() end
        end)
        if off and q then
            pcall(function() q = off * q end)
        end
        if q == nil then return nil end
        return q
    end

    local function quat_delta(from_q, to_q)
        if from_q == nil or to_q == nil then return to_q end
        local d = nil
        pcall(function()
            if from_q.inverse then d = from_q:inverse() * to_q end
        end)
        if d == nil then
            pcall(function()
                if from_q.conjugate then d = from_q:conjugate() * to_q end
            end)
        end
        return d or to_q
    end

    local function read_local_rot(tf)
        if not alive(tf) then return nil end
        local q = nil
        pcall(function() q = tf:call("get_LocalRotation") end)
        return q
    end

    local function release_hold(append)
        local i = 1
        while i <= #SLOTS do
            local hold = HOLD[i]
            if hold and hold.rot and alive(append) then
                local tf = plane_transform(plane_go(append, SLOTS[i].field))
                if alive(tf) then
                    pcall(function() tf:call("set_LocalRotation", hold.rot) end)
                end
            end
            HOLD[i] = nil
            i = i + 1
        end
        LIVE.pause_follow = false
    end

    local function pin_plane(i, tf, slot)
        local q = head_pose()
        if q == nil then return false end
        if HOLD[i] == nil then
            HOLD[i] = { rot = read_local_rot(tf), hmd = q }
        end
        local hold = HOLD[i]
        local delta = quat_delta(hold.hmd, q)
        local lx, ly, lz = slot.x, slot.y, slot.z
        pcall(function()
            local v = delta * Vector3f.new(slot.x, slot.y, slot.z)
            if v and type(v.x) == "number" then
                lx, ly, lz = v.x, v.y, v.z
            end
        end)
        local face = delta
        if hold.rot then
            pcall(function() face = delta * hold.rot end)
        end
        local ok = false
        pcall(function()
            tf:call("set_LocalPosition", Vector3f.new(lx, ly, lz))
            if face then tf:call("set_LocalRotation", face) end
            ok = true
        end)
        return ok
    end

    local function hide_planes(append)
        local i = 1
        while i <= #SLOTS do
            local go = plane_go(append, SLOTS[i].field)
            if alive(go) and read_draw(go) then
                set_draw(go, false)
            end
            i = i + 1
        end
    end

    local function apply_planes()
        local append = bind_append()
        if not alive(append) then
            if LIVE.pause_follow then release_hold(nil) end
            return
        end
        local scope = scope_on(append) == true
        if scope ~= true then
            hide_planes(append)
            if LIVE.pause_follow then release_hold(append) end
            return
        end
        local follow = pause_open()
        if not follow and LIVE.pause_follow then
            release_hold(append)
        end
        local i = 1
        while i <= #SLOTS do
            local slot = SLOTS[i]
            local go = plane_go(append, slot.field)
            if alive(go) then
                set_draw(go, slot.draw == true)
                local tf = plane_transform(go)
                if slot.draw == true and alive(tf) then
                    local pinned = false
                    if follow then
                        pinned = pin_plane(i, tf, slot)
                    end
                    if not pinned then
                        set_local_pos(tf, slot.x, slot.y, slot.z)
                    end
                    set_local_scale(tf, slot.scale)
                    set_output_all(go)
                end
            end
            i = i + 1
        end
        LIVE.pause_follow = follow
    end

    re.on_pre_gui_draw_element(function(element)
        local go = nil
        pcall(function() go = element:call("get_GameObject") end)
        if not alive(go) then return true end
        local name = nil
        pcall(function() name = go:call("get_Name") end)
        name = read_system_string(name)
        if name and PAUSE_GUI[name] then
            LIVE.pause_t = os.clock()
        end
        return true
    end)

    re.on_application_entry("PrepareRendering", function()
        apply_planes()
    end)

    re.on_application_entry("BeginRendering", function()
        if pause_open() then
            apply_planes()
        end
    end)

    re.on_script_reset(function()
        LIVE.append = nil
        LIVE.t = 0.0
        LIVE.pause_t = 0.0
        LIVE.pause_follow = false
        HOLD[1] = nil
        HOLD[2] = nil
        HOLD[3] = nil
    end)
end

install_glasses_scope()
log.info("[re8_vr_holster_visuals] glasses scope overlay active")

return {}
