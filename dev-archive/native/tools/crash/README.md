# Crash reading tools (2026-11-25)

Read a REFramework crash dump and the game's code without the game running.

- `crash_read.py <dump> [-a] [-m]`: the crash thread's stack with every address named by module (`-a` also the plain
  values of the first 0x200 bytes, `-m` the module list). Needs `pip install minidump`.
- `pedis.py <exe> func <rva-hex>`: the whole function that holds an address, read from the exe on disk
  (`pedis.py <exe> <rva-hex> [bytes-hex]` for a plain range). Needs `pip install capstone`.
- `strscan.py <exe> <text>...`: every plain-text or wide string in the exe that holds the text.

Never commit a dump (it holds this PC's paths) or the game's exe. Used for
`modding-notes/2026-11-25c-the-crash-at-4151c23-read-from-the-dumps.md`.
