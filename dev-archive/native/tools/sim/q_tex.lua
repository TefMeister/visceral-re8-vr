local m = E.book_meshc
local o = {}
local n = m:call("getMaterialTextureNum", 0)
for i = 0, n - 1 do o[#o + 1] = i .. ":" .. m:call("getMaterialTextureName", 0, i) end
local path = E.tex_path or "objectroot/setmodel/textures/sm60_035_pocketbook01a_b_albm.tex"
local r = sdk.create_resource("via.render.TextureResource", path)
o[#o + 1] = "new texture resource " .. tostring(r ~= nil)
if r ~= nil then
  r = r:add_ref()
  local h = r:create_holder("via.render.TextureResourceHolder"):add_ref()
  local ok, e = pcall(function() m:call("setMaterialTexture", 0, E.tex_slot or 0, h) end)
  o[#o + 1] = "setMaterialTexture " .. tostring(ok) .. " " .. tostring(e or "")
end
return table.concat(o, "  ")
