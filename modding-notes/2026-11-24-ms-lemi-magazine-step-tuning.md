# 2026-11-24 evening, /ms (Tefa in the headset, Build PC, Opus): the LEMI's magazine coming out, tuned frame by frame

Started as a /ms on Hand Poser (Window View 1.15's tilt / turn test); Tefa turned it to the LEMI's magazine.

## What Tefa asked (word for word)

- *"when taking the mag out of the Lemi, i need to be able to tune the fingers on the way from being docked on the bottom of
  the mag, then B pressed to release it all the way to until it lands on my hand. on the way, the hand turns and finger
  positions change so they clip through the mag and i need to be able to tune them step by step, the issue is, the mag and
  hand on it is not steady when it is in the chamber still and moves around and jitters with my head movement"* (clip
  `D:\Capcut export\1124.mp4`); then *"that is only when using hand freeze as far as i can tell. not 100% sure"*.
- *"cant we use animation and timing to make the fingers curl and hand move during the mag eject with LG docked?"*
- After b160: *"ejecting a mag, then getting a new mag from the pouch, hand should travel wit the mag to the chamber and go in
  a little, then need a final hand push from the player"*; *"i really need hand freeze to work on the mag too to freeze it,
  so it then travels from that point bacwards and forwards when i tune the animations and timing frame by frame so hand
  freeze just freezes the hand on the part, same with sliders, pump handles and other moving weapon parts"* (clip
  `D:\Capcut export\hand freeze not working and the little bump.mp4`).

## What was built

- **b160** (0fd233e): on the LEMI (settings `MAG_PULL_FOLLOWS_CLIP`) the left hand follows the game's `mag_out` finger clip
  by how far the magazine is down the grip (shellclip `follow` / `unfollow`), not by time; Hand Poser stands aside for the
  left hand meanwhile (slot 186, nothing changed there). A frame held in Animation & Timing holds the magazine at that
  frame's point (`held_progress`, reload `rail_frame`), LG may be let go; the clip's WHOLE HAND move now acts during the pull
  (dockpose, RAIL only). `[compile-verified 2026-11-24]`
- **b161** (8c9eed8): Hand Freeze (or Window View's controller mode; sleephands `held_still`) holding the left hand keeps the
  magazine on the grip, and the slide / pump, where they are, hand on them; unfrozen, the travel carries on from there. A
  fresh pouch magazine at a handgun's well goes onto the grip's line: up by itself with the hand on it, 30% short, then the
  hand's push (`PISTOL_FRESH_NEEDS_PUSH`; before, it seated by itself in 0.2 s, log 22:50:39). A window hold of ANY clip now
  wins over the following (b160 log 22:51:24: Tefa held `grip`, the following took the hand straight back).
- Animation & Timing: HOLD A FRAME starts on the frame the hand shows (0578806); plain words instead of changing numbers
  (2cfcbdb); numbered movement boxes instead of the drop-down, which stayed on top of everything and could not be changed in
  the headset (7a16695); PLAYING NOW folded away (73dfe2b).

## What Tefa saw

- b160 worn: the log shows the following started and let go on every pull `[verified-live 2026-11-24, n=4, log only]`.
- b161 worn: *"hand freeze now freezes the mag beautifully. the arrows work too with HOLD A FRAME! awesome."*
  `[verified-live 2026-11-24, n=1]`
- NOT yet checked: the pouch magazine's travel and last push (Tefa: next launch); the slide / pump freeze; whether the tuned
  frames then show in a real pull.

## Not established

- Why the docked hand jittered with the head under Hand Freeze before b161 (the rail measured the frozen left controller
  against the moving gun is the likely reading `[hypothesis]`); b161 removes the case either way.
- The pump and the slide do not follow a clip yet (board RE8-070, Tefa: later). Pistol slides have no recorded clip.
