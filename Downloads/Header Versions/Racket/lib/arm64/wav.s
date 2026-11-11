// Liberated Peep WAV extension codec (arm64): the PCM and float WAV files the built-in 16-bit
// decoder does not take. Same behaviour as wav.asm (x86-64).
//
//   * unsigned 8-bit, signed 16 / 24 / 32-bit PCM (any valid-bits value up to the container size),
//     32-bit and 64-bit IEEE float; plain or WAVE_FORMAT_EXTENSIBLE; 1 to 8 channels
//   * freestanding: no libc, no allocation, no workspace
//   * read32() gives every sample left-justified in an int32 (value << (32 - container bits)); float is
//     scaled by 2^31, rounded to nearest even and clipped (NaN is 0); read() gives the top 16 bits
//   * p->bits is the file's valid bit depth (float: 32)
//
// Plug it in:  const peep_codec *c[] = { &peep_codec_wavx, &peep_codec_flac, NULL };

.include "abi_a64.inc"

.equ S_BASE, 72                       // u64 address of the first sample frame
.equ S_POS,  80                       // u64 next frame to hand out
.equ S_FSZ,  88                       // u32 bytes per frame
.equ S_FMT,  92                       // u32 1 u8, 2 s16, 3 s24, 4 s32, 5 f32, 6 f64

    .text

// wx_conv: x9 = source (advanced), x10 = destination int32 (advanced), x11 = sample count, w12 = format.
// Clobbers x11, x13-x15, v0, v1.
    .balign 4
wx_conv:
    cbz   x11, .Lwc_ret
    cmp   w12, #2
    b.eq  .Lwc_s16
    b.hi  .Lwc_hi
.Lwc_u8:                              // unsigned: flip the sign bit
    ldrb  w13, [x9], #1
    eor   w13, w13, #0x80
    lsl   w13, w13, #24
    str   w13, [x10], #4
    subs  x11, x11, #1
    b.ne  .Lwc_u8
.Lwc_ret:
    ret
.Lwc_s16:
    ldrh  w13, [x9], #2
    lsl   w13, w13, #16
    str   w13, [x10], #4
    subs  x11, x11, #1
    b.ne  .Lwc_s16
    ret
.Lwc_hi:
    cmp   w12, #4
    b.eq  .Lwc_s32
    b.lo  .Lwc_s24
    movz  x13, #0x41E0, lsl #48       // 2^31 as a double
    fmov  d1, x13
    cmp   w12, #5
    b.eq  .Lwc_f32
.Lwc_f64:
    ldr   d0, [x9], #8
    fmul  d0, d0, d1
    frintn d0, d0                     // nearest even
    fcvtzs w13, d0                    // saturating; NaN gives 0
    str   w13, [x10], #4
    subs  x11, x11, #1
    b.ne  .Lwc_f64
    ret
.Lwc_f32:
    ldr   s0, [x9], #4
    fcvt  d0, s0                      // exact
    fmul  d0, d0, d1
    frintn d0, d0
    fcvtzs w13, d0
    str   w13, [x10], #4
    subs  x11, x11, #1
    b.ne  .Lwc_f32
    ret
