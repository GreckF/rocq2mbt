// Extracted from Rocq by rocq2mbt (MoonBit extraction).

pub fn negb(b : Bool) -> Bool {
  match b {
    true => false
    false => true
  }
}

pub(all) enum List[A] {
  Nil
  Cons(A, List[A])
}

pub type String0 = String

pub fn fact(n : Int) -> Int {
  (fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })(fn() { (fn(n) { n + 1 })(0) }, fn(p) { (fn(a) { fn(b) { a * b } })(n)(fact(p)) }, n)
}

pub fn fib(n : Int) -> Int {
  (fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })(fn() { 0 }, fn(p) {
    (fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })(fn() { (fn(n) { n + 1 })(0) }, fn(q) { (fn(a) { fn(b) { a + b } })(fib(p))(fib(q)) }, p)
  }, n)
}

pub fn max3(a : Int, b : Int, c : Int) -> Int {
  let m = match (fn(a) { fn(b) { a <= b } })(a)(b) {
    true => b
    false => a
  }
  match (fn(a) { fn(b) { a <= b } })(m)(c) {
    true => c
    false => m
  }
}

pub(all) enum Tm {
  Num(Int)
  Plus(Tm, Tm)
  Seq(Tms)
}

pub(all) enum Tms {
  TNil
  TCons(Tm, Tms)
}

pub fn eval(t : Tm) -> Int {
  match t {
    Tm::Num(n) => n
    Tm::Plus(a, b) => (fn(a) { fn(b) { a + b } })(eval(a))(eval(b))
    Tm::Seq(ts) => eval_all(ts)
  }
}

pub fn eval_all(ts : Tms) -> Int {
  match ts {
    Tms::TNil => 0
    Tms::TCons(t, r) => (fn(a) { fn(b) { a + b } })(eval(t))(eval_all(r))
  }
}

pub let example_tm : Tm = Tm::Seq(Tms::TCons(Tm::Num((fn(n) { n + 1 })(0)), Tms::TCons(Tm::Plus(Tm::Num((fn(n) { n + 1 })((fn(n) { n + 1 })(0))), Tm::Num((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })(0))))), Tms::TNil)))

pub(all) enum Void {}

pub fn[A] from_void(_ : Void) -> A {
  abort("absurd case")
}

pub let oracle : (Int) -> Int = (fn(n) { n * 2 })

pub fn ask(n : Int) -> Int {
  (fn(a) { fn(b) { a + b } })(oracle(n))((fn(n) { n + 1 })(0))
}

pub let k : Int = (fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })(0)))))))

pub let k0 : Int = (fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })(0))))))))

pub let both : Int = (fn(a) { fn(b) { a + b } })(k)(k0)

pub let greeting : String0 = "hello \"rocq\" été"

pub fn add3(a : Int, b : Int, c : Int) -> Int {
  (fn(a) { fn(b) { a + b } })((fn(a) { fn(b) { a + b } })(a)(b))(c)
}

pub fn partial(n : Int) -> (Int) -> Int {
  { let a1 = fact(n); fn(x1) { add3(a1, (fn(n) { n + 1 })(0), x1) } }
}

pub(all) enum Monoid[A] {
  Build_monoid((A) -> (A) -> A, A)
}

pub let nat_add_monoid : Monoid[Int] = Monoid::Build_monoid((fn(a) { fn(b) { a + b } }), 0)

pub fn[A] mconcat(m : Monoid[A], l : List[A]) -> A {
  match l {
    List::Nil => match m {
      Monoid::Build_monoid(_, unit) => unit
    }
    List::Cons(x, t) => match m {
      Monoid::Build_monoid(op, _) => op(x)(mconcat(m, t))
    }
  }
}

pub let total : Int = mconcat(nat_add_monoid, List::Cons((fn(n) { n + 1 })(0), List::Cons((fn(n) { n + 1 })((fn(n) { n + 1 })(0)), List::Cons((fn(n) { n + 1 })((fn(n) { n + 1 })((fn(n) { n + 1 })(0))), List::Nil))))

pub fn nested_match(b : Bool, c : Bool) -> Int {
  match (match b {
    true => c
    false => negb(c)
  }) {
    true => (fn(n) { n + 1 })(0)
    false => 0
  }
}
