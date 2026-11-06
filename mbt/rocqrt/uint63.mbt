// Rocq primitive 63-bit integers (Corelib.Numbers.Cyclic.Int63.PrimInt63).
//
// A Rocq `int` is represented by a `UInt64` whose value is always below
// 2^63.  Unsigned operations work modulo 2^63; signed operations (`divs`,
// `ltsb`, `asr`, ...) read bit 62 as the sign bit.  The semantics follow the
// OCaml implementation in rocq/kernel/uint63_63.ml.

///|
let mask : UInt64 = 0x7FFFFFFFFFFFFFFFUL

///|
let sign_bit : UInt64 = 0x4000000000000000UL

///|
/// Constructor results of the `carry` type.
pub(all) enum Carry[A] {
  C0(A)
  C1(A)
} derive(Eq, Debug)

///|
fn to_signed(x : UInt64) -> Int64 {
  if (x & sign_bit) != 0UL {
    (x | 0x8000000000000000UL).reinterpret_as_int64()
  } else {
    x.reinterpret_as_int64()
  }
}

///|
fn of_signed(x : Int64) -> UInt64 {
  x.reinterpret_as_uint64() & mask
}

///|
/// Conversions for interoperability with MoonBit integers.
pub fn u63_of_int(x : Int) -> UInt64 {
  of_signed(x.to_int64())
}

///|
pub fn u63_to_int(x : UInt64) -> Int {
  to_signed(x).to_int()
}

///|
pub fn u63_of_int64(x : Int64) -> UInt64 {
  of_signed(x)
}

///|
pub fn u63_to_int64(x : UInt64) -> Int64 {
  to_signed(x)
}

///|
pub fn u63_lsl(x : UInt64, y : UInt64) -> UInt64 {
  if y < 63UL {
    (x << y.to_int()) & mask
  } else {
    0UL
  }
}

///|
pub fn u63_lsr(x : UInt64, y : UInt64) -> UInt64 {
  if y < 63UL {
    x >> y.to_int()
  } else {
    0UL
  }
}

///|
pub fn u63_asr(x : UInt64, y : UInt64) -> UInt64 {
  let sx = to_signed(x)
  if y < 63UL {
    of_signed(sx >> y.to_int())
  } else if sx >= 0L {
    0UL
  } else {
    mask
  }
}

///|
pub fn u63_land(x : UInt64, y : UInt64) -> UInt64 {
  x & y
}

///|
pub fn u63_lor(x : UInt64, y : UInt64) -> UInt64 {
  x | y
}

///|
pub fn u63_lxor(x : UInt64, y : UInt64) -> UInt64 {
  x ^ y
}

///|
pub fn u63_add(x : UInt64, y : UInt64) -> UInt64 {
  (x + y) & mask
}

///|
pub fn u63_sub(x : UInt64, y : UInt64) -> UInt64 {
  (x - y) & mask
}

///|
pub fn u63_mul(x : UInt64, y : UInt64) -> UInt64 {
  (x * y) & mask
}

///|
pub fn u63_div(x : UInt64, y : UInt64) -> UInt64 {
  if y == 0UL {
    0UL
  } else {
    x / y
  }
}

///|
pub fn u63_mod(x : UInt64, y : UInt64) -> UInt64 {
  if y == 0UL {
    x
  } else {
    x % y
  }
}

///|
pub fn u63_divs(x : UInt64, y : UInt64) -> UInt64 {
  if y == 0UL {
    0UL
  } else {
    of_signed(to_signed(x) / to_signed(y))
  }
}

///|
pub fn u63_mods(x : UInt64, y : UInt64) -> UInt64 {
  if y == 0UL {
    x
  } else {
    of_signed(to_signed(x) % to_signed(y))
  }
}

///|
pub fn u63_eqb(x : UInt64, y : UInt64) -> Bool {
  x == y
}

///|
pub fn u63_ltb(x : UInt64, y : UInt64) -> Bool {
  x < y
}

///|
pub fn u63_leb(x : UInt64, y : UInt64) -> Bool {
  x <= y
}

