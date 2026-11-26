cmake_minimum_required(VERSION 3.20)
project(visceral_re8 C CXX)

# Visceral RE8, rebuild 2 (2026-11-26): a REFramework plugin for praydog's nightly. VS2022 Build Tools.
# tools/build.sh builds it, checks the exports and the rule-set scans, and installs through tools/install.sh.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(visceral_re8 SHARED
    src/plugin.cpp
    src/base.cpp
    src/switches.cpp
    src/bridge.cpp
    src/ready.cpp
    src/jointwriter.cpp
    src/fingers.cpp
    src/carryarms.cpp
    src/gamearms.cpp
    src/gate.cpp
    src/doors.cpp
    src/doorsounds.cpp
    src/bodyturn.cpp
    src/sleephands.cpp
    src/spinestill.cpp)
target_include_directories(visceral_re8 PRIVATE include src)
set_target_properties(visceral_re8 PROPERTIES OUTPUT_NAME "visceral_re8" PREFIX "")
target_compile_definitions(visceral_re8 PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
if(MSVC)
    target_compile_options(visceral_re8 PRIVATE /W4 /utf-8 /wd4267 /wd4189)   # two warnings inside praydog's API.hpp
    target_link_options(visceral_re8 PRIVATE "/Brepro")                        # same source, same hash
endif()

# the frame's maths against sums built another way (tools/build.sh --test); not part of the plugin
add_executable(mathtest EXCLUDE_FROM_ALL tests/mathtest.cpp src/base.cpp)
target_include_directories(mathtest PRIVATE include src)
target_compile_definitions(mathtest PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
if(MSVC)
    target_compile_options(mathtest PRIVATE /utf-8 /wd4267 /wd4189)
endif()
