// lookup.cpp -- see lookup.h
#include "lookup.h"
#include "common.h"

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace vn::lookup {

namespace {
std::filesystem::path dir() {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    return std::filesystem::path(exe).parent_path() / "reframework" / "data" / "visceral_re8";
}
std::filesystem::file_time_type g_mtime{};
ULONGLONG g_check = 0;

std::string lower(std::string s) { std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); }); return s; }
std::string tname(API::TypeDefinition* t) { return t != nullptr ? t->get_full_name() : std::string("?"); }

API::TypeDefinition* find_type(const std::string& full) {
    auto* tdb = API::get()->tdb();
    if (auto* t = tdb->find_type(full)) return t;
    const auto n = tdb->get_num_types();
    for (uint32_t i = 0; i < n; ++i) { auto* t = tdb->get_type(i); if (t != nullptr && t->get_full_name() == full) return t; }
    return nullptr;
}

void describe(std::ostringstream& o, API::TypeDefinition* t, bool parents, const std::string& member) {
    for (int depth = 0; t != nullptr && depth < 12; ++depth) {
        o << "== " << tname(t) << "\n";
        for (auto* m : t->get_methods()) {
            if (m == nullptr) continue;
            const std::string nm = m->get_name();
            if (!member.empty() && lower(nm).find(member) == std::string::npos) continue;
            o << "  " << (m->is_static() ? "static " : "") << tname(m->get_return_type()) << " " << nm << "(";
            bool first = true;
            for (const auto& p : m->get_params()) { o << (first ? "" : ", ") << tname((API::TypeDefinition*)p.t) << " " << (p.name ? p.name : ""); first = false; }
            o << ")\n";
        }
        for (auto* f : t->get_fields()) {
            if (f == nullptr) continue;
            const std::string nm = f->get_name();
            if (!member.empty() && lower(nm).find(member) == std::string::npos) continue;
            o << "  field " << (f->is_static() ? "static " : "") << tname(f->get_type()) << " " << nm << " @0x" << std::hex << f->get_offset_from_base() << std::dec << "\n";
        }
        if (!parents) break;
        t = t->get_parent_type();
    }
}

void answer(const std::vector<std::string>& asks) {
    std::ostringstream o;
    auto* tdb = API::get()->tdb();
    const auto n = tdb->get_num_types();
    for (const auto& raw : asks) {
        std::string a = raw;
        while (!a.empty() && (a.back() == '\r' || a.back() == ' ')) a.pop_back();
        if (a.empty() || a[0] == '#') continue;
        o << ">>> " << a << "\n";
        if (a.rfind("type:", 0) == 0 || a.rfind("tree:", 0) == 0) {   // type:Full.Name[/member part] -- one type; tree: with its parents
            const bool parents = a[0] == 't' && a[1] == 'r';
            std::string full = a.substr(5), member;
            if (const auto sl = full.find('/'); sl != std::string::npos) { member = lower(full.substr(sl + 1)); full = full.substr(0, sl); }
            auto* t = find_type(full);
            if (t == nullptr) o << "  NOT FOUND\n";
            else describe(o, t, parents, member);
        } else if (a.rfind("member:", 0) == 0) {   // member:part -- every type with a method or field whose name holds it
            const std::string want = lower(a.substr(7));
            int hits = 0;
            for (uint32_t i = 0; i < n && hits < 300; ++i) {
                auto* t = tdb->get_type(i);
                if (t == nullptr) continue;
                bool any = false;
                for (auto* m : t->get_methods()) if (m != nullptr && lower(m->get_name()).find(want) != std::string::npos) { if (!any) o << tname(t) << ":"; o << " " << m->get_name() << "()"; any = true; }
                for (auto* f : t->get_fields()) if (f != nullptr && lower(f->get_name()).find(want) != std::string::npos) { if (!any) o << tname(t) << ":"; o << " ." << f->get_name(); any = true; }
                if (any) { o << "\n"; ++hits; }
            }
            if (hits == 0) o << "  nothing\n";
        } else {   // a part of a type name
            const std::string want = lower(a);
            int hits = 0;
            for (uint32_t i = 0; i < n && hits < 300; ++i) {
                auto* t = tdb->get_type(i);
                if (t == nullptr) continue;
                const std::string full = t->get_full_name();
                if (lower(full).find(want) != std::string::npos) { o << "  " << full << "\n"; ++hits; }
            }
            if (hits == 0) o << "  nothing\n";
        }
        o << "\n";
    }
    std::ofstream out(dir() / "lookup_answer.txt", std::ios::binary | std::ios::trunc);
    out << o.str();
    LOGI("%s lookup: answered %zu question line(s) into lookup_answer.txt", TAG, asks.size());
}
} // namespace

void frame() {
    const ULONGLONG now = GetTickCount64();
    if (now - g_check < 500) return;
    g_check = now;
    std::error_code ec;
    const auto p = dir() / "lookup_ask.txt";
    const auto mt = std::filesystem::last_write_time(p, ec);
    if (ec || mt == g_mtime) return;
    g_mtime = mt;
    std::ifstream in(p, std::ios::binary);
    std::vector<std::string> asks;
    for (std::string line; std::getline(in, line);) asks.push_back(line);
    answer(asks);
}

} // namespace vn::lookup
