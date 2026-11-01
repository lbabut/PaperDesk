// SPDX-License-Identifier: MIT
// Run with: c++ -std=c++17 -O2 -Wall -Wextra -Werror tests/terminal-core.cpp -o /tmp/paperterminal-core-test
#include "../product/payload/apps/paperterminal/native/terminal-core.h"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>
#include <string>

using PaperTerminal::Cell;
using PaperTerminal::TerminalCore;

#define CHECK(expression) do { if (!(expression)) { \
    std::cerr << __func__ << ":" << __LINE__ << ": " << #expression << " failed\n"; \
    std::exit(1); } } while (false)

static void feed(TerminalCore& terminal, const std::string& text) {
    terminal.feed(text.data(), text.size());
}
static std::u32string row(const TerminalCore& terminal, int index) {
    std::u32string result;
    for (const Cell& cell : terminal.line(index)) result += cell.codepoint;
    return result;
}
static void invariant(const TerminalCore& terminal) {
    CHECK(terminal.columns() >= 1 && terminal.columns() <= TerminalCore::MaximumColumns);
    CHECK(terminal.rows() >= 1 && terminal.rows() <= TerminalCore::MaximumRows);
    CHECK(terminal.cursorColumn() >= 0 && terminal.cursorColumn() < terminal.columns());
    CHECK(terminal.cursorRow() >= 0 && terminal.cursorRow() < terminal.rows());
    CHECK(terminal.historySize() <= TerminalCore::MaximumHistoryLines);
    CHECK(static_cast<std::size_t>(terminal.historySize() * terminal.columns()) <=
          TerminalCore::MaximumHistoryCells);
    CHECK(terminal.scrollOffset() >= 0 && terminal.scrollOffset() <= terminal.historySize());
    for (int y = 0; y < terminal.rows(); ++y) {
        CHECK(terminal.line(y).size() == static_cast<std::size_t>(terminal.columns()));
        CHECK(terminal.line(y)[0].codepoint != 0);
        for (int x = 1; x < terminal.columns(); ++x) {
            if (terminal.line(y)[static_cast<std::size_t>(x)].codepoint == 0) {
                CHECK(terminal.line(y)[static_cast<std::size_t>(x - 1)].codepoint != 0);
                CHECK(terminal.line(y)[static_cast<std::size_t>(x - 1)].codepoint != U' ');
            }
        }
    }
}
static bool sameCell(const Cell& a, const Cell& b) {
    return a.codepoint == b.codepoint && a.foreground == b.foreground &&
           a.background == b.background && a.bold == b.bold &&
           a.underline == b.underline && a.inverse == b.inverse;
}
static void sameTerminal(const TerminalCore& a, const TerminalCore& b) {
    CHECK(a.columns() == b.columns() && a.rows() == b.rows());
    CHECK(a.cursorColumn() == b.cursorColumn() && a.cursorRow() == b.cursorRow());
    CHECK(a.cursorVisible() == b.cursorVisible());
    CHECK(a.applicationCursor() == b.applicationCursor());
    CHECK(a.mouseTracking() == b.mouseTracking() && a.sgrMouse() == b.sgrMouse());
    CHECK(a.bracketedPaste() == b.bracketedPaste());
    CHECK(a.historySize() == b.historySize() && a.scrollOffset() == b.scrollOffset());
    for (int y = 0; y < a.rows(); ++y)
        for (int x = 0; x < a.columns(); ++x)
            CHECK(sameCell(a.line(y)[static_cast<std::size_t>(x)],
                           b.line(y)[static_cast<std::size_t>(x)]));
}

static void basicControls() {
    TerminalCore terminal(5, 3);
    CHECK(terminal.takeDirtyRows() == (std::vector<int>{0, 1, 2}));
    CHECK(terminal.takeDirtyRows().empty());
    feed(terminal, "abc");
    CHECK(row(terminal, 0) == U"abc  ");
    CHECK(terminal.cursorColumn() == 3 && terminal.cursorRow() == 0);
    CHECK(terminal.takeDirtyRows() == (std::vector<int>{0}));
    feed(terminal, "\rX\bY\nZ");
    CHECK(row(terminal, 0) == U"Ybc  ");
    CHECK(row(terminal, 1) == U" Z   ");
    feed(terminal, "\x1b[20h\nQ");
    CHECK(row(terminal, 2) == U"Q    ");
    feed(terminal, "\x1b[?25l");
    CHECK(!terminal.cursorVisible());
    feed(terminal, "\x1b[?25h\x1b[1;5H");
    CHECK(terminal.cursorVisible());
    CHECK(terminal.cursorRow() == 0 && terminal.cursorColumn() == 4);
    CHECK(terminal.takeDirtyRows() == (std::vector<int>{0, 1, 2}));
    feed(terminal, "\x1b[?9999h\a\0");
    CHECK(terminal.takeDirtyRows().empty());
    invariant(terminal);
}

