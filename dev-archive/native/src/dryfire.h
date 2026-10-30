// dryfire.h -- the empty click (2026-10-30, Tefa: "add an empty click sound to every RT press if gun is empty or needs racking
// before the shot ... a quick short click, so that on repeated presses the sound doesn't cut out anywhere").
// Every fresh RT press while the gun in hand will not fire plays sfx/dry_click.wav (40 ms, made by tools/make_dry_click.py):
// the gun is empty, its magazine is out, a rack / pump / bolt is due, or a revolver / GM 79 is open. Only our hand-reloaded
// guns, only while the hands are free (no menu, no cutscene). The click is kept in memory, so each press plays it at once.
#pragma once

namespace vn::dryfire {
void frame();   // once a frame, after reload::frame and rack::frame
} // namespace vn::dryfire
