// Tokenizer for .mbti files.

///|
pub(all) enum Tok {
  Id(String) // identifiers and keywords
  Str(String) // string literal (contents, unescaped loosely)
  Lit(String) // numeric / char / other literals, raw
  Sym(String) // punctuation
  Eof
} derive(Eq, Debug)

///|
pub(all) struct Token {
  tok : Tok
  line : Int
  bol : Bool // first token on its line
} derive(Debug)

///|
fn is_ident_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_'
}

///|
fn is_ident_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
}

///|
/// Two-character symbols, longest match first.
let two_char_syms : Array[String] = ["->", "=>", "::", "..", "&&", "||"]

///|
pub fn lex(src : String) -> Array[Token] {
  let cs : Array[Char] = []
  for c in src {
    cs.push(c)
  }
  let n = cs.length()
  let out : Array[Token] = []
  let mut i = 0
  let mut line = 1
  let mut bol = true
  while i < n {
    let c = cs[i]
    if c == '\n' {
      line = line + 1
      bol = true
      i = i + 1
    } else if c == ' ' || c == '\t' || c == '\r' {
      i = i + 1
    } else if c == '/' && i + 1 < n && cs[i + 1] == '/' {
      // comment; "// private fields" marks abstract structs
      let start = i
      while i < n && cs[i] != '\n' {
        i = i + 1
      }
      let text = String::from_array(cs[start:i])
      if text.contains("private fields") {
        out.push({ tok: Id("__private__"), line, bol })
        bol = false
      }
    } else if c == '#' && bol {
      // attribute line such as #deprecated or #as_free_fn(..)
      while i < n && cs[i] != '\n' {
        i = i + 1
      }
    } else if is_ident_start(c) {
      let sb = StringBuilder::new()
      while i < n && is_ident_char(cs[i]) {
        sb.write_char(cs[i])
        i = i + 1
      }
      out.push({ tok: Id(sb.to_string()), line, bol })
      bol = false
    } else if c == '"' {
      let sb = StringBuilder::new()
      i = i + 1
      while i < n && cs[i] != '"' {
        if cs[i] == '\\' && i + 1 < n {
          sb.write_char(cs[i])
          i = i + 1
        }
        sb.write_char(cs[i])
        i = i + 1
      }
      i = i + 1
      out.push({ tok: Str(sb.to_string()), line, bol })
      bol = false
    } else if c == '\'' {
      let sb = StringBuilder::new()
      sb.write_char(c)
      i = i + 1
      while i < n && cs[i] != '\'' && cs[i] != '\n' {
        if cs[i] == '\\' && i + 1 < n {
          sb.write_char(cs[i])
          i = i + 1
        }
        sb.write_char(cs[i])
        i = i + 1
      }
      sb.write_char('\'')
      i = i + 1
      out.push({ tok: Lit(sb.to_string()), line, bol })
      bol = false
    } else if c.is_ascii_digit() {
      let sb = StringBuilder::new()
      while i < n &&
            (is_ident_char(cs[i]) ||
            (cs[i] == '.' && i + 1 < n && cs[i + 1] != '.')) {
        sb.write_char(cs[i])
        i = i + 1
      }
      out.push({ tok: Lit(sb.to_string()), line, bol })
      bol = false
    } else {
      let mut sym = String::make(1, c)
      if i + 1 < n {
        let two = String::from_array([c, cs[i + 1]])
        if two_char_syms.contains(two) {
          sym = two
        }
      }
      i = i + sym.length()
      out.push({ tok: Sym(sym), line, bol })
      bol = false
    }
  }
  out.push({ tok: Eof, line, bol: true })
  out
}
