#ifndef PAPER_SKETCH_MATERIAL_H
#define PAPER_SKETCH_MATERIAL_H

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

// A paper pixel holds fixed and loose 16-bit pigment masses, with their sum
// bounded by 65535. The persistent fingertip is a second mass map: touching
// transfers pigment between the two surfaces, without creating or deleting it.
struct PaperMaterial {
    static constexpr int FingerStride = 82; // Includes QImage's padded column.
    static constexpr int FingerCenter = 40;
    int width = 0, height = 0;
    std::vector<uint8_t> tooth;
    uint8_t optical[65536]{};
    uint16_t inverse[256]{};
    double untilNext = 0;

    static uint32_t hash(uint32_t x, uint32_t y) {
        uint32_t n = x * 374761393u + y * 668265263u + 0x9e3779b9u;
        n = (n ^ (n >> 13)) * 1274126177u;
        return n ^ (n >> 16);
    }

    void init(int w, int h) {
        if (width == w && height == h) return;
        width = w;
        height = h;
        tooth.resize(size_t(w) * h);
        for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
            int fine = hash(x, y) & 255;
            int coarse = hash(x / 4, y / 4) & 255;
            int fiber = hash(x / 2, y / 9) & 255;
            tooth[y * w + x] = (fine * 3 + coarse * 2 + fiber) / 6;
        }
        for (int i = 0; i < 65536; ++i)
            optical[i] = uint8_t(std::lround(255 * std::exp(-i / 14000.0)));
        for (int i = 0; i < 256; ++i)
            inverse[i] = uint16_t(std::min(65535.0,
                std::round(-std::log(std::max(1, i) / 255.0) * 14000)));
    }

    void import(const uint32_t *image, uint32_t *mass) {
        for (int i = 0; i < width * height; ++i) {
            int total = inverse[image[i] & 255], fixed = total * 7 / 10;
            mass[i] = (uint32_t(fixed) << 16) | (total - fixed);
        }
    }

    static bool valid(int tool, double size, double tone, double strength,
                      double x, double y, double pressure) {
        return tool >= 0 && tool <= 7 && std::isfinite(size) && size >= 1 && size <= 80 &&
            std::isfinite(tone) && tone >= 0 && tone <= 255 &&
            std::isfinite(strength) && strength >= 0 && strength <= 1 &&
            std::isfinite(x) && std::isfinite(y) && std::isfinite(pressure);
    }

    void dab(uint32_t *mass, uint32_t *image, uint16_t *finger, int tool,
             double size, double tone, double strength, double cx, double cy,
             double pressure) {
        if (!valid(tool, size, tone, strength, cx, cy, pressure) ||
            pressure <= 0 || strength == 0 || width <= 0 || height <= 0) return;
        double p = std::min(pressure, 1.0);
        if (tool < 6) p *= std::sqrt(p);
        double radius = tool == 7 ? std::max(6.0, size * .5 * (.65 + .35 * p)) :
            std::max(.8, size * (.18 + .82 * p) * .5);
        // Reject distant coordinates before converting them to integer bounds.
        if (cx < -radius || cy < -radius || cx > width + radius || cy > height + radius) return;
        int x0 = std::max(0, int(std::floor(cx - radius)));
        int x1 = std::min(width - 1, int(std::ceil(cx + radius)));
        int y0 = std::max(0, int(std::floor(cy - radius)));
        int y1 = std::min(height - 1, int(std::ceil(cy + radius)));
        constexpr double doses[] = {6000, 12000, 16000, 22000, 20000, 24000};
        constexpr double fixedFraction[] = {.94, .78, .58, .38, .14, .08};
        constexpr double capacities[] = {18000, 30000, 40000, 55000, 65000, 65535};
        // Keep divisions and tool constants outside the per-pixel hot loop.
        const double inverseRadiusSquared = 1.0 / (radius * radius);
        const double contactStrength = p * strength;
        const double dose = tool < 6 ? doses[tool] * contactStrength * (1 - tone / 255.0) : 0;
        const double capacityAtPressure = tool < 6 ? capacities[tool] * (.12 + .88 * p) : 0;
        const double bondedFraction = tool < 6 ? fixedFraction[tool] : 0;
        const double toothContact = tool < 4 ? .7 : .5;
        const double eraseContact = strength * (.15 + .85 * p);
        // A footprint is at most 82 columns wide (80px size plus the two
        // fractional bounds). Reuse its coordinates across all scanlines.
        double columnSquared[82];
        int fingerColumn[82];
        for (int x = x0; x <= x1; ++x) {
            double dx = x + .5 - cx;
            columnSquared[x - x0] = dx * dx;
            if (tool == 7)
                fingerColumn[x - x0] = std::clamp(int(std::lround(dx)) + FingerCenter, 0, 80);
        }
        for (int y = y0; y <= y1; ++y) {
            const double dy = y + .5 - cy, dySquared = dy * dy;
            const int fingerRow = tool == 7 ?
                std::clamp(int(std::lround(dy)) + FingerCenter, 0, 80) * FingerStride : 0;
            for (int x = x0; x <= x1; ++x) {
                double edge = 1 - (columnSquared[x - x0] + dySquared) * inverseRadiusSquared;
                if (edge <= 0) continue;
                edge *= edge;
                int at = y * width + x;
                uint32_t packed = mass[at];
                int fixed = packed >> 16, loose = packed & 65535;
                if (tool == 7) {
                    int fi = fingerRow + fingerColumn[x - x0];
                    int held = finger[fi], room = 65535 - held;
                    double contact = contactStrength * edge;
                    int pickLoose = std::min({loose, room, int(std::lround(loose * .13 * contact))});
                    int pickFixed = std::min({fixed, room - pickLoose,
                        int(std::lround(fixed * .012 * p * contact))});
                    loose -= pickLoose;
                    fixed -= pickFixed;
                    held += pickLoose + pickFixed;
                    int deposit = std::min(65535 - fixed - loose, int(std::lround(held * .16 * contact)));
                    loose += deposit;
                    held -= deposit;
                    finger[fi] = held;
                } else if (tool == 6) {
                    double contact = edge * eraseContact;
                    loose -= std::min(loose, int(std::lround(loose * contact * .65)));
                    fixed -= std::min(fixed, int(std::lround(fixed * contact * .28)));
                } else {
                    double grain = tooth[at] / 255.0;
                    double contact = std::clamp((p + .2 - grain * toothContact) * 2.0, 0.0, 1.0);
                    double valley = std::clamp((.9 - grain) / .7, 0.0, 1.0);
                    int capacity = int(capacityAtPressure * (.08 + .92 * valley * valley));
                    int room = std::max(0, capacity - fixed - loose);
                    double amount = dose * edge * contact * (room / double(capacity));
                    int added = std::min(room, int(std::lround(amount)));
                    int bonded = int(std::lround(added * bondedFraction));
                    fixed += bonded;
                    loose += added - bonded;
                }
                mass[at] = (uint32_t(fixed) << 16) | loose;
                int gray = optical[fixed + loose];
                image[at] = 0xff000000u | uint32_t(gray) * 0x010101u;
            }
        }
        if (tool == 7) {
            // Friction mixes neighboring fingertip cells. Each pairwise
            // exchange is bounded and conservative. Light contact now mixes
            // less than firm contact, as well as picking up less pigment.
            int lo = std::max(0, FingerCenter - int(std::ceil(radius)));
            int hi = std::min(80, FingerCenter + int(std::ceil(radius)));
            // 16-bit fixed point avoids a floating point conversion for each
            // neighbor. The largest signed product is below INT32_MAX.
            int friction = int(16384 * contactStrength);
            for (int y = lo; y <= hi; ++y) for (int x = lo; x <= hi; ++x) {
                int i = y * FingerStride + x;
                if (x < hi) {
                    int flow = (int(finger[i]) - int(finger[i + 1])) * friction / 65536;
                    finger[i] -= flow;
                    finger[i + 1] += flow;
                }
                if (y < hi) {
                    int flow = (int(finger[i]) - int(finger[i + FingerStride])) * friction / 65536;
                    finger[i] -= flow;
                    finger[i + FingerStride] += flow;
                }
            }
        }
    }

    void segment(uint32_t *mass, uint32_t *image, uint16_t *finger, int tool,
                 double size, double tone, double strength, double ax, double ay,
                 double ap, double bx, double by, double bp, int index) {
        if (!valid(tool, size, tone, strength, ax, ay, ap) ||
            !valid(tool, size, tone, strength, bx, by, bp)) return;
        if (!index) {
            untilNext = 0;
            dab(mass, image, finger, tool, size, tone, strength, bx, by, bp);
            return;
        }
        double dx = bx - ax, dy = by - ay, length = std::hypot(dx, dy);
        // Even subpixel segments consume distance; dropping short events used
        // to change density when the same path arrived as many tiny events.
        if (length == 0 || !std::isfinite(length)) return;
        double spacing = std::clamp(size * .10, .65, 2.0);
        double travel = untilNext > 0 ? untilNext : spacing;
        while (travel <= length) {
            double t = travel / length;
            dab(mass, image, finger, tool, size, tone, strength,
                ax + dx * t, ay + dy * t, ap + (bp - ap) * t);
            travel += spacing;
        }
        untilNext = travel - length;
    }
};
#endif
