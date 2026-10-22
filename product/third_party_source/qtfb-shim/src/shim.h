#pragma once
#include <iostream>
#define INTERNAL_SHIM_NOT_APPLICABLE (-227008859)

#ifdef DEBUG
#define CERR std::cerr << "[QTFB-SHIM] "
#else
#define CERR if(false) std::cerr
#endif
