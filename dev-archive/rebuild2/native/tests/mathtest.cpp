// mathtest.cpp -- rebuild 2: the frame's own maths, checked against sums built another way (the SHIPPED base.cpp
// is compiled in, not a copy). Run by tools/build.sh --test. 2026-11-26.
#include "../src/base.h"

#include <cstdio>
#include <cstdlib>

using namespace vr8;

static int g_bad = 0;
static void near_eq(const char* what, Vec3 a, Vec3 b) {
    if (length(a - b) > 1e-4f) { ++g_bad; std::printf("FAIL %s: %f %f %f, wanted %f %f %f\n", what, a.x, a.y, a.z, b.x, b.y, b.z); }
}
// the same turn through the rotation matrix of a unit quaternion (the textbook form), not through rotate()'s sums
static Vec3 by_matrix(Quat q, Vec3 v) {
    const float xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z, xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z,
                wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;
    return {(1 - 2 * (yy + zz)) * v.x + 2 * (xy - wz) * v.y + 2 * (xz + wy) * v.z,
            2 * (xy + wz) * v.x + (1 - 2 * (xx + zz)) * v.y + 2 * (yz - wx) * v.z,
            2 * (xz - wy) * v.x + 2 * (yz + wx) * v.y + (1 - 2 * (xx + yy)) * v.z};
}

int main() {
    const float PI = 3.14159265f;
    // a quarter turn about up takes +X to -Z: the door leaf's rule ("the leaf at yaw t lies along (cos t, 0, -sin t)")
    const Quat quarter{0.0f, std::sin(PI / 4), 0.0f, std::cos(PI / 4)};
    near_eq("quarter turn of +X", rotate(quarter, {1, 0, 0}), {0, 0, -1});
    for (int deg = -170; deg <= 170; deg += 17) {
        const float t = deg * PI / 180.0f;
        near_eq("leaf at yaw t", rotate({0.0f, std::sin(t / 2), 0.0f, std::cos(t / 2)}, {1, 0, 0}), {std::cos(t), 0, -std::sin(t)});
    }
    std::srand(7);
    for (int i = 0; i < 200; ++i) {
        auto r = []() { return (float)std::rand() / RAND_MAX * 2.0f - 1.0f; };
        Quat q{r(), r(), r(), r()};
        const float n = std::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
        if (n < 0.1f) continue;
        q = {q.x / n, q.y / n, q.z / n, q.w / n};
        const Vec3 v{r() * 3, r() * 3, r() * 3};
        near_eq("rotate against the matrix", rotate(q, v), by_matrix(q, v));
        near_eq("there and back", rotate(conjugate(q), rotate(q, v)), v);
    }
    std::printf(g_bad == 0 ? "mathtest: all checks pass\n" : "mathtest: %d FAILED\n", g_bad);
    return g_bad == 0 ? 0 : 1;
}
