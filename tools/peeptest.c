/* peeptest: a small self-contained test program for lib-Peep (WAV + native FLAC only).
 *   peeptest              run the built-in self test (no files needed)
 *   peeptest FILE         decode FILE, print its info, peak and RMS
 *   peeptest FILE OUT.wav also write the decoded stereo 16-bit audio to OUT.wav
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "../peep.h"

static int fails;
#define CHECK(c) do { if (c) printf("  ok    %s\n", #c); else { printf("  FAIL  %s\n", #c); fails++; } } while (0)

static void le32(uint8_t *p, uint32_t v) { for (int i = 0; i < 4; i++) p[i] = v >> (8 * i); }
static void le16(uint8_t *p, unsigned v) { p[0] = v; p[1] = v >> 8; }

static int16_t tone(size_t i, unsigned rate) { return (int16_t)(10000 * sin(6.2831853 * 440.0 * i / rate)); }

static uint8_t *make_wav(unsigned rate, unsigned ch, size_t frames, size_t *len)
{
    size_t dl = frames * ch * 2; uint8_t *w = calloc(1, 44 + dl);
    memcpy(w, "RIFF", 4); le32(w + 4, 36 + dl); memcpy(w + 8, "WAVEfmt ", 8);
    le32(w + 16, 16); le16(w + 20, 1); le16(w + 22, ch); le32(w + 24, rate);
    le32(w + 28, rate * ch * 2); le16(w + 32, ch * 2); le16(w + 34, 16);
    memcpy(w + 36, "data", 4); le32(w + 40, dl);
    for (size_t i = 0; i < frames; i++)
        for (unsigned c = 0; c < ch; c++)
            le16(w + 44 + (i * ch + c) * 2, (unsigned)tone(i, rate));
    *len = 44 + dl; return w;
}

static int open_any(peep *p, void *d, size_t n, void **work)
{
    static const peep_codec *const codecs[] = { &peep_codec_flac, 0 };
    *work = NULL;
    if (peep_open(p, codecs, d, n, NULL, 0)) return 1;
    if (!p->work_need) return 0;
    *work = calloc(1, p->work_need);
    return peep_open(p, codecs, d, n, *work, p->work_need);
}

static int selftest(void)
{
    size_t len; uint8_t *w = make_wav(44100, 1, 44100, &len);
    peep p; void *work; static int16_t buf[4096 * 2];
    printf("lib-Peep %s self test (built-in WAV, native FLAC linked)\n", LIBPEEP_VERSION);
    CHECK(open_any(&p, w, len, &work));
    CHECK(p.rate == 44100 && p.channels == 1 && p.total == 44100);
    size_t n, tot = 0; int dup = 1;
    while ((n = peep_fill(&p, buf, 4096)) > 0) {
        for (size_t i = 0; i < n; i++) if (buf[2 * i] != buf[2 * i + 1]) dup = 0;
        tot += n;
    }
    CHECK(tot == 44100);
    CHECK(dup);                                   /* mono duplicated to both sides */
    peep_seek(&p, 1000);
    CHECK(peep_fill(&p, buf, 1) == 1 && buf[0] == tone(1000, 44100));
    peep_set_gain(&p, 128); peep_seek(&p, 1000); peep_fill(&p, buf, 1);
    CHECK(abs(buf[0] - tone(1000, 44100) / 2) <= 1);
    peep_seek(&p, 1u << 30); CHECK(peep_fill(&p, buf, 16) == 0);   /* clamps to the end */
    peep_close(&p); free(work);
    uint8_t junk[64] = "not audio at all";
    CHECK(!open_any(&p, junk, sizeof junk, &work));                /* rejected, no crash */
    free(w);
    printf(fails ? "RESULT: %d FAILED\n" : "RESULT: all passed\n", fails);
    return fails != 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) return selftest();
    FILE *f = fopen(argv[1], "rb"); if (!f) { perror(argv[1]); return 3; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    void *d = malloc(n > 0 ? n : 1);
    if (n <= 0 || fread(d, 1, n, f) != (size_t)n) { fprintf(stderr, "cannot read %s\n", argv[1]); return 3; }
    fclose(f);
    peep p; void *work;
    if (!open_any(&p, d, n, &work)) { fprintf(stderr, "REJECTED: not WAV (16-bit PCM) or FLAC\n"); return 1; }
    printf("file     %s\nformat   %s\nrate     %u Hz\nchannels %u\nframes   %llu (%.2f s)\n", argv[1],
           p.kind == 1 ? "WAV" : "FLAC", p.rate, p.channels, (unsigned long long)p.total,
           p.rate ? (double)p.total / p.rate : 0.0);
    FILE *o = argc > 2 ? fopen(argv[2], "wb") : NULL;
    uint8_t hdr[44] = {0}; if (o) fwrite(hdr, 1, 44, o);
    static int16_t buf[4096 * 2]; size_t m, tot = 0; int peak = 0; double sq = 0;
    while ((m = peep_fill(&p, buf, 4096)) > 0) {
        for (size_t i = 0; i < m * 2; i++) { int a = abs(buf[i]); if (a > peak) peak = a; sq += (double)buf[i] * buf[i]; }
        if (o) fwrite(buf, 4, m, o);
        tot += m;
    }
    printf("decoded  %zu frames\npeak     %d\nrms      %.1f\n", tot, peak, tot ? sqrt(sq / (tot * 2.0)) : 0.0);
    if (o) {
        size_t dl = tot * 4; memcpy(hdr, "RIFF", 4); le32(hdr + 4, 36 + dl); memcpy(hdr + 8, "WAVEfmt ", 8);
        le32(hdr + 16, 16); le16(hdr + 20, 1); le16(hdr + 22, 2); le32(hdr + 24, p.rate);
        le32(hdr + 28, p.rate * 4); le16(hdr + 32, 4); le16(hdr + 34, 16); memcpy(hdr + 36, "data", 4); le32(hdr + 40, dl);
        fseek(o, 0, SEEK_SET); fwrite(hdr, 1, 44, o); fclose(o); printf("wrote    %s\n", argv[2]);
    }
    peep_close(&p); free(work); free(d); return 0;
}
