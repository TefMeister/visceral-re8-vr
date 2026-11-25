// switches.cpp -- see switches.h
#include "switches.h"

#include "base.h"
#include "paths.h"

#include <fstream>
#include <set>
#include <string>

namespace vr8::switches {

bool off(const char* part) {
    static std::set<std::string> names;
    static bool read = false;
    if (!read) {
        read = true;
        std::ifstream f(paths::data(L"off.txt"));
        std::string word, all;
        while (f >> word) {
            if (word.empty() || word[0] == '#') continue;
            names.insert(word);
            all += word + " ";
        }
        if (!names.empty()) LOGI("%s OFF (off.txt): %s", TAG, all.c_str());
    }
    return names.count(part) != 0;
}

} // namespace vr8::switches
