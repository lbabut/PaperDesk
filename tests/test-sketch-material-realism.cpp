#include "../product/payload/apps/papersketch/native/sketch-material.h"
#include <cassert>
#include <cstdio>
#include <numeric>
#include <limits>

struct Surface {
    static constexpr int W = 160;
    PaperMaterial p;
    std::vector<uint32_t> mass = std::vector<uint32_t>(W * W);
    std::vector<uint32_t> image = std::vector<uint32_t>(W * W, 0xffffffffu);
    std::vector<uint16_t> finger = std::vector<uint16_t>(82 * 81);
    Surface() { p.init(W, W); }
    void point(int tool, double size = 32, double pressure = .6, double x = 80, double y = 80) {
        p.dab(mass.data(), image.data(), finger.data(), tool, size, 0, 1, x, y, pressure);
    }
    void segment(int tool, double ax, double ay, double bx, double by, int index, double pressure = 1) {
        p.segment(mass.data(), image.data(), finger.data(), tool, 24, 0, 1, ax, ay, pressure, bx, by, pressure, index);
    }
    uint64_t total() const {
        uint64_t sum = std::accumulate(finger.begin(), finger.end(), uint64_t(0));
        for (auto value : mass) sum += (value >> 16) + (value & 65535);
        return sum;
    }
    void consistent() const {
        for (size_t i = 0; i < mass.size(); ++i) {
            unsigned sum = (mass[i] >> 16) + (mass[i] & 65535);
            assert(sum <= 65535);
            assert(image[i] == (0xff000000u | uint32_t(p.optical[sum]) * 0x010101u));
        }
        for (int y = 0; y <= 80; ++y) assert(finger[y * 82 + 81] == 0);
    }
    std::pair<int, int> extents() const {
        int x0 = W, x1 = -1, y0 = W, y1 = -1;
        for (int y = 0; y < W; ++y) for (int x = 0; x < W; ++x) if (mass[y * W + x]) {
            x0 = std::min(x0, x); x1 = std::max(x1, x);
            y0 = std::min(y0, y); y1 = std::max(y1, y);
        }
        return {x1 - x0 + 1, y1 - y0 + 1};
    }
};

static void testTiltAndPressure() {
    Surface sideways, upright, rotated;
    std::fill(sideways.p.tooth.begin(), sideways.p.tooth.end(), 100);
    upright = sideways; rotated = sideways;
    sideways.p.tiltX = .9;
    rotated.p.tiltY = .9;
    sideways.point(2); upright.point(2); rotated.point(2);
    auto horizontal = sideways.extents(), vertical = rotated.extents();
    assert(horizontal.first > horizontal.second * 2);
    assert(vertical.second > vertical.first * 2);
    assert(horizontal.first == vertical.second && horizontal.second == vertical.first);
    assert(upright.extents().first == upright.extents().second);
    assert(horizontal.first > upright.extents().first);
    for (int tool = 0; tool < 6; ++tool) {
        uint64_t previous = 0;
        double radius = 0;
        for (double pressure : {.05, .1, .15, .25, .5, .75, 1.0}) {
            Surface sample;
            sample.point(tool, 32, pressure);
            assert(sample.total() >= previous);
            previous = sample.total();
            double current = sample.p.footprintRadius(tool, 32, pressure);
            assert(current >= radius && current <= 40);
            radius = current;
        }
    }
    sideways.consistent(); rotated.consistent(); upright.consistent();
}

static double variance(const std::vector<uint8_t> &values) {
    double mean = std::accumulate(values.begin(), values.end(), 0.0) / values.size(), sum = 0;
    for (auto value : values) sum += (value - mean) * (value - mean);
    return sum / values.size();
}

static void testPaperAndWear() {
    Surface paper;
    const auto original = paper.p.tooth;
    paper.point(2, 24, 1);
    const auto mass = paper.mass;
    const auto surface = paper.p.burnish;
    paper.p.setPaperKind(1);
    auto smooth = variance(paper.p.tooth);
    assert(paper.mass == mass && paper.p.burnish == surface);
    paper.p.setPaperKind(2);
    assert(variance(paper.p.tooth) > variance(original) && smooth < variance(original));
    paper.p.setPaperKind(0);
    assert(paper.p.tooth == original && paper.mass == mass);
    assert(std::accumulate(surface.begin(), surface.end(), uint64_t(0)) > 0);
    Surface light;
    light.point(2, 24, .3);
    assert(std::accumulate(light.p.burnish.begin(), light.p.burnish.end(), uint64_t(0)) == 0);
    auto beforeReset = paper.total();
    paper.p.resetSurface();
    assert(paper.total() == beforeReset && paper.mass == mass);
    assert(std::accumulate(paper.p.burnish.begin(), paper.p.burnish.end(), uint64_t(0)) == 0);
    // Polishing changes future contact; it never rewrites existing pigment.
    Surface fresh, polished;
    std::fill(polished.p.burnish.begin(), polished.p.burnish.end(), 255);
    fresh.point(2, 24, .5); polished.point(2, 24, .5);
    assert(fresh.mass != polished.mass);
    Surface worn;
    worn.segment(4, 20, 80, 20, 80, 0);
    worn.segment(4, 20, 80, 140, 80, 1);
    assert(worn.p.wear[4] > 0 && worn.p.wear[4] < .01);
    assert(worn.p.wear[0] == 0);
    double sharpRadius = worn.p.footprintRadius(4, 24, .5);
    worn.p.wear[4] = 1;
    assert(worn.p.footprintRadius(4, 24, .5) > sharpRadius);
    auto beforeSharpen = worn.mass;
    worn.p.sharpen(4);
    assert(worn.p.wear[4] == 0 && worn.mass == beforeSharpen);
    worn.p.wear[3] = .5; worn.p.sharpen(7);
    assert(worn.p.wear[3] == .5);
    worn.consistent();
}

