cmake_minimum_required(VERSION 3.20)
project(visceral_re8_native C CXX)

# Visceral RE8's native code (2026-10-15): a REFramework plugin, API 1.15 (the DLSS build 76298bd Village runs).
# VS2022 Build Tools; tools/build.sh builds and checks the exports. Same shape as visceral-re2-vr's native code.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(visceral_re8_native SHARED
    src/plugin.cpp
    src/common.cpp
    src/bridge.cpp
    src/haptics.cpp
    src/player.cpp
    src/recoil.cpp
    src/json_mini.cpp)
target_include_directories(visceral_re8_native PRIVATE include src)
set_target_properties(visceral_re8_native PROPERTIES OUTPUT_NAME "visceral_re8_native" PREFIX "")
target_compile_definitions(visceral_re8_native PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
if(MSVC)
    target_compile_options(visceral_re8_native PRIVATE /W4 /utf-8 /wd4267 /wd4189)   # two warnings inside praydog API.hpp
    target_link_options(visceral_re8_native PRIVATE "/Brepro")                # reproducible: same source, same hash
endif()
