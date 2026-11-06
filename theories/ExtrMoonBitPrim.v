(** Extraction of Rocq's primitive types to MoonBit:
    - [PrimInt63.int]    -> [UInt64] (values kept below 2^63),
    - [PrimFloat.float]  -> [Double],
    - [PrimArray.array]  -> [@rocqrt.PArray] (persistent diff arrays).
    Literals of these types ([42%uint63], [1.5%float], [[| 1; 2 | 0 |]])
    are printed natively by the plugin.

    The generated code needs the runtime package; in its [moon.pkg]:
      import { "GreckF/rocqrt" @rocqrt } *)

From RocqMbt Require Export ExtrMoonBitBasic.
From Corelib Require Import PrimInt63 CarryType PrimFloat FloatClass PrimArray PrimString.

(** Result types of primitive operations *)
Extract Inductive comparison => "@rocqrt.Comparison"
  [ "@rocqrt.Comparison::Eq" "@rocqrt.Comparison::Lt" "@rocqrt.Comparison::Gt" ].
Extract Inductive carry => "@rocqrt.Carry" [ "@rocqrt.Carry::C0" "@rocqrt.Carry::C1" ].
Extract Inductive float_comparison => "@rocqrt.FloatComparison"
  [ "@rocqrt.FloatComparison::FEq" "@rocqrt.FloatComparison::FLt"
    "@rocqrt.FloatComparison::FGt" "@rocqrt.FloatComparison::FNotComparable" ].
Extract Inductive float_class => "@rocqrt.FloatClass"
  [ "@rocqrt.FloatClass::PNormal" "@rocqrt.FloatClass::NNormal"
    "@rocqrt.FloatClass::PSubn" "@rocqrt.FloatClass::NSubn"
    "@rocqrt.FloatClass::PZero" "@rocqrt.FloatClass::NZero"
    "@rocqrt.FloatClass::PInf" "@rocqrt.FloatClass::NInf"
    "@rocqrt.FloatClass::NaN" ].

(** 63-bit integers *)
Extract Inlined Constant PrimInt63.int => "UInt64".
Extract MoonBit Function PrimInt63.lsl => "@rocqrt.u63_lsl($0, $1)".
Extract MoonBit Function PrimInt63.lsr => "@rocqrt.u63_lsr($0, $1)".
Extract MoonBit Function PrimInt63.asr => "@rocqrt.u63_asr($0, $1)".
Extract MoonBit Function PrimInt63.land => "@rocqrt.u63_land($0, $1)".
Extract MoonBit Function PrimInt63.lor => "@rocqrt.u63_lor($0, $1)".
Extract MoonBit Function PrimInt63.lxor => "@rocqrt.u63_lxor($0, $1)".
Extract MoonBit Function PrimInt63.add => "@rocqrt.u63_add($0, $1)".
Extract MoonBit Function PrimInt63.sub => "@rocqrt.u63_sub($0, $1)".
Extract MoonBit Function PrimInt63.mul => "@rocqrt.u63_mul($0, $1)".
Extract MoonBit Function PrimInt63.mulc => "@rocqrt.u63_mulc($0, $1)".
Extract MoonBit Function PrimInt63.div => "@rocqrt.u63_div($0, $1)".
Extract MoonBit Function PrimInt63.mod => "@rocqrt.u63_mod($0, $1)".
Extract MoonBit Function PrimInt63.divs => "@rocqrt.u63_divs($0, $1)".
Extract MoonBit Function PrimInt63.mods => "@rocqrt.u63_mods($0, $1)".
Extract MoonBit Function PrimInt63.eqb => "@rocqrt.u63_eqb($0, $1)".
Extract MoonBit Function PrimInt63.ltb => "@rocqrt.u63_ltb($0, $1)".
Extract MoonBit Function PrimInt63.leb => "@rocqrt.u63_leb($0, $1)".
Extract MoonBit Function PrimInt63.ltsb => "@rocqrt.u63_ltsb($0, $1)".
Extract MoonBit Function PrimInt63.lesb => "@rocqrt.u63_lesb($0, $1)".
Extract MoonBit Function PrimInt63.addc => "@rocqrt.u63_addc($0, $1)".
Extract MoonBit Function PrimInt63.addcarryc => "@rocqrt.u63_addcarryc($0, $1)".
Extract MoonBit Function PrimInt63.subc => "@rocqrt.u63_subc($0, $1)".
Extract MoonBit Function PrimInt63.subcarryc => "@rocqrt.u63_subcarryc($0, $1)".
Extract MoonBit Function PrimInt63.diveucl => "@rocqrt.u63_diveucl($0, $1)".
Extract MoonBit Function PrimInt63.diveucl_21 => "@rocqrt.u63_diveucl_21($0, $1, $2)".
Extract MoonBit Function PrimInt63.addmuldiv => "@rocqrt.u63_addmuldiv($0, $1, $2)".
Extract MoonBit Function PrimInt63.compare => "@rocqrt.u63_compare($0, $1)".
Extract MoonBit Function PrimInt63.compares => "@rocqrt.u63_compares($0, $1)".
Extract MoonBit Function PrimInt63.head0 => "@rocqrt.u63_head0($0)".
Extract MoonBit Function PrimInt63.tail0 => "@rocqrt.u63_tail0($0)".

