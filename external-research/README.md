# visceral-re8-vr — `external-research/`

Ongoing **public research** findings for the **Visceral — RE8 (Village) VR** add-on: leads, prior art and technique write-ups gathered from publicly available sources (other mods' public pages and repos, engine documentation, forums), kept **separate from hands-on modding work**.

This folder exists so a dedicated research-only session can run *at the same time* as reverse-engineering and coding work without any risk of the two colliding: research writes only here (plus create-only files in other folders' `inbox/`), and the modding side reads this folder when it wants to check for new leads. See [INDEX.md](INDEX.md) for the running list of topics.

## The folders for Visceral — RE8 VR

Everything for this game lives in one repository, one folder per job. You are in **`external-research/`**.

| Folder | What lives here |
| --- | --- |
| [`dev-archive/`](../dev-archive/) | The working source: the native C++ REFramework plugin, its Lua bridge, and Andyalpa's original Lua (reference). |
| [`modding-notes/`](../modding-notes/) | Readable field notes and measurements, newest first. |
| [`engine-research/`](../engine-research/) | Engine facts for the modding side (so far only its `inbox/`). |
| [`ideas/`](../ideas/) | Mod ideas waiting to be picked. |
| **`external-research/`** ← you are here | Ongoing public-research leads: read-only input to the other folders, never the other way around. |

## How this folder is used

- A **research session** reads the other folders for context (to know what has already been tried) and writes only here.
- A **modding session** reads this folder when it wants new leads, and folds anything useful into its own notes and code, attributed back to the topic file here. Its verdicts on a lead come back as a file in [`inbox/`](inbox/).
- [INDEX.md](INDEX.md) is the front door: every topic, with a status tag, newest first.
- `topics/` holds one self-contained file per lead, not chronological session logs.

## Credits

See [CREDITS.md](CREDITS.md): every source, tool and prior work this research builds on, credited by name, plus a standing notice on respecting creators' wishes.

## Contributing & policy

See [CONTRIBUTING.md](CONTRIBUTING.md): how we credit and link sources, our **study-everything-public but write-our-own-code** rule (we copy no one else's source code or files, any licence or price), the terms for reusing our work (free, with credit), and how to request a correction or removal.
