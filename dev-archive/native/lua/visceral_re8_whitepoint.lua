-- visceral_re8_whitepoint.lua -- Village's "adaptive lighting" held still (2026-10-29, Fable, Tefa in the headset).
--
-- Read live through the RE Engine MCP [verified-live 2026-10-29, Village, n=1]: the main camera's via.render.ToneMapping
-- keeps EV = 3 and SnappedRealEV = 3 everywhere; AutoExposure is Enable (0); what moves is the pair MinWhitePoint /
-- MaxWhitePoint, set per area by the level (11/25 indoors, 5.6/15 outdoors, 2/5 in a dark spot) and rewritten every frame,
-- so a one-off write is gone within a second. The adaptation happens on the graphics card BETWEEN those two limits
-- (the exposure value itself never moves, which is why RE2's pin of MinEV/MaxEV found nothing to pin here, and why
-- switching AutoExposure off left a fixed EV 3 that is far too bright outdoors: the golden veil).
--
-- So: every frame, after the game has written the area's limits and before the frame is drawn (BeginRendering pre),
-- both limits are set to ONE value taken from the area's own pair, leaving the adaptation no room. The value is a choice:
--   mean  = sqrt(min * max), the middle of the area's range (the default)
--   min / max = the area's own low / high end
--   value = a fixed number (cfg.value)
--   off   = nothing written (the game's own adaptive light)
-- Mode lives in reframework/data/visceral_re8/whitepoint.json ({"mode": "mean"}) and is re-read every two seconds, so a
-- session can switch modes with nobody at the keyboard; the REFramework menu has the same choice under
-- "Visceral RE8: steady light".
local TAG = "[visceral-re8-whitepoint]"
local MODE_FILE = "visceral_re8/whitepoint.json"
local MODES = { "off", "mean", "min", "max", "value" }
local cfg = { mode = "mean", value = 8.0 }
local frame, last_log, writes = 0, 0, 0
local seen = { lo = -1, hi = -1 }   -- the game's own pair as read this frame (before our write)

local function load_cfg()
    local ok, d = pcall(json.load_file, MODE_FILE)
    if ok and type(d) == "table" and type(d.mode) == "string" then
        if d.mode ~= cfg.mode then log.info(TAG .. " mode " .. cfg.mode .. " -> " .. d.mode) end
        cfg.mode = d.mode
        cfg.value = tonumber(d.value) or cfg.value
    end
end
local function save_cfg() pcall(json.dump_file, MODE_FILE, cfg) end
load_cfg()

local function tonemapping()
    local cam = sdk.get_primary_camera()
    if not cam then return nil end
    local go = cam:call("get_GameObject")
    if not go then return nil end
    return go:call("getComponent(System.Type)", sdk.typeof("via.render.ToneMapping"))
end

re.on_pre_application_entry("BeginRendering", function()
    frame = frame + 1
    if frame % 120 == 0 then load_cfg() end
    if cfg.mode == "off" then return end
    local t = tonemapping()
    if not t then return end
    local lo, hi = t:call("get_MinWhitePoint"), t:call("get_MaxWhitePoint")
    if type(lo) ~= "number" or type(hi) ~= "number" then return end
    seen.lo, seen.hi = lo, hi
    local v
    if cfg.mode == "mean" then v = math.sqrt(math.max(lo, 0.0001) * math.max(hi, 0.0001))
    elseif cfg.mode == "min" then v = lo
    elseif cfg.mode == "max" then v = hi
    else v = cfg.value end
    t:call("set_MinWhitePoint", v)
    t:call("set_MaxWhitePoint", v)
    writes = writes + 1
    local now = os.clock()
    if now - last_log >= 5.0 then
        last_log = now
        log.info(string.format("%s %s: the game's pair this frame %.2f..%.2f -> pinned %.2f (%d writes; EV %.2f)", TAG, cfg.mode, lo, hi, v, writes, t:call("get_EV") or -1))
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8: steady light") then return end
    local idx = 1
    for i, m in ipairs(MODES) do if m == cfg.mode then idx = i end end
    local changed, new = imgui.combo("Brightness held at", idx, MODES)
    if changed and MODES[new] then cfg.mode = MODES[new]; save_cfg(); log.info(TAG .. " mode -> " .. cfg.mode) end
    local c2, nv = imgui.slider_float("Fixed value (mode 'value')", cfg.value, 0.5, 30.0, "%.2f")
    if c2 then cfg.value = nv; save_cfg() end
    imgui.text(string.format("area pair seen %.2f..%.2f, %d writes", seen.lo, seen.hi, writes))
    imgui.tree_pop()
end)
