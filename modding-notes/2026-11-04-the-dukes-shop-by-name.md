# The Duke's shop, called up by name (2026-11-04)

Home PC, Fable, flat (no headset answering), 17:11-17:35. The job: Tefa's 2026-10-30 ask, *"design it using the game's
own Duke's shop interface, that the player can actually see in VR"*, for the Visceral options.

## What was found, in order

- **The live-game connector cannot run on this game's REFramework build** (no .NET in it; known since 2026-11-02), so
  the reading was done by a small Lua probe in `reframework/autorun` driven by a json file under `reframework/data`
  (`visceral_re8_shop_probe.lua`: names / manager / open / dump / inspect / create / show / settext / ...). Reloading it
  without a game restart goes through REFramework's overlay (ScriptRunner > Reset scripts), now a recorded
  Menu-o-matiC route (`reset-scripts`, replayed 6 times today).
- **`app.GUIManager` (singleton)** has `createGUIShopBuy()`, `createGUIShopCustomize()`, `isShowingGUIShop()`,
  `suicideGUIShop()`, `enterShopEvent()` / `leaveShopEvent()`, and the general `createGUI(UInt32 alias, Boolean)`.
- **A screen is made by its alias hash, and the alias hash is the RE Engine name hash** (murmur3_32 of the UTF-16LE
  name, seed 0xFFFFFFFF, the same hash as item and sound ids): `createGUIShopBuy()`'s handle carries alias 3474722425
  = hash("ShopBuy") `[verified-live 2026-11-04, n=1]`. So `createGUI(hash(name), true)` makes any screen by name.
  Found by name: **Shop** (app.GUIShop: the top, holds `menuHandle`, `bgHandle`, `initialMode`), **ShopBg**
  (app.GUIShopBg: the dark-red wall), **ShopBuy**, **ShopSell**, **ShopCustomize**, **ShopRecipe**. Not names:
  ShopTop, ShopMenu, ShopSelect, ShopMain, ShopTitle, ShopMode, ShopModeSelect, ShopList, ShopCategory, ShopFront,
  ShopEntrance, ShopDuke, DukeShop, Emporium, ShopCook, ShopTreasure, ShopCommon, ModeSelect.
- **`app.GUIShopMode`** has five modes, Menu / Buy / Customize / Sell / Recipe, with hashes that are hash("Menu"),
  hash("Buy") ... (mode names, not screen aliases). **The three-card screen is the "Menu" mode**; its screen alias is
  still unknown (made inside `app.GUIShop.openShop` as `menuHandle`).
