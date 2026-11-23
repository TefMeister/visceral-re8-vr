-- q_re2_allguns.lua (TESTING ONLY, through rv.py -f with RV_GAME_DIR = RE2): every gun the 20-slot inventory can take.
-- WeaponType numbers from app.ropeway.EquipmentDefine.WeaponType (WP0000 = 1 ...); bullet item ids from KNOWN.md.
local im = sdk.get_managed_singleton('app.ropeway.gamemastering.InventoryManager')
local W = { {1,'Matilda',15}, {10,'SLS 60',15}, {3,'JMB Hp3',15}, {2,'M19',15}, {11,'W-870',16}, {42,'GM 79',22}, {21,'MQ 11',17},
            {23,'LE 5',17}, {43,'Chemical Flamethrower',25}, {44,'Spark Shot',0}, {4,'Quickdraw Army',15}, {8,'MUP',15},
            {9,'Broom Hc',15}, {45,'ATM-4',0}, {49,'Anti-tank Rocket',0}, {31,'Lightning Hawk',18}, {50,'Minigun',0} }
local out = {}
for _, w in ipairs(W) do
    local has = im:call('hasWeapon', w[1])
    if has then out[#out+1] = w[2] .. ': owned'
    else
        local ok, r = pcall(function() return im:call('addAndEquipMainWeapon', w[1], 1, 0) end)
        out[#out+1] = w[2] .. ': ' .. ((ok and im:call('hasWeapon', w[1])) and 'added' or 'NOT added')
    end
end
local inv = im:get_field('<CurrentInventory>k__BackingField'); local slots = inv:get_field('_Slots'); local used = 0
for i = 0, slots:call('get_Count') - 1 do
    local s = slots:call('get_Item', i); local wt = s:call('get_WeaponType'); local id = s:call('get_ItemID')
    if wt ~= -1 or id ~= 0 then used = used + 1 end
    for _, w in ipairs(W) do if wt == w[1] and w[3] ~= 0 then pcall(function() s:call('set_BulletID', w[3]) end) end end
end
return table.concat(out, ', ') .. ' | slots used ' .. used .. ' of ' .. slots:call('get_Count')
