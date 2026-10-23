// ammo_hud.cpp -- see ammo_hud.h. A line-for-line port of re8_vr_ammo_hud.lua (its function names are kept in the
// comments, so the two can be read side by side); what differs is said where it happens.
#include "ammo_hud.h"
#include "bridge.h"
#include "joints.h"
#include "json_mini.h"
#include "player.h"
#include "weapons.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>

namespace vn::ammo_hud {

using joints::now_s;

namespace {
constexpr uint32_t ETHAN_REMAIN_AMMO_HASH = 1927694450u;

enum class Display { DEFAULT, WEAPON, OFF };
struct Cfg {   // re8_vr_ammo_hud.lua CFG, Andyalpa's defaults
    Display display = Display::WEAPON;
    bool keep_open = true;
    float force_open_interval_s = 2.0f;
    bool set_world_view = true;
    float off_right = 0.04f, off_up = -0.02f, off_forward = 0.08f;
    float rot_yaw = 0.0f, rot_pitch = 0.0f, rot_roll = 0.0f;
    float scale = 0.55f;
    float poll_s = 0.35f;
};
Cfg g_cfg;

// the menu reads this number (lua/visceral_re8_menu.lua STATUS_NAMES): the Lua's STATE.status
enum Status { ST_INIT, ST_READY, ST_PARTIAL, ST_NO_GUI_MANAGER, ST_NO_REMAIN_AMMO, ST_RECOVER_PENDING, ST_MENU_YIELD,
              ST_OFF, ST_MELEE_HIDE, ST_WEAPON, ST_DEFAULT };
enum class Kind { MELEE, AMMO, UNKNOWN };

struct State {   // STATE
    Status status = ST_INIT;
    MO* gui_mgr = nullptr;
    MO* wig = nullptr;         // the remaining-ammo driver (app.GUIRemainAmmo / app.GUIPl4000RemainAmmo)
    MO* go = nullptr;
    MO* xform = nullptr;
    MO* gui_comp = nullptr;
    std::string go_name = "GUIRemainAmmo";
    bool is_open = false;
    float last_poll_t = 0, last_open_t = 0, last_draw_t = 0;
    int apply_count = 0, draw_count = 0;
    bool menu_blocking = false, menu_was_blocking = false;
    float recover_t = 0;
    std::string active_weapon_id;
    std::string hide_reason;
    bool show_ammo = false, was_show_ammo = false;
    float lost_show_t = 0, last_recover_t = 0;
    std::string recover_reason;
    float pause_gui_time = -10.0f;
    std::string last_ammo_id;
    float last_ammo_t = 0;
    int recover_draw_count = 0;
    std::string pre_menu_ammo_id;
    bool pre_menu_show = false;
    int hmd_was = -1;          // -1 = not seen yet (the Lua's nil)
};
State S;

bool alive(MO* o) { return o != nullptr && is_managed(o); }   // managed_alive

// ---- the settings file (load_cfg; the menu Lua writes it) ----------------------------------------------------------
std::wstring cfg_path() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring p(exe);
    p = p.substr(0, p.find_last_of(L"\\/") + 1);
    return p + L"reframework\\data\\re8_vr\\re8_vr_ammo_hud.json";
}
void load_cfg() {
    json::Value v;
    if (!json::load_file(cfg_path(), v) || v.kind != json::Value::OBJ) return;
    Cfg c;
    auto b = [&](const char* k, bool& out) { if (auto* x = v.get(k); x && x->kind == json::Value::BOOL) out = x->b; };
    auto f = [&](const char* k, float& out) { if (auto* x = v.get(k); x && x->kind == json::Value::NUM) out = (float)x->n; };
    b("keep_open", c.keep_open); f("force_open_interval_s", c.force_open_interval_s); b("set_world_view", c.set_world_view);
    f("off_right", c.off_right); f("off_up", c.off_up); f("off_forward", c.off_forward);
    f("rot_yaw", c.rot_yaw); f("rot_pitch", c.rot_pitch); f("rot_roll", c.rot_roll);
    f("scale", c.scale); f("poll_s", c.poll_s);
    // display: "default" | "weapon" | "off"; older files had enabled / attach booleans instead
    const auto* d = v.get("display");
    if (d != nullptr && d->kind == json::Value::STR) c.display = d->s == "default" ? Display::DEFAULT : d->s == "off" ? Display::OFF : Display::WEAPON;
    else {
        const auto* en = v.get("enabled");
        const auto* at = v.get("attach");
        if ((en && en->kind == json::Value::BOOL && !en->b) || (at && at->kind == json::Value::BOOL && !at->b)) c.display = Display::DEFAULT;
    }
    g_cfg = c;
    LOGI("%s ammo hud: settings read (display %s, scale %.2f, offset %.3f %.3f %.3f)", TAG,
         c.display == Display::WEAPON ? "weapon" : c.display == Display::OFF ? "off" : "default", c.scale, c.off_right, c.off_up, c.off_forward);
}
void check_cfg_file() {
    static FILETIME last{};
    static bool first = true;
    static float next = 0.0f;
    const float now = now_s();
    if (now < next) return;   // a file check twice a second is plenty for a slider
    next = now + 0.5f;
    WIN32_FILE_ATTRIBUTE_DATA a{};
    if (!GetFileAttributesExW(cfg_path().c_str(), GetFileExInfoStandard, &a)) { first = false; return; }
    if (!first && CompareFileTime(&a.ftLastWriteTime, &last) == 0) return;
    first = false;
    last = a.ftLastWriteTime;
    load_cfg();
}

bool weapon_mode() { return g_cfg.display == Display::WEAPON; }   // is_weapon_mode

// is_blocking_menu: the holster's __vr_is_interaction_blocked(), or a pause / inventory GUI drawn in the last 0.5 s
bool blocking_menu() { return bridge::flag(bridge::S_INTERACTION_BLOCKED) || now_s() - S.pause_gui_time < 0.50f; }

void clear_hud_children() { S.go = S.xform = S.gui_comp = nullptr; }
void clear_refs() { S.wig = nullptr; clear_hud_children(); }

bool is_type(MO* o, const char* full) {   // the type or any parent is `full`
    if (o == nullptr) return false;
    for (auto* td = o->get_type_definition(); td != nullptr; td = td->get_parent_type())
        if (std::strcmp(td->get_full_name().c_str(), full) == 0) return true;
    return false;
}
bool is_remain_ammo_driver(MO* drv) {
    if (!alive(drv)) return false;
    const std::string n = type_name(drv);
    return n == "app.GUIRemainAmmo" || n == "app.GUIPl4000RemainAmmo";
}

// ---- which weapon (classify_weapon_for_ammo) ----------------------------------------------------------------------
// The Lua asked praydog's re8vr / the holster's globals; the plugin's own player snapshot holds the same weapon.
Kind classify() {
    if (!weapon_mode()) { S.active_weapon_id.clear(); S.hide_reason = "mode"; return Kind::MELEE; }
    if (bridge::flag(bridge::S_BARE_HANDS)) { S.active_weapon_id = "Hand"; S.hide_reason = "bare"; return Kind::MELEE; }
    const auto& p = player::now();
    if (!alive(p.weapon)) { S.active_weapon_id.clear(); S.hide_reason = "unknown"; return Kind::UNKNOWN; }
    if (is_type(p.weapon, "app.WeaponMeleeCore") || is_type(p.weapon, "app.WeaponThrowableCore")) {
        S.active_weapon_id = "melee_type"; S.hide_reason = "melee"; return Kind::MELEE;
    }
    const std::string id = p.weapon_id.empty() ? std::string("armed") : weapons::canonical(p.weapon_id);
    S.active_weapon_id = id;
    if (id == "Hand" || id.find("BareHand") != std::string::npos || id == "ri3022_Inventory" || id == "ri3044_Inventory") {
        S.hide_reason = "melee"; return Kind::MELEE;
    }
    S.hide_reason.clear();
    return Kind::AMMO;
}
bool should_show() {   // should_show_ammo_hud
    const Kind k = classify();
    if (k == Kind::AMMO) S.show_ammo = true;
    else if (k == Kind::MELEE) S.show_ammo = false;
    return S.show_ammo;
}

// ---- the game's counter (resolve_weapon_info) ---------------------------------------------------------------------
MO* find_driver_in_handles(MO* gm) {   // find_remain_ammo_driver_from_handles
    MO* handles = call_ptr(gm, "get_guiHandles");
    if (!alive(handles)) return nullptr;
    const int n = call_direct<int>(handles, "get_Count", 0);
    for (int i = 0; i < n && i < 512; ++i) {
        MO* h = call_ptr(handles, "get_Item", {(void*)(intptr_t)i});
        if (!alive(h)) continue;
        MO* drv = call_ptr(h, "get_driver");
        if (is_remain_ammo_driver(drv)) return drv;
    }
    return nullptr;
}
MO* gui_comp_from_driver(MO* drv) {   // resolve_gui_comp_from_driver
    MO* ctrl = call_ptr(drv, "get_selfGUIController");
    if (!alive(ctrl)) return nullptr;
    MO* gui = call_ptr(ctrl, "get_Component");
    return alive(gui) ? gui : nullptr;
}
bool refresh_open_state() {
    if (!alive(S.wig)) return S.is_open = false;
    const bool suspended = call_direct<bool>(S.wig, "get_drawSuspend", false);
    const float timer = call_direct<float>(S.wig, "get_displayTimer", 0.0f);
    bool drawn = call_direct<bool>(S.wig, "get_isDrawSelf", false);
    if (!drawn && alive(S.go)) drawn = call_direct<bool>(S.go, "get_Draw", false);
    return S.is_open = !suspended || drawn || timer > 0.05f;
}
bool resolve(bool force) {
    if (!alive(S.gui_mgr)) S.gui_mgr = (MO*)API::get()->get_managed_singleton("app.GUIManager");
    if (!alive(S.gui_mgr)) { S.status = ST_NO_GUI_MANAGER; return false; }
    if (force || !alive(S.wig)) {
        MO* fresh = find_driver_in_handles(S.gui_mgr);
        if (!alive(fresh)) {
            MO* handle = call_ptr(S.gui_mgr, "findGUI", {(void*)(uintptr_t)ETHAN_REMAIN_AMMO_HASH});
            if (alive(handle)) fresh = call_ptr(handle, "get_driver");
        }
        if (!is_remain_ammo_driver(fresh)) { S.status = ST_NO_REMAIN_AMMO; clear_refs(); return false; }
        if (force || S.wig != fresh) {
            if (S.wig != fresh) LOGI("%s ammo hud: the game's counter found (%s)", TAG, type_name(fresh).c_str());
            S.wig = fresh;
            clear_hud_children();
        }
    }
    if (!alive(S.go)) S.go = call_ptr(S.wig, "get_GameObject");
    if (alive(S.go)) {
        const std::string n = read_string(call_ptr(S.go, "get_Name"));
        if (!n.empty()) S.go_name = n;
        if (!alive(S.xform)) S.xform = call_ptr(S.go, "get_Transform");
    }
    if (alive(S.wig) && !alive(S.gui_comp)) S.gui_comp = gui_comp_from_driver(S.wig);
    refresh_open_state();
    if (alive(S.wig) && alive(S.xform)) { S.status = ST_READY; return true; }
    S.status = ST_PARTIAL;
    return alive(S.wig);
}

bool is_ammo_go_name(const std::string& n) {
    return !n.empty() && (n == S.go_name || n == "GUIRemainAmmo" || n == "GUIPl4000RemainAmmo");
}

// ---- the world view (ensure_world_view, fix_screen_children_for_world) ---------------------------------------------
void fix_children(MO* view) {
    float hw = 0.0f, hh = 0.0f;
    if (auto* m = find_method_deep(view->get_type_definition(), "get_ScreenSize"); m != nullptr) {
        auto r = m->invoke(view, std::vector<void*>{});
        if (!r.exception_thrown) { float sz[2]{}; std::memcpy(sz, r.bytes.data(), sizeof sz); hw = sz[0] * 0.5f; hh = sz[1] * 0.5f; }
    }
    MO* child = call_ptr(view, "get_Child");
    for (int n = 0; alive(child) && n < 64; ++n) {
        const Vec3 at{hw, hh, 0.0f};
        call_direct<void*>(child, "set_Position", nullptr, (void*)&at);   // a value type goes by pointer
        child = call_ptr(child, "get_Next");
    }
}
void ensure_world_view(MO* gui) {
    if (!g_cfg.set_world_view || !alive(gui)) return;
    MO* view = call_ptr(gui, "get_View");
    if (!alive(view)) return;
    call_direct<void*>(view, "set_ViewType", nullptr, 1);
    call_direct<void*>(view, "set_Overlay", nullptr, true);
    call_direct<void*>(view, "set_Detonemap", nullptr, true);
    call_direct<void*>(view, "set_DepthTest", nullptr, true);
    fix_children(view);
}

// ---- keeping it open, hiding it, recovering it --------------------------------------------------------------------
void keep_drawn() {   // keep_ammo_drawn
    if (!alive(S.wig)) return;
    call_direct<void*>(S.wig, "setViewDrawState", nullptr, true);
    call_direct<void*>(S.wig, "set_drawSuspend", nullptr, false);
    call_direct<void*>(S.wig, "set_updateSuspend", nullptr, false);
    call_direct<void*>(S.wig, "set_displayTimer", nullptr, 30.0f);
    if (auto* p = field_ptr<bool>(S.wig, "<drawSuspend>k__BackingField")) *p = false;
    if (auto* p = field_ptr<bool>(S.wig, "<updateSuspend>k__BackingField")) *p = false;
    if (auto* p = field_ptr<float>(S.wig, "<displayTimer>k__BackingField")) *p = 30.0f;
    if (alive(S.gui_comp)) call_direct<void*>(S.gui_comp, "set_Enabled", nullptr, true);
    if (alive(S.go)) {
        call_direct<void*>(S.go, "set_DrawSelf", nullptr, true);
        call_direct<void*>(S.go, "set_UpdateSelf", nullptr, true);
        call_direct<void*>(S.go, "set_Draw", nullptr, true);
        call_direct<void*>(S.go, "set_Update", nullptr, true);
    }
    call_direct<void*>(S.wig, "applyToUI", nullptr);
    refresh_open_state();
}
void force_open(bool hard, bool bypass_weapon = false) {   // force_open_ammo_hud
    if (!weapon_mode()) return;
    if (!bypass_weapon && !should_show()) return;
    if (!g_cfg.keep_open || blocking_menu() || !alive(S.gui_mgr)) return;
    if (!alive(S.wig)) resolve(true);
    if (!alive(S.wig)) return;
    keep_drawn();   // Village's get_isDrawSelf stays false even when shown: always clear suspend / timer first
    const float now = now_s();
    if (!hard && now - S.last_open_t < g_cfg.force_open_interval_s) return;
    S.last_open_t = now;
    // The Lua also asked the counter's order object for cancelHide(), show(true) and showRemainAmmo(mode, item), each
    // inside pcall. None of those calls exists in that shape: the game's show / showRemainAmmo take one
    // app.GUIRequest.Parameter object and live on the driver, and there is no cancelHide (type_probe.txt,
    // 2026-10-18). In Lua they failed quietly every time; here the raw call passed `true` where an object was
    // expected, the game faulted on it every 2 s (this timer) and its half-finished GUI request list crashed it
    // minutes later (2026-10-22 23:19 dump). So the port does what the Lua effectively did: nothing here.
    if (!alive(S.gui_comp)) S.gui_comp = gui_comp_from_driver(S.wig);
    ensure_world_view(S.gui_comp);
    keep_drawn();
}
void force_hide(bool destructive) {   // force_hide_ammo_hud
    if (!alive(S.wig)) resolve(false);
    if (!alive(S.wig) || !destructive) return;
    call_direct<void*>(S.wig, "setViewDrawState", nullptr, false);
    call_direct<void*>(S.wig, "set_displayTimer", nullptr, 0.0f);
    S.is_open = false;
}
void recover(const std::string& reason) {   // recover_after_menu
    clear_refs();
    resolve(true);
    if (alive(S.wig)) { call_direct<void*>(S.wig, "reset", nullptr); resolve(true); }
    const float now = now_s();
    S.last_open_t = 0;
    S.last_recover_t = now;
    S.recover_t = 0;
    const bool must_open = reason == "menu_close" || reason == "show_edge" || reason == "draw_watchdog" ||
                           reason == "no_resolve" || reason == "pause_close" || reason == "hmd_edge";
    const Kind k = classify();
    const bool armed = k == Kind::AMMO ||
                       (k == Kind::UNKNOWN && !S.pre_menu_ammo_id.empty() && reason == "menu_close") ||
                       (k == Kind::UNKNOWN && !S.last_ammo_id.empty() && now - S.last_ammo_t < 0.40f);
    if (must_open && armed) {
        if (S.last_ammo_id.empty() && !S.pre_menu_ammo_id.empty()) { S.last_ammo_id = S.pre_menu_ammo_id; S.last_ammo_t = now; }
        S.show_ammo = S.was_show_ammo = true;
        S.hide_reason = "recover_force";
        force_open(true, true);
        if (alive(S.gui_comp)) ensure_world_view(S.gui_comp);
    } else if (must_open) {
        S.show_ammo = false;
        S.hide_reason = "recover_skip_melee";
    } else if (should_show()) {
        force_open(true);
        if (alive(S.gui_comp)) ensure_world_view(S.gui_comp);
    } else {
        force_hide(false);
    }
    LOGI("%s ammo hud: recovered (%s)", TAG, reason.c_str());
}
void schedule_recover(float delay_s, const char* reason, bool force) {
    const float now = now_s(), when = now + delay_s;
    if (!force && now - S.last_recover_t < 1.25f) return;
    if (S.recover_t > 0 && S.recover_t <= when) { S.recover_reason = reason; return; }
    S.recover_t = when;
    S.recover_reason = reason;
    S.recover_draw_count = S.draw_count;
}

// ---- where it goes (right_hand_world_pose, compute_attach_pose, apply_xform) ---------------------------------------
Quat quat_from_euler(float pitch_deg, float yaw_deg, float roll_deg) {   // glm::quat(vec3(pitch, yaw, roll)), as Lua's
    const float d = 3.14159265f / 180.0f;
    const float cx = std::cos(pitch_deg * d * 0.5f), sx = std::sin(pitch_deg * d * 0.5f);
    const float cy = std::cos(yaw_deg * d * 0.5f), sy = std::sin(yaw_deg * d * 0.5f);
    const float cz = std::cos(roll_deg * d * 0.5f), sz = std::sin(roll_deg * d * 0.5f);
    return qnorm(Quat{sx * cy * cz - cx * sy * sz, cx * sy * cz + sx * cy * sz, cx * cy * sz - sx * sy * cz, cx * cy * cz + sx * sy * sz});
}
// the right hand in the game world: the IK target (re8vr.right_hand_ik_transform), else re8vr's last right hand position
// with the controller's turn carried into the world
bool right_hand(Vec3& pos, Quat& rot) {
    if (player::get_pose(field_obj(player::now().ik_right, "Target"), pos, rot)) return true;
    if (!bridge::flag(bridge::S_HANDS_W_OK)) return false;
    pos = bridge::view_vec3(bridge::S_RHAND_W);
    if (!bridge::room_rot_to_world(bridge::view_quat(bridge::S_RROT), rot)) rot = Quat{0, 0, 0, 1};
    return true;
}
bool attach_pose(Vec3& pos, Quat& rot) {
    if (!right_hand(pos, rot)) return false;
    pos = pos + rotate(rot, Vec3{g_cfg.off_right, g_cfg.off_up, g_cfg.off_forward});
    rot = qnorm(qmul(rot, quat_from_euler(g_cfg.rot_pitch, g_cfg.rot_yaw, g_cfg.rot_roll)));
    return true;
}
// the transform's world matrix, written in place (the Lua wrote the same four rows at 0x80..0xB0)
bool apply_xform(MO* xform, Vec3 pos, Quat rot) {
    if (!alive(xform)) return false;
    const float s = g_cfg.scale;
    const Vec3 c0 = rotate(rot, Vec3{1, 0, 0}) * s, c1 = rotate(rot, Vec3{0, 1, 0}) * s, c2 = rotate(rot, Vec3{0, 0, 1}) * s;
    float* m = (float*)((uint8_t*)xform + 0x80);
    const float rows[16] = {c0.x, c0.y, c0.z, 0, c1.x, c1.y, c1.z, 0, c2.x, c2.y, c2.z, 0, pos.x, pos.y, pos.z, 1};
    std::memcpy(m, rows, sizeof rows);
    return true;
}
void tick_attach() {   // apply_manual_attach
    Vec3 pos;
    Quat rot;
    if (!weapon_mode() || !attach_pose(pos, rot)) return;
    ensure_world_view(S.gui_comp);
    if (apply_xform(S.xform, pos, rot)) ++S.apply_count;
}

// ---- the menu's buttons -------------------------------------------------------------------------------------------
void menu_commands() {
    static float seen = -1.0f;
    const float seq = bridge::view(bridge::S_HUD_CMD_SEQ);
    if (!bridge::has(seq) || seq == seen) return;
    const bool first = seen < 0.0f;
    seen = seq;
    if (first) return;   // whatever the menu last sent before this plugin started
    switch ((int)(bridge::view(bridge::S_HUD_CMD) + 0.5f)) {
    case 1: S.last_open_t = 0; S.is_open = false; force_open(true, true); LOGI("%s ammo hud: menu: open now", TAG); break;
    case 2: recover("ui"); break;
    case 3: clear_refs(); resolve(true); LOGI("%s ammo hud: menu: re-resolve", TAG); break;
    default: break;
    }
}
} // namespace

