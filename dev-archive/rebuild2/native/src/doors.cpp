// doors.cpp -- see doors.h
#include "doors.h"

#include "base.h"
#include "bridge.h"
#include "gamearms.h"
#include "gate.h"
#include "jointwriter.h"
#include "paths.h"
#include "ready.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <set>
#include <string>

namespace vr8::doors {

namespace {
// ---- the named numbers -----------------------------------------------------------------------------------------
constexpr float DEG = 3.14159265f / 180.0f;
// app.DoorBehavior.get_doorState: the hash of the state's name (app.DoorStateNames, read from the exe 2026-11-26;
// eight of them match the running game of 2026-11-19). b178 had "LittleOpen" as 3407536511: no such state; the
// real one is LittleOpening.
constexpr uint32_t ST_CLOSED = 474011919u, ST_LOCKED = 3401490761u, ST_LITTLE_OPENING = 2329368004u,
                   ST_LITTLE_OPENED = 171654102u, ST_OPENING = 887278378u, ST_OPENED = 3232296810u,
                   ST_PUSH = 396010129u, ST_CLOSING = 3360157036u, ST_CURVE = 4118602539u;
// the door's own sound kinds used here (doorsounds.h has all ten)
constexpr uint32_t SE_CREAK_SLOW = 1884312664u, SE_CREAK_STOP = 3741696246u;
constexpr float CLOSE_S = 1.2f;            // our leaf swings shut over this long once the game starts closing the door
                                           // (the game's own close sounds are 1.0 to 1.6 s apart, log of 2026-11-26)
constexpr float CREAK_STOP_S = 0.25f;      // the leaf has not moved for this long: the creak ends
constexpr float MOVED_DEG = 0.05f;         // a push of less than this in a frame is not movement
constexpr int MAX_LEAVES = 6;              // leaves looked after at once (a gate has two; a kept one holds its place)
constexpr int MAX_SOLID = 8;               // solid parts of one leaf (the leaf, padlocks hanging on it)
constexpr int MAX_CHILDREN = 40;
constexpr float SCAN_S = 0.5f;             // how often the near leaves are looked for
constexpr float SCAN_M = 3.0f;             // how near, across the floor
constexpr float SCAN_UP_M = 1.5f;          // and up or down (another floor is not near)
constexpr float RELEASE_M = 10.0f;         // a leaf of ours this far away is let go whatever its state
constexpr float HAND_CM = 10.0f;           // the hand's reach around the wrist (doors.txt, 1st number)
constexpr float BODY_CM = 32.0f;           // the body's, around the player's spot (doors.txt, 2nd number)
constexpr float LEAF_M = 1.0f;             // a leaf's width when the door does not tell [hypothesis]
constexpr float LEAF_MIN_M = 0.3f, LEAF_MAX_M = 3.0f;
constexpr float HINGE_GAP_M = 0.10f;       // nearer the hinge than this is the frame, not the leaf
constexpr float TOUCH_COOLDOWN_S = 1.5f;   // one ask per touch, not one per frame
constexpr float INTERACT_PICK_M = 1.6f;    // an InteractDoor part this near the hinge belongs to that leaf
constexpr float INITIAL_DEG = 1.0f;        // how far the leaf stands open when the game opens it (Tefa, b142: 1)
constexpr float MAX_DEG = 92.0f;
constexpr float SHUT_HOLD_S = 0.3f;        // the state Closed this long: the game has shut it
constexpr float FILE_EVERY_S = 2.0f;
constexpr int MAX_LINES = 2000;
constexpr float ASK_WAIT_S = 0.35f;        // the game was asked to open a shut door and it is still shut after this
                                           // long: the hand takes the leaf itself
// DIFFERENT DOORS (Tefa, 2026-11-26 17:5x, after three builds that tried to make the hand open them): "the doors
// that are different, not meant to be opened by hand, let them open the game's way, automatically from the
// distance, maybe we can just tweak the distance to be much less so basically i can still roleplay putting my
// hand near the door, but it just opens with proximity to me, there are a few of these doors in the game. and
// just normal doors, they can just open normally by hand."
// A door is different when it is found standing a crack open, when it swings by itself (scripted), or when the
// game was asked to open it and did nothing. For those the game's own walk-in open is let through, for that
// door only, while a hand is within NEAR_HAND_CM of the leaf or the body within NEAR_BODY_CM; the leaf stays
// the game's. doors.txt, 3rd and 4th number.
constexpr float NEAR_HAND_CM = 25.0f;
constexpr float NEAR_BODY_CM = 60.0f;
constexpr float PARTS_EVERY_S = 1.0f;
constexpr int ALLOWED = 4;                 // InteractDoor parts whose walk-in open is let through at once
constexpr int PUSHERS = 3;                 // left hand, right hand, the body

struct Leaf {
    MO* door = nullptr;        // app.DoorBehavior
    MO* transform = nullptr;   // its object's transform: the shut leaf's frame
    MO* hinge = nullptr;       // the joint "_00"
    float side = 0.0f;         // +1 / -1: the leaf lies along the frame's +X / -X; 0 = the door did not tell
    float width = LEAF_M;
    bool seen_shut = false;    // only a door seen shut is ever taken (one left open earlier stays as it is)
    bool games_own = false;    // opened while Rose was carried: the game's, until it is shut again
    bool ours = false;         // open and drawn by us
    float sign = 1.0f;         // which way the joint turns to open (from the game's DestAngle)
    float rest_deg = 0.0f;     // the joint's own yaw while shut
    float drawn_deg = 0.0f;
    float shut_since = -1.0f;
    bool put_back = false;     // pose(): write the rest angle once (the game has shut it)
    float prev[PUSHERS]{};     // per pusher: its distance to the shut leaf (shut) or its angle (open) last frame
    bool prev_ok[PUSHERS]{};
    float closing_from = -1.0f; // the game is closing it: the angle ours had when that began (-1 = not closing)
    float closing_at = 0.0f;
    bool creaking = false;     // we started the hinge creak and have not ended it
    float asked_at = -1.0f;    // when the game was asked to open it (-1 = no ask waiting for its answer)
    float ask_sign = 1.0f;     // which way the leaf would turn away from the hand that asked
    bool different = false;    // not a door for the hand: it opens the game's way, by nearness (see DIFFERENT DOORS)
    bool near_told = false;
    MO* parts[2]{};            // its app.InteractDoor parts (the walk-in open is theirs); looked up while it is near
    float parts_at = -10.0f;
    float moved_at = -1.0f;
    MO* solid[MAX_SOLID]{};    // the parts we switched off (each held by one add_ref, rule 7)
    int solid_n = 0;
};
Leaf g_leaf[MAX_LEAVES];
unsigned g_generation = 0;
MO* g_hand[2]{};
float g_scan_at = -SCAN_S, g_touch_at = -TOUCH_COOLDOWN_S, g_file_at = -FILE_EVERY_S;
float g_hand_m = HAND_CM * 0.01f, g_body_m = BODY_CM * 0.01f;
int g_lines = 0;
bool g_hook_tried = false;
std::atomic<bool> g_walk_in{true};         // read by the hook: true = the game's own walk-in open stands
std::atomic<unsigned> g_walk_skipped{0};

std::set<MO*> g_named;                     // doors whose name line was logged this run
std::set<MO*> g_refused;                   // shut doors the game was asked to open and did not: different from then on
std::atomic<void*> g_allowed[ALLOWED];     // read by the hook: these InteractDoor parts may open by walking in
MO* g_allow_next[ALLOWED]{};               // main thread: this frame's list, published at the end of frame()
int g_allow_n = 0;
float g_near_hand_m = NEAR_HAND_CM * 0.01f, g_near_body_m = NEAR_BODY_CM * 0.01f;
unsigned g_walk_told = 0;

void say(const char* fmt, float a = 0, float b = 0, float c = 0) {
    if (g_lines++ >= MAX_LINES) return;
    char line[240];
    std::snprintf(line, sizeof line, fmt, a, b, c);
    LOGI("%s doors: %s", TAG, line);
}

// ---- the game, read ---------------------------------------------------------------------------------------------
Call& joint_position() { static Call c("via.Joint", "get_Position", 0); return c; }
Call& transform_position() { static Call c("via.Transform", "get_Position", 0); return c; }
Call& transform_rotation() { static Call c("via.Transform", "get_Rotation", 0); return c; }
Call& transform_child() { static Call c("via.Transform", "get_Child", 0); return c; }
Call& transform_next() { static Call c("via.Transform", "get_Next", 0); return c; }
Call& transform_object() { static Call c("via.Transform", "get_GameObject", 0); return c; }
Call& object_transform() { static Call c("via.GameObject", "get_Transform", 0); return c; }
Call& object_name() { static Call c("via.GameObject", "get_Name", 0); return c; }
Call& transform_parent() { static Call c("via.Transform", "get_Parent", 0); return c; }

bool finite(Vec3 v) { return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z); }
float level(Vec3 a, Vec3 b) { return std::sqrt((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)); }

MO* transform_of(MO* component) { return object_transform().ptr(dyn_ptr(component, "get_GameObject")); }

MO* components(const char* type) {
    static Call current("via.SceneManager", "get_CurrentScene", 0);
    static Call find("via.Scene", "findComponents(System.Type)", 1);
    auto* scene = current.ptr(API::get()->get_native_singleton("via.SceneManager"));
    auto* rt = API::get()->typeof(type);
    return scene != nullptr && rt != nullptr ? find.ptr(scene, {rt}) : nullptr;
}
int count_of(MO* list) {
    int n = 0;
    return dyn_value(list, "get_Count", &n, sizeof n) ? std::clamp(n, 0, 4096) : 0;
}
MO* item_of(MO* list, int i) { return dyn_ptr(list, "get_Item", {(void*)(intptr_t)i}); }

uint32_t state_of(MO* door) {
    uint32_t st = 0;
    return dyn_value(door, "get_doorState", &st, sizeof st) ? st : 0u;
}
bool is_shut(uint32_t st) { return st == ST_CLOSED || st == ST_LOCKED; }
bool is_open(uint32_t st) {
    return st == ST_LITTLE_OPENING || st == ST_LITTLE_OPENED || st == ST_OPENING || st == ST_OPENED || st == ST_PUSH;
}
bool is_locked(MO* door) {
    bool locked = false;
    return dyn_value(door, "IsLocked", &locked, sizeof locked) && locked;
}

float local_yaw_deg(MO* joint) {
    Quat q{};
    return jointwriter::read_local_rotation(joint, q) ? 2.0f * std::atan2(q.y, q.w) / DEG : 0.0f;
}

// a world point in the shut leaf's frame (hinge at 0, the leaf along +X or -X, the door's face across Z)
bool to_leaf_frame(const Leaf& d, Vec3 p, Vec3& out) {
    Vec3 hinge{};
    Quat rotation{};
    if (!joint_position().value(d.hinge, &hinge, sizeof hinge) ||
        !transform_rotation().value(d.transform, &rotation, sizeof rotation) || !finite(hinge)) return false;
    out = rotate(conjugate(rotation), p - hinge);
    return finite(out);
}

// the point's angle around the hinge from the shut leaf, in the opening direction (degrees), and how far out it
// is (carried over from b178: the leaf at local yaw t lies along (s cos t, 0, -s sin t))
void angle_of(const Leaf& d, Vec3 local, float& deg, float& radius) {
    const float s = d.side != 0.0f ? d.side : 1.0f;
    radius = std::sqrt(local.x * local.x + local.z * local.z);
    deg = std::atan2(-local.z * s, local.x * s) / DEG * d.sign;
}

// ---- the leaf's solid parts (through the request gate) ----------------------------------------------------------
void solid_on(Leaf& d) {
    for (int i = 0; i < d.solid_n; ++i) {
        if (is_managed(d.solid[i])) {
            dyn_ptr(d.solid[i], "set_Enabled", {(void*)(uintptr_t)1});
            d.solid[i]->release();
        }
        d.solid[i] = nullptr;
    }
    d.solid_n = 0;
}

// NOT app.DoorBehavior.SetDoorCollidersEnable: it left the leaf's own via.physics.Colliders on (simulator,
// 2026-11-19). Off: the leaf's own colliders and its children's, except the game's sensors (children named
// Collider*: push / in / passed) and the enemies' map (AiMap).
void solid_off(Leaf& d) {
    if (d.solid_n != 0 || !is_managed(d.door)) return;
    auto take = [&](MO* go) {
        MO* c = component(go, "via.physics.Colliders");
        bool enabled = false;
        if (c == nullptr || d.solid_n >= MAX_SOLID || !dyn_value(c, "get_Enabled", &enabled, sizeof enabled) || !enabled) return;
        c->add_ref();
        dyn_ptr(c, "set_Enabled", {(void*)(uintptr_t)0});
        d.solid[d.solid_n++] = c;
    };
    take(transform_object().ptr(d.transform));
    MO* child = transform_child().ptr(d.transform);
    for (int n = 0; child != nullptr && n < MAX_CHILDREN; ++n) {
        MO* go = transform_object().ptr(child);
        const std::string name = read_string(object_name().ptr(go));
        if (go != nullptr && name.rfind("Collider", 0) != 0 && name.find("AiMap") == std::string::npos &&
            name.find("AIMap") == std::string::npos) take(go);
        child = transform_next().ptr(child);
    }
    say("an open door: %.0f solid part(s) off while the hands and the body push it", (float)d.solid_n);
}

int index_of(const Leaf& d) { return (int)(&d - g_leaf); }

// Tefa, 2026-11-26: a door pushed by hand made one sound at the touch and none while it moved: the game creaks
// only while IT moves a leaf. So the door's own creak is asked for while ours moves, and its stop when it rests.
void creak(Leaf& d, bool on) {
    if (d.creaking == on) return;
    d.creaking = on;
    MO* door = d.door;
    const uint32_t kind = on ? SE_CREAK_SLOW : SE_CREAK_STOP;
    gate::ask(gate::Kind::DoorSound, [door, kind]() {
        static Call call_se("app.DoorBehavior", "CallSE(System.UInt32)", 1);
        if (is_managed(door)) call_se.ptr(door, {(void*)(uintptr_t)kind});
    });
}

void drop(Leaf& d, bool door_still_there) {
    if (d.solid_n != 0) {
        if (door_still_there) solid_on(d);
        else for (int i = 0; i < d.solid_n; ++i) if (is_managed(d.solid[i])) d.solid[i]->release();
    }
    d = Leaf{};
}

bool drawn(const Leaf& d);   // below, with the several-doors-in-one-spot note

// ---- finding the near leaves ------------------------------------------------------------------------------------
void take(Leaf& d, MO* door, float away) {
    d = Leaf{};
    d.door = door;
    d.transform = transform_of(door);
    d.hinge = jointwriter::joint_by_name(d.transform, L"_00");
    if (d.transform == nullptr || d.hinge == nullptr) { say("a door with no joint _00: left alone"); d = Leaf{}; return; }
    d.rest_deg = local_yaw_deg(d.hinge);
    // which side of the hinge the leaf lies on, and how wide it is: from the door's own bottom centre. Whether
    // the game gives that in the world or in the door's frame is not known, so both are tried (the log says).
    Vec3 centre{}, hinge{}, local{};
    const char* read_as = "not given: both sides count, 1 m wide";
    if (dyn_value(door, "get_doorBottomCenter", &centre, sizeof centre) && finite(centre) &&
        joint_position().value(d.hinge, &hinge, sizeof hinge)) {
        bool have = false;
        if (length(centre - hinge) < LEAF_MAX_M) { have = to_leaf_frame(d, centre, local); read_as = "a world point"; }
        else if (length(centre) < LEAF_MAX_M) { local = centre; have = true; read_as = "a point in the door's frame"; }
        if (have && std::fabs(local.x) * 2.0f >= LEAF_MIN_M && std::fabs(local.x) * 2.0f <= LEAF_MAX_M) {
            d.side = local.x < 0.0f ? -1.0f : 1.0f;
            d.width = std::fabs(local.x) * 2.0f;
        } else {
            read_as = "not usable: both sides count, 1 m wide";
        }
    }
    const uint32_t st = state_of(door);
    if (g_named.insert(door).second && g_lines++ < MAX_LINES) {
        // every door is its own object with its own name: a door that needs its own rule is told apart by it
        std::string name = read_string(object_name().ptr(transform_object().ptr(d.transform)));
        if (MO* parent = transform_parent().ptr(d.transform))
            name = read_string(object_name().ptr(transform_object().ptr(parent))) + "/" + name;
        LOGI("%s doors: met \"%s\" %.1f m away: leaf %.2f m wide, side %+.0f (bottom centre %s), state %u, leaf at %.0f deg, %s", TAG,
             name.c_str(), away, d.width, d.side, read_as, st, d.rest_deg, drawn(d) ? "drawn" : "NOT drawn");
    }
}

void scan(Vec3 at) {
    MO* list = components("app.DoorBehavior");
    const int n = count_of(list);
    MO* best[MAX_LEAVES]{};
    float best_m[MAX_LEAVES];
    std::fill(best_m, best_m + MAX_LEAVES, SCAN_M);
    bool listed[MAX_LEAVES]{};
    for (int i = 0; i < n; ++i) {
        MO* door = item_of(list, i);
        for (int k = 0; k < MAX_LEAVES; ++k) listed[k] = listed[k] || (door != nullptr && g_leaf[k].door == door);
        Vec3 p{};
        if (door == nullptr || !transform_position().value(transform_of(door), &p, sizeof p) || !finite(p)) continue;
        if (std::fabs(p.y - at.y) > SCAN_UP_M) continue;
        const float m = level(p, at);
        for (int j = 0; j < MAX_LEAVES; ++j) {
            if (m >= best_m[j]) continue;
            for (int k = MAX_LEAVES - 1; k > j; --k) { best[k] = best[k - 1]; best_m[k] = best_m[k - 1]; }
            best[j] = door;
            best_m[j] = m;
            break;
        }
    }
    for (int k = 0; k < MAX_LEAVES; ++k) {
        Leaf& d = g_leaf[k];
        if (d.door == nullptr) continue;
        if (!listed[k]) { drop(d, false); continue; }            // the scene no longer has it: nothing of it is touched
        bool close_by = false;
        for (MO* b : best) close_by = close_by || b == d.door;
        if (!close_by && !d.ours) drop(d, true);
        // a leaf of ours is NOT let go while the game is closing it (2026-11-26, Tefa: doors closing behind him
        // "close with a teleport step": walking on past 3 m let the leaf go mid-swing). It is let go by step()'s
        // own "the game shut the door", or here once it is far away.
        else if (!close_by && d.ours) {
            Vec3 hinge{};
            if (!joint_position().value(d.hinge, &hinge, sizeof hinge) || level(hinge, at) > RELEASE_M) drop(d, true);
        }
    }
    for (int j = 0; j < MAX_LEAVES; ++j) {
        if (best[j] == nullptr) continue;
        bool have = false;
        for (const Leaf& d : g_leaf) have = have || d.door == best[j];
        if (have) continue;
        for (Leaf& d : g_leaf)
            if (d.door == nullptr) { take(d, best[j], best_m[j]); break; }
    }
}

// SEVERAL DOORS IN ONE SPOT (2026-11-26, found by the name lines: the bolted door in the village is three door
// objects on one hinge, "Before_Dynamic/..._Out" standing 20 deg open, "After1_Dynamic/...DoorOneWayLock_1Way"
// and "After2_Dynamic/..._Door_Dynamic"; the game shows one and keeps the others). Until b186 the InteractDoor
// part was picked by nearness to the hinge, so the game was asked to open the WRONG door of the three (ten asks,
// none answered), and the hand was read against leaves that are not drawn.
// a part belongs to a door when its own Door field is that door
bool part_of(MO* part, MO* door) { return field_obj(part, "Door") == door; }
// is the door's object drawn at all? (not answered = taken as drawn)
bool drawn(const Leaf& d) {
    bool draw = true;
    MO* go = transform_object().ptr(d.transform);
    return go == nullptr || !dyn_value(go, "get_Draw", &draw, sizeof draw) || draw;
}

// ---- the hand on a shut door: the game's own door start, through the gate ---------------------------------------
void open_request(MO* door, Vec3 hinge) {
    const auto& player = ready::now();
    Vec3 at{};
    const uint32_t st = is_managed(door) ? state_of(door) : 0u;
    if ((st != ST_CLOSED && st != ST_CURVE) || player.player == nullptr ||
        !transform_position().value(player.transform, &at, sizeof at)) return;
    MO* list = components("app.InteractDoor");
    MO* best = nullptr;
    float best_m = 1e9f;
    bool best_own = false;
    for (int i = 0, n = count_of(list); i < n; ++i) {
        MO* part = item_of(list, i);
        Vec3 p{};
        if (part == nullptr || !transform_position().value(transform_of(part), &p, sizeof p) || !finite(p)) continue;
        if (level(p, hinge) > INTERACT_PICK_M || std::fabs(p.y - hinge.y) > 2.0f) continue;
        const bool own = part_of(part, door);
        if (own && !best_own) { best = nullptr; best_m = 1e9f; best_own = true; }   // from here only its own parts count
        if (best_own && !own) continue;
        const float m = level(p, at);
        if (m < best_m) { best = part; best_m = m; }
    }
    if (best == nullptr) { say("a hand on a door, but no InteractDoor part within %.1f m of its hinge", INTERACT_PICK_M); return; }
    static Call start("app.InteractDoor", "StartInteractDoor", 1);
    start.ptr(best, {player.player});
    say(best_own ? "a hand on a door: the game was asked to open it (the door's own part, %.2f m from Ethan)"
                 : "a hand on a door: the game was asked to open it (the NEAREST part, %.2f m from Ethan: none says it is this door's)", best_m);
}

void touch(Leaf& d, const Vec3 hands[2], const bool hand_ok[2], float now, uint32_t /*st*/) {
    for (int i = 0; i < 2; ++i) {
        Vec3 local{};
        if (!hand_ok[i] || !to_leaf_frame(d, hands[i], local)) { d.prev_ok[i] = false; continue; }
        // the leaf at joint yaw t lies along (s cos t, 0, -s sin t); for a door never seen shut its rest is taken as 0
        const float t = (local_yaw_deg(d.hinge) - (d.seen_shut ? d.rest_deg : 0.0f)) * DEG;
        const float on_line = local.x * std::cos(t) - local.z * std::sin(t);
        const float along = d.side != 0.0f ? on_line * d.side : std::fabs(on_line);
        const float across = local.x * std::sin(t) + local.z * std::cos(t);   // which face of the leaf the hand is at
        const float off = std::fabs(across);
        const float away = (across > 0.0f ? 1.0f : -1.0f) * (d.side != 0.0f ? d.side : 1.0f);   // the turn that moves the leaf away from it
        const bool on_leaf = along >= HINGE_GAP_M && along <= d.width + g_hand_m && off <= g_hand_m;
        const bool closing_in = d.prev_ok[i] && off < d.prev[i];
        d.prev[i] = off;
        d.prev_ok[i] = true;
        if (!on_leaf || !closing_in || now - g_touch_at < TOUCH_COOLDOWN_S) continue;
        g_touch_at = now;
        if (is_locked(d.door)) { say("a hand on a LOCKED door (%.2f m from the hinge): nothing asked", along); return; }
        Vec3 hinge{};
        if (!joint_position().value(d.hinge, &hinge, sizeof hinge)) return;
        say(i == 0 ? "the left hand on a door, %.2f m from the hinge (the leaf at %.0f deg)" : "the right hand on a door, %.2f m from the hinge (the leaf at %.0f deg)", along, t / DEG);
        MO* door = d.door;
        gate::ask(gate::Kind::DoorOpen, [door, hinge]() { open_request(door, hinge); });
        d.asked_at = now;
        d.ask_sign = away;
        return;
    }
}

// ---- an open leaf: pushed by the hands and the body (the sums are b178's) ---------------------------------------
void push(Leaf& d, const Vec3 points[PUSHERS], const bool ok[PUSHERS]) {
    for (int i = 0; i < PUSHERS; ++i) {
        Vec3 local{};
        const float reach = i < 2 ? g_hand_m : g_body_m;
        float a = 0.0f, r = 0.0f;
        if (!ok[i] || !to_leaf_frame(d, points[i], local)) { d.prev_ok[i] = false; continue; }
        angle_of(d, local, a, r);
        if (r < (i < 2 ? HINGE_GAP_M : reach) || r > d.width + reach) { d.prev_ok[i] = false; continue; }
        const float m = std::asin(std::min(1.0f, reach / r)) / DEG;      // the pusher's own half width, as an angle
        if (i < 2) {
            // a hand that crossed the leaf since last frame, or is on it, pushes it to just past itself
            const bool crossed = d.prev_ok[i] && d.prev[i] <= d.drawn_deg + m && a + m > d.drawn_deg;
            const bool on_it = std::fabs(a - d.drawn_deg) <= m;
            if ((crossed || on_it) && a + m > d.drawn_deg && a + m < MAX_DEG + 20.0f) d.drawn_deg = std::min(MAX_DEG, a + m);
        } else if (a + m > d.drawn_deg && a - m < MAX_DEG) {
            d.drawn_deg = std::min(MAX_DEG, a + m);                     // never drawn through the player in the doorway
        }
        d.prev[i] = a;
        d.prev_ok[i] = true;
    }
}

// A different door: is a hand or the body near its leaf (where the leaf stands now)? Then its walk-in open is let
// through this frame.
void near_opens(Leaf& d, const Vec3 points[PUSHERS], const bool ok[PUSHERS], float now) {
    bool close = false;
    const float t = (local_yaw_deg(d.hinge) - (d.seen_shut ? d.rest_deg : 0.0f)) * DEG;
    for (int i = 0; i < PUSHERS && !close; ++i) {
        Vec3 local{};
        if (!ok[i] || !to_leaf_frame(d, points[i], local)) continue;
        const float reach = i < 2 ? g_near_hand_m : g_near_body_m;
        const float on_line = local.x * std::cos(t) - local.z * std::sin(t);
        const float along = d.side != 0.0f ? on_line * d.side : std::fabs(on_line);
        const float off = std::fabs(local.x * std::sin(t) + local.z * std::cos(t));
        close = along >= -reach && along <= d.width + reach && off <= reach && (i < 2 || std::fabs(local.y) < 2.5f);
    }
    if (!close) { d.near_told = false; return; }
    if (now - d.parts_at > PARTS_EVERY_S) {
        d.parts_at = now;
        d.parts[0] = d.parts[1] = nullptr;
        Vec3 hinge{};
        MO* list = components("app.InteractDoor");
        float best[2] = {INTERACT_PICK_M, INTERACT_PICK_M};
        if (joint_position().value(d.hinge, &hinge, sizeof hinge))
            for (int i = 0, n = count_of(list); i < n; ++i) {
                MO* part = item_of(list, i);
                Vec3 p{};
                if (part == nullptr || !transform_position().value(transform_of(part), &p, sizeof p) || !finite(p)) continue;
                const float m = level(p, hinge);
                if (std::fabs(p.y - hinge.y) > 2.0f || !part_of(part, d.door)) continue;
                if (m < best[0]) { best[1] = best[0]; d.parts[1] = d.parts[0]; best[0] = m; d.parts[0] = part; }
                else if (m < best[1]) { best[1] = m; d.parts[1] = part; }
            }
    }
    for (MO* part : d.parts)
        if (part != nullptr && g_allow_n < ALLOWED) g_allow_next[g_allow_n++] = part;
    if (!d.near_told) {
        d.near_told = true;
        say("a different door: a hand or the body is near, its own walk-in open is let through (%.0f part(s))",
            (float)((d.parts[0] != nullptr) + (d.parts[1] != nullptr)));
    }
}

void step(Leaf& d, const Vec3 points[PUSHERS], const bool ok[PUSHERS], bool hands_free, float now) {
    if (!is_managed(d.door)) { drop(d, false); return; }
    const uint32_t st = state_of(d.door);
    if (!d.ours && !drawn(d)) { std::fill(d.prev_ok, d.prev_ok + PUSHERS, false); return; }   // one of several in this spot, not shown
    if (!d.ours) {
        if (is_shut(st)) {
            if (!d.seen_shut || d.games_own) d.rest_deg = local_yaw_deg(d.hinge);
            d.seen_shut = true;
            d.games_own = false;
            if (d.asked_at >= 0.0f && st == ST_CLOSED && now - d.asked_at > ASK_WAIT_S) {
                // asked, and the game did nothing (the bolted door once it had swung shut: ten asks, 2026-11-26)
                d.asked_at = -1.0f;
                g_refused.insert(d.door);
                say("the game did not open the door it was asked to: a different door from now on (it opens by nearness)");
            }
            if (g_refused.count(d.door) != 0) d.different = true;
            if (d.different) { if (st == ST_CLOSED && !is_locked(d.door)) near_opens(d, points, ok, now); return; }
            if (st == ST_CLOSED && hands_free) touch(d, points, ok, now, st);
            return;
        }
        // found standing a crack open, or swinging by itself: a different door
        if ((!d.seen_shut && st == ST_LITTLE_OPENED) || st == ST_CURVE) {
            d.different = true;
            near_opens(d, points, ok, now);
            return;
        }
        if (d.different && is_open(st)) d.games_own = true;           // it opened its own way: the game's leaf
        if (!d.seen_shut || d.games_own || !is_open(st)) return;      // found open, or the game's own (Rose)
        if (!hands_free) {                                            // opened by walking in with Rose: all the game's
            d.games_own = true;
            say("a door opened while the game's arms show: left to the game until it is shut again");
            return;
        }
        d.ours = true;
        d.asked_at = -1.0f;
        const auto* dest = (const float*)field_data(d.door, "DestAngle");
        d.sign = dest != nullptr && std::isfinite(*dest) && *dest < -1.0f ? -1.0f : 1.0f;
        d.drawn_deg = INITIAL_DEG;
        d.shut_since = -1.0f;
        std::fill(d.prev_ok, d.prev_ok + PUSHERS, false);
        say("the game opened a door (it turns %+.0f, its own target %.0f deg): drawn at %.0f deg, pushed from here",
            d.sign, dest != nullptr ? *dest : 0.0f, INITIAL_DEG);
        const int k = index_of(d);
        gate::ask(gate::Kind::DoorSolid, [k]() { if (g_leaf[k].ours) solid_off(g_leaf[k]); });
        return;
    }
    if (is_shut(st)) { if (d.shut_since < 0.0f) d.shut_since = now; } else d.shut_since = -1.0f;
    bool hands_push[PUSHERS] = {ok[0], ok[1], ok[2]};
    if (st == ST_CLOSING || is_shut(st)) {
        if (d.closing_from < 0.0f) { d.closing_from = d.drawn_deg; d.closing_at = now; creak(d, false); }
        const float k = std::clamp((now - d.closing_at) / CLOSE_S, 0.0f, 1.0f);
        d.drawn_deg = std::min(d.drawn_deg, d.closing_from * (1.0f - k * k * (3.0f - 2.0f * k)));
        hands_push[0] = hands_push[1] = false;            // only the body in the doorway holds a closing leaf
    } else {
        d.closing_from = -1.0f;
    }
    if (d.shut_since >= 0.0f && now - d.shut_since >= SHUT_HOLD_S && (d.closing_from < 0.0f || now - d.closing_at >= CLOSE_S)) {
        creak(d, false);
        d.closing_from = -1.0f;
        say("the game shut the door: ours too (drawn %.0f deg, back to its own %.1f)", d.drawn_deg, d.rest_deg);
        d.ours = false;
        d.put_back = true;
        d.drawn_deg = 0.0f;
        d.shut_since = -1.0f;
        std::fill(d.prev_ok, d.prev_ok + PUSHERS, false);
        const int k = index_of(d);
        gate::ask(gate::Kind::DoorSolid, [k]() { if (!g_leaf[k].ours) solid_on(g_leaf[k]); });
        return;
    }
    const float before = d.drawn_deg;
    push(d, points, hands_push);
    if (d.drawn_deg > before + MOVED_DEG && d.closing_from < 0.0f) { d.moved_at = now; creak(d, true); }
    else if (d.creaking && now - d.moved_at > CREAK_STOP_S) creak(d, false);
    if (std::floor(d.drawn_deg / 15.0f) != std::floor(before / 15.0f)) say("a door pushed to %.0f deg", d.drawn_deg);
}

// ---- the walk-in hook (rule 8: one flag read, one counter) ------------------------------------------------------
int pre_walk_in(int argc, void** argv, REFrameworkTypeDefinitionHandle*, unsigned long long) {
    if (g_walk_in.load(std::memory_order_relaxed)) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    if (argc >= 2 && argv != nullptr && argv[1] != nullptr)
        for (const auto& allowed : g_allowed)
            if (allowed.load(std::memory_order_relaxed) == argv[1]) return REFRAMEWORK_HOOK_CALL_ORIGINAL;
    g_walk_skipped.fetch_add(1, std::memory_order_relaxed);
    return REFRAMEWORK_HOOK_SKIP_ORIGINAL;
}
void post_nothing(void**, REFrameworkTypeDefinitionHandle, unsigned long long) {}

void place_hook() {
    if (g_hook_tried) return;
    g_hook_tried = true;
    auto* method = API::get()->tdb()->find_method("app.InteractDoor", "OnOverlapDoorPushCollider");
    if (method == nullptr) { LOGW("%s doors: app.InteractDoor.OnOverlapDoorPushCollider was not found: doors still open by walking near", TAG); return; }
    method->add_hook(pre_walk_in, post_nothing, false);
    LOGI("%s doors: no open by walking near any more; a hand on the door opens it (walking in still does while Rose is carried)", TAG);
}

void read_file(float now) {
    if (now - g_file_at < FILE_EVERY_S) return;
    g_file_at = now;
    float hand = HAND_CM, body = BODY_CM, v = 0.0f;
    std::ifstream f(paths::data(L"doors.txt"));
    if (f >> v && std::isfinite(v)) hand = std::clamp(v, 2.0f, 40.0f);
    if (f >> v && std::isfinite(v)) body = std::clamp(v, 10.0f, 80.0f);
    float near_hand = NEAR_HAND_CM, near_body = NEAR_BODY_CM;
    if (f >> v && std::isfinite(v)) near_hand = std::clamp(v, 5.0f, 150.0f);
    if (f >> v && std::isfinite(v)) near_body = std::clamp(v, 20.0f, 300.0f);
    if (near_hand * 0.01f != g_near_hand_m || near_body * 0.01f != g_near_body_m)
        say("a different door opens with a hand within %.0f cm or the body within %.0f cm now", near_hand, near_body);
    g_near_hand_m = near_hand * 0.01f;
    g_near_body_m = near_body * 0.01f;
    if (hand * 0.01f != g_hand_m || body * 0.01f != g_body_m)
        say("the hand reaches %.0f cm and the body %.0f cm now", hand, body);
    g_hand_m = hand * 0.01f;
    g_body_m = body * 0.01f;
}
} // namespace

