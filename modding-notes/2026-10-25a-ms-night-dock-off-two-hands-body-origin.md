# 2026-10-24 20:35 to 2026-10-25 03:00, /ms, home PC, Tefa in the headset (Opus, then Fable from 00:35)

Nineteen builds in one night. Tefa worn every one; `[verified-live]` below means Tefa saw it, n = the number of wears.

## What now works, in order of weight

1. **The pad works again.** `re8_vr.lua` had set a NEW field on praydog's C++ `re8vr` object; sol throws "cannot set
   (new_index)" and the whole pad update died silently, because REFramework does not write Lua hook errors to the log unless
   `ScriptRunner_LogToDisk=true` in `re2_fw_config.txt` (now on; backup `/d/RE Village REFramework builds/
   re2_fw_config.before-lua-log-2026-10-24.txt`). State moved to `_G`. `[verified-live 2026-10-24, n=1]`
2. **Thumb rest + right stick = the quick slots**, the bindings file (`_interaction_profiles_oculus_touch_controller.json`)
   works, the right stick no longer turns the camera while the thumb rests. "it all works!" `[verified-live 2026-10-24, n=1]`
3. **The game's own left-hand dock is off while LG is up** (`nodock.cpp`): praydog docks within 10 cm of the animation's
   left wrist, button or not, and turns the gun toward the hand; four downstream fixes (the grip script's undo, smooth.cpp's
   put-back, first solve then every solve) each acted a solve late and the hand still flicked (live log watch 01:06: the dock
   switched on and off four times in four seconds). praydog finds that wrist by `via.motion.Motion.getJointIndexByNameHash`
   with the left hand IK's `<HashJoint2>`; a hook answers 0 (the root joint) for that hash while LG is up. The first version
   also compared the `this` to the player's motion and never matched; dropped. Tens of thousands of asks answered, the game
   docked only with LG held. "no jumps now, grip takes hold fine" `[verified-live 2026-10-25, n=2]`
4. **One hold per gun and part on the slide / pump / bolt** (`hand_holds.json`, keys `<gun>:<part>:v2`): the pump keeps
   the animation's two-handed hold (position and turn), the slide / bolt the hand's turn as it first came; the palm offset is
   measured against the hand joint's own rotation and kept once (it varied per take against the target's). The pump lands
   the same every time `[verified-live 2026-10-25, n=3]`; the slide lands in one spot but with the back of the hand against
   the slide's right side (the first take set it; "Drop this gun's slide / pump / bolt hold" in the menu retakes it, the turn
   sliders adjust it) `[reported 2026-10-25]`.
5. **Two hands on the pump gun**: the grip script steers the gun at the rack's socket (bridge slots 99 = on, 100-102 =
   the socket in the right hand's frame) while the hand is on the pump; on a pump gun it keeps off otherwise.
   `[verified-live 2026-10-25, n=1]` ("shotgun is fine now!")
