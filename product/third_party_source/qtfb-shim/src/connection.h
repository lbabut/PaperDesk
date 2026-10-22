#pragma once
#include "qtfb-client/qtfb-client.h"


extern qtfb::FBKey shimFramebufferKey;
extern uint8_t shimType;

extern qtfb::ClientConnection *clientConnection;
extern void *shmMemory;
extern int shmFD;
void connectShim();
