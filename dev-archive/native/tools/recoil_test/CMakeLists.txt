# The recoil numeric test (no game): builds recoil_test.cpp, which includes the shipped src/recoil.cpp.
#   cmake -S . -B build -G "Visual Studio 17 2022" -A x64 && cmake --build build --config Release
cmake_minimum_required(VERSION 3.20)
project(recoil_test CXX)
set(CMAKE_CXX_STANDARD 20)
add_executable(recoil_test recoil_test.cpp ../../src/json_mini.cpp)
target_include_directories(recoil_test PRIVATE ../../include ../../src)
target_compile_definitions(recoil_test PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
if(MSVC)
    target_compile_options(recoil_test PRIVATE /W4 /utf-8 /wd4267 /wd4189 /wd4505)
endif()
