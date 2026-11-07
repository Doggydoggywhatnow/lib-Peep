// Liberated Peep FLAC codec (arm64): native AArch64 assembly FLAC decoder behind the
// peep_codec interface. Same behaviour as flac.asm (x86-64).
//
//   * freestanding: no libc, no malloc, no syscalls, no writable globals
//   * workspace lent by the host: channels * max_blocksize * 4 + 16 bytes
//     (16 of them in front of the first plane)
//   * ID3v2 tags in front of the stream are skipped; damaged frames are counted in p->errors;
//     read32() gives the samples at full resolution; peep_flac_metadata() hands out metadata blocks
//   * 4..31 bits per sample, 1..8 channels, fixed and variable block sizes, all subframe
//     types, every Rice mode, all stereo modes, seeking by binary search over frame headers,
//     resynchronisation over damaged frames
//   * every frame's CRC-16 is verified; a frame that fails it is output as silence of the right
//     length (so timing and seek positions stay correct) instead of as wrong samples
//
// Register convention inside this file (private; the exported entry points set it up):
//   x19 = peep *           x20 = read pointer into the file
//   x21 = bit cache (MSB first, left aligned)     w22 = valid bits in the cache
//   x23 = end of file      x24 = residual write pointer      x28 = locals (512 bytes)
// br_get/br_gets/br_refill clobber only x0-x3. Routines that call others save x30 themselves.

.include "abi_a64.inc"

// FLAC state inside peep.state[] (offsets from the start of struct peep)
.equ S_NEXT,   72                     // u64 offset of the next frame
.equ S_START,  80                     // u64 offset of the first frame
.equ S_BLKLEN, 88                     // u32 samples in the decoded block
.equ S_BLKPOS, 92                     // u32 next sample to hand out
.equ S_MAXBLK, 96                     // u32 STREAMINFO max block size = plane stride
.equ S_BLK0,   100                    // u32 STREAMINFO min block size (fixed-size streams)
.equ S_BPS,    104                    // u32 bits per sample of the decoded block
.equ S_SIBPS,  108                    // u32 STREAMINFO bits per sample
.equ S_SPOS,   112                    // u64 first sample number of the decoded block
.equ S_PLANE0, 120                    // u64 address of plane 0 (work + 16)

// locals, addressed from x28
.equ L_COEF,   0                      // 32 x int32, oldest sample first (128 bytes)
.equ L_BS,     256
.equ L_CA,     260
.equ L_BPS,    264
.equ L_ORDER,  268
.equ L_SHIFT,  272
.equ L_WASTED, 276
.equ L_WIDTH,  280
.equ L_PRECIS, 284
.equ L_NUM,    288
.equ L_HSTART, 296
.equ L_START,  304
.equ L_PLANE,  312
.equ L_OUT,    320
.equ L_FRAMES, 328
.equ L_GOT,    336
.equ L_CH,     344
.equ L_CHIDX,  348
.equ L_VARBS,  352
.equ L_PSIZE,  356
.equ L_PBITS,  360
.equ L_NPART,  364
.equ L_SPOS,   376
.equ L_SLIM,   384
.equ L_LO,     392
.equ L_HI,     400
.equ L_TGT,    408
.equ L_MID,    416
.equ L_FIX,    424                    // order of a fixed predictor, 0 for LPC
.equ L_CRC,    432                    // the CRC-16 stored in the frame
.equ L_WIDE,   440                    // 0: read() int16, 1: read32() int32
.equ L_ESCP,   448                    // escape partition: where it starts
.equ L_ESCN,   456                    // and how many samples it holds
.equ L_PB,     464                    // LPC: bytes in the (padded) window, 4 * P
.equ L_PM4,    472                    // LPC: P - 4, the taps the loop handles before the newest four
.equ L_MODE,   480                    // residual loop flavour: 0 none, 1 fixed predictor, 2 LPC
.equ P_CTX,    64                     // where the metadata blocks start (for peep_flac_metadata)

    .text

    .balign 4
fixtab: .word 1, -1, 2, 1, -3, 3, -1, 4, -6, 4      // fixed predictors 1..4, oldest first

// ============================================================================
// Bit reader
// ============================================================================

// Top up the cache by 32 bits (only with w22 < 32). Past the end of the file it supplies
// zero bits; callers detect that with CHECK_OVERRUN. Clobbers x0-x2.
.macro REFILL
    add   x1, x20, #4
    cmp   x1, x23
    b.hi  8f
    ldr   w0, [x20]
    rev   w0, w0
    b     7f
8:  mov   w0, #0                      // fewer than 4 bytes left: zero fill
    mov   x2, x20
    .rept 4
    lsl   w0, w0, #8
    cmp   x2, x23
    b.hs  1f
    ldrb  w1, [x2]
    orr   w0, w0, w1
1:  add   x2, x2, #1
    .endr
7:  mov   w1, #32
    sub   w1, w1, w22
    lsl   x0, x0, x1
    orr   x21, x21, x0
    add   w22, w22, #32
    add   x20, x20, #4
.endm

// w0 = n (0..32) -> x0 = next n bits (sign extended when \sgn). Clobbers x0-x3.
.macro GETBITS sgn
    mov   w3, w0
    cbz   w3, 4f
    cmp   w22, w3
    b.hs  3f
    REFILL
3:  mov   w1, #64
    sub   w1, w1, w3
    lsr   x0, x21, x1
    lsl   x21, x21, x3
    sub   w22, w22, w3
.if \sgn
    lsl   x0, x0, x1
    asr   x0, x0, x1
.endif
    ret
4:  mov   x0, #0
    ret
.endm

FUNCL br_refill
    REFILL
    ret

FUNCL br_get
    GETBITS 0

FUNCL br_gets
    GETBITS 1

