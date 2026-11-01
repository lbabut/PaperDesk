// Private OpenSSH askpass bridge for Paper Terminal. SPDX-License-Identifier: MIT
// No password is accepted through argv or the environment. The app supplies a
// single-use credential through an owner-only local Unix socket. Host-key and
// other prompts always require a human answer on the controlling terminal.
#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <termios.h>
#include <fcntl.h>
#include <unistd.h>

namespace {
void wipe(std::string &value) {
    volatile char *data = value.empty() ? nullptr : &value[0];
    for (size_t index = 0; index < value.size(); ++index) data[index] = 0;
    value.clear();
}
bool writeAll(int fd, const char *bytes, size_t size) {
    while (size) {
        const ssize_t written = ::write(fd, bytes, size);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return false;
        bytes += written; size -= size_t(written);
    }
    return true;
}
bool readAll(int fd, char *bytes, size_t size) {
    while (size) {
        const ssize_t count = ::read(fd, bytes, size);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        bytes += count; size -= size_t(count);
    }
    return true;
}
bool passwordPrompt(const std::string &prompt) {
    std::string lower = prompt;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    while (!lower.empty() && std::isspace(static_cast<unsigned char>(lower.back()))) lower.pop_back();
    return lower.size() >= 9 && lower.compare(lower.size() - 9, 9, "password:") == 0;
}
bool remembered(std::string &password) {
    const char *name = ::getenv("PAPERTERMINAL_ASKPASS_SOCKET");
    if (!name || std::strlen(name) >= sizeof(sockaddr_un::sun_path)) return false;
    // The containing directory must be private as well as the socket. Reject
    // unexpected files instead of contacting arbitrary environment endpoints.
    const std::string path(name);
    const size_t separator = path.find_last_of('/');
    if (separator == std::string::npos) return false;
    struct stat directory{}, socketInfo{};
    if (::lstat(path.substr(0, separator).c_str(), &directory) != 0 || !S_ISDIR(directory.st_mode) ||
        directory.st_uid != ::geteuid() || (directory.st_mode & 077) != 0 ||
        ::lstat(name, &socketInfo) != 0 || !S_ISSOCK(socketInfo.st_mode) || socketInfo.st_uid != ::geteuid() ||
        (socketInfo.st_mode & 077) != 0) return false;
    const int descriptor = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (descriptor < 0) return false;
    struct timeval timeout{3, 0};
    ::setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    ::setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
    struct sockaddr_un address{}; address.sun_family = AF_UNIX;
    std::memcpy(address.sun_path, name, path.size() + 1);
    bool success = ::connect(descriptor, reinterpret_cast<sockaddr *>(&address), sizeof address) == 0;
    struct ucred peer{}; socklen_t peerSize = sizeof peer;
    success = success && ::getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, &peer, &peerSize) == 0 && peer.uid == ::geteuid();
    unsigned char header[4]{};
    success = success && readAll(descriptor, reinterpret_cast<char *>(header), sizeof header);
    const uint32_t length = uint32_t(header[0]) << 24 | uint32_t(header[1]) << 16 | uint32_t(header[2]) << 8 | header[3];
    success = success && length > 0 && length <= 1024;
    if (success) { password.resize(length); success = readAll(descriptor, &password[0], length); }
    ::close(descriptor);
    if (!success || password.find_first_of("\r\n") != std::string::npos || password.find('\0') != std::string::npos) {
        wipe(password); return false;
    }
    return true;
}
bool askHuman(const std::string &prompt, bool confirmation, bool notification, std::string &answer) {
    const int tty = ::open("/dev/tty", O_RDWR | O_CLOEXEC);
    if (tty < 0) return false;
    struct termios original{}, input{};
    if (::tcgetattr(tty, &original) != 0) { ::close(tty); return false; }
    input = original;
    if (confirmation) input.c_lflag |= ECHO;
    else input.c_lflag &= ~(ECHO | ECHONL);
    if (::tcsetattr(tty, TCSANOW, &input) != 0) { ::close(tty); return false; }
    bool success = writeAll(tty, prompt.data(), prompt.size());
    if (success && !notification) {
        char character = 0;
        while (answer.size() <= 1024) {
            const ssize_t count = ::read(tty, &character, 1);
            if (count < 0 && errno == EINTR) continue;
            if (count != 1) { success = false; break; }
            if (character == '\n' || character == '\r') break;
            if (character != '\0') answer += character;
        }
        if (answer.size() > 1024) success = false;
    }
    (void)::tcsetattr(tty, TCSANOW, &original);
    if (!confirmation) (void)writeAll(tty, "\r\n", 2);
    ::close(tty);
    if (!success) wipe(answer);
    return success;
}
}

int main(int argc, char **argv) {
    if (argc != 2 || std::strlen(argv[1]) > 8192) return 1;
    const std::string prompt(argv[1]);
    const char *kind = ::getenv("SSH_ASKPASS_PROMPT");
    const bool confirmation = kind && std::strcmp(kind, "confirm") == 0;
    const bool notification = kind && std::strcmp(kind, "none") == 0;
    std::string answer;
    // A host-key prompt can contain arbitrary host text. Its explicit confirm
    // classification takes precedence over any occurrence of "password:".
    bool success = !confirmation && !notification && passwordPrompt(prompt) && remembered(answer);
    if (!success) success = askHuman(prompt, confirmation, notification, answer);
    if (success && !notification) success = writeAll(STDOUT_FILENO, answer.data(), answer.size()) && writeAll(STDOUT_FILENO, "\n", 1);
    wipe(answer);
    return success ? 0 : 1;
}
