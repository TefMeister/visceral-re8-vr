# The gun aims right: the reference pose (2026-10-25, home PC)

Tefa, in the headset, 2026-10-25 21:45: *"right now the gun is aiming correctly after so many runs ... this is how the gun
is naturally in the player hand and should always be like this, regardless of sitting or standing or playing in poor
light conditions"*.

What was new in that run: the right grip no longer presses the game's aim, so the game never enters its aim stance
(`visceral_re8_holsters.lua`, `AIM_OFF = true`, commit ee750e4). The likely reason the gun now aims right is that the
aim stance moved the gun into the game's own aiming pose, away from the hand `[hypothesis]`.

These are copies of every setting that places the gun and the hands, exactly as they were during that run. If the gun
ever stops aiming right, compare against these first.

| File | What it sets |
| --- | --- |
| `visceral_re8/zones.json` | the grab zones and the "gun in the right hand" box (Grab Zones app) |
| `visceral_re8/grip_spots.json` | the front-grip spot per gun |
| `visceral_re8/hand_holds.json`, `slide_hand.json`, `hand_state.json` | the left hand on the gun and on the slide / bolt |
| `re8_vr/re8_vr_holster.json`, `re8_hand_gestures.json`, `re8_vr_ammo_hud.json` | Andyalpa's holster, gestures and ammo HUD settings |
| `visceral_re8_holsters.lua` | the script with `AIM_OFF = true` and the let-go holster |
