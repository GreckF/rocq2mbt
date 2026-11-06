// Extracted from Rocq by rocq2mbt (MoonBit extraction).

pub(all) enum Nat {
  O
  S(Nat)
}

pub let infinity : Double = (1.0 / 0.0)

pub let nan : Double = (0.0 / 0.0)

pub let neg_zero : Double = (-0x0.0p0)

pub type Array0[A] = @rocqrt.PArray[A]

pub type Array1[A] = Array[A]

pub type Eq0[A] = (A) -> (A) -> Bool
// singleton inductive, whose constructor was Build_Eq

pub type Show0[A] = (A) -> String
// singleton inductive, whose constructor was Build_Show

pub let eq_Int : Eq0[Int] = fn(x1) { fn(x2) { (x1 == x2) } }

#warnings("-unused_trait_bound")
pub fn[A : Eq] eq_Array(_ : Eq0[A]) -> Eq0[Array1[A]] {
  fn(x1) { fn(x2) { (x1 == x2) } }
}

pub let show_Int : Show0[Int] = fn(x1) { x1.to_string() }

pub let big : UInt64 = 9223372036854775807UL

pub let wrap : UInt64 = @rocqrt.u63_add(big, 1UL)

pub fn u63_ops(x : UInt64, y : UInt64) -> ((UInt64, UInt64), Bool) {
  ((@rocqrt.u63_mul(x, y), @rocqrt.u63_divs(x, y)), @rocqrt.u63_ltsb(x, y))
}

pub fn pow2(n : Nat) -> UInt64 {
  match n {
    Nat::O => 1UL
    Nat::S(n0) => @rocqrt.u63_mul(2UL, pow2(n0))
  }
}

pub let carry_test : @rocqrt.Carry[UInt64] = @rocqrt.u63_addc(big, 1UL)

pub let cmp_test : @rocqrt.Comparison = @rocqrt.u63_compare(3UL, 5UL)

pub let half : Double = 0x1.0p-1

pub fn fsum(x : Double, y : Double) -> Double {
  @rocqrt.f64_add(x, @rocqrt.f64_mul(y, 0x1.0p1))
}

pub let special : ((Double, Double), Double) = ((infinity, neg_zero), nan)

pub let fclass : (Double) -> @rocqrt.FloatClass = fn(x1) { @rocqrt.f64_classify(x1) }

pub let arr0 : Array0[UInt64] = @rocqrt.PArray::of_array([1UL, 2UL, 3UL], 0UL)

pub let arr1 : Array0[UInt64] = @rocqrt.PArray::set(arr0, 1UL, 20UL)

pub let arr_read : ((UInt64, UInt64), UInt64) = ((@rocqrt.PArray::get(arr0, 1UL), @rocqrt.PArray::get(arr1, 1UL)), @rocqrt.PArray::get(arr1, 7UL))

pub let arr_len : UInt64 = @rocqrt.PArray::length(arr1)

pub let answer : Int = @rocqrt.u63_to_int(42UL)

#warnings("-unused_trait_bound")
pub fn[A : Show] show_twice(h : Show0[A], x : A) -> String {
  (h(x) + h(x))
}

pub let show_answer : String = show_twice(show_Int, answer)

#warnings("-unused_trait_bound")
pub fn[A : Eq] same(h : Eq0[A]) -> (A) -> (A) -> Bool {
  h
}

pub let arrays_equal : Bool = (same(eq_Array(eq_Int)))({ let rocq_c = Array::make(@rocqrt.u63_to_int(2UL), answer).copy(); rocq_c.push(answer); rocq_c })(Array::make(@rocqrt.u63_to_int(3UL), answer))

pub(all) suberror MathError {
  DivByZero
  Negative(Int)
}

pub fn safe_div(a : Int, b : Int) -> Int raise MathError {
  let rocq_result = match (b == @rocqrt.u63_to_int(0UL)) {
    true => Result::Err(MathError::DivByZero)
    false => match (a < @rocqrt.u63_to_int(0UL)) {
      true => Result::Err(MathError::Negative(a))
      false => Result::Ok((a / b))
    }
  }
  match rocq_result {
    Result::Ok(rocq_v) => rocq_v
    Result::Err(rocq_e) => raise rocq_e
  }
}

pub fn div_or_zero(a : Int, b : Int) -> Int {
  match (try safe_div(a, b) catch { rocq_e => Result::Err(rocq_e) } noraise { rocq_v => Result::Ok(rocq_v) }) {
    Result::Ok(q) => q
    Result::Err(_) => @rocqrt.u63_to_int(0UL)
  }
}
