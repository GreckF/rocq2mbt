// Recursive-descent parser for .mbti files.  Unknown or malformed
// declarations are skipped (recorded as `DSkipped`), never fatal.

///|
pub suberror ParseError {
  ParseError(String)
} derive(Debug)

///|
priv struct Parser {
  toks : Array[Token]
  mut pos : Int
}

///|
fn Parser::peek(self : Parser) -> Tok {
  self.toks[self.pos].tok
}

///|
fn Parser::peek_at(self : Parser, k : Int) -> Tok {
  let i = self.pos + k
  if i < self.toks.length() {
    self.toks[i].tok
  } else {
    Eof
  }
}

///|
fn Parser::line(self : Parser) -> Int {
  self.toks[self.pos].line
}

///|
fn Parser::at_bol(self : Parser) -> Bool {
  self.toks[self.pos].bol
}

///|
fn Parser::advance(self : Parser) -> Unit {
  if self.pos < self.toks.length() - 1 {
    self.pos = self.pos + 1
  }
}

///|
fn Parser::is_sym(self : Parser, s : String) -> Bool {
  self.peek() == Sym(s)
}

///|
fn Parser::is_id(self : Parser, s : String) -> Bool {
  self.peek() == Id(s)
}

///|
fn Parser::fail(self : Parser, msg : String) -> Unit raise ParseError {
  let at = match self.peek() {
    Id(s) | Lit(s) | Sym(s) => s
    Str(s) => "\"" + s + "\""
    Eof => "end of file"
  }
  raise ParseError("line \{self.line()}: \{msg} (at `\{at}`)")
}

///|
fn Parser::expect_sym(self : Parser, s : String) -> Unit raise ParseError {
  if self.is_sym(s) {
    self.advance()
  } else {
    self.fail("expected `\{s}`")
  }
}

///|
fn Parser::expect_id(self : Parser, s : String) -> Unit raise ParseError {
  if self.is_id(s) {
    self.advance()
  } else {
    self.fail("expected `\{s}`")
  }
}

///|
fn Parser::ident(self : Parser) -> String raise ParseError {
  match self.peek() {
    Id(s) => {
      self.advance()
      s
    }
    _ => {
      self.fail("expected an identifier")
      ""
    }
  }
}

///|
fn Parser::accept_sym(self : Parser, s : String) -> Bool {
  if self.is_sym(s) {
    self.advance()
    true
  } else {
    false
  }
}

///|
/// Skip the rest of the current line (and any bracketed block opened on it).
fn Parser::skip_line(self : Parser) -> Unit {
  let mut depth = 0
  while true {
    match self.peek() {
      Eof => break
      _ => ()
    }
    if self.at_bol() && depth == 0 {
      break
    }
    match self.peek() {
      Sym("{") | Sym("(") | Sym("[") => depth = depth + 1
      Sym("}") | Sym(")") | Sym("]") => depth = if depth > 0 { depth - 1 } else { 0 }
      _ => ()
    }
    self.advance()
  }
}

///|
/// Path of a type or trait: `Int`, `Self`, `@json.Json`, `@a/b.T`, `T::U`.
fn Parser::path(self : Parser) -> String raise ParseError {
  let sb = StringBuilder::new()
  if self.accept_sym("@") {
    sb.write_char('@')
    sb.write_string(self.ident())
    while self.accept_sym("/") {
      sb.write_char('/')
      sb.write_string(self.ident())
    }
    self.expect_sym(".")
    sb.write_char('.')
  }
  sb.write_string(self.ident())
  sb.to_string()
}

///|
fn Parser::effect(self : Parser) -> Effect raise ParseError {
  if self.is_id("noraise") {
    self.advance()
    NoRaise
  } else if self.is_id("raise") {
    self.advance()
    if self.accept_sym("?") {
      RaisePoly
    } else if !(self.at_bol()) &&
      (
        match self.peek() {
          Id(_) | Sym("@") | Sym("(") => true
          _ => false
        }
      ) {
      Raise(self.ty())
    } else {
      Raise(TName("Error", []))
    }
  } else {
    NoRaise
  }
}

///|
fn Parser::ty(self : Parser) -> Ty raise ParseError {
  let mut t = self.ty_atom()
  while self.is_sym("?") && self.peek_at(1) != Sym(":") {
    self.advance()
    t = TName("Option", [t])
  }
  t
}

