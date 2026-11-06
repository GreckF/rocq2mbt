From RocqMbt Require Import ExtrMoonBitBasic.

(* naturals, recursion, partial application *)
Fixpoint add (n m : nat) : nat := match n with O => m | S p => S (add p m) end.
Fixpoint mul (n m : nat) : nat := match n with O => O | S p => add m (mul p m) end.
Definition inc : nat -> nat := add 1.
Definition double (n : nat) : nat := add n n.
Definition adder : nat -> nat -> nat := add.

Fixpoint eqb (n m : nat) : bool :=
  match n, m with
  | O, O => true
  | S n, S m => eqb n m
  | _, _ => false
  end.

Fixpoint leb (n m : nat) : bool :=
  match n with O => true | S n => match m with O => false | S m => leb n m end end.

(* mutual recursion *)
Fixpoint even (n : nat) : bool := match n with O => true | S n => odd n end
with odd (n : nat) : bool := match n with O => false | S n => even n end.

(* local fixpoint and let-ins *)
Definition sum_to (n : nat) : nat :=
  (fix go (k acc : nat) := match k with O => acc | S k' => go k' (add k acc) end) n O.

Definition lets (n : nat) : nat :=
  let x := add n n in
  let y := mul x x in
  add x y.

(* polymorphism and higher-order functions *)
Fixpoint length {A} (l : list A) : nat :=
  match l with nil => O | cons _ t => S (length t) end.

Fixpoint map {A B} (f : A -> B) (l : list A) : list B :=
  match l with nil => nil | cons x t => cons (f x) (map f t) end.

Fixpoint fold_left {A B} (f : A -> B -> A) (l : list B) (a : A) : A :=
  match l with nil => a | cons b t => fold_left f t (f a b) end.

Definition twice {A} (f : A -> A) (x : A) : A := f (f x).
Definition compose {A B C} (g : B -> C) (f : A -> B) : A -> C := fun x => g (f x).
Definition empty {A} : list A := nil.
Definition hd_opt {A} (l : list A) : option A :=
  match l with nil => None | cons x _ => Some x end.

Fixpoint seq (start len : nat) : list nat :=
  match len with O => nil | S l => cons start (seq (S start) l) end.

Definition sum_list (l : list nat) : nat := fold_left add l O.
Definition squares (n : nat) : list nat := map (fun x => mul x x) (seq O n).
Definition incs : list nat -> list nat := map inc.

(* user inductive with parameters *)
Inductive tree (A : Type) :=
| Leaf : tree A
| Node : tree A -> A -> tree A -> tree A.
Arguments Leaf {A}.
Arguments Node {A}.

Fixpoint insert (x : nat) (t : tree nat) : tree nat :=
  match t with
  | Leaf => Node Leaf x Leaf
  | Node l y r => if leb x y then Node (insert x l) y r else Node l y (insert x r)
  end.

Fixpoint to_list {A} (t : tree A) : list A :=
  match t with
  | Leaf => nil
  | Node l x r => app (to_list l) (cons x (to_list r))
  end.

Definition tree_sort (l : list nat) : list nat :=
  to_list (fold_left (fun t x => insert x t) l Leaf).

(* records *)
Record point := { px : nat; py : nat }.
Definition swap (p : point) : point := {| px := py p; py := px p |}.
Definition norm1 (p : point) : nat := add (px p) (py p).

(* logical arguments and subset types *)
Definition pred_safe (n : nat) (H : n <> O) : nat :=
  match n with O => O | S p => p end.
Definition safe_three : nat := pred_safe 4 (fun H => match H with eq_refl => I end).

Definition div2_sig (n : nat) : {m : nat | m = m} := exist _ (Nat.div2 n) eq_refl.
Definition div2 (n : nat) : nat := proj1_sig (div2_sig n).

Definition is_zero (n : nat) : {n = O} + {n <> O}.
Proof. destruct n; [left; reflexivity | right; discriminate]. Defined.
Definition zero_or_one (n : nat) : nat := if is_zero n then 1 else O.

(* coinductive streams *)
CoInductive stream (A : Type) := SCons : A -> stream A -> stream A.
Arguments SCons {A}.
CoFixpoint nats_from (n : nat) : stream nat := SCons n (nats_from (S n)).
CoFixpoint repeat {A} (x : A) : stream A := SCons x (repeat x).
Fixpoint take {A} (n : nat) (s : stream A) : list A :=
  match n with
  | O => nil
  | S n => match s with SCons x s => cons x (take n s) end
  end.

(* failing branch / axiom-free exceptions *)
Definition nth_default {A} (d : A) : list A -> nat -> A :=
  fix f l n := match l, n with
               | nil, _ => d
               | cons x _, O => x
               | cons _ t, S n => f t n
               end.

Extraction "basic/basic.mbt"
  add mul inc double adder eqb even odd sum_to lets
  length map fold_left twice compose empty hd_opt seq sum_list squares incs
  insert to_list tree_sort swap norm1 pred_safe safe_three div2 zero_or_one
  nats_from repeat take nth_default.
