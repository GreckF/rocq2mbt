From RocqMbt Require Import ExtrMoonBitBasic.

(* A dependently typed arity: not ML-typable, needs rocq_magic. *)
Fixpoint nary (n : nat) : Type := match n with O => nat | S p => nat -> nary p end.
Fixpoint sum_n (n : nat) (acc : nat) : nary n :=
  match n return nary n with O => acc | S p => fun x => sum_n p (Nat.add acc x) end.
Definition use_sum : nat := sum_n 2 0 3 4.

Extraction "magic/magic.mbt" use_sum.