.Lwc_s24:
    ldrh  w13, [x9]
    ldrb  w14, [x9, #2]
    add   x9, x9, #3
    orr   w13, w13, w14, lsl #16
    lsl   w13, w13, #8
    str   w13, [x10], #4
    subs  x11, x11, #1
    b.ne  .Lwc_s24
    ret
.Lwc_s32:
    ldr   w13, [x9], #4
    str   w13, [x10], #4
    subs  x11, x11, #1
    b.ne  .Lwc_s32
    ret

// int open(peep *p, const void *data, size_t len)
    .balign 4
wx_open:
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
    str   wzr, [x9, #S_FMT]           // no fmt chunk seen yet
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
    b.ne  .Lwo_notfmt
    cmp   w4, #16
    b.lo  .Lwo_fail
    add   x8, x6, #16
    cmp   x8, x11
    b.hi  .Lwo_fail
    ldrh  w3, [x7]                    // format tag
    ldrh  w13, [x7, #14]              // bits per sample
    cmp   w3, #1
    b.eq  .Lwo_tag
    cmp   w3, #3
    b.eq  .Lwo_tag
    movz  w8, #0xFFFE                 // extensible: valid bits and the sub-format decide
    cmp   w3, w8
    b.ne  .Lwo_fail
    cmp   w4, #40
    b.lo  .Lwo_fail
    add   x8, x6, #40
    cmp   x8, x11
    b.hi  .Lwo_fail
    ldrh  w13, [x7, #18]              // valid bits
    ldrh  w3, [x7, #24]               // sub-format
    cmp   w3, #1
    b.eq  .Lwo_tag
    cmp   w3, #3
    b.ne  .Lwo_fail
.Lwo_tag:
    mov   w14, w3                     // 1 PCM, 3 float
    ldrh  w15, [x7, #2]               // channels
    sub   w3, w15, #1
    cmp   w3, #7
    b.hi  .Lwo_fail
    ldrh  w3, [x7, #12]               // block align
    udiv  w16, w3, w15                // bytes per sample
    msub  w17, w16, w15, w3
    cbnz  w17, .Lwo_fail
    lsl   w17, w16, #3                // container bits
    cbnz  w13, .Lwo_vb
    mov   w13, w17                    // 0 means all of the container
.Lwo_vb:
    cmp   w13, w17
    b.hi  .Lwo_fail
    cmp   w14, #3
    b.eq  .Lwo_isfl
    cmp   w16, #1
    b.lo  .Lwo_fail
    cmp   w16, #4
    b.hi  .Lwo_fail
    mov   w3, w16                     // PCM: format code = bytes per sample
    b     .Lwo_setfmt
.Lwo_isfl:
    mov   w13, #32
    mov   w3, #5
    cmp   w16, #4
    b.eq  .Lwo_setfmt
    mov   w3, #6
    cmp   w16, #8
    b.ne  .Lwo_fail
.Lwo_setfmt:
    str   w3, [x9, #S_FMT]
    mul   w16, w16, w15
    str   w16, [x9, #S_FSZ]
    str   w15, [x9, #P_CH]
    ldr   w3, [x7, #4]
    str   w3, [x9, #P_RATE]
    strh  w13, [x9, #P_BITS]
    b     .Lwo_next
.Lwo_notfmt:
    MOV32 w8, 0x61746164              // 'data'
    cmp   w3, w8
    b.ne  .Lwo_next
    ldr   w3, [x9, #S_FMT]            // data before fmt: not understood
    cbz   w3, .Lwo_fail
    sub   x3, x11, x6                 // bytes actually present
    cmp   x4, x3
    csel  x4, x4, x3, lo              // clamp truncated / unknown-length files
    add   x3, x10, x6
    str   x3, [x9, #S_BASE]
    ldr   w5, [x9, #S_FSZ]
    udiv  x5, x4, x5
    str   x5, [x9, #P_TOTAL]
    str   xzr, [x9, #S_POS]
    mov   w0, #1
    ret
.Lwo_next:
    and   x3, x4, #1                  // odd-sized chunks carry a pad byte
    add   x12, x6, x4
    add   x12, x12, x3
    b     .Lwo_chunk
.Lwo_fail:
    mov   w0, #0
    ret

// Common start of both reads: x19 = p, x21 = frames wanted -> frames available (0 = none left), x9 = source.
wx_take:
    ldr   x0, [x19, #P_TOTAL]
    ldr   x1, [x19, #S_POS]
    subs  x0, x0, x1
    b.ls  .Lwt_none
    cmp   x21, x0
    csel  x21, x21, x0, lo
    cbz   x21, .Lwt_none
    ldr   w2, [x19, #S_FSZ]
    mul   x2, x2, x1
    ldr   x3, [x19, #S_BASE]
    add   x9, x3, x2
    add   x1, x1, x21
    str   x1, [x19, #S_POS]
    ret
.Lwt_none:
    mov   x21, #0
    ret

// size_t read32(peep *p, int32_t *out, size_t frames): native channel count, left-justified
    .balign 4
wx_read32:
    stp   x29, x30, [sp, #-48]!
    mov   x29, sp
    stp   x19, x20, [sp, #16]
    str   x21, [sp, #32]
    mov   x19, x0
    mov   x20, x1
    mov   x21, x2
    bl    wx_take
    cbz   x21, .Lr32_d
    ldr   w11, [x19, #P_CH]
    mul   x11, x11, x21
    mov   x10, x20
    ldr   w12, [x19, #S_FMT]
    bl    wx_conv
.Lr32_d:
    mov   x0, x21
    ldr   x21, [sp, #32]
    ldp   x19, x20, [sp, #16]
    ldp   x29, x30, [sp], #48
    ret

// size_t read(peep *p, int16_t *out, size_t frames): the top 16 bits of each sample
    .balign 4
wx_read:
    stp   x29, x30, [sp, #-64]!
    mov   x29, sp
    stp   x19, x20, [sp, #16]
    stp   x21, x22, [sp, #32]
    str   x23, [sp, #48]
    sub   sp, sp, #1024
    mov   x19, x0
    mov   x20, x1
    mov   x21, x2
    bl    wx_take
    cbz   x21, .Lrd_d
    ldr   w22, [x19, #P_CH]
    mul   x22, x22, x21               // samples left
.Lrd_c:
    cbz   x22, .Lrd_d
    mov   x23, #256
    cmp   x22, x23
    csel  x23, x22, x23, lo
    sub   x22, x22, x23
    mov   x11, x23
    mov   x10, sp
    ldr   w12, [x19, #S_FMT]
    bl    wx_conv
    mov   x13, sp
    mov   x14, x23
.Lrd_n:
    ldr   w15, [x13], #4
    asr   w15, w15, #16
    strh  w15, [x20], #2
    subs  x14, x14, #1
    b.ne  .Lrd_n
    b     .Lrd_c
.Lrd_d:
    mov   x0, x21
    add   sp, sp, #1024
    ldr   x23, [sp, #48]
    ldp   x21, x22, [sp, #32]
    ldp   x19, x20, [sp, #16]
    ldp   x29, x30, [sp], #64
    ret

// void seek(peep *p, uint64_t frame)
    .balign 4
wx_seek:
    ldr   x2, [x0, #P_TOTAL]
    cmp   x1, x2
    csel  x1, x1, x2, lo
    str   x1, [x0, #S_POS]
    ret

// const peep_codec *peep_wavx(void): the codec table's address, for languages whose FFI cannot read data symbols
FUNC peep_wavx
.ifdef APPLE
    adrp  x0, _peep_codec_wavx@PAGE
    add   x0, x0, _peep_codec_wavx@PAGEOFF
.else
    adrp  x0, :got:peep_codec_wavx
    ldr   x0, [x0, :got_lo12:peep_codec_wavx]
.endif
    ret

// ============================================================================
    DATA_RO
.ifdef APPLE
    .globl _peep_codec_wavx
_peep_codec_wavx:
.else
    .globl peep_codec_wavx
    .type peep_codec_wavx, %object
peep_codec_wavx:
.endif
    .quad wx_open, wx_read, wx_seek, 0, wx_read32

NO_EXEC_STACK
