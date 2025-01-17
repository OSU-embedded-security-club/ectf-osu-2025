#include <led.h>
#include <mxc.h>
#include <mxc_delay.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
  __attribute__((aligned(16))) uint64_t lo;
  int64_t hi;
} zig_i128;

zig_i128 __multi3(zig_i128 lhs, zig_i128 rhs) {
  uint64_t a_low = lhs.lo;
  int64_t a_high = lhs.hi;
  uint64_t b_low = rhs.lo;
  int64_t b_high = rhs.hi;

  uint32_t a_ll = (uint32_t)a_low;
  uint32_t a_lh = (uint32_t)(a_low >> 32);
  uint32_t a_hl = (uint32_t)a_high;
  uint32_t a_hh = (uint32_t)(a_high >> 32);
  uint32_t b_ll = (uint32_t)b_low;
  uint32_t b_lh = (uint32_t)(b_low >> 32);
  uint32_t b_hl = (uint32_t)b_high;
  uint32_t b_hh = (uint32_t)(b_high >> 32);

  uint64_t p0 = (uint64_t)a_ll * b_ll;
  uint64_t p1 = (uint64_t)a_ll * b_lh;
  uint64_t p2 = (uint64_t)a_lh * b_ll;
  uint64_t p3 = (uint64_t)a_lh * b_lh;
  uint64_t p4 = (uint64_t)a_hl * b_ll;
  uint64_t p5 = (uint64_t)a_hl * b_lh;
  uint64_t p6 = (uint64_t)a_hh * b_ll;
  uint64_t p7 = (uint64_t)a_hh * b_lh;

  uint64_t result_low = p0;
  uint64_t t = p1 + (p0 >> 32);
  result_low = (t << 32) | (result_low & 0xFFFFFFFF);

  uint64_t result_high = (t >> 32) + p2 + p3;
  result_high += p4 + p5 + p6 + p7;

  if (a_high < 0) {
    result_high += (uint64_t)b_low;
  }
  if (b_high < 0) {
    result_high += (uint64_t)a_low;
  }

  zig_i128 result;
  result.lo = result_low;
  result.hi = result_high;

  return result;
}
