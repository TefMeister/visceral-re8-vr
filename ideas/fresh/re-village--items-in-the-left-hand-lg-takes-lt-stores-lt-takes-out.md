# Items in the left hand: LG takes, LT stores, LT takes out

Order: 4024
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-10-27

`[raw]` · `[looks doable]` — *the left-hand pose system exists; the inventory calls are not checked*

**What Tefa said (2026-10-27):** after the guns, items get the same hand poses per spot; the left grip takes an item, the
left trigger while holding it puts it into the inventory, and the left trigger takes it out again.

**What it'd take:** a held-item state for the left hand (the pickup the game already does, shown in the hand), a store
call into the game's inventory on LT, and the take-out on LT; the pose per spot then saves an item's hold like a gun's.
`MODEL: OPUS`.

Verbatim record: [`inbox/2026-10-27-village-dukes-emporium-quickslot-and-item-pickup.md`](../inbox/2026-10-27-village-dukes-emporium-quickslot-and-item-pickup.md)
