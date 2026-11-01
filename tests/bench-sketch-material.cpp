// The same CPU-only workload can be built against two material headers.
// This does not read tablet input, touch a framebuffer or load the native app.
#ifndef MATERIAL_HEADER
#define MATERIAL_HEADER "../product/payload/apps/papersketch/native/sketch-material.h"
#endif
#include MATERIAL_HEADER
#include <chrono>
#include <cstdio>

struct Bench {
    PaperMaterial paper;
    std::vector<uint32_t> mass, image;
    std::vector<uint16_t> finger;
    Bench() : mass(320 * 320), image(320 * 320, 0xffffffffu), finger(82 * 81) {
        paper.init(320, 320);
    }
};

int main() {
    Bench bench;
    bench.paper.segment(bench.mass.data(), bench.image.data(), bench.finger.data(),
                        4, 24, 0, 1, 160, 20, 1, 160, 20, 1, 0);
    bench.paper.segment(bench.mass.data(), bench.image.data(), bench.finger.data(),
                        4, 24, 0, 1, 160, 20, 1, 160, 300, 1, 1);
    std::vector<long> pencil, smudge;
    for (int i = 0; i < 2500; ++i) {
        double x = 80 + (i % 100) * 1.5;
        auto start = std::chrono::steady_clock::now();
        bench.paper.segment(bench.mass.data(), bench.image.data(), bench.finger.data(),
                            7, 64, 0, 1, x, 160, .7, x + 1.5, 160, .7, 1);
        auto middle = std::chrono::steady_clock::now();
        bench.paper.segment(bench.mass.data(), bench.image.data(), bench.finger.data(),
                            2, 24, 0, 1, x, 60, .7, x + 1.5, 60, .7, 1);
        auto finish = std::chrono::steady_clock::now();
        if (i >= 500) {
            smudge.push_back(std::chrono::duration_cast<std::chrono::nanoseconds>(middle - start).count());
            pencil.push_back(std::chrono::duration_cast<std::chrono::nanoseconds>(finish - middle).count());
        }
    }
    std::sort(pencil.begin(), pencil.end());
    std::sort(smudge.begin(), smudge.end());
    printf("{\"smudge_p50_us\":%.3f,\"smudge_p95_us\":%.3f,"
           "\"pencil_p50_us\":%.3f,\"pencil_p95_us\":%.3f}\n",
           smudge[1000] / 1000., smudge[1900] / 1000., pencil[1000] / 1000., pencil[1900] / 1000.);
}
