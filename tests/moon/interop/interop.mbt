// Extracted from Rocq by rocq2mbt (MoonBit extraction).

pub(all) enum List[A] {
  Nil
  Cons(A, List[A])
}

pub type Array0[A] = Array[A]

pub type Compare0[A] = (A) -> (A) -> Int
// singleton inductive, whose constructor was Build_Compare

pub let compare_Int : Compare0[Int] = fn(x1) { fn(x2) { x1.compare(x2) } }

pub fn point_x(p : @mlib.Point) -> Int {
  (fn(rocq_k, rocq_s : @mlib.Point) { rocq_k(rocq_s.x, rocq_s.y) })(fn(point_x0, _) { point_x0 }, p)
}

pub fn point_y(p : @mlib.Point) -> Int {
  (fn(rocq_k, rocq_s : @mlib.Point) { rocq_k(rocq_s.x, rocq_s.y) })(fn(_, point_y0) { point_y0 }, p)
}

pub type Pretty[A] = (A) -> String
// singleton inductive, whose constructor was Build_Pretty

pub let pretty_Point : Pretty[@mlib.Point] = fn(x1) { @mlib.Pretty::pretty(x1) }

pub let pretty_Int : Pretty[Int] = fn(x1) { @mlib.Pretty::pretty(x1) }

pub let i : (UInt64) -> Int = fn(x1) { @rocqrt.u63_to_int(x1) }

pub let shapes : List[@mlib.Shape] = List::Cons(@mlib.Shape::Circle(i(1UL).to_double()), List::Cons(@mlib.Shape::Rect(w=i(2UL).to_double(), h=i(3UL).to_double()), List::Cons(@mlib.Shape::Dot, List::Nil)))

pub fn total_area(l : List[@mlib.Shape]) -> Double {
  match l {
    List::Nil => i(0UL).to_double()
    List::Cons(s, t) => @rocqrt.f64_add(@mlib.area(s), total_area(t))
  }
}

pub fn kind(s : @mlib.Shape) -> Int {
  match s {
    @mlib.Shape::Circle(_) => i(0UL)
    @mlib.Shape::Rect(w=_, h=_) => i(1UL)
    @mlib.Shape::Dot => i(2UL)
  }
}

pub fn rect_width(s : @mlib.Shape) -> Option[Double] {
  match s {
    @mlib.Shape::Rect(w=w, h=_) => Some(w)
    _ => None
  }
}

pub fn swap(p : @mlib.Point) -> @mlib.Point {
  @mlib.Point::{ x: point_y(p), y: point_x(p) }
}

pub let far : @mlib.Point = @mlib.Point::scale(swap(@mlib.Point::{ x: i(1UL), y: (-i(2UL)) }), k=i(3UL))

pub let far_norm : Int = @mlib.Point::norm1(far)

pub let origin_norm : Int = @mlib.Point::norm1(@mlib.origin)

pub let counter_value : Int = @mlib.Counter::value(@mlib.Counter::new(@mlib.MAX))

#warnings("-unused_trait_bound")
pub fn[A : Compare] build(h : Compare0[A], l : List[A], t : @mlib.Tree[A]) -> @mlib.Tree[A] {
  match l {
    List::Nil => t
    List::Cons(x, r) => build(h, r, @mlib.insert(t, x))
  }
}

pub let sorted_tree : @mlib.Tree[Int] = build(compare_Int, List::Cons(i(5UL), List::Cons(i(1UL), List::Cons(i(3UL), List::Nil))), @mlib.Tree::Leaf)

pub fn[A] rev_app(l : List[A], acc : List[A]) -> List[A] {
  match l {
    List::Nil => acc
    List::Cons(x, r) => rev_app(r, List::Cons(x, acc))
  }
}

pub fn[A] tree_to_list(t : @mlib.Tree[A]) -> List[A] {
  rev_app(@mlib.fold_tree(t, List::Nil, fn(rocq_p0_0, rocq_p0_1) { (fn(acc) { fn(x) { List::Cons(x, acc) } })(rocq_p0_0)(rocq_p0_1) }), List::Nil)
}

pub let sorted : List[Int] = tree_to_list(sorted_tree)

pub let tree_sum : Int = {
  let a2 = i(0UL)
  let a3 = fn(x1) { fn(x2) { (x1 + x2) } }
  @mlib.fold_tree(sorted_tree, a2, fn(rocq_p0_0, rocq_p0_1) { a3(rocq_p0_0)(rocq_p0_1) })
}

pub let add10 : (Int) -> (Int) -> Int = {
  let a1 = i(10UL)
  { let rocq_f0 = @mlib.make_adder(a1); fn(rocq_q0_0) { fn(rocq_q0_1) { rocq_f0(rocq_q0_0, rocq_q0_1) } } }
}

pub let added : Int = add10(i(1UL))(i(2UL))

pub fn digit_or_minus1(s : String) -> Int {
  match (try @mlib.parse_digit(s) catch { rocq_e => Result::Err(rocq_e) } noraise { rocq_v => Result::Ok(rocq_v) }) {
    Result::Ok(d) => d
    Result::Err(p) => match p {
      @mlib.ParseErr::NotADigit(_) => (-i(1UL))
      @mlib.ParseErr::EmptyInput => (-i(2UL))
    }
  }
}

#warnings("-unused_trait_bound")
pub fn[A : @mlib.Pretty, B : @mlib.Pretty] pretty_pair(h : Pretty[A], h0 : Pretty[B], a : A, b : B) -> String {
  (h(a) + (" " + h0(b)))
}

pub let pretty_test : String = pretty_pair(pretty_Int, pretty_Point, i(7UL), far)

pub let pretty_array : String = @mlib.pretty_all({ let rocq_c = Array::make(i(2UL), i(1UL)).copy(); rocq_c.push(i(2UL)); rocq_c })

pub let labelled : String = @mlib.with_label(i(42UL), label="answer")
