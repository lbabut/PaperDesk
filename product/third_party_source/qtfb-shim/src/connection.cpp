#include "qtfb-client/qtfb-client.h"
#include "shim.h"

qtfb::FBKey shimFramebufferKey;
uint8_t shimType = FBFMT_RM2FB;

qtfb::ClientConnection *clientConnection = NULL;
void *shmMemory = NULL;
int shmFD = -1;
int initiatorPID = 0;


void connectShim(){
    char *fbKey = getenv("QTFB_KEY");
    initiatorPID = getpid();
    if(fbKey != NULL) {
        shimFramebufferKey = (unsigned int) strtoul(fbKey, NULL, 10);
    }

    CERR << "Connecting to the shim!" << std::endl;
    if(shmFD == -1) {
        CERR << "Connecting to the shim step2!" << std::endl;
        clientConnection = new qtfb::ClientConnection(shimFramebufferKey, shimType, {}, false);
        shmFD = clientConnection->shmFD;
        shmMemory = clientConnection->shm;

        atexit([](){ if(initiatorPID == getpid()) delete clientConnection; });
    }
}
