#ifndef PAPER_SKETCH_MATERIAL_H
#define PAPER_SKETCH_MATERIAL_H

#include <algorithm>
#include <array>
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
    std::vector<uint8_t> burnish;
    std::vector<uint8_t> ink;
    bool hasInk = false;
    std::array<double, 6> wear{};
    double tiltX = 0, tiltY = 0;
    double contactAspect = 1, contactAngle = 0;
    bool kneaded = false;
    std::vector<uint16_t> kneadedLift; // Per-contact removal caps, never saved.
    bool kneadedContact = false; // Transient contact state, reset at stroke start.
    int paperKind = 0; // 0 plain, 1 smooth, 2 rough.
    uint8_t optical[65536]{};
    uint16_t inverse[256]{};
    double untilNext = 0;

    struct GrainResponse { double grain, capacity; };
    static const std::array<GrainResponse, 65536> &grainResponses() {
        // These two values depend only on the 8-bit tooth and burnish pair,
        // not on pressure, tool, pigment or position. Share the exact double
        // results across pages instead of recomputing them in every dab.
        static const auto responses = [] {
            std::array<GrainResponse, 65536> values{};
            for (int b = 0; b < 256; ++b) {
                double polish = b * (1.0 / 255.0);
                for (int t = 0; t < 256; ++t) {
                    double grain = (t * (1.0 / 255.0)) * (1 - .45 * polish) + .18 * polish;
                    double valley = std::clamp((.9 - grain) * (1.0 / .7), 0.0, 1.0);
                    values[b * 256 + t] = {grain, .08 + .92 * valley * valley};
                }
            }
            return values;
        }();
        return responses;
    }

    static uint32_t hash(uint32_t x, uint32_t y) {
        uint32_t n = x * 374761393u + y * 668265263u + 0x9e3779b9u;
        n = (n ^ (n >> 13)) * 1274126177u;
        return n ^ (n >> 16);
    }

    void rebuildTooth() {
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            int fine = hash(x, y) & 255;
            int coarse = hash(x / 4, y / 4) & 255;
            int fiber = hash(x / 2, y / 9) & 255;
            double grain = (fine * 3 + coarse * 2 + fiber) / 6;
            if (paperKind == 1) grain = 72 + (grain - 128) * .35;
            if (paperKind == 2) grain = 128 + (grain - 128) * 1.65 +
                (int(hash(x / 9, y / 7) & 255) - 128) * .14;
            tooth[y * width + x] = uint8_t(std::clamp(grain, 0.0, 255.0));
        }
    }

    void setPaperKind(int kind) {
        kind = std::clamp(kind, 0, 2);
        if (paperKind == kind) return;
        paperKind = kind;
        rebuildTooth();
    }

    void resetInk() { std::fill(ink.begin(), ink.end(), 0); hasInk = false; }
    void resetSurface() { std::fill(burnish.begin(), burnish.end(), 0); }
    void sharpen(int tool) { if (tool >= 0 && tool < 6) wear[tool] = 0; }

    void init(int w, int h) {
        if (width == w && height == h) return;
        width = w;
        height = h;
        tooth.resize(size_t(w) * h);
        burnish.assign(tooth.size(), 0);
        ink.assign(tooth.size(), 0); hasInk = false;
        rebuildTooth();
        (void)grainResponses(); // Initialize the shared table before drawing.
        for (int i = 0; i < 65536; ++i)
            optical[i] = uint8_t(std::lround(255 * std::exp(-i / 14000.0)));
        for (int i = 0; i < 256; ++i)
            inverse[i] = uint16_t(std::min(65535.0,
                std::round(-std::log(std::max(1, i) / 255.0) * 14000)));
    }

    static double unit(double value) {
        return std::isfinite(value) ? std::clamp(value, 0.0, 1.0) : 0;
    }
    // Pigment amounts are finite and nonnegative; this is lround without a
    // libm call in every covered pixel. Finger coordinates still use lround.
    static int roundMass(double value) { return int(value + .5); }
    struct Footprint { double a, b, c, s, tilt, worn; };
    Footprint footprint(int tool, double size, double pressure) const {
        double p = unit(pressure), a, b, angle = 0, tilt = 0, worn = 0;
        if (tool == 7) {
            double aspect = std::isfinite(contactAspect) ? std::clamp(contactAspect, 1.0, 2.0) : 1;
            double r = std::max(6.0, size * .5 * (.8 + .2 * std::sqrt(p)));
            a = std::min(40.0, r * std::sqrt(aspect));
            b = std::min(40.0, r / std::sqrt(aspect));
            angle = std::isfinite(contactAngle) ? contactAngle : 0;
        } else if (tool == 8) {
            a = b = std::max(.5, size * .5) + .5;
        } else if (tool == 6 && kneaded) {
            a = b = std::max(.8, size * .5 * (.7 + .3 * std::sqrt(p)));
        } else if (tool < 6 && tool >= 0) {
            constexpr double widthExponent[] = {.90, 1.05, 1.15, 1.20, .80, .70};
            constexpr double minimumWidth[] = {.22, .20, .18, .16, .35, .40};
            worn = unit(wear[tool]);
            double tx = std::isfinite(tiltX) ? std::clamp(tiltX, -1.0, 1.0) : 0;
            double ty = std::isfinite(tiltY) ? std::clamp(tiltY, -1.0, 1.0) : 0;
            tilt = std::min(1.0, std::hypot(tx, ty));
            angle = tilt > 0 ? std::atan2(ty, tx) : 0;
            double width = minimumWidth[tool] + (1 - minimumWidth[tool]) * std::pow(p, widthExponent[tool]);
            double r = std::max(.8, size * .5 * width);
            a = std::min(40.0, r * (1 + .65 * tilt + .18 * worn));
            b = std::min(40.0, std::max(.55, r * (1 - .45 * tilt) * (1 + .30 * worn)));
        } else {
            a = b = std::min(40.0, std::max(.8, size * (.18 + .82 * p) * .5));
        }
        return {a, b, std::cos(angle), std::sin(angle), tilt, worn};
    }
    double footprintRadius(int tool, double size, double pressure) const {
        auto shape = footprint(tool, size, pressure);
        return std::max(shape.a, shape.b);
    }

    void import(const uint32_t *image, uint32_t *mass) {
        resetInk();
        for (int i = 0; i < width * height; ++i) {
            int total = inverse[image[i] & 255], fixed = total * 7 / 10;
            mass[i] = (uint32_t(fixed) << 16) | (total - fixed);
        }
    }

    static bool valid(int tool, double size, double tone, double strength,
                      double x, double y, double pressure) {
        return tool >= 0 && tool <= 8 && std::isfinite(size) && size >= 1 && size <= 80 &&
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
        if (tool == 6 && kneaded && kneadedLift.size() != size_t(width) * height)
            kneadedLift.assign(size_t(width) * height, 0);
        auto shape = footprint(tool, size, p);
        double radius = std::max(shape.a, shape.b);
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
        const double inverseA = 1.0 / (shape.a * shape.a), inverseB = 1.0 / (shape.b * shape.b);
        const double quadraticX = shape.c * shape.c * inverseA + shape.s * shape.s * inverseB;
        const double quadraticY = shape.s * shape.s * inverseA + shape.c * shape.c * inverseB;
        const double quadraticXY = 2 * shape.c * shape.s * (inverseA - inverseB);
        const double contactStrength = (tool == 7 ? .9 * std::sqrt(p) : p) * strength;
        constexpr double doseExponent[] = {1.2, 1.35, 1.45, 1.50, .90, .80};
        const double dosePressure = tool < 6 ? std::pow(p, doseExponent[tool]) : p;
        const double dose = tool < 6 ? doses[tool] * strength * dosePressure * (1 - tone / 255.0) *
            (1 - .15 * shape.worn) : 0;
        const double capacityAtPressure = tool < 6 ? capacities[tool] * (.12 + .88 * p) : 0;
        const double bondedFraction = tool < 6 ? fixedFraction[tool] : 0;
        const double toothContact = tool < 4 ? .7 : .5;
        const double eraseContact = strength * (.15 + .85 * p);
        const double firmScale = p > .6 ? (p - .6) / .4 * strength : 0;
        const double stock = paperKind == 1 ? 1.2 : paperKind == 2 ? .65 : 1;
        const double burnishScale = 5 * firmScale * stock * (tool < 4 ? 1 : .45);
        const auto *responses = tool < 6 ? grainResponses().data() : nullptr;
        // An antialiased ink footprint is at most 84 columns wide (80px size plus
        // fractional bounds). Reuse its coordinates across all scanlines.
        double columnSquared[84];
        double columnX[84], columnCross[84];
        int fingerColumn[84];
        const bool rotatedFinger = tool == 7 && (std::abs(shape.s) > 1e-10 || shape.c < 0);
        for (int x = x0; x <= x1; ++x) {
            double dx = x + .5 - cx;
            columnX[x - x0] = dx;
            columnSquared[x - x0] = dx * dx * quadraticX;
            columnCross[x - x0] = dx * quadraticXY;
            if (tool == 7)
                fingerColumn[x - x0] = std::clamp(int(std::lround(dx)) + FingerCenter, 0, 80);
        }
        for (int y = y0; y <= y1; ++y) {
            const double dy = y + .5 - cy, dySquared = dy * dy * quadraticY;
            const int fingerRow = tool == 7 ?
                std::clamp(int(std::lround(dy)) + FingerCenter, 0, 80) * FingerStride : 0;
            for (int x = x0; x <= x1; ++x) {
                double edge = 1 - columnSquared[x - x0] - dySquared - columnCross[x - x0] * dy;
                if (edge <= 0) continue;
                if (tool == 8) {
                    int at = y * width + x;
                    double distance = std::sqrt(std::max(0.0, 1 - edge)) * shape.a;
                    int coverage = roundMass(255 * std::clamp(shape.a - distance, 0.0, 1.0));
                    int prior = ink[at];
                    if (coverage > prior) {
                        int gray = ((int(image[at] & 255)) * (255 - coverage) + (255 - prior) / 2) / (255 - prior);
                        ink[at] = uint8_t(coverage); hasInk = true;
                        image[at] = 0xff000000u | uint32_t(gray) * 0x010101u;
                    }
                    continue;
                }
                edge *= edge;
                if (tool == 4 || tool == 5)
                    edge += edge * (1 - edge) * .55 * shape.tilt;
                int at = y * width + x;
                uint32_t packed = mass[at];
                int fixed = packed >> 16, loose = packed & 65535;
                if (tool == 7) {
                    int fi = fingerRow + fingerColumn[x - x0];
                    if (rotatedFinger) {
                        double dx = columnX[x - x0];
                        int fx = std::clamp(int(std::lround(shape.c * dx + shape.s * dy)) + FingerCenter, 0, 80);
                        int fy = std::clamp(int(std::lround(-shape.s * dx + shape.c * dy)) + FingerCenter, 0, 80);
                        fi = fy * FingerStride + fx;
                    }
                    int held = finger[fi], room = 65535 - held;
                    double contact = contactStrength * edge;
                    if (hasInk) contact *= (255 - ink[at]) * (1.0 / 255.0);
                    int pickLoose = std::min({loose, room, roundMass(loose * .40 * contact)});
                    int pickFixed = std::min({fixed, room - pickLoose,
                        roundMass(fixed * .06 * (.3 + .7 * p) * contact)});
                    loose -= pickLoose;
                    fixed -= pickFixed;
                    held += pickLoose + pickFixed;
                    int deposit = std::min(65535 - fixed - loose, roundMass(held * .36 * contact));
                    loose += deposit;
                    held -= deposit;
                    finger[fi] = held;
                } else if (tool == 6) {
                    if (kneaded) {
                        // A contact lifts a bounded fraction, independent of event count.
                        // More pressure or moving onto fresh paper can lift more pigment.
                        double contact = edge * strength * std::sqrt(p);
                        int looseTarget = roundMass(255 * .55 * contact);
                        int fixedTarget = roundMass(255 * .12 * contact * (.35 + .65 * std::sqrt(p)));
                        unsigned prior = kneadedLift[at];
                        int priorLoose = prior & 255, priorFixed = prior >> 8;
                        if (looseTarget > priorLoose)
                            loose -= std::min(loose, roundMass(loose * double(looseTarget-priorLoose) / (255-priorLoose)));
                        if (fixedTarget > priorFixed)
                            fixed -= std::min(fixed, roundMass(fixed * double(fixedTarget-priorFixed) / (255-priorFixed)));
                        kneadedLift[at] = uint16_t(std::max(priorLoose,looseTarget) | (std::max(priorFixed,fixedTarget)<<8));
                    } else {
                        double contact = edge * eraseContact;
                        loose -= std::min(loose, roundMass(loose * contact * .65));
                        fixed -= std::min(fixed, roundMass(fixed * contact * .28));
                    }
                } else {
                    double polish = burnish[at] * (1.0 / 255.0);
                    const auto &response = responses[unsigned(burnish[at]) * 256 + tooth[at]];
                    double contact = std::clamp((1.05 * p + .15 - response.grain * toothContact) * 2.0, 0.0, 1.0);
                    int capacity = std::max(1, int(capacityAtPressure * response.capacity * (1 - .22 * polish)));
                    int room = std::max(0, capacity - fixed - loose);
                    if (room > 0) {
                        double amount = dose * edge * contact * (1 - .35 * polish) * (room / double(capacity));
                        int added = std::min(room, roundMass(amount));
                        int bonded = roundMass(added * std::min(.99, bondedFraction + .10 * polish));
                        fixed += bonded;
                        loose += added - bonded;
                    }
                    if (p > .6) {
                        double firm = firmScale * edge;
                        int compact = std::min(loose, roundMass(loose * .012 * firm));
                        fixed += compact;
                        loose -= compact;
                        int polishAdded = roundMass(burnishScale * edge);
                        burnish[at] = uint8_t(std::min(255, int(burnish[at]) + polishAdded));
                    }
                }
                mass[at] = (uint32_t(fixed) << 16) | loose;
                int gray = optical[fixed + loose];
                if (hasInk && ink[at]) gray = (gray * (255 - ink[at]) + 127) / 255;
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
            if (tool == 6 && kneaded) kneadedLift.assign(size_t(width) * height, 0);
            kneadedContact = tool == 6 && kneaded && bp > 0 && strength > 0;
            dab(mass, image, finger, tool, size, tone, strength, bx, by, bp);
            return;
        }
        double dx = bx - ax, dy = by - ay, length = std::hypot(dx, dy);
        if (tool == 6 && kneaded) {
            if (bp > 0 && strength > 0) kneadedContact = true;
            if (length == 0) {
                dab(mass,image,finger,tool,size,tone,strength,bx,by,bp);
                return;
            }
        }
        // Preserve subpixel travel between input samples.
        if (length == 0 || !std::isfinite(length)) return;
        double spacing = tool == 8 ? std::clamp(size * .25, .25, 1.0) : std::clamp(size * .10, .65, 2.0);
        double travel = untilNext > 0 ? untilNext : spacing;
        while (travel <= length) {
            double t = travel / length;
            double pressure = ap + (bp - ap) * t;
            dab(mass, image, finger, tool, size, tone, strength,
                ax + dx * t, ay + dy * t, pressure);
            if (tool < 6 && pressure > 0 && strength > 0) {
                constexpr double wearRate[] = {.000003, .000004, .000006, .000008, .000018, .000024};
                wear[tool] = std::min(1.0, unit(wear[tool]) + spacing * unit(pressure) * strength * wearRate[tool]);
            }
            travel += spacing;
        }
        untilNext = travel - length;
    }
};
#endif
