// base.cpp -- see base.h
#include "base.h"

#include <windows.h>

#include <chrono>
#include <cstring>
#include <map>

namespace vr8 {

const REFrameworkPluginInitializeParam* g_param = nullptr;

namespace {
constexpr int MAX_THROWS = 2;            // rule 6: a call that throws twice is switched off
constexpr int STRING_LENGTH_AT = 0x10;   // System.String: the length, then UTF-16 text (read from b178, RE Engine)
constexpr int STRING_TEXT_AT = 0x14;
constexpr int STRING_MAX = 512;
constexpr int PARENT_DEPTH = 12;         // how far up the type chain a field is looked for

API::Field* find_field_deep(API::TypeDefinition* td, std::string_view name) {
    for (int i = 0; td != nullptr && i < PARENT_DEPTH; ++i) {
        if (auto* f = td->find_field(name)) return f;
        td = td->get_parent_type();
    }
    return nullptr;
}
} // namespace

float now_s() {
    static const auto t0 = std::chrono::steady_clock::now();
    return std::chrono::duration<float>(std::chrono::steady_clock::now() - t0).count();
}

bool is_managed(void* p) {
    return p != nullptr && API::get()->sdk()->managed_object->is_managed_object(p);
}

std::string type_name(MO* o) {
    if (o == nullptr) return "null";
    if (!is_managed(o)) return "stale";
    auto* td = o->get_type_definition();
    return td != nullptr ? td->get_full_name() : "?";
}

MO* field_obj(MO* o, std::string_view field) {
    if (!is_managed(o)) return nullptr;
    auto* f = find_field_deep(o->get_type_definition(), field);
    if (f == nullptr) return nullptr;
    auto** p = (MO**)f->get_data_raw(o, false);
    return p != nullptr && is_managed(*p) ? *p : nullptr;
}

std::string read_string(void* s) {
    if (!is_managed(s) || type_name((MO*)s) != "System.String") return "";
    const auto len = *(const int32_t*)((const char*)s + STRING_LENGTH_AT);
    const auto* w = (const wchar_t*)((const char*)s + STRING_TEXT_AT);
    if (len <= 0 || len > STRING_MAX) return "";
    const int n = WideCharToMultiByte(CP_UTF8, 0, w, len, nullptr, 0, nullptr, nullptr);
    std::string out(n > 0 ? n : 0, '\0');
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w, len, out.data(), n, nullptr, nullptr);
    return out;
}

MO* managed_string(const wchar_t* text) {
    static std::map<std::wstring, MO*> made;   // rule 7: one hold per text, by this one owner, for the whole run
    auto it = made.find(text);
    if (it != made.end()) return it->second;
    auto* s = API::get()->create_managed_string(text);
    if (s != nullptr) s->add_ref();
    return made[text] = s;
}

bool Call::usable() {
    if (m_off) return false;
    if (m_looked) return m_found != nullptr;
    m_looked = true;
    m_found = API::get()->tdb()->find_method(m_type, m_method);
    if (m_found == nullptr) {
        LOGW("%s call off: %s.%s was not found", TAG, m_type, m_method);
        return false;
    }
    if (m_found->get_num_params() != m_params) {
        LOGW("%s call off: %s.%s takes %u parameters, %u were expected", TAG, m_type, m_method,
             m_found->get_num_params(), m_params);
        m_found = nullptr;
        return false;
    }
    return true;
}

void Call::threw() {
    if (++m_throws < MAX_THROWS) return;
    m_off = true;
    LOGW("%s call off: %s.%s threw %d times", TAG, m_type, m_method, m_throws);
}

MO* Call::ptr(void* self, std::vector<void*> args) {
    if (self == nullptr || args.size() != m_params || !usable()) return nullptr;
    auto r = m_found->invoke((MO*)self, args);
    if (r.exception_thrown) { threw(); return nullptr; }
    return (MO*)r.ptr;
}

bool Call::value(void* self, void* out, size_t size, std::vector<void*> args) {
    if (self == nullptr || args.size() != m_params || !usable()) return false;
    auto r = m_found->invoke((MO*)self, args);
    if (r.exception_thrown) { threw(); return false; }
    if (size > r.bytes.size()) return false;
    std::memcpy(out, r.bytes.data(), size);
    return true;
}

bool Call::set_value(void* self, const void* value) {
    if (self == nullptr || value == nullptr || m_params != 1 || !usable()) return false;
    m_found->call<void>(API::get()->get_vm_context(), self, (void*)value);
    return true;
}

MO* component(MO* go, const char* type) {
    if (!is_managed(go)) return nullptr;
    auto* rt = API::get()->typeof(type);
    if (rt == nullptr) return nullptr;
    // only the System.Type overload is a real function; the plain name has generic stubs (b178, 2026-09-04)
    static Call get_component("via.GameObject", "getComponent(System.Type)", 1);
    return get_component.ptr(go, {rt});
}

} // namespace vr8
