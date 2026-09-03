/* JIT paint_frame for Mode B demo (and former FbJit tipa).
 * void paint(uint32_t *base, int w, int h, int bpr, uint32_t t, const int32_t *orbs);
 * Full-frame redraw using 4x4 block fills (~16x fewer stores than per-pixel).
 * Orbs: 3 x {x,y,r} int32.
 */
.align 2
.globl _paint
_paint:
  stp x29, x30, [sp, #-96]!
  stp x19, x20, [sp, #16]
  stp x21, x22, [sp, #32]
  stp x23, x24, [sp, #48]
  stp x25, x26, [sp, #64]
  stp x27, x28, [sp, #80]
  mov x29, sp
  mov x19, x0
  mov w20, w1
  mov w21, w2
  mov w22, w3
  mov w23, w4
  mov x24, x5
  lsl w23, w23, #3
  mov w25, #0
yloop:
  umull x26, w25, w22
  add x26, x19, x26
  mov w27, #0
xloop:
  add w8, w27, w23
  mov w9, #3
  mul w8, w8, w9
  add w9, w25, w23
  mov w10, #5
  mul w9, w9, w10
  add w10, w27, w25
  lsl w10, w10, #2
  eor w11, w8, w9
  eor w11, w11, w10
  eor w11, w11, w23
  and w12, w11, #0xff
  lsr w13, w11, #3
  and w13, w13, #0xff
  lsr w14, w11, #6
  and w14, w14, #0xff
  lsl w13, w13, #8
  lsl w14, w14, #16
  orr w12, w12, w13
  orr w12, w12, w14
  mov w8, #0
  movk w8, #0xff00, lsl #16
  orr w12, w12, w8

  mov w28, #0
orbloop:
  mov w8, #12
  mul w8, w28, w8
  add x8, x24, w8, uxtw
  ldr w9, [x8]
  ldr w10, [x8, #4]
  ldr w11, [x8, #8]
  sub w13, w27, w9
  sub w14, w25, w10
  mul w13, w13, w13
  mul w14, w14, w14
  add w13, w13, w14
  mul w11, w11, w11
  cmp w13, w11
  b.ge 1f
  mov w13, #0xe0ff
  movk w13, #0x00c0, lsl #16
  orr w12, w12, w13
1:
  add w28, w28, #1
  cmp w28, #3
  b.lo orbloop

  /* fill 4x4 block with same color (smooth + full coverage) */
  mov w8, #0
row4:
  umull x9, w8, w22
  add x9, x26, x9
  str w12, [x9, w27, uxtw #2]
  add w10, w27, #1
  cmp w10, w20
  b.hs 2f
  str w12, [x9, w10, uxtw #2]
2:
  add w10, w27, #2
  cmp w10, w20
  b.hs 3f
  str w12, [x9, w10, uxtw #2]
3:
  add w10, w27, #3
  cmp w10, w20
  b.hs 4f
  str w12, [x9, w10, uxtw #2]
4:
  add w8, w8, #1
  cmp w8, #4
  b.lo row4

  add w27, w27, #4
  cmp w27, w20
  b.lo xloop
  add w25, w25, #4
  cmp w25, w21
  b.lo yloop

  ldp x27, x28, [sp, #80]
  ldp x25, x26, [sp, #64]
  ldp x23, x24, [sp, #48]
  ldp x21, x22, [sp, #32]
  ldp x19, x20, [sp, #16]
  ldp x29, x30, [sp], #96
  ret