// x4 = byte offset: point the reader there
FUNCL br_init
    ldr   x20, [x19, #P_SRC]
    ldr   x23, [x19, #P_LEN]
    add   x23, x20, x23
    add   x20, x20, x4
    mov   x21, #0
    mov   x22, #0
    ret

// branch to \target if more bits were consumed than the file holds
.macro CHECK_OVERRUN target
    cmp   x20, x23
    b.ls  2f
    sub   x0, x20, x23
    lsl   x0, x0, #3
    cmp   x0, x22
    b.hi  \target
2:
.endm

// ---- CRC-16 (FLAC: polynomial 0x8005, start 0, MSB first, no reflection) -----------------------
// Table k holds, for every byte value, the CRC of that byte followed by k zero bytes. The
// assembler builds the eight tables itself (no generator script): 8 x 512 bytes.
.macro CRC16TAB k
    .set i, 0
    .rept 256
        .set c, i << 8
        .rept 8 * (\k + 1)
            .if c & 0x8000
                .set c, ((c << 1) ^ 0x8005) & 0xFFFF
            .else
                .set c, (c << 1) & 0xFFFF
            .endif
        .endr
        .hword c
        .set i, i + 1
    .endr
.endm

    .balign 16
crc16_tab:
    .set k, 0
    .rept 8
        CRC16TAB k
        .set k, k + 1
    .endr

// crc16: x1 = bytes, x2 = count -> w0. 8 bytes per step (slicing-by-8): the CRC only mixes into
// the first two bytes, so the other six table lookups do not wait for it. Clobbers x1-x15.
FUNCL crc16
    mov   w0, #0
    adr   x8, crc16_tab
    cmp   x2, #8
    b.lo  .Lc16_t
    add   x9, x8, #512                // tables for 1 .. 7 zero bytes after the byte
    add   x10, x8, #1024
    add   x11, x8, #1536
    add   x12, x8, #2048
    add   x13, x8, #2560
    add   x14, x8, #3072
    add   x15, x8, #3584
.Lc16_l8:
    ldr   x3, [x1], #8                // b0 is the low byte
    lsr   w4, w0, #8
    eor   w4, w4, w3
    and   w4, w4, #0xFF               // (crc >> 8) ^ b0
    and   w5, w0, #0xFF
    ubfx  x6, x3, #8, #8
    eor   w5, w5, w6                  // (crc & 255) ^ b1
    ldrh  w0, [x15, x4, lsl #1]
    ldrh  w7, [x14, x5, lsl #1]
    eor   w0, w0, w7
    ubfx  x6, x3, #16, #8
    ldrh  w7, [x13, x6, lsl #1]
    eor   w0, w0, w7
    ubfx  x6, x3, #24, #8
    ldrh  w7, [x12, x6, lsl #1]
    eor   w0, w0, w7
    ubfx  x6, x3, #32, #8
    ldrh  w7, [x11, x6, lsl #1]
    eor   w0, w0, w7
    ubfx  x6, x3, #40, #8
    ldrh  w7, [x10, x6, lsl #1]
    eor   w0, w0, w7
    ubfx  x6, x3, #48, #8
    ldrh  w7, [x9, x6, lsl #1]
    eor   w0, w0, w7
    lsr   x6, x3, #56
    ldrh  w7, [x8, x6, lsl #1]
    eor   w0, w0, w7
    sub   x2, x2, #8
    cmp   x2, #8
    b.hs  .Lc16_l8
.Lc16_t:
    cbz   x2, .Lc16_d
.Lc16_t1:
    ldrb  w3, [x1], #1
    lsr   w4, w0, #8
    eor   w4, w4, w3
    and   w4, w4, #0xFF
    lsl   w0, w0, #8
    and   w0, w0, #0xFFFF
    ldrh  w5, [x8, x4, lsl #1]
    eor   w0, w0, w5
    subs  x2, x2, #1
    b.ne  .Lc16_t1
.Lc16_d:
    ret

// ============================================================================
// Frame header: leaves block size, channel assignment, bits per sample and the first sample
// number in locals. w0 = 1 ok, 0 not a valid header. Clobbers x0-x13.
// ============================================================================
FUNCL parse_header
    str   x30, [sp, #-16]!
    ldr   x0, [x19, #P_SRC]
    sub   x1, x20, x0
    lsl   x1, x1, #3
    sub   x1, x1, x22
    lsr   x1, x1, #3
    str   x1, [x28, #L_HSTART]
    mov   w0, #14
    bl    br_get
    mov   w1, #0x3FFE
    cmp   w0, w1
    b.ne  .Lph_bad
    mov   w0, #1
    bl    br_get                      // reserved
    cbnz  w0, .Lph_bad
    mov   w0, #1
    bl    br_get                      // blocking strategy: 0 fixed, 1 variable
    str   w0, [x28, #L_VARBS]
    mov   w0, #4
    bl    br_get
    mov   w4, w0                      // block size code
    mov   w0, #4
    bl    br_get
    mov   w5, w0                      // sample rate code
    mov   w0, #4
    bl    br_get
    mov   w6, w0                      // channel assignment
    cmp   w6, #10
    b.hi  .Lph_bad
    str   w6, [x28, #L_CA]
    mov   w0, #3
    bl    br_get
    mov   w7, w0                      // sample size code
    mov   w0, #1
    bl    br_get
    cbnz  w0, .Lph_bad
    ldr   w8, [x19, #S_SIBPS]
    cbz   w7, .Lph_bpsok
    mov   w8, #8
    cmp   w7, #1
    b.eq  .Lph_bpsok
    mov   w8, #12
    cmp   w7, #2
    b.eq  .Lph_bpsok
    mov   w8, #16
    cmp   w7, #4
    b.eq  .Lph_bpsok
    mov   w8, #20
    cmp   w7, #5
    b.eq  .Lph_bpsok
    mov   w8, #24
    cmp   w7, #6
    b.ne  .Lph_bad
.Lph_bpsok:
    str   w8, [x28, #L_BPS]
    // ---- UTF-8 coded frame / sample number ---------------------------------
    mov   w0, #8
    bl    br_get
    mov   x9, x0
    mov   w10, w0
    cmp   w0, #0x80
    b.lo  .Lph_num
    cmp   w0, #0xC0
    b.lo  .Lph_bad
    cmp   w0, #0xFF
    b.eq  .Lph_bad
    mvn   w11, w10
    and   w11, w11, #0xFF
    clz   w11, w11
    sub   w11, w11, #24               // leading ones in the first byte
    sub   w11, w11, #1                // continuation bytes
    mov   w12, #6
    sub   w12, w12, w11
    mov   w13, #1
    lsl   w13, w13, w12
    sub   w13, w13, #1
    and   w9, w10, w13                // payload bits of the first byte
.Lph_ub:
    mov   w0, #8
    bl    br_get
    and   w1, w0, #0xC0
    cmp   w1, #0x80
    b.ne  .Lph_bad
    and   w0, w0, #0x3F
    lsl   x9, x9, #6
    orr   x9, x9, x0
    subs  w11, w11, #1
    b.ne  .Lph_ub
.Lph_num:
    str   x9, [x28, #L_NUM]
    // ---- block size -------------------------------------------------------------
    cbz   w4, .Lph_bad
    cmp   w4, #1
    b.ne  .Lph_b2
    mov   w0, #192
    b     .Lph_bs
.Lph_b2:
    cmp   w4, #5
    b.hi  .Lph_b6
    sub   w1, w4, #2
    mov   w0, #576
    lsl   w0, w0, w1
    b     .Lph_bs
.Lph_b6:
    cmp   w4, #6
    b.ne  .Lph_b7
    mov   w0, #8
    bl    br_get
    add   w0, w0, #1
    b     .Lph_bs
.Lph_b7:
    cmp   w4, #7
    b.ne  .Lph_b8
    mov   w0, #16
    bl    br_get
    add   w0, w0, #1
    b     .Lph_bs
.Lph_b8:
    sub   w1, w4, #8
    mov   w0, #256
    lsl   w0, w0, w1
.Lph_bs:
    ldr   w1, [x19, #S_MAXBLK]
    cmp   w0, w1
    b.hi  .Lph_bad
    str   w0, [x28, #L_BS]
    // ---- explicit sample rate (skipped) -------------------------------------
    cmp   w5, #15
    b.eq  .Lph_bad
    cmp   w5, #12
    b.lo  .Lph_rd
    mov   w0, #8
    b.eq  .Lph_rg
    mov   w0, #16
.Lph_rg:
    bl    br_get
.Lph_rd:
    // ---- header CRC-8 -------------------------------------------------------------
    ldr   x1, [x19, #P_SRC]
    sub   x0, x20, x1
    lsl   x0, x0, #3
    sub   x0, x0, x22
    lsr   x0, x0, #3                  // offset of the CRC byte
    ldr   x2, [x19, #P_LEN]
    cmp   x0, x2
    b.hs  .Lph_bad
    ldr   x3, [x28, #L_HSTART]
    sub   x2, x0, x3                  // bytes to check
    add   x1, x1, x3
    mov   w10, #0
.Lph_crc:
    cbz   x2, .Lph_crcd
    ldrb  w0, [x1], #1
    eor   w10, w10, w0
    mov   w3, #8
.Lph_crcb:
    tst   w10, #0x80
    lsl   w10, w10, #1
    eor   w0, w10, #7
    csel  w10, w0, w10, ne
    and   w10, w10, #0xFF
    subs  w3, w3, #1
    b.ne  .Lph_crcb
    sub   x2, x2, #1
    b     .Lph_crc
.Lph_crcd:
    mov   w0, #8
    bl    br_get
    cmp   w0, w10
    b.ne  .Lph_bad
    // ---- channels must match STREAMINFO --------------------------------------
    ldr   w0, [x28, #L_CA]
    cmp   w0, #8
    b.lo  .Lph_ind
    mov   w0, #1
.Lph_ind:
    add   w0, w0, #1
    ldr   w1, [x19, #P_CH]
    cmp   w0, w1
    b.ne  .Lph_bad
    // ---- first sample of this frame ---------------------------------------------
    ldr   x0, [x28, #L_NUM]
    ldr   w1, [x28, #L_VARBS]
    cbnz  w1, .Lph_var
    ldr   w1, [x19, #S_BLK0]
    mul   x0, x0, x1
.Lph_var:
    str   x0, [x28, #L_START]
    mov   w0, #1
    ldr   x30, [sp], #16
    ret
.Lph_bad:
    mov   w0, #0
    ldr   x30, [sp], #16
    ret

// ff_scan: find the next valid frame header. x4 = first offset to try, x5 = headers must
// start below this. -> w0 = 1 and x4 = offset, or w0 = 0.
FUNCL ff_scan
    str   x30, [sp, #-16]!
    ldr   x0, [x19, #P_LEN]
    cmp   x5, x0
    csel  x5, x5, x0, lo
    str   x5, [x28, #L_SLIM]
    str   x4, [x28, #L_SPOS]
    ldr   x6, [x19, #P_SRC]
.Lfs_f:
    ldr   x1, [x28, #L_SLIM]
    cmp   x4, x1
    b.hs  .Lfs_fail
    ldr   x0, [x19, #P_LEN]
    add   x2, x4, #1
    cmp   x2, x0
    b.hs  .Lfs_fail
    ldrb  w0, [x6, x4]
    cmp   w0, #0xFF
    b.ne  .Lfs_adv
    add   x1, x6, x4
    ldrb  w0, [x1, #1]
    and   w0, w0, #0xFE
    cmp   w0, #0xF8
    b.eq  .Lfs_cand
.Lfs_adv:
    add   x4, x4, #1
    b     .Lfs_f
.Lfs_cand:
    str   x4, [x28, #L_SPOS]
    bl    br_init
    bl    parse_header
    ldr   x4, [x28, #L_SPOS]
    cbnz  w0, .Lfs_ok
    add   x4, x4, #1
    str   x4, [x28, #L_SPOS]
    ldr   x6, [x19, #P_SRC]
    b     .Lfs_f
.Lfs_ok:
    mov   w0, #1
    ldr   x30, [sp], #16
    ret
.Lfs_fail:
    mov   w0, #0
    ldr   x30, [sp], #16
    ret

// ============================================================================
// Residual: Rice-coded, writes plane[order .. blocksize). The hot loop.
// ============================================================================
// RICE entry, mode: the Rice residual loop for one partition, with the prediction done in the same loop as each sample is decoded (the predictor's
// dependency chain then runs alongside the bit reader's instead of in a second pass). One copy per mode so the loop has no mode tests.
// mode 0: none (order 0)   1: fixed predictor, orders 1 to 4   2: LPC (NEON for the older taps)
// In: w9 = samples left in the partition, w10 = Rice parameter k, x24 = output, w15 = previous sample, x20 to x23 = bit reader.
.macro RICE entry, mode
\entry:
.Lrs_\@:
    cmp   w22, #32
    b.lo  .Lrf1_\@
.Lc1_\@:
    cbz   x21, .Llong_\@
    clz   x4, x21                     // q: leading zero bits
    add   w5, w4, w10
    add   w5, w5, #1                  // t = q + 1 + k bits for this sample
    cmp   w5, w22
    b.hi  .Lmore_\@                      // not all in the cache: slow path
    mov   w6, #64
    sub   w6, w6, w5
    lsr   x7, x21, x6                 // V = top t bits = (1 << k) | low
    sub   x8, x4, #1
    lsl   x8, x8, x10                 // (q - 1) << k
    add   x7, x7, x8                  // u = V + ((q - 1) << k) = q << k | low
    lsl   x21, x21, x5                // the only loop-carried work: drop t bits
    sub   w22, w22, w5
.Lzz_\@:
    and   x8, x7, #1
    neg   x8, x8
    eor   x7, x8, x7, lsr #1          // zig-zag: (u >> 1) ^ -(u & 1)
.if \mode == 0
    str   w7, [x24], #4
    subs  w9, w9, #1
    b.ne  .Lrs_\@
    b     .Lres_pdone
.elseif \mode == 1
    ldr   w8, [x28, #L_FIX]
    cmp   w8, #2
    b.lo  .Lp1_\@
    b.eq  .Lp2_\@
    cmp   w8, #3
    b.eq  .Lp3_\@
.Lp4_\@:                                 // order 4: 4(c1 + c3) - 6c2 - c4 (older samples are read back from the plane)
    ldur  w4, [x24, #-12]
    add   w4, w4, w15
    lsl   w4, w4, #2
    ldur  w5, [x24, #-8]
    add   w5, w5, w5, lsl #1
    lsl   w5, w5, #1
    sub   w4, w4, w5
    ldur  w5, [x24, #-16]
    sub   w4, w4, w5
    add   w7, w7, w4
    b     .Lst_\@
.Lp3_\@:                                 // order 3: 3(c1 - c2) + c3
    ldur  w4, [x24, #-8]
    sub   w4, w15, w4
    add   w4, w4, w4, lsl #1
    ldur  w5, [x24, #-12]
    add   w4, w4, w5
    add   w7, w7, w4
    b     .Lst_\@
.Lp2_\@:                                 // order 2: 2c1 - c2
    ldur  w4, [x24, #-8]
    lsl   w5, w15, #1
    sub   w4, w5, w4
    add   w7, w7, w4
    b     .Lst_\@
.Lp1_\@:
    add   w7, w7, w15                 // order 1: c1
.Lst_\@:
    mov   w15, w7
    str   w7, [x24], #4
    subs  w9, w9, #1
    b.ne  .Lrs_\@
    b     .Lres_pdone
.else
    ldr   w12, [x28, #L_PB]
    sub   x11, x24, x12               // window start x[i - P]
    add   x2, x28, #L_COEF
    mov   x1, x11
    ldr   w13, [x28, #L_PM4]
    cbz   w13, .Llnov_\@
    movi  v2.2d, #0
.Llmac_\@:                            // NEON: 4 taps per pass as two 2-lane signed 32x32 -> 64 multiply-accumulates
    ld1   {v0.4s}, [x1], #16          // at least 4 samples old, so long since stored (no store-forwarding stall)
    ld1   {v1.4s}, [x2], #16
    smlal v2.2d, v0.2s, v1.2s
    smlal2 v2.2d, v0.4s, v1.4s
    subs  w13, w13, #4
    b.ne  .Llmac_\@
    addp  d2, v2.2d
    fmov  x14, d2
    b     .Lltail_\@
.Llnov_\@:
    mov   x14, #0
.Lltail_\@:                           // the newest four taps: x[i-4..i-2] from memory, x[i-1] from the register
    ldp   w0, w3, [x1]
    ldp   w16, w17, [x2]
    smaddl x14, w0, w16, x14
    smaddl x14, w3, w17, x14
    ldr   w0, [x1, #8]
    ldr   w16, [x2, #8]
    smaddl x14, w0, w16, x14
    ldr   w16, [x2, #12]
    smaddl x14, w15, w16, x14
    ldr   w0, [x28, #L_SHIFT]
    asr   x14, x14, x0
    add   w7, w7, w14                 // residual + prediction, int32 wrap
    mov   w15, w7
    str   w7, [x24], #4
    subs  w9, w9, #1
    b.ne  .Lrs_\@
    b     .Lres_pdone
.endif
.Lrf1_\@:
    bl    br_refill
    b     .Lc1_\@
.Lmore_\@:                               // x4 = q: consume the unary part, then top up for the rest
    lsl   x21, x21, x4
    lsl   x21, x21, #1
    add   w6, w4, #1
    sub   w22, w22, w6
.Lkstage_\@:
    cmp   w22, w10
    b.hs  .Lc2_\@
    bl    br_refill
.Lc2_\@:
    mov   w6, #63
    sub   w6, w6, w10
    lsr   x7, x21, #1
    lsr   x7, x7, x6                  // k low bits
    lsl   x21, x21, x10
    sub   w22, w22, w10
    lsl   x8, x4, x10
    orr   x7, x7, x8                  // u = q << k | low
    b     .Lzz_\@
.Llong_\@:                               // the cache holds only zeros: keep counting
    mov   x4, x22
    mov   x21, #0
    mov   x22, #0
.Llg_\@:
    add   x0, x23, #16
    cmp   x20, x0
    b.hi  .Lres_bad                   // ran far past the end of the file
    bl    br_refill
    cbnz  x21, .Llgf_\@
    add   x4, x4, x22
    mov   x21, #0
    mov   x22, #0
    b     .Llg_\@
.Llgf_\@:
    clz   x5, x21
    add   x4, x4, x5
    lsl   x21, x21, x5
    lsl   x21, x21, #1
    add   w5, w5, #1
    sub   w22, w22, w5
    b     .Lkstage_\@
.endm

FUNCL decode_residual
    str   x30, [sp, #-16]!
    mov   w0, #2
    bl    br_get
    cmp   w0, #1
    b.hi  .Lres_bad
    add   w0, w0, #4
    str   w0, [x28, #L_PBITS]         // 4 or 5 bit Rice parameters
    mov   w0, #4
    bl    br_get
    mov   w12, w0                     // partition order
    mov   w13, #1
    lsl   w13, w13, w12
    str   w13, [x28, #L_NPART]
    ldr   w14, [x28, #L_BS]
    sub   w1, w13, #1
    tst   w1, w14                     // block size must divide into the partitions
    b.ne  .Lres_bad
    lsr   w1, w14, w12
    str   w1, [x28, #L_PSIZE]
    ldr   w2, [x28, #L_ORDER]
    subs  w9, w1, w2                  // the first partition holds order fewer samples
    b.lo  .Lres_bad
    ldr   x24, [x28, #L_PLANE]
    add   x24, x24, x2, lsl #2
    ldr   w0, [x28, #L_FIX]           // which loop: 1 fixed predictor, 2 LPC, 0 none (order 0)
    cbnz  w0, .Lmfix
    cbz   w2, .Lmset
    mov   w0, #2
    b     .Lmset
.Lmfix:
    mov   w0, #1
.Lmset:
    str   w0, [x28, #L_MODE]
.Lres_part:
    ldur  w15, [x24, #-4]             // previous sample (fixed predictors); front slack makes order 0 safe too
    ldr   w0, [x28, #L_PBITS]
    bl    br_get
    mov   w10, w0                     // Rice parameter k, or the escape code
    ldr   w1, [x28, #L_PBITS]
    mov   w2, #1
    lsl   w2, w2, w1
    sub   w2, w2, #1
    cmp   w10, w2
    b.eq  .Lres_esc
    cbz   w9, .Lres_pdone
    ldr   w0, [x28, #L_MODE]
    cbz   w0, .Lrs0
    cmp   w0, #1
    b.eq  .Lrs1
    b     .Lrs2
    RICE  .Lrs0, 0
    RICE  .Lrs1, 1
    RICE  .Lrs2, 2
.Lres_esc:                            // partition stored as n-bit signed integers
    mov   w0, #5
    bl    br_get
    mov   w11, w0
    cbz   w9, .Lres_pdone
    str   x24, [x28, #L_ESCP]         // remember the region: a fixed predictor still has to be run over it
    str   w9, [x28, #L_ESCN]
    cbnz  w11, .Lres_eraw
.Lres_ez:
    str   wzr, [x24], #4
    subs  w9, w9, #1
    b.ne  .Lres_ez
    b     .Lres_edone
.Lres_eraw:
    mov   w0, w11
    bl    br_gets
    str   w0, [x24], #4
    subs  w9, w9, #1
    b.ne  .Lres_eraw
.Lres_edone:
    ldr   w0, [x28, #L_FIX]
    cbnz  w0, .Lres_efix
    ldr   w1, [x28, #L_ORDER]
    cbz   w1, .Lres_pdone
    ldr   x10, [x28, #L_ESCP]         // LPC: predict only this region (its history is in the plane before it)
    ldr   w5, [x28, #L_ESCN]
    bl    lpc_run
    b     .Lres_erest
.Lres_efix:
    ldr   x10, [x28, #L_ESCP]         // fixed predictor: the same for the region
    ldr   w5, [x28, #L_ESCN]
    bl    .Lpr_fixed_at
.Lres_erest:
    ldr   x24, [x28, #L_ESCP]
    ldr   w0, [x28, #L_ESCN]
    add   x24, x24, x0, lsl #2
.Lres_pdone:
    ldr   w9, [x28, #L_PSIZE]
    ldr   w0, [x28, #L_NPART]
    subs  w0, w0, #1
    str   w0, [x28, #L_NPART]
    b.ne  .Lres_part
    mov   w0, #1
    ldr   x30, [sp], #16
    ret
.Lres_bad:
    mov   w0, #0
    ldr   x30, [sp], #16
    ret

// ============================================================================
// LPC / fixed prediction, in place. 64-bit accumulator (smaddl), so any precision and any
// sample width is exact. The newest sample stays in a register, so the serial chain
// never goes through memory. Clobbers x0-x17.
// ============================================================================
// lpc_prep: once per LPC subframe, before decode_residual: pad the coefficients to a multiple of 4 taps (zeros on the old side) and record the window size.
FUNCL lpc_prep
    ldr   w4, [x28, #L_ORDER]
    add   x6, x28, #L_COEF
    add   w7, w4, #3
    and   w7, w7, #0xFFFFFFFC         // P = order rounded up to a multiple of 4
    sub   w8, w7, w4                  // d zero coefficients go on the OLD side
    cbz   w8, .Lpr_padded
    mov   w9, w4
.Lpr_mv:
    sub   w9, w9, #1
    ldr   w10, [x6, x9, lsl #2]
    add   w11, w9, w8
    str   w10, [x6, x11, lsl #2]
    cbnz  w9, .Lpr_mv
    mov   w9, #0
.Lpr_zp:
    str   wzr, [x6, x9, lsl #2]
    add   w9, w9, #1
    cmp   w9, w8
    b.lo  .Lpr_zp
.Lpr_padded:
    lsl   w0, w7, #2
    str   w0, [x28, #L_PB]
    sub   w0, w7, #4
    str   w0, [x28, #L_PM4]
    ret

// lpc_run: LPC prediction over a region, in place: x10 = &x[start], w5 = count (>= 1). The whole-subframe case is done inside decode_residual;
// this is for escape-coded partitions. 64-bit accumulator (smaddl), so any precision and any sample width is exact.
FUNCL lpc_run
    add   x6, x28, #L_COEF
    ldr   w0, [x28, #L_PB]
    sub   x11, x10, x0                // window start x[start - P] (up to 3 slots of front slack)
    ldrsw x12, [x10, #-4]             // x[i-1] lives in a register
    ldr   w13, [x28, #L_PM4]          // the last 4 window slots are handled outside the loop
    ldr   w14, [x28, #L_SHIFT]
.Lpr_s:
    mov   x1, x11
    mov   x2, x6
    mov   w9, w13
    cbz   w9, .Lpr_nov                // order <= 4: nothing for the vector loop to do
    movi  v2.2d, #0
.Lpr_mac:                             // NEON: 4 taps per pass as two 2-lane signed 32x32 -> 64 multiply-accumulates
    ld1   {v0.4s}, [x1], #16          // x[j .. j+3]: all at least 4 samples old, so long since stored (no store-forwarding stall)
    ld1   {v1.4s}, [x2], #16          // the four coefficients (int32, oldest first)
    smlal v2.2d, v0.2s, v1.2s
    smlal2 v2.2d, v0.4s, v1.4s
    subs  w9, w9, #4
    b.ne  .Lpr_mac
    addp  d2, v2.2d
    fmov  x15, d2                     // the sum of the older taps, exact in 64 bits like the scalar code
    b     .Lpr_tail
.Lpr_nov:
    mov   x15, #0
.Lpr_tail:                            // x[i-4..i-2] from memory, the newest term from the register
    ldp   w0, w3, [x1]
    ldp   w16, w17, [x2]
    smaddl x15, w0, w16, x15
    smaddl x15, w3, w17, x15
    ldr   w0, [x1, #8]
    ldr   w16, [x2, #8]
    smaddl x15, w0, w16, x15
    ldr   w16, [x2, #12]
    smaddl x15, w12, w16, x15
    asr   x15, x15, x14
    ldr   w0, [x10]
    add   w0, w0, w15                 // residual + prediction, int32 wrap
    str   w0, [x10], #4
    sxtw  x12, w0
    add   x11, x11, #4
    subs  w5, w5, #1
    b.ne  .Lpr_s
.Lpr_done:
    ret
.Lpr_fixed_at:                        // fixed predictors over a region: x10 = &x[start], w5 = count, w0 = order
    cmp   w0, #2
    b.lo  .Lpf1
    b.eq  .Lpf2
    cmp   w0, #3
    b.eq  .Lpf3
    ldp   w1, w2, [x10, #-16]         // order 4: 4c1 - 6c2 + 4c3 - c4
    ldp   w3, w4, [x10, #-8]
.Lpl4:
    add   w6, w4, w2
    lsl   w6, w6, #2
    add   w7, w3, w3, lsl #1
    lsl   w7, w7, #1
    sub   w6, w6, w7
    sub   w6, w6, w1
    ldr   w7, [x10]
    add   w6, w6, w7
    str   w6, [x10], #4
    mov   w1, w2
    mov   w2, w3
    mov   w3, w4
    mov   w4, w6
    subs  w5, w5, #1
    b.ne  .Lpl4
    ret
.Lpf3:
    ldp   w1, w2, [x10, #-12]         // order 3: 3(c1 - c2) + c3
    ldr   w3, [x10, #-4]
.Lpl3:
    sub   w4, w3, w2
    add   w4, w4, w4, lsl #1
    add   w4, w4, w1
    ldr   w6, [x10]
    add   w4, w4, w6
    str   w4, [x10], #4
    mov   w1, w2
    mov   w2, w3
    mov   w3, w4
    subs  w5, w5, #1
    b.ne  .Lpl3
    ret
.Lpf2:
    ldp   w1, w2, [x10, #-8]          // order 2: 2c1 - c2
.Lpl2:
    lsl   w3, w2, #1
    sub   w3, w3, w1
    ldr   w4, [x10]
    add   w3, w3, w4
    str   w3, [x10], #4
    mov   w1, w2
    mov   w2, w3
    subs  w5, w5, #1
    b.ne  .Lpl2
    ret
.Lpf1:
    ldr   w1, [x10, #-4]              // order 1: c1
.Lpl1:
    ldr   w2, [x10]
    add   w1, w1, w2
    str   w1, [x10], #4
    subs  w5, w5, #1
    b.ne  .Lpl1
    ret

// ============================================================================
// One subframe into plane L_PLANE, width L_WIDTH bits. w0 = 1 ok, 0 error.
// ============================================================================
FUNCL decode_subframe
    str   x30, [sp, #-16]!
    mov   w0, #1
    bl    br_get
    cbnz  w0, .Lsf_bad
    mov   w0, #6
    bl    br_get
    mov   w9, w0                      // subframe type
    mov   w0, #1
    bl    br_get
    mov   w12, w0
    mov   w10, #0                     // wasted bits
    cbz   w12, .Lsf_nw
.Lsf_wl:
    mov   w0, #1
    bl    br_get
    add   w10, w10, #1
    cmp   w10, #32
    b.hi  .Lsf_bad
    cbz   w0, .Lsf_wl
.Lsf_nw:
    str   w10, [x28, #L_WASTED]
    ldr   w0, [x28, #L_WIDTH]
    subs  w0, w0, w10
    b.ls  .Lsf_bad
    str   w0, [x28, #L_WIDTH]
    ldr   w11, [x28, #L_BS]
    cbz   w9, .Lsf_const
    cmp   w9, #1
    b.eq  .Lsf_verb
    cmp   w9, #8
    b.lo  .Lsf_bad
    cmp   w9, #12
    b.ls  .Lsf_fixed
    cmp   w9, #32
    b.lo  .Lsf_bad
    sub   w0, w9, #31                 // LPC order 1..32
    str   w0, [x28, #L_ORDER]
    str   wzr, [x28, #L_FIX]
    b     .Lsf_warm
.Lsf_const:
    ldr   w0, [x28, #L_WIDTH]
    bl    br_gets
    ldr   x1, [x28, #L_PLANE]
    mov   w2, w11
.Lsf_cl:
    str   w0, [x1], #4
    subs  w2, w2, #1
    b.ne  .Lsf_cl
    b     .Lsf_wasted
.Lsf_verb:
    ldr   x12, [x28, #L_PLANE]
    mov   w13, w11
.Lsf_vl:
    ldr   w0, [x28, #L_WIDTH]
    bl    br_gets
    str   w0, [x12], #4
    subs  w13, w13, #1
    b.ne  .Lsf_vl
    b     .Lsf_wasted
.Lsf_fixed:
    sub   w0, w9, #8                  // order 0..4
    str   w0, [x28, #L_ORDER]
    str   w0, [x28, #L_FIX]
    str   wzr, [x28, #L_SHIFT]
    cbz   w0, .Lsf_warm
    sub   w1, w0, #1
    mul   w1, w1, w0
    lsr   w1, w1, #1
    adr   x2, fixtab
    add   x2, x2, x1, lsl #2
    add   x3, x28, #L_COEF
    mov   w4, w0
.Lsf_fc:
    ldr   w5, [x2], #4
    str   w5, [x3], #4
    subs  w4, w4, #1
    b.ne  .Lsf_fc
.Lsf_warm:
    ldr   w0, [x28, #L_ORDER]
    cmp   w0, w11
    b.hi  .Lsf_bad
    mov   w13, w0
    cbz   w13, .Lsf_nowarm
    ldr   x12, [x28, #L_PLANE]
.Lsf_wu:
    ldr   w0, [x28, #L_WIDTH]
    bl    br_gets
    str   w0, [x12], #4
    subs  w13, w13, #1
    b.ne  .Lsf_wu
.Lsf_nowarm:
    cmp   w9, #32
    b.lo  .Lsf_resid
    mov   w0, #4
    bl    br_get
    cmp   w0, #15
    b.eq  .Lsf_bad
    add   w0, w0, #1
    str   w0, [x28, #L_PRECIS]
    mov   w0, #5
    bl    br_gets
    tbnz  w0, #31, .Lsf_bad           // a negative shift is not allowed
    str   w0, [x28, #L_SHIFT]
    ldr   w13, [x28, #L_ORDER]
    add   x12, x28, #L_COEF
.Lsf_cf:
    ldr   w0, [x28, #L_PRECIS]
    bl    br_gets
    sub   w14, w13, #1
    str   w0, [x12, x14, lsl #2]      // the first coefficient is the newest sample's
    subs  w13, w13, #1
    b.ne  .Lsf_cf
.Lsf_resid:
    ldr   w0, [x28, #L_FIX]
    cbnz  w0, 1f
    ldr   w0, [x28, #L_ORDER]
    cbz   w0, 1f
    bl    lpc_prep                    // LPC: pad the coefficients; decode_residual then predicts as it decodes
1:  bl    decode_residual
    cbz   w0, .Lsf_bad
.Lsf_wasted:
    ldr   w0, [x28, #L_WASTED]
    cbz   w0, .Lsf_ok
    ldr   x1, [x28, #L_PLANE]
    ldr   w2, [x28, #L_BS]
.Lsf_ws:
    ldr   w3, [x1]
    lsl   w3, w3, w0
    str   w3, [x1], #4
    subs  w2, w2, #1
    b.ne  .Lsf_ws
.Lsf_ok:
    mov   w0, #1
    ldr   x30, [sp], #16
    ret
.Lsf_bad:
    mov   w0, #0
    ldr   x30, [sp], #16
    ret

// ============================================================================
// Undo stereo decorrelation on planes 0 and 1 (NEON, 4 samples per step)
// ============================================================================
FUNCL stereo_fix
    ldr   w0, [x28, #L_CA]
    cmp   w0, #8
    b.lo  .Lst_r
    ldr   w1, [x28, #L_BS]
    ldr   x2, [x19, #S_PLANE0]
    ldr   w3, [x19, #S_MAXBLK]
    add   x3, x2, x3, lsl #2
    lsr   w4, w1, #2                  // groups of 4
    and   w5, w1, #3                  // scalar tail
    cmp   w0, #8
    b.eq  .Lst_ls
    cmp   w0, #9
    b.eq  .Lst_sr
    movi  v3.4s, #1                   // mid / side
    cbz   w4, .Lst_mt
.Lst_m4:
    ld1   {v0.4s}, [x2]
    ld1   {v1.4s}, [x3]
    shl   v0.4s, v0.4s, #1
    and   v2.16b, v1.16b, v3.16b
    orr   v0.16b, v0.16b, v2.16b      // mid = (mid << 1) | (side & 1)
    add   v4.4s, v0.4s, v1.4s
    sshr  v4.4s, v4.4s, #1            // left  = (mid + side) >> 1
    sub   v5.4s, v0.4s, v1.4s
    sshr  v5.4s, v5.4s, #1            // right = (mid - side) >> 1
    st1   {v4.4s}, [x2], #16
    st1   {v5.4s}, [x3], #16
    subs  w4, w4, #1
    b.ne  .Lst_m4
.Lst_mt:
    cbz   w5, .Lst_r
.Lst_m1:
    ldr   w6, [x2]
    ldr   w7, [x3]
    lsl   w6, w6, #1
    and   w8, w7, #1
    orr   w6, w6, w8
    add   w9, w6, w7
    asr   w9, w9, #1
    sub   w10, w6, w7
    asr   w10, w10, #1
    str   w9, [x2], #4
    str   w10, [x3], #4
    subs  w5, w5, #1
    b.ne  .Lst_m1
.Lst_r:
    ret
.Lst_ls:                              // left / side: right = left - side
    cbz   w4, .Lst_lt
.Lst_l4:
    ld1   {v0.4s}, [x2], #16
    ld1   {v1.4s}, [x3]
    sub   v0.4s, v0.4s, v1.4s
    st1   {v0.4s}, [x3], #16
    subs  w4, w4, #1
    b.ne  .Lst_l4
.Lst_lt:
    cbz   w5, .Lst_r
.Lst_l1:
    ldr   w6, [x2], #4
    ldr   w7, [x3]
    sub   w6, w6, w7
    str   w6, [x3], #4
    subs  w5, w5, #1
    b.ne  .Lst_l1
    ret
.Lst_sr:                              // side / right: left = side + right
    cbz   w4, .Lst_st
.Lst_s4:
    ld1   {v0.4s}, [x2]
    ld1   {v1.4s}, [x3], #16
    add   v0.4s, v0.4s, v1.4s
    st1   {v0.4s}, [x2], #16
    subs  w4, w4, #1
    b.ne  .Lst_s4
.Lst_st:
    cbz   w5, .Lst_r
.Lst_s1:
    ldr   w6, [x2]
    ldr   w7, [x3], #4
    add   w6, w6, w7
    str   w6, [x2], #4
    subs  w5, w5, #1
    b.ne  .Lst_s1
    ret

// silence_block: zero every channel's block (a frame whose CRC-16 did not match)
FUNCL silence_block
    ldr   x0, [x19, #S_PLANE0]
    ldr   w1, [x19, #P_CH]
    ldr   w2, [x19, #S_MAXBLK]
    ldr   w3, [x28, #L_BS]
.Lsb_c:
    mov   x4, x0
    mov   w5, w3
.Lsb_z:
    str   wzr, [x4], #4
    subs  w5, w5, #1
    b.ne  .Lsb_z
    add   x0, x0, x2, lsl #2
    subs  w1, w1, #1
    b.ne  .Lsb_c
    ret

// ============================================================================
// Body of a frame whose header was just parsed. w0 = 1 ok, 0 error.
// ============================================================================
FUNCL decode_body
    str   x30, [sp, #-16]!
    ldr   w0, [x19, #P_CH]
    str   w0, [x28, #L_CH]
    str   wzr, [x28, #L_CHIDX]
.Lb_chan:
    ldr   w0, [x28, #L_CHIDX]
    ldr   w1, [x19, #S_MAXBLK]
    mul   x0, x0, x1
    ldr   x2, [x19, #S_PLANE0]
    add   x0, x2, x0, lsl #2
    str   x0, [x28, #L_PLANE]
    ldr   w0, [x28, #L_BPS]
    ldr   w1, [x28, #L_CA]
    ldr   w2, [x28, #L_CHIDX]
    cmp   w1, #8                      // the side channel carries one extra bit
    b.ne  .Lb_n8
    cmp   w2, #1
    b.ne  .Lb_wd
    add   w0, w0, #1
    b     .Lb_wd
.Lb_n8:
    cmp   w1, #9
    b.ne  .Lb_n9
    cbnz  w2, .Lb_wd
    add   w0, w0, #1
    b     .Lb_wd
.Lb_n9:
    cmp   w1, #10
    b.ne  .Lb_wd
    cmp   w2, #1
    b.ne  .Lb_wd
    add   w0, w0, #1
.Lb_wd:
    str   w0, [x28, #L_WIDTH]
    bl    decode_subframe
    cbz   w0, .Lb_fail
    CHECK_OVERRUN .Lb_fail
    ldr   w0, [x28, #L_CHIDX]
    add   w0, w0, #1
    str   w0, [x28, #L_CHIDX]
    ldr   w1, [x28, #L_CH]
    cmp   w0, w1
    b.lo  .Lb_chan
    and   w0, w22, #7                 // pad to a byte, then read the CRC-16
    bl    br_get
    mov   w0, #16
    bl    br_get
    str   w0, [x28, #L_CRC]           // the CRC-16 stored in the frame
    CHECK_OVERRUN .Lb_fail
    ldr   x1, [x19, #P_SRC]
    sub   x0, x20, x1
    lsl   x0, x0, #3
    sub   x0, x0, x22
    lsr   x0, x0, #3
    str   x0, [x19, #S_NEXT]
    ldr   x3, [x28, #L_HSTART]        // CRC-16 over the whole frame, header to the last audio byte
    sub   x2, x0, #2
    sub   x2, x2, x3
    add   x1, x1, x3
    bl    crc16
    ldr   w1, [x28, #L_CRC]
    cmp   w0, w1
    b.eq  .Lb_crcok
    bl    silence_block               // damaged: silence of the right length, not wrong samples
    ldr   w0, [x19, #P_ERRS]
    add   w0, w0, #1
    str   w0, [x19, #P_ERRS]
    ldr   x0, [x28, #L_HSTART]        // the length it claimed cannot be trusted either: look for the
    add   x0, x0, #1                  // next valid frame header from just after this one's first byte
    str   x0, [x19, #S_NEXT]
.Lb_crcok:
    bl    stereo_fix
    ldr   w0, [x28, #L_BS]
    str   w0, [x19, #S_BLKLEN]
    str   wzr, [x19, #S_BLKPOS]
    ldr   w0, [x28, #L_BPS]
    str   w0, [x19, #S_BPS]
    ldr   x0, [x28, #L_START]
    str   x0, [x19, #S_SPOS]
    mov   w0, #1
    ldr   x30, [sp], #16
    ret
.Lb_fail:
    mov   w0, #0
    ldr   x30, [sp], #16
    ret

// decode_next: decode the frame at S_NEXT, resynchronising over damage.
// w0 = 1 a block is ready, 0 end of stream.
FUNCL decode_next
    str   x30, [sp, #-16]!
.Ldn_retry:
    ldr   x4, [x19, #S_NEXT]
    ldr   x0, [x19, #P_LEN]
    cmp   x4, x0
    b.hs  .Ldn_eof
    bl    br_init
    bl    parse_header
    cbnz  w0, .Ldn_body
.Ldn_resync:
    ldr   x4, [x19, #S_NEXT]
    add   x4, x4, #1
    ldr   x5, [x19, #P_LEN]
    bl    ff_scan
    cbz   w0, .Ldn_eof
    str   x4, [x19, #S_NEXT]
    b     .Ldn_retry
.Ldn_body:
    bl    decode_body
    cbnz  w0, .Ldn_ok
    ldr   w0, [x19, #P_ERRS]          // a frame that could not be decoded
    add   w0, w0, #1
    str   w0, [x19, #P_ERRS]
    b     .Ldn_resync
.Ldn_ok:
    mov   w0, #1
    ldr   x30, [sp], #16
    ret
.Ldn_eof:
    ldr   x0, [x19, #P_LEN]
    str   x0, [x19, #S_NEXT]
    str   wzr, [x19, #S_BLKLEN]
    str   wzr, [x19, #S_BLKPOS]
    mov   w0, #0
    ldr   x30, [sp], #16
    ret

// interleave32: w0 = frames to hand out from the decoded block, to L_OUT as int32, each sample
// left-justified: value << (32 - bps). Clobbers x0-x16, v0-v6.
FUNCL interleave32
    mov   w4, w0
    ldr   w5, [x19, #P_CH]
    ldr   w0, [x19, #S_BPS]
    mov   w1, #32
    sub   w6, w1, w0                  // left shift
    dup   v6.4s, w6
    ldr   w9, [x19, #S_BLKPOS]
    ldr   x10, [x19, #S_PLANE0]
    ldr   w11, [x19, #S_MAXBLK]
    cmp   w5, #2
    b.ne  .Li3_gen
    add   x12, x10, x9, lsl #2
    add   x13, x10, x11, lsl #2
    add   x13, x13, x9, lsl #2
    ldr   x14, [x28, #L_OUT]
    lsr   w15, w4, #2
    cbz   w15, .Li3_tail
.Li3_v:
    ld1   {v0.4s}, [x12], #16
    ld1   {v1.4s}, [x13], #16
    sshl  v0.4s, v0.4s, v6.4s
    sshl  v1.4s, v1.4s, v6.4s
    st2   {v0.4s, v1.4s}, [x14], #32
    subs  w15, w15, #1
    b.ne  .Li3_v
.Li3_tail:
    ands  w15, w4, #3
    b.eq  .Li3_done
.Li3_t:
    ldr   w0, [x12], #4
    lsl   w0, w0, w6
    str   w0, [x14], #4
    ldr   w0, [x13], #4
    lsl   w0, w0, w6
    str   w0, [x14], #4
    subs  w15, w15, #1
    b.ne  .Li3_t
    b     .Li3_done
.Li3_gen:
    mov   w15, #0
    lsl   x16, x5, #2                 // output bytes per frame
.Li3_gc:
    mul   w0, w11, w15
    add   x0, x0, x9
    add   x1, x10, x0, lsl #2
    ldr   x2, [x28, #L_OUT]
    add   x2, x2, x15, lsl #2
    mov   w3, w4
.Li3_gl:
    ldr   w0, [x1], #4
    lsl   w0, w0, w6
    str   w0, [x2]
    add   x2, x2, x16
    subs  w3, w3, #1
    b.ne  .Li3_gl
    add   w15, w15, #1
    cmp   w15, w5
    b.lo  .Li3_gc
.Li3_done:
    ldr   w0, [x19, #S_BLKPOS]
    add   w0, w0, w4
    str   w0, [x19, #S_BLKPOS]
    ldr   x0, [x28, #L_FRAMES]
    sub   x0, x0, x4
    str   x0, [x28, #L_FRAMES]
    ldr   x0, [x28, #L_GOT]
    add   x0, x0, x4
    str   x0, [x28, #L_GOT]
    mul   x1, x4, x5
    lsl   x1, x1, #2
    ldr   x0, [x28, #L_OUT]
    add   x0, x0, x1
    str   x0, [x28, #L_OUT]
    ret

// interleave: w0 = frames to hand out from the decoded block, to L_OUT.
// int16 = (sample << max(0,16-bps)) >> max(0,bps-16), saturating. Clobbers x0-x16, v0-v6.
FUNCL interleave
    mov   w4, w0                      // take
    ldr   w5, [x19, #P_CH]
    ldr   w0, [x19, #S_BPS]
    mov   w1, #16
    subs  w6, w1, w0
    csel  w6, w6, wzr, gt             // left shift
    subs  w7, w0, w1
    csel  w7, w7, wzr, gt             // right shift
    sub   w8, w6, w7
    dup   v6.4s, w8                   // signed: positive = left, negative = arithmetic right
    ldr   w9, [x19, #S_BLKPOS]
    ldr   x10, [x19, #S_PLANE0]
    ldr   w11, [x19, #S_MAXBLK]
    cmp   w5, #2
    b.ne  .Lil_gen
    add   x12, x10, x9, lsl #2
    add   x13, x10, x11, lsl #2
    add   x13, x13, x9, lsl #2
    ldr   x14, [x28, #L_OUT]
    lsr   w15, w4, #2
    cbz   w15, .Lil_tail
.Lil_v:
    ld1   {v0.4s}, [x12], #16
    ld1   {v1.4s}, [x13], #16
    sshl  v0.4s, v0.4s, v6.4s
    sshl  v1.4s, v1.4s, v6.4s
    sqxtn v0.4h, v0.4s
    sqxtn v1.4h, v1.4s
    st2   {v0.4h, v1.4h}, [x14], #16
    subs  w15, w15, #1
    b.ne  .Lil_v
.Lil_tail:
    ands  w15, w4, #3
    b.eq  .Lil_done
.Lil_t:
    ldr   w0, [x12], #4
    lsl   w0, w0, w6
    asr   w0, w0, w7
    strh  w0, [x14], #2
    ldr   w0, [x13], #4
    lsl   w0, w0, w6
    asr   w0, w0, w7
    strh  w0, [x14], #2
    subs  w15, w15, #1
    b.ne  .Lil_t
    b     .Lil_done
.Lil_gen:                             // mono and 3..8 channels: one pass per channel
    mov   w15, #0
    lsl   x16, x5, #1                 // output bytes per frame
.Lil_gc:
    mul   w0, w11, w15
    add   x0, x0, x9
    add   x1, x10, x0, lsl #2
    ldr   x2, [x28, #L_OUT]
    add   x2, x2, x15, lsl #1
    mov   w3, w4
.Lil_gl:
    ldr   w0, [x1], #4
    lsl   w0, w0, w6
    asr   w0, w0, w7
    strh  w0, [x2]
    add   x2, x2, x16
    subs  w3, w3, #1
    b.ne  .Lil_gl
    add   w15, w15, #1
    cmp   w15, w5
    b.lo  .Lil_gc
.Lil_done:
    ldr   w0, [x19, #S_BLKPOS]
    add   w0, w0, w4
    str   w0, [x19, #S_BLKPOS]
    ldr   x0, [x28, #L_FRAMES]
    sub   x0, x0, x4
    str   x0, [x28, #L_FRAMES]
    ldr   x0, [x28, #L_GOT]
    add   x0, x0, x4
    str   x0, [x28, #L_GOT]
    mul   x1, x4, x5
    lsl   x1, x1, #1
    ldr   x0, [x28, #L_OUT]
    add   x0, x0, x1
    str   x0, [x28, #L_OUT]
    ret

// ============================================================================
// Exported (through peep_codec_flac)
// ============================================================================

// int open(peep *p, const void *data, size_t len)
FUNCL flac_open
    mov   x9, x0
    mov   x10, x1
    mov   x11, x2
    mov   x12, #0                     // bytes of ID3v2 tag(s) in front of the stream
.Lfo_id3:
    cmp   x11, #52
    b.lo  .Lfo_noid3
    ldr   w3, [x10]
    and   w3, w3, #0xFFFFFF
    MOV32 w4, 0x334449                // 'ID3'
    cmp   w3, w4
    b.ne  .Lfo_noid3
    ldr   w3, [x10, #6]               // four 7-bit size bytes
    MOV32 w4, 0x80808080
    tst   w3, w4
    b.ne  .Lfo_noid3
    rev   w3, w3
    and   w4, w3, #0x7F
    ubfx  w5, w3, #8, #7
    orr   w4, w4, w5, lsl #7
    ubfx  w5, w3, #16, #7
    orr   w4, w4, w5, lsl #14
    lsr   w5, w3, #24
    orr   w4, w4, w5, lsl #21
    add   x4, x4, #10
    ldrb  w5, [x10, #5]
    tbz   w5, #4, .Lfo_nofoot         // footer present: 10 more bytes
    add   x4, x4, #10
.Lfo_nofoot:
    add   x5, x4, #42
    cmp   x5, x11
    b.hi  .Lfo_noid3
    add   x10, x10, x4
    sub   x11, x11, x4
    add   x12, x12, x4
    b     .Lfo_id3
.Lfo_noid3:
    cmp   x11, #42
    b.lo  .Lfo_fail
    ldr   w3, [x10]
    MOV32 w4, 0x43614c66              // 'fLaC'
    cmp   w3, w4
    b.ne  .Lfo_fail
    ldrb  w3, [x10, #4]
    tst   w3, #0x7F                   // the first block must be STREAMINFO
    b.ne  .Lfo_fail
    ldr   w3, [x10, #4]
    rev   w3, w3
    and   w3, w3, #0xFFFFFF
    cmp   w3, #34
    b.lo  .Lfo_fail
    ldr   w3, [x10, #8]
    rev   w3, w3
    lsr   w4, w3, #16                 // min block size
    and   w3, w3, #0xFFFF             // max block size
    cbz   w4, .Lfo_fail
    cbz   w3, .Lfo_fail
    str   w4, [x9, #S_BLK0]
    str   w3, [x9, #S_MAXBLK]
    ldr   x3, [x10, #18]
    rev   x3, x3                      // rate:20 channels-1:3 bps-1:5 samples:36
    lsr   x4, x3, #44
    cbz   x4, .Lfo_fail
    str   w4, [x9, #P_RATE]
    ubfx  x4, x3, #41, #3
    add   w4, w4, #1
    str   w4, [x9, #P_CH]
    ubfx  x4, x3, #36, #5
    add   w4, w4, #1
    cmp   w4, #4
    b.lo  .Lfo_fail
    cmp   w4, #31
    b.hi  .Lfo_fail
    str   w4, [x9, #S_SIBPS]
    strh  w4, [x9, #P_BITS]           // the source's bit depth, for the caller
    ubfx  x4, x3, #0, #36
    str   x4, [x9, #P_TOTAL]
    mov   x5, #4                      // skip metadata blocks
.Lfo_mb:
    add   x6, x5, #4
    cmp   x6, x11
    b.hi  .Lfo_fail
    ldrb  w7, [x10, x5]
    add   x8, x10, x5
    ldr   w6, [x8]
    rev   w6, w6
    and   w6, w6, #0xFFFFFF
    add   x5, x5, x6
    add   x5, x5, #4
    cmp   x5, x11
    b.hi  .Lfo_fail
    tbz   w7, #7, .Lfo_mb
    ldr   w6, [x9, #P_CH]             // workspace: one plane of int32 per channel
    ldr   w7, [x9, #S_MAXBLK]
    mul   x6, x6, x7
    lsl   x6, x6, #2
    add   x6, x6, #16                 // front slack: predict reads up to 3 slots before plane 0
    str   x6, [x9, #P_WNEED]
    ldr   x7, [x9, #P_WORK]
    cbz   x7, .Lfo_fail
    ldr   x8, [x9, #P_WSIZE]
    cmp   x8, x6
    b.lo  .Lfo_fail
    add   x5, x5, x12                 // offsets are from the start of the file, ID3 included
    str   x5, [x9, #S_NEXT]
    str   x5, [x9, #S_START]
    add   x12, x12, #4
    str   x12, [x9, #P_CTX]
    add   x7, x7, #16
    str   x7, [x9, #S_PLANE0]
    mov   w0, #1
    ret
.Lfo_fail:
    mov   w0, #0
    ret

// size_t read(peep *p, int16_t *out, size_t frames)
FUNCL flac_read
    mov   w3, #0
    b     .Lfr_go

// size_t read32(peep *p, int32_t *out, size_t frames): every sample left-justified (<< 32 - bits)
FUNCL flac_read32
    mov   w3, #1
.Lfr_go:
    ENTER
    str   w3, [x28, #L_WIDE]
    mov   x19, x0
    str   x1, [x28, #L_OUT]
    str   x2, [x28, #L_FRAMES]
    str   xzr, [x28, #L_GOT]
.Lfr_loop:
    ldr   x0, [x28, #L_FRAMES]
    cbz   x0, .Lfr_done
    ldr   w1, [x19, #S_BLKLEN]
    ldr   w2, [x19, #S_BLKPOS]
    subs  w1, w1, w2
    b.ne  .Lfr_have
    bl    decode_next
    cbnz  w0, .Lfr_loop
    b     .Lfr_done
.Lfr_have:
    ldr   x0, [x28, #L_FRAMES]
    cmp   x1, x0
    csel  x0, x1, x0, lo
    ldr   w3, [x28, #L_WIDE]
    cbnz  w3, .Lfr_w32
    bl    interleave
    b     .Lfr_loop
.Lfr_w32:
    bl    interleave32
    b     .Lfr_loop
.Lfr_done:
    ldr   x0, [x28, #L_GOT]
    LEAVE

// void seek(peep *p, uint64_t frame)
FUNCL flac_seek
    ENTER
    mov   x19, x0
    mov   x25, x1
    str   wzr, [x19, #S_BLKLEN]
    str   wzr, [x19, #S_BLKPOS]
    ldr   x0, [x19, #S_START]
    str   x0, [x19, #S_NEXT]
    cbz   x25, .Lsk_r
    str   x25, [x28, #L_TGT]
    str   x0, [x28, #L_LO]            // the frame at lo starts at or before the target
    ldr   x1, [x19, #P_LEN]
    str   x1, [x28, #L_HI]
.Lsk_bs:
    ldr   x0, [x28, #L_HI]
    ldr   x1, [x28, #L_LO]
    sub   x0, x0, x1
    cmp   x0, #2
    b.lo  .Lsk_found
    lsr   x0, x0, #1
    add   x4, x0, x1
    str   x4, [x28, #L_MID]
    ldr   x5, [x28, #L_HI]
    bl    ff_scan
    cbz   w0, .Lsk_nf
    ldr   x0, [x28, #L_START]
    ldr   x1, [x28, #L_TGT]
    cmp   x0, x1
    b.hi  .Lsk_gt
    str   x4, [x28, #L_LO]
    b     .Lsk_bs
.Lsk_gt:
    str   x4, [x28, #L_HI]
    b     .Lsk_bs
.Lsk_nf:
    ldr   x0, [x28, #L_MID]
    str   x0, [x28, #L_HI]
    b     .Lsk_bs
.Lsk_found:
    ldr   x0, [x28, #L_LO]
    str   x0, [x19, #S_NEXT]
    bl    decode_next
    cbz   w0, .Lsk_r
    ldr   x0, [x28, #L_TGT]
    ldr   x1, [x19, #S_SPOS]
    subs  x0, x0, x1
    b.lo  .Lsk_r
    ldr   w1, [x19, #S_BLKLEN]
    cmp   x0, x1
    csel  x0, x0, x1, lo
    str   w0, [x19, #S_BLKPOS]
.Lsk_r:
    LEAVE

// size_t peep_flac_metadata(peep *p, int type, int index, const void **data)
// Zero-copy access to the index-th metadata block of the given type of a file opened through
// peep_codec_flac. Returns the block's length and stores its address in *data (may be NULL),
// or (size_t)-1 when there is no such block or p is not a FLAC file.
FUNC peep_flac_metadata
    stp   x29, x30, [sp, #-32]!
    mov   x29, sp
    stp   x19, x20, [sp, #16]
    mov   x19, x0
    mov   x20, x3
    ldr   w4, [x19, #P_KIND]
    cmp   w4, #2
    b.ne  .Lmd_no
    stp   x1, x2, [sp, #-16]!
    bl    .L_peep_flac
    ldp   x1, x2, [sp], #16
    ldr   x4, [x19, #P_CODEC]
    cmp   x0, x4
    b.ne  .Lmd_no
    ldr   x4, [x19, #P_CTX]           // offset of the first block header
    ldr   x5, [x19, #P_SRC]
    ldr   x6, [x19, #P_LEN]
.Lmd_blk:
    add   x7, x4, #4
    cmp   x7, x6
    b.hi  .Lmd_no
    ldr   w8, [x5, x4]
    rev   w8, w8
    and   w9, w8, #0xFFFFFF           // length
    lsr   w10, w8, #24                // last-flag | type
    add   x11, x4, #4                 // body
    add   x12, x11, x9                // end of body
    cmp   x12, x6
    b.hi  .Lmd_no
    and   w13, w10, #0x7F
    cmp   w13, w1
    b.ne  .Lmd_next
    cbz   w2, .Lmd_hit
    sub   w2, w2, #1
.Lmd_next:
    tbnz  w10, #7, .Lmd_no
    mov   x4, x12
    b     .Lmd_blk
.Lmd_hit:
    cbz   x20, .Lmd_hz
    add   x13, x5, x11
    str   x13, [x20]
.Lmd_hz:
    mov   x0, x9
    b     .Lmd_ret
.Lmd_no:
    mov   x0, #-1
.Lmd_ret:
    ldp   x19, x20, [sp, #16]
    ldp   x29, x30, [sp], #32
    ret

// const peep_codec *peep_flac(void): the codec table's address, for languages whose FFI can
// import functions but not data symbols. Position independent (works in a shared library).
FUNC peep_flac
.ifdef APPLE
    adrp  x0, _peep_codec_flac@PAGE
    add   x0, x0, _peep_codec_flac@PAGEOFF
.else
    adrp  x0, :got:peep_codec_flac
    ldr   x0, [x0, :got_lo12:peep_codec_flac]
.endif
    ret

// ============================================================================
    DATA_RO
.ifdef APPLE
    .globl _peep_codec_flac
_peep_codec_flac:
.else
    .globl peep_codec_flac
    .type peep_codec_flac, %object
peep_codec_flac:
.endif
    .quad flac_open, flac_read, flac_seek, 0, flac_read32

NO_EXEC_STACK