(** Floats *)
Extract Inlined Constant PrimFloat.float => "Double".
Extract MoonBit Function PrimFloat.classify => "@rocqrt.f64_classify($0)".
Extract MoonBit Function PrimFloat.abs => "@rocqrt.f64_abs($0)".
Extract MoonBit Function PrimFloat.sqrt => "@rocqrt.f64_sqrt($0)".
Extract MoonBit Function PrimFloat.opp => "@rocqrt.f64_opp($0)".
Extract MoonBit Function PrimFloat.eqb => "@rocqrt.f64_eqb($0, $1)".
Extract MoonBit Function PrimFloat.ltb => "@rocqrt.f64_ltb($0, $1)".
Extract MoonBit Function PrimFloat.leb => "@rocqrt.f64_leb($0, $1)".
Extract MoonBit Function PrimFloat.compare => "@rocqrt.f64_compare($0, $1)".
Extract MoonBit Function PrimFloat.Leibniz.eqb => "@rocqrt.f64_equal($0, $1)".
Extract MoonBit Function PrimFloat.mul => "@rocqrt.f64_mul($0, $1)".
Extract MoonBit Function PrimFloat.add => "@rocqrt.f64_add($0, $1)".
Extract MoonBit Function PrimFloat.sub => "@rocqrt.f64_sub($0, $1)".
Extract MoonBit Function PrimFloat.div => "@rocqrt.f64_div($0, $1)".
Extract MoonBit Function PrimFloat.of_uint63 => "@rocqrt.f64_of_uint63($0)".
Extract MoonBit Function PrimFloat.normfr_mantissa => "@rocqrt.f64_normfr_mantissa($0)".
Extract MoonBit Function PrimFloat.frshiftexp => "@rocqrt.f64_frshiftexp($0)".
Extract MoonBit Function PrimFloat.ldshiftexp => "@rocqrt.f64_ldshiftexp($0, $1)".
Extract MoonBit Function PrimFloat.next_up => "@rocqrt.f64_next_up($0)".
Extract MoonBit Function PrimFloat.next_down => "@rocqrt.f64_next_down($0)".

(** Primitive strings: literals become MoonBit string literals.  Rocq strings
    are byte strings; only the type is mapped, use the Prelude's [String]
    operations on MoonBit strings. *)
Extract Inlined Constant PrimString.string => "String".

(** Persistent arrays *)
Extract Constant PrimArray.array "A" => "@rocqrt.PArray[A]".
Extract MoonBit Function PrimArray.make => "@rocqrt.PArray::make($0, $1)".
Extract MoonBit Function PrimArray.get => "@rocqrt.PArray::get($0, $1)".
Extract MoonBit Function PrimArray.default => "@rocqrt.PArray::default($0)".
Extract MoonBit Function PrimArray.set => "@rocqrt.PArray::set($0, $1, $2)".
Extract MoonBit Function PrimArray.length => "@rocqrt.PArray::length($0)".
Extract MoonBit Function PrimArray.copy => "@rocqrt.PArray::copy($0)".
Extract MoonBit Function PrimArray.max_length => "@rocqrt.max_length".
