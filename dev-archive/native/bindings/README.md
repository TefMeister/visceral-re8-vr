# REFramework controller bindings for Visceral RE8

`_interaction_profiles_oculus_touch_controller.json` goes in the game folder (next to `re8.exe`); REFramework reads it at
start instead of its built-in bindings for Quest / Oculus Touch controllers (`OpenXR::initialize_actions`, REFramework
source `src/mods/vr/runtimes/OpenXR.cpp`). It lists every built-in binding (`OpenXR.hpp` `s_bindings_map`, the `*` hand
written out as left and right) plus one:

- `minimap` = `/user/hand/left/input/thumbrest/touch`: the left thumb rest. Nothing used `minimap` on Touch controllers
  (no built-in binding), so our scripts read it as "the thumb rest is touched": thumb rest + right stick = the D-pad
  (Tefa, 2026-10-24: "change d-pad to left thumb rest + right stick up, down, left, right").

Undo: delete the file from the game folder; REFramework goes back to its built-in bindings.
