// Rocq primitive floats (Corelib.Floats.PrimFloat) on MoonBit `Double`.
// Semantics follow rocq/kernel/float64_common.ml.

///|
pub(all) enum FloatComparison {
  FEq
  FLt
  FGt
  FNotComparable
} derive(Eq, Debug)

///|
pub(all) enum FloatClass {
  PNormal
  NNormal
  PSubn
  NSubn
  PZero
  NZero
  PInf
  NInf
  NaN
} derive(Eq, Debug)

///|
fn bits(x : Double) -> UInt64 {
  x.reinterpret_as_uint64()
}

///|
fn of_bits(b : UInt64) -> Double {
  b.reinterpret_as_double()
}

///|
fn is_nan(x : Double) -> Bool {
  x != x
}

///|
fn negative(x : Double) -> Bool {
  (bits(x) >> 63) != 0UL
}

///|
pub fn f64_opp(x : Double) -> Double {
  -x
}

///|
pub fn f64_abs(x : Double) -> Double {
  of_bits(bits(x) & 0x7FFFFFFFFFFFFFFFUL)
}

///|
pub fn f64_sqrt(x : Double) -> Double {
  x.sqrt()
}

///|
pub fn f64_add(x : Double, y : Double) -> Double {
  x + y
}

///|
pub fn f64_sub(x : Double, y : Double) -> Double {
  x - y
}

///|
pub fn f64_mul(x : Double, y : Double) -> Double {
  x * y
}

///|
pub fn f64_div(x : Double, y : Double) -> Double {
  x / y
}

///|
pub fn f64_eqb(x : Double, y : Double) -> Bool {
  x == y
}

///|
pub fn f64_ltb(x : Double, y : Double) -> Bool {
  x < y
}

///|
pub fn f64_leb(x : Double, y : Double) -> Bool {
  x <= y
}

///|
pub fn f64_compare(x : Double, y : Double) -> FloatComparison {
  if x < y {
    FLt
  } else if x > y {
    FGt
  } else if x == y {
    FEq
  } else {
    FNotComparable
  }
}

///|
/// Leibniz equality: NaNs are equal, +0 and -0 are not.
pub fn f64_equal(x : Double, y : Double) -> Bool {
  if x == y {
    x != 0.0 || negative(x) == negative(y)
  } else {
    is_nan(x) && is_nan(y)
  }
}

///|
pub fn f64_classify(x : Double) -> FloatClass {
  let e = (bits(x) >> 52) & 0x7FFUL
  let m = bits(x) & 0xFFFFFFFFFFFFFUL
  let neg = negative(x)
  if e == 0x7FFUL {
    if m != 0UL {
      NaN
    } else if neg {
      NInf
    } else {
      PInf
    }
  } else if e == 0UL {
    if m == 0UL {
      if neg {
        NZero
      } else {
        PZero
      }
    } else if neg {
      NSubn
    } else {
      PSubn
    }
  } else if neg {
    NNormal
  } else {
    PNormal
  }
}

///|
pub fn f64_of_uint63(x : UInt64) -> Double {
  x.to_double()
}

///|
/// x * 2^n, correctly rounded (port of musl's scalbn).
pub fn f64_ldexp(x : Double, n : Int) -> Double {
  let mut y = x
  let mut n = n
  let p1023 = of_bits(0x7FEUL << 52) // 2^1023
  let pm969 = of_bits((1023UL - 969UL) << 52) // 2^-1022 * 2^53 = 2^-969
  if n > 1023 {
    y = y * p1023
    n = n - 1023
    if n > 1023 {
      y = y * p1023
      n = n - 1023
      if n > 1023 {
        n = 1023
      }
    }
  } else if n < -1022 {
    y = y * pm969
    n = n + 1022 - 53
    if n < -1022 {
      y = y * pm969
      n = n + 1022 - 53
      if n < -1022 {
        n = -1022
      }
    }
  }
  y * of_bits((0x3FF + n).to_uint64() << 52)
}

///|
/// (m, e) with x = m * 2^e and 0.5 <= |m| < 1, for finite non-zero x.
fn frexp(x : Double) -> (Double, Int) {
  let e = ((bits(x) >> 52) & 0x7FFUL).to_int()
  if e == 0 {
    // subnormal: scale to normal first
    let (m, e2) = frexp(x * of_bits((1023UL + 64UL) << 52))
    (m, e2 - 64)
  } else {
    let m = of_bits((bits(x) & 0x800FFFFFFFFFFFFFUL) | (1022UL << 52))
    (m, e - 1022)
  }
}

///|
let prec = 53

///|
let eshift = 2101

///|
pub fn f64_normfr_mantissa(x : Double) -> UInt64 {
  let a = f64_abs(x)
  if a >= 0.5 && a < 1.0 {
    f64_ldexp(a, prec).to_uint64()
  } else {
    0UL
  }
}

///|
pub fn f64_frshiftexp(x : Double) -> (Double, UInt64) {
  match f64_classify(x) {
    PZero | NZero | PInf | NInf | NaN => (x, 0UL)
    _ => {
      let (m, e) = frexp(x)
      (m, (e + eshift).to_uint64())
    }
  }
}

///|
pub fn f64_ldshiftexp(x : Double, e : UInt64) -> Double {
  let e = if e < (2 * eshift).to_uint64() { e.to_int() } else { 2 * eshift }
  f64_ldexp(x, e - eshift)
}

///|
pub fn f64_next_up(x : Double) -> Double {
  if is_nan(x) || x == of_bits(0x7FF0000000000000UL) {
    x
  } else if x == 0.0 {
    of_bits(1UL)
  } else if negative(x) {
    of_bits(bits(x) - 1UL)
  } else {
    of_bits(bits(x) + 1UL)
  }
}

///|
pub fn f64_next_down(x : Double) -> Double {
  -f64_next_up(-x)
}
