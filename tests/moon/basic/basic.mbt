// Extracted from Rocq by rocq2mbt (MoonBit extraction).

/// Memoized suspension, used for coinductive types.
pub struct RocqLazy[A] {
  mut value : A?
  mut thunk : (() -> A)?
}

fn[A] rocq_lazy(f : () -> A) -> RocqLazy[A] {
  { value: None, thunk: Some(f) }
}

fn[A] rocq_force(l : RocqLazy[A]) -> A {
  match l.value {
    Some(v) => v
    None => {
      let v = (l.thunk.unwrap())()
      l.value = Some(v)
      l.thunk = None
      v
    }
  }
}

pub(all) enum Nat {
  O
  S(Nat)
}

pub(all) enum List[A] {
  Nil
  Cons(A, List[A])
}

pub fn[A] app(l : List[A], m : List[A]) -> List[A] {
  match l {
    List::Nil => m
    List::Cons(a, l1) => List::Cons(a, app(l1, m))
  }
}

// Sig : singleton inductive, expanded at use sites

pub fn div2(n : Nat) -> Nat {
  match n {
    Nat::O => Nat::O
    Nat::S(n0) => match n0 {
      Nat::O => Nat::O
      Nat::S(n_) => Nat::S(div2(n_))
    }
  }
}

pub fn add(n : Nat, m : Nat) -> Nat {
  match n {
    Nat::O => m
    Nat::S(p) => Nat::S(add(p, m))
  }
}

pub fn mul(n : Nat, m : Nat) -> Nat {
  match n {
    Nat::O => Nat::O
    Nat::S(p) => add(m, mul(p, m))
  }
}

pub let inc : (Nat) -> Nat = fn(x1) { add(Nat::S(Nat::O), x1) }

pub fn double(n : Nat) -> Nat {
  add(n, n)
}

pub let adder : (Nat) -> (Nat) -> Nat = fn(x1) { fn(x2) { add(x1, x2) } }

pub fn eqb(n : Nat, m : Nat) -> Bool {
  match n {
    Nat::O => match m {
      Nat::O => true
      Nat::S(_) => false
    }
    Nat::S(n0) => match m {
      Nat::O => false
      Nat::S(m0) => eqb(n0, m0)
    }
  }
}

pub fn leb(n : Nat, m : Nat) -> Bool {
  match n {
    Nat::O => true
    Nat::S(n0) => match m {
      Nat::O => false
      Nat::S(m0) => leb(n0, m0)
    }
  }
}

pub fn even(n : Nat) -> Bool {
  match n {
    Nat::O => true
    Nat::S(n0) => odd(n0)
  }
}

pub fn odd(n : Nat) -> Bool {
  match n {
    Nat::O => false
    Nat::S(n0) => even(n0)
  }
}

pub fn sum_to(n : Nat) -> Nat {
  {
    letrec go = fn(k) {
      fn(acc) {
        match k {
          Nat::O => acc
          Nat::S(k_) => go(k_)(add(k, acc))
        }
      }
    }
    go(n)(Nat::O)
  }
}

pub fn lets(n : Nat) -> Nat {
  let x = add(n, n)
  let y = mul(x, x)
  add(x, y)
}

pub fn[A] length(l : List[A]) -> Nat {
  match l {
    List::Nil => Nat::O
    List::Cons(_, t) => Nat::S(length(t))
  }
}

pub fn[A, B] map(f : (A) -> B, l : List[A]) -> List[B] {
  match l {
    List::Nil => List::Nil
    List::Cons(x, t) => List::Cons(f(x), map(f, t))
  }
}

pub fn[A, B] fold_left(f : (A) -> (B) -> A, l : List[B], a : A) -> A {
  match l {
    List::Nil => a
    List::Cons(b, t) => fold_left(f, t, f(a)(b))
  }
}

pub fn[A] twice(f : (A) -> A, x : A) -> A {
  f(f(x))
}

pub fn[A, B, C] compose(g : (B) -> C, f : (A) -> B, x : A) -> C {
  g(f(x))
}

