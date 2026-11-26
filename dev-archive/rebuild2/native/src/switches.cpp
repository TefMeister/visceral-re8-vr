// switches.cpp -- see switches.h
#include "switches.h"

#include "base.h"
#include "paths.h"

#include <fstream>
#include <set>
#include <string>

namespace vr8::switches {

namespace {
std::set<std::string> g_names;
std::string g_all;
void read_once() {
    static bool read = false;
    if (read) return;
    read = true;
    std::ifstream f(paths::data(L"off.txt"));
    std::string word;
    while (f >> word) {
        if (word.empty() || word[0] == '#') continue;
        g_names.insert(word);
        g_all += (g_all.empty() ? "" : " ") + word;
    }
    if (!g_names.empty()) LOGI("%s OFF (off.txt): %s", TAG, g_all.c_str());
}
} // namespace

bool off(const char* part) {
    read_once();
    return g_names.count(part) != 0;
}

const char* all() {
    read_once();
    return g_all.c_str();
}

} // namespace vr8::switches
