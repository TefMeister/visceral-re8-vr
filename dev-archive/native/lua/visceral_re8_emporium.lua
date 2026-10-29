-- Visceral RE8: the Visceral options, dressed as the Duke's Emporium (2026-10-29).
--
-- Tefa (idea 8003, 2026-10-28): "RE8 - customization menu with all the relevant settings only, made to look like the
-- Dukes emporium design ... RE8 with tabs like the Duke's shop"; 2026-10-29: "the 3 tabs should say Comfort Graphics
-- Settings ... use the game's actual duke's emporium when entering the shop as a blueprint".
--
-- The Emporium's shop screen is a dark red wall with three framed parchment cards (Supplies, Gunsmithy, The Duke's
-- Purse), each with a curly title and a one-line motto, and the shop's name and motto above them. Here the three cards
-- are the tabs; the picked card lights up and its settings open on a parchment sheet under the cards.
--
-- The window shows while REFramework's menu is open (it sits beside the old long menu, which stays for the fine
-- settings). Only the settings that matter are here, handed over by the scripts that own them through one shared list:
--
--   _G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}
--   table.insert(_G.VISCERAL_OPTIONS, { tab = "comfort" | "graphics" | "settings", order = <number>,
--       kind = "check" | "slider" | "choice" | "button", label = "...", help = "...",
--       get = function() return <value> end, set = function(v) ... end,          -- check, slider, choice
--       min = <n>, max = <n>, fmt = "%.2f",                                         -- slider
--       choices = { "...", ... },                                                   -- choice: get/set use 1..n
--       press = function() ... end })                                               -- button
--
-- Each script keeps saving its own settings the way it always has; this file only draws. Fonts: Georgia (Windows'
-- own) copied into reframework/fonts beside the game (never into the repo); without them the default font is used.
-- [hypothesis] until it has been seen in the game.

local SAVE_PATH = "visceral_re8/emporium.json"   -- under reframework/data: which card is open, shown or not

local TITLE = "The Visceral Emporium"
local MOTTO = "No one's a stranger to the Emporium"
local CARDS = {
    { tab = "comfort", name = "Comfort", motto = "Easy on the stomach!" },
    { tab = "graphics", name = "Graphics", motto = "A feast for the eyes!" },
    { tab = "settings", name = "Settings", motto = "Everything in its place!" },
}
local EMPTY_TEXT = "Nothing on these shelves yet, stranger."

-- sizes, in pixels at the default font size
local WIN_W, WIN_H = 760, 640
local CARD_H = 92
local CARD_GAP = 14
local MOTTO_UP = 0.42          -- the motto sits this far up from a card's bottom, as a share of its height
local SHEET_PAD = 18
local LABEL_W = 300            -- the controls start this far into the sheet
local CONTROL_W = 300