// ---- the frame (re.on_frame) --------------------------------------------------------------------------------------
void frame() {
    bridge::put(bridge::S_HUD_STATUS, (float)S.status);
    check_cfg_file();
    if (bridge::flag(bridge::S_MASTER_OFF)) return;
    menu_commands();
    const float now = now_s();

    const int hmd = bridge::live() ? 1 : 0;
    if (hmd == 1 && S.hmd_was == 0 && weapon_mode()) schedule_recover(0.25f, "hmd_edge", true);
    S.hmd_was = hmd;

    const bool blocking = blocking_menu();
    S.menu_blocking = blocking;
    Kind kind = Kind::MELEE;
    if (weapon_mode()) kind = classify();
    else S.hide_reason = "mode";

    bool show = false;
    if (blocking) {
        if (kind == Kind::AMMO) { S.lost_show_t = 0; S.last_ammo_id = S.active_weapon_id; S.last_ammo_t = now; }
        if (S.last_ammo_id.empty() && !S.pre_menu_ammo_id.empty()) { S.last_ammo_id = S.pre_menu_ammo_id; S.last_ammo_t = now; }
        show = !S.last_ammo_id.empty() || S.pre_menu_show || S.was_show_ammo;
        S.hide_reason = "menu_freeze";
    } else if (kind == Kind::AMMO) {
        S.lost_show_t = 0;
        S.last_ammo_id = S.active_weapon_id;
        S.last_ammo_t = now;
        show = true;
    } else if (kind == Kind::UNKNOWN) {
        show = !S.last_ammo_id.empty() && now - S.last_ammo_t < 0.40f;   // a weapon swap: a short grace
        S.hide_reason = show ? "unknown_grace" : "unknown_hide";
    } else {
        S.last_ammo_id.clear();
        if (S.was_show_ammo) {
            if (S.lost_show_t == 0) S.lost_show_t = now;
            if (now - S.lost_show_t < 0.12f) show = true;
        }
    }
    if (show && !S.was_show_ammo && weapon_mode() && !blocking) schedule_recover(0.10f, "show_edge", true);
    S.was_show_ammo = S.show_ammo = show;

    if (blocking && !S.menu_was_blocking) {
        S.menu_was_blocking = true;
        S.pre_menu_ammo_id = !S.last_ammo_id.empty() ? S.last_ammo_id : S.active_weapon_id;
        S.pre_menu_show = show || !S.last_ammo_id.empty() || kind == Kind::AMMO;
    } else if (!blocking && S.menu_was_blocking) {
        S.menu_was_blocking = false;
        if (weapon_mode()) schedule_recover(0.35f, "menu_close", true);
    }

    if (S.recover_t > 0 && now >= S.recover_t) {
        const std::string reason = S.recover_reason.empty() ? "timer" : S.recover_reason;
        const float draw_age = now - S.last_draw_t;
        const int drew_since = S.draw_count - S.recover_draw_count;
        S.recover_t = 0;
        S.recover_reason.clear();
        const bool must = reason == "menu_close" || reason == "show_edge" || reason == "no_resolve" || reason == "pause_close" || reason == "hmd_edge";
        const bool watchdog = reason == "draw_watchdog" && (drew_since < 5 || draw_age > 0.85f);
        if (weapon_mode() && !blocking_menu() && (must || (show && watchdog))) recover(reason);
    }
    if (S.recover_t > 0 && now < S.recover_t) { S.status = ST_RECOVER_PENDING; return; }

    if (now - S.last_poll_t >= g_cfg.poll_s) {
        S.last_poll_t = now;
        if (!resolve(false)) {
            if (g_cfg.display == Display::DEFAULT) S.status = ST_DEFAULT;
            if (weapon_mode() && show && !blocking && now - S.last_draw_t > 1.25f) schedule_recover(0.05f, "no_resolve", false);
        }
    }
    if (!alive(S.wig) && weapon_mode() && show) resolve(true);
    if (!alive(S.wig) && g_cfg.display != Display::DEFAULT) return;
    if (blocking) { S.status = ST_MENU_YIELD; return; }

    if (g_cfg.display == Display::OFF) {
        S.status = ST_OFF;
        force_hide(true);
    } else if (weapon_mode()) {
        if (!show) {
            S.status = ST_MELEE_HIDE;
            force_hide(false);
        } else {
            keep_drawn();
            const float draw_age = now - S.last_draw_t;
            if (draw_age > 1.25f) schedule_recover(0.05f, "draw_watchdog", false);
            else force_open(draw_age > 1.0f);
            tick_attach();
            if (S.status != ST_READY && S.status != ST_PARTIAL) S.status = ST_WEAPON;
        }
    } else {
        S.status = ST_DEFAULT;
    }
}

