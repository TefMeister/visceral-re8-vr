// whichpart.cpp -- see whichpart.h.
#include "whichpart.h"

#include "rack.h"
#include "reload.h"
#include "settings.h"

namespace vn::whichpart {
using namespace vn::settings;

const char* name(Part p) { return p == MAG ? "magazine" : p == RACK ? rack::part_name() : p == GRIP ? "front grip" : "nothing"; }

Part nearest() {
    Part best = NONE;
    float best_n = 1.0f;   // inside a zone = distance / reach <= 1
    float d = 0.0f, r = 0.0f;
    if (reload::mag_reach(d, r) && r > 0.0f && d <= r) { best = MAG; best_n = d / r; }
    if (rack::part_reach(d, r) && r > 0.0f && d <= r) {
        const float n = (d / r) * (rack::due_now() ? WHICHPART_DUE_BIAS : 1.0f);
        if (best == NONE || n < best_n) { best = RACK; best_n = n; }
    }
    if (rack::long_gun() && rack::grip_reach(d, r) && r > 0.0f && d <= r) {
        const float n = d / r;
        if (best == NONE || n < best_n) { best = GRIP; best_n = n; }
    }
    return best;
}
}  // namespace vn::whichpart
