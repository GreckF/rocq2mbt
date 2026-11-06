test "uint63 arithmetic wraps modulo 2^63" {
  let max = 0x7FFFFFFFFFFFFFFFUL
  assert_eq(@rocqrt.u63_add(max, 1UL), 0UL)
  assert_eq(@rocqrt.u63_sub(0UL, 1UL), max)
  assert_eq(@rocqrt.u63_mul(max, 2UL), max - 1UL)
  assert_eq(@rocqrt.u63_div(7UL, 0UL), 0UL)
  assert_eq(@rocqrt.u63_mod(7UL, 0UL), 7UL)
  assert_eq(@rocqrt.u63_lsl(1UL, 62UL), 0x4000000000000000UL)
  assert_eq(@rocqrt.u63_lsl(1UL, 63UL), 0UL)
  assert_eq(@rocqrt.u63_head0(1UL), 62UL)
  assert_eq(@rocqrt.u63_head0(0UL), 63UL)
  assert_eq(@rocqrt.u63_tail0(8UL), 3UL)
}

test "uint63 signed operations" {
  let m1 = @rocqrt.u63_of_int(-1)
  assert_eq(m1, 0x7FFFFFFFFFFFFFFFUL)
  assert_eq(@rocqrt.u63_to_int(@rocqrt.u63_divs(@rocqrt.u63_of_int(-7), 2UL)), -3)
  assert_eq(@rocqrt.u63_to_int(@rocqrt.u63_mods(@rocqrt.u63_of_int(-7), 2UL)), -1)
  assert_eq(@rocqrt.u63_ltsb(m1, 0UL), true)
  assert_eq(@rocqrt.u63_ltb(m1, 0UL), false)
  assert_eq(@rocqrt.u63_asr(m1, 5UL), m1)
  assert_eq(@rocqrt.u63_compares(m1, 0UL), @rocqrt.Comparison::Lt)
}

test "uint63 carries and wide operations" {
  let max = 0x7FFFFFFFFFFFFFFFUL
  assert_eq(@rocqrt.u63_addc(max, 1UL), @rocqrt.Carry::C1(0UL))
  assert_eq(@rocqrt.u63_subc(0UL, 1UL), @rocqrt.Carry::C1(max))
  assert_eq(@rocqrt.u63_mulc(max, max), (max - 1UL, 1UL))
  assert_eq(@rocqrt.u63_mulc(3UL, 5UL), (0UL, 15UL))
  let (q, r) = @rocqrt.u63_diveucl_21(1UL, 5UL, 3UL)
  // (2^63 + 5) / 3
  assert_eq(q, 3074457345618258604UL)
  assert_eq(r, 1UL)
  assert_eq(@rocqrt.u63_addmuldiv(4UL, 1UL, max), 31UL)
}

test "float64" {
  assert_eq(@rocqrt.f64_classify(0.0), @rocqrt.FloatClass::PZero)
  assert_eq(@rocqrt.f64_classify(-0.0), @rocqrt.FloatClass::NZero)
  assert_eq(@rocqrt.f64_classify(1.0e-310), @rocqrt.FloatClass::PSubn)
  assert_eq(@rocqrt.f64_equal(0.0, -0.0), false)
  assert_eq(@rocqrt.f64_compare(1.0, 2.0), @rocqrt.FloatComparison::FLt)
  let (m, e) = @rocqrt.f64_frshiftexp(12.0)
  assert_eq(m, 0.75)
  assert_eq(e, 2105UL)
  assert_eq(@rocqrt.f64_ldshiftexp(m, e), 12.0)
  let (m2, e2) = @rocqrt.f64_frshiftexp(1.0e-310)
  assert_eq(@rocqrt.f64_ldshiftexp(m2, e2), 1.0e-310)
  assert_eq(@rocqrt.f64_normfr_mantissa(0.75), 6755399441055744UL)
  assert_eq(@rocqrt.f64_next_up(1.0), 1.0000000000000002)
  assert_eq(@rocqrt.f64_next_down(0.0), -5.0e-324)
}

test "persistent arrays" {
  let a0 = @rocqrt.PArray::make(3UL, 0)
  let a1 = a0.set(1UL, 10)
  let a2 = a1.set(2UL, 20)
  assert_eq(a2.get(1UL), 10)
  assert_eq(a0.get(1UL), 0)
  assert_eq(a1.get(2UL), 0)
  assert_eq(a2.get(2UL), 20)
  assert_eq(a2.get(99UL), 0)
  assert_eq(a0.set(99UL, 5).length(), 3UL)
  let c = a1.copy().set(0UL, 7)
  assert_eq(c.to_array(), [7, 10, 0])
  assert_eq(a1.to_array(), [0, 10, 0])
}
