-- visceral_re8_emporium_layout.lua -- WHERE EACH SETTING SITS in the VR Options Emporium (2026-11-15).
--
-- Tefa (2026-11-15): "we need all the sub menus to look the same, like gunsmithy ... it has all the things needed and is
-- neatly categorized, and has sliders". Three tabs: 1 Comfort and Controls, 2 Game Settings, 3 Graphics and Display.
-- Every tab opens the game's own Gunsmithy (visceral_re8_emporium_shop.lua): its left column (the guns, to the game) is
-- the tab's CATEGORIES, its four upgrade rows are that category's settings.
-- Tefa (2026-11-15): a setting that is not built yet stays HIDDEN until it works (no "coming soon" rows): an entry with
-- `hidden = true` is left out.
--
-- This file only sorts; it changes no setting. The settings themselves are still handed over by every Visceral script
-- in _G.VISCERAL_OPTIONS (shape: visceral_re8_emporium.lua's header). A script may name its own place with
-- `place = { tab = "comfort" | "game" | "graphics", cat = "..." }`; otherwise the PLACES list below finds it by the start
-- of its label, and anything still unplaced goes to its old tab (settings -> Game Settings) under "Other".
-- Read by visceral_re8_emporium_shop.lua through _G.VISCERAL_EMPORIUM_LAYOUT.

local M = {}

M.ROWS = 4                  -- the Gunsmithy shows four upgrade rows; a bigger category becomes "Name (1/2)", "Name (2/2)"
local CACHE_S = 0.1         -- the sorted lists are kept this long (the Gunsmithy asks every frame)

M.TABS = {
    { tab = "comfort",  name = "Comfort and Controls", motto = "Easy on the stomach!" },
    { tab = "game",     name = "Game Settings",        motto = "Everything in its place!" },
    { tab = "graphics", name = "Graphics and Display", motto = "A feast for the eyes!" },
}

-- the categories of each tab, in the order the column shows them (a category with nothing in it is not shown)
M.CATS = {
    comfort  = { "Turning", "Camera", "Play space" },
    game     = { "Holsters", "Guns and magazines", "Recoil and rumble", "Hands and smoothing" },
    graphics = { "HUD", "Brightness" },
}

-- { start of the label (a Lua pattern), tab, category }; the first match wins
local PLACES = {
    { "^Body turns",                       "comfort",  "Turning" },
    { "^Camera shake while walking",       "comfort",  "Camera" },       -- Tefa's "head bobbing"
    { "^Other camera shakes",              "comfort",  "Camera" },
    { "^Keep my view when Ethan examines", "comfort",  "Camera" },
    { "^Roomscale",                        "comfort",  "Play space" },
    { "^Set my standing height",           "comfort",  "Play space" },
    { "^Holsters$",                        "game",     "Holsters" },
    { "^%s+Hip holster",                   "game",     "Holsters" },
    { "^%s+Shoulder holster",              "game",     "Holsters" },
    { "^%s+Left chest",                    "game",     "Holsters" },
    { "^%s+Right chest",                   "game",     "Holsters" },
    { "^%s+Flashlight",                    "game",     "Holsters" },
    { "^%s+Inventory pocket",              "game",     "Holsters" },
    { "^The game's own new%-gun move",     "game",     "Guns and magazines" },
    { "^Play the new%-gun move",           "game",     "Guns and magazines" },
    { "^Thrown magazines",                 "game",     "Guns and magazines" },
    { "^How long they lie",                "game",     "Guns and magazines" },
    { "^Recoil",                           "game",     "Recoil and rumble" },
    { "^Gun shaking the controller",       "game",     "Recoil and rumble" },
    { "^Left hand on the gun only",        "game",     "Hands and smoothing" },
    { "^Smoothing",                        "game",     "Hands and smoothing" },
    { "^Crosshair",                        "graphics", "HUD" },
    { "^Ammo counter",                     "graphics", "HUD" },
    { "^Let the game adjust the brightness", "graphics", "Brightness" },
}
local OLD_TAB = { comfort = "comfort", settings = "game", graphics = "graphics" }

-- where one setting sits: tab key, category name (kept on the entry once found; the smoothing rows rename themselves
-- every frame, but always start with "Smoothing")
function M.place(e)
    if type(e.place) == "table" and e.place.tab then return e.place.tab, e.place.cat or "Other" end
    if e.__visceral_place then return e.__visceral_place[1], e.__visceral_place[2] end
    local label = tostring(e.label or "")
    local t, c = nil, nil
    for _, p in ipairs(PLACES) do
        if label:find(p[1]) then t, c = p[2], p[3]; break end
    end
    if t == nil then t, c = OLD_TAB[e.tab] or "game", "Other" end
    e.__visceral_place = { t, c }
    return t, c
end

local function by_order(a, b) return (a.order or 0) < (b.order or 0) end
local function has(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end return false end

local cache = {}
-- the tab's categories in column order: { { name = "Holsters (1/2)", rows = { entry, ... up to M.ROWS } }, ... }
function M.categories(tabkey)
    local now = os.clock()
    local c = cache[tabkey]
    if c and now - c.t < CACHE_S and c.n == #(_G.VISCERAL_OPTIONS or {}) then return c.list end
    local by = {}
    for _, e in ipairs(_G.VISCERAL_OPTIONS or {}) do
        if type(e) == "table" and not e.hidden then
            local t, cat = M.place(e)
            if t == tabkey then by[cat] = by[cat] or {}; table.insert(by[cat], e) end
        end
    end
    local names = {}
    for _, n in ipairs(M.CATS[tabkey] or {}) do if by[n] then names[#names + 1] = n end end
    local extra = {}
    for n in pairs(by) do if not has(M.CATS[tabkey], n) then extra[#extra + 1] = n end end
    table.sort(extra)
    for _, n in ipairs(extra) do names[#names + 1] = n end
    local out = {}
    for _, n in ipairs(names) do
        local list = by[n]
        table.sort(list, by_order)
        local pages = math.ceil(#list / M.ROWS)
        for p = 1, pages do
            local rows = {}
            for i = (p - 1) * M.ROWS + 1, math.min(#list, p * M.ROWS) do rows[#rows + 1] = list[i] end
            out[#out + 1] = { name = pages > 1 and string.format("%s (%d/%d)", n, p, pages) or n, rows = rows }
        end
    end
    cache[tabkey] = { t = now, n = #(_G.VISCERAL_OPTIONS or {}), list = out }
    return out
end

-- every setting of the tab, flat, in column order (for the screens that list them all)
function M.entries_for(tabkey)
    local out = {}
    for _, cat in ipairs(M.categories(tabkey)) do
        for _, e in ipairs(cat.rows) do out[#out + 1] = e end
    end
    return out
end

-- the longest column any tab needs (the Gunsmithy's column is shared: the left stick changes the tab in place)
function M.most_categories()
    local n = 0
    for _, t in ipairs(M.TABS) do n = math.max(n, #M.categories(t.tab)) end
    return n
end

_G.VISCERAL_EMPORIUM_LAYOUT = M
log.info("[visceral-emporium-layout] loaded: three tabs, " .. #PLACES .. " places")
return M
