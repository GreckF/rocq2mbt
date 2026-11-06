// Extracted from Rocq by rocq2mbt (MoonBit extraction).

/// Unsafe coercion used where Rocq terms are not ML-typable.
fn[A, B] rocq_magic(x : A) -> B = "%identity"

/// Placeholder for types that cannot be expressed in MoonBit.
pub(all) struct RocqAny {}

pub(all) enum Nat {
  O
  S(Nat)
}

pub fn add(n : Nat, m : Nat) -> Nat {
  match n {
    Nat::O => m
    Nat::S(p) => Nat::S(add(p, m))
  }
}

pub type Nary = RocqAny

pub fn sum_n(n : Nat, acc : Nat) -> Nary {
  match n {
    Nat::O => rocq_magic(acc)
    Nat::S(p) => rocq_magic(fn(x) { sum_n(p, add(acc, x)) })
  }
}

pub let use_sum : Nat = rocq_magic(fn(x1) { fn(x2) { sum_n(x1, x2) } })(Nat::S(Nat::S(Nat::O)))(Nat::O)(Nat::S(Nat::S(Nat::S(Nat::O))))(Nat::S(Nat::S(Nat::S(Nat::S(Nat::O)))))
