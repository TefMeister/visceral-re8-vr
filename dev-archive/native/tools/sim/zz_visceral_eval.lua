-- zz_visceral_eval.lua -- A LIVE QUESTION-AND-ANSWER LINE INTO THE RUNNING GAME (dev tool, 2026-11-10, Fable).
-- Tefa 2026-11-09: "install the connector so you can see stuff in real time". praydog's connector cannot run on this
-- REFramework build (no .NET), so this is ours: a file in, a file out, no restart between questions.
--   in:  reframework/data/visceral_re8/eval_in.json   { "id": <number>, "code": "<lua chunk>" }
--   out: reframework/data/visceral_re8/eval_out.json  { "id": ..., "ok": true|false, "result": "<text>" }
-- The chunk runs on the game thread (before UpdateBehavior) with these helpers; E is a table that stays between
-- questions (keep objects, counters and hook results there):
--   S(name)         a managed singleton            N(name)        a native singleton
--   T(name)         a type definition              F(obj)         the object's field names and values (text)
--   M(obj|typename, [part of a name])  method names (text)        G(name)  a scene GameObject by name
--   C(go, type)     a component by type name       show(v)        any value as text
-- Driven by tools/sim/rv.py. Not shipped to players.
local IN, OUT = "visceral_re8/eval_in.json", "visceral_re8/eval_out.json"
local EVERY = 4
local last_id, tick = nil, 0
E = E or {}

local function show(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "nil" or t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return v end
    if t == "table" then
        if depth > 1 then return "{...}" end
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1)
            if #parts > 80 then parts[#parts + 1] = "..."; break end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    local ok, s = pcall(function()
        if v.w ~= nil and v.x ~= nil then return string.format("(%.4f %.4f %.4f %.4f)", v.x, v.y, v.z, v.w) end
        if v.z ~= nil and v.x ~= nil then return string.format("(%.4f %.4f %.4f)", v.x, v.y, v.z) end
        return nil
    end)
    if ok and s then return s end
    local ok2, name = pcall(function() return v:get_type_definition():get_full_name() end)
    if ok2 and name then return "<" .. name .. ">" end
    return tostring(v)
end
local function typedef_of(x)
    if type(x) == "string" then return sdk.find_type_definition(x) end
    local ok, td = pcall(function() return x:get_type_definition() end)
    return ok and td or nil
end
local STOP = { ["System.Object"] = true, ["via.Component"] = true, ["via.Behavior"] = true }
local helpers = {
    show = show,
    S = function(n) return sdk.get_managed_singleton(n) end,
    N = function(n) return sdk.get_native_singleton(n) end,
    T = function(n) return sdk.find_type_definition(n) end,
    F = function(obj)
        local td, out = typedef_of(obj), {}
        while td ~= nil and not STOP[td:get_full_name()] do
            for _, f in ipairs(td:get_fields()) do
                local name = f:get_name()
                local ok, val = pcall(function()
                    if f:is_static() then return f:get_data(nil) end
                    return obj:get_field(name)
                end)
                out[#out + 1] = (f:is_static() and "static " or "") .. name .. " = " .. (ok and show(val, 1) or "?")
            end
            td = td:get_parent_type()
        end
        return table.concat(out, "\n")
    end,
    M = function(x, pat)
        local td, out = typedef_of(x), {}
        while td ~= nil and td:get_full_name() ~= "System.Object" do
            for _, m in ipairs(td:get_methods()) do
                local n = m:get_name()
                if pat == nil or string.find(string.lower(n), string.lower(pat), 1, true) then
                    local ps = {}
                    for _, p in ipairs(m:get_param_types()) do ps[#ps + 1] = p:get_full_name() end
                    out[#out + 1] = td:get_name() .. "." .. n .. "(" .. table.concat(ps, ", ") .. ") -> " .. m:get_return_type():get_full_name()
                end
            end
            td = td:get_parent_type()
        end
        return table.concat(out, "\n")
    end,
    G = function(name)
        local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
        return scene and scene:call("findGameObject(System.String)", name)
    end,
    C = function(go, tname)
        local t = sdk.typeof(tname)
        return go and t and go:call("getComponent(System.Type)", t)
    end,
}
setmetatable(helpers, { __index = _G })

local function answer(id, ok, text)
    text = tostring(text or "")
    if #text > 60000 then text = string.sub(text, 1, 60000) .. "\n...(cut)" end
    json.dump_file(OUT, { id = id, ok = ok, result = text })
end

re.on_pre_application_entry("UpdateBehavior", function()
    tick = tick + 1
    if tick % EVERY ~= 0 then return end
    local q = json.load_file(IN)
    if q == nil or q.id == nil or q.id == last_id then return end
    last_id = q.id
    local chunk, err = load("return " .. (q.code or ""), "eval", "t", helpers)
    if chunk == nil then chunk, err = load(q.code or "", "eval", "t", helpers) end
    if chunk == nil then answer(q.id, false, "does not compile: " .. tostring(err)); return end
    local res = table.pack(pcall(chunk))
    if not res[1] then answer(q.id, false, res[2]); return end
    local parts = {}
    for i = 2, res.n do parts[#parts + 1] = show(res[i]) end
    answer(q.id, true, table.concat(parts, "\t"))
end)
log.info("[visceral-eval] the live question line is up (reframework/data/" .. IN .. ")")
