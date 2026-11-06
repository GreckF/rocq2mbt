// A small MoonBit library exercising the mbti2rocq translation.
// tests/run.sh runs `moon info` on it and translates the resulting
// pkg.generated.mbti to tests/gen/Mlib.v.

///|
pub(all) enum Shape {
  Circle(Double)
  Rect(w~ : Double, h~ : Double)
  Dot
}

///|
pub fn area(s : Shape) -> Double {
  match s {
    Circle(r) => 3.0 * r * r
    Rect(w~, h~) => w * h
    Dot => 0.0
  }
}

///|
pub(all) struct Point {
  x : Int
  y : Int
}

///|
pub fn Point::norm1(self : Point) -> Int {
  self.x.abs() + self.y.abs()
}

///|
pub fn Point::scale(self : Point, k~ : Int) -> Point {
  { x: self.x * k, y: self.y * k }
}

///|
pub let origin : Point = { x: 0, y: 0 }

///|
pub const MAX : Int = 100

///|
/// Abstract type with private state.
pub struct Counter {
  priv start : Int
}

///|
pub fn Counter::new(start : Int) -> Counter {
  { start, }
}

///|
pub fn Counter::value(self : Counter) -> Int {
  self.start
}

///|
pub(all) enum Tree[A] {
  Leaf
  Node(Tree[A], A, Tree[A])
}

///|
pub fn[A : Compare] insert(t : Tree[A], x : A) -> Tree[A] {
  match t {
    Leaf => Node(Leaf, x, Leaf)
    Node(l, y, r) => if x < y { Node(insert(l, x), y, r) } else { Node(l, y, insert(r, x)) }
  }
}

///|
/// Multi-parameter callback: curried on the Rocq side.
pub fn[A, B] fold_tree(t : Tree[A], init : B, f : (B, A) -> B) -> B {
  match t {
    Leaf => init
    Node(l, x, r) => fold_tree(r, f(fold_tree(l, init, f), x), f)
  }
}

///|
/// Returns a multi-parameter function.
pub fn make_adder(n : Int) -> (Int, Int) -> Int {
  fn(a, b) { a + b + n }
}

///|
pub suberror ParseErr {
  NotADigit(String)
  EmptyInput
}

///|
pub fn parse_digit(s : String) -> Int raise ParseErr {
  if s.length() == 0 {
    raise EmptyInput
  }
  let c = s.get_char(0).unwrap()
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else {
    raise NotADigit(s)
  }
}

///|
pub(open) trait Pretty {
  pretty(Self) -> String
}

///|
pub impl Pretty for Int with pretty(self) {
  "#" + self.to_string()
}

///|
pub impl Pretty for Point with pretty(self) {
  "(" + self.x.to_string() + ", " + self.y.to_string() + ")"
}

///|
pub fn[A : Pretty] pretty_all(xs : Array[A]) -> String {
  xs.map(fn(x) { x.pretty() }).join(" ")
}

///|
pub fn with_label(x : Int, label~ : String, sep? : String = ": ") -> String {
  label + sep + x.to_string()
}
