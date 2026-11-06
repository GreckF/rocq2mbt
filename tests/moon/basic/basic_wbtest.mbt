// Runtime tests for the code extracted from tests/Basic.v.

fn n(i : Int) -> Nat {
  if i <= 0 { Nat::O } else { Nat::S(n(i - 1)) }
}

fn i(x : Nat) -> Int {
  match x {
    Nat::O => 0
    Nat::S(p) => 1 + i(p)
  }
}

fn[A] arr(l : List[A]) -> Array[A] {
  let out = []
  fn go(l : List[A]) {
    match l {
      List::Nil => ()
      List::Cons(x, t) => {
        out.push(x)
        go(t)
      }
    }
  }
  go(l)
  out
}

fn ints(l : List[Nat]) -> Array[Int] {
  arr(l).map(i)
}

fn lst(xs : Array[Int]) -> List[Nat] {
  let mut l = List::Nil
  for k = xs.length() - 1; k >= 0; k = k - 1 {
    l = List::Cons(n(xs[k]), l)
  }
  l
}

test "arithmetic" {
  assert_eq(i(add(n(2), n(3))), 5)
  assert_eq(i(mul(n(4), n(3))), 12)
  assert_eq(i(inc(n(9))), 10)
  assert_eq(i(double(n(7))), 14)
  assert_eq(i(adder(n(1))(n(2))), 3)
  assert_eq(eqb(n(3), n(3)), true)
  assert_eq(eqb(n(3), n(4)), false)
  assert_eq(even(n(10)), true)
  assert_eq(odd(n(10)), false)
  assert_eq(i(sum_to(n(4))), 10)
  assert_eq(i(lets(n(1))), 6)
  assert_eq(i(safe_three), 3)
  assert_eq(i(div0(n(9))), 4)
  assert_eq(i(zero_or_one(n(0))), 1)
  assert_eq(i(zero_or_one(n(5))), 0)
}

test "lists and higher-order functions" {
  assert_eq(ints(seq(n(2), n(4))), [2, 3, 4, 5])
  assert_eq(ints(squares(n(4))), [0, 1, 4, 9])
  assert_eq(ints(incs(lst([1, 2, 3]))), [2, 3, 4])
  assert_eq(i(sum_list(lst([1, 2, 3, 4]))), 10)
  assert_eq(i(length(lst([5, 5, 5]))), 3)
  assert_eq(i(length((empty() : List[Int]))), 0)
  assert_eq(i(twice(inc, n(0))), 2)
  assert_eq(i(compose(inc, double, n(3))), 7)
  assert_eq(hd_opt(lst([7, 8])).map(i), Some(7))
  assert_eq(hd_opt((List::Nil : List[Nat])).map(i), None)
  assert_eq(i(nth_default(n(42), lst([1, 2, 3]), n(1))), 2)
  assert_eq(i(nth_default(n(42), lst([1, 2, 3]), n(5))), 42)
  assert_eq(arr(map(fn(x) { i(x) * 10 }, lst([1, 2]))), [10, 20])
}

test "user inductives and records" {
  assert_eq(ints(tree_sort(lst([5, 1, 4, 2, 3]))), [1, 2, 3, 4, 5])
  let p = swap(Point::Build_point(n(1), n(2)))
  match p {
    Point::Build_point(x, y) => {
      assert_eq(i(x), 2)
      assert_eq(i(y), 1)
    }
  }
  assert_eq(i(norm1(p)), 3)
}

test "coinductive streams" {
  assert_eq(ints(take(n(5), nats_from(n(3)))), [3, 4, 5, 6, 7])
  assert_eq(arr(take(n(3), repeat("x"))), ["x", "x", "x"])
}
