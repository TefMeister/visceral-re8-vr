// bodyturn.h -- rebuild 2 (2026-11-26, design item 15): the body no longer turns as one chunk with the head.
//
// Tefa (2026-11-26, the bare base): "when walking the body is 'glued' to the headset and turns exactly as i look
// left or right ... i should be able to walk and look around without the body turning at all, then at an angle
// start turning a little towards the headset, a lot maybe when looking sideways more than 60 degrees maybe, but
// the thing is, walking forward must follow hmd direction not where the body is facing". And of b178's version:
// "Ethan walked in the direction of where the body was facing, not where i was actually looking".
//
// THE LEVER (b178's visceral_re8_bodyturn.lua, measured live 2026-11-10 on the simulator): the game asks
// app.PlayerMovement.destinationAngle() "which way should the body face?" and the loader has made the camera the
// head, so the answer is the head. This part replaces the answer with a direction it keeps itself: the body's.
// No camera, no view offset and no joint is touched; the game turns the body itself, legs and all.
//
// THE WALK (new in rebuild 2, from Tefa's words above): the game walks along the BODY. So the left stick is turned
// by (head - body) before the base script hands it to the game (one dated line at its set_AxisL): stick forward
// then walks where the head looks whatever the body faces. This part works the angle out and puts it in the
// bridge array (S_MOVE_TURN); the script only applies it.
//
// The body's direction: starts at the head's; any turn of the view the headset did not make (the stick, a
// re-centre) is carried over whole; within DEAD_DEG of the head it stays; past it the body turns all the way to
// the head with a small lag (Tefa, 2026-11-26, after wearing a wide free zone and then none; the numbers are in
// bodyturn.cpp, and the data folder's bodyturn.txt overrides the lag and the dead zone in play).
//
// The first game function this frame hooks. Switches in off.txt: bodyturn (the whole part, no hook is placed),
// bodyturn-walk (the stick is left as it is), bodyturn-walk-flip (the stick is turned the other way round).
#pragma once

namespace vr8::bodyturn {

void frame();
float head_off();   // radians, head - body, in the yaw measure of the bridge; 0 while this part stands down
//     // UpdateBehavior pre, after the bridge and the player are refreshed

} // namespace vr8::bodyturn