///|
pub fn u63_ltsb(x : UInt64, y : UInt64) -> Bool {
  to_signed(x) < to_signed(y)
}

///|
pub fn u63_lesb(x : UInt64, y : UInt64) -> Bool {
  to_signed(x) <= to_signed(y)
}

///|
/// Rocq's `comparison` type.
pub(all) enum Comparison {
  Eq
  Lt
  Gt
} derive(Eq, Debug)

///|
/// Unsigned comparison.
pub fn u63_compare(x : UInt64, y : UInt64) -> Comparison {
  if x < y {
    Lt
  } else if x == y {
    Comparison::Eq
  } else {
    Gt
  }
}

///|
/// Signed comparison.
pub fn u63_compares(x : UInt64, y : UInt64) -> Comparison {
  let sx = to_signed(x)
  let sy = to_signed(y)
  if sx < sy {
    Lt
  } else if sx == sy {
    Comparison::Eq
  } else {
    Gt
  }
}

///|
pub fn u63_head0(x : UInt64) -> UInt64 {
  if x == 0UL {
    63UL
  } else {
    (x.clz() - 1).to_uint64()
  }
}

///|
pub fn u63_tail0(x : UInt64) -> UInt64 {
  if x == 0UL {
    63UL
  } else {
    x.ctz().to_uint64()
  }
}

///|
pub fn u63_addc(x : UInt64, y : UInt64) -> Carry[UInt64] {
  let r = u63_add(x, y)
  if r < x {
    C1(r)
  } else {
    C0(r)
  }
}

///|
pub fn u63_addcarryc(x : UInt64, y : UInt64) -> Carry[UInt64] {
  let r = (x + y + 1UL) & mask
  if r <= x {
    C1(r)
  } else {
    C0(r)
  }
}

///|
pub fn u63_subc(x : UInt64, y : UInt64) -> Carry[UInt64] {
  let r = u63_sub(x, y)
  if y <= x {
    C0(r)
  } else {
    C1(r)
  }
}

///|
pub fn u63_subcarryc(x : UInt64, y : UInt64) -> Carry[UInt64] {
  let r = (x - y - 1UL) & mask
  if y < x {
    C0(r)
  } else {
    C1(r)
  }
}

///|
/// Exact product as (high, low) 63-bit words: x * y = high * 2^63 + low.
pub fn u63_mulc(x : UInt64, y : UInt64) -> (UInt64, UInt64) {
  let m32 = 0xFFFFFFFFUL
  let xl = x & m32
  let xh = x >> 32
  let yl = y & m32
  let yh = y >> 32
  let ll = xl * yl
  let lh = xl * yh
  let hl = xh * yl
  let hh = xh * yh
  // 128-bit result (hi, lo)
  let mid = (ll >> 32) + (lh & m32) + (hl & m32)
  let lo = (ll & m32) | (mid << 32)
  let hi = hh + (lh >> 32) + (hl >> 32) + (mid >> 32)
  ((hi << 1) | (lo >> 63), lo & mask)
}

///|
pub fn u63_diveucl(x : UInt64, y : UInt64) -> (UInt64, UInt64) {
  (u63_div(x, y), u63_mod(x, y))
}

///|
/// Division of the 126-bit number xh * 2^63 + xl by y.
pub fn u63_diveucl_21(xh : UInt64, xl : UInt64, y : UInt64) -> (UInt64, UInt64) {
  if y <= xh {
    return (0UL, 0UL)
  }
  let mut nh = xh
  let mut nl = xl
  let mut q = 0UL
  for _i = 0; _i < 63; _i = _i + 1 {
    nh = (nh << 1) | (nl >> 62)
    nl = (nl << 1) & mask
    q = (q << 1) & mask
    if nh >= y {
      q = q | 1UL
      nh = nh - y
    }
  }
  (q, nh)
}

///|
pub fn u63_addmuldiv(p : UInt64, x : UInt64, y : UInt64) -> UInt64 {
  u63_lsl(x, p) | u63_lsr(y, u63_sub(63UL, p))
}