///|
fn Parser::ty_atom(self : Parser) -> Ty raise ParseError {
  if self.is_id("async") {
    self.fail("async function type")
  }
  if self.accept_sym("&") {
    return TObj(self.path())
  }
  if self.accept_sym("(") {
    let elems : Array[Ty] = []
    while !(self.is_sym(")")) {
      // labelled parameters of function types: drop the label
      match (self.peek(), self.peek_at(1), self.peek_at(2)) {
        (Id(_), Sym("~"), Sym(":")) | (Id(_), Sym("?"), Sym(":")) => {
          self.advance()
          self.advance()
          self.advance()
        }
        _ => ()
      }
      elems.push(self.ty())
      if !(self.accept_sym(",")) {
        break
      }
    }
    self.expect_sym(")")
    if self.accept_sym("->") {
      let ret = self.ty()
      let eff = self.effect()
      return TFun(elems, ret, eff)
    }
    if elems.length() == 1 {
      return elems[0]
    }
    return TTuple(elems)
  }
  let name = self.path()
  let args : Array[Ty] = []
  if self.accept_sym("[") {
    while !(self.is_sym("]")) {
      args.push(self.ty())
      if !(self.accept_sym(",")) {
        break
      }
    }
    self.expect_sym("]")
  }
  TName(name, args)
}

///|
fn Parser::tparams(self : Parser) -> Array[TParam] raise ParseError {
  let out : Array[TParam] = []
  if self.accept_sym("[") {
    while !(self.is_sym("]")) {
      let name = self.ident()
      let bounds : Array[String] = []
      if self.accept_sym(":") {
        bounds.push(self.path())
        while self.accept_sym("+") {
          bounds.push(self.path())
        }
      }
      out.push({ name, bounds })
      if !(self.accept_sym(",")) {
        break
      }
    }
    self.expect_sym("]")
  }
  out
}

///|
fn Parser::params(self : Parser) -> Array[Param] raise ParseError {
  let out : Array[Param] = []
  self.expect_sym("(")
  while !(self.is_sym(")")) {
    match (self.peek(), self.peek_at(1), self.peek_at(2)) {
      (Id(l), Sym("~"), Sym(":")) => {
        self.advance()
        self.advance()
        self.advance()
        let ty = self.ty()
        if self.accept_sym("=") {
          self.advance() // default `_`
        }
        out.push({ label: Some(l), optional: false, ty })
      }
      (Id(l), Sym("?"), Sym(":")) => {
        self.advance()
        self.advance()
        self.advance()
        out.push({ label: Some(l), optional: true, ty: self.ty() })
      }
      _ => out.push({ label: None, optional: false, ty: self.ty() })
    }
    if !(self.accept_sym(",")) {
      break
    }
  }
  self.expect_sym(")")
  out
}

///|
fn Parser::skip_derive(self : Parser) -> Unit raise ParseError {
  if self.is_id("derive") {
    self.advance()
    self.expect_sym("(")
    let mut depth = 1
    while depth > 0 {
      match self.peek() {
        Sym("(") => depth = depth + 1
        Sym(")") => depth = depth - 1
        Eof => self.fail("unterminated derive")
        _ => ()
      }
      self.advance()
    }
  }
}

///|
fn Parser::fn_decl(self : Parser, is_async : Bool) -> Decl raise ParseError {
  self.expect_id("fn")
  let tparams = self.tparams()
  let first = self.path()
  let (owner, name) = if self.accept_sym("::") {
    (Some(first), self.ident())
  } else {
    (None, first)
  }
  let params = self.params()
  let (ret, effect) = if self.accept_sym("->") {
    let r = self.ty()
    (r, self.effect())
  } else {
    (TName("Unit", []), NoRaise)
  }
  DFn({ tparams, owner, name, params, ret, effect, is_async })
}

///|
fn Parser::ctors(self : Parser) -> Array[Ctor] raise ParseError {
  let out : Array[Ctor] = []
  self.expect_sym("{")
  while !(self.is_sym("}")) {
    let name = self.ident()
    let args : Array[CtorArg] = []
    if self.accept_sym("(") {
      while !(self.is_sym(")")) {
        let is_mut = if self.is_id("mut") {
          self.advance()
          true
        } else {
          false
        }
        let label = match (self.peek(), self.peek_at(1), self.peek_at(2)) {
          (Id(l), Sym("~"), Sym(":")) => {
            self.advance()
            self.advance()
            self.advance()
            Some(l)
          }
          _ => None
        }
        args.push({ label, is_mut, ty: self.ty() })
        if !(self.accept_sym(",")) {
          break
        }
      }
      self.expect_sym(")")
    }
    if self.accept_sym("=") {
      self.advance() // explicit discriminant
    }
    ignore(self.accept_sym(";"))
    out.push({ name, args })
  }
  self.expect_sym("}")
  out
}

