# Archived probes

- `visceral_re8_hud_probe.lua` (2026-10-24): logged the quick-slot cross's panel tree once; its answer is in `visceral_re8_hud.lua` (c_layout, c_top / c_right / c_bottom / c_left at 115, m_key_T/R/B/L). Not installed.
- `visceral_re8_sphere_probe.lua` (2026-10-30): made one balloon (sm59_162) at the title screen to read its material's variables for the grip spheres' fade. Answer: at the title screen the balloon's material never came in (`get_MaterialNum` 0 for 60 frames, the mesh in), and a SECOND `set_Material` on it crashed the game (dump and log kept in `D:/RE Village REFramework builds/logs/*2026-10-30-2020*`). The fade in `visceral_re8_zones.lua` now looks for its variable once the material is in, during play, and logs every variable. Not installed.
