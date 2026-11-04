#define main paperSketchCharcoalMain
#include "test-sketch-charcoal-speed.cpp"
#undef main
extern "C" int paperSketchCharcoalTest(int argc,char **argv){return paperSketchCharcoalMain(argc,argv);}
