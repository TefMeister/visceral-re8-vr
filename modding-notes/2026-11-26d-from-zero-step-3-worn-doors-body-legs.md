# 2026-11-26d: from zero, step 3 worn: doors, the body at a stop, the legs (/ms, Fable, Build PC)

Tefa in the headset, 15:40 to 19:2x, eight builds (b181 to b188, builds store `rebuild 2/`). Board rows RE8-087,
RE8-091 to RE8-095. Everything is in `dev-archive/rebuild2/`. Kept logs (Build PC, not in the repo):
`~/visceral-kept-logs/re8-2026-11-26-1636...` to `...-1900-b187-bolted-door-steps-off.txt`. Tefa's clips:
"glitches re8", "hands not opening doors re8", "re8 glitchy hands and legs" (Capcut export folder on D:).

## 1. Doors: what is established

- **b181, the prologue house** `[verified-live 2026-11-26, Tefa, n=1 run]`: the bedroom door opened by walking in
  with Rose; nothing from afar; three shut doors opened at the hand and were pushed to 90 degrees. Tefa: *"2 yes 3
  yes 4 nothing happened 5 works perfectly"*. The Rose check and the scene list in the frame (b180) worked in that run
  (the log: carrying Rose, the body's 2 meshes, the crib scene).
- **Ordinary village doors by hand** (b182 on) `[verified-live, Tefa, n=4 runs]`: *"6 works well"*.
- **Sounds** `[measured from the log + Tefa's ear]`: every open fires OpenKnob and OpenSlow in the same frame;
  CreakSlow / CreakStop come only while the GAME moves a leaf (the bedroom door with Rose); CloseCreakLong then Close
  (or CloseCreakShort then CloseSoft) when it shuts. OpenKnob muted: Tefa, of the one sound left at the touch
  (OpenSlow): *"the sound is ok"*. With OpenSlow muted too: *"doors don't make sounds so far"* (not wanted).
  Our own CreakSlow / CreakStop while a hand moves the leaf (b183): in the log at every push; Tefa did not object.
  Both forms of `CallSE` are found; all ten kinds known by their objects; each sound is counted ONCE per play.
- **The game shuts a hand-opened door 1 to 4 s after it opens** `[measured]`; our leaf swings shut with it over
  1.2 s and is held until the game's state is Closed, also when Tefa has walked on (b184; the log's "the game shut
  the door" lines). Tefa after b184: nothing more said of the jump.
- **DIFFERENT DOORS: Tefa's rule (17:5x)**: *"the doors that are different, not meant to be opened by hand, let them
  open the game's way, automatically from the distance, maybe we can just tweak the distance to be much less so
  basically i can still roleplay putting my hand near the door, but it just opens with proximity to me, there are a
  few of these doors in the game. and just normal doors, they can just open normally by hand."* Built in b186: a
  door found a crack open, swinging by itself (state CurveAnimation), or refusing the game's door start gets the
  game's own walk-in open let through for its own InteractDoor parts while a hand is within 25 cm or the body within
  60 cm (doors.txt, 3rd and 4th number). The swinging door: *"the swinging door did and it works really well"*,
  *"after the swinging door closed shut, it worked like that too"* `[verified-live, Tefa, n=1]`.
- **Tried and thrown out (b183 to b185): the hand taking such a leaf itself.** Tefa: the bolted door *"jankily opens"*;
  the swinging door *"just teleports open and stays open, and i can still hear the swinging creaking"*; with the
  game's door start on it (b184) it *"teleport opened my way, not the way i was pushing, then when i backed away, it
  teleported to swinging animation again"* `[disproved as designs, n=1 each]`.
- **Doors have names; several can share one hinge** `[measured, the log's "met" lines]`. The bolted door in the
  village is three: `Before_Dynamic/sm81_051_WoodDoor_01_Door_Dynamic_Out` (drawn, LittleOpened, 20 degrees),
  `After1_Dynamic/sm81_051_WoodDoor_01_DoorOneWayLock_1Way` and `After2_Dynamic/sm81_051_WoodDoor_01_Door_Dynamic`
  (both "NOT drawn" while the first shows). Until b186 the InteractDoor part was picked by nearness to the hinge, so
  the game was asked to open the wrong door of the three; from b187 a part must name the door in its own `Door`
  field, and a door whose object is not drawn (`via.GameObject.get_Draw`) is ignored.
- **THE BOLTED DOOR IS NOT SOLVED.** Half open as found: its own walk-in let through: nothing (b187); a hand on it
  asking `StartInteractDoor` on its own part: nothing (b188, Tefa: *"2 no, still needs A"*). A opens it. After it
  shuts: a hand *"makes a sound like the door has been activated for opening, but hand doesn't do anyhting. then
  when i back off and try again it's silence, until i open it with A, let it close on it's own and get close to it
  again"*. Tefa: *"maybe it's meant to open with pressing A?"* What A calls is not known (`InteractDoor.Interact`,
  an `app.InteractBasic`; `SetForceInteract(via.GameObject)` exists and is untried).

## 2. A fault of the frame, found and fixed (b182)

