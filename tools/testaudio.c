/* testaudio: a stutter / glitch soak test for the playback API.
 *
 * It behaves like a hostile audio callback. For every file it first decodes the whole stream in one go
 * (the reference), then performs thousands of random operations on a fresh peep: fill with a random number
 * of frames (1, primes, block-size neighbours, huge), seek anywhere (start, end, past the end, block edges),
 * change the volume. Every fill is compared sample for sample with the reference, so any dropped, repeated,
 * stale, shifted or garbled sample at any call boundary is caught, and so is a fill that returns zero before
 * the end of the stream (a stall, heard as a stutter), one that returns more than asked, or one that writes
 * beyond its buffer (canary bytes).
 *
 *   testaudio ITERATIONS file...      exit status 0 = clean
 *
 * Library 0.4.0 and later apply the volume to sources wider than 16 bits before the single reduction to 16 bits; older
 * ones reduce first. Build with -DPEEP_WIDE for the newer behaviour (the reference then also uses peep_fill32).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include "peep.h"

static unsigned long long rs = 88172645463325252ull;
static unsigned long long rnd(void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static long failures, checks;
#define FAIL(...) do { failures++; printf("FAIL %s: ", name); printf(__VA_ARGS__); printf("\n"); return; } while (0)

static const unsigned gains[] = { 256, 256, 256, 0, 1, 77, 100, 164, 200, 255 };
static const size_t sizes[] = { 1, 2, 3, 7, 13, 64, 127, 191, 192, 193, 576, 1000, 1152, 1153, 4096, 4097, 4608, 8191, 65537 };

static void soak(const char *name, const void *data, size_t len, long iters)
{
    static const peep_codec *const codecs[] = { &peep_codec_flac, 0 };
    peep p; void *work = NULL;
    if (!peep_open(&p, codecs, data, len, NULL, 0)) {
        if (!p.work_need) { printf("skip %s (not accepted)\n", name); return; }
        work = calloc(1, p.work_need);
        if (!peep_open(&p, codecs, data, len, work, p.work_need)) { printf("skip %s\n", name); free(work); return; }
    }
    /* reference: the whole stream, unity volume, one pass */
    size_t cap = 1 << 16, n = 0, got; int16_t *ref = malloc(cap * 4);
    while ((got = peep_fill(&p, ref + n * 2, cap - n)) > 0) { n += got; if (n == cap) { cap *= 2; ref = realloc(ref, cap * 4); } }
    checks++;
    if (p.total && p.total != n) { failures++; printf("FAIL %s: decoded %zu frames but the header says %llu\n", name, n, (unsigned long long)p.total); goto out; }
    checks++;
    if (peep_fill(&p, ref + n * 2, 16) != 0) { failures++; printf("FAIL %s: data after the end of the stream\n", name); goto out; }
    peep_seek(&p, 0); peep_set_gain(&p, 256);
#ifdef PEEP_WIDE
    int32_t *ref32 = malloc(n * 8 + 8); size_t n32 = 0, g32;           /* the same stream at full resolution */
    while (n32 < n && (g32 = peep_fill32(&p, ref32 + n32 * 2, n - n32)) > 0) n32 += g32;
    checks++;
    if (n32 != n) { failures++; printf("FAIL %s: peep_fill32 gave %zu frames, peep_fill %zu\n", name, n32, n); free(ref32); goto out; }
    peep_seek(&p, 0); peep_set_gain(&p, 256);
#endif
    int16_t *buf = malloc(65537 * 4 + 64);
    size_t pos = 0; unsigned gain = 256;
    for (long it = 0; it < iters; it++) {
        unsigned long long r = rnd(); unsigned op = r % 16;
        if (op == 0) {                                   /* seek */
            size_t t;
            switch ((r >> 8) % 6) { case 0: t = 0; break; case 1: t = n; break; case 2: t = n + 1 + (r >> 20) % 999; break;
                case 3: t = n ? n - 1 : 0; break; case 4: t = n ? (r >> 20) % n : 0; break;
                default: t = sizes[(r >> 20) % (sizeof sizes / sizeof *sizes)]; t = t < n ? t : n / 2; }
            peep_seek(&p, t); pos = (t < n || p.total == 0) ? t : n; checks++;     /* a stream of unknown length cannot clamp */
            if (p.pos != pos) { failures++; printf("FAIL %s: after seek(%zu) the position is %llu, not %zu\n", name, t, (unsigned long long)p.pos, pos); break; }
        } else if (op == 1) {                            /* volume */
            gain = gains[(r >> 8) % (sizeof gains / sizeof *gains)]; peep_set_gain(&p, gain);
        } else {                                         /* fill */
            size_t ask = (r >> 8) & 1 ? sizes[(r >> 16) % (sizeof sizes / sizeof *sizes)] : 1 + (r >> 16) % 3000;
            memset(buf, 0x5A, ask * 4 + 64);
            size_t g = peep_fill(&p, buf, ask); checks += 3;
            if (g > ask) { failures++; printf("FAIL %s: asked for %zu frames, got %zu\n", name, ask, g); break; }
            for (int i = 0; i < 64; i++) if (((unsigned char *)buf)[ask * 4 + i] != 0x5A) { failures++; printf("FAIL %s: wrote past the end of the buffer (ask %zu)\n", name, ask); goto done; }
            if (g == 0 && pos < n) { failures++; printf("FAIL %s: stall: fill returned 0 at frame %zu of %zu (ask %zu)\n", name, pos, n, ask); break; }
            if (g > (pos < n ? n - pos : 0)) { failures++; printf("FAIL %s: %zu frames returned with only %zu left\n", name, g, pos < n ? n - pos : 0); break; }
            for (size_t i = 0; i < g * 2; i++) {
                int want = ((int)ref[pos * 2 + i] * (int)gain) >> 8;
#ifdef PEEP_WIDE
                if (p.bits > 16 && gain != 256) want = (int)((((long long)ref32[pos * 2 + i] * gain) >> 8) >> 16);
#endif
                if (buf[i] != want) { failures++; printf("FAIL %s: sample %zu (frame %zu, ch %zu) is %d, expected %d (gain %u, ask %zu, op %ld)\n", name, pos * 2 + i, pos + i / 2, i & 1, buf[i], want, gain, ask, it); goto done; }
            }
            pos += g; checks++;
            if (p.pos != pos) { failures++; printf("FAIL %s: position %llu after the fill, expected %zu\n", name, (unsigned long long)p.pos, pos); break; }
        }
    }
done:
    free(buf);
#ifdef PEEP_WIDE
    free(ref32);
#endif
out:
    peep_close(&p); free(ref); free(work);
}

int main(int argc, char **argv)
{
    if (argc < 3) { fprintf(stderr, "usage: testaudio ITERATIONS file...\n"); return 2; }
    long iters = atol(argv[1]); int files = 0;
    for (int i = 2; i < argc; i++) {
        int fd = open(argv[i], O_RDONLY); struct stat st;
        if (fd < 0 || fstat(fd, &st) || !st.st_size) { printf("cannot read %s\n", argv[i]); failures++; continue; }
        void *d = mmap(0, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
        rs ^= (unsigned long long)i * 0x9E3779B97F4A7C15ull; soak(argv[i], d, st.st_size, iters); files++;
        munmap(d, st.st_size); close(fd);
    }
    printf("testaudio: %d files, %ld checks, %ld failures\n", files, checks, failures);
    return failures != 0;
}
