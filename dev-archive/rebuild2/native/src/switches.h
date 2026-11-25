// switches.h -- rebuild 2, RULE 10: every part has its switch in off.txt, so a fault is halved in two launches.
// reframework/data/visceral_re8/off.txt: part names, one per line or space-separated; "#" starts a comment word.
// Read once, at the first question. No file = everything on. Never shipped with a file in place.
#pragma once

namespace vr8::switches {

bool off(const char* part);

} // namespace vr8::switches
