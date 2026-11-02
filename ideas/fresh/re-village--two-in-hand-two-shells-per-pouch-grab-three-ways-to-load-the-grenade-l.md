# Two in hand: two shells per pouch grab, three ways to load the grenade launcher, two magazines for the pistols

Order: 4022
From: the ideas repo, `games/re-village.md` (<https://github.com/TefMeister/mod-ideas/blob/main/games/re-village.md>), copied 2026-11-02

`[raw]` · `[looks doable]` for the shells and the grenade launcher (*judged from the mod's code: rounds in hand, the shell port
zone, LT at a dock and the game's own shell-in finger movement all exist; not built*) · `[hard]` for the second magazine
(*nothing draws a second magazine in the hand yet; unchecked*)

**What Tefa said (2026-11-02):** pump shotguns: LG at the pouch takes TWO shells (one if only one is carried or there is
room for only one); the hand docks at the shell port and LT pushes them in with the game's own hand movement. Single-shot
grenade launcher, three ways: (1) a new round already in hand, dock at the open barrel, LT swaps the spent one out and
pushes the live one in; (2) take the spent case out and keep LG held to the pouch: a buzz says the live round is in hand
too, and at the barrel it goes in by itself; (3) throw the spent case away, take a new round, bring it to the barrel and
it goes in by itself, held by the hand all the way until LG lets go. Pistols: the empty magazine kept in hand (LG held) to
the pouch puts a full one in the same hand, the empty in the palm and the full between the fingers, like the flat-screen
reload. The same for RE2 and RE3 where it applies.

**What it'd take:** a round count in hand (1-2, capped by what is carried and the room left) and LT at the shell port
instead of the automatic insert; a small state per grenade launcher (spent / live / both in hand); a second magazine
model held in the hand with its own pose.

Verbatim record: [`inbox/2026-11-02b-village-reloads-two-in-hand.md`](../inbox/2026-11-02b-village-reloads-two-in-hand.md)
