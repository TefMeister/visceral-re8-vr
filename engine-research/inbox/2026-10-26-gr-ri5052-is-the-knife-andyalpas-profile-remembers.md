# /gr: ri5052 is the knife Andyalpa's own profile remembers

From: `/gr`, 2026-10-26 (estate sweep). Found in our own repo while searching, not on the web.

**The board row:** `[VR USER]` "THE CRASH: CAUSE READ, GUARDED, UNWORN": *"Still unknown: what ri5003 / ri5052 are"*.

**Lead** `[inferred-static 2026-10-26]`: Andyalpa's shipped holster profile,
`dev-archive/original-lua/data/re8_vr/re8_vr_holster.json`, saves `"last_knife_id": "ri5052"` (beside
`last_pistol_id` ri3046 and `last_longarm_id` ri3036). So ri5052 is a knife's item id, and the stalled swap that crashed
was most likely a swap to the knife's INVENTORY item (`ri5052_Inventory`) rather than its `app.WeaponMeleeCore`, which
is why the guard's knife test did not match it. ri5003 is probably another knife variant `[hypothesis]`. A public search
found no Village item-id table, and GitHub code search finds the two ids only in this repo `[reported 2026-10-26]`.

**Suggested change:** note it in `weapon-ids.md`; when the guard next logs `REFUSED`, check whether the refused item is
the knife being drawn through the D-pad, and consider letting a knife's inventory item through by resolving it to its
weapon core instead of refusing it outright.
