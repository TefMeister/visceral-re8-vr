# Village weapon ids

The game's own id is the weapon owner's name (`ri3046`); Andyalpa's files write it `ri3046_Inventory`
(`weapons::canonical` turns one into the other). Source: Andyalpa's Hands Off pack (`re8_vr_recoil.lua` catalog, the two
melee ids in `re8_vr_ammo_hud.lua`) `[reported]`, none checked in our own run yet. A web and GitHub code search
(2026-10-18) found no public Village id table. The plugin writes every held weapon id it sees to
`reframework/data/visceral_re8/weapon_ids.json` (`NEW` = not in this list), so missing ones show up by playing.
Expected missing: Chris's weapons and grenades, the Shadows of Rose extras.

How each reloads by hand is ours, from what the gun is `[inferred-static]`.

| Id | Name | Reload by hand | Where it goes in | Rack / pump |
| --- | --- | --- | --- | --- |
| `ri3040` | M1911 | magazine | at the gun hand | slide |
| `ri3046` | LEMI | magazine | at the gun hand | slide |
| `ri3047` | V61 Custom | magazine | at the gun hand | slide |
| `ri3050` | S.T.A.K.E | magazine | at the gun hand | slide |
| `ri3115` | Rocket Pistol | magazine | at the gun hand | slide |
| `ri3122` | Samurai Edge - AW Model-01 | magazine | at the gun hand | slide |
| `ri3124` | USM-AI | magazine | at the gun hand | slide |
| `ri3135` | LEMI - Shadows of Rose | magazine | at the gun hand | slide |
| `ri3081` | LEMI - Mercenaries | magazine | at the gun hand | slide |
| `ri3082` | M1911 - Mercenaries | magazine | at the gun hand | slide |
| `ri3083` | V61 Custom - Mercenaries | magazine | at the gun hand | slide |
| `ri3130` | USM-AI - Mercenaries | magazine | at the gun hand | slide |
| `ri3042` | F2 Rifle | magazine | ahead along the barrel | bolt |
| `ri3087` | F2 Rifle - Mercenaries | magazine | ahead along the barrel | bolt |
| `ri3049` | WCX | magazine | ahead along the barrel | charging handle |
| `ri3125` | Dragoon | magazine | ahead along the barrel | charging handle |
| `ri3129` | Dragoon - Mercenaries | magazine | ahead along the barrel | charging handle |
| `ri3048` | SYG-12 | magazine | ahead along the barrel | charging handle |
| `ri3086` | SYG-12 - Mercenaries | magazine | ahead along the barrel | charging handle |
| `ri3021` | W870 TAC | single shells | ahead along the barrel | pump |
| `ri3085` | W870 TAC - Mercenaries | single shells | ahead along the barrel | pump |
| `ri3036` | M1897 | single shells | ahead along the barrel | pump |
| `ri3084` | M1897 - Mercenaries | single shells | ahead along the barrel | pump |
| `ri3147` | M1897 - Shadows of Rose | single shells | ahead along the barrel | pump |
| `ri3023` | GM 79 | single grenades | ahead along the barrel | — |
| `ri3008` | M1851 Wolfsbane | single rounds | at the gun hand | — |
| `ri3116` | Handcannon PZ | single rounds | at the gun hand | — |
| `ri3022` | knife (melee) | — | — | — |
| `ri3044` | knife (melee, second) | — | — | — |

Gun parts: not known for Village. The plugin tries `_04` as the magazine and `_01` as the slide (RE2 / RE7 names)
`[hypothesis]`, and logs every gun's joints the first time it is held (`[visceral-re8] joint <id>[n] <name> ...`).
