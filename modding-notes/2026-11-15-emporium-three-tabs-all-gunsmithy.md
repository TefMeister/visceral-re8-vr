# 2026-11-15: the VR Options Emporium, three tabs, every one the Gunsmithy (Developer PC, Opus, no game launched)

## What Tefa asked (2026-11-15 morning, word for word where quoted)

*"the VR options emporium menu look so good now!! ... we need all the sub menus to look the same, like gunsmithy i think, it
has all the things needed and is neatly categorized, and has sliders."* Three tabs, each with its own list:

**1 Comfort and Controls:** 1 snap turn on / off and the degrees; 2 movement vignette on / off and a strength slider;
3 seated or standing play (changes the holster zones; in RE8, RE2 and RE3 an automatic height and recentre at game launch,
or when seated / standing is changed); 4 snap turn on enemy grabs: 1/4 = four small snap turns, 1/2 = two, or fully at once;
5 decoupled pitch in cutscenes (*"game takes control only of the left and right camera movement but leaves up and down to
player"*); 6 head bobbing on / off; 7 left / right handed (*"not sure if we will do this one"*); 8 2D cutscenes (*"not sure if
even doable, but you managed to get this working in SH2"*); 9 controls tutorial pictures explaining our bindings.

**2 Game Settings:** 1 holster zones: our Holster Zones app in the game, for seated and standing separately; 2 grip zones:
the same, the spheres showing as they do in the app, *"without window view required"*; 3 recoil strength; 4 rumble: every
holster part separately in a holsters rumble category, and weapon rumble on / off or *"buzz once when LG or RG has been
pressed for grip zones, ammo insert and if you can think of anything else, maybe shooting strength and how left and right
hand controller rumbles"*; 5 reloading immersive / automatic (*"semi automatic we will not do so please scrap that idea"*);
6 yellow tape: game original / blend into background; 7 weapon smoothing for all weapons, strengths for both hands;
8 manual flashlight on / off (*"off still means that a flashlight can be held in hand, it just switches on/off on it's
own"*).

**3 Graphics and Display:** 1 DLSS on / off; 2 AFW (*"we'll see about that one"*); 3 SFM eye fix; 4 colour grading indoors /
outdoors / adaptive; 5 contrast (*"these settings have to affect both game and scope at the same time and same amount"*);
6 hands and body on / off, with options to turn them off by themselves in game and in cutscenes; 7 decoupled pitch, only if
someone would need it switchable.

## Decided (Tefa 2026-11-15)

- Order: first all three tabs rebuilt in the Gunsmithy style with what already works, then the new switches one at a time,
  the research ones last.
- A setting that is not built yet stays **hidden until it works** (no greyed "coming soon" rows): `hidden = true` on an entry.
- AFW = **PureDark's frame warping** (not looked at yet). DLSS is an option, **off by default** (lifts the 2026-10-31
  "REFramework's DLSS stays off" rule for Village only as a menu choice; the default keeps it).
- Decoupled pitch: one switch, under Comfort (my call, it was on two lists).
- *"if Fable is needed we need to do these parts on wednesday"* (2026-11-18): the Fable items below wait for then.

## Step 1, built (not run): every tab is the Gunsmithy

- New file `dev-archive/native/lua/visceral_re8_emporium_layout.lua`: the three tabs, their categories in order, and which
  setting goes where (by the start of its label, or a script's own `place = { tab, cat }`); a category of more than four
  settings becomes "Name (1/2)", "Name (2/2)". Checked outside the game on all 30 settings of today: all placed, the
  hidden test entry left out, the longest tab (Game Settings) needs 6 column entries `[verified-numerically 2026-11-15]`.
- `visceral_re8_emporium_shop.lua`: tab names Comfort and Controls / Game Settings / Graphics and Display; the first and
  third cards walk the game's own selection to the Gunsmithy card and OK it there, keeping the wanted tab; in the Gunsmithy
  the gun column = the tab's categories, the header = tab name over the category name, the four rows = that category;
  the left stick changes the tab in place; buttons work on a row; leading spaces off the holster labels. `ALL_GUNSMITHY =
  false` brings back the Supplies grid and the Duke's Purse. Desk commands: `custdump` (the Gunsmithy's fields and its whole
  control tree to the log), `tab <1-3>`. `[compile-verified]` (luac 5.4), the rest `[hypothesis]` until run.
- Not known yet: how many entries the gun column shows (it is the player's guns, `currentWeapons`: 6 on the save of
  2026-11-04; a new player has fewer, so the column must be lengthened or paged before anyone else plays it), and the
  column's own controls (to put the category names where the gun names are). The first flat run answers both: open the
  Emporium, pick each card, `custdump`, read the log line "the Gunsmithy is up: N gun(s) in its column, the tabs need 6".

## The list after step 1 (what each needs)

| Item | Now | Needs |
| --- | --- | --- |
| Head bobbing | "Camera shake while walking" exists | rename only |
| Recoil strength | exists | — |
| Weapon smoothing per gun, both hands | exists (rows by the gun in hand) | a gun picker row, to set guns not in hand |
| Seated / standing | sitting offset (Holster Zones' file), "Set my standing height now" | a choice row, auto height + recentre at launch and on change; RE2 and RE3 the same |
| Colour grading, contrast | in `visceral_re8_whitepoint.lua`, monitor menu only | rows; the scope by the same amount (look at how the scope draws) |
| Snap turn + degrees | REFramework's own | read / write REFramework's setting from our row |
| Vignette | none | build (a darkening at the eye edges while moving / turning) |
| Snap turn on grabs | none | find the grab moment; turn in 1/4, 1/2 or one step |
| Rumble rows | "Gun shaking the controller" | split by holster and by weapon event |
| Reloading immersive / automatic | immersive only | automatic mode (`breech.cpp` notes the old modes) |
| Manual / automatic torch | the torch in the hand (b116) | darkness reading for the automatic one |
| Hands and body on / off, auto in cutscenes | none | the body and arms draw switches, a cutscene reading |
| DLSS (off by default), SFM eye fix | REFramework's | rows on REFramework's settings |
| Holster / grip zones in the game | the Holster Zones and Grip Zones windows | in-game editing rows + the spheres; seated and standing apart |
| Yellow tape | none | find the paint's material; a blend |
| Controls pictures | none | pictures on a screen of the shop |
| 2D cutscenes, decoupled pitch in cutscenes, AFW | none | research: `MODEL: FABLE`, Wednesday |
| Left / right handed | parked (Tefa unsure) | — |
