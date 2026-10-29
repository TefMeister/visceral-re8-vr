-- visceral_re8_whitepoint.lua -- Village's "adaptive lighting" (eye adaptation) experiments, live (2026-10-29, Fable, Tefa
-- in the headset). Two knobs, both re-applied every frame at BeginRendering pre (after the game's ToneMapController has
-- written its own values, before the frame is drawn), because every one-off write is undone within a second.
--
-- What is known live [verified-live 2026-10-29, Village, n=1]:
-- - The main camera's via.render.ToneMapping keeps EV = 3 everywhere (the authored base). AutoExposure is Enable (0).
-- - The ADAPTED exposure is computed on the graphics card; the CPU getter only shows it after calcRealEV():
--   get_SnappedRealEV read 3.00 before calcRealEV and 6.17 after it, outdoors. THIS number is the adaptive lighting.
-- - MinWhitePoint / MaxWhitePoint (11/25 indoors, 5.6/15 or 7/15 outdoors, 2/5 in a dark spot) are the level's per-area
--   tone-curve range; pinning both to one value did NOT stop the light changing (Tefa, mode "value" 9.0), so they are
--   not the adaptation's limits. Kept here as a knob ("pin"), default off.
-- - BrightAdaptationRate 0.035 / DarkAdaptationRate 0.05 are the adaptation's speeds; the controller rewrites them every
--   late update from its _UpdateData, so they too must be written every frame.
-- - Switching AutoExposure off (2) leaves the fixed EV 3, far too bright outdoors: the golden veil (22:27). Not used.
--
-- Knobs, in reframework/data/visceral_re8/whitepoint.json (re-read every two seconds) and the REFramework menu:
--   adapt = "game"    the game's own speeds (nothing written)
--           "freeze"  both speeds 0 every frame: does the adapted exposure stop moving? (the experiment of 22:50)
--           "instant" both speeds 1 every frame: no slow drift, the exposure follows the view at once
--   pin   = "off" | "mean" | "min" | "max" | "value"   the white-point pin (see above; default off)
-- The log line every 5 s carries RealEV (after calcRealEV), the game's pair, and what was written.
local TAG = "[visceral-re8-whitepoint]"
local MODE_FILE = "visceral_re8/whitepoint.json"
local PIN_MODES = { "off", "mean", "min", "max", "value" }
local ADAPT_MODES = { "game", "freeze", "instant" }
local cfg = { mode = "off", value = 8.0, adapt = "game" }
local frame, last_log, writes = 0, 0, 0
local seen = { lo = -1, hi = -1, real = -1, brate = -1, drate = -1 }

local function load_cfg()
    local ok, d = pcall(json.load_file, MODE_FILE)
    if ok and type(d) == "table" then
        if type(d.mode) == "string" and d.mode ~= cfg.mode then log.info(TAG .. " pin " .. cfg.mode .. " -> " .. d.mode); cfg.mode = d.mode end
        if type(d.adapt) == "string" and d.adapt ~= cfg.adapt then log.info(TAG .. " adapt " .. cfg.adapt .. " -> " .. d.adapt); cfg.adapt = d.adapt end
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
    local t = tonemapping()
    if not t then return end
    local lo, hi = t:call("get_MinWhitePoint"), t:call("get_MaxWhitePoint")
    if type(lo) == "number" and type(hi) == "number" then seen.lo, seen.hi = lo, hi end
    seen.brate, seen.drate = t:call("get_BrightAdaptationRate") or -1, t:call("get_DarkAdaptationRate") or -1
    local wrote = {}
    if cfg.adapt == "freeze" then
        t:call("set_BrightAdaptationRate", 0.0); t:call("set_DarkAdaptationRate", 0.0); wrote[#wrote + 1] = "rates 0"
    elseif cfg.adapt == "instant" then
        t:call("set_BrightAdaptationRate", 1.0); t:call("set_DarkAdaptationRate", 1.0); wrote[#wrote + 1] = "rates 1"
    end
    if cfg.mode ~= "off" and type(lo) == "number" and type(hi) == "number" then
        local v
        if cfg.mode == "mean" then v = math.sqrt(math.max(lo, 0.0001) * math.max(hi, 0.0001))
        elseif cfg.mode == "min" then v = lo
        elseif cfg.mode == "max" then v = hi
        else v = cfg.value end
        t:call("set_MinWhitePoint", v); t:call("set_MaxWhitePoint", v)
        wrote[#wrote + 1] = string.format("pin %.2f", v)
    end
    if #wrote > 0 then writes = writes + 1 end
    local now = os.clock()
    if now - last_log >= 5.0 then
        last_log = now
        t:call("calcRealEV")
        seen.real = t:call("get_SnappedRealEV") or -1
        log.info(string.format("%s adapt=%s pin=%s: RealEV %.2f (EV %.2f), the game's pair %.2f..%.2f, rates %.3f/%.3f -> %s (%d frames written)",
            TAG, cfg.adapt, cfg.mode, seen.real, t:call("get_EV") or -1, seen.lo, seen.hi, seen.brate, seen.drate,
            #wrote > 0 and table.concat(wrote, ", ") or "nothing", writes))
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Visceral RE8: steady light") then return end
    local ai = 1
    for i, m in ipairs(ADAPT_MODES) do if m == cfg.adapt then ai = i end end
    local ca, na = imgui.combo("Eye adaptation", ai, ADAPT_MODES)
    if ca and ADAPT_MODES[na] then cfg.adapt = ADAPT_MODES[na]; save_cfg(); log.info(TAG .. " adapt -> " .. cfg.adapt) end
    local idx = 1
    for i, m in ipairs(PIN_MODES) do if m == cfg.mode then idx = i end end
    local changed, new = imgui.combo("White-point pin", idx, PIN_MODES)
    if changed and PIN_MODES[new] then cfg.mode = PIN_MODES[new]; save_cfg(); log.info(TAG .. " pin -> " .. cfg.mode) end
    local c2, nv = imgui.slider_float("Fixed value (pin 'value')", cfg.value, 0.5, 30.0, "%.2f")
    if c2 then cfg.value = nv; save_cfg() end
    imgui.text(string.format("RealEV %.2f, area pair %.2f..%.2f, rates %.3f/%.3f, %d frames written", seen.real, seen.lo, seen.hi, seen.brate, seen.drate, writes))
    imgui.tree_pop()
end)
