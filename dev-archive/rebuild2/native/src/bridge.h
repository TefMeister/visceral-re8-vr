// bridge.h -- rebuild 2 (design item 3): what the plugin cannot read itself comes in from Lua, nothing else.
//
// REFramework's plugin API gives C++ no VR state and none of praydog's `re8vr` flags (they live in his Lua-facing
// object). lua/visceral_re8_bridge.lua keeps ONE managed float array and writes the slots below at UpdateHID.
//
// How the plugin finds the array (new in rebuild 2: no hook, no "mailbox" method): the script writes the array's
// address and a random sentinel to reframework/data/visceral_re8/bridge.txt; the plugin reads the file, checks
// that the address is a live System.Single[] whose sentinel slot holds the same number, and only then reads from
// it. A file left by an earlier run fails that check. If the frame counter stops (the scripts were reset) the
// plugin lets go and reads the file again.
#pragma once

namespace vr8::bridge {

enum Slot : int {
    S_FRAME = 0,           // +1 every UpdateHID
    S_SENTINEL = 1,        // the random number also written to bridge.txt
    S_ACTIVE = 2,          // 1 = headset active AND controllers in use
    S_CUTSCENE = 3,        // re8vr.is_in_cutscene
    S_CAN_USE_HANDS = 4,   // re8vr.can_use_hands
    S_GAME_ARMS = 5,       // WRITTEN BY THE PLUGIN (gamearms.h): 1 = the game's own arms are showing (Rose carried)
    S_WEAPON = 6,          // 1 = re8vr.weapon is something (a gun or the knife in the right hand)
    S_TURN_OK = 7,         // 1 = in play, headset active, no cutscene: the yaws below are meant (bodyturn.h)
    S_TURN_STAMP = 8,      // +1 each time the script's camera step wrote the two yaws
    S_HEAD_YAW = 9,        // the head's flat yaw, radians, as the loader wrote it to the camera controller
    S_BASE_YAW = 10,       // the same with the headset's own turn taken out (changes only by the stick)
    S_MOVE_TURN = 11,      // WRITTEN BY THE PLUGIN: turn the left stick by this, radians (head - body); 0 = leave it
    S_LEFT_ASLEEP = 12,    // 1 = the left controller reports the position 0 0 0 (asleep): sleephands.h
    S_RIGHT_ASLEEP = 13,   // the same for the right controller
    S_STICK_X = 14,        // the left stick as the script handed it to the game (turned, or a room step's push)
    S_STICK_Y = 15,
    S_STEP_ON = 16,        // 1 = a room step is pushing the stick
    S_HMD_AT = 17,         // 17..19 the headset's place, 20..23 its turn (x y z w), as the loader reports them
    S_HMD_TURN = 20,
    S_LEFT_AT = 24,        // 24..26 the left controller's place, the same space
    S_RIGHT_AT = 27,       // 27..29 the right one's
    S_LEAN = 30,           // WRITTEN BY THE PLUGIN (leanfix.h): metres the body should sit further back
    S_LEAN_APPLIED = 31,   // what the script's body placing really used this frame (0 = nothing)
    S_SCRIPTBODY_OFF = 32, // 1 = the script half of the body is switched off (scriptbody-off.json)
    S_COUNT = 40,          // the array's length
};

void frame();                 // once per frame, game thread (UpdateBehavior pre): attach / let go
bool live();                  // attached and the frame counter moved within the last STALE_FRAMES frames
float read(Slot slot);        // 0 when not live
inline float read_at(Slot first, int n) { return read((Slot)((int)first + n)); }
void write(Slot slot, float value);   // only the slots marked WRITTEN BY THE PLUGIN; nothing when not live
inline bool flag(Slot slot) { return read(slot) > 0.5f; }

} // namespace vr8::bridge
