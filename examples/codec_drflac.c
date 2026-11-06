/* Example codec: FLAC through dr_flac (public domain, third_party/dr_flac.h
 * in the Peep repo). This is the whole adapter. Any other decoder works the
 * same way: fill rate/channels/total in open(), return int16 in read(). */
#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"
#include "../peep.h"

static int fl_open(peep *p, const void *d, size_t n)
{
    if (n < 4 || d == NULL || ((const unsigned char *)d)[0] != 'f') return 0;
    drflac *f = drflac_open_memory(d, n, NULL);
    if (!f) return 0;
    p->ctx = f;
    p->rate = f->sampleRate;
    p->channels = f->channels;
    p->total = f->totalPCMFrameCount;
    return 1;
}
static size_t fl_read(peep *p, int16_t *o, size_t n) { return drflac_read_pcm_frames_s16(p->ctx, n, o); }
static void   fl_seek(peep *p, uint64_t f)           { drflac_seek_to_pcm_frame(p->ctx, f); }
static void   fl_close(peep *p)                      { drflac_close(p->ctx); }

const peep_codec peep_codec_drflac = { fl_open, fl_read, fl_seek, fl_close };
