#define main books_download_main
#include "../product/payload/apps/paperbooks-download/book-download.c"
#undef main
#include <assert.h>
int main(int argc,char **argv) {
    assert(valid_token("safe-request-123"));assert(!valid_token("../etc/passwd"));assert(!valid_token("short"));
    assert(allowed("https://arxiv.org/pdf/2601.12345"));
    assert(allowed("https://ia800123.us.archive.org/file.pdf"));
    const char *bad[]={"http://arxiv.org/pdf/x","https://arxiv.org@127.0.0.1/x","https://arxiv.org.evil.org/x","https://archive.org:443/x","https://127.0.0.1/x","file:///etc/passwd","https://arxiv.org/\\x","https://arxiv.org/x\nfoo"};
    for(size_t i=0;i<sizeof(bad)/sizeof(bad[0]);i++)assert(!allowed(bad[i]));
    assert(argc==4);FILE *f=fopen(argv[1],"rb");assert(f);int ok=validate(f,argv[2]);fclose(f);assert(ok==atoi(argv[3]));
    puts("Book download URL and file validation OK");return 0;
}