///|
fn Parser::type_decl(self : Parser, all : Bool) -> Decl raise ParseError {
  let kw = self.ident()
  let name = self.ident()
  let params = self.tparams().map(fn(p) { p.name })
  let kind = match kw {
    "struct" => {
      let fields : Array[Field] = []
      let mut private = false
      if self.accept_sym("(") {
        // tuple struct: treat as abstract
        self.skip_line()
        return DType(name, params, Abstract, all)
      }
      self.expect_sym("{")
      while !(self.is_sym("}")) {
        if self.is_id("__private__") || self.is_id("priv") {
          private = true
          if self.is_id("priv") {
            self.advance()
            continue
          }
          self.advance()
          continue
        }
        let is_mut = if self.is_id("mut") {
          self.advance()
          true
        } else {
          false
        }
        let fname = self.ident()
        self.expect_sym(":")
        fields.push({ name: fname, is_mut, ty: self.ty() })
        ignore(self.accept_sym(";"))
        ignore(self.accept_sym(","))
      }
      self.expect_sym("}")
      Struct(fields, all, private)
    }
    "enum" => Enum(self.ctors())
    "suberror" =>
      if self.is_sym("{") {
        ErrorType(self.ctors())
      } else if !(self.at_bol()) && !(self.is_id("derive")) {
        // old syntax `suberror E T`: one constructor E(T)
        ErrorType([{ name, args: [{ label: None, is_mut: false, ty: self.ty() }] }])
      } else {
        ErrorType([{ name, args: [] }])
      }
    "type" =>
      if self.accept_sym("=") {
        Alias(self.ty())
      } else {
        Abstract
      }
    _ => {
      self.fail("unknown type declaration")
      Abstract
    }
  }
  self.skip_derive()
  DType(name, params, kind, all)
}

///|
fn Parser::trait_decl(self : Parser) -> Decl raise ParseError {
  self.expect_id("trait")
  let name = self.ident()
  if self.accept_sym(":") {
    // supertraits are ignored
    ignore(self.path())
    while self.accept_sym("+") {
      ignore(self.path())
    }
  }
  let methods : Array[TraitMethod] = []
  self.expect_sym("{")
  while !(self.is_sym("}")) {
    if self.is_id("fn") {
      self.advance()
    }
    let mname = self.ident()
    if self.is_sym("[") {
      self.fail("generic trait method")
    }
    let params = self.params()
    if params.iter().any(fn(p) { p.label is Some(_) }) {
      self.fail("labelled trait method parameters")
    }
    self.expect_sym("->")
    let ret = self.ty()
    match self.effect() {
      NoRaise | RaisePoly => ()
      _ => self.fail("raising trait method")
    }
    if self.accept_sym("=") {
      self.advance() // default implementation `_`
    }
    ignore(self.accept_sym(";"))
    methods.push({ name: mname, params: params.map(fn(p) { p.ty }), ret })
  }
  self.expect_sym("}")
  DTrait(name, methods)
}

///|
fn Parser::impl_decl(self : Parser) -> Decl raise ParseError {
  self.expect_id("impl")
  let tparams = self.tparams()
  let trait_ = self.path()
  self.expect_id("for")
  let for_ty = self.ty()
  self.skip_line() // `with method(..)`
  DImpl(tparams, trait_, for_ty)
}

///|
fn Parser::decl(self : Parser) -> Decl? raise ParseError {
  let mut all = false
  if self.is_id("pub") {
    self.advance()
    if self.accept_sym("(") {
      let vis = self.ident()
      all = vis == "all" || vis == "open"
      self.expect_sym(")")
    }
  }
  match self.peek() {
    Id("fn") => Some(self.fn_decl(false))
    Id("async") => {
      self.advance()
      Some(self.fn_decl(true))
    }
    Id("let") | Id("const") => {
      self.advance()
      let name = self.ident()
      self.expect_sym(":")
      let ty = self.ty()
      self.skip_line() // `= value`
      Some(DValue(name, ty))
    }
    Id("struct") | Id("enum") | Id("suberror") | Id("type") =>
      Some(self.type_decl(all))
    Id("trait") => Some(self.trait_decl())
    Id("impl") => Some(self.impl_decl())
    _ => {
      // using, typealias, fnalias, traitalias, extern, ...
      self.advance()
      self.skip_line()
      None
    }
  }
}

///|
pub fn parse(src : String) -> Interface {
  let p : Parser = { toks: lex(src), pos: 0 }
  let mut pkg = ""
  let decls : Array[Decl] = []
  while p.peek() != Eof {
    match p.peek() {
      Id("package") => {
        p.advance()
        match p.peek() {
          Str(s) => pkg = s
          _ => ()
        }
        p.skip_line()
        continue
      }
      Id("import") => {
        p.advance()
        p.skip_line()
        continue
      }
      _ => ()
    }
    let start = p.pos
    let line = p.line()
    let res = try p.decl() catch {
      ParseError(msg) => {
        if p.pos == start {
          p.advance()
        }
        p.skip_line()
        decls.push(DSkipped(line, msg))
        None
      }
    }
    match res {
      Some(d) => decls.push(d)
      None => ()
    }
    if p.pos == start {
      p.advance()
    }
  }
  { pkg, decls }
}
