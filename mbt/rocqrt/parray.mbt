// Rocq primitive persistent arrays (Corelib.Array.PrimArray).
//
// Baker-style diff arrays, as in rocq/kernel/parray.ml: the newest version
// owns the mutable buffer, older versions are chains of `Updated` diffs.
// Accessing an old version "reroots" the buffer to it.  Linear use is O(1).

///|
pub struct PArray[A] {
  priv mut node : Node[A]
}

///|
priv enum Node[A] {
  Flat(Array[A], A)
  Updated(Int, A, PArray[A])
}

///|
pub let max_length : UInt64 = 4194303UL

///|
fn trunc_size(n : UInt64) -> Int {
  if n < max_length {
    n.to_int()
  } else {
    max_length.to_int()
  }
}

///|
/// Make `p` the version owning the buffer (iteratively, no deep recursion).
fn[A] reroot(p : PArray[A]) -> Array[A] {
  let path : Array[PArray[A]] = []
  let mut cur = p
  while true {
    match cur.node {
      Flat(_, _) => break
      Updated(_, _, next) => {
        path.push(cur)
        cur = next
      }
    }
  }
  // cur is the root; walk back towards p, inverting each diff
  for k = path.length() - 1; k >= 0; k = k - 1 {
    let t = path[k]
    match t.node {
      Updated(i, v, parent) =>
        match parent.node {
          Flat(a, def) => {
            let old = a[i]
            a[i] = v
            t.node = Flat(a, def)
            parent.node = Updated(i, old, t)
          }
          Updated(_, _, _) => abort("PArray: broken reroot")
        }
      Flat(_, _) => abort("PArray: broken reroot")
    }
  }
  match p.node {
    Flat(a, _) => a
    Updated(_, _, _) => abort("PArray: broken reroot")
  }
}

///|
fn[A] root_default(p : PArray[A]) -> A {
  ignore(reroot(p))
  match p.node {
    Flat(_, d) => d
    Updated(_, _, _) => abort("PArray: broken reroot")
  }
}

///|
pub fn[A] PArray::make(n : UInt64, def : A) -> PArray[A] {
  { node: Flat(Array::make(trunc_size(n), def), def) }
}

///|
/// Literal arrays produced by extraction.
pub fn[A] PArray::of_array(a : Array[A], def : A) -> PArray[A] {
  { node: Flat(a.copy(), def) }
}

///|
pub fn[A] PArray::get(p : PArray[A], n : UInt64) -> A {
  let a = reroot(p)
  if n < a.length().to_uint64() {
    a[n.to_int()]
  } else {
    root_default(p)
  }
}

///|
pub fn[A] PArray::set(p : PArray[A], n : UInt64, e : A) -> PArray[A] {
  let a = reroot(p)
  if n < a.length().to_uint64() {
    let i = n.to_int()
    let old = a[i]
    a[i] = e
    let t = { node: p.node }
    p.node = Updated(i, old, t)
    t
  } else {
    p
  }
}

///|
pub fn[A] PArray::default(p : PArray[A]) -> A {
  root_default(p)
}

///|
pub fn[A] PArray::length(p : PArray[A]) -> UInt64 {
  reroot(p).length().to_uint64()
}

///|
pub fn[A] PArray::copy(p : PArray[A]) -> PArray[A] {
  let a = reroot(p)
  { node: Flat(a.copy(), root_default(p)) }
}

///|
/// Snapshot of the contents, for interoperability.
pub fn[A] PArray::to_array(p : PArray[A]) -> Array[A] {
  reroot(p).copy()
}
