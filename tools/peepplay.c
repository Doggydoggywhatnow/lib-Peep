/* peepplay: minimal drag-and-drop player for lib-Peep (WAV + native FLAC, nothing else).
 * Opens a black window; drop a .wav or .flac on it to play it. SDL2 is used only for the
 * window, file drops and the audio device; all decoding is lib-Peep.
 *
 *   space  pause/resume      left/right  seek -/+ 5 s      up/down  volume
 *   home   restart           esc / q     quit              (a file may also be given on the command line)
 *
 * Build: gcc -O2 tools/peepplay.c build/libpeep.a $(sdl2-config --cflags --libs) -o peepplay
 */
#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../peep.h"

static const unsigned gains[] = { 0,1,3,6,10,16,23,31,41,52,64,77,92,108,125,144,164,185,207,231,256 };
static const peep_codec *const codecs[] = { &peep_codec_flac, 0 };

static peep p;
static int loaded;
static void *filedata, *work;
static size_t filelen;
static SDL_AudioDeviceID dev;
static volatile long long seek_req = -1;       /* set by the UI thread, served by the audio thread */
static volatile int ended;
static int paused, vol = 20;
static char name[256] = "drop a .wav or .flac file here";

static void audio_cb(void *ud, Uint8 *out, int bytes)
{
    (void)ud;
    size_t want = bytes / 4, got = 0;
    if (seek_req >= 0) { peep_seek(&p, (uint64_t)seek_req); seek_req = -1; ended = 0; }
    while (got < want) {
        size_t n = peep_fill(&p, (int16_t *)out + got * 2, want - got);
        if (!n) { ended = 1; break; }
        got += n;
    }
    memset(out + got * 4, 0, (want - got) * 4);       /* silence after the end */
}

static void unload(void)
{
    if (dev) { SDL_CloseAudioDevice(dev); dev = 0; }
    if (loaded) { peep_close(&p); loaded = 0; }
    free(filedata); free(work); filedata = work = NULL;
}

static int load(const char *path)
{
    unload();
    const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
    snprintf(name, sizeof name, "%s", base);
    FILE *f = fopen(path, "rb");
    if (!f) { snprintf(name, sizeof name, "cannot read %s", base); return 0; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (n <= 0) { fclose(f); snprintf(name, sizeof name, "empty file %s", base); return 0; }
    filedata = malloc(n); filelen = n;
    if (fread(filedata, 1, n, f) != (size_t)n) { fclose(f); unload(); snprintf(name, sizeof name, "read error %s", base); return 0; }
    fclose(f);
    int ok = peep_open(&p, codecs, filedata, filelen, NULL, 0);
    if (!ok && p.work_need) {
        work = calloc(1, p.work_need);
        ok = peep_open(&p, codecs, filedata, filelen, work, p.work_need);
    }
    if (!ok) { free(filedata); free(work); filedata = work = NULL; snprintf(name, sizeof name, "not WAV (16-bit PCM) or FLAC: %s", base); return 0; }
    loaded = 1; ended = 0; seek_req = -1;
    peep_set_gain(&p, gains[vol]);
    SDL_AudioSpec want, have;
    SDL_zero(want);
    want.freq = p.rate; want.format = AUDIO_S16SYS; want.channels = 2; want.samples = 1024; want.callback = audio_cb;
    dev = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);     /* SDL converts if the device cannot do p.rate */
    if (!dev) { snprintf(name, sizeof name, "no audio device: %s", SDL_GetError()); unload(); return 0; }
    paused = 0; SDL_PauseAudioDevice(dev, 0);
    return 1;
}

static void seek_to(long long frame)
{
    if (!loaded) return;
    if (frame < 0) frame = 0;
    seek_req = frame;
}

int main(int argc, char **argv)
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return 1; }
    SDL_Window *win = SDL_CreateWindow("lib-Peep player", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 640, 360, SDL_WINDOW_RESIZABLE);
    SDL_Renderer *ren = win ? SDL_CreateRenderer(win, -1, 0) : NULL;
    if (!ren) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return 1; }
    SDL_EventState(SDL_DROPFILE, SDL_ENABLE);
    if (argc > 1) load(argv[1]);

    int run = 1; Uint32 lastt = 0;
    while (run) {
        SDL_Event e;
        while (SDL_WaitEventTimeout(&e, 100)) {
            if (e.type == SDL_QUIT) run = 0;
            else if (e.type == SDL_DROPFILE) { load(e.drop.file); SDL_free(e.drop.file); }
            else if (e.type == SDL_KEYDOWN) {
                long long step = loaded ? 5LL * p.rate : 0;
                switch (e.key.keysym.sym) {
                case SDLK_ESCAPE: case SDLK_q: run = 0; break;
                case SDLK_SPACE: if (dev) { paused = !paused; SDL_PauseAudioDevice(dev, paused); } break;
                case SDLK_RIGHT: if (loaded) seek_to((long long)p.pos + step); break;
                case SDLK_LEFT:  if (loaded) seek_to((long long)p.pos - step); break;
                case SDLK_HOME:  seek_to(0); break;
                case SDLK_UP:    if (vol < 20) vol++; if (loaded) peep_set_gain(&p, gains[vol]); break;
                case SDLK_DOWN:  if (vol > 0)  vol--; if (loaded) peep_set_gain(&p, gains[vol]); break;
                }
            }
        }
        Uint32 now = SDL_GetTicks();
        if (now - lastt >= 100) {                      /* title shows status; the window itself stays black */
            lastt = now;
            char t[400];
            if (loaded) {
                double pos = (double)p.pos / p.rate, tot = (double)p.total / p.rate;
                snprintf(t, sizeof t, "%s  %s  %d:%02d / %d:%02d  vol %d%%  [space pause, arrows seek/volume]",
                         ended ? "[done]" : paused ? "[paused]" : "[playing]", name,
                         (int)pos / 60, (int)pos % 60, (int)tot / 60, (int)tot % 60, vol * 5);
            } else snprintf(t, sizeof t, "lib-Peep player - %s", name);
            SDL_SetWindowTitle(win, t);
        }
        SDL_SetRenderDrawColor(ren, 0, 0, 0, 255); SDL_RenderClear(ren);
        if (loaded && p.total) {                       /* thin progress line along the bottom edge */
            int w, h; SDL_GetWindowSize(win, &w, &h);
            SDL_Rect r = { 0, h - 3, (int)((double)w * (p.pos > p.total ? p.total : p.pos) / p.total), 3 };
            SDL_SetRenderDrawColor(ren, 90, 90, 90, 255); SDL_RenderFillRect(ren, &r);
        }
        SDL_RenderPresent(ren);
    }
    unload();
    SDL_DestroyRenderer(ren); SDL_DestroyWindow(win); SDL_Quit();
    return 0;
}