// ---- each GUI element before it is drawn (re.on_pre_gui_draw_element) --------------------------------------------
bool pre_gui_draw(void* element, void*) {
    static const char* PAUSE_GUI[] = {"GUIPause", "GUIInventoryMenu", "GUISaveLoad", "GUIInventory", "GUIInventoryTreasure",
                                      "GUIInventoryCraft", "GUIInventoryKeyItem", "GUIMainMenu", "GUIDialog"};
    MO* go = call_ptr((MO*)element, "get_GameObject");
    if (!alive(go)) return true;
    const std::string name = read_string(call_ptr(go, "get_Name"));
    for (const char* p : PAUSE_GUI) if (name == p) { S.pause_gui_time = now_s(); break; }
    if (!is_ammo_go_name(name)) return true;
    if (g_cfg.display == Display::OFF) return false;
    if (g_cfg.display != Display::WEAPON) return true;
    if (!S.show_ammo || S.menu_blocking || blocking_menu() || S.recover_t > 0) return false;
    if (!alive(S.go) || S.go != go) {
        S.go = go;
        S.go_name = name;
        S.xform = call_ptr(go, "get_Transform");
        if (alive(S.wig)) S.gui_comp = gui_comp_from_driver(S.wig);
        if (!alive(S.gui_comp)) S.gui_comp = component(go, "via.gui.GUI");
    }
    ensure_world_view(S.gui_comp);
    Vec3 pos;
    Quat rot;
    if (attach_pose(pos, rot) && apply_xform(S.xform != nullptr ? S.xform : call_ptr(go, "get_Transform"), pos, rot)) {
        ++S.draw_count;
        S.last_draw_t = now_s();
    }
    return true;
}

} // namespace vn::ammo_hud