void frame() {
    place_hook();
    const auto& player = ready::now();
    const bool in_vr = bridge::live() && bridge::flag(bridge::S_ACTIVE);
    const bool hands_free = in_vr && player.hands_are_players && !gamearms::carrying();
    g_walk_in.store(!in_vr || gamearms::carrying(), std::memory_order_relaxed);
    const unsigned skipped = g_walk_skipped.load(std::memory_order_relaxed);
    if (skipped != 0 && g_walk_told == 0) say("a door's walk-in open was skipped for the first time (doors wait for a hand)");
    g_walk_told = skipped;

    if (player.generation != g_generation) {                // a new player (a load): nothing kept, nothing touched
        g_generation = player.generation;
        for (Leaf& d : g_leaf) drop(d, false);
        g_hand[0] = g_hand[1] = nullptr;
    }
    Vec3 at{};
    if (player.transform == nullptr || !transform_position().value(player.transform, &at, sizeof at) || !finite(at)) return;
    const float now = now_s();
    read_file(now);
    if (now - g_scan_at >= SCAN_S) { g_scan_at = now; scan(at); }

    if (g_hand[0] == nullptr) g_hand[0] = jointwriter::joint_by_name(player.transform, L"L_Hand");
    if (g_hand[1] == nullptr) g_hand[1] = jointwriter::joint_by_name(player.transform, L"R_Hand");
    Vec3 points[PUSHERS]{};
    bool ok[PUSHERS]{};
    for (int i = 0; i < 2; ++i) {
        const bool asleep = bridge::flag(i == 0 ? bridge::S_LEFT_ASLEEP : bridge::S_RIGHT_ASLEEP);
        ok[i] = hands_free && !asleep && g_hand[i] != nullptr &&
                joint_position().value(g_hand[i], &points[i], sizeof(Vec3)) && finite(points[i]);
    }
    points[2] = at;
    ok[2] = true;
    g_allow_n = 0;
    for (Leaf& d : g_leaf)
        if (d.door != nullptr) step(d, points, ok, hands_free, now);
    for (int i = 0; i < ALLOWED; ++i) g_allowed[i].store(i < g_allow_n ? g_allow_next[i] : nullptr, std::memory_order_relaxed);
}

void pose() {
    for (Leaf& d : g_leaf) {
        if (d.door == nullptr || d.hinge == nullptr || !(d.ours || d.put_back) || !is_managed(d.door)) continue;
        const float deg = d.ours ? d.rest_deg + d.sign * d.drawn_deg : d.rest_deg;
        const float half = deg * DEG * 0.5f;
        jointwriter::ask_local_rotation(jointwriter::Owner::DoorLeaf, d.hinge, Quat{0.0f, std::sin(half), 0.0f, std::cos(half)});
        d.put_back = false;
    }
}

} // namespace vr8::doors
