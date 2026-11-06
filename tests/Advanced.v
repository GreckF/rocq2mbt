From RocqMbt Require Import ExtrMoonBitBasic.

(* nat as MoonBit Int, via custom constants and a custom match *)
Extract Inductive nat => "Int" [ "0" "(fn(n) { n + 1 })" ]
  "(fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })".
Extract Inlined Constant Nat.add => "(fn(a) { fn(b) { a + b } })".
Extract Inlined Constant Nat.mul => "(fn(a) { fn(b) { a * b } })".
Extract Inlined Constant Nat.leb => "(fn(a) { fn(b) { a <= b } })".

Fixpoint fact (n : nat) : nat := match n with O => 1 | S p => n * fact p end.
Fixpoint fib (n : nat) : nat :=
  match n with O => 0 | S p => match p with O => 1 | S q => fib p + fib q end end.
Definition max3 (a b c : nat) : nat :=
  let m := if Nat.leb a b then b else a in if Nat.leb m c then c else m.

(* mutual inductive types *)
Inductive tm : Type :=
| Num : nat -> tm
| Plus : tm -> tm -> tm
| Seq : tms -> tm
with tms : Type :=
| TNil : tms
| TCons : tm -> tms -> tms.

Fixpoint eval (t : tm) : nat :=
  match t with
  | Num n => n
  | Plus a b => eval a + eval b
  | Seq ts => eval_all ts
  end
with eval_all (ts : tms) : nat :=
  match ts with TNil => 0 | TCons t r => eval t + eval_all r end.

Definition example_tm : tm := Seq (TCons (Num 1) (TCons (Plus (Num 2) (Num 3)) TNil)).

(* empty type, absurd elimination, axioms *)
Inductive void : Set := .
Definition from_void {A : Type} (v : void) : A := match v with end.
Parameter oracle : nat -> nat.
Axiom oracle_spec : forall n, oracle n = n.
Definition ask (n : nat) : nat := oracle n + 1.
Extract Constant oracle => "(fn(n) { n * 2 })".

(* modules are flattened *)
Module M.
  Definition k : nat := 7.
  Module N.
    Definition k : nat := 8.
  End N.
End M.
Definition both : nat := M.k + M.N.k.

(* primitive strings *)
From Corelib Require Import PrimString.
Extract Constant PrimString.string => "String".
Definition greeting : string := "hello ""rocq"" été"%pstring.

(* partial application with a non-trivial argument (evaluated once) *)
Definition add3 (a b c : nat) : nat := a + b + c.
Definition partial (n : nat) : nat -> nat := add3 (fact n) 1.

(* records of functions, higher-rank via records *)
Record monoid (A : Type) := { op : A -> A -> A; unit : A }.
Arguments op {A}. Arguments unit {A}.
Definition nat_add_monoid : monoid nat := {| op := Nat.add; unit := 0 |}.
Fixpoint mconcat {A} (m : monoid A) (l : list A) : A :=
  match l with nil => unit m | cons x t => op m x (mconcat m t) end.
Definition total : nat := mconcat nat_add_monoid (cons 1 (cons 2 (cons 3 nil))).

(* a match whose scrutinee is itself a match (MoonBit needs parentheses) *)
Definition nested_match (b c : bool) : nat :=
  match (match b with true => c | false => negb c end) with true => 1 | false => 0 end.

Extraction "advanced/advanced.mbt"
  fact fib max3 eval example_tm from_void ask both partial total greeting
  nested_match.
