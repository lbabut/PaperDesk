// Paper Terminal's original, dependency-free terminal model.
// SPDX-License-Identifier: MIT
#ifndef PAPERTERMINAL_TERMINAL_CORE_H
#define PAPERTERMINAL_TERMINAL_CORE_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <string>
#include <utility>
#include <vector>

namespace PaperTerminal {

struct Cell {
    char32_t codepoint = U' ';
    std::uint32_t foreground = 0x000000;
    std::uint32_t background = 0xffffff;
    bool bold = false;
    bool underline = false;
    bool inverse = false;
};

// A cell with codepoint == 0 is the second column of a wide character. The
// renderer paints its background but must not draw a glyph for that cell.
// Combining characters have zero width; storing composed grapheme clusters is
// intentionally outside this compact model's scope. Resizing preserves cells,
// without reflowing old lines (the PTY's SIGWINCH lets applications redraw).
class TerminalCore {
public:
    static constexpr int MaximumColumns = 240;
    static constexpr int MaximumRows = 160;
    static constexpr int MaximumHistoryLines = 2000;
    static constexpr std::size_t MaximumHistoryCells = 262144;

    explicit TerminalCore(int columns = 80, int rows = 24)
        : columns_(bounded(columns, 1, MaximumColumns)),
          rows_(bounded(rows, 1, MaximumRows)) { reset(); }

    int columns() const { return columns_; }
    int rows() const { return rows_; }
    int cursorColumn() const { return active().x; }
    int cursorRow() const { return active().y; }
    bool cursorVisible() const { return cursorVisible_ && scrollOffset_ == 0; }
    bool applicationCursor() const { return applicationCursor_; }
    bool mouseTracking() const { return mouseModes_ != 0; }
    bool sgrMouse() const { return sgrMouse_; }
    bool bracketedPaste() const { return bracketedPaste_; }
    int scrollOffset() const { return scrollOffset_; }
    int historySize() const { return static_cast<int>(history_.size()); }

    const std::vector<Cell>& line(int row) const {
        row = bounded(row, 0, rows_ - 1);
        if (alternateActive_ || scrollOffset_ == 0)
            return active().lines[static_cast<std::size_t>(row)];
        const int index = historySize() - scrollOffset_ + row;
        if (index < historySize()) return history_[static_cast<std::size_t>(index)];
        return primary_.lines[static_cast<std::size_t>(index - historySize())];
    }

    std::vector<int> takeDirtyRows() {
        std::vector<int> result;
        for (int row = 0; row < rows_; ++row) {
            if (dirty_[static_cast<std::size_t>(row)]) result.push_back(row);
        }
        std::fill(dirty_.begin(), dirty_.end(), false);
        return result;
    }

    std::string takeResponses() {
        std::string result;
        result.swap(responses_);
        return result;
    }

    void reset() {
        primary_ = freshScreen();
        alternate_ = freshScreen();
        alternateActive_ = false;
        history_.clear();
        scrollOffset_ = 0;
        cursorVisible_ = true;
        applicationCursor_ = false;
        bracketedPaste_ = false;
        mouseModes_ = 0;
        sgrMouse_ = false;
        autoWrap_ = true;
        insertMode_ = false;
        newlineMode_ = false;
        originMode_ = false;
        g0Graphics_ = g1Graphics_ = shiftOut_ = false;
        parser_ = Parser::Ground;
        sequence_.clear();
        sequenceOverflow_ = false;
        utfRemaining_ = 0;
        utfCodepoint_ = utfMinimum_ = 0;
        previousCharacter_ = U' ';
        responses_.clear();
        tabs_.assign(static_cast<std::size_t>(columns_), false);
        for (int x = 8; x < columns_; x += 8) tabs_[static_cast<std::size_t>(x)] = true;
        dirty_.assign(static_cast<std::size_t>(rows_), true);
    }

