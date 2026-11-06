// Translation of a parsed .mbti interface to a Rocq file of axioms whose
// extraction (with the rocq2mbt plugin) calls back the original MoonBit code.
//
//   MoonBit                          Rocq
//   pub fn f(A, B) -> C              Axiom f : A -> B -> C.
//                                    Extract MoonBit Function f => "@pkg.f($0, $1)".
//   fn[A : Eq] g(..)                 Axiom g : forall {A : Type} `{Eq A}, ..
//   fn h(..) -> T raise E            Axiom h : .. -> Result T E.
//   pub(all) enum / suberror         Inductive + Extract Inductive
//   pub(all) struct                  Record + Extract Inductive (custom match)
//   abstract types                   Axiom T : Type -> Type.
//   trait T { m(Self) -> X }         Class T (Self : Type) := { m : Self -> X }.
//   impl T for X                     Instance T_X : T X.
//
// Multi-parameter MoonBit function types are curried in Rocq; the call
// templates convert callbacks and results in both directions.

///|
pub suberror Unsupported {
  Unsupported(String)
} derive(Debug)

///|
let rocq_reserved : Array[String] = [
  "as", "at", "cofix", "else", "end", "exists", "exists2", "fix", "for", "forall",
  "fun", "if", "IF", "in", "let", "match", "mod", "return", "Set", "SProp", "Prop",
  "then", "Type", "using", "where", "with", "struct", "Definition", "Theorem",
  "Lemma", "Axiom", "Inductive", "Record", "Class", "Instance", "Fixpoint",
  "Module", "Section", "End", "Import", "Export", "Require", "From", "Proof", "Qed",
  "Defined", "Admitted", "Variable", "Parameter", "Hypothesis", "Notation",
  "Arguments", "Check", "Print", "Eval", "Compute", "Abbreviation", "Local",
  "Global", "Let", "Context", "Structure", "Variant", "CoInductive", "Coercion",
  "Existing", "Canonical", "Opaque", "Transparent", "Scheme", "Ltac", "Tactic",
  "Hint", "Open", "Close", "Scope", "Delimit", "Bind", "Unset", "Set", "Show",
  "Search", "About", "Extraction", "Extract", "nat", "bool", "unit", "option",
  "list", "prod", "sum", "true", "false", "tt", "Some", "None", "pair", "fst",
  "snd", "S", "O", "id", "not", "and", "or", "True", "False", "eq", "le", "lt",
]

///|
/// Names exported by RocqMbt.Prelude that generated names must not shadow.
let prelude_names : Array[String] = [
  "Result", "Ok", "Err", "Int", "Int64", "UInt", "UInt64", "Byte", "Char", "String",
  "Bytes", "Error", "Double", "Array", "Builtin", "Eq", "Compare", "Show", "Hash",
  "equal", "compare", "to_string", "hash",
]

///|
/// MoonBit builtin types and their Rocq counterparts (from RocqMbt.Prelude).
fn builtin_type(name : String) -> String? {
  match name {
    "Int" | "Int64" | "UInt" | "UInt64" | "Byte" | "Char" | "String" | "Bytes"
    | "Error" | "Double" => Some(name)
    // since moonc v0.10.x (2026-11), `moon info` prints `Int`/`UInt` by their
    // canonical names `Int32`/`UInt32`
    "Int32" => Some("Int")
    "UInt32" => Some("UInt")
    "Bool" => Some("bool")
    "Unit" => Some("unit")
    "Option" => Some("option")
    "Result" => Some("Result")
    "Array" => Some("Array")
    _ => None
  }
}

///|
/// Traits of the Prelude: Rocq class and the `Builtin.*` axioms of its methods.
fn prelude_trait(name : String) -> (String, Array[(String, String)])? {
  match name {
    "Eq" => Some(("Eq", [("equal", "Builtin.equal")]))
    "Compare" => Some(("Compare", [("compare", "Builtin.compare")]))
    "Show" => Some(("Show", [("to_string", "Builtin.to_string")]))
    "Hash" => Some(("Hash", [("hash", "Builtin.hash")]))
    _ => None
  }
}

///|
priv struct LocalTrait {
  rocq : String
  methods : Array[(String, String)] // Rocq field name, generic method axiom
}

///|
priv struct Gen {
  palias : String // "@pkg"
  types : Map[String, (String, Array[String], TypeKind)] // mbt name -> rocq name, params, final kind
  traits : Map[String, LocalTrait]
  foreign : Map[String, (String, Int)] // mbt type path -> rocq name, arity
  foreign_order : Array[String]
  used : Set[String]
  out_types : StringBuilder
  out_traits : StringBuilder
  out_values : StringBuilder
  out_impls : StringBuilder
  notes : Array[String]
}

///|
fn sanitize(name : String) -> String {
  if rocq_reserved.contains(name) {
    name + "_"
  } else {
    name
  }
}

