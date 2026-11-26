// gamearms.cpp -- see gamearms.h
#include "gamearms.h"

#include "base.h"
#include "bridge.h"
#include "ready.h"

#include <string>

namespace vr8::gamearms {

namespace {
// ---- the named numbers and the two lists ------------------------------------------------------------------------
constexpr int CHECK_EVERY_FRAMES = 10;     // the carry check (as the script had it)
constexpr int MAX_CHILDREN = 80;           // how many of the player's children are looked at
constexpr int MAX_BODY_MESHES = 4;
constexpr int HEAD_MESHES = 2;

struct Carried { const char* object; const char* what; };
const Carried CARRIED[] = {
    {"pl5000", "Rose"},
};

struct Scene { const char* event; const char* what; bool body; bool head; };
const Scene SCENES[] = {
    {"c10e050_00", "Ethan puts Rose in the crib", true, true},
};

const char* const BODY_PARTS[] = {"pl1000LowerBody"};          // children of the player drawn with the body
const char* const HEAD_FIELDS[HEAD_MESHES] = {"FaceMesh", "HairMesh"};   // app.PlayerMeshController

// ---- state ------------------------------------------------------------------------------------------------------
unsigned g_generation = 0;
int g_frame = 0;
const Carried* g_carrying = nullptr;
MO* g_body[MAX_BODY_MESHES]{};
int g_body_n = -1;                         // -1 = not looked for yet (for this player)
const Scene* g_scene = nullptr;
MO* g_head[HEAD_MESHES]{};
bool g_head_was[HEAD_MESHES]{};
int g_head_n = 0;
MO* g_events = nullptr;                   // app.GameEventActionController on the player, found once per player

Call& get_child() { static Call c("via.Transform", "get_Child", 0); return c; }
Call& get_next() { static Call c("via.Transform", "get_Next", 0); return c; }
Call& get_game_object() { static Call c("via.Transform", "get_GameObject", 0); return c; }
Call& get_name() { static Call c("via.GameObject", "get_Name", 0); return c; }
Call& set_draw() { static Call c("via.render.Mesh", "set_DrawDefault", 1); return c; }
Call& get_draw() { static Call c("via.render.Mesh", "get_DrawDefault", 0); return c; }

// every first-level child of a transform: fn(its GameObject, its name); fn returns true to stop
template <typename Fn> void each_child(MO* transform, Fn&& fn) {
    MO* child = get_child().ptr(transform);
    for (int n = 0; child != nullptr && n < MAX_CHILDREN; ++n) {
        MO* go = get_game_object().ptr(child);
        if (go != nullptr && fn(go, read_string(get_name().ptr(go)))) return;
        child = get_next().ptr(child);
    }
}

const Carried* carried_child(MO* transform) {
    const Carried* found = nullptr;
    each_child(transform, [&](MO*, const std::string& name) {
        for (const auto& c : CARRIED)
            if (name == c.object) { found = &c; return true; }
        return false;
    });
    return found;
}

void set_carrying(const Carried* what) {
    bridge::write(bridge::S_GAME_ARMS, what != nullptr ? 1.0f : 0.0f);   // every time: the script may have restarted
    if (what == g_carrying) return;
    g_carrying = what;
    if (what != nullptr) LOGI("%s game arms: the game's arms, carrying %s", TAG, what->what);
    else LOGI("%s game arms: the controllers have the hands back", TAG);
}

void draw(MO* mesh, bool on) {
    if (is_managed(mesh)) set_draw().ptr(mesh, {(void*)(uintptr_t)(on ? 1 : 0)});
}

void find_body(const ready::Snapshot& player) {
    g_body_n = 0;
    if (MO* own = component(player.player, "via.render.Mesh")) g_body[g_body_n++] = own;
    each_child(player.transform, [&](MO* go, const std::string& name) {
        for (const char* part : BODY_PARTS)
            if (name == part && g_body_n < MAX_BODY_MESHES)
                if (MO* mesh = component(go, "via.render.Mesh")) g_body[g_body_n++] = mesh;
        return false;
    });
    LOGI("%s game arms: the body stays drawn: %d meshes", TAG, g_body_n);
}

const Scene* running_scene(MO* player) {
    if (!is_managed(g_events)) g_events = component(player, "app.GameEventActionController");
    MO* action = field_obj(g_events, "_GameEventAction");
    if (action == nullptr) return nullptr;
    const std::string name = read_string(field_obj(action, "_EventName"));
    if (name.empty()) return nullptr;
    for (const auto& s : SCENES)
        if (name == s.event) return &s;
    return nullptr;
}

void head_end() {
    for (int i = 0; i < g_head_n; ++i) draw(g_head[i], g_head_was[i]);
    if (g_head_n != 0) LOGI("%s game arms: head: put back as found", TAG);
    g_head_n = 0;
}

void head_begin(MO* player) {
    g_head_n = 0;
    MO* controller = component(player, "app.PlayerMeshController");
    if (controller == nullptr) { LOGI("%s game arms: head: no mesh controller on the player", TAG); return; }
    for (const char* field : HEAD_FIELDS) {
        MO* mesh = field_obj(controller, field);
        bool was = false;
        if (mesh == nullptr || !get_draw().value(mesh, &was, sizeof was)) {
            LOGI("%s game arms: head: %s not found", TAG, field);
            continue;
        }
        LOGI("%s game arms: head, as found: %s drawn=%d", TAG, field, was ? 1 : 0);
        g_head[g_head_n] = mesh;
        g_head_was[g_head_n] = was;
        ++g_head_n;
    }
}

void forget() {
    g_carrying = nullptr;
    g_body_n = -1;
    g_scene = nullptr;
    g_events = nullptr;
    g_head_n = 0;        // a new player: the old meshes are not ours to put back
}
} // namespace

bool carrying() { return g_carrying != nullptr; }

void frame() {
    const auto& player = ready::now();
    if (player.generation != g_generation) {
        g_generation = player.generation;
        forget();
    }
    if (player.transform == nullptr) { set_carrying(nullptr); return; }
    if (++g_frame % CHECK_EVERY_FRAMES != 0) {
        bridge::write(bridge::S_GAME_ARMS, g_carrying != nullptr ? 1.0f : 0.0f);
        return;
    }
    set_carrying(carried_child(player.transform));
}

void lock_scene() {
    const auto& player = ready::now();
    if (player.generation != g_generation || player.player == nullptr || player.transform == nullptr) return;
    const Scene* scene = running_scene(player.player);
    if (scene != g_scene) {
        head_end();
        if (scene != nullptr && scene->head) head_begin(player.player);
        g_scene = scene;
        if (scene != nullptr)
            LOGI("%s game arms: scene on the list: %s%s", TAG, scene->what, scene->body ? " (body shown)" : "");
    }
    for (int i = 0; i < g_head_n; ++i) draw(g_head[i], true);
    if (g_carrying == nullptr && !(scene != nullptr && scene->body)) return;
    if (g_body_n < 0) find_body(player);
    for (int i = 0; i < g_body_n; ++i) draw(g_body[i], true);
}

} // namespace vr8::gamearms