    void resize(int columns, int rows) {
        columns = bounded(columns, 1, MaximumColumns);
        rows = bounded(rows, 1, MaximumRows);
        if (columns == columns_ && rows == rows_) return;
        const int oldColumns = columns_;
        const int oldRows = rows_;
        // Grow/shrink scrollback cells as well, keeping line() rectangular.
        for (auto& historyLine : history_) {
            historyLine.resize(static_cast<std::size_t>(columns), Cell{});
            normalizeLine(historyLine);
        }
        auto resizeScreen = [&](Screen& screen, bool keepHistory) {
            for (auto& screenLine : screen.lines) {
                screenLine.resize(static_cast<std::size_t>(columns), Cell{});
                normalizeLine(screenLine);
            }
            if (rows < oldRows) {
                // Retain the cursor's row and as many following rows as fit.
                const int removeTop = std::min(oldRows - rows,
                                               std::max(0, screen.y - rows + 1));
                if (keepHistory) {
                    for (int n = 0; n < removeTop; ++n)
                        history_.push_back(std::move(screen.lines[static_cast<std::size_t>(n)]));
                }
                screen.lines.erase(screen.lines.begin(), screen.lines.begin() + removeTop);
                screen.y -= removeTop;
                screen.savedY = std::max(0, screen.savedY - removeTop);
            }
            screen.lines.resize(static_cast<std::size_t>(rows),
                                Line(static_cast<std::size_t>(columns), Cell{}));
            screen.x = bounded(screen.x, 0, columns - 1);
            screen.y = bounded(screen.y, 0, rows - 1);
            screen.savedX = bounded(screen.savedX, 0, columns - 1);
            screen.savedY = bounded(screen.savedY, 0, rows - 1);
            screen.top = 0;
            screen.bottom = rows - 1;
            screen.wrapPending = false;
        };
        resizeScreen(primary_, true);
        resizeScreen(alternate_, false);
        columns_ = columns;
        rows_ = rows;
        tabs_.resize(static_cast<std::size_t>(columns), false);
        if (columns > oldColumns) {
            for (int x = oldColumns; x < columns; ++x)
                if (x != 0 && x % 8 == 0) tabs_[static_cast<std::size_t>(x)] = true;
        }
        trimHistory();
        scrollOffset_ = bounded(scrollOffset_, 0, historySize());
        dirty_.assign(static_cast<std::size_t>(rows_), true);
    }

    void scroll(int delta) {
        if (alternateActive_) return;
        const long long offset = static_cast<long long>(scrollOffset_) + delta;
        const int next = static_cast<int>(std::max(0LL, std::min(offset,
                                           static_cast<long long>(historySize()))));
        if (next == scrollOffset_) return;
        scrollOffset_ = next;
        markAll();
    }

    void feed(const char* data, std::size_t length) {
        if (!data) return;
        for (std::size_t index = 0; index < length; ++index)
            consume(static_cast<unsigned char>(data[index]));
    }

private:
    using Line = std::vector<Cell>;
    struct Screen {
        std::vector<Line> lines;
        int x = 0, y = 0, savedX = 0, savedY = 0;
        int top = 0, bottom = 0;
        bool wrapPending = false;
        bool savedOrigin = false, savedAutoWrap = true;
        Cell attribute{}, savedAttribute{};
    };
    enum class Parser { Ground, Escape, EscapeIntermediate, Charset,
                        CSI, OSC, OSCEscape, String, StringEscape };
    int columns_, rows_;
    Screen primary_, alternate_;
    bool alternateActive_ = false;
    std::deque<Line> history_;
    std::vector<bool> dirty_, tabs_;
    int scrollOffset_ = 0;
    bool cursorVisible_ = true, applicationCursor_ = false;
    bool bracketedPaste_ = false, autoWrap_ = true;
    bool insertMode_ = false, newlineMode_ = false, originMode_ = false;
    unsigned mouseModes_ = 0;
    bool sgrMouse_ = false;
    bool g0Graphics_ = false, g1Graphics_ = false, shiftOut_ = false;
    bool charsetG1_ = false;
    unsigned char escapeIntermediate_ = 0;
    Parser parser_ = Parser::Ground;
    std::string sequence_, responses_;
    bool sequenceOverflow_ = false;
    unsigned utfRemaining_ = 0;
    char32_t utfCodepoint_ = 0, utfMinimum_ = 0;
    char32_t previousCharacter_ = U' ';