-- fonts (Georgia italic for the curly titles, like the Emporium's)
local FONT_TITLE = { file = "georgiai.ttf", size = 34 }
local FONT_CARD = { file = "georgiai.ttf", size = 26 }
local FONT_MOTTO = { file = "georgiai.ttf", size = 17 }
local FONT_BODY = { file = "georgia.ttf", size = 18 }

-- colours, 0xAABBGGRR as imgui wants them
local C = {
    wall = 0xF00E104A,         -- the Emporium's dark red wall
    title = 0xFFAAD6E8,        -- cream gold lettering
    card = 0xFF98B6C6,         -- parchment, in the shade
    card_hover = 0xFFAAC6D4,
    card_open = 0xFFCCE6F0,    -- the picked card, lit
    ink = 0xFF142030,          -- dark brown ink
    ink_faint = 0xFF3C5468,
    gold = 0xFF488CB0,         -- the frames
    sheet = 0xFFB8D6E2,        -- the parchment sheet under the cards
    field = 0xFF92B4C4,        -- a box or slider track on the sheet
    field_hover = 0xFF9CBECE,
    field_active = 0xFFA6C8D8,
    blood = 0xFF141878,        -- tick marks and slider knobs: dark red
    blood_lit = 0xFF181E96,
}

-- imgui's colour slots (ImGuiCol_*) and style slots (ImGuiStyleVar_*) used here
local COL = { Text = 0, WindowBg = 2, ChildBg = 3, PopupBg = 4, Border = 5, FrameBg = 7, FrameBgHovered = 8,
    FrameBgActive = 9, TitleBg = 10, TitleBgActive = 11, CheckMark = 18, SliderGrab = 19, SliderGrabActive = 20,
    Button = 21, ButtonHovered = 22, ButtonActive = 23, Header = 24, HeaderHovered = 25, HeaderActive = 26,
    Separator = 27 }
local VAR = { WindowRounding = 3, ChildRounding = 7, ChildBorderSize = 8, FrameRounding = 12, FrameBorderSize = 13 }
local ROUND_CARD = 6.0
local BORDER = 2.0

_G.VISCERAL_OPTIONS = _G.VISCERAL_OPTIONS or {}

local state = { open_tab = "comfort", shown = true }
do
    local ok, loaded = pcall(json.load_file, SAVE_PATH)
    if ok and type(loaded) == "table" then
        if type(loaded.open_tab) == "string" then state.open_tab = loaded.open_tab end
        if loaded.shown == false then state.shown = false end
    end
end
local function save() pcall(json.dump_file, SAVE_PATH, state) end

local function load_font(f)
    local ok, h = pcall(imgui.load_font, f.file, f.size)
    if ok then return h end
    return nil
end
local fonts = { title = load_font(FONT_TITLE), card = load_font(FONT_CARD), motto = load_font(FONT_MOTTO),
    body = load_font(FONT_BODY) }

local function with_font(h, fn)
    if h ~= nil and pcall(imgui.push_font, h) then
        fn()
        imgui.pop_font()
    else
        fn()
    end
end

local function push_colors(list)
    for _, p in ipairs(list) do imgui.push_style_color(p[1], p[2]) end
    return #list
end

-- Text centred in the window's width, at the current height.
local function centred(text, color)
    local ok, size = pcall(imgui.calc_text_size, text)
    local wsize = imgui.get_window_size()
    if ok and size and wsize then
        local pos = imgui.get_cursor_pos()
        imgui.set_cursor_pos(Vector2f.new(math.max(0, (wsize.x - size.x) * 0.5), pos.y))
    end
    imgui.text_colored(text, color)
end

local function entries_for(tab)
    local out = {}
    for _, e in ipairs(_G.VISCERAL_OPTIONS) do
        if type(e) == "table" and e.tab == tab then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.order or 0) < (b.order or 0) end)
    return out
end

local function draw_entry(e, i)
    local id = "##visceral_opt_" .. e.tab .. "_" .. i
    if e.kind == "button" then
        local n = push_colors({ { COL.Button, C.card }, { COL.ButtonHovered, C.card_hover }, { COL.ButtonActive, C.card_open } })
        if imgui.button(e.label .. id) and e.press then pcall(e.press) end
        imgui.pop_style_color(n)
    else
        imgui.text_colored(e.label, C.ink)
        imgui.same_line(LABEL_W)
        imgui.set_next_item_width(CONTROL_W)
        local okg, cur = pcall(e.get)
        if not okg then cur = nil end
        local changed, v = false, nil
        if e.kind == "check" then
            changed, v = imgui.checkbox(id, cur == true)
        elseif e.kind == "slider" then
            changed, v = imgui.slider_float(id, tonumber(cur) or e.min or 0.0, e.min or 0.0, e.max or 1.0, e.fmt or "%.2f")
        elseif e.kind == "choice" then
            changed, v = imgui.combo(id, tonumber(cur) or 1, e.choices or {})
        end
        if changed and e.set then pcall(e.set, v) end
    end
    if type(e.help) == "string" and e.help ~= "" then
        imgui.indent(SHEET_PAD)
        imgui.text_colored(e.help, C.ink_faint)
        imgui.unindent(SHEET_PAD)
    end
    imgui.spacing()
end

