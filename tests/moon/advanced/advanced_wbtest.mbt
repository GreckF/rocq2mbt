// Runtime tests for the code extracted from tests/Advanced.v.

test "custom nat = Int" {
  assert_eq(fact(5), 120)
  assert_eq(fib(10), 55)
  assert_eq(max3(3, 9, 4), 9)
  assert_eq(max3(3, 2, 1), 3)
}

test "mutual inductives" {
  assert_eq(eval(example_tm), 6)
}

test "axioms realized by Extract Constant, modules" {
  assert_eq(ask(5), 11)
  assert_eq(both, 15)
}

test "partial application evaluates its argument once" {
  let f = partial(3)
  assert_eq(f(10), 17)
  assert_eq(f(0), 7)
}

test "records of functions" {
  assert_eq(total, 6)
}

test "strings" {
  assert_eq(greeting, "hello \"rocq\" été")
}

test "match on a match" {
  assert_eq(nested_match(true, true), 1)
  assert_eq(nested_match(true, false), 0)
  assert_eq(nested_match(false, false), 1)
}
