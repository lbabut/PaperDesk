#include <dlfcn.h>
#include <cstdio>
int main(int argc,char **argv){
    if(argc<2)return 2;
    void *module=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!module){std::fprintf(stderr,"%s\n",dlerror());return 2;}
    auto run=reinterpret_cast<int(*)(int,char**)>(dlsym(module,"paperSketchCharcoalTest"));
    if(!run){std::fprintf(stderr,"%s\n",dlerror());dlclose(module);return 2;}
    int result=run(argc-1,argv+1);
    dlclose(module);return result;
}
