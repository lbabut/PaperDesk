#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <chrono>
#include <cstdio>
#include <limits>
#include <numeric>

struct Fixture {
    PaperMaterial p;
    std::vector<uint32_t> m, img;
    std::vector<uint16_t> finger;
    Fixture() : m(320 * 320), img(320 * 320, 0xffffffffu), finger(82 * 81) { p.init(320, 320); }
    void point(int tool, double x, double y, double pressure = 1, int size = 24,
               double tone = 0, double strength = 1) {
        p.dab(m.data(), img.data(), finger.data(), tool, size, tone, strength, x, y, pressure);
    }
    void segment(int tool, double ax, double ay, double ap, double bx, double by,
                 double bp, int index, int size = 24) {
        p.segment(m.data(), img.data(), finger.data(), tool, size, 0, 1,
                  ax, ay, ap, bx, by, bp, index);
    }
    void line(int tool, double ax, double ay, double bx, double by, double pressure = 1, int size = 24) {
        segment(tool, ax, ay, pressure, ax, ay, pressure, 0, size);
        segment(tool, ax, ay, pressure, bx, by, pressure, 1, size);
    }
    uint64_t pageMass() const {
        uint64_t sum = 0;
        for (auto v : m) sum += (v >> 16) + (v & 65535);
        return sum;
    }
    uint64_t mass() const {
        return pageMass() + std::accumulate(finger.begin(), finger.end(), uint64_t(0));
    }
    uint64_t loose() const {
        uint64_t sum = 0;
        for (auto v : m) sum += v & 65535;
        return sum;
    }
    int gray(int x, int y) const { return img[y * 320 + x] & 255; }
    void consistent() const {
        for (size_t i = 0; i < m.size(); ++i) {
            unsigned total = (m[i] >> 16) + (m[i] & 65535);
            assert(total <= 65535);
            assert(img[i] == (0xff000000u | uint32_t(p.optical[total]) * 0x010101u));
        }
        for (int y = 0; y <= 80; ++y) assert(finger[y * 82 + 81] == 0);
    }
};

static void testPencilsAndPaper() {
    Fixture tiny;
    tiny.line(1, 160, 160, 160, 160, 1, 1);
    assert(tiny.mass() > 0);
    Fixture soft, firm;
    soft.line(1, 60, 160, 260, 160, .4, 20);
    firm.line(1, 60, 160, 260, 160, .9, 20);
    assert(firm.mass() > soft.mass() * 3);
    Fixture pale, dark;
    pale.point(2, 160, 160, 1, 24, 200);
    dark.point(2, 160, 160);
    assert(dark.mass() > pale.mass() * 4);
    uint64_t previous = dark.mass();
    for (int i = 0; i < 100; ++i) {
        dark.point(2, 160, 160);
        assert(dark.mass() >= previous);
        previous = dark.mass();
    }
    dark.consistent();
    // The paper texture stays fixed while layers accumulate.
    assert(dark.gray(159, 159) != dark.gray(160, 160));
}

static void testNoContactAndInvalidInput() {
    Fixture original;
    original.line(4, 160, 80, 160, 240);
    original.line(7, 100, 160, 220, 160, 1, 64);
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double infinity = std::numeric_limits<double>::infinity();
    for (int tool = 0; tool <= 7; ++tool) {
        Fixture unchanged = original;
        unchanged.point(tool, 160, 160, 0);
        unchanged.point(tool, 160, 160, -1);
        unchanged.point(tool, 160, 160, 1, 24, 0, 0);
        unchanged.point(tool, nan, 160);
        unchanged.point(tool, 160, 160, infinity);
        unchanged.point(tool, 1e100, 160);
        unchanged.point(tool, 160, 160, 1, 24, nan);
        unchanged.segment(tool, 160, 160, 1, 200, 160, nan, 1);
        assert(unchanged.m == original.m && unchanged.img == original.img && unchanged.finger == original.finger);
        assert(unchanged.p.burnish == original.p.burnish && unchanged.p.wear == original.p.wear);
    }
    original.point(-1, 160, 160);
    original.point(9, 160, 160);
    original.consistent();
}

