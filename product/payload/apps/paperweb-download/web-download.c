/* Browser downloads use the Books structural validator and staging utilities,
 * but a separate public-Internet policy and lower resource limits. */
#define LIMIT (64ULL*1024*1024)
#define EPUB_LIMIT (128ULL*1024*1024)
#ifndef WEB_BASE
#define WEB_BASE "/home/root/.local/share/paperdesk/web-inbox"
#endif
#define BASE WEB_BASE
#define main books_worker_main
#include "../paperbooks-download/book-download.c"
#undef main
#include <arpa/inet.h>
#include <sys/socket.h>
#define RESERVE (512ULL*1024*1024)
static const char *problem;
static char transfer_error[200];
static long response_code;
static uint64_t declared;
static uint64_t redirect_bytes;
static time_t last_progress;
static int storage_parent(const char *path) {
    struct stat s;
    if(mkdir(path,0700)&&errno!=EEXIST)return 0;
    /* The pre-existing shared parent may be 0755. Only staging must be 0700. */
    return !lstat(path,&s)&&S_ISDIR(s.st_mode)&&s.st_uid==getuid()&&!(s.st_mode&022);
}

static int public_v4(uint32_t ip) {
    unsigned a=ip>>24,b=(ip>>16)&255,c=(ip>>8)&255;
    return a!=0&&a!=10&&a!=127&&a<224&&
        !(a==100&&b>=64&&b<=127)&&!(a==169&&b==254)&&
        !(a==172&&b>=16&&b<=31)&&!(a==192&&(b==168||(b==0&&(c==0||c==2))||(b==88&&c==99)))&&
        !(a==198&&(b==18||b==19||(b==51&&c==100)))&&!(a==203&&b==0&&c==113);
}
static int web_url(const char *url) {
    if(strncmp(url,"https://",8)||strlen(url)>2000)return 0;
    const char *p=url+8,*end=strpbrk(p,"/?#");size_t n=end?(size_t)(end-p):strlen(p);
    if(!n||n>253)return 0;
    for(const char *c=url;*c;c++)if((unsigned char)*c<33||*c=='\\'||*c=='#')return 0;
    char host[254];memcpy(host,p,n);host[n]=0;
    for(size_t i=0;i<n;i++)if(!isalnum((unsigned char)host[i])&&host[i]!='-'&&host[i]!='.')return 0;
    if(host[0]=='.'||host[n-1]=='.'||strstr(host,".."))return 0;
    struct in_addr addr;
    if(inet_pton(AF_INET,host,&addr)==1)return public_v4(ntohl(addr.s_addr));
    if(!strchr(host,'.')||!strcasecmp(host,"localhost")||
       (n>6&&!strcasecmp(host+n-6,".local")))return 0;
    return 1; /* The resolved address is checked again at socket creation. */
}
static curl_socket_t public_socket(void *unused,curlsocktype purpose,struct curl_sockaddr *addr) {
    (void)unused;
    if(purpose!=CURLSOCKTYPE_IPCXN||addr->family!=AF_INET||(addr->socktype&15)!=SOCK_STREAM){
        snprintf(transfer_error,sizeof(transfer_error),"Unsupported network socket (%d/%d/%d).",(int)purpose,addr->family,addr->socktype);problem=transfer_error;return CURL_SOCKET_BAD;
    }
    struct sockaddr_in *v4=(struct sockaddr_in*)&addr->addr;
    if(ntohs(v4->sin_port)!=443||!public_v4(ntohl(v4->sin_addr.s_addr))){problem="Private/local download addresses are blocked.";return CURL_SOCKET_BAD;}
    return socket(addr->family,addr->socktype,addr->protocol);
}
static int room(void) {
    struct statvfs disk;
    return !statvfs(BASE,&disk)&&(uint64_t)disk.f_bavail*disk.f_frsize>=RESERVE;
}
static size_t headers(char *data,size_t size,size_t count,void *unused) {
    (void)unused;if(size&&count>SIZE_MAX/size)return 0;
    size_t n=size*count;if(n>16384)return 0;
    char line[16385];memcpy(line,data,n);line[n]=0;
    if(!strncasecmp(line,"HTTP/",5)){
        char *space=strchr(line,' ');response_code=space?strtol(space+1,NULL,10):0;declared=0;redirect_bytes=0;
    }else if(!strncasecmp(line,"Content-Type:",13)&&response_code==200){
        char *type=line+13;while(isspace((unsigned char)*type))type++;
        if(!strncasecmp(type,"text/",5)){problem="This link returned a web page or text, not a PDF or EPUB.";return 0;}
    }else if(!strncasecmp(line,"Content-Length:",15)&&response_code==200){
        char *start=line+15,*end;while(isspace((unsigned char)*start))start++;
        if(!isdigit((unsigned char)*start)){problem="Invalid file size.";return 0;}
        errno=0;unsigned long long length=strtoull(start,&end,10);
        while(isspace((unsigned char)*end))end++;
        if(errno||*end||!length||length>LIMIT||(declared&&declared!=length)){
            problem="File is empty, has an invalid size or exceeds 64 MB.";return 0;
        }declared=length;
    }
    return n;
}
static size_t web_write(char *data,size_t size,size_t count,void *handle) {
    if(size&&count>SIZE_MAX/size)return 0;
    size_t n=size*count;
    if(response_code>=300&&response_code<400){
        redirect_bytes+=n;return redirect_bytes<=65536?n:0;
    } /* Redirect bodies are discarded and capped. */
    if(response_code!=200){problem="The server did not return a complete file (HTTP 200).";return 0;}
    if(n>LIMIT-received){problem="Download exceeds the 64 MB limit.";return 0;}
    if(!room()){problem="Download stopped to keep 512 MB free on the tablet.";return 0;}
    if(!access(cancel_path,F_OK))return 0;
    if(!received&&n>=5&&memcmp(data,"%PDF-",5)&&memcmp(data,"PK\003\004",4)){
        problem="This link did not return a PDF or EPUB file.";return 0;
    }
    received+=n;
    return fwrite(data,1,n,(FILE*)handle);
}
static int progress(void *unused,curl_off_t total,curl_off_t now,curl_off_t up_total,curl_off_t up_now) {
    (void)unused;(void)up_total;(void)up_now;
    if(total>(curl_off_t)LIMIT||now>(curl_off_t)LIMIT){problem="Download exceeds the 64 MB limit.";return 1;}
    if(!access(cancel_path,F_OK))return 1;
    if(time(NULL)>last_progress+2){
        if(!room()){problem="Download stopped to keep 512 MB free on the tablet.";return 1;}
        char message[120];
        if(total>0)snprintf(message,sizeof(message),"Downloading: %lld / %lld MB",(long long)(now/1048576),(long long)((total+1048575)/1048576));
        else snprintf(message,sizeof(message),"Downloading: %lld MB (64 MB maximum)",(long long)(now/1048576));
        status("downloading",message,NULL);last_progress=time(NULL);
    }return 0;
}
#ifndef WEB_ENTRY
#define WEB_ENTRY main
#endif
int WEB_ENTRY(int argc,char **argv) {
    umask(077);
    if(argc==3&&!strcmp(argv[1],"--cancel")&&valid_token(argv[2])){
        /* A cancellation may arrive before AppLoad has spawned the transfer. */
        if(!storage_parent("/home/root/.local/share/paperdesk")||!private_dir(BASE))return 73;
        snprintf(job,sizeof(job),"%s/%s",BASE,argv[2]);
        if(mkdir(job,0700)&&errno!=EEXIST)return 73;
        int dir=open(job,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
        if(dir<0)return 73;
        int fd=openat(dir,"cancel",O_CREAT|O_WRONLY|O_NOFOLLOW,0600);
        if(fd>=0)close(fd);
        close(dir);return fd<0?73:0;
    }
    if(argc==3&&(!strcmp(argv[1],"--clean")||!strcmp(argv[1],"--cancel")))return books_worker_main(argc,argv);
    if(argc!=4||!valid_token(argv[1])||!argv[3][0]||strlen(argv[3])>1000)return 64;
    if(!storage_parent("/home/root/.local/share/paperdesk")||!private_dir(BASE))return 73;
    snprintf(job,sizeof(job),"%s/%s",BASE,argv[1]);if(mkdir(job,0700))return 73;
    snprintf(status_path,sizeof(status_path),"%s/status.json",job);
    snprintf(cancel_path,sizeof(cancel_path),"%s/cancel",job);
    if(!web_url(argv[2])){status("error","Use a public HTTPS document link on standard port 443, without embedded credentials.",NULL);return 64;}
    /* Share Books' lock: never run two large document transfers at once. */
    const char *shared="/home/root/.local/share/paperdesk/books-inbox";
    if(!private_dir(shared)){status("error","Download storage is unavailable.",NULL);return 1;}
    char lockpath[512];snprintf(lockpath,sizeof(lockpath),"%s/download.lock",shared);
    int lock=open(lockpath,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(lock<0||flock(lock,LOCK_EX|LOCK_NB)){status("error","Another document download is running.",NULL);return 75;}
    prune_staging();
    struct statvfs disk;
    if(statvfs(BASE,&disk)||(uint64_t)disk.f_bavail*disk.f_frsize<RESERVE+LIMIT){
        status("error","Keep at least 576 MB free before downloading (64 MB file limit plus 512 MB reserve).",NULL);return 1;
    }
    void *lib=dlopen("libcurl.so.4",RTLD_NOW);
    if(!lib){status("error","System HTTPS downloader is unavailable.",NULL);return 1;}
    *(void**)(&init)=dlsym(lib,"curl_easy_init");*(void**)(&option)=dlsym(lib,"curl_easy_setopt");
    *(void**)(&perform)=dlsym(lib,"curl_easy_perform");*(void**)(&info)=dlsym(lib,"curl_easy_getinfo");*(void**)(&cleanup)=dlsym(lib,"curl_easy_cleanup");
    if(!init||!option||!perform||!info||!cleanup){status("error","System HTTPS downloader is incompatible.",NULL);return 1;}
    char name[160];size_t len=0;
    /* Fixed ASCII filesystem name, user-visible title supplied at import time. */
    for(const unsigned char *p=(const unsigned char*)argv[3];*p&&len<100;p++)name[len++]=isalnum(*p)&&*p<128?*p:(*p==' '||*p=='-'||*p=='_'?*p:'_');
    while(len&&name[len-1]=='_')len--;
    name[len]=0;
    if(!len)strcpy(name,"PaperWeb document");
    char part[820];snprintf(part,sizeof(part),"%s/download.part",job);
    status("downloading","Checking file size and downloading…",NULL);
    time_t started=time(NULL);char url[2048];snprintf(url,sizeof(url),"%s",argv[2]);
    for(int redirects=0;redirects<6;redirects++){
        long remaining=180-(long)(time(NULL)-started);
        if(!web_url(url)||remaining<1||!access(cancel_path,F_OK))break;
        int fd=open(part,O_CREAT|O_EXCL|O_RDWR|O_NOFOLLOW,0600);if(fd<0)break;
        FILE *file=fdopen(fd,"w+b");if(!file){close(fd);unlink(part);break;}
        CURL *c=init();if(!c){fclose(file);unlink(part);break;}
        received=0;declared=0;response_code=0;
        /* Refuse to run if this libcurl cannot install any safety option. */
#define SET(k,v) do { if(option(c,k,v)!=CURLE_OK)goto incompatible; } while(0)
        SET(CURLOPT_URL,url);SET(CURLOPT_PROTOCOLS,(long)CURLPROTO_HTTPS);SET(CURLOPT_FOLLOWLOCATION,0L);
        SET(CURLOPT_PROXY,"");SET(CURLOPT_IPRESOLVE,(long)CURL_IPRESOLVE_V4);
        SET(CURLOPT_OPENSOCKETFUNCTION,public_socket);SET(CURLOPT_SSL_VERIFYPEER,1L);SET(CURLOPT_SSL_VERIFYHOST,2L);
        SET(CURLOPT_CONNECTTIMEOUT,15L);SET(CURLOPT_TIMEOUT,remaining);
        SET(CURLOPT_LOW_SPEED_LIMIT,1024L);SET(CURLOPT_LOW_SPEED_TIME,20L);
        SET(CURLOPT_MAXFILESIZE_LARGE,(curl_off_t)LIMIT);
        SET(CURLOPT_HEADERFUNCTION,headers);SET(CURLOPT_WRITEFUNCTION,web_write);SET(CURLOPT_WRITEDATA,file);
        SET(CURLOPT_NOPROGRESS,0L);SET(CURLOPT_XFERINFOFUNCTION,progress);
        SET(CURLOPT_USERAGENT,"PaperDesk-Web/3 (https://paperdesk.lukaszbabut.info/)");
        CURLcode result=perform(c);long code=0;info(c,CURLINFO_RESPONSE_CODE,&code);
        char *redirect=NULL;info(c,CURLINFO_REDIRECT_URL,&redirect);
        if(result==CURLE_OK&&code>=300&&code<400&&redirect&&web_url(redirect)&&strlen(redirect)<sizeof(url)){
            snprintf(url,sizeof(url),"%s",redirect);cleanup(c);fclose(file);unlink(part);continue;
        }
        const char *format=NULL;
        if(result==CURLE_OK&&code==200&&!fflush(file)&&(!declared||declared==received)&&room()){
            if(validate(file,"pdf"))format="pdf";
            else if(validate(file,"epub"))format="epub";
        }
        if(format&&!fsync(fd)){
            char path[800];snprintf(path,sizeof(path),"%s/%s.%s",job,name,format);
            cleanup(c);fclose(file);
            if(!rename(part,path)){status("ready","Ready to add to My files.",path);return 0;}
            unlink(part);break;
        }
        if(!problem){snprintf(transfer_error,sizeof(transfer_error),"Download failed (network %d, HTTP %ld, %zu bytes). The file was not imported.",(int)result,code,received);problem=transfer_error;}
        cleanup(c);fclose(file);unlink(part);break;
incompatible:
        problem="System HTTPS downloader cannot enforce the safety limits.";
        cleanup(c);fclose(file);unlink(part);break;
#undef SET
    }
    if(!access(cancel_path,F_OK)){remove_job();return 1;}
    status("error",problem?problem:"Download failed: incomplete, unsafe, unsupported or larger than 64 MB. Nothing was imported.",NULL);
    return 1;
}