    static int bounded(int number, int low, int high) {
        return std::max(low, std::min(number, high));
    }
    Screen& active() { return alternateActive_ ? alternate_ : primary_; }
    const Screen& active() const { return alternateActive_ ? alternate_ : primary_; }
    Screen freshScreen() const {
        Screen result;
        result.lines.assign(static_cast<std::size_t>(rows_),
                            Line(static_cast<std::size_t>(columns_), Cell{}));
        result.bottom = rows_ - 1;
        return result;
    }
    void mark(int row) {
        // Live screen rows are displaced down the viewport while the user is
        // reading scrollback; output can still edit those visible live rows.
        if (!alternateActive_) row += scrollOffset_;
        if (row >= 0 && row < rows_) dirty_[static_cast<std::size_t>(row)] = true;
    }
    void markAll() { std::fill(dirty_.begin(), dirty_.end(), true); }
    Cell blank() const {
        Cell result = active().attribute;
        result.codepoint = U' ';
        return result;
    }
    std::size_t historyLimit() const {
        return std::min(static_cast<std::size_t>(MaximumHistoryLines),
                        MaximumHistoryCells / static_cast<std::size_t>(columns_));
    }
    void trimHistory() {
        const std::size_t limit = historyLimit();
        while (history_.size() > limit) history_.pop_front();
        scrollOffset_ = std::min(scrollOffset_, historySize());
    }
    Line addHistory(Line&& oldLine) {
        history_.push_back(std::move(oldLine));
        // Preserve a scrolled-back viewport while output arrives.
        if (scrollOffset_ > 0) ++scrollOffset_;
        Line recycled;
        if (history_.size() > historyLimit()) {
            // Reuse the oldest line's allocation once scrollback is full.
            // Steady output therefore does not allocate a new vector per row.
            recycled = std::move(history_.front());
            history_.pop_front();
        }
        scrollOffset_ = std::min(scrollOffset_, historySize());
        return recycled;
    }
    void respond(const std::string& response) {
        // A hostile program must not allocate indefinitely while the PTY is
        // congested. Status replies are advisory, so discard excess replies.
        if (response.size() <= 4096 - responses_.size()) responses_ += response;
    }
    void moveCursor(int x, int y) {
        Screen& screen = active();
        mark(screen.y);
        screen.x = bounded(x, 0, columns_ - 1);
        screen.y = bounded(y, 0, rows_ - 1);
        screen.wrapPending = false;
        mark(screen.y);
    }
    void saveCursor() {
        Screen& screen = active();
        screen.savedX = screen.x;
        screen.savedY = screen.y;
        screen.savedAttribute = screen.attribute;
        screen.savedOrigin = originMode_;
        screen.savedAutoWrap = autoWrap_;
    }
    void restoreCursor() {
        Screen& screen = active();
        screen.attribute = screen.savedAttribute;
        originMode_ = screen.savedOrigin;
        autoWrap_ = screen.savedAutoWrap;
        moveCursor(screen.savedX, screen.savedY);
    }
    void switchAlternate(bool enable, bool clear, bool save) {
        if (enable == alternateActive_) return;
        if (enable) {
            if (save) saveCursor();
            if (clear) alternate_ = freshScreen();
            alternateActive_ = true;
        } else {
            alternateActive_ = false;
            if (save) restoreCursor();
        }
        scrollOffset_ = 0;
        markAll();
    }
    void scrollUp(int count, bool keepHistory = true) {
        Screen& screen = active();
        count = bounded(count, 1, screen.bottom - screen.top + 1);
        if (keepHistory && !alternateActive_ && screen.top == 0 && screen.bottom == rows_ - 1) {
            for (int row = screen.top; row < screen.top + count; ++row)
                screen.lines[static_cast<std::size_t>(row)] =
                    addHistory(std::move(screen.lines[static_cast<std::size_t>(row)]));
        }
        // Rotate row vectors once. Repeating a one-line shift count times is
        // quadratic for full-screen SU/SD sequences on a large terminal.
        std::rotate(screen.lines.begin() + screen.top,
                    screen.lines.begin() + screen.top + count,
                    screen.lines.begin() + screen.bottom + 1);
        for (int row = screen.bottom - count + 1; row <= screen.bottom; ++row)
            screen.lines[static_cast<std::size_t>(row)].assign(static_cast<std::size_t>(columns_), blank());
        if (scrollOffset_ > 0) markAll();
        else for (int row = screen.top; row <= screen.bottom; ++row) mark(row);
    }
    void scrollDown(int count) {
        Screen& screen = active();
        count = bounded(count, 1, screen.bottom - screen.top + 1);
        std::rotate(screen.lines.begin() + screen.top,
                    screen.lines.begin() + screen.bottom - count + 1,
                    screen.lines.begin() + screen.bottom + 1);
        for (int row = screen.top; row < screen.top + count; ++row)
            screen.lines[static_cast<std::size_t>(row)].assign(static_cast<std::size_t>(columns_), blank());
        for (int row = screen.top; row <= screen.bottom; ++row) mark(row);
    }
    void index() {
        Screen& screen = active();
        screen.wrapPending = false;
        if (screen.y == screen.bottom) scrollUp(1);
        else moveCursor(screen.x, std::min(screen.y + 1, rows_ - 1));
    }
    void reverseIndex() {
        Screen& screen = active();
        screen.wrapPending = false;
        if (screen.y == screen.top) scrollDown(1);
        else moveCursor(screen.x, std::max(0, screen.y - 1));
    }

