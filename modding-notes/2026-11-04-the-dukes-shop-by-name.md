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