- **A created screen draws nothing** until its driver's `drawSuspend` is false and it has been shown. `app.GUIHandle`
  = { driver (the screen's own component, e.g. app.GUIShopBuy), isManaged, aliasHash, isForceHide }. Every driver is
  an `app.GUIDriver`: `show(Parameter)`, `hide`, `enterExclusive`, `execute(GUIRequest)`, `get_step`, `set_drawSuspend`,
  `onShow(bool)`, `get_GameObject` (via the component).
- ⭐ **ShopBg shows in gameplay by script:** `createGUI(hash("ShopBg"), true)`, then on its driver
  `set_drawSuspend(false)` + `onShow(true)`: the Duke's dark-red embossed wall with the crest appeared over the
  village `[verified-live 2026-11-04, n=1, screenshot]`. Its tree is tiny (View > main > c_type (hidden) > main_bg
  Rect_Bg, c_type0 t_bg) and the component holds a **`via.render.Mesh`** and its own camera numbers (AppearPosition,
  NowFov, DistFov): the wall is a 3D object placed in front of the camera, **which is why the real shop is visible in
  the headset while our imgui window is not**.
- **ShopBuy's tree: 1302 controls** (`View > main > c_layout > bg_main t_bg_L; c_detail > c_parts_list > sl_list >
  item1..5/si_list (each c_item_btn, c_glow_size, c_item_size icn_parts/icn_item, c_name m_text/m_name) ...`), a
  ScrollList, a ScrollGrid, detail / stock / bullet panels, texts `m_name`, `m_text` and the driver's own
  `itemNameText`, `itemDescriptionText`, `itemCategoryText`, `stockText`. Its game object draws (draw=true) but the
  list is empty with no `buyUnits`.
- ⛔ **`onShow(true)` on a freshly created ShopBuy with no data crashed the game** (17:34:39, reframework_crash.dmp,
  380 KB, on the Gold Digger `crashes` shelf once the collector fix lands): it needs the menu data the real flow
  gives it (`get_menuData`, buyUnits, the mode). `openShop(Parameter)` with an empty `app.GUIRequest.Parameter`
  (a class with no fields of its own) throws, harmlessly.

## What it means for the Visceral Emporium

The game's shop is three layers: the 3D wall (ShopBg, a mesh, VR-visible), the mode menu (the three cards; alias not
yet found), and the mode screens (Buy / Sell / Customize / Recipe, 2D via.gui trees that REFramework projects into
the headset the way it does the inventory). Two routes to Tefa's screen, cheapest first:
1. **Borrow the wall, draw our own words on it.** Show ShopBg by script (works), then draw the three cards and the
   settings as text / world-space quads of our own in front of the wall through the VR layer, or through REFramework's
   `draw` API if it reaches the headset. Needs a headset look to settle whether `draw.*` shows in VR.
2. **Borrow ShopBuy's list as the settings list.** Feed it fake `buyUnits` or set its `m_name` / `itemNameText` /
   `itemDescriptionText` texts with `set_Message` (the probe's `settext`, untested after the crash), hook
   `canBuyItem` → never, read `scrollListSelectionChanged` for the cursor. More to hijack, but the look is exact.
Either way the game's own flow (`openShop` with a real request) is what makes the cards; finding the Menu screen's
alias (try the names the mode names suggest: "ShopMenu" failed; next "ShopModeMenu", "ShopTopMenu", "MenuShop",
"ShopCard", "ShopSelectMode", or read `app.GUIShop.openShop`'s code with the disassembler) is the first step of the
next session.

## Tools fed today

- Menu-o-matiC: a mouse-wheel step (`wheel <window> N --at x,y`), recorded and replayed; the `reset-scripts` route.
- State-o-matiC: a still, answering game is "still" (idle, or waiting for a key), not "frozen"; a poke tells them apart.
- The always-on collector: a crash dump written in the game folder now counts as a crash.
- Village KNOWN.md: the day's facts.

## Second run, 18:01-18:08: the three-card screen is "ShopMenu", and the game takes our words

- **A name scan of 340 likely names (10 a frame) found exactly two: `Shop` and `ShopMenu`** (`app.GUIShopMenu`). "ShopMenu"
  had returned nothing in the first run, when no `Shop` had been made before it; made right after `Shop` it answers.
- **GUIShopMenu's tree (132 controls) IS the three cards:** `View > main > c_layout > l_list` (a `via.gui.SimpleList`) with
  `si_list0..2` (each: `HitArea_SelectItem`, `t_list_bg` texture, a `cursor` panel, `c_new` with two type panels, and the
  texts **`m_name0`** and **`m_name1`**: the card's title and its motto), a hidden `l_list_add` with four more items
  (si_list0..3, the extra modes), a `header` panel with **`m_header`** and **`m_header_desc`** (the shop's name and
  motto), `c_ui2000` (subtitle / interact prompts), `c_ui2002 > c_mode` (a mode badge with `m_text`).
- **`via.gui.Text.set_Message(string)` takes our words:** on ShopBuy, all 16 `m_name` controls set to "VISCERAL" read back
  "VISCERAL" `[verified-live 2026-11-04, n=16]`. So the cards can say Comfort / Graphics / Settings with their mottos, and the
  header "The Visceral Emporium".
- **Drawing is the open problem:** `set_drawSuspend(false)` alone draws nothing (ShopBuy with our words, ShopMenu: both
  invisible; the draw hook sees only the cursor and, after the failed show, a `GUIGuide`). `onShow(true)` on ShopMenu
  threw an exception (no crash this time); the wall (`ShopBg`) is the only one that shows this way, because it is a mesh.
  The 2D screens want the game's request flow: `app.GUIDriver.show(app.GUIRequest.Parameter)` / `execute(app.GUIRequest)`
  with the request the game builds in `app.GUIShop.openShop` (and `GUIManager.exclusiveTarget` for input). That is the
  next session's first job; the disassembler on `openShop` / `GUIShopMenu.onShow` is the way to read what they need.
- `app.GUIManager` also holds `prefabHolders` (`app.GUIPrefabHolder`) and `guiHandles`: the full alias table, if ever
  another screen name is wanted.

## Third run, 18:10-18:20: THE VISCERAL EMPORIUM IS ON THE DUKE'S OWN CARDS, IN GAMEPLAY

- **The order words a driver answers to** (its `ExecuteDict` keys are name hashes): Suicide, Show, Hide, SetSegment,
  SetState, SetAttachTarget, EnterExclusive, LeaveExclusive, and one unmatched (4213754707) `[verified-live 2026-11-04]`.
- ⭐ **`app.GUIDriver.show(app.GUIRequest.Parameter)` with a fresh empty Parameter SHOWS THE THREE-CARD SCREEN** (ShopMenu
  made by `createGUI(hash("ShopMenu"), true)`): the call throws an exception after doing its work, and the screen comes up
  over the village: "The Duke's Emporium" header, Supplies / Gunsmithy / The Duke's Purse with their pictures, the key
  guide "Purchase items  F OK  Close" at the bottom `[verified-live 2026-11-04, n=1, screenshot]`.
- ⭐ **Our words on it:** `set_Message` on `m_header` ("The Visceral Emporium"), `m_header_desc`, and per card
  (`settextat si_list0|m_name0|Comfort` ...) gives **Comfort / Easy on the stomach!, Graphics / A feast for the eyes!,
  Settings / Everything in its place!** in the game's own font and frames `[verified-live 2026-11-04, screenshot]`.
  Each card name lives twice (`l_list` and the hidden `l_list_add`); set both.
- **It takes the controls:** keyboard Right moved the selection (the guide line changed to the Gunsmithy's "Upgrade
  weapons to make them stronger"). F (OK) was NOT pressed: it would open the Buy screen with no shop data (the crash).
- `createExclusiveModeGUI(hash("Shop"), hash("Menu"))` gives the top `app.GUIShop` handle (not exclusive by itself);
  `enterExclusive` and the proper GUIRequest are the clean way, still to be tried.
- The probe: `visceral_re8_shop_probe.lua` v11 (commands: names, manager, type, open, create, createhash, exclusive,
  enterex, show, show2, request <word>, unsuspend, orders, inspect, dumpnow, dump, settext, settextat, handles, modes,
  aliasscan, call, close).

## What the Visceral Emporium build needs (next session, Opus; the design is settled)

1. Own script `visceral_re8_emporium.lua` reborn: X + A held 0.5 s -> createGUI(hash("ShopBg")) + show on its driver
   (the wall) and createGUI(hash("ShopMenu")) + `show(Parameter)` (the cards); set the header and the three cards' words
   with set_Message; swap the three pictures later (Texture0/1 under c_type0/1 of each card; our own textures or none).
2. Selection: read `GUIShopMenu`'s `simpleList` cursor (hook `simpleListSelectionChanged`, or read `lastIndex`) and
   swallow the decide: hook `openMenu(mode, bool, result)` / `mainStateFinished` to return without opening a mode, and
   instead open OUR settings page: the ShopBuy list dressed with our settings (`m_name` = label, price text = value;
   hook `canBuyItem` -> never; the detail panel's `itemDescriptionText` = the help line), or a plain list drawn with
   set_Message on ShopBuy's rows. Back (Escape / B) -> Suicide order on both handles.
3. Hide the game's own key guide line, or set its texts; keep the player frozen while open (the exclusive mode:
   enterExclusive on the ShopMenu driver, LeaveExclusive on close).
4. The headset look: the cards are the game's own 2D GUI, which REFramework already projects into the headset the way
   it does the inventory `[reported]`; one VR run confirms.

### Closing it (18:20)

- Keyboard Esc on the cards opens the game's PAUSE menu on top (GUIPause); Esc again closes the pause; the cards stay.
- `app.GUIManager.suicideGUIShop()` takes the cards (and the guide line) off cleanly: only the mouse cursor is drawn
  afterwards `[verified-live 2026-11-04, n=1]`. So the Emporium's Back is `suicideGUIShop()` (plus the wall's own handle).
- A GUIRequest cannot be made from Lua (`sdk.create_instance("app.GUIRequest")` gives nil), so the driver's
  `show(Parameter)` / `suicideGUIShop()` pair is the whole API we need.

## Tefa's design for it (2026-11-04 19:00, with three screenshots of the real shop's list screens)

Verbatim: *"what i mean is using these screens, they are the screens that open up when choosing one of the 3 tablets in the
emporium. all have things we can use, for instance in the shop screen can have a red lint in the corner for off, green for
on and a description on the right hand side for a description of what the setting does - crosshair on and off for example,
the one for upgrades, we can use these for sliders like smoothing strenght, reloading style - immersive, semi immersive or
automatic - , recoil strength and so on and the one for selling stuff can be graphics options like supersampling, dlss, eye
fix for single frame multipass, adaptive lighting if we can make that toggleable without breaking the scope colours and
brightness and so on. the tree big tablets are for the setting group - we still have to name them but for now comfort,
graphics and settings will do, and the Visceral emporium needs to be called VR Options Emporium. we also need to come up
with custom images for all of these"*

So:
- **Header: "VR Options Emporium".** The three cards stay the setting GROUPS (Comfort / Graphics / Settings for now; names
  to be decided).
- **A card opens the game's own LIST screen behind it, filled with our settings, not one setting per card** (the cards-as-
  settings pages built today are a stop-gap):
  - **The Buy screen (the item grid, "Supplies")** = ON / OFF switches: each tile a setting, a **red tint in the corner =
    off, green = on**, the description on the right-hand side (crosshair on/off, for example).
  - **The Gunsmithy (upgrade list with level bars)** = SLIDERS and STEPPED CHOICES: smoothing strength, reloading style
    (immersive / semi-immersive / automatic), recoil strength, and so on; the level bars show the value.
  - **The Duke's Purse (the sell table: name / on hand / price / number)** = GRAPHICS options: supersampling, DLSS, the eye
    fix for single frame multipass, adaptive lighting (only if it can be switched without breaking the scope's colour and
    brightness), and so on.
- **Custom pictures for all of it** (the three cards, every tile and list row): to be designed together.

What it takes: those three screens are filled by the game's real shop flow (ShopBuy needs buyUnits; it crashed with none).
So the next step is to learn how the game fills them: watch one real Duke visit with the hooks on (openMenu passing through),
read what each screen is given (assortment, units, specs), then feed our own rows the same way.

## Evening, 19:10-20:05: the real Duke recorded, the walk bug found and fixed, the kitchen = REFramework's menu

- **The real Duke, driven by a pretend Xbox pad** (right stick turns, A talks: "Open the shop."), with the probe's
  `watchshop` hooks listening `[verified-live 2026-11-04, n=1 visit]`:
  - in: `createGUI(hash("Shop"))`, then `app.GUIShop.openShop(app.GUIShopOrder.GUIRequestOpenShopParameter {mode = Menu,
    cursorIndex 0, existMerchant true, result})`; the game then makes RemainMoney, ShopBg, ShopMenu itself and calls
    `GUIShopMenu.openMenu(Menu)` once (V = 0) on the way in.
  - a card: `openMenu(mode)` with V = 1 Buy, 2 Customize (Gunsmithy), 3 Sell (Duke's Purse), 4 Recipe (the Kitchen);
    each screen is made with `createExclusiveModeGUI(hash("ShopBuy") ...)` and opened with its own request
    (GUIRequestOpenShopBuyParameter, ...Customize..., ...Sell..., ...Recipe...).
  - **Supplies (ShopBuy)**: `assortmentHash` 1481905281 (this Duke's stock), `collectBuyUnits` fills `buyUnits` (24 here),
    `setupScrollGrid` lays the tiles. **Gunsmithy (ShopCustomize)**: `currentWeapons` (the player's 6 guns), the upgrade
    rows from each gun's spec, `tuneupBy`. **Duke's Purse (ShopSell)**: `sellUnits` (32, the player's own items) from
    `collectSellUnits`. **Kitchen (ShopRecipe)**: `materialUnits` (3), recipe rows with a tick box, a dish picture, an
    ingredients table and a "Reward" line.
  - out (B on the cards): hide on the TOP screen (app.GUIShop), then `GUIShop.onHide`, `GUIShop.onFinishedHide` (leaves
    exclusive mode, brings the ammo HUD back).
- **The walk bug's cause** `[verified-live 2026-11-04, n=4 boots]`: opening by calling the driver's openShop (or making
  the wall and cards by hand) skipped the shop's ORDER bookkeeping, so the top screen never finished closing and kept
  the player's controls. **Fix: open through the order object** (`driver:get_order()` is an `app.GUIShopOrder` with
  `openShop(mode, cursorIndex, existMerchant, result)`), **close by hiding the TOP screen through its order**
  (`order:hide(false, false, false, "")`). Walking after a full loop: picture change 21.9-26.6 (stuck runs read 0.0-0.05).
- **Back on a page**: the game's B hides the top screen; it reaches us twice (the order's hide, then the driver's hide),
  so the first is turned into Back and the second is swallowed for 0.6 s. **The card's identity** comes from openMenu's
  mode (V), since the lit-card reading only knows the three-card list.
- **The kitchen (Tefa: "the kitchen can be reframework full ui")**: the fourth card reads "Every Setting / REFramework's
  full menu"; picking it closes the shop the game's way, then the native plugin presses REFramework's menu key
  (new `src/menukey.cpp`, bridge slot 185 `S_MENU_KEY`; REFramework's Lua can only ASK whether its menu is open). Seen:
  the shop closed, REFramework's menu opened, the player walks afterwards `[verified-live 2026-11-04, n=1]`.
- The Emporium script now ships with the plugin's installer (`tools/build.sh`); the plugin build with menukey deployed
  2026-11-04 19:51 (backup `_backup-2026-11-04-1951-before-visceral-re8-deploy`).

## Next (the design Tefa gave, in order)

1. Supplies as the ON/OFF screen: let the game open ShopBuy for a Comfort/Graphics/Settings group (pass openMenu
   through with mode Buy), then after `collectBuyUnits` trim `buyUnits` to our count and, after `setupScrollGrid`,
   write each tile: price text = On / Off, a red / green tint on the tile's corner, `itemNameText` / `itemDescriptionText`
   = the setting's name and help; A on a tile flips it instead of buying (hook `buyItem` / `decideBuyItem`).
2. Gunsmithy as the slider screen (upgrade rows and level bars), Duke's Purse as the graphics table.
3. Custom pictures (together), the group names, then one headset look.

## 20:05-20:25: Supplies is the ON/OFF screen; "no merchant" ends the second freeze

- A group card opens the game's real Buy screen (openMenu passed through; ShopBuy's assortmentHash = the village Duke's stock
  1481905281). After `collectBuyUnits` the list is cut to the group's on/off settings; after each `setupScrollGrid` /
  selection change the tiles are written: the price text = On / Off, the red Sold Out banner (text "Off") shown when off,
  the corner marker (c_new > Texture0) tinted green / red; the header = the group's name and motto; the description panel =
  the setting's name, the group, its help line. The grid's tiles are `si_list` (the first), then `item1` .. `item15`.
- A on a tile first asks `canBuyItem` (with needUnitSelectDialog, isSoldOutByUnit); our tiles have no item, so the game
  stopped there. The flip is done in that question (skipped). Moving across tiles flips nothing `[verified-live, n=1]`.
- ⛔ A trip into ANY real sub-screen froze the player after closing, even with none of our changes (`realraw` switch,
  n=2); `openShop(..., existMerchant = true, ...)` waits for a merchant's goodbye that never comes. **existMerchant = false
  fixes it**: walking after Supplies in/out, flips and the Graphics card: picture change 22.0 and 25.9 `[verified-live
  2026-11-04, n=2]`.
- Seen: "Comfort / Easy on the stomach!", five tiles (Camera shake while walking Off, Other camera shakes Off, Roomscale
  movement On, two more On), "Now: Off. Press to change." Rough edges left: the third tile's "On" text did not show; the
  game's own item pictures stay on the tiles (our pictures to come); the unused tiles stay as empty slots.
- Graphics and Settings still open the game's own Gunsmithy and Duke's Purse unchanged (they are next).

## 20:40-21:00: the Gunsmithy is the SLIDER screen

- The second card opens the game's own Gunsmithy (ShopCustomize). The gun column picks the GROUP (first gun = Comfort,
  second = Graphics, third = Settings, read from `currentWeaponIndex`); its upgrade rows (`c_list0..3`, in both the left list
  and the right summary) become the group's sliders and choices first, then its switches: `m_name` = the setting,
  `m_lv` = its value, the price hidden, the six-step bar (`bg_gauge0..5` shown up to the steps, `gauge0..5` filled) = where it
  stands. The screen is caught on its own per-frame `onLateUpdate`; our words go back on every 6 frames (the game re-lays it).
- A on a row asks `canTune` first (then `tuning` would upgrade and the "Upgrade weapon?" question would come): both skipped,
  `canTune` answers no; the lit row comes from the screen's own `cursorIndex` (canTune's argument read one row too far).
  Seen: "Comfort / Easy on the stomach!", "Recoil strength" with a 6-step bar, the switches as one-step bars; three A's took
  Recoil strength 2.0 -> 2.5 -> 3.0 (bar full) and five more wrapped it back to 2.0 `[verified-live 2026-11-04, n=1]`.
- Left: the slider row's "Lv. 2" text is still the game's (our value shows on the switch rows); the gun pictures and the gun
  name ("LEMI / Handgun") stay; pressing A on the real Gunsmithy BEFORE our hook was in left a dead "Upgrade weapon?"
  question on screen until the game restarted (nothing was bought).

## 21:00-21:15: the Duke's Purse is the GRAPHICS TABLE; the real screens are the default

- The third card opens the game's own sell table (ShopSell). `collectSellUnits` -> cut to the group's settings (40 -> 9);
  each row (`si_list`, `item1` ..., in the `sl_list` that holds `c_count`): `m_name` = the setting, the row's last `c_num`
  ("On Hand") = its value, the "No." count emptied, the price and the total hidden; header = the group, the description
  panel = the help line + "Now: <value>. Left / right to change."
- Left / Right on a row call `changeSellCountBy(delta, bool)` -> our step down / up (skipped); A (`canSellItem`, `sellItem`,
  `onSellDecideDialog`) steps up, never sells. Seen: the Settings group as a table (Holsters, Hip holster, Shoulder holster,
  Left chest (knife), Right chest (healing), Flashlight, ...), Right turned Hip holster Off, Left back On `[verified-live
  2026-11-04, n=1]`.
- `real_screens` is now ON by default: Comfort -> the Supplies grid (switches), Graphics -> the Gunsmithy (sliders), Settings
  -> the Duke's Purse (the table), the Kitchen -> REFramework's menu. All three in and out, then close: the player walks
  (picture change 23.2) `[verified-live 2026-11-04]`.
- Open questions for Tefa: which settings belong in which group (today each card shows its group's settings in that
  screen's style); the group names; our pictures; the slider row's "Lv." text; then one headset look.
