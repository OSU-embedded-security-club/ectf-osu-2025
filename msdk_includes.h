#include <led.h>
#include <mxc.h>
#include <mxc_delay.h>
#include <stdint.h>
#include <stdio.h>

int64_t __multi3(int64_t *result_high, int64_t a, int64_t b) {
  uint32_t a_low = (uint32_t)a;
  uint32_t a_high = (uint32_t)(a >> 32);
  uint32_t b_low = (uint32_t)b;
  uint32_t b_high = (uint32_t)(b >> 32);

  uint64_t low_low = (uint64_t)a_low * b_low;
  uint64_t low_high = (uint64_t)a_low * b_high;
  uint64_t high_low = (uint64_t)a_high * b_low;
  uint64_t high_high = (uint64_t)a_high * b_high;

  uint64_t mid = (low_low >> 32) + (uint32_t)low_high + (uint32_t)high_low;
  uint64_t result_low = ((mid & 0xFFFFFFFF) << 32) | (uint32_t)low_low;
  *result_high =
      (high_high + (mid >> 32) + (low_high >> 32) + (high_low >> 32));

  return result_low;
}
