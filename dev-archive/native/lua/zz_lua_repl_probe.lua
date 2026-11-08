-- zz_lua_repl_probe.lua -- a file-driven Lua prompt inside the running game, for searching it with nobody at the keys
-- (2026-11-08, home PC, Opus; first used for Tefa's "first time getting a new gun" animation hunt).
--
-- Drop a Lua chunk into reframework/data/lua_repl/in.lua whose FIRST line is "--seq N" (a new number each time; REFramework's
-- Lua has no os.remove, so the number is what marks it done); on the next frame it runs once (protected). Inside it,
-- out(...) writes one line to reframework/data/lua_repl/out.txt (the file is started fresh for every chunk) and the result
-- or the error goes there too. Global table R keeps values between chunks. Testing only: archived when the hunt is done.

if reframework:get_game_name() ~= "re8" then return end

local DIR = "lua_repl"
local IN, OUT = DIR .. "/in.lua", DIR .. "/out.txt"
R = R or {}
local lines = {}

local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, "\t")
end

local function flush()
    local f = io.open(OUT, "w")   -- REFramework sandboxes io to reframework/data
    if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
end

local busy, last_seq, frames = false, nil, 0
re.on_frame(function()
    frames = frames + 1
    if busy or frames % 12 ~= 0 then return end   -- a look about five times a second
    local f = io.open(IN, "r")
    if not f then return end
    local code = f:read("*a"); f:close()
    local seq = code:match("^%-%-seq (%d+)")
    if seq == nil or seq == last_seq then return end
    last_seq = seq
    busy = true
    lines = {}
    local env = setmetatable({ out = out }, { __index = _G })
    local chunk, err = load(code, "in.lua", "t", env)
    if not chunk then out("COMPILE ERROR", err) else
        local ok, res = pcall(chunk)
        if ok then out("OK", res) else out("ERROR", res) end
    end
    flush()
    busy = false
end)

log.info("[lua-repl] ready: drop reframework/data/lua_repl/in.lua")
