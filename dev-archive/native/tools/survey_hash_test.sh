#!/usr/bin/env bash
# The gun survey's sound-name hash (the shipped Lua, cut out between its HASH markers) against the 39 names and ids the game
# itself reported on 2026-10-24. Needs a stand-alone Lua 5.4 (lua on PATH).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"
HW="$(cygpath -m "$HERE" 2>/dev/null || echo "$HERE")"   # a Windows Lua needs C:/ paths
sed -n "/^-- ==== HASH/,/^-- ==== END HASH/p" "$HERE/../lua/visceral_re8_gun_survey.lua" | tr -d "\r" > "$T/hash.lua"
cat >> "$T/hash.lua" <<EOF
local known = dofile([[$HW/survey_hash_known.lua]])
local ok, bad = 0, 0
for _, p in ipairs(known) do if murmur3_utf16(p[1]) == p[2] then ok = ok + 1 else bad = bad + 1; print("MISMATCH", p[1], p[2], murmur3_utf16(p[1])) end end
print(string.format("hash: %d of %d known names match", ok, ok + bad))
os.exit(bad == 0 and 0 or 1)
EOF
lua "$T/hash.lua"
