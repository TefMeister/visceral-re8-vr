-- q_re3_allguns.lua (TESTING ONLY, rv.py -f with RV_GAME_DIR = RE3): tries the gun types of offline.EquipmentDefine.WeaponType
-- and says which the game took. 2026-11-23.
local im = sdk.get_managed_singleton('offline.gamemastering.InventoryManager')
local out = {}
for _, w in ipairs({21, 31, 42}) do   -- 2026-11-23: the wider list (2, 4, 3, 22, 32, 49, 50, 12, 23, 43, 44, 45) took none and FROZE the game
    if im:call('hasWeapon', w) then out[#out+1] = w .. ':owned'
    else
        pcall(function() return im:call('addAndEquipMainWeapon', w, 1, 0) end)
        out[#out+1] = w .. (im:call('hasWeapon', w) and ':added' or ':no')
    end
end
local inv = im:get_field('<CurrentInventory>k__BackingField'); local slots = inv:get_field('_Slots'); local used, names = 0, {}
for i = 0, slots:call('get_Count') - 1 do
    local s = slots:call('get_Item', i); local wt = s:call('get_WeaponType')
    if wt ~= -1 or s:call('get_ItemID') ~= 0 then used = used + 1 end
    if wt > 0 then names[#names+1] = 'w' .. wt end
end
return table.concat(out, ' ') .. ' | used ' .. used .. ' of ' .. slots:call('get_Count') .. ' | guns ' .. table.concat(names, ' ')
