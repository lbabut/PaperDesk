static char test_base[256];
#define WEB_BASE test_base
#define WEB_ENTRY web_worker_main
#include "../product/payload/apps/paperweb-download/web-download.c"
#include <assert.h>
int main(void) {
    strcpy(test_base,"/tmp/paperdesk-web-limit-XXXXXX");assert(mkdtemp(test_base));
    assert(storage_parent(test_base));assert(!chmod(test_base,0755));assert(storage_parent(test_base));
    assert(!chmod(test_base,0777));assert(!storage_parent(test_base));assert(!chmod(test_base,0700));
    assert(web_url("https://example.com/manual.pdf"));
    assert(web_url("https://cdn.example.com/get?id=20"));
    const char *bad[]={"http://example.com/a.pdf","https://localhost/a.pdf","https://192.168.1.1/a.pdf","https://169.254.169.254/a","https://10.1.2.3/a","https://[::1]/a","https://user:pass@example.com/a","https://example.com:8443/a","file:///tmp/a.pdf","https://example.com\\@127.0.0.1/a","https://example.local/a","https://example.com/a#fragment"};
    for(size_t i=0;i<sizeof(bad)/sizeof(bad[0]);i++)assert(!web_url(bad[i]));
    assert(public_v4(0x08080808));
    uint32_t bad_ips[]={0,0x0a000001,0x7f000001,0xa9fea9fe,0xac100001,0xc0a80001,0x64400001,0xe0000001,0xc6120001};
    for(size_t i=0;i<sizeof(bad_ips)/sizeof(bad_ips[0]);i++)assert(!public_v4(bad_ips[i]));
    char ok[]="Content-Length: 12345\r\n",big[]="Content-Length: 67108865\r\n",invalid[]="Content-Length: -1\r\n";
    response_code=200;declared=0;
    assert(headers(ok,1,strlen(ok),NULL)==strlen(ok));assert(declared==12345);
    assert(headers(big,1,strlen(big),NULL)==0);assert(headers(invalid,1,strlen(invalid),NULL)==0);
    declared=0;response_code=200;
    char html[]="Content-Type: text/html\r\n";assert(!headers(html,1,strlen(html),NULL));
    FILE *f=tmpfile();assert(f);received=LIMIT;
    assert(web_write("x",1,1,f)==0);assert(received==LIMIT);fclose(f);
    f=tmpfile();assert(f);received=LIMIT-4;cancel_path[0]=0;
    assert(web_write("1234",1,4,f)==4);assert(received==LIMIT);
    assert(web_write("x",1,1,f)==0);fclose(f);
    f=tmpfile();received=0;assert(!web_write("<html>bad",1,9,f));fclose(f);
    assert(!rmdir(test_base));
    struct curl_sockaddr addr={0};addr.family=AF_INET;addr.socktype=SOCK_STREAM;
    struct sockaddr_in *v4=(struct sockaddr_in*)&addr.addr;v4->sin_port=htons(443);v4->sin_addr.s_addr=htonl(0x7f000001);
    assert(public_socket(NULL,CURLSOCKTYPE_IPCXN,&addr)==CURL_SOCKET_BAD);
    v4->sin_addr.s_addr=htonl(0x08080808);addr.socktype=SOCK_STREAM|SOCK_CLOEXEC;
    int sock=public_socket(NULL,CURLSOCKTYPE_IPCXN,&addr);assert(sock>=0);close(sock);
    assert(progress(NULL,LIMIT+1,0,0,0)==1);
    puts("Web worker URL/IP/redirect policy, header and streaming limits passed");
    return 0;
}
