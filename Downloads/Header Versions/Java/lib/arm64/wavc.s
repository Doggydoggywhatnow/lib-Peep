// Liberated Peep compressed-WAV codec (arm64): A-law, mu-law, IMA ADPCM and Microsoft ADPCM. Same behaviour as wavc.asm (x86-64);
// see that file's header for what is covered (IMA follows the reference algorithm, MS ADPCM divides by 256 truncating toward zero,
// a 'fact' chunk trims the last block, ADPCM needs an 80-byte workspace, output is 16-bit with p->bits = 16).
//
// Plug it in:  const peep_codec *c[] = { &peep_codec_wavc, &peep_codec_wavx, &peep_codec_flac, NULL };

.include "abi_a64.inc"

.equ S_BASE, 72                       // u64 address of the first byte of the data chunk
.equ S_POS,  80                       // u64 next frame to hand out
.equ S_DPOS, 88                       // u64 the frame the ADPCM decoder state is positioned at (-1: none yet)
.equ S_BLKP, 96                       // u64 address of the block the decoder is in
.equ S_COEF, 104                      // u64 MS ADPCM: address of the coefficient pairs in the file's fmt chunk
.equ S_FMT,  112                      // u32 1 A-law, 2 mu-law, 3 IMA ADPCM, 4 MS ADPCM
.equ S_SPB,  116                      // u32 frames per ADPCM block
.equ S_BA,   120                      // u32 block align
.equ S_W,    124                      // u32 index of the next frame inside the current block
// workspace (ADPCM): 32 bytes per channel: +0 predictor / sample1, +4 step index / sample2, +8 delta, +12 coef1, +16 coef2; +64 u32 coefficient pairs
.equ WORKNEED, 80

    .text
    .balign 8
ima_index: .byte -1, -1, -1, -1, 2, 4, 6, 8
    .balign 8
ms_adapt:  .hword 230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230
ima_step:  .hword 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118
           .hword 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166
           .hword 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845
           .hword 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767

// ima_nib: w2 = 4-bit code, x10 = channel state -> w0 = the new sample (also stored). Clobbers x0-x5.
    .balign 4
