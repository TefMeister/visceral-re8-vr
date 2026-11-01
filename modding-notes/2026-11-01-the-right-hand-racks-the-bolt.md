# The right hand racks the rifle's bolt (2026-11-01, Opus)

Tefa's idea, the same morning: with the rifle held by LG on the front and LT held, RG sends the RIGHT hand onto the bolt
to rack it; the left hand can still rack too.

## How it works
The gun hangs off the right hand in the game, so while the right hand is on the bolt the gun is carried by the left
controller: its transform is written every frame (late update, before rendering, after the arm solves) and its own local
pose is put back afterwards. Poses are kept in the left controller's frame from the moment of the take.

## Three passes, one day
- **b025** (RG takes it, LT held): works `[verified-live 2026-11-01, n=1]`. Tefa: "really cool! it works. it is still a
  little janky, throws the gun a little and left hand doesn't stay on like solidly holding on to the gun".
- **b026** (LT on the front LOCKS the rifle; a 0.4 s slow trail instead of a freeze; both drawn hands sit on the gun; RG
  racks any time): Tefa: "this is epic. really is" `[verified-live 2026-11-01, n=1]`.
- **b027** (Tefa's rules, unworn): LG + LT on the front only make RG ready; RG pressed and held holds the rifle and takes
  the bolt; LT let go mid-rack: the cycle finishes first; LG let go mid-rack: the rifle back on the right hand in 0.12 s,
  the bolt left where it was, to be finished later. RG let go: the hand back to the grip, then a 0.3 s handover easing
  the gun and the right hand together `[compile-verified 2026-11-01]`.

## Worth knowing
- A rack with no shot is cosmetic: no round lost, no case thrown.
- Settings: `RIGHT_RACK_*` and `RIGHT_BOLT_HAND_*` in settings.h. The right hand's place on the bolt is untuned.
- Silent Hill 2 got a port the same morning (`rhbolt.cpp` there), built on the b026 design (LT locks), not b027's rules.