static void testPigmentTransport() {
    Fixture white;
    white.line(7, 60, 160, 260, 160, .7, 64);
    assert(white.mass() == 0 && white.gray(160, 160) == 255);
    Fixture hb, coal;
    hb.line(1, 160, 80, 160, 240);
    coal.line(4, 160, 80, 160, 240);
    assert(coal.loose() > hb.loose() * 2);
    auto sum = coal.mass();
    int core = coal.gray(160, 160);
    coal.line(7, 100, 160, 240, 160, 1, 64);
    assert(coal.mass() == sum && coal.gray(160, 160) > core && coal.gray(195, 160) < 255);
    // A lifted finger retains pigment and can mark a clean part of the page.
    auto onFinger = std::accumulate(coal.finger.begin(), coal.finger.end(), uint64_t(0));
    assert(onFinger > 0);
    coal.line(7, 100, 280, 240, 280, 1, 64);
    assert(coal.mass() == sum && coal.gray(160, 280) < 255);
    coal.consistent();
    Fixture light, heavy;
    light.line(4, 160, 80, 160, 240);
    heavy = light;
    light.line(7, 100, 160, 240, 160, .1, 64);
    heavy.line(7, 100, 160, 240, 160, 1, 64);
    assert(heavy.gray(160, 160) > light.gray(160, 160));
    sum = hb.mass();
    hb.line(6, 160, 80, 160, 240, 1, 40);
    assert(hb.mass() < sum / 2);
    hb.consistent();
    // Fully loaded paper and fingertip must never overflow either compartment.
    Fixture full;
    std::fill(full.m.begin(), full.m.end(), (uint32_t(30000) << 16) | 35535);
    std::fill(full.img.begin(), full.img.end(), 0xff000000u | uint32_t(full.p.optical[65535]) * 0x010101u);
    for (int y = 0; y <= 80; ++y) for (int x = 0; x <= 80; ++x) full.finger[y * 82 + x] = 65535;
    sum = full.mass();
    for (int i = 0; i < 10; ++i) full.line(7, 0, i * 30, 320, i * 30, 1, 80);
    assert(full.mass() == sum);
    full.consistent();
}

static void testFriction() {
    Fixture light, firm;
    light.finger[40 * 82 + 40] = 60000;
    firm = light;
    auto mass = light.mass();
    light.point(7, 160, 160, .1, 80);
    firm.point(7, 160, 160, 1, 80);
    assert(light.mass() == mass && firm.mass() == mass);
    assert(firm.finger[40 * 82 + 40] < light.finger[40 * 82 + 40]);
}

static void testResampling() {
    Fixture sparse, dense;
    sparse.line(1, 60, 160, 260, 160, 1, 20);
    dense.segment(1, 60, 160, 1, 60, 160, 1, 0, 20);
    for (int x = 62; x <= 260; x += 2) dense.segment(1, x - 2, 160, 1, x, 160, 1, 1, 20);
    assert(sparse.m == dense.m);
    // Sub-.001 pixel input events used to lose their entire traveled distance.
    Fixture micro, whole;
    whole.line(4, 60, 160, 64, 160);
    micro.segment(4, 60, 160, 1, 60, 160, 1, 0);
    for (int i = 1; i <= 16384; ++i)
        micro.segment(4, 60 + (i - 1) / 4096.0, 160, 1, 60 + i / 4096.0, 160, 1, 1);
    assert(whole.m == micro.m);
    assert(whole.p.burnish == micro.p.burnish && whole.p.wear == micro.p.wear);
    Fixture ramp, split;
    ramp.segment(2, 32, 160, .125, 32, 160, .125, 0);
    ramp.segment(2, 32, 160, .125, 288, 160, 1, 1);
    split.segment(2, 32, 160, .125, 32, 160, .125, 0);
    for (int i = 1; i <= 512; ++i)
        split.segment(2, 32 + (i - 1) * .5, 160, .125 + .875 * (i - 1) / 512,
                      32 + i * .5, 160, .125 + .875 * i / 512, 1);
    assert(ramp.m == split.m && ramp.img == split.img);
    assert(ramp.p.burnish == split.p.burnish && ramp.p.wear == split.p.wear);
    // Smudging has the same sampling guarantee, including fingertip state.
    sparse.line(4, 160, 80, 160, 240);
    dense = sparse;
    sparse.line(7, 60, 160, 260, 160, .7, 64);
    dense.segment(7, 60, 160, .7, 60, 160, .7, 0, 64);
    for (int x = 62; x <= 260; x += 2) dense.segment(7, x - 2, 160, .7, x, 160, .7, 1, 64);
    assert(sparse.m == dense.m && sparse.finger == dense.finger);
}

static void testBorders() {
    Fixture edges;
    for (int tool = 0; tool <= 7; ++tool) {
        edges.line(tool, 0, 0, 320, 0, 1, 80);
        edges.line(tool, 320, 0, 320, 320, .2, 80);
        edges.line(tool, 320, 320, 0, 320, 1, 80);
        edges.line(tool, 0, 320, 0, 0, .2, 80);
        // Largest fractional footprints exercise both cached boundary columns.
        edges.point(tool, 159.3, 159.8, 1, 80);
        edges.point(tool, .3, 319.8, .37, 80);
        edges.consistent();
    }
}

int main() {
    testPencilsAndPaper();
    testNoContactAndInvalidInput();
    testPigmentTransport();
    testFriction();
    testResampling();
    testBorders();
    std::vector<long> timing;
    Fixture speed;
    speed.line(4, 160, 20, 160, 300);
    for (int i = 0; i < 500; ++i) {
        double x = 80 + (i % 100) * 1.5;
        auto t = std::chrono::steady_clock::now();
        speed.segment(7, x, 160, .7, x + 1.5, 160, .7, 1, 64);
        timing.push_back(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t).count());
    }
    std::sort(timing.begin(), timing.end());
    printf("{\"passed\":true,\"mass_conserved\":true,\"resampling_invariant\":true,\"zero_contact_noop\":true,"
           "\"bounded_saturation\":true,\"smudge_p50_us\":%ld,\"smudge_p95_us\":%ld,\"smudge_max_us\":%ld}\n",
           timing[250], timing[475], timing[499]);
}