///|
/// A fresh global Rocq name based on `base`.
fn Gen::fresh(self : Gen, base : String) -> String {
  let mut n = sanitize(base)
  if self.used.contains(n) || prelude_names.contains(n) {
    let palias = self.palias.view(start_offset=1).to_owned()
    n = palias + "_" + n
    let mut k = 1
    let base2 = n
    while self.used.contains(n) {
      n = base2 + k.to_string()
      k = k + 1
    }
  }
  self.used.add(n)
  n
}

///|
fn rocq_string(s : String) -> String {
  "\"" + s.replace_all(old="\"", new="\"\"") + "\""
}

///|
fn foreign_rocq_name(path : String) -> String {
  let sb = StringBuilder::new()
  for c in path {
    if c == '@' {
      continue
    }
    if c == '.' || c == '/' {
      sb.write_char('_')
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Type environment: type variables in scope and the meaning of `Self`.
priv struct TEnv {
  vars : Array[String]
  self_ty : String?
  self_head : String? // rocq name of Self's constructor (applied to Self[..] args)
}

///|
fn paren_app(head : String, args : Array[String]) -> String {
  if args.is_empty() {
    head
  } else {
    "(" + head + " " + args.join(" ") + ")"
  }
}

///|
fn Gen::rty(self : Gen, t : Ty, env : TEnv) -> String raise Unsupported {
  match t {
    TName(n, args) => {
      let rargs = args.map(a => self.rty(a, env))
      if args.is_empty() && env.vars.contains(n) {
        return n
      }
      if n == "Self" {
        match (env.self_ty, env.self_head) {
          (Some(s), _) if args.is_empty() => return s
          (_, Some(h)) => return paren_app(h, rargs)
          (Some(s), None) => return s
          _ => raise Unsupported("Self outside of a method")
        }
      }
      match self.types.get(n) {
        Some((r, _, _)) => return paren_app(r, rargs)
        None => ()
      }
      match builtin_type(n) {
        Some(r) => return paren_app(r, rargs)
        None => ()
      }
      // foreign type: declared as an axiom
      let r = match self.foreign.get(n) {
        Some((r, arity)) => {
          if arity != args.length() {
            raise Unsupported("type \{n} used with different arities")
          }
          r
        }
        None => {
          let r = self.fresh(foreign_rocq_name(n))
          self.foreign.set(n, (r, args.length()))
          self.foreign_order.push(n)
          r
        }
      }
      paren_app(r, rargs)
    }
    TTuple(ts) =>
      if ts.length() == 2 {
        "(" + self.rty(ts[0], env) + " * " + self.rty(ts[1], env) + ")"
      } else {
        raise Unsupported("tuples of size \{ts.length()}")
      }
    TFun(ps, r, eff) => {
      match eff {
        Raise(_) => raise Unsupported("raising callback")
        _ => ()
      }
      let parts = if ps.is_empty() {
        ["unit"]
      } else {
        ps.map(p => self.rty(p, env))
      }
      parts.push(self.rty(r, env))
      "(" + parts.join(" -> ") + ")"
    }
    TObj(p) => raise Unsupported("trait object &\{p}")
  }
}

///|
/// Does a value of this type need converting between Rocq's curried
/// functions and MoonBit's multi-parameter functions?
fn needs_adapt(t : Ty) -> Bool {
  match t {
    TFun(ps, r, _) =>
      ps.length() != 1 || ps.iter().any(needs_adapt) || needs_adapt(r)
    TName(_, args) => args.iter().any(needs_adapt)
    TTuple(ts) => ts.iter().any(needs_adapt)
    TObj(_) => false
  }
}

///|
/// Conversions can only be done at the top of a type, not inside containers.
fn check_adaptable(t : Ty) -> Unit raise Unsupported {
  match t {
    TFun(ps, r, _) => {
      ps.each(check_adaptable)
      check_adaptable(r)
    }
    TName(_, args) =>
      if args.iter().any(needs_adapt) {
        raise Unsupported("multi-parameter function inside a type constructor")
      }
    TTuple(ts) =>
      if ts.iter().any(needs_adapt) {
        raise Unsupported("multi-parameter function inside a tuple")
      }
    TObj(_) => ()
  }
}

///|
/// Rocq value `e` (curried) -> MoonBit value of type `t`.
fn to_mbt(t : Ty, e : String, depth : Int) -> String {
  match t {
    TFun(ps, r, _) if needs_adapt(t) => {
      let names = Array::makei(ps.length(), fn(k) { "rocq_p\{depth}_\{k}" })
      let mut app = e
      if ps.is_empty() {
        app = app + "(())"
      }
      for k in 0..<ps.length() {
        app = app + "(" + to_rocq(ps[k], names[k], depth + 1) + ")"
      }
      "fn(" + names.join(", ") + ") { " + to_mbt(r, app, depth + 1) + " }"
    }
    _ => e
  }
}

///|
/// MoonBit value `e` of type `t` -> Rocq value (curried).
fn to_rocq(t : Ty, e : String, depth : Int) -> String {
  match t {
    TFun(ps, r, _) if needs_adapt(t) => {
      let f = "rocq_f\{depth}"
      let names = Array::makei(ps.length(), fn(k) { "rocq_q\{depth}_\{k}" })
      let call = f +
        "(" +
        Array::makei(ps.length(), fn(k) { to_mbt(ps[k], names[k], depth + 1) }).join(
          ", ",
        ) +
        ")"
      let mut body = to_rocq(r, call, depth + 1)
      if ps.is_empty() {
        body = "fn(_) { " + body + " }"
      } else {
        for k = ps.length() - 1; k >= 0; k = k - 1 {
          body = "fn(" + names[k] + ") { " + body + " }"
        }
      }
      "{ let " + f + " = " + e + "; " + body + " }"
    }
    _ => e
  }
}

///|
/// `forall {A B : Type} `{Eq A}, ` for type parameters with trait bounds.
fn Gen::binders(self : Gen, tps : Array[TParam]) -> String raise Unsupported {
  if tps.is_empty() {
    return ""
  }
  let parts : Array[String] = []
  parts.push("{" + tps.map(fn(p) { p.name }).join(" ") + " : Type}")
  for p in tps {
    for b in p.bounds {
      parts.push("`{" + self.trait_class(b) + " " + p.name + "}")
    }
  }
  "forall " + parts.join(" ") + ", "
}

///|
fn Gen::trait_class(self : Gen, path : String) -> String raise Unsupported {
  match self.traits.get(path) {
    Some(t) => t.rocq
    None =>
      match prelude_trait(path) {
        Some((c, _)) => c
        None => raise Unsupported("trait bound \{path}")
      }
  }
}

///|
fn Gen::note(self : Gen, what : String, why : String) -> Unit {
  self.notes.push(what + ": " + why)
}

// ---------------------------------------------------------------------------
// Types

///|
fn type_deps(t : Ty, acc : Array[String]) -> Unit {
  match t {
    TName(n, args) => {
      acc.push(n)
      args.each(fn(a) { type_deps(a, acc) })
    }
    TTuple(ts) => ts.each(fn(a) { type_deps(a, acc) })
    TFun(ps, r, _) => {
      ps.each(fn(a) { type_deps(a, acc) })
      type_deps(r, acc)
    }
    TObj(_) => ()
  }
}

///|
/// Do the names in `group` occur only strictly positively, under inductive
/// type constructors (option, Result, tuples, other enums)?
fn positive(t : Ty, group : Array[String], enums : Set[String]) -> Bool {
  match t {
    TName(n, args) => {
      let ok_head = builtin_type(n) is Some("option") ||
        builtin_type(n) is Some("Result") ||
        enums.contains(n) ||
        group.contains(n)
      if ok_head {
        args.iter().all(fn(a) { positive(a, group, enums) })
      } else {
        args.iter().all(fn(a) { !(mentions(a, group)) })
      }
    }
    TTuple(ts) => ts.iter().all(fn(a) { positive(a, group, enums) })
    TFun(ps, r, _) => !(ps.iter().any(fn(a) { mentions(a, group) })) && !(mentions(r, group))
    TObj(_) => true
  }
}

///|
fn mentions(t : Ty, names : Array[String]) -> Bool {
  let acc = []
  type_deps(t, acc)
  acc.iter().any(fn(n) { names.contains(n) })
}

///|
fn ctor_types(kind : TypeKind) -> Array[Ty] {
  match kind {
    Enum(cs) | ErrorType(cs) => cs.map(fn(c) { c.args.map(fn(a) { a.ty }) }).flatten()
    Struct(fs, _, _) => fs.map(fn(f) { f.ty })
    Alias(t) => [t]
    Abstract => []
  }
}

///|
/// Decide how each local type is translated.  Non-representable enums and
/// structs become abstract.
fn Gen::classify_types(self : Gen, decls : Array[Decl]) -> Array[(String, Array[String], TypeKind)] {
  let tys : Array[(String, Array[String], TypeKind)] = []
  for d in decls {
    match d {
      DType(name, params, kind, all) => {
        let kind = match kind {
          Struct(fs, a, private) =>
            if !(a && all) || private || fs.iter().any(fn(f) { f.is_mut }) || fs.length() <= 1 {
              Abstract
            } else {
              kind
            }
          Enum(cs) | ErrorType(cs) =>
            if cs.iter().any(fn(c) { c.args.iter().any(fn(a) { a.is_mut }) }) ||
              (cs.length() == 1 && cs[0].args.length() == 1) ||
              cs.is_empty() {
              Abstract
            } else {
              kind
            }
          _ => kind
        }
        let kind = if ctor_types(kind).iter().any(needs_adapt) { Abstract } else { kind }
        tys.push((name, params, kind))
      }
      _ => ()
    }
  }
  // positivity / cycles: types in a cycle must all be enums (mutual Inductive)
  let names = tys.map(fn(t) { t.0 })
  let enums = Set([])
  for t in tys {
    match t.2 {
      Enum(_) | ErrorType(_) | Struct(_, _, _) => enums.add(t.0)
      _ => ()
    }
  }
  let result = tys.map(fn(t) {
    let (name, params, kind) = t
    let group = self.cycle_group(name, tys)
    let in_cycle = group.length() > 1 || (group.contains(name) && self.self_loop(name, tys))
    let kind = match kind {
      Enum(_) | ErrorType(_) | Struct(_, _, _) => {
        let all_enums = group.iter().all(fn(g) {
          match find_kind(g, tys) {
            Some(Enum(_)) | Some(ErrorType(_)) => true
            _ => false
          }
        })
        let pos = ctor_types(kind).iter().all(fn(a) { positive(a, group, enums) })
        if in_cycle && (!(all_enums) || !(pos)) { Abstract } else { kind }
      }
      Alias(_) => if in_cycle { Abstract } else { kind }
      _ => kind
    }
    ignore(names)
    (name, params, kind)
  })
  result
}

///|
fn find_kind(name : String, tys : Array[(String, Array[String], TypeKind)]) -> TypeKind? {
  for t in tys {
    if t.0 == name {
      return Some(t.2)
    }
  }
  None
}

///|
fn local_deps(name : String, tys : Array[(String, Array[String], TypeKind)]) -> Array[String] {
  match find_kind(name, tys) {
    None | Some(Abstract) => []
    Some(k) => {
      let acc = []
      ctor_types(k).each(fn(t) { type_deps(t, acc) })
      acc.filter(fn(n) { find_kind(n, tys) is Some(_) })
    }
  }
}

///|
fn Gen::self_loop(self : Gen, name : String, tys : Array[(String, Array[String], TypeKind)]) -> Bool {
  ignore(self)
  local_deps(name, tys).contains(name)
}

///|
/// Types mutually reachable with `name` (its strongly connected component).
fn Gen::cycle_group(self : Gen, name : String, tys : Array[(String, Array[String], TypeKind)]) -> Array[String] {
  ignore(self)
  let reach = fn(from : String) -> Set[String] {
    let seen = Set([])
    let todo = [from]
    while todo.pop() is Some(n) {
      for d in local_deps(n, tys) {
        if !(seen.contains(d)) {
          seen.add(d)
          todo.push(d)
        }
      }
    }
    seen
  }
  let from_name = reach(name)
  let group = [name]
  for t in tys {
    if t.0 != name && from_name.contains(t.0) && reach(t.0).contains(name) {
      group.push(t.0)
    }
  }
  group
}

///|
fn Gen::emit_abstract(self : Gen, name : String, rocq : String, params : Array[String]) -> Unit {
  let sig = Array::make(params.length() + 1, "Type").join(" -> ")
  self.out_types.write_string("Axiom \{rocq} : \{sig}.\n")
  let path = self.palias + "." + name
  if params.is_empty() {
    self.out_types.write_string("Extract Inlined Constant \{rocq} => \{rocq_string(path)}.\n")
  } else {
    let ids = params.map(rocq_string).join(" ")
    let applied = path + "[" + params.join(", ") + "]"
    self.out_types.write_string("Extract Constant \{rocq} \{ids} => \{rocq_string(applied)}.\n")
  }
}

///|
fn ctor_template(path : String, c : Ctor) -> String {
  let callee = path + "::" + c.name
  if c.args.is_empty() {
    return callee
  }
  if c.args.iter().all(fn(a) { a.label is None }) {
    return callee
  }
  let args = Array::makei(c.args.length(), fn(i) {
    match c.args[i].label {
      Some(l) => l + "=$" + i.to_string()
      None => "$" + i.to_string()
    }
  })
  callee + "(" + args.join(", ") + ")"
}

///|
fn Gen::emit_inductive_group(
  self : Gen,
  group : Array[(String, String, Array[String], Array[Ctor])],
) -> Unit raise Unsupported {
  // group: mbt name, rocq name, params, ctors
  let defs : Array[String] = []
  let after = StringBuilder::new()
  for g in group {
    let (name, rocq, params, ctors) = g
    let env = { vars: params, self_ty: None, self_head: None }
    let applied = paren_app(rocq, params)
    let header = if params.is_empty() {
      rocq + " : Type :="
    } else {
      rocq + " " + params.map(fn(p) { "(" + p + " : Type)" }).join(" ") + " : Type :="
    }
    let lines = [header]
    let cnames : Array[String] = []
    for c in ctors {
      let cn = self.fresh(c.name)
      cnames.push(cn)
      let parts = c.args.map(a => self.rty(a.ty, env))
      parts.push(applied)
      lines.push("| " + cn + " : " + parts.join(" -> "))
      if !(params.is_empty()) {
        after.write_string("Arguments \{cn} {\{params.join(" ")}}.\n")
      }
    }
    defs.push(lines.join("\n"))
    let path = self.palias + "." + name
    let cstrs = ctors.map(fn(c) { rocq_string(ctor_template(path, c)) }).join(" ")
    after.write_string("Extract Inductive \{rocq} => \{rocq_string(path)} [ \{cstrs} ].\n")
  }
  self.out_types.write_string("Inductive " + defs.join("\nwith ") + ".\n")
  self.out_types.write_string(after.to_string())
}

///|
fn Gen::emit_record(
  self : Gen,
  name : String,
  rocq : String,
  params : Array[String],
  fields : Array[Field],
) -> Unit raise Unsupported {
  let env = { vars: params, self_ty: None, self_head: None }
  let ps = params.map(fn(p) { "(" + p + " : Type)" }).join(" ")
  let build = self.fresh("Build_" + rocq)
  let fs = fields.map(f => {
    let fname = self.fresh(rocq + "_" + f.name)
    fname + " : " + self.rty(f.ty, env)
  })
  let head = if params.is_empty() { rocq } else { rocq + " " + ps }
  self.out_types.write_string(
    "Record \{head} : Type := \{build} {\n  " + fs.join(";\n  ") + "\n}.\n",
  )
  if !(params.is_empty()) {
    self.out_types.write_string("Arguments \{build} {\{params.join(" ")}}.\n")
  }
  let path = self.palias + "." + name
  let cons = path +
    "::{ " +
    Array::makei(fields.length(), fn(i) { fields[i].name + ": $" + i.to_string() }).join(
      ", ",
    ) +
    " }"
  let sty = if params.is_empty() {
    path
  } else {
    path + "[" + params.map(fn(_) { "_" }).join(", ") + "]"
  }
  let m = "(fn(rocq_k, rocq_s : " +
    sty +
    ") { rocq_k(" +
    fields.map(fn(f) { "rocq_s." + f.name }).join(", ") +
    ") })"
  self.out_types.write_string(
    "Extract Inductive \{rocq} => \{rocq_string(path)} [ \{rocq_string(cons)} ] \{rocq_string(m)}.\n",
  )
}

///|
/// Accessors (and constructor) of abstract structs / single-field types.
fn Gen::emit_accessors(self : Gen, name : String, rocq : String, params : Array[String], kind : TypeKind) -> Unit {
  let env = { vars: params, self_ty: None, self_head: None }
  let tb = if params.is_empty() { "" } else { "forall {" + params.join(" ") + " : Type}, " }
  let applied = paren_app(rocq, params)
  let path = self.palias + "." + name
  match kind {
    Struct(fs, all, private) => {
      for f in fs {
        let r = try self.rty(f.ty, env) catch {
          Unsupported(why) => {
            self.note(name + "." + f.name, why)
            continue
          }
        }
        if needs_adapt(f.ty) {
          self.note(name + "." + f.name, "multi-parameter function field")
          continue
        }
        let acc = self.fresh(rocq + "_" + f.name)
        self.out_values.write_string("Axiom \{acc} : \{tb}\{applied} -> \{r}.\n")
        self.out_values.write_string(
          "Extract MoonBit Function \{acc} => " + rocq_string("$0." + f.name) + ".\n",
        )
      }
      if all && !(private) && !(fs.is_empty()) {
        let ok = fs.iter().all(fn(f) { !(needs_adapt(f.ty)) })
        let parts = fs.map(fn(f) { try self.rty(f.ty, env) catch { _ => "" } })
        if ok && !(parts.contains("")) {
          let mk = self.fresh(rocq + "_new")
          parts.push(applied)
          self.out_values.write_string("Axiom \{mk} : \{tb}" + parts.join(" -> ") + ".\n")
          let tpl = path +
            "::{ " +
            Array::makei(fs.length(), fn(i) { fs[i].name + ": $" + i.to_string() }).join(
              ", ",
            ) +
            " }"
          self.out_values.write_string(
            "Extract MoonBit Function \{mk} => \{rocq_string(tpl)}.\n",
          )
        }
      }
    }
    Enum([c]) | ErrorType([c]) if c.args.length() == 1 && !(c.args[0].is_mut) => {
      // single-constructor wrapper: constructor and eliminator
      let a = c.args[0]
      let r = try self.rty(a.ty, env) catch {
        Unsupported(why) => {
          self.note(name, why)
          return
        }
      }
      let mk = self.fresh(rocq + "_" + c.name)
      self.out_values.write_string("Axiom \{mk} : \{tb}\{r} -> \{applied}.\n")
      self.out_values.write_string(
        "Extract MoonBit Function \{mk} => \{rocq_string(ctor_template(path, c) + (if a.label is None { "($0)" } else { "" }))}.\n",
      )
      let un = self.fresh(rocq + "_un" + c.name)
      self.out_values.write_string("Axiom \{un} : \{tb}\{applied} -> \{r}.\n")
      let pat = match a.label {
        Some(l) => path + "::" + c.name + "(" + l + "=rocq_x)"
        None => path + "::" + c.name + "(rocq_x)"
      }
      self.out_values.write_string(
        "Extract MoonBit Function \{un} => \{rocq_string("(match $0 { " + pat + " => rocq_x })")}.\n",
      )
    }
    _ => ()
  }
}

///|
fn Gen::emit_types(self : Gen, decls : Array[Decl]) -> Unit {
  let tys = self.classify_types(decls)
  // names first, so that types can refer to each other
  for t in tys {
    let (name, params, kind) = t
    self.types.set(name, (self.fresh(name), params, kind))
  }
  // abstract types
  for t in tys {
    let (name, params, kind) = t
    if kind is Abstract {
      let (rocq, _, _) = self.types.get(name).unwrap()
      self.emit_abstract(name, rocq, params)
    }
  }
  // the others, in dependency order
  let done = Set([])
  for t in tys {
    if t.2 is Abstract {
      done.add(t.0)
    }
  }
  let mut progress = true
  while progress {
    progress = false
    for t in tys {
      let (name, _, _) = t
      if done.contains(name) {
        continue
      }
      let group = self.cycle_group(name, tys)
      let ready = group.iter().all(fn(g) {
        local_deps(g, tys).iter().all(fn(d) { done.contains(d) || group.contains(d) })
      })
      if !(ready) {
        continue
      }
      progress = true
      group.each(fn(g) { done.add(g) })
      self.emit_type_group(group, tys) catch {
        Unsupported(why) => {
          self.note("type " + name, why)
          // fall back to abstract types
          for g in group {
            let (rocq, params, _) = self.types.get(g).unwrap()
            self.emit_abstract(g, rocq, params)
            self.types.set(g, (rocq, params, Abstract))
          }
        }
      }
    }
  }
  for t in tys {
    let (name, params, _) = t
    let (rocq, _, final_kind) = self.types.get(name).unwrap()
    if !(final_kind is Abstract) {
      continue
    }
    match find_kind(name, decls_kinds(decls)) {
      Some(orig) => self.emit_accessors(name, rocq, params, orig)
      None => ()
    }
  }
}

///|
fn decls_kinds(decls : Array[Decl]) -> Array[(String, Array[String], TypeKind)] {
  decls.filter_map(fn(d) {
    match d {
      DType(n, ps, k, all) =>
        match k {
          // readonly structs are only readable
          Struct(fs, a, p) => Some((n, ps, Struct(fs, a && all, p)))
          _ => Some((n, ps, k))
        }
      _ => None
    }
  })
}

///|
fn Gen::emit_type_group(
  self : Gen,
  group : Array[String],
  tys : Array[(String, Array[String], TypeKind)],
) -> Unit raise Unsupported {
  let g0 = group[0]
  let (rocq0, params0, _) = self.types.get(g0).unwrap()
  match find_kind(g0, tys).unwrap() {
    Alias(t) => {
      let env = { vars: params0, self_ty: None, self_head: None }
      let ps = params0.map(fn(p) { "(" + p + " : Type)" }).join(" ")
      let head = if params0.is_empty() { rocq0 } else { rocq0 + " " + ps }
      self.out_types.write_string(
        "Definition \{head} : Type := \{self.rty(t, env)}.\n",
      )
    }
    Struct(fs, _, _) => self.emit_record(g0, rocq0, params0, fs)
    _ => {
      let members = group.map(fn(g) {
        let (rocq, params, _) = self.types.get(g).unwrap()
        let cs = match find_kind(g, tys).unwrap() {
          Enum(cs) | ErrorType(cs) => cs
          _ => []
        }
        (g, rocq, params, cs)
      })
      // check every constructor argument before emitting anything
      for m in members {
        let env = { vars: m.2, self_ty: None, self_head: None }
        for c in m.3 {
          for a in c.args {
            ignore(self.rty(a.ty, env))
          }
        }
      }
      self.emit_inductive_group(members)
    }
  }
}

// ---------------------------------------------------------------------------
// Traits and impls

///|
fn Gen::emit_trait(self : Gen, name : String, methods : Array[TraitMethod]) -> Unit raise Unsupported {
  let env = { vars: ["Self"], self_ty: Some("Self"), self_head: None }
  let fields : Array[String] = []
  let decls = StringBuilder::new()
  let ms : Array[(String, String)] = []
  for m in methods {
    for p in m.params {
      check_adaptable(p)
    }
    check_adaptable(m.ret)
    let parts = if m.params.is_empty() {
      ["unit"]
    } else {
      m.params.map(p => self.rty(p, env))
    }
    parts.push(self.rty(m.ret, env))
    let ty = parts.join(" -> ")
    ms.push((m.name, ty))
  }
  let rocq = self.fresh(name)
  let out : Array[(String, String)] = []
  for i in 0..<methods.length() {
    let m = methods[i]
    let field = self.fresh(m.name)
    let ax = self.fresh(rocq + "_" + m.name + "_impl")
    fields.push(field + " : " + ms[i].1)
    out.push((field, ax))
    let n = m.params.length()
    let args = Array::makei(n, fn(k) { to_mbt(m.params[k], "$" + k.to_string(), 0) })
    let call = to_rocq(m.ret, self.palias + "." + name + "::" + m.name + "(" + args.join(", ") + ")", 0)
    decls.write_string("Axiom \{ax} : forall {Self : Type}, \{ms[i].1}.\n")
    let arity = if n == 0 { " 1" } else { "" }
    decls.write_string("Extract MoonBit Function \{ax}\{arity} => \{rocq_string(call)}.\n")
  }
  self.out_traits.write_string(
    "Class \{rocq} (Self : Type) : Type := {\n  " + fields.join(";\n  ") + "\n}.\n",
  )
  self.out_traits.write_string(
    "Extract MoonBit Trait \{rocq} => \{rocq_string(self.palias + "." + name)}.\n",
  )
  self.out_traits.write_string(decls.to_string())
  self.traits.set(name, { rocq, methods: out })
}

///|
fn ty_head(t : Ty) -> String {
  match t {
    TName(n, _) =>
      match builtin_type(n) {
        Some(r) => r
        None => foreign_rocq_name(n)
      }
    TTuple(_) => "Tuple"
    TFun(_, _, _) => "Fun"
    TObj(_) => "Obj"
  }
}

///|
fn Gen::emit_impl(self : Gen, tps : Array[TParam], trait_ : String, for_ty : Ty) -> Unit raise Unsupported {
  let (cls, methods) = match self.traits.get(trait_) {
    Some(t) => (t.rocq, t.methods)
    None =>
      match prelude_trait(trait_) {
        Some(p) => p
        None => raise Unsupported("unknown trait \{trait_}")
      }
  }
  let env = { vars: tps.map(fn(p) { p.name }), self_ty: None, self_head: None }
  let target = self.rty(for_ty, env)
  let name = self.fresh(cls + "_" + ty_head(for_ty))
  let binders = if tps.is_empty() {
    ""
  } else {
    let parts = ["{" + tps.map(fn(p) { p.name }).join(" ") + " : Type}"]
    for p in tps {
      for b in p.bounds {
        parts.push("`{" + self.trait_class(b) + " " + p.name + "}")
      }
    }
    " " + parts.join(" ")
  }
  let fields = methods.map(fn(m) { m.0 + " := " + m.1 }).join("; ")
  self.out_impls.write_string(
    "#[global] Instance \{name}\{binders} : \{cls} \{target} := {| \{fields} |}.\n",
  )
}

// ---------------------------------------------------------------------------
// Functions and values

///|
fn Gen::emit_fn(self : Gen, f : FnDecl) -> Unit raise Unsupported {
  if f.is_async {
    raise Unsupported("async function")
  }
  let (self_ty, self_head) = match f.owner {
    Some(o) =>
      match self.types.get(o) {
        Some((r, ps, _)) =>
          if ps.is_empty() {
            (Some(r), None)
          } else {
            (None, Some(r))
          }
        None =>
          match builtin_type(o) {
            Some(r) => (Some(r), None)
            None => raise Unsupported("method of unknown type \{o}")
          }
      }
    None => (None, None)
  }
  let env = { vars: f.tparams.map(fn(p) { p.name }), self_ty, self_head }
  let params = f.params.filter(fn(p) { !(p.optional) })
  for p in params {
    check_adaptable(p.ty)
  }
  check_adaptable(f.ret)
  let parts = if params.is_empty() {
    ["unit"]
  } else {
    params.map(p => self.rty(p.ty, env))
  }
  let ret = self.rty(f.ret, env)
  let ret = match f.effect {
    Raise(e) => {
      if needs_adapt(f.ret) {
        raise Unsupported("raising function returning a function")
      }
      "(Result " + ret + " " + self.rty(e, env) + ")"
    }
    _ => ret
  }
  parts.push(ret)
  let ty = self.binders(f.tparams) + parts.join(" -> ")
  let callee = match f.owner {
    Some(o) =>
      match builtin_type(o) {
        Some(_) => o + "::" + f.name
        None => self.palias + "." + o + "::" + f.name
      }
    None => self.palias + "." + f.name
  }
  let args = Array::makei(params.length(), fn(k) {
    let a = to_mbt(params[k].ty, "$" + k.to_string(), 0)
    match params[k].label {
      Some(l) => l + "=" + a
      None => a
    }
  })
  let call = callee + "(" + args.join(", ") + ")"
  let call = match f.effect {
    Raise(_) =>
      "(try " +
      call +
      " catch { rocq_e => Result::Err(rocq_e) } noraise { rocq_v => Result::Ok(rocq_v) })"
    _ => to_rocq(f.ret, call, 0)
  }
  let base = match f.owner {
    Some(o) => o + "_" + f.name
    None => f.name
  }
  let name = self.fresh(base)
  let arity = if params.is_empty() { " 1" } else { "" }
  self.out_values.write_string("Axiom \{name} : \{ty}.\n")
  self.out_values.write_string(
    "Extract MoonBit Function \{name}\{arity} => \{rocq_string(call)}.\n",
  )
}

///|
fn Gen::emit_value(self : Gen, name : String, t : Ty) -> Unit raise Unsupported {
  check_adaptable(t)
  let env = { vars: [], self_ty: None, self_head: None }
  let ty = self.rty(t, env)
  let r = self.fresh(name)
  self.out_values.write_string("Axiom \{r} : \{ty}.\n")
  self.out_values.write_string(
    "Extract MoonBit Function \{r} 0 => \{rocq_string(to_rocq(t, self.palias + "." + name, 0))}.\n",
  )
}

///|
fn show_ty(t : Ty) -> String {
  match t {
    TName(n, []) => n
    TName(n, args) => n + "[" + args.map(show_ty).join(", ") + "]"
    TTuple(ts) => "(" + ts.map(show_ty).join(", ") + ")"
    TFun(ps, r, _) => "(" + ps.map(show_ty).join(", ") + ") -> " + show_ty(r)
    TObj(p) => "&" + p
  }
}

///|
/// Translate an interface.  `palias` is the package palias used in the
/// generated MoonBit code (default: last component of the package path).
pub fn generate(iface : Interface, palias? : String, source? : String = "") -> String {
  let palias = match palias {
    Some(a) => if a.has_prefix("@") { a } else { "@" + a }
    None => {
      let parts = iface.pkg.split("/").map(fn(v) { v.to_owned() }).to_array()
      "@" + (if parts.is_empty() { "pkg" } else { parts[parts.length() - 1] })
    }
  }
  let g : Gen = {
    palias,
    types: {},
    traits: {},
    foreign: {},
    foreign_order: [],
    used: Set([]),
    out_types: StringBuilder::new(),
    out_traits: StringBuilder::new(),
    out_values: StringBuilder::new(),
    out_impls: StringBuilder::new(),
    notes: [],
  }
  g.emit_types(iface.decls)
  for d in iface.decls {
    match d {
      DTrait(name, ms) =>
        g.emit_trait(name, ms) catch {
          Unsupported(why) => g.note("trait " + name, why)
        }
      _ => ()
    }
  }
  for d in iface.decls {
    match d {
      DFn(f) => {
        let what = match f.owner {
          Some(o) => "fn " + o + "::" + f.name
          None => "fn " + f.name
        }
        g.emit_fn(f) catch {
          Unsupported(why) => g.note(what, why)
        }
      }
      DValue(n, t) => g.emit_value(n, t) catch { Unsupported(why) => g.note(n, why) }
      DImpl(tps, tr, t) =>
        g.emit_impl(tps, tr, t) catch {
          Unsupported(why) => g.note("impl " + tr + " for " + show_ty(t), why)
        }
      DSkipped(_, why) => g.note("unparsed declaration", why)
      _ => ()
    }
  }
  // foreign types are discovered while translating: declare them first
  let foreign = StringBuilder::new()
  for path in g.foreign_order {
    let (r, arity) = g.foreign.get(path).unwrap()
    let mbt = if path.has_prefix("@") { path } else { path }
    if arity == 0 {
      foreign.write_string(
        "Axiom \{r} : Type.\nExtract Inlined Constant \{r} => \{rocq_string(mbt)}.\n",
      )
    } else {
      let ids = Array::makei(arity, fn(i) { "T" + i.to_string() })
      let sig = Array::make(arity + 1, "Type").join(" -> ")
      foreign.write_string(
        "Axiom \{r} : \{sig}.\nExtract Constant \{r} \{ids.map(rocq_string).join(" ")} => \{rocq_string(mbt + "[" + ids.join(", ") + "]")}.\n",
      )
    }
  }
  let out = StringBuilder::new()
  out.write_string("(* Generated by mbti2rocq")
  if source != "" {
    out.write_string(" from " + source)
  }
  out.write_string(". Do not edit.\n")
  out.write_string("   MoonBit package: \"\{iface.pkg}\", used as \{palias}:\n")
  out.write_string("   import it in the moon.pkg of the extracted code with that alias. *)\n\n")
  out.write_string("From RocqMbt Require Import Prelude.\n")
  let section = fn(title : String, body : String) {
    if body != "" {
      out.write_string("\n(** * " + title + " *)\n\n")
      out.write_string(body)
    }
  }
  section("Foreign types", foreign.to_string())
  section("Types", g.out_types.to_string())
  section("Traits", g.out_traits.to_string())
  section("Functions and values", g.out_values.to_string())
  section("Instances", g.out_impls.to_string())
  if !(g.notes.is_empty()) {
    out.write_string("\n(* Not translated:\n")
    for n in g.notes {
      out.write_string("   - " + n.replace_all(old="*)", new="* )") + "\n")
    }
    out.write_string("*)\n")
  }
  out.to_string()
}