pub fn[A] empty() -> List[A] {
  List::Nil
}

pub fn[A] hd_opt(l : List[A]) -> Option[A] {
  match l {
    List::Nil => None
    List::Cons(x, _) => Some(x)
  }
}

pub fn seq(start : Nat, len : Nat) -> List[Nat] {
  match len {
    Nat::O => List::Nil
    Nat::S(l) => List::Cons(start, seq(Nat::S(start), l))
  }
}

pub fn sum_list(l : List[Nat]) -> Nat {
  fold_left(fn(x1) { fn(x2) { add(x1, x2) } }, l, Nat::O)
}

pub fn squares(n : Nat) -> List[Nat] {
  map(fn(x) { mul(x, x) }, seq(Nat::O, n))
}

pub let incs : (List[Nat]) -> List[Nat] = fn(x1) { map(inc, x1) }

pub(all) enum Tree[A] {
  Leaf
  Node(Tree[A], A, Tree[A])
}

pub fn insert(x : Nat, t : Tree[Nat]) -> Tree[Nat] {
  match t {
    Tree::Leaf => Tree::Node(Tree::Leaf, x, Tree::Leaf)
    Tree::Node(l, y, r) => match leb(x, y) {
      true => Tree::Node(insert(x, l), y, r)
      false => Tree::Node(l, y, insert(x, r))
    }
  }
}

pub fn[A] to_list(t : Tree[A]) -> List[A] {
  match t {
    Tree::Leaf => List::Nil
    Tree::Node(l, x, r) => app(to_list(l), List::Cons(x, to_list(r)))
  }
}

pub fn tree_sort(l : List[Nat]) -> List[Nat] {
  to_list(fold_left(fn(t) { fn(x) { insert(x, t) } }, l, Tree::Leaf))
}

pub(all) enum Point {
  Build_point(Nat, Nat)
}

pub fn swap(p : Point) -> Point {
  Point::Build_point(match p {
    Point::Build_point(_, py) => py
  }, match p {
    Point::Build_point(px, _) => px
  })
}

pub fn norm1(p : Point) -> Nat {
  add(match p {
    Point::Build_point(px, _) => px
  }, match p {
    Point::Build_point(_, py) => py
  })
}

pub fn pred_safe(n : Nat) -> Nat {
  match n {
    Nat::O => Nat::O
    Nat::S(p) => p
  }
}

pub let safe_three : Nat = pred_safe(Nat::S(Nat::S(Nat::S(Nat::S(Nat::O)))))

pub let div2_sig : (Nat) -> Nat = fn(x1) { div2(x1) }

pub let div0 : (Nat) -> Nat = div2_sig

pub fn is_zero(n : Nat) -> Bool {
  match n {
    Nat::O => true
    Nat::S(_) => false
  }
}

pub fn zero_or_one(n : Nat) -> Nat {
  match is_zero(n) {
    true => Nat::S(Nat::O)
    false => Nat::O
  }
}

pub(all) enum StreamCell[A] {
  SCons(A, Stream[A])
}
pub type Stream[A] = RocqLazy[StreamCell[A]]

pub fn nats_from(n : Nat) -> Stream[Nat] {
  rocq_lazy(fn() { StreamCell::SCons(n, nats_from(Nat::S(n))) })
}

pub fn[A] repeat(x : A) -> Stream[A] {
  rocq_lazy(fn() { StreamCell::SCons(x, repeat(x)) })
}

pub fn[A] take(n : Nat, s : Stream[A]) -> List[A] {
  match n {
    Nat::O => List::Nil
    Nat::S(n0) => match rocq_force(s) {
      StreamCell::SCons(x, s0) => List::Cons(x, take(n0, s0))
    }
  }
}

pub fn[A] nth_default(d : A, l : List[A], n : Nat) -> A {
  match l {
    List::Nil => d
    List::Cons(x, t) => match n {
      Nat::O => x
      Nat::S(n0) => nth_default(d, t, n0)
    }
  }
}
