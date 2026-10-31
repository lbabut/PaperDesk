#define PAPERSKETCH_BATCH_TEST
#include "../product/payload/apps/papersketch/native/papersketch-ink.c"
#include <assert.h>
int main(void) {
    struct PreviewBatch batch={0};batch.last_ms=-PREVIEW_INTERVAL_MS;
    for(long t=0;t<2000;t+=2) {
        int box[4]={(int)(t/2)%100,100,(int)(t/2)%100+2,104};
        merge_batch(&batch,box);flush_batch(&batch,t,0);
    }
    assert(batch.updates==125);
    assert(batch.dirty);
    flush_batch(&batch,2000,1);
    assert(batch.updates==126 && !batch.dirty);
    flush_batch(&batch,2000,1);assert(batch.updates==126);
    int a[4]={40,50,60,70},b[4]={10,90,20,100};
    merge_batch(&batch,a);merge_batch(&batch,b);
    assert(batch.box[0]==10 && batch.box[1]==50 && batch.box[2]==60 && batch.box[3]==100);
    flush_batch(&batch,2001,0);assert(batch.dirty);
    flush_batch(&batch,2001,1);assert(!batch.dirty && batch.updates==127);
    puts("PASS: 1000 reports coalesced to 126 updates; final tail and union bounds preserved");
    return 0;
}
