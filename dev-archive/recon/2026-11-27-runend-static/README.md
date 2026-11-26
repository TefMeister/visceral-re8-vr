# Reading Village's script code off the exe, with no game running (2026-11-27, /pd, RE8-096)

Small scripts written while tracing the running-stop motion. They read `re8.exe` only; nothing here is game content.
Run them from this folder; the exe path is at the top of `rdis.py`, the type database reader is the toolkit's `tdb-read.py`.

| script | what it answers |
| --- | --- |
| `rdis.py <address>` | the function around an address (bounds from the exe's unwind table), disassembled |
| `pf.py <address>` | one function, with every rip-relative target worked out |
| `lit.py` / `litx.py <regex>` | the game's string literals by number, and every place in the code that loads one (`mov ecx, <number>; call 0x14118c3c0`) |
| `cst.py <state name> ...` | the address of a motion state's name hash (set up in the static constructor at 0x142b0af90) and every function that reads it |
| `ripx.py <address> ...` | every rip-relative reference to an address, in all of the code |
| `gf.py`, `fl.py` | functions that touch a given field offset; the function list of an address range |
| `names.py <from> <to>` | every method name in the type database between two names |

What they found is in `modding-notes/2026-11-27a-what-starts-the-running-stop-read-off-the-exe.md`.
