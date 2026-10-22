/* Bounded background downloader. Never writes the reMarkable library itself.
 * Uses system libcurl; native Xochitl performs document import/conversion. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/file.h>
#include <dlfcn.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
#include "curl.h"
#ifndef LIMIT
#define LIMIT (256ULL*1024*1024)
#endif
#ifndef BASE
#define BASE "/home/root/.local/share/paperdesk/books-inbox"
#endif
#ifndef EPUB_LIMIT
#define EPUB_LIMIT (512ULL*1024*1024)
#endif
static CURL *(*init)(void);
static CURLcode (*option)(CURL*,CURLoption,...);
static CURLcode (*perform)(CURL*);
static CURLcode (*info)(CURL*,CURLINFO,...);
static void (*cleanup)(CURL*);
static size_t received;
static char job[512], status_path[600];
static char cancel_path[600];
static int valid_token(const char *s) {
    size_t n=strlen(s);if(n<8||n>80)return 0;
    for(size_t i=0;i<n;i++)if(!isalnum((unsigned char)s[i])&&s[i]!='-'&&s[i]!='_')return 0;
    return 1;
}
static int allowed(const char *url) {
    if(strncmp(url,"https://",8)||strlen(url)>2000)return 0;
    const char *p=url+8,*end=strchr(p,'/');if(!end)return 0;
    size_t n=end-p;if(n>250)return 0;
    char host[256];memcpy(host,p,n);host[n]=0;
    for(const char *c=url;*c;c++)if((unsigned char)*c<33||*c=='\\'||*c=='#')return 0;
    return !strcmp(host,"wolnelektury.pl")||!strcmp(host,"arxiv.org")||!strcmp(host,"export.arxiv.org")||
        !strcmp(host,"assets.openstax.org")||!strcmp(host,"archive.org")||
        (n>12&&!strcmp(host+n-12,".archive.org"));
}
static void quoted(FILE *f,const char *s) {
    fputc('"',f);for(;*s;s++){unsigned char c=*s;if(c=='"'||c=='\\')fputc('\\',f);if(c<32)fprintf(f,"\\u%04x",c);else fputc(c,f);}fputc('"',f);
}
static void status(const char *state,const char *message,const char *path) {
    char tmp[650];snprintf(tmp,sizeof(tmp),"%s.tmp",status_path);
    int fd=open(tmp,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0600);if(fd<0)return;
    FILE *f=fdopen(fd,"w");if(!f){close(fd);unlink(tmp);return;}
    fputs("{\"state\":",f);quoted(f,state);fputs(",\"message\":",f);quoted(f,message);
    fputs(",\"path\":",f);quoted(f,path?path:"");fputs("}\n",f);
    if(fclose(f)==0)rename(tmp,status_path);
}
static size_t write_data(char *data,size_t size,size_t count,void *handle) {
    if(!access(cancel_path,F_OK))return 0;
    if(size&&count>SIZE_MAX/size)return 0;
    size_t n=size*count;if(n>LIMIT-received)return 0;
    received+=n;return fwrite(data,1,n,(FILE*)handle);
}
static uint16_t u16(const unsigned char *p){return p[0]|(p[1]<<8);}
static uint32_t u32(const unsigned char *p){return (uint32_t)u16(p)|((uint32_t)u16(p+2)<<16);}
static int validate(FILE *f,const char *format) {
    if(fseek(f,0,SEEK_END))return 0;
    long len=ftell(f);if(len<100||len>(long)LIMIT)return 0;
    unsigned char head[64];rewind(f);if(fread(head,1,sizeof(head),f)!=sizeof(head))return 0;
    size_t tailn=(size_t)len<65557?(size_t)len:65557;
    unsigned char *tail=malloc(tailn);if(!tail)return 0;
    fseek(f,len-(long)tailn,SEEK_SET);if(fread(tail,1,tailn,f)!=tailn){free(tail);return 0;}
    if(!strcmp(format,"pdf")){
        int ok=!memcmp(head,"%PDF-",5)&&memmem(tail+(tailn>4096?tailn-4096:0),tailn>4096?4096:tailn,"%%EOF",5)!=NULL;
        free(tail);return ok;
    }
    // Verify ZIP central directory and EPUB mimetype, without extracting files.
    long end=-1;
    for(long i=(long)tailn-22;i>=0;i--)if(!memcmp(tail+i,"PK\005\006",4)&&i+22+u16(tail+i+20)==(long)tailn){end=i;break;}
    if(end<0){free(tail);return 0;}
    unsigned char *e=tail+end;uint32_t off=u32(e+16),bytes=u32(e+12);uint16_t count=u16(e+10);
    int ok=u16(e+4)==0&&u16(e+6)==0&&u16(e+8)==count&&count>0&&count<30000&&bytes<8*1024*1024&&
        (uint64_t)off+bytes==(uint64_t)len-tailn+end;
    free(tail);if(!ok)return 0;
    unsigned char *dir=malloc(bytes);if(!dir)return 0;
    fseek(f,off,SEEK_SET);if(fread(dir,1,bytes,f)!=bytes){free(dir);return 0;}
    size_t p=0;int mime=0,container=0,opf=0;uint64_t total=0;
    for(unsigned k=0;k<count;k++){
        if(p+46>bytes||memcmp(dir+p,"PK\001\002",4)){ok=0;break;}
        unsigned char *c=dir+p;size_t n=u16(c+28),extra=u16(c+30),comment=u16(c+32);
        if(p+46+n+extra+comment>bytes||!n||n>4096||u16(c+8)&1){ok=0;break;}
        char name[4097];memcpy(name,c+46,n);name[n]=0;
        total+=u32(c+24);
        if(strlen(name)!=n||name[0]=='/'||strchr(name,'\\')||strstr(name,"../")||!strcmp(name,"..")||total>EPUB_LIMIT){ok=0;break;}
        if(!strcmp(name,"META-INF/container.xml"))container=1;
        if(n>4&&!strcmp(name+n-4,".opf"))opf=1;
        if(!strcmp(name,"mimetype")&&u16(c+10)==0&&u32(c+24)==20){
            unsigned char local[30];long back=ftell(f);fseek(f,u32(c+42),SEEK_SET);
            if(fread(local,1,30,f)==30&&!memcmp(local,"PK\003\004",4)){
                unsigned char value[20];fseek(f,u16(local+26)+u16(local+28),SEEK_CUR);
                mime=fread(value,1,20,f)==20&&!memcmp(value,"application/epub+zip",20);
            }fseek(f,back,SEEK_SET);
        }
        p+=46+n+extra+comment;
    }
    free(dir);return ok&&p==bytes&&mime&&container&&opf;
}
static int private_dir(const char *path) {
    struct stat s;
    if(mkdir(path,0700)&&errno!=EEXIST)return 0;
    return !lstat(path,&s)&&S_ISDIR(s.st_mode)&&s.st_uid==getuid()&&(s.st_mode&077)==0;
}
static void remove_job(void) {
    // Never follow symlinks, recurse, or touch Xochitl's user-document store.
    int fd=open(job,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);if(fd<0)return;
    DIR *d=fdopendir(fd);if(!d){close(fd);return;}
    struct dirent *e;
    while((e=readdir(d))){
        if(!strcmp(e->d_name,".")||!strcmp(e->d_name,".."))continue;
        struct stat s;
        if(!fstatat(fd,e->d_name,&s,AT_SYMLINK_NOFOLLOW)&&S_ISREG(s.st_mode))unlinkat(fd,e->d_name,0);
    }
    closedir(d);rmdir(job);
}
static void prune_staging(void) {
    // Called only while holding the download lock. Retain a week of uncertain
    // imports; delete only our old token directories, never user documents.
    DIR *d=opendir(BASE);if(!d)return;
    struct dirent *e;char current[sizeof(job)];strcpy(current,job);
    time_t now=time(NULL);
    while((e=readdir(d))){
        if(!valid_token(e->d_name))continue;
        snprintf(job,sizeof(job),"%s/%s",BASE,e->d_name);
        struct stat s;
        if(!lstat(job,&s)&&S_ISDIR(s.st_mode)&&s.st_uid==getuid()&&now>s.st_mtime+7*86400)remove_job();
    }
    strcpy(job,current);closedir(d);
}
int main(int argc,char **argv) {
    umask(077);
    if(argc==3&&(!strcmp(argv[1],"--clean")||!strcmp(argv[1],"--cancel"))&&valid_token(argv[2])){
        snprintf(job,sizeof(job),"%s/%s",BASE,argv[2]);
        if(!strcmp(argv[1],"--clean"))remove_job();
        else {
            int dir=open(job,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
            if(dir>=0){int fd=openat(dir,"cancel",O_CREAT|O_WRONLY|O_NOFOLLOW,0600);if(fd>=0)close(fd);close(dir);}
        }
        return 0;
    }
    if(argc!=5||!valid_token(argv[1])||!allowed(argv[2])||
       (strcmp(argv[3],"pdf")&&strcmp(argv[3],"epub"))||!argv[4][0]||strlen(argv[4])>1000)return 64;
    if(!private_dir(BASE))return 73;
    snprintf(job,sizeof(job),"%s/%s",BASE,argv[1]);if(mkdir(job,0700))return 73;
    snprintf(status_path,sizeof(status_path),"%s/status.json",job);
    snprintf(cancel_path,sizeof(cancel_path),"%s/cancel",job);
    char lockpath[512];snprintf(lockpath,sizeof(lockpath),"%s/download.lock",BASE);
    int lock=open(lockpath,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(lock<0||flock(lock,LOCK_EX|LOCK_NB)){status("error","Another book download is running.",NULL);return 75;}
    prune_staging();
    struct statvfs disk;
    if(statvfs(BASE,&disk)||(uint64_t)disk.f_bavail*disk.f_frsize<LIMIT+64*1024*1024){status("error","Keep at least 320 MB free for download and native import.",NULL);return 1;}
    void *lib=dlopen("libcurl.so.4",RTLD_NOW);
    if(!lib){status("error","System HTTPS downloader is unavailable.",NULL);return 1;}
    *(void**)(&init)=dlsym(lib,"curl_easy_init");*(void**)(&option)=dlsym(lib,"curl_easy_setopt");
    *(void**)(&perform)=dlsym(lib,"curl_easy_perform");*(void**)(&info)=dlsym(lib,"curl_easy_getinfo");*(void**)(&cleanup)=dlsym(lib,"curl_easy_cleanup");
    if(!init||!option||!perform||!info||!cleanup){status("error","System HTTPS downloader is incompatible.",NULL);return 1;}
    char filename[200];size_t n=0;
    for(const unsigned char *s=(const unsigned char*)argv[4];*s&&n<120;s++)filename[n++]=*s<32||*s=='/'||*s=='\\'||*s==':'?'_':*s;
    while(n&&((unsigned char)filename[n-1]&0xc0)==0x80)n--;
    if(n&&(unsigned char)filename[n-1]>=0xc0)n--; // Never split UTF-8 in a filename.
    filename[n]=0;if(!n)strcpy(filename,"PaperDesk book");
    char path[800],part[820];snprintf(path,sizeof(path),"%s/%s.%s",job,filename,argv[3]);snprintf(part,sizeof(part),"%s.part",path);
    status("downloading","Downloading for the tablet reader…",NULL);
    time_t started=time(NULL);
    char url[2048];snprintf(url,sizeof(url),"%s",argv[2]);int success=0;
    for(int redirects=0;redirects<6;redirects++){
        long remaining=240-(long)(time(NULL)-started);
        if(!allowed(url)||remaining<1||!access(cancel_path,F_OK))break;
        int fd=open(part,O_CREAT|O_EXCL|O_RDWR|O_NOFOLLOW,0600);if(fd<0)break;
        FILE *f=fdopen(fd,"w+b");if(!f){close(fd);unlink(part);break;}
        CURL *c=init();if(!c){fclose(f);unlink(part);break;}
        received=0;option(c,CURLOPT_URL,url);option(c,CURLOPT_PROTOCOLS,(long)CURLPROTO_HTTPS);
        option(c,CURLOPT_FOLLOWLOCATION,0L);option(c,CURLOPT_CONNECTTIMEOUT,20L);option(c,CURLOPT_TIMEOUT,remaining);
        option(c,CURLOPT_LOW_SPEED_LIMIT,512L);option(c,CURLOPT_LOW_SPEED_TIME,30L);
        option(c,CURLOPT_MAXFILESIZE_LARGE,(curl_off_t)LIMIT);option(c,CURLOPT_WRITEFUNCTION,write_data);option(c,CURLOPT_WRITEDATA,f);
        option(c,CURLOPT_USERAGENT,"PaperDesk-Books/3 (https://paperdesk.lukaszbabut.info/)");
        CURLcode result=perform(c);long code=0;info(c,CURLINFO_RESPONSE_CODE,&code);
        char *redirect=NULL;info(c,CURLINFO_REDIRECT_URL,&redirect);
        if(result==CURLE_OK&&code>=300&&code<400&&redirect&&strlen(redirect)<sizeof(url)){
            snprintf(url,sizeof(url),"%s",redirect);cleanup(c);fclose(f);unlink(part);continue;
        }
        if(result==CURLE_OK&&code==200&&!fflush(f)&&validate(f,argv[3])&&!fsync(fd))success=1;
        cleanup(c);fclose(f);
        if(success&&rename(part,path)==0){status("ready","Ready to import into My files.",path);return 0;}
        unlink(part);break;
    }
    if(!access(cancel_path,F_OK)){remove_job();return 1;}
    status("error","Download failed, is restricted, incomplete or exceeds 256 MB. Nothing was added to My files.",NULL);
    return 1;
}
