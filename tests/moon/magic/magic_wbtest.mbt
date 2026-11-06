// Code using rocq_magic: only expected to work on some backends.

fn i(x : Nat) -> Int {
  match x {
    Nat::O => 0
    Nat::S(p) => 1 + i(p)
  }
}

test "dependent arity through rocq_magic" {
  assert_eq(i(use_sum), 7)
}