At the prologue's end the dying player object threw twice on `get_Transform`; rule 6 then switched that call off
for the whole run, so `ready` had no transform and every part that needs the player stood down for good, while the
body turn and the walk-in hook went on: idle hands at the face, no door opened by hand or by walking (Tefa's first
two clips). Now a call that threw twice in a row rests 5 s and is tried again. The next run crossed nothing like it,
but ran a full village session with every part alive `[verified-live 2026-11-26, n=5 runs since, no "resting" line]`.
That the fix survives the prologue's end itself: NOT seen (every later run started from the village save).

## 3. The body at a stop, after a cutscene, at a vault

Tefa: *"when i run and stop, Ethan's whole body get's pushed forward so for less than a second i'm looking through
his body, like from the centre of it"*; *"cutscenes still end with the torso being pushed forward a little"*; a vault:
*"the body stays up like i'm looking out from inside it"*, later *"after a vault the body jumps forward for about a
second, then teleports back"*.

- **Two "body pin" designs in the bridge script were WRONG** (b183, b184) `[disproved, each worn once]`: the first
  read the Head joint as the head (72 cm off standing still; the body dragged 63 cm back: *"ethan is like more than
  50cm befing me"*); the second learned a standing offset and still measured 30 to 46 cm of "lean" from plain head
  movement (*"swinging with the head movement and doing weird stuff all over"*). The joints read at the script's
  camera step are not the posed body. The pin is off by default (`bodyplace.json` "pin").
- **Measured, with nothing changed** (`leanrec.cpp`, PrepareRendering post; b185; three stops from a run):
  standing, the neck (Neck_0) is 15 to 19 cm behind the eyes and the hip 10 to 14; at each stop the neck went to
  9 cm IN FRONT of the eyes, and each time the loader's cutscene flag was up `[measured 2026-11-26, n=3]`.
- **Why** `[read, RE8VR.cpp, the March source; the nightly was not read]`: `m_is_in_cutscene` = the camera's
  controller is not the fully controllable one, and it stays up one second longer; `update_body_ik` then sets the leg
  solver's centre offset to zero. The game switches that controller for a moment when a run stops.
- **b186**: when the flag is up and no event runs (`_GameEventAction` nil, arms not jacked) the bridge keeps placing
  the body and the body turn carries on (the flag is lowered only around our own `re8vr:update_body_ik`). After:
  the neck comes to 1 cm from the eyes `[measured, n=3]`; Tefa: *"less but it still does it"*.
- With the follow lag at 0.05 s as well (live): the hip stays at 10 to 14 cm and the neck still dips to 4 to 6 cm for
  a moment `[measured, n=3]`: the upper body's own lean in the stop motion, about 12 cm. Tefa: *"still jumps
  ahead"*; standing still with 0.05 s: *"still fine"* (twice).
- `bodyplace.json` in the game folder now: `follow_s 0.05, dead_cm 0` (was 0.9 / 1). Tefa has not been asked whether
  it stays; the script's built-in numbers are still 0.9 / 1.
- Real scenes are named in the log now (`InteractEvent` seen twice): left to the loader.

## 4. The legs (and the hands) while walking: NOT solved

Tefa: *"legs glitchy when walking"*, *"teleporty"*, *"jittery"*. His third clip, the last second frame by frame
(60 a second): looking down, the knee lifts smoothly for about ten frames, then in ONE frame the leg is down again
and the same lift starts over, about four times a second; in the same clip the hand holds and then jumps to its
new place several times a second `[measured from the clip, n=1 clip]`.
Disproved by Tefa's own live comparisons `[disproved 2026-11-26, n=1 each]`: the body turn's 25 degree free zone (0
degrees: *"legs same"*); the body's follow lag (0.05 s: *"3 still glitchy, teleporty"*); "steps instead of sliding"
(steps 0: *"2 same"*).
Not tried: the walk turned by head minus body (`bodyturn-walk` in off.txt), the body turn hook itself, the still
spine, the bare base without our frame (`frame` in off.txt). **The jitter recorder is NOT wired into rebuild 2**
(`begone.py new`: nothing new all day): PROTOCOL section 18 says it must be; that is the first job.

## 5. What is NOT established

- Anything of today past the first village houses, with a weapon, in a fight, from the prologue's end onward in one run.
- That `get_Draw` is the right "is this door shown" test in general (seen right on one triple door).
- Which doors in the game are "different"; whether any story door now opens early (none seen).
- Whether the remaining 12 cm lean at a stop is what Tefa still sees, or something else again; the vault was never
  measured (no fence where he tested with the recorder in).
- The cost of the door part per frame (up to six leaves, several calls each); not measured.

## 6. Tools and switches made today

- `flat-to-vr-RE-toolkit/tools/tdb-read.py` (types off the exe, no game running).
- off.txt: `doors`, `doorsounds`, `gamearms`, `leanrec`. Live files in the data folder: `doors.txt` (hand reach cm,
  body reach cm, near-hand cm, near-body cm), `doorsounds.txt` (kinds to mute), `bodyplace.json` (`pin`, `steps`,
  `follow_s` ...), `bodyturn.txt`.
- `leanrec.cpp` is dev only and comes out when the body at a stop is settled.
