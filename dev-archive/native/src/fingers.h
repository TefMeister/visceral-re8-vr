// fingers.h -- the left hand opens a little where the left grip would take hold (Tefa 2026-10-24: "the left hand opens a
// little when getting to an activation area, like the slide racking, bolt racking, ammo pouch indicating that pressing LG
// will dock the hand or grab something ... for slide/pump handle/racking bolt and also when close to grip or the front part
// of the shotgun and rifle").
// The areas are the ones the code already uses: the slide / pump / bolt grab zone and the line along the gun (rack.cpp),
// and the ammo pouch (reload.cpp). In one, with the left grip not yet pressed and nothing in the hand, every left finger
// joint is eased part of the way from the animated pose toward the skeleton's rest pose (via.Joint BaseLocalRotation: the
// fingers straight), FINGER_OPEN_AMOUNT of the way, over FINGER_OPEN_SEC; out of it, back.
#pragma once

namespace vn::fingers {

void frame();          // UpdateBehavior pre: in an area or not, the eased amount
void render_point();   // PrepareRendering post: read the animated fingers once, write the opened ones
void begin_render();   // BeginRendering pre: write them again (the engine re-poses joints between the two)

} // namespace vn::fingers
