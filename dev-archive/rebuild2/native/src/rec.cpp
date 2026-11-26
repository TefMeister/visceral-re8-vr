// rec.cpp -- see rec.h
#define _CRT_SECURE_NO_WARNINGS   // the two recorder headers and the walk file use plain C file calls
#include "rec.h"

#include "base.h"
#include "bridge.h"
#include "jointwriter.h"
#include "leanfix.h"
#include "paths.h"
#include "ready.h"
#include "switches.h"

#define JITTERLOG_IMPLEMENTATION
#include "begone/jitterlog.h"
#define GHOSTHAND_IMPLEMENTATION
#include "begone/ghosthand.h"

#include <cstdio>
#include <cstring>
#include <ctime>

namespace vr8::rec {

namespace {
// ---- the named numbers ------------------------------------------------------------------------------------------
constexpr const char* GAME = "visceral-re8-vr";
constexpr const char* RUNTIME = "openxr";          // headset or simulator is not told apart here (b178 said the same)
constexpr int WALK_MAX_LINES = 90 * 60 * 15;       // a quarter hour at 90 pictures a second, then the file is full
constexpr int WALK_FLUSH_LINES = 90;
constexpr float RAD2DEG = 57.2957795f;
constexpr float OFF_AFTER_S = 3.0f;
constexpr int MOTION_LAYERS = 2;                   // the first two layers of the player's motion are written

enum Joint : int { HIP, L_FOOT, R_FOOT, L_KNEE, R_KNEE, L_HAND, R_HAND, NECK, JOINTS };
const wchar_t* const JOINT_NAMES[JOINTS] = {L"Hip", L"L_Foot", L"R_Foot", L"L_Shin", L"R_Shin", L"L_Hand", L"R_Hand", L"Neck_0"};
const char* const JOINT_SAY[JOINTS] = {"hip", "L_foot", "R_foot", "L_knee", "R_knee", "L_hand", "R_hand", "neck"};

bool g_on = false;
bool g_inited = false;
unsigned g_generation = 0;
MO* g_joint[JOINTS]{};
MO* g_motion = nullptr;
bool g_looked = false;
FILE* g_walk = nullptr;
int g_walk_lines = 0;
float g_walk_t0 = 0.0f;

Call& joint_position() { static Call c("via.Joint", "get_Position", 0); return c; }
Call& transform_position() { static Call c("via.Transform", "get_Position", 0); return c; }
Call& transform_rotation() { static Call c("via.Transform", "get_Rotation", 0); return c; }

Vec3 slot_vec(bridge::Slot first) { return {bridge::read_at(first, 0), bridge::read_at(first, 1), bridge::read_at(first, 2)}; }

void open_walk() {
    std::wstring folder = paths::data(L"walkrec");
    CreateDirectoryW(folder.c_str(), nullptr);
    const std::time_t now = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &now);
    wchar_t name[64]{};
    swprintf(name, 64, L"\\walk-%04d%02d%02d-%02d%02d%02d.csv", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour,
             tm.tm_min, tm.tm_sec);
    g_walk = _wfopen((folder + name).c_str(), L"w");
    g_walk_lines = 0;
    g_walk_t0 = now_s();
    if (g_walk == nullptr) { LOGW("%s recorders: the walk file could not be made", TAG); return; }
    std::fprintf(g_walk, "# visceral-re8 walkrec 1 off=[%s] scriptbody_off=%d\n", switches::all(),
                 bridge::flag(bridge::S_SCRIPTBODY_OFF) ? 1 : 0);
    std::fprintf(g_walk, "t_ms,dt_ms,flags,speed,head_off_deg,stick_x,stick_y,px,pz,pyaw_deg");
    for (int layer = 0; layer < MOTION_LAYERS; ++layer)
        std::fprintf(g_walk, ",m%d_bank,m%d_id,m%d_frame,m%d_frame_d,m%d_end", layer, layer, layer, layer, layer);
    for (int j = HIP; j <= R_KNEE; ++j) std::fprintf(g_walk, ",%s_x,%s_y,%s_z", JOINT_SAY[j], JOINT_SAY[j], JOINT_SAY[j]);
    std::fprintf(g_walk, ",gL_x,gL_y,gL_z,gR_x,gR_y,gR_z,cL_x,cL_y,cL_z,cR_x,cR_y,cR_z");
    std::fprintf(g_walk, ",neck_behind,lean_raw,lean_standing,lean_ask,lean_applied,down\n");
}

void turn_on() {
    if (!g_inited) {
        g_inited = true;
        jl_init(GAME, RUNTIME);
        gh_init(GAME, RUNTIME);
    }
    jl_vr_on();
    gh_vr_on();
    char mark[200]{};
    std::snprintf(mark, sizeof mark, "rebuild2 off=[%s] scriptbody_off=%d", switches::all(),
                  bridge::flag(bridge::S_SCRIPTBODY_OFF) ? 1 : 0);
    jl_mark(mark);
    open_walk();
    g_on = true;
    LOGI("%s recorders: on (the jitter recorder, Ghost Hand, the walk file)", TAG);
}

void turn_off() {
    if (!g_on) return;
    g_on = false;
    jl_vr_off();
    gh_vr_off();
    if (g_walk != nullptr) { std::fclose(g_walk); g_walk = nullptr; }
    LOGI("%s recorders: off (%d walk lines)", TAG, g_walk_lines);
}

void find(const ready::Snapshot& player) {
    if (g_looked) return;
    g_looked = true;
    std::string missing;
    for (int j = 0; j < JOINTS; ++j) {
        g_joint[j] = jointwriter::joint_by_name(player.transform, JOINT_NAMES[j]);
        if (g_joint[j] == nullptr) missing += std::string(" ") + JOINT_SAY[j];
    }
    g_motion = component(player.player, "via.motion.Motion");
    LOGI("%s recorders: joints%s; the player's motion %s", TAG, missing.empty() ? " all found" : (" MISSING:" + missing).c_str(),
         g_motion != nullptr ? "found" : "NOT found");
}

struct Layer { unsigned bank = 0, id = 0; float frame = -1.0f, end = -1.0f; double frame_d = -1.0; };

Layer read_layer(unsigned index) {
    static Call get_layer("via.motion.Motion", "getLayer", 1);
    static Call bank("via.motion.TreeLayer", "get_MotionBankID", 0);
    static Call id("via.motion.TreeLayer", "get_MotionID", 0);
    static Call frame("via.motion.TreeLayer", "get_Frame", 0);
    static Call end("via.motion.TreeLayer", "get_EndFrame", 0);
    Layer out;
    static Call layer_count("via.motion.Motion", "getLayerCount", 0);
    if (g_motion == nullptr || !is_managed(g_motion)) return out;
    unsigned count = 0;
    if (!layer_count.value(g_motion, &count, sizeof count) || index >= count) return out;   // never ask past the end
    MO* layer = get_layer.ptr(g_motion, {(void*)(uintptr_t)index});
    if (layer == nullptr) return out;
    bank.value(layer, &out.bank, sizeof out.bank);
    id.value(layer, &out.id, sizeof out.id);
    // a float comes back in the first four bytes on some builds of the loader and as a double on others: both are
    // written, the reader takes the one that reads as a frame number
    unsigned char bytes[8]{};
    if (frame.value(layer, bytes, sizeof bytes)) {
        std::memcpy(&out.frame, bytes, sizeof out.frame);
        std::memcpy(&out.frame_d, bytes, sizeof out.frame_d);
    }
    end.value(layer, &out.end, sizeof out.end);
    return out;
}

float sane(double v) { return std::isfinite(v) && std::fabs(v) < 1.0e6 ? (float)v : -1.0f; }
} // namespace

