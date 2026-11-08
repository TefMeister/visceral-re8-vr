# 2026-11-08: the Hands ideas, built (home PC, Opus, no game running)

Tefa, going through Village's ideas list: *"build it now, please, and actually the rest on the Hands list you can do with
Opus, except 26, 30, 32 as we are already fine tuning this idea, 36 needs to change ... 38 we are already doing"*.
Built and installed as **b084**, then **b085** (the rubber arm's log line fixed) (builds repo `visceral-re8-vr/hands/`). Tried on the
OpenXR Simulator with VR Bench the same evening (Tefa: *"pleaase shut the pc down after finishing and testing as much as you can"*);
results in "Simulator run" at the end.

## Idea 6: hand poses that change at set points on the gun

Tefa: *"i would like to have a point on the guns when something happens, then the hand pose changes. for exapmle, the
rifle bolt, when pulled back with left hand then after the click that means it's at the very back, then the hand changes
pose automatically, different with the right hand. the same with a handgun, holding LG to grip the mag, so it looks like
holding the grip in game, then pressing B makes the hand actually move under the mag, pressing it in with LT changes the
hand to go back on the grip."*

The plugin already tells Hand Poser and Dock Poser where each hand is (bridge slot 153 left, 184 right, `pairs.cpp`), and
both keep one pose per gun and spot. Each point is a new spot number:

| spot | when | Hand Poser name | Dock Poser |
| --- | --- | --- | --- |
| 11 | the slide / pump / bolt, from its click at the very back until it is home (`rack::at_back()` = `g_pulled`) | slide at the back | falls back to spot 3 until tuned |
| 12 | the same for a pistol slide taken from the left | slide from the left at the back | falls back to 8 |
| 13 | a magazine carried in the left hand (after B / LT took it out, or from the pouch), until LT starts it in | magazine in hand | its own (nothing = the controller's hand, as before) |
| right 4 (dock 104) | the right hand on the bolt from the click at the back until home | right hand on the bolt at the back | falls back to 102 |

The pistol flow Tefa described is then: LG on the seated magazine = spot 4 (pose it to look like the grip); B = spot 13
(the hand with the magazine, pose it under the magazine); LT pushing it home = spot 4 again (the grip look).
A spot with no pose saved: Hand Poser keeps the pose in hand (so the bolt hand does not change until Tefa poses "at the
back"); EXCEPT "magazine in hand", which lets the left hand go (the game's open / close, as before the spot existed) until
it has a pose of its own. Dock Poser's window starts an empty "at the back" spot from the spot it came from.
To pose them: hold the hand there (the bolt pulled back with LT still held, the magazine in hand) with Hand Freeze, and
pose in Hand Poser as with any other spot.

## Idea 10: the trigger finger follows RT

In `hand_poser.lua`: the bridge reports RT only as pressed / not pressed (slot 5; no trigger travel), so on every press the
right index finger eases (0.06 s) from where it is (our held pose or the game's own grip, read once as the press begins) to
the gun's "trigger pulled" pose, and back on release. To make that pose: with a gun out (empty is best), hold RT for a
second; the right hand's spot becomes "trigger pulled", and Hand Poser keeps a pose for it: bend the right index finger
there. A gun with no such pose: nothing changes. Only the R_Index joints of that pose are used.

## Idea 15: LG holds at any distance, rubber arms, the free hand turns at the wrist

Two of its three parts were already done: the grip stays while LG is held whatever the distance
(`re8_vrz_begone_grip.lua`, 2026-10-25 15:50), and the free hand swinging about a point 15 cm ahead was the start-up
offset fault fixed on 2026-10-30 (`re8_vr.lua`, the OpenXR offsets now go in once OpenXR is up). New: `armstretch.cpp`.
While the left hand is held on the gun (a docked spot or the two-handed grip), after the arm solves: when the hand's target
is further from L_UpperArm than the arm is long (the sum of the elbow-to-hand joints' own lengths), every joint from
L_Hand up to (not including) L_UpperArm is moved out along its bone by the same factor, up to 1.8, eased in and out
(settings.h `ARM_STRETCH_*`). It assumes the game's solve straightens the arm toward the target when it is out of reach
`[hypothesis]`; if it only bends a little short, the hand lands near, not on, the target.

## Idea 37: the hand takes the game's own grip near the middle of a zone

`make_finger_book.py` now also writes `clips/<gun>_grip.csv` (the left hand's settled hold in the game's idle, from the
draw_idle takes) and `clips/<gun>_grip_mag.csv` (the fullest left-hand grasp in mag_out). Only six guns' idles hold the gun
with the left hand (mean left-finger turn 40-64 deg: ri3021, ri3036, ri3042, ri3046, ri3047, ri3049); the other eleven let it
hang (30-32 deg), so they have no grip pose and keep the opening hand. Nine guns have a magazine grasp. Game data: in the
game's clip folder only, never on GitHub (the builds repo's PROJECT.conf now keeps `clips/` local, see below).
`fingers.cpp`: the free left hand (no LG, nothing in it, no poser holding it) near a shown grab zone (magazine, slide /
pump / bolt, front grip, grip handle) eases into that zone's game hold: none at 1.6 zone radii from the middle, all of it at
0.35, rate-limited to 0.15 s for a full change. Tunable per gun in `reframework/data/visceral_re8/grip_blend.json`:
`{"default": {"start": 1.6, "full": 0.35, "amount": 1}, "ri3046": {"amount": 0.6}}` (read once a second). Not yet tunable:
the end pose itself (it is the game's; the Animation & Timing window edits clips that are played, not this one).

## Idea 36 (changed): items from the world

Tefa: *"Epty hand grip button takes the item from game world, it travels to player hand as sson as in the close enough area,
then while holding the grip button, press trigger to store, no taking items out at all."* NOT built: which object is an item
lying in the world and which call picks it up are not known. Names in re8.exe's text: `InteractItemGet`, `ItemGetInteract`,
`RequestItemGetInteract`, `onPickUp`, `notifyPickUpItem`, `ItemGetSpawnController`. `tools/sim/zz_probe_items.lua` (read
only) lists which of those types exist, their methods and fields, and the nearest objects carrying them; one flat run near a
few items (copy it into autorun, look at the "[item-probe]" lines, take it out) gives what the build needs.

## Found on the way

- The builds repo had 362 finger-clip CSVs (the game's own animation data) pushed in earlier Village builds; `shellclip.h`
  says they never go to GitHub. From b084 on `PROJECT.conf` has `local_only = reframework/data/visceral_re8/clips`. The old
  copies are still in the repo's history (private repo): FAULTS.md row.

## Simulator run (2026-11-08 17:13-17:27, OpenXR Simulator + VR Bench, no headset)

Log kept: `D:/claude video game stuff/logs/village/re2_framework_log-2026-11-08-1725-hands-ideas-sim.txt`.
`[verified-live 2026-11-08, simulator, n=1 each]`:
- Idea 6: the M1897's pump pulled back by hand: the left spot went 3 -> 11 at the back -> 3 once home (zones_state.json read
  4 times a second). The LEMI: LG on the seated magazine = 4, right B = 13 and Hand Poser's spot read "magazine in hand".
  NOT seen: LT pushing it home back to 4 (my drive's LT did not start the insert; the magazine dropped when LG let go).
- Idea 10: RT held 1 s with the M1897 out: Hand Poser's state.json spot "trigger pulled"; let go: "" again. The finger
  blend itself not seen (no "trigger pulled" pose saved yet, and no joint reader running).
- Idea 37: hand free (LG let go) inside the M1897's pump zone: "ri3036_grip: the game's own left-hand hold read (15
  joints)", then "easing into the game's own hold (near the zone's middle)". The look not judged.
- Idea 15: "the left arm's 2 joints from the elbow to the hand found" (L_Hand's parent is L_Forearm, its parent
  L_UpperArm). Docked on the pump: shoulder to target 0.868 m, the hand 0.549 m, the arm 0.549 m -> x1.58. One picture:
  the left sleeve reaches along the gun; the forearm itself hidden by the sleeve. The first version's one-time line never
  printed (it waited for a stretch under x1.01, which the first ease step passes): fixed in b085. NOTE: in the simulator's
  fixed hand places the pump sits 0.87 m from the shoulder, so the arm stretches there all the time; in the headset it
  only should when the hands are wider than Ethan's arms.
- Idea 36, the probe: items lying in the world carry `app.InteractItemGet` (261 in the opening area, nearest 11.6 m);
  4 `app.InteractItemGetCustomParts`; no `app.ItemGetInteract`, `app.InteractObject`, `app.DropItem`, `app.ItemPickup`.
  `InteractItemGet` (57 methods, 27 fields) has `AddInventory/1`, `InsertInventory/1`, `InsertInventoryInternal/0`,
  `InventoryInsertFinishItem/1`, `RequestItemCore/1`, `SetForceInteract/1`, `SetInteractEnable/1`, and the fields
  `ItemCore`, `ItemSetGameObject`, `ItemGetRequest`, `RequestItemGetInteract`, `Interact`, `IsHighLightNow`.
  `app.ItemCore` has `onPickUpReserve/0`, `onSucceededGet/0`, `callGetSE/0`. Next: near an item, find which call stores it
  the game's way (InsertInventory's one argument first), then build the grab (LG pulls `ItemSetGameObject` to the hand,
  LT with LG held stores it). The probe is archived at `D:/claude video game stuff/archive/village-probes/`.
