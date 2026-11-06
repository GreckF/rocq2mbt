From RocqMbt Require Import Prelude.
From Corelib Require Import PrimInt63 CarryType FloatClass PrimFloat PrimArray PrimString.

Open Scope uint63_scope.

(* 63-bit integers *)
Definition big : int := 9223372036854775807.        (* 2^63 - 1 *)
Definition wrap : int := PrimInt63.add big 1.          (* 0 *)
Definition u63_ops (x y : int) : int * int * bool :=
  (PrimInt63.mul x y, PrimInt63.divs x y, PrimInt63.ltsb x y).
Fixpoint pow2 (n : nat) : int := match n with O => 1 | S n => PrimInt63.mul 2 (pow2 n) end.
Definition carry_test : carry int := PrimInt63.addc big 1.
Definition cmp_test : comparison := PrimInt63.compare 3 5.

(* floats *)
Open Scope float_scope.
Definition half : float := 0.5.
Definition fsum (x y : float) : float := PrimFloat.add x (PrimFloat.mul y 2).
Definition special : float * float * float := (PrimFloat.infinity, PrimFloat.neg_zero, PrimFloat.nan).
Definition fclass (x : float) : float_class := PrimFloat.classify x.
Close Scope float_scope.

(* persistent arrays *)
Definition arr0 : array int := [| 1; 2; 3 | 0 |].
Definition arr1 : array int := arr0.[1 <- 20].
Definition arr_read : int * int * int := (arr0.[1], arr1.[1], arr1.[7]).
Definition arr_len : int := PrimArray.length arr1.

(* MoonBit builtin types, traits as classes *)
Definition answer : Int := Int_of_uint63 42.
Definition show_twice {A} `{Show A} (x : A) : String :=
  String_append (to_string x) (to_string x).
Definition show_answer : String := show_twice answer.
Definition same {A} `{Eq A} (x y : A) : bool := equal x y.
Definition arrays_equal : bool :=
  same (Array_push (Array_make (Int_of_uint63 2) answer) answer)
       (Array_make (Int_of_uint63 3) answer).

(* a Rocq-defined error type and a raise function *)
Inductive MathError := DivByZero | Negative (n : Int).

Definition safe_div (a b : Int) : Result Int MathError :=
  if Int_eqb b (Int_of_uint63 0) then Err DivByZero
  else if Int_ltb a (Int_of_uint63 0) then Err (Negative a)
  else Ok (Int_div a b).
Extract MoonBit Raise safe_div.

Definition div_or_zero (a b : Int) : Int :=
  match safe_div a b with Ok q => q | Err _ => Int_of_uint63 0 end.

Extraction "prim/prim.mbt"
  wrap u63_ops pow2 carry_test cmp_test half fsum special fclass
  arr_read arr_len answer show_twice show_answer same arrays_equal
  safe_div div_or_zero.
