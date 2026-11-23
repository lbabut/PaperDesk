/* Read-only, one-process boundary sampler. No scheduling/configuration writes. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>

static int read_line(const char *path,char *out,size_t size) {
    FILE *f=fopen(path,"r");
    if(!f)return 0;
    int ok=fgets(out,(int)size,f)!=NULL;
    fclose(f);return ok;
}
int main(int argc,char **argv) {
    char *end; errno=0;
    if(argc!=2)return 2;
    long pid=strtol(argv[1],&end,10);
    if(errno || *end || pid<=0 || pid>INT_MAX)return 2;
    char base[80],path[160],stat[4096],sched[256],uptime[128];
    snprintf(base,sizeof(base),"/proc/%ld/task",pid);
    DIR *dir=opendir(base);
    if(!dir || !read_line("/proc/uptime",uptime,sizeof(uptime)))return 3;
    fputs(uptime,stdout);
    struct dirent *entry;
    while((entry=readdir(dir))) {
        if(!entry->d_name[0] || strspn(entry->d_name,"0123456789")!=strlen(entry->d_name))continue;
        long tid=strtol(entry->d_name,&end,10);
        if(*end || tid<=0 || tid>INT_MAX)continue;
        snprintf(path,sizeof(path),"%s/%ld/stat",base,tid);
        if(!read_line(path,stat,sizeof(stat)))continue;
        snprintf(path,sizeof(path),"%s/%ld/schedstat",base,tid);
        if(!read_line(path,sched,sizeof(sched)))strcpy(sched,"unavailable\n");
        puts("TASK");fputs(stat,stdout);fputs(sched,stdout);
    }
    closedir(dir);
    if(!read_line("/proc/uptime",uptime,sizeof(uptime)))return 3;
    puts("END");fputs(uptime,stdout);return ferror(stdout)?4:0;
}