static void wrappingAndScrollback() {
    TerminalCore terminal(3, 2);
    feed(terminal, "abc");
    CHECK(terminal.cursorRow() == 0 && terminal.cursorColumn() == 2);
    CHECK(terminal.historySize() == 0);
    feed(terminal, "DEFZ");
    CHECK(row(terminal, 0) == U"DEF");
    CHECK(row(terminal, 1) == U"Z  ");
    CHECK(terminal.historySize() == 1);
    terminal.scroll(1);
    CHECK(row(terminal, 0) == U"abc");
    CHECK(row(terminal, 1) == U"DEF");
    CHECK(!terminal.cursorVisible());
    feed(terminal, "\r\nnew\r\n");
    CHECK(terminal.scrollOffset() == 3);
    CHECK(row(terminal, 0) == U"abc");
    terminal.scroll(std::numeric_limits<int>::max());
    CHECK(terminal.scrollOffset() == terminal.historySize());
    terminal.scroll(std::numeric_limits<int>::min());
    CHECK(terminal.scrollOffset() == 0 && terminal.cursorVisible());
    feed(terminal, "\x1b[3J");
    CHECK(terminal.historySize() == 0);

    TerminalCore noWrap(4, 2);
    feed(noWrap, "\x1b[?7l123456");
    CHECK(row(noWrap, 0) == U"1236");
    CHECK(noWrap.cursorRow() == 0 && noWrap.historySize() == 0);
    noWrap.reset();
    feed(noWrap, "1234\rZ");
    CHECK(row(noWrap, 0) == U"Z234");
    CHECK(noWrap.cursorRow() == 0); // CR cancels the delayed wrap.
    invariant(noWrap);

    TerminalCore viewport(4, 3);
    feed(viewport, "old\r\naaa\r\nbbb\r\nccc");
    viewport.scroll(1);
    viewport.takeDirtyRows();
    feed(viewport, "\x1b[1;1HX");
    CHECK(row(viewport, 1) == U"Xaa ");
    CHECK(viewport.takeDirtyRows() == (std::vector<int>{1}));
}

static void editingAndMargins() {
    TerminalCore terminal(8, 5);
    feed(terminal, "ABCDEFGH\x1b[1;3H\x1b[2@xy");
    CHECK(row(terminal, 0) == U"ABxyCDEF");
    feed(terminal, "\x1b[1;4H\x1b[2P");
    CHECK(row(terminal, 0) == U"ABxDEF  ");
    feed(terminal, "\x1b[2X");
    CHECK(row(terminal, 0) == U"ABx  F  ");
    feed(terminal, "\x1b[1K");
    CHECK(row(terminal, 0) == U"     F  ");
    feed(terminal, "\x1b[2K\x1b[H1\x1b[2;1H2\x1b[3;1H3\x1b[4;1H4\x1b[5;1H5");
    feed(terminal, "\x1b[2;4r\x1b[4;1H\n");
    CHECK(row(terminal, 0)[0] == U'1');
    CHECK(row(terminal, 1)[0] == U'3');
    CHECK(row(terminal, 2)[0] == U'4');
    CHECK(row(terminal, 3)[0] == U' ');
    CHECK(row(terminal, 4)[0] == U'5');
    CHECK(terminal.historySize() == 0); // A partial region is not scrollback.
    feed(terminal, "\x1b[?6h\x1b[1;1HX\x1b[99;1HY");
    CHECK(row(terminal, 1)[0] == U'X');
    CHECK(row(terminal, 3)[0] == U'Y');
    CHECK(terminal.cursorRow() == 3);
    feed(terminal, "\x1b[?6l\x1b[2;1H\x1b[L");
    CHECK(row(terminal, 1)[0] == U' ');
    CHECK(row(terminal, 2)[0] == U'X');
    feed(terminal, "\x1b[M");
    CHECK(row(terminal, 1)[0] == U'X');
    feed(terminal, "\x1b[r\x1b[H\x1b[M");
    CHECK(terminal.historySize() == 0); // DL never archives deleted rows.
    feed(terminal, "\x1b[2J");
    for (int y = 0; y < terminal.rows(); ++y) CHECK(row(terminal, y) == U"        ");
    invariant(terminal);
}