void shutdown() { turn_off(); }

void pose() {
    const auto& player = ready::now();
    const bool want = bridge::live() && bridge::flag(bridge::S_ACTIVE) && player.transform != nullptr;
    // a controller put down for a moment must not cut the files in pieces: off only after OFF_AFTER_S without
    static float wanted_at = -1000.0f;
    if (want) wanted_at = now_s();
    if (!want) {
        if (now_s() - wanted_at > OFF_AFTER_S) turn_off();
        return;
    }
    if (player.generation != g_generation) {
        g_generation = player.generation;
        g_looked = false;
    }
    find(player);
    if (!g_on) turn_on();

    const auto& pace = ready::pace();
    MO* camera = ready::camera_transform();
    Vec3 eye{};
    Quat view{0, 0, 0, 1};
    const bool have_camera = camera != nullptr && transform_position().value(camera, &eye, sizeof eye) &&
                             transform_rotation().value(camera, &view, sizeof view);
    Vec3 at[JOINTS]{};
    bool have[JOINTS]{};
    for (int j = 0; j < JOINTS; ++j)
        have[j] = g_joint[j] != nullptr && joint_position().value(g_joint[j], &at[j], sizeof at[j]);

    // the headset and the controllers, the loader's own space
    const Vec3 hmd = slot_vec(bridge::S_HMD_AT);
    const Quat hmd_turn{bridge::read_at(bridge::S_HMD_TURN, 0), bridge::read_at(bridge::S_HMD_TURN, 1),
                        bridge::read_at(bridge::S_HMD_TURN, 2), bridge::read_at(bridge::S_HMD_TURN, 3)};
    const bool hmd_ok = std::fabs(hmd_turn.x * hmd_turn.x + hmd_turn.y * hmd_turn.y + hmd_turn.z * hmd_turn.z +
                                  hmd_turn.w * hmd_turn.w - 1.0f) < 0.05f;
    const Vec3 hand_room[2] = {slot_vec(bridge::S_LEFT_AT), slot_vec(bridge::S_RIGHT_AT)};
    const bool tracked[2] = {!bridge::flag(bridge::S_LEFT_ASLEEP), !bridge::flag(bridge::S_RIGHT_ASLEEP)};
    // everything in the head's own space: the controllers through the headset, the game's things through the camera
    Vec3 real[2]{}, game[JOINTS]{};
    for (int s = 0; s < 2; ++s) if (hmd_ok) real[s] = rotate(conjugate(hmd_turn), hand_room[s] - hmd);
    for (int j = 0; j < JOINTS; ++j) if (have[j] && have_camera) game[j] = rotate(conjugate(view), at[j] - eye);
    // and the legs in the player's own space (its spot, its facing)
    Vec3 own[JOINTS]{};
    for (int j = 0; j < JOINTS; ++j) if (have[j] && pace.ok) own[j] = rotate(conjugate(pace.turn), at[j] - pace.at);

    const float head_off_deg = bridge::read(bridge::S_MOVE_TURN) * RAD2DEG;
    const auto& lean = leanfix::last();

    // ---- Camera Jitter BeG0nE ----
    if (hmd_ok) jl_pose_q(hmd_turn.x, hmd_turn.y, hmd_turn.z, hmd_turn.w, hmd.x, hmd.y, hmd.z);
    if (have_camera) jl_camera_q(view.x, view.y, view.z, view.w, eye.x, eye.y, eye.z);
    jl_hand_ypr('L', tracked[0] ? 1 : 0, 0.0f, 0.0f, 0.0f, hand_room[0].x, hand_room[0].y, hand_room[0].z);
    jl_hand_ypr('R', tracked[1] ? 1 : 0, 0.0f, 0.0f, 0.0f, hand_room[1].x, hand_room[1].y, hand_room[1].z);
    jl_present();

    // ---- Ghost Hand BeG0nE ----
    if (hmd_ok && have_camera) {
        gh_real('L', tracked[0] ? 1 : 0, real[0].x, real[0].y, real[0].z);
        gh_real('R', tracked[1] ? 1 : 0, real[1].x, real[1].y, real[1].z);
        if (have[L_HAND]) gh_game('L', game[L_HAND].x, game[L_HAND].y, game[L_HAND].z);
        if (have[R_HAND]) gh_game('R', game[R_HAND].x, game[R_HAND].y, game[R_HAND].z);
        for (int j = HIP; j <= R_KNEE; ++j) if (have[j]) gh_part(JOINT_SAY[j], game[j].x, game[j].y, game[j].z);
        gh_value("speed", pace.speed_mps);
        gh_value("head_off_deg", head_off_deg);
        if (lean.ok) gh_value("neck_behind", lean.behind_m);
        gh_frame();
    }

    // ---- the walk file ----
    if (g_walk == nullptr || g_walk_lines >= WALK_MAX_LINES) return;
    const int flags = (bridge::flag(bridge::S_CUTSCENE) ? 1 : 0) | (bridge::flag(bridge::S_CAN_USE_HANDS) ? 2 : 0) |
                      (bridge::flag(bridge::S_WEAPON) ? 4 : 0) | (bridge::flag(bridge::S_TURN_OK) ? 8 : 0) |
                      (bridge::flag(bridge::S_STEP_ON) ? 16 : 0) | (tracked[0] ? 0 : 32) | (tracked[1] ? 0 : 64) |
                      (bridge::flag(bridge::S_GAME_ARMS) ? 128 : 0);
    const Vec3 facing = rotate(pace.turn, {0.0f, 0.0f, 1.0f});
    std::fprintf(g_walk, "%.1f,%.2f,%d,%.3f,%.1f,%.3f,%.3f,%.3f,%.3f,%.1f", (now_s() - g_walk_t0) * 1000.0f,
                 pace.dt * 1000.0f, flags, pace.speed_mps, head_off_deg, bridge::read(bridge::S_STICK_X),
                 bridge::read(bridge::S_STICK_Y), pace.at.x, pace.at.z, std::atan2(facing.x, facing.z) * RAD2DEG);
    for (unsigned layer = 0; layer < MOTION_LAYERS; ++layer) {
        const Layer m = read_layer(layer);
        std::fprintf(g_walk, ",%u,%u,%.2f,%.2f,%.1f", m.bank, m.id, sane(m.frame), sane(m.frame_d), sane(m.end));
    }
    for (int j = HIP; j <= R_KNEE; ++j) std::fprintf(g_walk, ",%.4f,%.4f,%.4f", own[j].x, own[j].y, own[j].z);
    std::fprintf(g_walk, ",%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", game[L_HAND].x, game[L_HAND].y,
                 game[L_HAND].z, game[R_HAND].x, game[R_HAND].y, game[R_HAND].z, real[0].x, real[0].y, real[0].z,
                 real[1].x, real[1].y, real[1].z);
    std::fprintf(g_walk, ",%.4f,%.4f,%.4f,%.4f,%.4f,%.2f\n", lean.behind_m, lean.raw_m, lean.standing_m, lean.ask_m,
                 lean.applied_m, lean.down);
    if (++g_walk_lines % WALK_FLUSH_LINES == 0) std::fflush(g_walk);
}

} // namespace vr8::rec
