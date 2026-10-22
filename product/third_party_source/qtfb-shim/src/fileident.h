#pragma once
#include <stdint.h>

typedef uint64_t fileident_t;

fileident_t getFileIdentity(int fd);
fileident_t getFileIdentityFromPath(const char *path);