static void tabsSaveRestoreAndModes() {
    TerminalCore terminal(20, 4);
    feed(terminal, "A\tB\tC");
    CHECK(row(terminal, 0) == U"A       B       C   ");
    feed(terminal, "\x1b[Z");
    CHECK(terminal.cursorColumn() == 16);
    feed(terminal, "\x1b[3g\r\t");
    CHECK(terminal.cursorColumn() == 19);
    feed(terminal, "\x1b[1;4H\x1bH\r\t");
    CHECK(terminal.cursorColumn() == 3);
    feed(terminal, "\x1b[1;1H\x1b[1;4;7;31m\x1b" "7\x1b[4;9H\x1b[0m\x1b" "8X");
    CHECK(terminal.cursorColumn() == 1 && terminal.cursorRow() == 0);
    CHECK(terminal.line(0)[0].bold && terminal.line(0)[0].underline && terminal.line(0)[0].inverse);
    CHECK(terminal.line(0)[0].foreground == 0x800000);
    feed(terminal, "\x1b[?1;1000;1006;2004h");
    CHECK(terminal.applicationCursor() && terminal.mouseTracking());
    CHECK(terminal.sgrMouse() && terminal.bracketedPaste());
    feed(terminal, "\x1b[?1;1000;1006;2004l");
    CHECK(!terminal.applicationCursor() && !terminal.mouseTracking());
    CHECK(!terminal.sgrMouse() && !terminal.bracketedPaste());
    feed(terminal, "\x1b[4h\rZ");
    CHECK(row(terminal, 0).substr(0, 2) == U"ZX");
    invariant(terminal);
}

static void colorsAndResponses() {
    TerminalCore terminal(12, 4);
    feed(terminal, "\x1b[38;5;196;48;5;232mA\x1b[38;2;1;2;3;48;2;254;253;252mB");
    CHECK(terminal.line(0)[0].foreground == 0xff0000);
    CHECK(terminal.line(0)[0].background == 0x080808);
    CHECK(terminal.line(0)[1].foreground == 0x010203);
    CHECK(terminal.line(0)[1].background == 0xfefdfc);
    feed(terminal, "\x1b[38:2::9:8:7mC\x1b[39;49mD\x1b[97;100mE");
    CHECK(terminal.line(0)[2].foreground == 0x090807);
    CHECK(terminal.line(0)[3].foreground == 0x000000);
    CHECK(terminal.line(0)[3].background == 0xffffff);
    CHECK(terminal.line(0)[4].foreground == 0xffffff);
    CHECK(terminal.line(0)[4].background == 0x808080);
    feed(terminal, "\x1b[3;4H\x1b[5n\x1b[6n\x1b[?6n\x1b[c\x1b[>c\x1b[18t");
    CHECK(terminal.takeResponses() == "\x1b[0n\x1b[3;4R\x1b[?3;4R\x1b[?1;2c\x1b[>0;1;0c\x1b[8;4;12t");
    CHECK(terminal.takeResponses().empty());
    feed(terminal, "\x1b[2;4r\x1b[?6h\x1b[2;3H\x1b[6n");
    CHECK(terminal.takeResponses() == "\x1b[2;3R");
    for (int n = 0; n < 10000; ++n) feed(terminal, "\x1b[5n");
    CHECK(terminal.takeResponses().size() <= 4096);
    invariant(terminal);
}

static void alternateAndFullScreen() {
    TerminalCore terminal(24, 8);
    feed(terminal, "shell prompt\x1b[3;7H\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H");
    feed(terminal, "\x1b(0lqqqqqqk\x1b(B\x1b[2;1Heditor");
    CHECK(row(terminal, 0).substr(0, 8) == U"┌──────┐");
    CHECK(row(terminal, 1).substr(0, 6) == U"editor");
    for (int frame = 0; frame < 100; ++frame) {
        feed(terminal, "\x1b[8;1Hstatus\r\n\x1b[1;1H");
        CHECK(terminal.historySize() == 0);
    }
    terminal.scroll(100);
    CHECK(terminal.scrollOffset() == 0);
    feed(terminal, "\x1b[?1049l\x1b[?25h");
    CHECK(row(terminal, 0).substr(0, 12) == U"shell prompt");
    CHECK(terminal.cursorRow() == 2 && terminal.cursorColumn() == 6);
    CHECK(terminal.cursorVisible());
    feed(terminal, "\x1b[?1049h");
    CHECK(row(terminal, 0) == U"                        ");
    feed(terminal, "\x1b[?1049l");
    invariant(terminal);
}

