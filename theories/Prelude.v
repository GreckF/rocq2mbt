(** MoonBit's builtin types, [Result], and its main traits, for writing Rocq
    code that interoperates with MoonBit.  Extraction maps everything back to
    the MoonBit builtins.

    Traits are Rocq classes (records of methods).  Instances for builtin
    types are dictionaries built from MoonBit's own implementations.  When a
    function with a dictionary argument [{Eq A}] is extracted, the MoonBit
    type parameter gets the matching bound [A : Eq]. *)

From RocqMbt Require Export ExtrMoonBitPrim.
From Corelib Require Import PrimInt63 PrimFloat PrimString.

(** * Result, [raise] functions *)

Inductive Result (T E : Type) : Type :=
| Ok : T -> Result T E
| Err : E -> Result T E.
Arguments Ok {T E} _.
Arguments Err {T E} _.
Register Result as rocq2mbt.result.type.
Extract Inductive Result => "Result" [ "Result::Ok" "Result::Err" ].

(** * Builtin types *)

Axiom Int : Type.
Extract Inlined Constant Int => "Int".
Axiom Int64 : Type.
Extract Inlined Constant Int64 => "Int64".
Axiom UInt : Type.
Extract Inlined Constant UInt => "UInt".
Axiom UInt64 : Type.
Extract Inlined Constant UInt64 => "UInt64".
Axiom Byte : Type.
Extract Inlined Constant Byte => "Byte".
Axiom Char : Type.
Extract Inlined Constant Char => "Char".
Axiom String : Type.
Extract Inlined Constant String => "String".
Axiom Bytes : Type.
Extract Inlined Constant Bytes => "Bytes".
Axiom Error : Type.
Extract Inlined Constant Error => "Error".
(** MoonBit's [Double] is Rocq's primitive float. *)
Abbreviation Double := PrimFloat.float.
(** Mutable MoonBit arrays, only used through pure operations below. *)
Axiom Array : Type -> Type.
Extract Constant Array "A" => "Array[A]".

(** * Conversions and literals *)

Axiom Int_of_uint63 : PrimInt63.int -> Int.
Extract MoonBit Function Int_of_uint63 => "@rocqrt.u63_to_int($0)".
Axiom Int_to_uint63 : Int -> PrimInt63.int.
Extract MoonBit Function Int_to_uint63 => "@rocqrt.u63_of_int($0)".
Axiom Int64_of_int : Int -> Int64.
Extract MoonBit Function Int64_of_int => "$0.to_int64()".
Axiom Int64_to_int : Int64 -> Int.
Extract MoonBit Function Int64_to_int => "$0.to_int()".
Axiom UInt_of_int : Int -> UInt.
Extract MoonBit Function UInt_of_int => "$0.reinterpret_as_uint()".
Axiom UInt_to_int : UInt -> Int.
Extract MoonBit Function UInt_to_int => "$0.reinterpret_as_int()".
Axiom UInt64_of_uint63 : PrimInt63.int -> UInt64.
Extract MoonBit Function UInt64_of_uint63 => "$0".
Axiom UInt64_to_uint63 : UInt64 -> PrimInt63.int.
Extract MoonBit Function UInt64_to_uint63 => "($0 & 0x7FFFFFFFFFFFFFFFUL)".
Axiom Double_of_int : Int -> Double.
Extract MoonBit Function Double_of_int => "$0.to_double()".
Axiom Char_of_int : Int -> Char.
Extract MoonBit Function Char_of_int => "$0.unsafe_to_char()".
Axiom Char_to_int : Char -> Int.
Extract MoonBit Function Char_to_int => "$0.to_int()".
(** String literals: [String_of_pstring "abc"%pstring]. *)
Axiom String_of_pstring : PrimString.string -> String.
Extract MoonBit Function String_of_pstring => "$0".

(** * Int arithmetic *)

Axiom Int_add Int_sub Int_mul Int_div Int_mod : Int -> Int -> Int.
Extract MoonBit Function Int_add => "($0 + $1)".
Extract MoonBit Function Int_sub => "($0 - $1)".
Extract MoonBit Function Int_mul => "($0 * $1)".
Extract MoonBit Function Int_div => "($0 / $1)".
Extract MoonBit Function Int_mod => "($0 % $1)".
Axiom Int_neg : Int -> Int.
Extract MoonBit Function Int_neg => "(-$0)".
Axiom Int_eqb Int_ltb Int_leb : Int -> Int -> bool.
Extract MoonBit Function Int_eqb => "($0 == $1)".
Extract MoonBit Function Int_ltb => "($0 < $1)".
Extract MoonBit Function Int_leb => "($0 <= $1)".

(** * Strings *)

Axiom String_append : String -> String -> String.
Extract MoonBit Function String_append => "($0 + $1)".
Axiom String_length : String -> Int.
Extract MoonBit Function String_length => "$0.length()".

(** * Arrays (pure operations: the argument is never mutated) *)

Axiom Array_make : forall {A}, Int -> A -> Array A.
Extract MoonBit Function Array_make => "Array::make($0, $1)".
Axiom Array_length : forall {A}, Array A -> Int.
Extract MoonBit Function Array_length => "$0.length()".
Axiom Array_get : forall {A}, Array A -> Int -> option A.
Extract MoonBit Function Array_get => "$0.get($1)".
Axiom Array_push : forall {A}, Array A -> A -> Array A.
Extract MoonBit Function Array_push =>
  "{ let rocq_c = $0.copy(); rocq_c.push($1); rocq_c }".