ima_nib:
    ldr   w0, [x10, #4]               // step index
    adrp  x1, ima_step
    add   x1, x1, :lo12:ima_step
    ldrh  w3, [x1, x0, lsl #1]        // step
    lsr   w4, w3, #3                  // diff = step >> 3
    tbz   w2, #0, 1f
    add   w4, w4, w3, lsr #2
1:  tbz   w2, #1, 2f
    add   w4, w4, w3, lsr #1
2:  tbz   w2, #2, 3f
    add   w4, w4, w3
3:  tbz   w2, #3, 4f
    neg   w4, w4
4:  ldr   w5, [x10]
    add   w4, w4, w5                  // predictor + diff, saturated to 16 bits
    mov   w5, #32767
    cmp   w4, w5
    csel  w4, w4, w5, le
    mov   w5, #-32768
    cmp   w4, w5
    csel  w4, w4, w5, ge
    str   w4, [x10]
    and   w2, w2, #7
    adrp  x1, ima_index
    add   x1, x1, :lo12:ima_index
    ldrsb w5, [x1, x2]
    ldr   w0, [x10, #4]
    add   w0, w0, w5
    cmp   w0, #0
    csel  w0, w0, wzr, ge
    mov   w5, #88
    cmp   w0, w5
    csel  w0, w0, w5, le
    str   w0, [x10, #4]
    mov   w0, w4
    ret

// ms_nib: w2 = 4-bit code (x2 zero-extended), x10 = channel state -> w0 = the new sample. Clobbers x0-x6.
    .balign 4
ms_nib:
    ldrsw x0, [x10]                   // sample1
    ldrsw x1, [x10, #12]              // coef1
    mul   x0, x0, x1
    ldrsw x1, [x10, #4]               // sample2
    ldrsw x3, [x10, #16]              // coef2
    madd  x0, x1, x3, x0
    asr   x1, x0, #63
    and   x1, x1, #255                // divide by 256 truncating toward zero: add 255 to a negative number first
    add   x0, x0, x1
    asr   x0, x0, #8
    sub   w4, w2, #16
    tst   w2, #8
    csel  w3, w4, w2, ne              // the code as a signed 4-bit number
    sxtw  x3, w3
    ldrsw x4, [x10, #8]               // delta
    madd  x0, x3, x4, x0
    mov   x5, #32767
    cmp   x0, x5
    csel  x0, x0, x5, le
    mov   x5, #-32768
    cmp   x0, x5
    csel  x0, x0, x5, ge
    ldr   w5, [x10]
    str   w5, [x10, #4]               // sample2 = sample1
    str   w0, [x10]                   // sample1 = the new one
    adrp  x1, ms_adapt
    add   x1, x1, :lo12:ms_adapt
    ldrh  w5, [x1, x2, lsl #1]
    mul   x5, x5, x4
    asr   x5, x5, #8                  // delta = max(16, adapt * delta >> 8), kept below 2^24 so a damaged stream cannot overflow
    mov   x6, #16
    cmp   x5, x6
    csel  x5, x5, x6, ge
    mov   x6, #0x1000000
    cmp   x5, x6
    csel  x5, x5, x6, le
    str   w5, [x10, #8]
    ret

// step: decode one ADPCM frame at the decoder's position into [x20] (int16 per channel); x20 advances; the position moves on.
// x19 = peep. Clobbers x0-x14.
    .balign 4
step:
    str   x30, [sp, #-16]!
    ldr   w8, [x19, #S_W]
    ldr   x9, [x19, #S_BLKP]
    ldr   x11, [x19, #P_WORK]
    ldr   w14, [x19, #P_CH]
    ldr   w0, [x19, #S_FMT]
    cmp   w0, #3
    b.ne  .Lst_ms
    cbnz  w8, .Lst_ima_n
    mov   w12, #0                     // IMA block start: the header holds the first sample and the state of each channel
1:  add   x1, x9, x12, lsl #2
    ldrsh w0, [x1]
    ldrb  w2, [x1, #2]
    mov   w3, #88
    cmp   w2, w3
    csel  w2, w2, w3, ls
    lsl   x3, x12, #5
    add   x3, x11, x3
    str   w0, [x3]
    str   w2, [x3, #4]
    strh  w0, [x20, x12, lsl #1]
    add   w12, w12, #1
    cmp   w12, w14
    b.lo  1b
    b     .Lst_adv
.Lst_ima_n:                           // frame w >= 1 is code k = (w-1) & 7 of group g = (w-1) >> 3, one 4-byte run per channel
    sub   w0, w8, #1
    lsr   w1, w0, #3
    and   w2, w0, #7
    add   w1, w1, #1
    mul   w1, w1, w14
    lsl   w1, w1, #2                  // 4 * ch * (g + 1): header plus the earlier groups
    add   w1, w1, w2, lsr #1          // plus k >> 1
    add   x9, x9, x1                  // the byte of channel 0
    and   w2, w2, #1
    lsl   w13, w2, #2                 // 0 for the low nibble, 4 for the high one
    mov   w12, #0
1:  add   x1, x9, x12, lsl #2
    ldrb  w2, [x1]                    // channel c's byte: 4 bytes on from channel c-1's
    lsr   w2, w2, w13
    and   w2, w2, #15
    lsl   x10, x12, #5
    add   x10, x11, x10
    bl    ima_nib
    strh  w0, [x20, x12, lsl #1]
    add   w12, w12, #1
    cmp   w12, w14
    b.lo  1b
    b     .Lst_adv
.Lst_ms:
    cmp   w8, #2
    b.hs  .Lst_msn
    cbnz  w8, .Lst_ms1
    mov   w12, #0                     // MS block start: per channel predictor index, delta, sample1, sample2 (header = 7 * ch bytes)
1:  ldrb  w0, [x9, x12]
    ldr   w1, [x11, #64]
    sub   w2, w1, #1
    cmp   w0, w1
    csel  w0, w0, w2, lo              // an out-of-range predictor index uses the last pair
    ldr   x1, [x19, #S_COEF]
    add   x1, x1, x0, lsl #2
    ldrsh w2, [x1]
    ldrsh w3, [x1, #2]
    lsl   x4, x12, #5
    add   x4, x11, x4
    str   w2, [x4, #12]
    str   w3, [x4, #16]
    add   x5, x9, x14
    add   x5, x5, x12, lsl #1         // delta at ch + 2c
    ldrsh w2, [x5]                    // the header delta is used as it stands (libsndfile and ffmpeg do the same); only the update floors it at 16
    str   w2, [x4, #8]
    add   x5, x14, x14, lsl #1
    add   x5, x9, x5
    add   x5, x5, x12, lsl #1         // sample1 at 3ch + 2c
    ldrsh w2, [x5]
    str   w2, [x4]
    add   x5, x14, x14, lsl #2
    add   x5, x9, x5
    add   x5, x5, x12, lsl #1         // sample2 at 5ch + 2c
    ldrsh w2, [x5]
    str   w2, [x4, #4]
    strh  w2, [x20, x12, lsl #1]      // frame 0 is sample2
    add   w12, w12, #1
    cmp   w12, w14
    b.lo  1b
    b     .Lst_adv
.Lst_ms1:                             // frame 1 is sample1 of each channel
    mov   w12, #0
1:  lsl   x4, x12, #5
    add   x4, x11, x4
    ldr   w0, [x4]
    strh  w0, [x20, x12, lsl #1]
    add   w12, w12, #1
    cmp   w12, w14
    b.lo  1b
    b     .Lst_adv
.Lst_msn:
    sub   w8, w8, #2                  // j: the nibble index (per channel)
    cmp   w14, #1
    b.eq  .Lst_msmono
    add   x1, x9, #14
    ldrb  w2, [x1, x8]                // stereo: the high nibble is left, the low one right
    mov   w13, w2
    lsr   w2, w2, #4
    mov   x10, x11
    bl    ms_nib
    strh  w0, [x20]
    and   w2, w13, #15
    add   x10, x11, #32
    bl    ms_nib
    strh  w0, [x20, #2]
    b     .Lst_adv
.Lst_msmono:
    lsr   w1, w8, #1
    add   x3, x9, #7
    ldrb  w2, [x3, x1]                // mono: the high nibble first
    and   w3, w2, #15
    lsr   w2, w2, #4
    tst   w8, #1
    csel  w2, w3, w2, ne
    mov   x10, x11
    bl    ms_nib
    strh  w0, [x20]
.Lst_adv:
    ldr   w0, [x19, #S_W]
    add   w0, w0, #1
    ldr   w1, [x19, #S_SPB]
    cmp   w0, w1
    b.lo  1f
    mov   w0, #0
    ldr   x2, [x19, #S_BLKP]
    ldr   w3, [x19, #S_BA]
    add   x2, x2, x3
    str   x2, [x19, #S_BLKP]
1:  str   w0, [x19, #S_W]
    ldr   x1, [x19, #S_DPOS]
    add   x1, x1, #1
    str   x1, [x19, #S_DPOS]
    add   x20, x20, x14, lsl #1
    ldr   x30, [sp], #16
    ret

// wc_adpcm: x20 = output (int16), x21 = frames (>= 1): from the current position S_POS. Resynchronises to the start of the block that holds
// S_POS when the decoder is somewhere else (a seek, or the very first read) by decoding and discarding up to one block of frames.
    .balign 4
wc_adpcm:
    stp   x22, x23, [sp, #-32]!
    str   x30, [sp, #16]
    ldr   x0, [x19, #S_POS]
    ldr   x1, [x19, #S_DPOS]
    cmp   x0, x1
    b.eq  .Lwa_go
    ldr   w2, [x19, #S_SPB]
    udiv  x3, x0, x2
    msub  x22, x3, x2, x0             // frames into the block
    ldr   w4, [x19, #S_BA]
    mul   x5, x3, x4
    ldr   x6, [x19, #S_BASE]
    add   x5, x5, x6
    str   x5, [x19, #S_BLKP]
    str   wzr, [x19, #S_W]
    sub   x0, x0, x22
    str   x0, [x19, #S_DPOS]
    cbz   x22, .Lwa_go
    mov   x23, x20
.Lwa_dl:
    add   x20, sp, #24                // the frames thrown away go to a scratch slot
    bl    step
    subs  x22, x22, #1
    b.ne  .Lwa_dl
    mov   x20, x23
.Lwa_go:
    mov   x22, x21
1:  bl    step
    subs  x22, x22, #1
    b.ne  1b
    ldr   x30, [sp, #16]
    ldp   x22, x23, [sp], #32
    ret

// wc_rd: produce x21 frames (already limited to what is left) into [x20] as int16 in the file's own channel count; the position advances.
// Preserves x19-x21 (x20 is not advanced for the caller).
    .balign 4
wc_rd:
    str   x30, [sp, #-16]!
    ldr   w0, [x19, #S_FMT]
    cmp   w0, #2
    b.hi  .Lrd_adpcm
    ldr   x1, [x19, #S_POS]           // A-law / mu-law: one byte per sample, stateless
    ldr   w2, [x19, #P_CH]
    mul   x3, x1, x2
    ldr   x4, [x19, #S_BASE]
    add   x4, x4, x3
    mul   x5, x21, x2                 // samples
    cbz   x5, .Lrd_done
    mov   x6, x20
    cmp   w0, #2
    b.eq  .Lrd_mu
.Lrd_al:
    ldrb  w7, [x4], #1
    mov   w1, #0x55
    eor   w7, w7, w1
    and   w8, w7, #15
    lsl   w8, w8, #4
    ubfx  w9, w7, #4, #3
    cbz   w9, 1f
    add   w8, w8, #0x108
    sub   w10, w9, #1
    lsl   w8, w8, w10
    b     2f
1:  add   w8, w8, #8
2:  neg   w10, w8
    tst   w7, #0x80
    csel  w8, w8, w10, ne
    strh  w8, [x6], #2
    subs  x5, x5, #1
    b.ne  .Lrd_al
    b     .Lrd_done
.Lrd_mu:
    ldrb  w7, [x4], #1
    mvn   w7, w7
    and   w7, w7, #0xFF
    and   w8, w7, #15
    lsl   w8, w8, #3
    add   w8, w8, #0x84
    ubfx  w9, w7, #4, #3
    lsl   w8, w8, w9
    mov   w10, #0x84
    sub   w11, w10, w8
    sub   w12, w8, w10
    tst   w7, #0x80
    csel  w8, w11, w12, ne
    strh  w8, [x6], #2
    subs  x5, x5, #1
    b.ne  .Lrd_mu
    b     .Lrd_done
.Lrd_adpcm:
    mov   x13, x20
    str   x13, [sp, #-16]!
    bl    wc_adpcm
    ldr   x20, [sp], #16
.Lrd_done:
    ldr   x1, [x19, #S_POS]
    add   x1, x1, x21
    str   x1, [x19, #S_POS]
    ldr   x30, [sp], #16
    ret

// wc_take: x21 = frames wanted -> frames available (0 when nothing is left)
    .balign 4
wc_take:
    ldr   x0, [x19, #P_TOTAL]
    ldr   x1, [x19, #S_POS]
    subs  x0, x0, x1
    b.ls  1f
    cmp   x21, x0
    csel  x21, x21, x0, lo
    ret
1:  mov   x21, #0
    ret

// size_t read(peep *p, int16_t *out, size_t frames)
    .balign 4
wc_read:
    stp   x29, x30, [sp, #-48]!
    mov   x29, sp
    stp   x19, x20, [sp, #16]
    str   x21, [sp, #32]
    mov   x19, x0
    mov   x20, x1
    mov   x21, x2
    bl    wc_take
    cbz   x21, 1f
    bl    wc_rd
1:  mov   x0, x21
    ldr   x21, [sp, #32]
    ldp   x19, x20, [sp, #16]
    ldp   x29, x30, [sp], #48
    ret

// size_t read32(peep *p, int32_t *out, size_t frames): each sample << 16
    .balign 4
wc_read32:
    stp   x29, x30, [sp, #-80]!
    mov   x29, sp
    stp   x19, x20, [sp, #16]
    stp   x21, x22, [sp, #32]
    stp   x23, x24, [sp, #48]
    mov   x19, x0
    mov   x22, x1
    mov   x21, x2
    bl    wc_take
    cbz   x21, .Lr32_z
    mov   x23, x21                    // frames to return
    mov   x24, x21                    // frames still to hand out
    sub   sp, sp, #2064               // 128 frames of up to 8 channels as int16, plus slack
.Lr32_c:
    cbz   x24, .Lr32_fin
    mov   x21, #128
    cmp   x24, x21
    csel  x21, x24, x21, lo
    sub   x24, x24, x21
    mov   x20, sp
    bl    wc_rd
    ldr   w2, [x19, #P_CH]
    mul   x2, x2, x21
    mov   x1, sp
.Lr32_w:
    ldrsh w3, [x1], #2
    lsl   w3, w3, #16
    str   w3, [x22], #4
    subs  x2, x2, #1
    b.ne  .Lr32_w
    b     .Lr32_c
.Lr32_fin:
    add   sp, sp, #2064
    mov   x21, x23
.Lr32_z:
    mov   x0, x21
    ldp   x23, x24, [sp, #48]
    ldp   x21, x22, [sp, #32]
    ldp   x19, x20, [sp, #16]
    ldp   x29, x30, [sp], #80
    ret

// void seek(peep *p, uint64_t frame)
    .balign 4
wc_seek:
    ldr   x2, [x0, #P_TOTAL]
    cmp   x1, x2
    csel  x1, x1, x2, lo
    str   x1, [x0, #S_POS]
    ret

// int open(peep *p, const void *data, size_t len)
    .balign 4
wc_open:
    mov   x9, x0
    mov   x10, x1
    mov   x11, x2
    cmp   x11, #44
    b.lo  .Lwo_fail
    ldr   w3, [x10]
    MOV32 w4, 0x46464952              // 'RIFF'
    cmp   w3, w4
    b.ne  .Lwo_fail
    ldr   w3, [x10, #8]
    MOV32 w4, 0x45564157              // 'WAVE'
    cmp   w3, w4
    b.ne  .Lwo_fail
    str   wzr, [x9, #S_FMT]
    mov   w17, #0                     // 'fact' sample count, 0 = none
    mov   x12, #12                    // chunk cursor
.Lwo_chunk:
    add   x3, x12, #8
    cmp   x3, x11
    b.hi  .Lwo_fail
    ldr   w3, [x10, x12]              // chunk id
    add   x5, x10, x12
    ldr   w4, [x5, #4]                // chunk size
    add   x6, x12, #8                 // body offset
    add   x7, x10, x6                 // body
    MOV32 w8, 0x20746d66              // 'fmt '
    cmp   w3, w8
    b.eq  .Lwo_fmt
    MOV32 w8, 0x74636166              // 'fact'
    cmp   w3, w8
    b.eq  .Lwo_fact
    MOV32 w8, 0x61746164              // 'data'
    cmp   w3, w8
    b.eq  .Lwo_data
.Lwo_next:
    and   x3, x4, #1                  // odd-sized chunks carry a pad byte
    add   x12, x6, x4
    add   x12, x12, x3
    b     .Lwo_chunk
.Lwo_fact:
    cmp   w4, #4
    b.lo  .Lwo_next
    add   x8, x6, #4
    cmp   x8, x11
    b.hi  .Lwo_next                   // the body is not all in the file: treat the chunk as absent
    ldr   w17, [x7]
    b     .Lwo_next
.Lwo_fmt:
    cmp   w4, #16
    b.lo  .Lwo_fail
    add   x8, x6, #16
    cmp   x8, x11
    b.hi  .Lwo_fail
    ldrh  w3, [x7]                    // format tag
    movz  w8, #0xFFFE
    cmp   w3, w8
    b.ne  .Lwo_tg
    cmp   w4, #40                     // extensible: only A-law and mu-law (the sub-format's first word is the tag)
    b.lo  .Lwo_fail
    add   x8, x6, #40
    cmp   x8, x11
    b.hi  .Lwo_fail
    ldrh  w3, [x7, #24]
    cmp   w3, #6
    b.eq  .Lwo_tg
    cmp   w3, #7
    b.ne  .Lwo_fail
.Lwo_tg:
    ldrh  w15, [x7, #2]               // channels
    sub   w0, w15, #1
    cmp   w0, #7
    b.hi  .Lwo_fail
    cmp   w3, #6
    b.eq  .Lwo_law
    cmp   w3, #7
    b.eq  .Lwo_law
    cmp   w15, #2                     // ADPCM: mono or stereo, 4 bits
    b.hi  .Lwo_fail
    ldrh  w0, [x7, #14]
    cmp   w0, #4
    b.ne  .Lwo_fail
    ldrh  w14, [x7, #12]              // block align
    cmp   w3, #0x11
    b.eq  .Lwo_ima
    cmp   w3, #2
    b.ne  .Lwo_fail
    lsl   w0, w15, #3                 // MS ADPCM: header 7 * ch bytes, then at least one byte of codes
    sub   w0, w0, w15
    cmp   w14, w0
    b.ls  .Lwo_fail
    cmp   w4, #22
    b.lo  .Lwo_fail
    ldrh  w1, [x7, #20]               // number of coefficient pairs
    cbz   w1, .Lwo_fail
    lsl   w2, w1, #2
    add   w2, w2, #22
    cmp   w2, w4
    b.hi  .Lwo_fail
    str   x1, [x9, #P_CTX]            // kept until the data chunk, then copied to the workspace
    add   x2, x7, #22
    str   x2, [x9, #S_COEF]
    sub   w2, w14, w0
    lsl   w2, w2, #1
    udiv  w2, w2, w15
    add   w2, w2, #2                  // frames per block = 2 + (ba - 7ch) * 2 / ch
    mov   w3, #4
    b     .Lwo_set
.Lwo_ima:
    lsl   w0, w15, #2                 // IMA ADPCM: 4 * ch header bytes, then whole groups of 4 * ch bytes
    lsl   w1, w0, #1
    cmp   w14, w1
    b.lo  .Lwo_fail
    udiv  w1, w14, w0
    msub  w1, w1, w0, w14
    cbnz  w1, .Lwo_fail
    sub   w2, w14, w0
    lsl   w2, w2, #1
    udiv  w2, w2, w15
    add   w2, w2, #1                  // frames per block = (ba - 4ch) * 2 / ch + 1
    mov   w3, #3
    b     .Lwo_set
.Lwo_law:
    ldrh  w0, [x7, #14]
    cmp   w0, #8
    b.ne  .Lwo_fail
    sub   w3, w3, #5                  // 6 -> 1, 7 -> 2
    ldrh  w14, [x7, #12]
    mov   w2, #0
.Lwo_set:
    str   w3, [x9, #S_FMT]
    str   w2, [x9, #S_SPB]
    str   w14, [x9, #S_BA]
    str   w15, [x9, #P_CH]
    ldr   w0, [x7, #4]
    str   w0, [x9, #P_RATE]
    mov   w0, #16
    strh  w0, [x9, #P_BITS]
    b     .Lwo_next
.Lwo_data:
    ldr   w3, [x9, #S_FMT]
    cbz   w3, .Lwo_fail
    sub   x0, x11, x6                 // bytes actually present
    cmp   x4, x0
    csel  x4, x4, x0, lo              // clamp truncated / unknown-length files
    add   x0, x10, x6
    str   x0, [x9, #S_BASE]
    ldr   w15, [x9, #P_CH]
    cmp   w3, #2
    b.hi  .Lwo_adpcm
    udiv  x0, x4, x15                 // A-law / mu-law: frames = bytes / channels
    b     .Lwo_total
.Lwo_adpcm:
    ldr   x0, [x9, #P_WORK]           // the decoder state lives in the host's workspace
    cbz   x0, .Lwo_need
    ldr   x1, [x9, #P_WSIZE]
    cmp   x1, #WORKNEED
    b.lo  .Lwo_need
    ldr   x1, [x9, #P_CTX]
    str   w1, [x0, #64]               // number of coefficient pairs (MS ADPCM)
    ldr   w14, [x9, #S_BA]
    udiv  x0, x4, x14
    msub  x1, x0, x14, x4             // x0 = whole blocks, x1 = bytes left over
    ldr   w2, [x9, #S_SPB]
    mul   x0, x0, x2                  // frames of the whole blocks
    ldr   w3, [x9, #S_FMT]
    cmp   w3, #3
    b.ne  .Lwo_msrem
    lsl   x2, x15, #2                 // IMA: a partial block holds 1 + 8 frames per whole group after the header
    cmp   x1, x2
    b.lo  .Lwo_remdone
    sub   x1, x1, x2
    udiv  x1, x1, x2
    lsl   x1, x1, #3
    add   x1, x1, #1
    add   x0, x0, x1
    b     .Lwo_remdone
.Lwo_msrem:
    lsl   x2, x15, #3                 // MS: a partial block holds 2 + (bytes - 7ch) * 2 / ch frames
    sub   x2, x2, x15
    cmp   x1, x2
    b.lo  .Lwo_remdone
    sub   x1, x1, x2
    lsl   x1, x1, #1
    udiv  x1, x1, x15
    add   x1, x1, #2
    add   x0, x0, x1
.Lwo_remdone:
    cbz   w17, .Lwo_total             // a 'fact' chunk trims the padding of the last block
    cmp   x0, x17
    csel  x0, x0, x17, ls
.Lwo_total:
    str   x0, [x9, #P_TOTAL]
    str   xzr, [x9, #S_POS]
    mov   x1, #-1
    str   x1, [x9, #S_DPOS]
    str   wzr, [x9, #S_W]
    mov   w0, #1
    ret
.Lwo_need:
    mov   x0, #WORKNEED
    str   x0, [x9, #P_WNEED]
.Lwo_fail:
    mov   w0, #0
    ret

// const peep_codec *peep_wavc(void)
FUNC peep_wavc
.ifdef APPLE
    adrp  x0, _peep_codec_wavc@PAGE
    add   x0, x0, _peep_codec_wavc@PAGEOFF
.else
    adrp  x0, :got:peep_codec_wavc
    ldr   x0, [x0, :got_lo12:peep_codec_wavc]
.endif
    ret

// ============================================================================
    DATA_RO
.ifdef APPLE
    .globl _peep_codec_wavc
_peep_codec_wavc:
.else
    .globl peep_codec_wavc
    .type peep_codec_wavc, %object
peep_codec_wavc:
.endif
    .quad wc_open, wc_read, wc_seek, 0, wc_read32

NO_EXEC_STACK