static void unicodeAndWideEditing() {
    TerminalCore terminal(8, 3);
    const std::string text = u8"Aą界🙂e\u0301Z";
    for (char byte : text) terminal.feed(&byte, 1);
    CHECK(row(terminal, 0) == (std::u32string{U'A', U'ą', U'界', 0, U'🙂', 0, U'e', U'Z'}));
    CHECK(terminal.cursorColumn() == 7 && terminal.cursorRow() == 0);
    feed(terminal, "\x1b[1;4Hx"); // Overwrite a wide continuation.
    CHECK(row(terminal, 0)[2] == U' ' && row(terminal, 0)[3] == U'x');
    feed(terminal, "\x1b[1;5H\x1b[X"); // Erasing the base also erases the continuation.
    CHECK(row(terminal, 0)[4] == U' ' && row(terminal, 0)[5] == U' ');
    feed(terminal, "\x1b[2;8H" + std::string(u8"界"));
    CHECK(row(terminal, 2)[0] == U'界' && row(terminal, 2)[1] == 0);
    terminal.resize(1, 3);
    invariant(terminal);
    CHECK(row(terminal, 2)[0] == U' '); // A split glyph is removed on narrowing.
    feed(terminal, u8"界");
    CHECK(row(terminal, 2)[0] == 0xfffd); // A wide glyph cannot fit a one-cell screen.

    TerminalCore invalid(12, 2);
    feed(invalid, std::string("\xf0\x80\x80\x80") + "A" + "\xe2" + "B" + "\xed\xa0\x80" + "C");
    CHECK(row(invalid, 0).substr(0, 6) == U"�A�B�C");
    feed(invalid, "\xc2\rD");
    CHECK(row(invalid, 0)[0] == U'D');
    invariant(invalid);
}

static void chunksAndParserDiscard() {
    const std::string input = "\x1b[2J\x1b[H" + std::string(u8"Zażółć gęślą 界🙂") +
        "\r\n\x1b[38;2;7;8;9mcolor\x1b[0m\x1b[?1049hALT\x1b[?1049l" +
        "\x1b]52;c;forbidden clipboard\x1b\\" + "\x1bPignored\x1b\\" +
        "\x1b[2;4r\x1b[4;1Ha\r\nb\r\nc\x1b[r\x1b[6n";
    TerminalCore whole(20, 5), bytes(20, 5), chunks(20, 5);
    feed(whole, input);
    for (char byte : input) bytes.feed(&byte, 1);
    for (std::size_t at = 0; at < input.size(); at += 7)
        chunks.feed(input.data() + at, std::min<std::size_t>(7, input.size() - at));
    sameTerminal(whole, bytes);
    sameTerminal(whole, chunks);
    CHECK(whole.takeResponses() == bytes.takeResponses());
    CHECK(chunks.takeResponses() == "\x1b[1;1R");

    TerminalCore discarded(8, 2);
    discarded.takeDirtyRows();
    feed(discarded, "\x1b]52;c;");
    feed(discarded, std::string(2 * 1024 * 1024, 'x'));
    CHECK(discarded.takeDirtyRows().empty());
    feed(discarded, "\x1b\\A\x1bP");
    feed(discarded, std::string(2 * 1024 * 1024, 'x'));
    feed(discarded, "\x1b\\B\x1b[");
    feed(discarded, std::string(100000, '9'));
    feed(discarded, "HC");
    CHECK(row(discarded, 0) == U"ABC     ");
    feed(discarded, "\x1b]unterminated\x18" "D");
    CHECK(row(discarded, 0) == U"ABCD    ");
    feed(discarded, "\x1b[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;22;23;24;25;26;27;28;29;30;31;32;33;34;35;36;37;38;39;40;41;42;43;44;45;46;47;48;49;50;51;52;53;54;55;56;57;58;59;60;61;62;63;64;65H");
    CHECK(discarded.cursorColumn() == 4);
    invariant(discarded);
}

