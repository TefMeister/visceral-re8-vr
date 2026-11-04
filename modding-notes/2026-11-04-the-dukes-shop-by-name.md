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
