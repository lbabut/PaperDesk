#include "../product/payload/apps/papersketch/native/sketch-pen.h"
#include <cassert>
int main(){PaperPen pen;pen.push(100,200,.2);pen.push(120,200,.9);assert(pen.at(100,200)==.2);assert(pen.at(120,200)==.9);assert(pen.at(300,300)<0);pen.pause();assert(pen.at(100,200)<0);}
