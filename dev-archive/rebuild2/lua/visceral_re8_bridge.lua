-- visceral_re8_bridge.lua -- rebuild 2 (2026-11-26, design item 3): what the plugin cannot read itself, and
-- nothing else. The slots and how the plugin finds the array: native/src/bridge.h (keep the two in step).
--
-- One managed float array, made once per script start and held (add_ref) for the plugin to read. Its address and
-- a random sentinel go to reframework/data/visceral_re8/bridge.txt; the plugin checks both before it reads.
-- Written at UpdateHID (before the plugin's UpdateBehavior step reads it). No hook, no joint, no object besides
-- the array, no request (rule set, design 2026-11-25d section 5).

local TAG = "[visceral-re8-bridge]"
local FILE = "visceral_re8/bridge.txt"
local ARRAY_DATA_AT = 0x20          -- a managed array's first element
local S_FRAME, S_SENTINEL, S_ACTIVE, S_CUTSCENE, S_CAN_USE_HANDS, S_GAME_ARMS, S_WEAPON = 0, 1, 2, 3, 4, 5, 6
local S_COUNT = 16

if reframework:get_game_name() ~= "re8" then return end

local arr = sdk.create_managed_array("System.Single", S_COUNT)
if not arr then
    log.info(TAG .. " could not make the array; the plugin's parts stand down")
    return
end
arr:add_ref()

local function w(slot, v) arr:write_float(ARRAY_DATA_AT + slot * 4, v or 0.0) end
local function wb(slot, b) w(slot, b and 1.0 or 0.0) end

math.randomseed(os.time())
local sentinel = math.random(100000, 9999999)   -- a whole number a float holds exactly
for i = 0, S_COUNT - 1 do w(i, 0.0) end
w(S_SENTINEL, sentinel)
json.dump_file(FILE, { a_address = string.format("%d", arr:get_address()), b_sentinel = sentinel })

local frame = 0
re.on_pre_application_entry("UpdateHID", function()
    frame = (frame + 1) % 1000000
    w(S_FRAME, frame)
    local active = false
    pcall(function() active = vrmod:is_hmd_active() and vrmod:is_using_controllers() end)
    wb(S_ACTIVE, active)
    wb(S_CUTSCENE, re8vr.is_in_cutscene == true)
    wb(S_CAN_USE_HANDS, re8vr.can_use_hands == true)
    wb(S_GAME_ARMS, rawget(_G, "__visceral_re8_game_arms") == true)
    wb(S_WEAPON, re8vr.weapon ~= nil)
end)

log.info(TAG .. " loaded: the array is ready")
