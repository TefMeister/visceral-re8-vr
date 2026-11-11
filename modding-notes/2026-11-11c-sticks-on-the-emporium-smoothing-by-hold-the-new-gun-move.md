# b115: the sticks drive the Emporium, smoothing by how the gun is held, the game's new-gun move, the ammo counter kept right (2026-11-11 evening)

Developer PC, Claude on Fable, OpenXR Simulator + VR Bench, nobody in the headset, Tefa away. Installed; builds store
`v0.1.0-b113` (the project's b115). **Nothing here is worn.**

## 1. The sticks drive the Visceral Emporium

Tefa (2026-11-08, 11-09): *"RS to change settings and sliders in VR options, LS to change the category from comfort to
graphics and so on, so no need to keep exiting to "main menu" of the VR options"*; *"use the RS - up/down to choose
settings - left/right to change them both sliders and on/off ones"*.

Built in `visceral_re8_emporium_shop.lua` (`watch_sticks`) and `re8_vr.lua`'s pad update:

- right stick up / down: the game's own selection moves (one D-pad tap a step, with a repeat while held); on the front
  cards, which lie side by side, up = the card before, down = the next;
- right stick left / right: the lit setting steps down / up (a tick box flips) on the Supplies grid, the Gunsmithy's rows
  and the Duke's Purse; on the front cards it moves between the cards; in the Gunsmithy's gun column right = into the rows;
- left stick left / right inside a screen: the next / previous group, by itself (the game's own Back, the card row walked
  to the wanted card, the game's own OK), wrapping round;
- while the Emporium is open the right stick does not turn the view and, inside a screen, the left stick's sideways half
  does not reach the game.

Seen on the simulator, driven from the desk (`emporium_cmd.json`: `stick r up|down|left|right`, `stick l left|right`,
`where`) `[verified-live 2026-11-11, simulator, n=1 pass]`: the card row 0 -> 1 -> 2 -> 1 -> 0; Supplies: down moved the lit
tile, right / left flipped "Gun shaking the controller" off and on; hop Comfort -> Graphics (Gunsmithy) -> Settings
(Purse) -> Comfort and back the other way; Purse: down then right / left flipped "Hip holster". NOT seen: a real
controller's stick (the desk command enters after the stick reading), the repeat while held, the Gunsmithy's rows being
stepped (only its gun column was reached), the Kitchen card.

Found on the way `[verified-live 2026-11-11, n=2]`:
- The card row answers the left STICK only. One-frame D-pad taps (LLeft / LRight, with or without the Emu bits) do
  nothing on it, though the same kind of tap moves the selection inside the three screens. A card move is the stick's
  sideways half held 5 frames.
- The cards live in two lists, `l_list` (three cards) and `l_list_add` (four, with the Kitchen). The one not in use keeps a
  cursor showing on its first card, so `lit_card()` read card 0 whatever was lit. It now takes the list the screen's own
  selection agrees with (`get_SelectedIndex`, which is right on the four-card list). New question file
  `tools/sim/q_shopcards.lua`.
- Inside a screen Back is the GAME's: the hop taps the game's Cancel, then the game's OK on the card, so the card opens its
  real screen (the script's own `pick()` opens the older own-pages instead).
- A screen that is fading out keeps its driver for a while: the lit setting is taken from the screen that belongs to the
  picked card.
- The Gunsmithy opens in its gun column (`lastIndex` moves, `cursorIndex` stays); the rows are lit after A
  (`lateUpdateSetTune` runs from then on).

## 2. Hand smoothing by how the gun is held

Tefa (2026-11-09): *"smoothing on with one hand and turned down when both hands are on the pistol ... when both hands are
holding it, to be able to adjust left and right hand smoothing separately"*.

`visceral_re8_hand_smooth.lua`: per gun three more strengths, `cfg.hold[<gun>] = { one, two_r, two_l }` (0-10): the gun hand
with the left hand off the gun; the right and the left hand with the left hand on it. "On the gun" = praydog's two-hand
grip, or the plugin's hand state 1-3 (grip, slide / bolt, pump; the bridge now publishes it as
`__visceral_left_hand_state`). A missing one = the gun's strength as before. It switches by itself, with a log line each
time. Three rows in the Emporium's Comfort group and in the REFramework menu.
`[compile-verified: loads and runs, 2026-11-11]`; the switch itself was not exercised (no two-hand grip was made on the
simulator this evening).

## 3. The game's own new-gun move

`visceral_re8_newgun.lua` (new): arms motion 2007 on the player's layers 1, 2, 9, 10 and the gun's own GetWeapon motion on
its layer 0, by `TreeLayer.changeMotion(UInt32, UInt32, Single, Single, InterpolationMode, InterpolationCurve)` =
`(0, id, 0, 6, 2, 0)`. While it plays the arm IK is skipped (the `__re8_arm_ik_update_override` chain answers "handled")
and the plugin is told "cutscene" (the bridge adds `__visceral_newgun_playing` to its cutscene slot), which every hand
job of the plugin already stands down for. It ends when the layer leaves 2007, reaches its end, or after 8 s.

Seen `[verified-live 2026-11-11, simulator, n=3, W870]`: started on the gun's first time in the hand, the arm layer ran
frame 0 to 130, over after 2.13 s, the hands back. ⚠️ One simulator picture mid-move shows the sleeves filling the lower
half of the view, very close to the eyes, no gun in sight `[n=1 picture]`: whether the move reads well in VR is not
known. So the automatic first-time play is OFF by default; the Emporium's Comfort group has the switch and "Play the
new-gun move again". The first-time list is ours (`visceral_re8/newgun.json`); the game's own flag was not looked for.

## 4. The ammo counter kept right

Tefa (2026-11-09): *"ammo counters showed zero just now, a shot made them go correct"*. The refresh our reloads already ask
for (`applyToUI`, `showRemainAmmo`, `updateRemainAmmo` through the counter's order) now also runs 0.6 s after every gun
change and every 2 s while a gun is out in play (`visceral_re8_bridge.lua`). The log confirms it runs. Which event left the
counter at zero was not caught, so this is `[hypothesis]` until a wear. ⚠️ The simulator pictures show the W870's counter at
"0 / 47" with the refresh running: either the gun is empty on this save or the refresh does not cure it; not settled.

## Not done

"Tuning on the monitor" (the design session with Tefa): not started; it needs Tefa.
