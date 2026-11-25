// paths.h -- rebuild 2: where the mod's own files are. The game folder is looked up from the running exe, never
// written into the source (the iron rule: no home path, no login anywhere).
#pragma once

#include <windows.h>

#include <string>

namespace vr8::paths {

// <game folder>\reframework\data\visceral_re8\<name>
inline std::wstring data(const wchar_t* name) {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring path(exe);
    path = path.substr(0, path.find_last_of(L"\\/") + 1);
    return path + L"reframework\\data\\visceral_re8\\" + name;
}

} // namespace vr8::paths