Axiom Array_set : forall {A}, Array A -> Int -> A -> Array A.
Extract MoonBit Function Array_set =>
  "{ let rocq_c = $0.copy(); rocq_c[$1] = $2; rocq_c }".
Axiom Array_map : forall {A B}, Array A -> (A -> B) -> Array B.
Extract MoonBit Function Array_map => "$0.map($1)".
Axiom Array_fold : forall {A B}, Array A -> B -> (B -> A -> B) -> B.
Extract MoonBit Function Array_fold =>
  "$0.fold(init=$1, fn(rocq_b, rocq_a) { $2(rocq_b)(rocq_a) })".
Axiom Array_of_parray : forall {A}, PrimArray.array A -> Array A.
Extract MoonBit Function Array_of_parray => "$0.to_array()".

(** * Traits *)

(** MoonBit's statically dispatched trait methods, at any type.  They are
    only used to build the instances below: extraction calls them at a
    concrete type, or under the bound added for the instance's own
    dictionary arguments. *)
Module Builtin.
  Axiom equal : forall {A}, A -> A -> bool.
  Extract MoonBit Function equal => "($0 == $1)".
  Axiom compare : forall {A}, A -> A -> Int.
  Extract MoonBit Function compare => "$0.compare($1)".
  Axiom to_string : forall {A}, A -> String.
  Extract MoonBit Function to_string => "$0.to_string()".
  Axiom hash : forall {A}, A -> Int.
  Extract MoonBit Function hash => "$0.hash()".
End Builtin.

Class Eq (Self : Type) := { equal : Self -> Self -> bool }.
Extract MoonBit Trait Eq => "Eq".
Class Compare (Self : Type) := { compare : Self -> Self -> Int }.
Extract MoonBit Trait Compare => "Compare".
Class Show (Self : Type) := { to_string : Self -> String }.
Extract MoonBit Trait Show => "Show".
Class Hash (Self : Type) := { hash : Self -> Int }.
Extract MoonBit Trait Hash => "Hash".

#[global] Instance Eq_Int : Eq Int := {| equal := Builtin.equal |}.
#[global] Instance Eq_Int64 : Eq Int64 := {| equal := Builtin.equal |}.
#[global] Instance Eq_UInt : Eq UInt := {| equal := Builtin.equal |}.
#[global] Instance Eq_UInt64 : Eq UInt64 := {| equal := Builtin.equal |}.
#[global] Instance Eq_Double : Eq Double := {| equal := Builtin.equal |}.
#[global] Instance Eq_Char : Eq Char := {| equal := Builtin.equal |}.
#[global] Instance Eq_String : Eq String := {| equal := Builtin.equal |}.
#[global] Instance Eq_Bool : Eq bool := {| equal := Builtin.equal |}.
#[global] Instance Eq_Array {A} `{Eq A} : Eq (Array A) := {| equal := Builtin.equal |}.
#[global] Instance Eq_Option {A} `{Eq A} : Eq (option A) := {| equal := Builtin.equal |}.

#[global] Instance Compare_Int : Compare Int := {| compare := Builtin.compare |}.
#[global] Instance Compare_Int64 : Compare Int64 := {| compare := Builtin.compare |}.
#[global] Instance Compare_UInt : Compare UInt := {| compare := Builtin.compare |}.
#[global] Instance Compare_UInt64 : Compare UInt64 := {| compare := Builtin.compare |}.
#[global] Instance Compare_Double : Compare Double := {| compare := Builtin.compare |}.
#[global] Instance Compare_Char : Compare Char := {| compare := Builtin.compare |}.
#[global] Instance Compare_String : Compare String := {| compare := Builtin.compare |}.
#[global] Instance Compare_Array {A} `{Compare A} : Compare (Array A) :=
  {| compare := Builtin.compare |}.

#[global] Instance Show_Int : Show Int := {| to_string := Builtin.to_string |}.
#[global] Instance Show_Int64 : Show Int64 := {| to_string := Builtin.to_string |}.
#[global] Instance Show_UInt : Show UInt := {| to_string := Builtin.to_string |}.
#[global] Instance Show_UInt64 : Show UInt64 := {| to_string := Builtin.to_string |}.
#[global] Instance Show_Double : Show Double := {| to_string := Builtin.to_string |}.
#[global] Instance Show_Char : Show Char := {| to_string := Builtin.to_string |}.
#[global] Instance Show_String : Show String := {| to_string := Builtin.to_string |}.
#[global] Instance Show_Bool : Show bool := {| to_string := Builtin.to_string |}.

#[global] Instance Hash_Int : Hash Int := {| hash := Builtin.hash |}.
#[global] Instance Hash_Int64 : Hash Int64 := {| hash := Builtin.hash |}.
#[global] Instance Hash_UInt : Hash UInt := {| hash := Builtin.hash |}.
#[global] Instance Hash_UInt64 : Hash UInt64 := {| hash := Builtin.hash |}.
#[global] Instance Hash_Char : Hash Char := {| hash := Builtin.hash |}.
#[global] Instance Hash_String : Hash String := {| hash := Builtin.hash |}.
#[global] Instance Hash_Bool : Hash bool := {| hash := Builtin.hash |}.