6. **The quick-slot cross** sits in the middle of the view, slots 300 / 170 from the centre; the onShow / onHide calls and
   the hide refusal are gone (they left the game's open / close state wrong: "after that, d-pad menu doesn't show at all");
   the per-frame slot scale is gone (it fought the game's slot animation: "small like squares"). The door for "shown while
   the thumb rests" is `app.GUIQuickEquip.openQuickEquip(app.GUIRequest.Parameter)` on the cross itself, with
   `get_/set_closeTimer(System.Single)` for keeping it open `[measured 2026-10-25, the method listing]`; not wired yet. The
   label text has no `set_FontSize`: sizes stay the game's until another way is found. `[reported 2026-10-25]`: the labels
   are different sizes and too small.
7. **The open hand near a grab spot** (`fingers.cpp`): ramps with the distance to the gun, stands down while Hand Poser
   holds any finger (`_G.hand_poser_held`, bridge slot 29). Village's `BaseLocalRotation` is a relaxed CURL, so the first
   version closed the hand near the pump and, since nothing re-poses finger joints, left it so ("gets stuck"); it now opens
   toward the identity local rotation and writes back the pose it found when the episode ends. `[verified-live 2026-10-25,
   n=1]` ("fingers a bit more pointy ... didn't get stuck this time")
8. **The standing origin** (`visceral_re8_origin.lua`): REFramework takes the headset's launch position as the origin;
   "Recenter View" lifts the picture but the body and hands are placed against the origin, so the guns sit wrong after it.
   `vrmod:set_standing_origin(vrmod:get_position(0))` then `recenter_view()` (what REFramework's own button does) once the
   player is in gameplay with the controllers in use and the headset moving, plus a menu button. First run fired on the
   title's player object with the headset on the desk; the worn-headset test was added. `[compile-verified 2026-10-25]`, unworn.
9. **The hands-on magazine** (`reload.cpp` `grab_frame` / `pull_out`): with the magazine seated, LG pressed with the left
   controller within 14 cm of it puts the hand on it; LT pulls it out into the hand (the pouch's IN_HAND state, with the
   eject's bookkeeping); B ejects only on pistols (and on a gun whose magazine joint is unknown). Unworn.
10. **Hand Poser** finds Village's fingers (`L_IndexF1` ... `L_Thumb3`, `L_Hand`); its script announces how many joints it
    holds. The posing session itself did not happen: the hands were not settled enough.

## The body turn (idea 6): the lever found, the result not yet

- Turning the ROOT joint alone is never drawn, however many times it is written (LateUpdateBehavior post, PrepareRendering
  post, BeginRendering pre: every check "held", the chest still followed the head) `[verified-live 2026-10-25, n=5]`.
- Turning EVERY joint (read all first, then write; the 2026-10-24 strips came from reading a child after its parent was
  turned) IS drawn: "i can actually walk and look around without the body dangling the same way" `[verified-live 2026-10-25,
  n=1]`; but turned about the player transform's position, which is not under Ethan, the body swung into the view, and the
  arm chains (left out so the hands stay on the controllers) hang off turned shoulders: "a mess". Now about the root joint's
  own position, behind "Body turns like RE2 (EXPERIMENTAL)" in the Visceral RE8 reload menu, off by default; a once-a-second
  line logs the root's yaw before / after, the transform's, the body's and the look's for the sign check ("rotated back"
  past 20 degrees may be the turn going the wrong way). Tefa: "maybe we'll focus on it another time".
- Tefa's rule for it: the body comes round once the head is more than 60 deg off standing, 45 walking, 30 running, then turns
  slowly to face the look; in the inventory nothing is written (the inventory read from hooks on `app.GUIInventory.openInventory`
  / `closeInventory`; `app.MenuManager` has no `isOpenInventoryMenu` or `open/closeInventoryMenu` in Village).

## Still wrong (Tefa's words), for the next sessions

- Pistol: the two-handed grip can start with the magazine out; wanted: only after a new magazine (and a rack when the gun
  ran dry). The slide locks back on a mid-magazine eject; wanted: only after the last round, one round staying chambered.
  Shotgun shells: too small for the M1897, right for the W870 TAC. All filed in mod-ideas 2026-10-25.
- The quick-slot cross: not shown on the thumb rest alone; labels small and uneven; boxes to sit closer (done, unseen).
- Boot route: the game sat on "Checking for additional content. Please do not close the game or turn off the power." for
  eight minutes at 02:43 (REFramework overlay open) and never reached the title; `re8drive.py boot` has no template for it.
  Closed with WM_CLOSE.

## Notes

- Hand holds, grip spots and the kept palm offset live in `reframework/data/visceral_re8/` (`hand_holds.json`,
  `grip_spots.json`); the bridge array is 104 floats now (slots 29, 99-103 new).
- Ghost Hand (BeG0nE) at 23:14: the left hand jumped 117 times while the controller was calm, before the dock was switched off.

## 03:00 to 03:55: the magazine comes out by hand, a crash, and the "off" hands measured

- **The hands-on magazine WORKS** `[verified-live 2026-10-25, n=1]`: Tefa: "the mag eject actually kinda works!! unbelievable
  ... it does come out and stay in my hand, i can throw it on the floor and get a new one from the pouch". The first version
  needed LT hammered with the hand yanked away: the pulled magazine appeared at the well and the insert check seated it again
  the same instant (log: "insert at 0.001 m" after every pull-out). Now it must get 12 cm clear of the well first
  (`INSERT_CLEAR_M`); the grab zone is 12 cm, measured from the drawn hand (the controller sits ~15 cm behind it, so the
  first version never reached); the grab wins over the rack and the grip while the hand is near the magazine.
- **A crash at 03:12:09** (access violation in re8.exe with a garbage object, 0.6 s after a headset tracking blip,
  `reframework_crash.dmp`). `[hypothesis]`: the game rebuilt its hand IK through `getJointIndexByNameHash` and got the root
  joint from nodock. Since then nodock answers only asks whose return address lies in REFramework's module (DINPUT8.dll).
  No crash in the three runs after `[reported 2026-10-25, n=3]`.
- **The game's own dock is off whenever a gun is in hand** (not only with LG up): with LG held it was handed back and fought
  every hand of ours (160 docks in one run: "docked on the rifle grip like holding a pistol", the pistol "hops on the grip
  when racking is needed"). The grip script lets it through (bridge slot 105) only to learn a pistol's first grip spot. Also:
  no two-handed grip while the magazine is out or a rack is due; on a long gun no grip closer than 25 cm to the right hand.
- **The height fix works** (Tefa) once the origin is also set on the first active frame and on any 25 cm headset jump.
- **The "off" hands, measured**: Tefa: "sometimes it does, other times it doesn't ... more when i sit and play in darker
  conditions ... one launch the guns are fine, next launch they are off ... tonight it was right just one time". The log of
  the "off" run: 29 `XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED` events in 20 minutes, each right after `pad: skipped:
  using controllers false` (the controllers dropped out of tracking and came back) `[measured 2026-10-25]`. That count is
  the measure. Our put-back's learned offset could be poisoned by such a moment; it now uses praydog's own
  `left_hand_position_offset` / `left_hand_rotation_offset` through the bridge (slots 106-112) every frame, so any "off"
  hand from here is the tracking, not ours. The log is overwritten at every launch, so the "right" run could not be compared:
  keep each launch's log (lanes 0.85.0's rule).
- Filed in mod-ideas, Tefa's words: LG holds the gun whatever the controllers' distance; rubber arms that stretch to keep
  the hand on the gun; the free hand pivoting at the wrist (praydog's 15 cm lever).

## 04:00, the last wear (build 5783045), Tefa's words

> the mag is still in the activation area and jumps back in after i take it out. hand still gripped on the rifle grip handle
> alongside right hand and it was very hard to get it to dock on the mag. the bolt activation area is too large.

So the 12 cm clear rule, the 25 cm long-gun rule and the 12 cm grab zone did not do what they were meant to, and the bolt's
grab zone (the whole gun line, 16 cm) is too wide `[reported 2026-10-25, n=1]`. Unread logs; the board carries the four checks.