local function draw_cards()
    local wsize = imgui.get_window_size()
    local card_w = math.floor(((wsize and wsize.x or WIN_W) - 2 * SHEET_PAD - 2 * CARD_GAP) / #CARDS)
    imgui.set_cursor_pos(Vector2f.new(SHEET_PAD, imgui.get_cursor_pos().y))
    for i, card in ipairs(CARDS) do
        if i > 1 then imgui.same_line(0, CARD_GAP) end
        local open = state.open_tab == card.tab
        local face = open and C.card_open or C.card
        local n = push_colors({ { COL.Button, face }, { COL.ButtonHovered, open and C.card_open or C.card_hover },
            { COL.ButtonActive, C.card_open }, { COL.Text, C.ink }, { COL.Border, C.gold } })
        local pressed = false
        with_font(fonts.card, function()
            pressed = imgui.button(card.name .. "\n" .. "##visceral_card_" .. card.tab, Vector2f.new(card_w, CARD_H))
        end)
        imgui.pop_style_color(n)
        if pressed and not open then
            state.open_tab = card.tab
            save()
        end
    end
    -- the mottos under the card names, as on the shop's cards (drawn over the lower half of each card)
    local below = imgui.get_cursor_pos().y
    imgui.set_cursor_pos(Vector2f.new(SHEET_PAD, below - CARD_H * MOTTO_UP))
    with_font(fonts.motto, function()
        for i, card in ipairs(CARDS) do
            local x = SHEET_PAD + (i - 1) * (card_w + CARD_GAP)
            local ok, size = pcall(imgui.calc_text_size, card.motto)
            local tw = ok and size and size.x or 0
            imgui.set_cursor_pos(Vector2f.new(x + math.max(0, (card_w - tw) * 0.5), imgui.get_cursor_pos().y))
            imgui.text_colored(card.motto, C.ink)
            if i < #CARDS then imgui.same_line() end
        end
    end)
    imgui.set_cursor_pos(Vector2f.new(SHEET_PAD, below))
end

local function draw_sheet()
    local list = entries_for(state.open_tab)
    local wsize = imgui.get_window_size()
    local pos = imgui.get_cursor_pos()
    local w = (wsize and wsize.x or WIN_W) - 2 * SHEET_PAD
    local h = (wsize and wsize.y or WIN_H) - pos.y - SHEET_PAD
    imgui.set_cursor_pos(Vector2f.new(SHEET_PAD, pos.y))
    local n = push_colors({ { COL.ChildBg, C.sheet }, { COL.Border, C.gold }, { COL.Text, C.ink },
        { COL.FrameBg, C.field }, { COL.FrameBgHovered, C.field_hover }, { COL.FrameBgActive, C.field_active },
        { COL.CheckMark, C.blood }, { COL.SliderGrab, C.blood }, { COL.SliderGrabActive, C.blood_lit },
        { COL.PopupBg, C.sheet }, { COL.Header, C.field }, { COL.HeaderHovered, C.field_hover },
        { COL.HeaderActive, C.field_active }, { COL.Separator, C.gold } })
    if imgui.begin_child_window("##visceral_sheet", Vector2f.new(w, h), true) then
        imgui.spacing()
        imgui.indent(SHEET_PAD)
        with_font(fonts.body, function()
            if #list == 0 then
                imgui.text_colored(EMPTY_TEXT, C.ink_faint)
            else
                for i, e in ipairs(list) do pcall(draw_entry, e, i) end
            end
        end)
        imgui.unindent(SHEET_PAD)
    end
    imgui.end_child_window()
    imgui.pop_style_color(n)
end

local first = true
re.on_frame(function()
    if not state.shown or not reframework:is_drawing_ui() then return end
    if first then
        imgui.set_next_window_size(Vector2f.new(WIN_W, WIN_H), 4)   -- 4 = ImGuiCond_FirstUseEver
        first = false
    end
    local n = push_colors({ { COL.WindowBg, C.wall }, { COL.TitleBg, C.wall }, { COL.TitleBgActive, C.wall },
        { COL.Border, C.gold }, { COL.Text, C.title } })
    local nv = 0
    for _, v in ipairs({ { VAR.WindowRounding, ROUND_CARD }, { VAR.ChildRounding, ROUND_CARD },
        { VAR.ChildBorderSize, BORDER }, { VAR.FrameRounding, ROUND_CARD * 0.5 }, { VAR.FrameBorderSize, 1.0 } }) do
        if pcall(imgui.push_style_var, v[1], v[2]) then nv = nv + 1 end
    end
    local still = imgui.begin_window("Visceral options", true, 0)
    if still == false then
        state.shown = false
        save()
    end
    with_font(fonts.title, function() centred(TITLE, C.title) end)
    with_font(fonts.motto, function() centred(MOTTO, C.title) end)
    imgui.spacing()
    draw_cards()
    imgui.spacing()
    draw_sheet()
    imgui.end_window()
    if nv > 0 then imgui.pop_style_var(nv) end
    imgui.pop_style_color(n)
end)

-- in the old long menu: bring the window back after it was closed
re.on_draw_ui(function()
    if imgui.tree_node("Visceral options (the Emporium)") then
        local c, v = imgui.checkbox("Show the Visceral options window while this menu is open", state.shown)
        if c then state.shown = v; save() end
        imgui.tree_pop()
    end
end)
