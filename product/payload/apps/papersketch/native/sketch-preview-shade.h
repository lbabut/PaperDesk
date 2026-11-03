#ifndef PAPER_SKETCH_PREVIEW_SHADE_H
#define PAPER_SKETCH_PREVIEW_SHADE_H
#include <stdint.h>
// Mean optical gray of upright size-3 lines on fresh plain paper, sampled from
// PaperMaterial at 1/16 pressure intervals. Not a replacement for its grain,
// wear, tilt or pigment history. Regenerate with test-sketch-preview-shade.cpp
// compiled with -DGENERATE_PREVIEW_SHADE.
static inline unsigned char sketchPreviewGray(int tool,float pressure) {
    static const unsigned char gray[6][17]={
    {255,254,254,253,253,251,249,244,236,226,215,206,198,191,184,177,171},
    {255,254,254,253,251,249,246,241,228,211,193,177,164,154,144,136,128},
    {255,254,254,253,251,248,244,238,228,208,184,163,146,133,122,112,104},
    {255,254,254,252,250,246,241,233,224,199,170,143,122,107,95,85,78},
    {255,253,251,248,239,224,202,178,154,135,121,110,100,92,84,77,71},
    {255,252,249,241,226,204,179,153,133,118,107,98,90,83,77,71,66}};
    if(tool==8)return 0;
    if(tool<0||tool>=6)return 255;
    if(!(pressure>0))return 255;
    if(pressure>=1)return gray[tool][16];
    float position=pressure*16;int i=(int)position;
    return (unsigned char)(gray[tool][i]+(gray[tool][i+1]-gray[tool][i])*(position-i)+.5f);
}
// Same Bayer thresholds as the final fast display conversion. Screen anchoring
// avoids random flicker and repeated samples never accumulate extra density.
static inline int sketchPreviewDot(int gray,int x,int y) {
    static const unsigned char bayer[8][8]={
    {0,48,12,60,3,51,15,63},{32,16,44,28,35,19,47,31},
    {8,56,4,52,11,59,7,55},{40,24,36,20,43,27,39,23},
    {2,50,14,62,1,49,13,61},{34,18,46,30,33,17,45,29},
    {10,58,6,54,9,57,5,53},{42,26,38,22,41,25,37,21}};
    // Retain a faint 1/8-density guide even below the material's visible
    // deposition threshold. Release restores the exact material pixels.
    if(gray>223)gray=223;
    return gray<=bayer[y&7][x&7]*4+2;
}
#endif
