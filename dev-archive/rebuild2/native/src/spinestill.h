// spinestill.h -- rebuild 2 (2026-11-26): the stomach no longer turns with the head.
//
// Tefa (2026-11-26, with the body turn's dead zone in): "looking left and right seems to move the stomach area
// only, Ethan's coat and clothing only at the stomach level seem to move with turning my head left or right";
// asked which way: "stomach moves the same way as my head".
//
// Measured (the recorder's twist lines, 2026-11-26 14:08, n=1 run, 45 lines, the head between -15 and +19 degrees
// off the body): the joint Spine_0 turns about the up axis by half the head's angle off the body (-15 -> -9 from a
// rest of about -1.5; +19 -> +8) and Spine_1 turns the same amount the other way (13 and -4 from a rest of about
// 5.5); Spine_2, the neck joints and the hip do not change. So the game (or the loader's body solver) turns the
// lower spine toward the view and takes it out again one joint up: unseen while the body was one chunk with the
// head (the angle was always 0), seen now that the head may look off the body.
//
// What it does: every frame, both joints' local rotations are read as the motion left them and asked of the joint
// writer with that half angle turned back (Spine_0) and put back (Spine_1). Nothing is held: the motion's own
// spine pose passes through. It stands down for a cutscene and when the body turn is not running.
//
// It writes no joint itself (rule 3) and makes nothing (rule 4). Its switch in off.txt: spinestill.
#pragma once

namespace vr8::spinestill {

void pose();      // post-PrepareRendering, before the joint writer's flush

} // namespace vr8::spinestill
