# 2026-11-06 22:3x: every saved hand pose, taken out so the game's own finger movements can be judged

Tefa: *"can you save the hand poses done so far so they don't get lost, but then set all of them to default, so i can check
the game's own animations and see if they work."*

- `guns/`: all 73 Hand Poser files from the game's `reframework/data/hand_poser/guns/` (the window's own copy in
  `%APPDATA%\HandPoserVR\re8\guns\` was identical, checked by hash). Both live folders are now EMPTY.
- `window/autosave.json`: the Hand Poser window's last pose (also taken out of the window's folder).
- `dock_poses.json`, `gate_turns.json`: Dock Poser's wrist spots and the Wolfsbane's kept left-hand turns, copied for safety
  but LEFT IN PLACE (they place the hand, they are not finger poses).
- `MANIFEST.sha256`: hashes of every file here.

To put them all back: copy `guns/*` into both live folders (game closed).