    // Compact deterministic width rules, independent of host locale. These
    // cover combining marks, CJK, Hangul, full-width forms and common emoji.
    static int characterWidth(char32_t cp) {
        if (cp < 0x20 || (cp >= 0x7f && cp < 0xa0)) return 0;
        if ((cp >= 0x0300 && cp <= 0x036f) || (cp >= 0x0483 && cp <= 0x0489) ||
            (cp >= 0x0591 && cp <= 0x05bd) || cp == 0x05bf ||
            (cp >= 0x05c1 && cp <= 0x05c2) || (cp >= 0x05c4 && cp <= 0x05c5) ||
            cp == 0x05c7 || (cp >= 0x0610 && cp <= 0x061a) ||
            (cp >= 0x064b && cp <= 0x065f) || cp == 0x0670 ||
            (cp >= 0x06d6 && cp <= 0x06ed) ||
            (cp >= 0x1ab0 && cp <= 0x1aff) || (cp >= 0x1dc0 && cp <= 0x1dff) ||
            (cp >= 0x200b && cp <= 0x200f) || (cp >= 0x202a && cp <= 0x202e) ||
            (cp >= 0x2060 && cp <= 0x206f) || (cp >= 0x20d0 && cp <= 0x20ff) ||
            (cp >= 0xfe00 && cp <= 0xfe0f) || (cp >= 0xfe20 && cp <= 0xfe2f) ||
            (cp >= 0x1f3fb && cp <= 0x1f3ff) ||
            (cp >= 0xe0100 && cp <= 0xe01ef)) return 0;
        if (cp >= 0x1100 &&
            (cp <= 0x115f || cp == 0x2329 || cp == 0x232a ||
             (cp >= 0x2e80 && cp <= 0xa4cf && cp != 0x303f) ||
             (cp >= 0xac00 && cp <= 0xd7a3) ||
             (cp >= 0xf900 && cp <= 0xfaff) ||
             (cp >= 0xfe10 && cp <= 0xfe19) ||
             (cp >= 0xfe30 && cp <= 0xfe6f) ||
             (cp >= 0xff00 && cp <= 0xff60) ||
             (cp >= 0xffe0 && cp <= 0xffe6) ||
             (cp >= 0x1f300 && cp <= 0x1faff) ||
             (cp >= 0x20000 && cp <= 0x3fffd))) return 2;
        return 1;
    }
    static void normalizeLine(Line& cells) {
        for (std::size_t column = 0; column < cells.size(); ++column) {
            if (cells[column].codepoint == 0) {
                cells[column].codepoint = U' ';
            } else if (characterWidth(cells[column].codepoint) == 2) {
                if (column + 1 < cells.size() && cells[column + 1].codepoint == 0)
                    ++column;
                else cells[column].codepoint = U' ';
            }
        }
    }
    void clearGlyphAt(Line& cells, int column) {
        if (column < 0 || column >= columns_) return;
        if (cells[static_cast<std::size_t>(column)].codepoint == 0 && column > 0)
            cells[static_cast<std::size_t>(column - 1)] = blank();
        if (column + 1 < columns_ && cells[static_cast<std::size_t>(column + 1)].codepoint == 0)
            cells[static_cast<std::size_t>(column + 1)] = blank();
        cells[static_cast<std::size_t>(column)] = blank();
    }
    void erase(int row, int begin, int end) {
        begin = bounded(begin, 0, columns_);
        end = bounded(end, 0, columns_);
        if (begin >= end) return;
        Line& cells = active().lines[static_cast<std::size_t>(row)];
        clearGlyphAt(cells, begin);
        clearGlyphAt(cells, end - 1);
        std::fill(cells.begin() + begin, cells.begin() + end, blank());
        mark(row);
    }
    void insertCharacters(int count) {
        Screen& screen = active();
        count = bounded(count, 1, columns_ - screen.x);
        Line& cells = screen.lines[static_cast<std::size_t>(screen.y)];
        if (cells[static_cast<std::size_t>(screen.x)].codepoint == 0)
            clearGlyphAt(cells, screen.x);
        std::move_backward(cells.begin() + screen.x, cells.end() - count, cells.end());
        std::fill(cells.begin() + screen.x, cells.begin() + screen.x + count, blank());
        normalizeLine(cells);
        mark(screen.y);
    }
    void deleteCharacters(int count) {
        Screen& screen = active();
        count = bounded(count, 1, columns_ - screen.x);
        Line& cells = screen.lines[static_cast<std::size_t>(screen.y)];
        clearGlyphAt(cells, screen.x);
        if (screen.x + count < columns_ && cells[static_cast<std::size_t>(screen.x + count)].codepoint == 0)
            clearGlyphAt(cells, screen.x + count);
        std::move(cells.begin() + screen.x + count, cells.end(), cells.begin() + screen.x);
        std::fill(cells.end() - count, cells.end(), blank());
        normalizeLine(cells);
        mark(screen.y);
    }
    static char32_t graphicsCharacter(char32_t cp) {
        switch (cp) {
        case U'`': return 0x25c6; case U'a': return 0x2592;
        case U'f': return 0x00b0; case U'g': return 0x00b1;
        case U'j': return 0x2518; case U'k': return 0x2510;
        case U'l': return 0x250c; case U'm': return 0x2514;
        case U'n': return 0x253c; case U'o': return 0x23ba;
        case U'p': return 0x23bb; case U'q': return 0x2500;
        case U'r': return 0x23bc; case U's': return 0x23bd;
        case U't': return 0x251c; case U'u': return 0x2524;
        case U'v': return 0x2534; case U'w': return 0x252c;
        case U'x': return 0x2502; case U'y': return 0x2264;
        case U'z': return 0x2265; case U'{': return 0x03c0;
        case U'|': return 0x2260; case U'}': return 0x00a3;
        case U'~': return 0x00b7; default: return cp;
        }
    }
    void put(char32_t cp) {
        if ((shiftOut_ ? g1Graphics_ : g0Graphics_) && cp >= 0x60 && cp <= 0x7e)
            cp = graphicsCharacter(cp);
        int width = characterWidth(cp);
        if (width == 0) return;
        Screen& screen = active();
        if (screen.wrapPending && autoWrap_) {
            screen.x = 0;
            index();
        }
        screen.wrapPending = false;
        if (width == 2 && screen.x == columns_ - 1) {
            if (autoWrap_ && columns_ > 1) {
                screen.x = 0;
                index();
            } else { cp = 0xfffd; width = 1; }
        }
        if (insertMode_) insertCharacters(width);
        Line& cells = screen.lines[static_cast<std::size_t>(screen.y)];
        clearGlyphAt(cells, screen.x);
        if (width == 2) clearGlyphAt(cells, screen.x + 1);
        Cell character = screen.attribute;
        character.codepoint = cp;
        cells[static_cast<std::size_t>(screen.x)] = character;
        if (width == 2) {
            character.codepoint = 0;
            cells[static_cast<std::size_t>(screen.x + 1)] = character;
        }
        previousCharacter_ = cp;
        mark(screen.y);
        if (screen.x + width >= columns_) {
            screen.x = columns_ - 1;
            screen.wrapPending = autoWrap_;
        } else screen.x += width;
    }
    void tab(int count, bool backwards = false) {
        int x = active().x;
        count = bounded(count, 1, columns_);
        for (int n = 0; n < count; ++n) {
            if (backwards) {
                do { --x; } while (x > 0 && !tabs_[static_cast<std::size_t>(x)]);
                x = std::max(0, x);
            } else {
                do { ++x; } while (x < columns_ - 1 && !tabs_[static_cast<std::size_t>(x)]);
                x = std::min(columns_ - 1, x);
            }
        }
        moveCursor(x, active().y);
    }
    void control(unsigned char byte) {
        switch (byte) {
        case 0x08: moveCursor(active().x - 1, active().y); break;
        case 0x09: tab(1); break;
        case 0x0a: case 0x0b: case 0x0c:
            if (newlineMode_) active().x = 0;
            index(); break;
        case 0x0d: moveCursor(0, active().y); break;
        case 0x0e: shiftOut_ = true; break;
        case 0x0f: shiftOut_ = false; break;
        default: break; // BEL has no blinking or audible side effects on e-ink.
        }
    }
    void consume(unsigned char byte) {
        // CAN/SUB cancel any unterminated control sequence, including strings.
        if (byte == 0x18 || byte == 0x1a) {
            parser_ = Parser::Ground;
            sequence_.clear();
            utfRemaining_ = 0;
            return;
        }
        if (parser_ == Parser::OSC || parser_ == Parser::String) {
            if (byte == 0x1b)
                parser_ = parser_ == Parser::OSC ? Parser::OSCEscape : Parser::StringEscape;
            else if (byte == 0x9c || (parser_ == Parser::OSC && byte == 0x07))
                parser_ = Parser::Ground;
            return; // Titles, clipboard, images and DCS payloads are discarded.
        }
        if (parser_ == Parser::OSCEscape || parser_ == Parser::StringEscape) {
            if (byte == '\\' || byte == 0x9c ||
                (parser_ == Parser::OSCEscape && byte == 0x07)) parser_ = Parser::Ground;
            else if (byte != 0x1b)
                parser_ = parser_ == Parser::OSCEscape ? Parser::OSC : Parser::String;
            return;
        }
        if (byte == 0x1b) {
            if (utfRemaining_) { put(0xfffd); utfRemaining_ = 0; }
            parser_ = Parser::Escape;
            return;
        }
        if (byte < 0x20) {
            if (utfRemaining_) { put(0xfffd); utfRemaining_ = 0; }
            control(byte);
            return;
        }
        if (byte == 0x7f) return;
        if (parser_ == Parser::Escape) {
            parser_ = Parser::Ground;
            switch (byte) {
            case '[': parser_ = Parser::CSI; sequence_.clear(); sequenceOverflow_ = false; break;
            case ']': parser_ = Parser::OSC; break;
            case 'P': case 'X': case '^': case '_': parser_ = Parser::String; break;
            case '(': case ')':
                charsetG1_ = byte == ')'; parser_ = Parser::Charset; break;
            case '#': case '%': case '*': case '+': case '-': case '.': case '/':
                escapeIntermediate_ = byte; parser_ = Parser::EscapeIntermediate; break;
            case '7': saveCursor(); break;
            case '8': restoreCursor(); break;
            case 'D': index(); break;
            case 'E': moveCursor(0, active().y); index(); break;
            case 'M': reverseIndex(); break;
            case 'H': tabs_[static_cast<std::size_t>(active().x)] = true; break;
            case 'c': reset(); break;
            case 'Z': respond("\x1b[?1;2c"); break;
            default: break;
            }
            return;
        }
        if (parser_ == Parser::Charset) {
            (charsetG1_ ? g1Graphics_ : g0Graphics_) = byte == '0';
            parser_ = Parser::Ground;
            return;
        }
        if (parser_ == Parser::EscapeIntermediate) {
            if (escapeIntermediate_ == '#' && byte == '8') {
                for (int row = 0; row < rows_; ++row) {
                    for (Cell& cell : active().lines[static_cast<std::size_t>(row)]) {
                        cell = Cell{};
                        cell.codepoint = U'E';
                    }
                }
                markAll();
            }
            parser_ = Parser::Ground;
            return;
        }
        if (parser_ == Parser::CSI) {
            if (byte >= 0x40 && byte <= 0x7e) {
                if (!sequenceOverflow_) dispatchCSI(static_cast<char>(byte));
                sequence_.clear();
                parser_ = Parser::Ground;
            } else if (byte >= 0x20 && byte <= 0x3f) {
                if (sequence_.size() < 256) sequence_ += static_cast<char>(byte);
                else sequenceOverflow_ = true;
            } else {
                sequence_.clear();
                parser_ = Parser::Ground;
            }
            return;
        }
        if (utfRemaining_) {
            if ((byte & 0xc0) == 0x80) {
                utfCodepoint_ = (utfCodepoint_ << 6) | (byte & 0x3f);
                if (--utfRemaining_ == 0) {
                    if (utfCodepoint_ < utfMinimum_ || utfCodepoint_ > 0x10ffff ||
                        (utfCodepoint_ >= 0xd800 && utfCodepoint_ <= 0xdfff)) put(0xfffd);
                    else put(utfCodepoint_);
                }
                return;
            }
            utfRemaining_ = 0;
            put(0xfffd);
            // Reprocess a non-continuation as the start of the next character.
        }
        if (byte < 0x80) put(byte);
        else if (byte >= 0xc2 && byte <= 0xdf) {
            utfCodepoint_ = byte & 0x1f; utfRemaining_ = 1; utfMinimum_ = 0x80;
        } else if (byte >= 0xe0 && byte <= 0xef) {
            utfCodepoint_ = byte & 0x0f; utfRemaining_ = 2; utfMinimum_ = 0x800;
        } else if (byte >= 0xf0 && byte <= 0xf4) {
            utfCodepoint_ = byte & 0x07; utfRemaining_ = 3; utfMinimum_ = 0x10000;
        } else put(0xfffd);
    }