static void testKneadedLift() {
    Surface coal;
    coal.segment(4, 20, 80, 20, 80, 0);
    coal.segment(4, 20, 80, 140, 80, 1);
    Surface kneaded = coal, hard = coal;
    kneaded.p.kneaded = true;
    kneaded.segment(6, 60, 80, 60, 80, 0);
    auto afterTouch = kneaded.mass;
    kneaded.segment(6, 60, 80, 140, 80, 1);
    assert(kneaded.mass != afterTouch && kneaded.total() < coal.total());
    assert(kneaded.mass[80 * Surface::W + 120] != coal.mass[80 * Surface::W + 120]);
    hard.segment(6, 60, 80, 60, 80, 0);
    hard.segment(6, 60, 80, 140, 80, 1);
    assert(hard.total() < kneaded.total());
    assert(hard.mass[80 * Surface::W + 120] != coal.mass[80 * Surface::W + 120]);
    auto value = coal.mass[80 * Surface::W + 60], lifted = kneaded.mass[80 * Surface::W + 60];
    double looseRemoved = double((value & 65535) - (lifted & 65535)) / (value & 65535);
    double fixedRemoved = double((value >> 16) - (lifted >> 16)) / (value >> 16);
    assert(looseRemoved > fixedRemoved * 4);
    Surface delayed = coal;
    delayed.p.kneaded = true;
    delayed.segment(6, 60, 80, 60, 80, 0, 0);
    assert(delayed.mass == coal.mass);
    delayed.segment(6, 60, 80, 62, 80, 1);
    assert(delayed.total() < coal.total());
    auto firstContact = delayed.mass;
    delayed.segment(6, 62, 80, 140, 80, 1);
    assert(delayed.mass != firstContact);
    // A stationary light touch must respond to later force, without rubbing away
    // more pigment just because the input device reports more samples.
    Surface ramp = coal; ramp.p.kneaded = true;
    ramp.segment(6,60,80,60,80,0,.05);
    auto light = ramp.mass; int lightGray = ramp.image[80*Surface::W+60] & 255;
    ramp.segment(6,60,80,60,80,1,1);
    assert(ramp.mass != light);
    assert(int(ramp.image[80*Surface::W+60]&255) >= lightGray+10);
    auto firm = ramp.mass;
    for(int i=0;i<100;i++) ramp.segment(6,60,80,60,80,1,1);
    assert(ramp.mass == firm);
    ramp.segment(6,60,80,60,80,0,1);
    assert(ramp.mass != firm); // A new dab can lift again.
    ramp.consistent();
    kneaded.consistent(); hard.consistent();
}

static void testFingerAndBounds() {
    for (double angle : {0.0, .3, .7853981633974483, 1.5707963267948966, 3.14}) {
        Surface finger;
        finger.p.contactAspect = 2;
        finger.p.contactAngle = angle;
        finger.segment(4, 20, 80, 20, 80, 0);
        finger.segment(4, 20, 80, 140, 80, 1);
        auto total = finger.total();
        auto surface = finger.p.burnish;
        for (int x = 0; x <= 160; x += 4) finger.point(7, 80, .7, x + .3, 80.8);
        assert(finger.total() == total && finger.p.burnish == surface);
        finger.consistent();
    }
    for (int tool = 0; tool <= 7; ++tool) for (double angle : {0.0, .2, .7, 1.57, 2.3}) {
        Surface maximum;
        maximum.p.tiltX = std::cos(angle); maximum.p.tiltY = std::sin(angle);
        maximum.p.contactAspect = 2; maximum.p.contactAngle = angle;
        maximum.p.wear.fill(1);
        assert(maximum.p.footprintRadius(tool, 80, 1) <= 40);
        maximum.point(tool, 80, 1, 79.3, 79.8);
        maximum.point(tool, 80, .1, .3, 159.8);
        maximum.consistent();
    }
    Surface fingerX, fingerY;
    std::fill(fingerX.finger.begin(), fingerX.finger.end(), 20000);
    for (int y = 0; y <= 80; ++y) fingerX.finger[y * 82 + 81] = 0;
    fingerY = fingerX;
    fingerX.p.contactAspect = fingerY.p.contactAspect = 2;
    fingerY.p.contactAngle = 1.5707963267948966;
    auto total = fingerX.total();
    fingerX.point(7, 48, 1); fingerY.point(7, 48, 1);
    assert(fingerX.total() == total && fingerY.total() == total);
    assert(fingerX.extents().first > fingerX.extents().second);
    assert(fingerY.extents().second > fingerY.extents().first);
}

static void testFullStateResampling() {
    Surface whole, split;
    whole.p.tiltX = split.p.tiltX = .8;
    whole.p.tiltY = split.p.tiltY = .3;
    whole.p.setPaperKind(2); split.p.setPaperKind(2);
    whole.segment(2, 20, 80, 20, 80, 0);
    whole.segment(2, 20, 80, 140, 80, 1);
    split.segment(2, 20, 80, 20, 80, 0);
    for (int x = 22; x <= 140; x += 2) split.segment(2, x - 2, 80, x, 80, 1);
    assert(whole.mass == split.mass && whole.image == split.image);
    assert(whole.p.burnish == split.p.burnish && whole.p.wear == split.p.wear);
}

int main() {
    testTiltAndPressure(); testPaperAndWear(); testKneadedLift();
    testFingerAndBounds(); testFullStateResampling();
    std::puts("PASS directional tilt, pressure profiles, three paper stocks, persistent burnish, distance wear/sharpen, kneaded lift, rotated conservative finger, bounded maximum footprints and full-state event resampling");
}
