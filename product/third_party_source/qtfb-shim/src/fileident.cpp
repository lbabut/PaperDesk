#include "fileident.h"
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>

fileident_t getFileIdentity(int fd) {
    struct stat stat;
    if(fd == -1) return -1ULL;
    if(fstat(fd, &stat) != 0) return -1ULL;
    fileident_t base = 0;
    fileident_t marker = 0;
    if(S_ISCHR(stat.st_mode)) {
        base = stat.st_rdev;
        marker = 1;
    } else if(S_ISBLK(stat.st_mode)) {
        base = stat.st_rdev;
        marker = 2;
    } else if(S_ISREG(stat.st_mode)) {
        base = stat.st_ino;
        marker = 0;
    } else {
        return -1ULL;
    }
    return (base ^ ((base >> 62) & 0b11)) | (marker << 62);
}

fileident_t getFileIdentityFromPath(const char *path) {
    static int (*_open)(const char *, int, mode_t) = (int (*)(const char *, int, mode_t)) dlsym(RTLD_NEXT, "open");
    int fd = _open(path, O_RDONLY, 0);
    fileident_t ident = getFileIdentity(fd);
    if(fd != -1) close(fd);
    return ident;
}