    static std::uint32_t palette(int number) {
        static constexpr std::uint32_t basic[] = {
            0x000000, 0x800000, 0x008000, 0x808000,
            0x000080, 0x800080, 0x008080, 0xc0c0c0,
            0x808080, 0xff0000, 0x00ff00, 0xffff00,
            0x0000ff, 0xff00ff, 0x00ffff, 0xffffff
        };
        number = bounded(number, 0, 255);
        if (number < 16) return basic[number];
        if (number >= 232) {
            const auto gray = static_cast<std::uint32_t>(8 + (number - 232) * 10);
            return gray * 0x010101;
        }
        number -= 16;
        auto component = [](int value) -> std::uint32_t {
            return static_cast<std::uint32_t>(value == 0 ? 0 : 55 + value * 40);
        };
        return (component(number / 36) << 16) |
               (component((number / 6) % 6) << 8) | component(number % 6);
    }
    void sgr(const std::vector<int>& parameters) {
        Cell& attribute = active().attribute;
        for (std::size_t index = 0; index < parameters.size(); ++index) {
            const int value = parameters[index] < 0 ? 0 : parameters[index];
            switch (value) {
            case 0: attribute = Cell{}; break;
            case 1: attribute.bold = true; break;
            case 4: attribute.underline = true; break;
            case 7: attribute.inverse = true; break;
            case 22: attribute.bold = false; break;
            case 24: attribute.underline = false; break;
            case 27: attribute.inverse = false; break;
            case 39: attribute.foreground = Cell{}.foreground; break;
            case 49: attribute.background = Cell{}.background; break;
            case 38: case 48: {
                std::uint32_t color = 0;
                bool valid = false;
                if (index + 2 < parameters.size() && parameters[index + 1] == 5) {
                    color = palette(parameters[index + 2]); index += 2; valid = true;
                } else if (index + 4 < parameters.size() && parameters[index + 1] == 2) {
                    // ISO colon form may include an omitted color-space slot.
                    std::size_t first = index + 2;
                    if (parameters[first] < 0 && first + 3 < parameters.size()) ++first;
                    if (first + 2 < parameters.size()) {
                        color = (static_cast<std::uint32_t>(bounded(parameters[first], 0, 255)) << 16) |
                                (static_cast<std::uint32_t>(bounded(parameters[first + 1], 0, 255)) << 8) |
                                static_cast<std::uint32_t>(bounded(parameters[first + 2], 0, 255));
                        index = first + 2; valid = true;
                    }
                }
                if (valid) {
                    if (value == 38) attribute.foreground = color;
                    else attribute.background = color;
                }
                break;
            }
            default:
                if (value >= 30 && value <= 37) attribute.foreground = palette(value - 30);
                else if (value >= 40 && value <= 47) attribute.background = palette(value - 40);
                else if (value >= 90 && value <= 97) attribute.foreground = palette(value - 90 + 8);
                else if (value >= 100 && value <= 107) attribute.background = palette(value - 100 + 8);
                break;
            }
        }
    }
    void mode(const std::vector<int>& parameters, bool privateMode, bool enabled) {
        for (int parameter : parameters) {
            if (privateMode) {
                switch (parameter) {
                case 1: applicationCursor_ = enabled; break;
                case 6: originMode_ = enabled; moveCursor(0, enabled ? active().top : 0); break;
                case 7: autoWrap_ = enabled; active().wrapPending = false; break;
                case 25: cursorVisible_ = enabled; mark(active().y); break;
                case 47: switchAlternate(enabled, false, false); break;
                case 1047: switchAlternate(enabled, true, false); break;
                case 1048: if (enabled) saveCursor(); else restoreCursor(); break;
                case 1049: switchAlternate(enabled, true, true); break;
                case 1000: case 1002: case 1003: {
                    const unsigned bit = parameter == 1000 ? 1u : (parameter == 1002 ? 2u : 4u);
                    if (enabled) mouseModes_ |= bit; else mouseModes_ &= ~bit;
                    break;
                }
                case 1006: sgrMouse_ = enabled; break;
                case 2004: bracketedPaste_ = enabled; break;
                default: break;
                }
            } else {
                if (parameter == 4) insertMode_ = enabled;
                if (parameter == 20) newlineMode_ = enabled;
            }
        }
    }
    void dispatchCSI(char final) {
        std::vector<int> parameters;
        parameters.reserve(16);
        bool privateMode = false, secondary = false, intermediate = false;
        std::size_t offset = 0;
        if (!sequence_.empty() && (sequence_[0] == '?' || sequence_[0] == '>')) {
            privateMode = sequence_[0] == '?'; secondary = sequence_[0] == '>'; ++offset;
        }
        int current = -1;
        for (; offset < sequence_.size(); ++offset) {
            const char character = sequence_[offset];
            if (character >= '0' && character <= '9') {
                current = std::min(999999, std::max(0, current) * 10 + character - '0');
            } else if (character == ';' || (character == ':' && final == 'm')) {
                if (parameters.size() >= 63) return;
                parameters.push_back(current); current = -1;
            } else if (character >= 0x20 && character <= 0x2f) intermediate = true;
            else return;
        }
        parameters.push_back(current);
        if (intermediate) {
            // DECSTR soft reset: retain visible output and scrollback.
            if (sequence_ == "!" && final == 'p') {
                active().attribute = Cell{};
                active().top = 0; active().bottom = rows_ - 1;
                insertMode_ = originMode_ = applicationCursor_ = false;
                autoWrap_ = cursorVisible_ = true;
                active().wrapPending = false;
                mark(active().y);
            }
            return;
        }
        auto parameter = [&](std::size_t index, int fallback) {
            return index < parameters.size() && parameters[index] >= 0 ? parameters[index] : fallback;
        };
        const int n = std::max(1, parameter(0, 1));
        Screen& screen = active();
        const int top = originMode_ ? screen.top : 0;
        const int bottom = originMode_ ? screen.bottom : rows_ - 1;
        // Private and secondary prefixes are valid only for their defined
        // commands; do not interpret arbitrary private commands as cursor edits.
        if (secondary && final != 'c') return;
        if (privateMode && final != 'h' && final != 'l' && final != 'n' && final != 'J' && final != 'K') return;
        switch (final) {
        case 'A': moveCursor(screen.x, std::max(top, screen.y - n)); break;
        case 'B': case 'e': moveCursor(screen.x, std::min(bottom, screen.y + n)); break;
        case 'C': case 'a': moveCursor(screen.x + n, screen.y); break;
        case 'D': moveCursor(screen.x - n, screen.y); break;
        case 'E': moveCursor(0, std::min(bottom, screen.y + n)); break;
        case 'F': moveCursor(0, std::max(top, screen.y - n)); break;
        case 'G': case '`': moveCursor(n - 1, screen.y); break;
        case 'd': moveCursor(screen.x, bounded(top + n - 1, top, bottom)); break;
        case 'H': case 'f':
            moveCursor(std::max(1, parameter(1, 1)) - 1,
                       bounded(top + n - 1, top, bottom)); break;
        case 'I': tab(n); break;
        case 'Z': tab(n, true); break;
        case 'J': {
            const int operation = parameter(0, 0);
            if (operation == 0) {
                erase(screen.y, screen.x, columns_);
                for (int row = screen.y + 1; row < rows_; ++row) erase(row, 0, columns_);
            } else if (operation == 1) {
                for (int row = 0; row < screen.y; ++row) erase(row, 0, columns_);
                erase(screen.y, 0, screen.x + 1);
            } else if (operation == 2) {
                for (int row = 0; row < rows_; ++row) erase(row, 0, columns_);
            } else if (operation == 3 && !alternateActive_) {
                history_.clear(); scrollOffset_ = 0; markAll();
            }
            screen.wrapPending = false;
            break;
        }
        case 'K': {
            const int operation = parameter(0, 0);
            if (operation == 0) erase(screen.y, screen.x, columns_);
            else if (operation == 1) erase(screen.y, 0, screen.x + 1);
            else if (operation == 2) erase(screen.y, 0, columns_);
            screen.wrapPending = false;
            break;
        }
        case 'X': erase(screen.y, screen.x, screen.x + std::min(n, columns_)); break;
        case '@': insertCharacters(n); screen.wrapPending = false; break;
        case 'P': deleteCharacters(n); screen.wrapPending = false; break;
        case 'L': case 'M': {
            if (screen.y < screen.top || screen.y > screen.bottom) break;
            const int originalTop = screen.top;
            screen.top = screen.y;
            if (final == 'L') scrollDown(n); else scrollUp(n, false);
            screen.top = originalTop;
            screen.wrapPending = false;
            break;
        }
        case 'S': scrollUp(n); screen.wrapPending = false; break;
        case 'T': scrollDown(n); screen.wrapPending = false; break;
        case 'b':
            // Avoid CPU amplification from a tiny hostile REP sequence. REP is
            // intended for short runs; requests beyond one screen row are
            // truncated to the maximum supported row width (240 cells).
            for (int count = std::min(n, MaximumColumns); count > 0; --count)
                put(previousCharacter_);
            break;
        case 'r': {
            const int first = std::max(1, parameter(0, 1)) - 1;
            const int last = std::max(1, parameter(1, rows_)) - 1;
            if (first < last && first < rows_ && last < rows_) {
                screen.top = first; screen.bottom = last;
                moveCursor(0, originMode_ ? first : 0);
            }
            break;
        }
        case 's': saveCursor(); break;
        case 'u': restoreCursor(); break;
        case 'm': sgr(parameters); break;
        case 'h': mode(parameters, privateMode, true); break;
        case 'l': mode(parameters, privateMode, false); break;
        case 'g':
            if (parameter(0, 0) == 0) tabs_[static_cast<std::size_t>(screen.x)] = false;
            else if (parameter(0, 0) == 3) std::fill(tabs_.begin(), tabs_.end(), false);
            break;
        case 'n':
            if (parameter(0, 0) == 5 && !privateMode) respond("\x1b[0n");
            else if (parameter(0, 0) == 6) {
                const int row = screen.y - (originMode_ ? screen.top : 0) + 1;
                respond(std::string("\x1b[") + (privateMode ? "?" : "") +
                        std::to_string(row) + ";" + std::to_string(screen.x + 1) + "R");
            }
            break;
        case 'c':
            if (parameter(0, 0) == 0)
                respond(secondary ? "\x1b[>0;1;0c" : "\x1b[?1;2c");
            break;
        case 't':
            if (parameter(0, 0) == 18)
                respond("\x1b[8;" + std::to_string(rows_) + ";" + std::to_string(columns_) + "t");
            break;
        default: break;
        }
    }
};

} // namespace PaperTerminal
#endif
