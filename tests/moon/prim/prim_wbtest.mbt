// Runtime tests for the code extracted from tests/Prim.v.

test "uint63" {
  assert_eq(wrap, 0UL)
  assert_eq(u63_ops(6UL, 4UL), ((24UL, 1UL), false))
  assert_eq(pow2(Nat::S(Nat::S(Nat::S(Nat::O)))), 8UL)
  assert_eq(carry_test, @rocqrt.Carry::C1(0UL))
  assert_eq(cmp_test, @rocqrt.Comparison::Lt)
}

test "floats" {
  assert_eq(half, 0.5)
  assert_eq(fsum(1.0, 2.0), 5.0)
  let ((inf, nz), n) = special
  assert_eq(inf, 1.0 / 0.0)
  assert_eq(@rocqrt.f64_classify(nz), @rocqrt.FloatClass::NZero)
  assert_eq(n != n, true)
  assert_eq(fclass(-3.0), @rocqrt.FloatClass::NNormal)
}

test "persistent arrays" {
  assert_eq(arr_read, ((2UL, 20UL), 0UL))
  assert_eq(arr_len, 3UL)
  assert_eq(arr0.to_array(), [1UL, 2UL, 3UL])
}

test "builtin types and traits" {
  assert_eq(answer, 42)
  assert_eq(show_answer, "4242")
  assert_eq(arrays_equal, true)
  assert_eq(show_twice(show_Int, 7), "77")
}

test "raise functions" {
  assert_eq(div_or_zero(7, 2), 3)
  assert_eq(div_or_zero(7, 0), 0)
  assert_eq(safe_div(9, 3), 3)
  let r : Result[Int, MathError] = try safe_div(-1, 3) catch { e => Err(e) } noraise { v => Ok(v) }
  match r {
    Err(MathError::Negative(k)) => assert_eq(k, -1)
    _ => fail("expected Negative")
  }
}