static void boundedHistoryAndResize() {
    TerminalCore terminal(80, 24);
    for (int line = 0; line < 10000; ++line)
        feed(terminal, std::to_string(line) + "\r\n");
    CHECK(terminal.historySize() == TerminalCore::MaximumHistoryLines);
    terminal.scroll(100);
    const std::u32string anchor = row(terminal, 0);
    feed(terminal, "arrival\r\n");
    CHECK(row(terminal, 0) == anchor);
    terminal.resize(240, 160);
    CHECK(terminal.historySize() == static_cast<int>(TerminalCore::MaximumHistoryCells / 240));
    invariant(terminal);
    terminal.resize(std::numeric_limits<int>::min(), std::numeric_limits<int>::max());
    CHECK(terminal.columns() == 1 && terminal.rows() == TerminalCore::MaximumRows);
    invariant(terminal);
    terminal.reset();
    CHECK(terminal.historySize() == 0 && terminal.scrollOffset() == 0);
    terminal.resize(6, 4);
    feed(terminal, "one\r\ntwo\r\nthree\r\nfour");
    terminal.resize(6, 2);
    CHECK(row(terminal, 0) == U"three ");
    CHECK(row(terminal, 1) == U"four  ");
    CHECK(terminal.historySize() == 2 && terminal.cursorRow() == 1);
    terminal.scroll(2);
    CHECK(row(terminal, 0) == U"one   " && row(terminal, 1) == U"two   ");
    invariant(terminal);
}

static void bulkScrollEquivalence() {
    for (bool margins : {false, true}) {
        for (char command : {'S', 'T'}) {
            for (int count : {1, 7, 20, 999999}) {
                TerminalCore bulk(24, 20), single(24, 20);
                std::string initial;
                for (int y = 1; y <= 20; ++y)
                    initial += "\x1b[" + std::to_string(y) + ";1Hrow " + std::to_string(y);
                if (margins) initial += "\x1b[3;17r";
                initial += "\x1b[41m";
                feed(bulk, initial); feed(single, initial);
                feed(bulk, "\x1b[" + std::to_string(count) + command);
                const int height = margins ? 15 : 20;
                for (int n = 0; n < std::min(count, height); ++n)
                    feed(single, std::string("\x1b[") + command);
                sameTerminal(bulk, single);
                for (int offset = 1; offset <= bulk.historySize(); ++offset) {
                    bulk.scroll(1); single.scroll(1);
                    sameTerminal(bulk, single);
                }
                invariant(bulk); invariant(single);
            }
        }
    }
    TerminalCore stress(240, 160);
    std::string repeated;
    for (int n = 0; n < 580; ++n) repeated += "\x1b[160S";
    const auto start = std::chrono::steady_clock::now();
    feed(stress, repeated);
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::cout << "580 full-height scroll requests: " << elapsed << " ms\n";
    invariant(stress);
}

static void hostileAndFuzz() {
    TerminalCore repetition(240, 160);
    feed(repetition, "x\x1b[999999b");
    CHECK(repetition.cursorRow() == 1 && repetition.cursorColumn() == 1);
    const auto start = std::chrono::steady_clock::now();
    for (int request = 0; request < 6000; ++request) feed(repetition, "\x1b[999999b");
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::cout << "6000 hostile REP requests: " << elapsed << " ms\n";
    invariant(repetition);

    TerminalCore fuzz(80, 24);
    std::mt19937 random(0x50415045);
    std::string input(4096, '\0');
    for (int round = 0; round < 100; ++round) {
        for (char& byte : input) byte = static_cast<char>(random() & 0xff);
        feed(fuzz, input);
        // Cancel incomplete strings/UTF8 before intentional operations.
        feed(fuzz, "\x18\x1b[?1049l");
        fuzz.resize(static_cast<int>(random() % 260), static_cast<int>(random() % 180));
        fuzz.scroll(static_cast<int>(random() % 100) - 50);
        CHECK(fuzz.takeResponses().size() <= 4096);
        invariant(fuzz);
    }
    fuzz.feed(nullptr, 100);
    fuzz.feed("", 0);
    invariant(fuzz);
}

int main() {
    basicControls();
    wrappingAndScrollback();
    editingAndMargins();
    tabsSaveRestoreAndModes();
    colorsAndResponses();
    alternateAndFullScreen();
    unicodeAndWideEditing();
    chunksAndParserDiscard();
    boundedHistoryAndResize();
    bulkScrollEquivalence();
    hostileAndFuzz();
    std::cout << "Paper Terminal core behavior tests passed\n";
}
