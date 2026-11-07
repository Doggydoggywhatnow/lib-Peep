/* bench file [dr|native]  -- decode the whole file from RAM, best of 9 runs */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "../peep.h"
extern const peep_codec peep_codec_drflac;
static double cpu(void){ struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return t.tv_sec+t.tv_nsec/1e9; }
int main(int argc,char**argv){
  FILE*f=fopen(argv[1],"rb"); fseek(f,0,SEEK_END); size_t n=ftell(f); rewind(f);
  unsigned char*d=malloc(n); if (fread(d,1,n,f)!=n) return 1; fclose(f);
  int dr = argc > 2 && !strcmp(argv[2], "dr");
  static const peep_codec*const cd[]={&peep_codec_drflac,0}, *const cn[]={&peep_codec_flac,0};
  const peep_codec*const*cs = dr ? cd : cn;
  static int16_t out[1024*2]; double best=9; size_t frames=0; unsigned rate=44100;
  peep p; void *w=NULL; size_t ws=0;
  if(!peep_open(&p,cs,d,n,w,ws)){ if(!p.work_need){puts("reject");return 1;} w=calloc(1,ws=p.work_need); }
  for(int r=0;r<9;r++){
    if(!peep_open(&p,cs,d,n,w,ws)){puts("reject");return 1;}
    rate=p.rate; frames=0; double t=cpu(); size_t k;
    while((k=peep_fill(&p,out,1024))>0) frames+=k; t=cpu()-t; if(t<best) best=t; peep_close(&p); }
  double secs=(double)frames/rate;
  printf("%-7s %5.0f s audio  %.4f s   %6.0fx realtime   %.2f ns/frame\n", dr?"dr_flac":"native", secs, best, secs/best, best/frames*1e9);
}
