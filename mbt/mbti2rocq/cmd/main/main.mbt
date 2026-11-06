// mbti2rocq: generate Rocq axioms from a MoonBit interface file.
//
//   mbti2rocq <input.mbti> [-o <Output.v>] [--alias <@pkg>]

///|
fn usage() -> Unit {
  println("usage: mbti2rocq <input.mbti> [-o <Output.v>] [--alias <@pkg>]")
}

///|
fn main {
  let args = @env.args()
  let mut input : String? = None
  let mut output : String? = None
  let mut pkg_alias : String? = None
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "-o" if i + 1 < args.length() => {
        output = Some(args[i + 1])
        i = i + 2
      }
      "--alias" if i + 1 < args.length() => {
        pkg_alias = Some(args[i + 1])
        i = i + 2
      }
      "-h" | "--help" => {
        usage()
        return
      }
      a => {
        input = Some(a)
        i = i + 1
      }
    }
  }
  guard input is Some(path) else {
    usage()
    panic()
  }
  let src = @fs.read_file_to_string(path) catch {
    e => {
      ignore(e)
      println("mbti2rocq: cannot read \{path}")
      panic()
    }
  }
  let iface = @lib.parse(src)
  let v = match pkg_alias {
    Some(a) => @lib.generate(iface, palias=a, source=path)
    None => @lib.generate(iface, source=path)
  }
  match output {
    Some(o) =>
      @fs.write_string_to_file(o, v) catch {
        e => {
          ignore(e)
          println("mbti2rocq: cannot write \{o}")
          panic()
        }
      }
    None => println(v)
  }
}
