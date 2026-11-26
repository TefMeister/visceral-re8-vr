// base.h -- Visceral RE8, rebuild 2 (2026-11-26): logging, small maths and the CHECKED calls into the game.
//
// Written fresh for rebuild 2 (design note 2026-11-25d). The reference read for it: b178's common.h / common.cpp and
// joints.h. What is kept from there is the knowledge, each piece named where it is used; no file was copied.
//
// RULE 6 lives here: every call into the game is found once, its parameter count checked, and a call that throws
// twice in a row RESTS for a few seconds before it is tried again (b178: the crash of 2026-10-22 and the flood
// of 113,905 error lines). Until 2026-11-26 it was switched off for the whole run: when the prologue ended, the
// dying player object threw twice on get_Transform and every part that needs the player stood down for good
// (Tefa's clips of that run: idle hands at the face, hands that open no door).
#pragma once

#include <cmath>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "reframework/API.hpp"

namespace vr8 {

using API = reframework::API;
using MO = reframework::API::ManagedObject;

extern const REFrameworkPluginInitializeParam* g_param;
constexpr const char* TAG = "[visceral-re8]";

#define VR8_LOG(fn, ...) do { if (vr8::g_param && vr8::g_param->functions && vr8::g_param->functions->fn) vr8::g_param->functions->fn(__VA_ARGS__); } while (0)
#define LOGI(...) VR8_LOG(log_info, __VA_ARGS__)
#define LOGW(...) VR8_LOG(log_warn, __VA_ARGS__)

struct Vec3 { float x, y, z; };
struct Quat { float x, y, z, w; };

inline Vec3 operator-(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline float length(Vec3 v) { return std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z); }

float now_s();                                  // seconds since the plugin loaded (steady clock)

// REFramework's own test (readable memory, a type that points back at itself): false for null and for an object a
// load has freed. Every helper below asks it before it reads a managed object's type.
bool is_managed(void* p);
std::string type_name(MO* o);
MO* field_obj(MO* o, std::string_view field);   // a reference-type field, or nullptr
std::string read_string(void* system_string);   // a System.String as UTF-8 ("" if it is not one)
MO* managed_string(const wchar_t* text);        // one per text, made once and kept (add_ref'd by us, never released)

// ---- checked calls (rule 6) -----------------------------------------------------------------------------------
// A Call is one method of one type, by name and parameter count. It is looked up on first use. It reports "not
// usable" when the method is missing or the count differs (for good, logged once), and for REST_S seconds
// after it has thrown MAX_THROWS times in a row (logged the first few times).
class Call {
public:
    Call(const char* type, const char* method, uint32_t params) : m_type(type), m_method(method), m_params(params) {}
    // object / pointer result (nullptr on any failure)
    MO* ptr(void* self, std::vector<void*> args = {});
    // a value-type result copied out of the return bytes (Vec3, Quat); false on any failure
    bool value(void* self, void* out, size_t size, std::vector<void*> args = {});
    // a call with no result that takes ONE value type by pointer (the x64 ABI passes value types that way):
    // via.Joint.set_LocalRotation and the like. Works on native objects (joints, transforms) too.
    bool set_value(void* self, const void* value);

private:
    bool usable();
    void threw();
    const char* m_type;
    const char* m_method;
    uint32_t m_params;
    API::Method* m_found = nullptr;
    bool m_looked = false;
    bool m_off = false;
    int m_throws = 0;
    float m_rest_until = 0.0f;
    int m_rests = 0;
};

MO* component(MO* game_object, const char* type);   // getComponent(System.Type), nullptr when absent or stale

// ---- checked calls on an object whose type is only known when it is met (2026-11-26, doors) ---------------------
// The method is looked up on the object's OWN type (a list the scene hands back, a component of some derived
// kind). Same rule 6: found once per (type, method), parameter count checked, switched off after it threw twice.
MO* dyn_ptr(MO* self, const char* method, std::vector<void*> args = {});
bool dyn_value(MO* self, const char* method, void* out, size_t size, std::vector<void*> args = {});

// a value-type field's bytes inside a managed object (a float, a bool, a number), or nullptr
void* field_data(MO* o, std::string_view field);

inline Vec3 operator+(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Quat conjugate(Quat q) { return {-q.x, -q.y, -q.z, q.w}; }
Vec3 rotate(Quat q, Vec3 v);                        // v turned by the unit quaternion q

} // namespace vr8
