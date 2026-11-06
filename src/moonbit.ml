(* MoonBit backend for Rocq extraction.

   Translation scheme (see README.md for the user-facing description):

   - Inductive types become [pub(all) enum]s, with constructors always
     qualified ([Nat::S(n)]).  Type parameters are printed positionally as
     [A], [B], ...  Singleton inductives become type aliases.  Coinductive
     types [T] become an enum [TCell] plus [type T = RocqLazy[TCell]].
   - Top-level functions are uncurried: a definition with [n] leading
     lambdas (bounded by the arrows of its type) becomes a MoonBit function
     of [n] parameters.  Call sites with at least [n] arguments call it
     directly; partial applications and bare references are eta-expanded
     into curried closures.  Every function-typed *value* is a curried
     one-argument closure [(A) -> B].
   - Top-level constants of polymorphic type (and non-function fixpoints)
     become zero-argument generic functions, referenced as [c()].
   - [Obj.magic] is [rocq_magic], a ["%identity"] primitive.  This only works
     on backends with a uniform value representation (tested: wasm; it fails
     on wasm-gc and native); a warning is emitted when it is needed.
   - Custom constants ([Extract Constant]) are MoonBit expressions of the
     curried extracted type.  Custom matches ([Extract Inductive ... "m"])
     are MoonBit functions taking one uncurried function per branch and
     finally the scrutinee: [m(fn(..) {..}, ..., e)]. *)

open Names
open Extraction_plugin
open Miniml
open Mlutil
open Table
open Common

(*s Lexical conventions *)

let keywords =
  List.fold_right (fun s -> Id.Set.add (Id.of_string s))
    ([ (* keywords *)
      "as"; "else"; "extern"; "fn"; "if"; "let"; "const"; "match"; "using";
      "mut"; "type"; "struct"; "enum"; "extenum"; "trait"; "derive"; "while";
      "break"; "continue"; "import"; "return"; "throw"; "raise"; "try";
      "catch"; "pub"; "priv"; "proof_assert"; "proof_let"; "readonly";
      "true"; "false"; "_"; "test"; "loop"; "for"; "in"; "impl"; "with";
      "guard"; "async"; "is"; "suberror"; "and"; "letrec"; "enumview";
      "noraise"; "nocancel"; "defer"; "lexmatch"; "lexscan"; "where";
      "declare"; "nobreak"; "extend"; "typealias"; "traitalias"; "fnalias";
      "init"; "main"; "self"; "Self"; "__";
      (* reserved words *)
      "module"; "move"; "ref"; "static"; "super"; "unsafe"; "use"; "await";
      "dyn"; "abstract"; "do"; "final"; "macro"; "override"; "typeof";
      "virtual"; "yield"; "local"; "method"; "alias"; "assert"; "package";
      "recur"; "isnot"; "define"; "downcast"; "inherit"; "member";
      "namespace"; "upcast"; "void"; "lazy"; "include"; "mixin"; "protected";
      "sealed"; "constructor"; "atomic"; "volatile"; "anyframe"; "anytype";
      "asm"; "comptime"; "errdefer"; "export"; "opaque"; "orelse"; "resume";
      "threadlocal"; "unreachable"; "dynclass"; "dynobj"; "dynrec"; "var";
      "finally"; "noasync"; "assume";
      (* builtin types and functions we must not shadow *)
      "Int"; "Int16"; "Int64"; "UInt"; "UInt16"; "UInt64"; "Byte"; "Bool";
      "Char"; "String"; "Double"; "Float"; "Unit"; "Bytes"; "Array";
      "FixedArray"; "Option"; "Result"; "Ref"; "Map"; "Error"; "Json";
      "abort"; "panic"; "ignore"; "not"; "println"; "print"; "physical_equal";
      "Eq"; "Compare"; "Show"; "Hash"; "Default"; "Debug"; "ToJson"; "FromJson";
      "Logger"; "Hasher"; "Add"; "Sub"; "Mul"; "Div"; "Neg"; "Mod"; "BitAnd"; "BitOr";
      "BitXOr"; "Shl"; "Shr"; "Iter"; "Iter2"; "ArrayView"; "StringView"; "BytesView";
      (* runtime support of the generated code *)
      "RocqAny"; "RocqLazy"; "rocq_magic"; "rocq_lazy"; "rocq_force";
      "rocq_result"; "rocq_v"; "rocq_e"; "rocqrt" ])
    Id.Set.empty

let unquote s = String.map (fun c -> if c == '\'' then '_' else c) s

(* Local names are not passed through [unquote] by [Common]. *)
let sanitize id =
  let s = Id.to_string id in
  if String.contains s '\'' then Id.of_string (unquote s) else id

let push ids env = push_vars (List.map sanitize ids) env

(*s Things the preamble needs, discovered during the dry run. *)

let need_magic = ref false
let need_any = ref false
let need_lazy = ref false

(*s Tiny layout engine.  A [code] is a non-empty list of lines; the first line
    continues the current line, the following ones are indented relative to
    the enclosing statement. *)

type code = string list

let rec ( ^^ ) (a : code) (b : code) : code = match a, b with
  | [], b -> b
  | a, [] -> a
  | [x], y :: ys -> (x ^ y) :: ys
  | x :: xs, b -> x :: (xs ^^ b)

let indent n (c : code) : code =
  let pre = String.make n ' ' in
  List.map (fun s -> if String.equal s "" then s else pre ^ s) c

let is_one_line = function [_] -> true | _ -> false

let concat_with sep (cs : code list) : code = match cs with
  | [] -> [""]
  | c :: cs -> List.fold_left (fun acc c -> acc ^^ [sep] ^^ c) c cs

let short_limit = 70

(* A block of statements [{ s1; ...; sn }]. *)
let block ?(force=false) (stmts : code list) : code =
  let width = List.fold_left (fun n c -> n + String.length (List.hd c) + 2) 0 stmts in
  if not force && List.for_all is_one_line stmts && width <= short_limit then
    ["{ " ^ String.concat "; " (List.map List.hd stmts) ^ " }"]
  else ["{"] @ indent 2 (List.concat stmts) @ ["}"]

let paren c = ["("] ^^ c ^^ [")"]

let call (head : code) (args : code list) : code =
  head ^^ ["("] ^^ concat_with ", " args ^^ [")"]

let to_pp (c : code) =
  Pp.(v 0 (prlist_with_sep fnl str c))

(*s String and char literals *)

let escape_char ~quote c =
  match c with
  | '\\' -> "\\\\"
  | '\n' -> "\\n"
  | '\t' -> "\\t"
  | '\r' -> "\\r"
  | '\b' -> "\\b"
  | c when c == quote -> "\\" ^ String.make 1 c
  | c when Char.code c < 32 || Char.code c >= 127 ->
    Printf.sprintf "\\u{%x}" (Char.code c)
  | c -> String.make 1 c

(* Rocq strings are byte strings, MoonBit strings are Unicode.  Valid UTF-8 is
   kept as is; otherwise every non-ASCII byte becomes one code unit. *)
let string_lit s =
  let utf8 = String.is_valid_utf_8 s in
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (fun c ->
      if utf8 && Char.code c >= 128 then Buffer.add_char b c
      else Buffer.add_string b (escape_char ~quote:'"' c)) s;
  Buffer.add_char b '"';
  Buffer.contents b

let char_lit c = "'" ^ escape_char ~quote:'\'' c ^ "'"

let float_lit f =
  match Float64.to_hex_string f with
  | "nan" -> "(0.0 / 0.0)"
  | "infinity" -> "(1.0 / 0.0)"
  | "neg_infinity" -> "(-1.0 / 0.0)"
  | s ->
    (* OCaml prints 0x1.8p+3, MoonBit wants 0x1.8p3 *)
    let b = Buffer.create (String.length s) in
    String.iteri (fun i c ->
        if not (c = '+' && i > 0 && s.[i - 1] = 'p') then Buffer.add_char b c) s;
    let s = Buffer.contents b in
    (* MoonBit needs a fractional part: 0x1p3 -> 0x1.0p3 *)
    let s = match String.index_opt s 'p' with
      | Some i when not (String.contains s '.') ->
        String.sub s 0 i ^ ".0" ^ String.sub s i (String.length s - i)
      | _ -> s
    in
    if s.[0] = '-' then "(" ^ s ^ ")" else s

(*s Type variables are named positionally: A, B, ..., Z, A1, ..., skipping
    the names of types occurring in the extracted code (collected during the
    dry run). *)

let type_names = ref CString.Set.empty

let tvar i =
  let candidate k =
    let letter = String.make 1 (Char.chr (65 + k mod 26)) in
    if k < 26 then letter else letter ^ string_of_int (k / 26)
  in
  let rec find i k =
    let c = candidate k in
    if CString.Set.mem c !type_names then find i (k + 1)
    else if i = 1 then c else find (i - 1) (k + 1)
  in
  find i 0

let tvars n = List.init n (fun i -> tvar (i + 1))

let generics = function
  | 0 -> ""
  | n -> "[" ^ String.concat ", " (tvars n) ^ "]"

(*s Global names *)

let pp_global_str table k r =
  let s = if is_inline_custom r then find_custom r else Common.pp_global table k r in
  if k == Type then type_names := CString.Set.add s !type_names;
  s

let ind_of_cons r = match r.glob with
  | GlobRef.ConstructRef (ind, _) -> { r with glob = GlobRef.IndRef ind }
  | _ -> assert false

let cell_name name = name ^ "Cell"

(* The (qualified) name of a constructor, e.g. [Nat::S]. *)
let pp_cons table r =
  if is_inline_custom r then find_custom r
  else
    let ty = pp_global_str table Type (ind_of_cons r) in
    let ty = if is_coinductive (State.get_table table) r then cell_name ty else ty in
    ty ^ "::" ^ Common.pp_global table Cons r

(*s Types *)

(* MoonBit forbids [type T[A] = A]: such aliases (from definitions or
   singleton inductives) are expanded at their use sites instead. *)
let inline_aliases : ml_type GlobRef.Map.t ref = ref GlobRef.Map.empty

let is_inline_alias r = GlobRef.Map.mem r.glob !inline_aliases

let rec pp_type table t : string =
  match t with
  | Tmeta _ | Tvar' _ -> assert false
  | Tvar i -> tvar i
  | Tglob (gr, l) when not (keep_singleton ()) && Rocqlib.check_ref sig_type_name gr.glob ->
    pp_type table (List.hd l)
  | Tglob (r, l) when is_inline_alias r ->
    pp_type table (type_subst_list l (GlobRef.Map.find r.glob !inline_aliases))
  | Tglob (r, []) -> pp_global_str table Type r
  | Tglob (r, l) ->
    let s = pp_global_str table Type r in
    if String.equal s "(,)" then "(" ^ String.concat ", " (List.map (pp_type table) l) ^ ")"
    else s ^ "[" ^ String.concat ", " (List.map (pp_type table) l) ^ "]"
  | Tarr (t1, t2) -> "(" ^ pp_type table t1 ^ ") -> " ^ pp_type table t2
  | Tdummy _ -> "Unit"
  | Tunknown -> need_any := true; "RocqAny"
  | Taxiom -> need_any := true; "RocqAny"

(* Split [t] into its first [n] argument types and the result type. *)
let rec split_arrows n t =
  if n = 0 then [], t
  else match t with
    | Tarr (a, b) -> let args, r = split_arrows (n - 1) b in a :: args, r
    | _ -> assert false

let rec nb_arrows = function Tarr (_, b) -> 1 + nb_arrows b | _ -> 0

(*s How top-level definitions are compiled; filled for the whole structure
    before printing. *)

type shape =
  | Value              (* [pub let c : T = ...], referenced as [c] *)
  | Thunk              (* [pub fn[..] c() -> T], referenced as [c()] *)
  | Func of int        (* [pub fn f(x1, .., xn) -> T], n >= 1 *)
  | Extern of extern   (* realized by [Extract MoonBit Function] *)

and extern = {
  template : string;
  dicts : bool list;   (* one entry per consumed argument: is it a dictionary? *)
}

(*s Call templates: [$i] is the i-th (non-dictionary) argument. *)

type piece = Lit of string | Arg of int

let parse_template s : piece list =
  let n = String.length s in
  let buf = Buffer.create n in
  let out = ref [] in
  let flush () =
    if Buffer.length buf > 0 then (out := Lit (Buffer.contents buf) :: !out; Buffer.clear buf) in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '$' && !i + 1 < n && '0' <= s.[!i + 1] && s.[!i + 1] <= '9' then begin
      flush ();
      let j = ref (!i + 1) in
      while !j < n && '0' <= s.[!j] && s.[!j] <= '9' do incr j done;
      out := Arg (int_of_string (String.sub s (!i + 1) (!j - !i - 1))) :: !out;
      i := !j
    end else (Buffer.add_char buf s.[!i]; incr i)
  done;
  flush ();
  List.rev !out

let has_placeholder s = List.exists (function Arg _ -> true | Lit _ -> false) (parse_template s)

let template_arity s =
  List.fold_left (fun m p -> match p with Arg i -> max m (i + 1) | Lit _ -> m) 0 (parse_template s)

(* Arguments may be duplicated or delayed by the template: bind them first. *)
let template_needs_binding s =
  let args = List.filter_map (function Arg i -> Some i | Lit _ -> None) (parse_template s) in
  let rec has_fn i = i + 3 <= String.length s && (String.equal (String.sub s i 3) "fn(" || has_fn (i + 1)) in
  List.length args <> List.length (List.sort_uniq compare args) || has_fn 0

(* Does this expression need parentheses before a postfix [(..)], [.f] or
   [[..]]?  Yes for multi-line code, closures, blocks, and anything with a
   space or a leading minus at nesting depth 0. *)
let needs_paren_postfix (c : code) =
  match c with
  | [l] ->
    let n = String.length l in
    let starts p = n >= String.length p && String.equal (String.sub l 0 (String.length p)) p in
    if n = 0 || starts "fn(" || starts "fn " || starts "{" || starts "-" then true
    else
      let depth = ref 0 and quoted = ref false and space = ref false in
      String.iteri (fun i ch ->
          if !quoted then (if ch = '"' && (i = 0 || l.[i - 1] <> '\\') then quoted := false)
          else match ch with
            | '"' -> quoted := true
            | '(' | '[' | '{' -> incr depth
            | ')' | ']' | '}' -> decr depth
            | ' ' when !depth = 0 -> space := true
            | _ -> ()) l;
      !space
  | _ -> true

(* A custom string used as the head of an application. *)
let paren_custom s = if needs_paren_postfix [s] then paren [s] else [s]

let apply_template s (args : code list) : code =
  let args = Array.of_list args in
  let rec go acc = function
    | [] -> acc
    | Lit l :: rest -> go (acc ^^ [l]) rest
    | Arg i :: rest ->
      if i >= Array.length args then
        CErrors.user_err Pp.(str "MoonBit template " ++ qs s ++ str " uses a missing argument.");
      let postfix = match rest with
        | Lit l :: _ -> String.length l > 0 && (l.[0] = '(' || l.[0] = '.' || l.[0] = '[')
        | _ -> false
      in
      let a = args.(i) in
      let a = if postfix && needs_paren_postfix a then paren a else a in
      go (acc ^^ a) rest
  in
  go [""] (parse_template s)

(* A constructor or constant given by a custom string, applied to [args]. *)
let custom_app s (args : code list) : code =
  if String.equal s "(,)" then paren (concat_with ", " args)
  else if has_placeholder s then apply_template s args
  else match args with [] -> [s] | _ -> call [s] args

let is_trait_type = function
  | Tglob (r, _) -> Option.has_some (Mbt_table.find_trait r.glob)
  | _ -> false

let extern_of_type (f : Mbt_table.extern_fun) t =
  let n = match f.arity with Some n -> n | None -> template_arity f.template in
  let rec go k t = match t with
    | Tarr (a, b) when is_trait_type a -> true :: go k b
    | _ when k = 0 -> []
    | Tarr (_, b) -> false :: go (k - 1) b
    | _ -> List.init k (fun _ -> false)
  in
  { template = f.template; dicts = go n t }

let shapes : (global * shape) list GlobRef.Map.t ref = ref GlobRef.Map.empty

let find_shape r =
  try
    let l = GlobRef.Map.find r.glob !shapes in
    snd (List.find (fun (r', _) -> InfvInst.equal r.inst r'.inst) l)
  with Not_found ->
    match Mbt_table.find_fun r.glob with
    | Some f ->
      let n = match f.arity with Some n -> n | None -> template_arity f.template in
      Extern { template = f.template; dicts = List.init n (fun _ -> false) }
    | None -> Value

let add_shape r s =
  let l = try GlobRef.Map.find r.glob !shapes with Not_found -> [] in
  shapes := GlobRef.Map.add r.glob ((r, s) :: l) !shapes

let compute_shape ~in_fix r a t =
  match Mbt_table.find_fun r.glob with
  | Some f -> Extern (extern_of_type f t)
  | None ->
  if is_custom r then (if type_maxvar t > 0 then Thunk else Value)
  else
    let n = min (nb_lams a) (nb_arrows t) in
    if n > 0 then Func n
    else if in_fix || type_maxvar t > 0 then Thunk
    else Value

(*s Functions extracted as [raise] functions ([Extract MoonBit Raise]). *)

let is_raise r = Mbt_table.is_raise r.glob

(* Inductive types used as error types of raise functions: printed as
   [suberror]s. *)
let error_types = ref GlobRef.Set.empty

let result_parts t = match t with
  | Tglob (r, [ok; err]) when Rocqlib.check_ref "rocq2mbt.result.type" r.glob -> Some (ok, err)
  | _ -> None

let raise_result r shape t =
  let n = match shape with Func n -> n | _ -> 0 in
  let _, res = split_arrows n t in
  match result_parts res with
  | Some p -> p
  | None ->
    CErrors.user_err Pp.(str "Extract MoonBit Raise: " ++ Printer.pr_global r.glob ++
                         str " must return a RocqMbt.Prelude.Result.")

let register_term ~in_fix r a t =
  let shape = compute_shape ~in_fix r a t in
  add_shape r shape;
  if is_raise r then begin
    (match shape with
     | Func _ | Thunk -> ()
     | _ -> CErrors.user_err Pp.(str "Extract MoonBit Raise: " ++ Printer.pr_global r.glob ++
                                 str " must be a function defined in Rocq."));
    match raise_result r shape t with
    | _, Tglob (e, []) when (match e.glob with GlobRef.IndRef _ -> true | _ -> false) ->
      error_types := GlobRef.Set.add e.glob !error_types
    | _ -> ()
  end

let rec register_decl = function
  | Dterm (r, a, t) -> register_term ~in_fix:false r a t
  | Dfix (rv, defs, typs) ->
    Array.iteri (fun i r -> register_term ~in_fix:true r defs.(i) typs.(i)) rv
  | Dind { ind_kind = Singleton; ind_packets = [| p |] }
    when not (p.ip_logical || is_custom p.ip_typename_ref) ->
    (match p.ip_types.(0) with
     | [Tvar _ as t] -> inline_aliases := GlobRef.Map.add p.ip_typename_ref.glob t !inline_aliases
     | _ -> ())
  | Dtype (r, _, (Tvar _ as t)) when not (is_custom r) ->
    inline_aliases := GlobRef.Map.add r.glob t !inline_aliases
  | Dind _ | Dtype _ -> ()

let rec register_struct_elem = function
  | (_, SEdecl d) -> register_decl d
  | (_, SEmodule { ml_mod_expr = MEstruct (_, sel) }) -> List.iter register_struct_elem sel
  | _ -> ()

(*s Expressions *)

(* Local fixpoints whose body is not a function are compiled to zero-argument
   closures; occurrences of their names must be forced with [()]. *)
let thunk_locals = ref Id.Set.empty

let rec is_simple = function
  | MLrel _ | MLdummy _ | MLstring _ | MLuint _ | MLfloat _ | MLlam _ -> true
  | MLglob r -> (match find_shape r with Thunk | Extern _ -> false | _ -> true)
  | MLcons (_, _, l) -> List.for_all is_simple l
  | MLmagic a -> is_simple a
  | _ -> false

let fresh_names env base n =
  let ids, env = push (List.init n (fun i -> Id.of_string (base ^ string_of_int (i + 1)))) env in
  List.map Id.to_string ids, env

(* [fn(x1) { fn(x2) { ... body } }] *)
let rec curried_lams names body = match names with
  | [] -> body
  | x :: xs -> ["fn(" ^ x ^ ") "] ^^ block [curried_lams xs body]

let rec pp_expr table env (e : ml_ast) : code =
  match e with
  | MLrel n ->
    let id = get_db_name n env in
    if Id.equal id dummy_name then ["()"]
    else if Id.Set.mem id !thunk_locals then [Id.to_string id ^ "()"]
    else [Id.to_string id]
  | MLapp (f, args) -> pp_app table env f args
  | MLlam _ ->
    let ids, body = collect_lams e in
    let ids, env' = push (List.map id_of_mlid ids) env in
    curried_lams (List.rev_map Id.to_string ids) (pp_body table env' body)
  | MLletin _ -> block (pp_stmts table env e)
  | MLglob r -> pp_global_value table env r
  | MLcons (_, r, args) as c ->
    if is_native_char c then [char_lit (get_native_char c)]
    else if is_native_string c then [string_lit (get_native_string c)]
    else
      let head = pp_cons table r in
      let args = List.map (pp_expr table env) args in
      let v = if is_inline_custom r then custom_app head args
        else match args with [] -> [head] | _ -> call [head] args
      in
      if is_coinductive (State.get_table table) r then begin
        need_lazy := true;
        ["rocq_lazy(fn() "] ^^ block [v] ^^ [")"]
      end else v
  | MLtuple l -> paren (concat_with ", " (List.map (pp_expr table env) l))
  | MLcase (_, t, pv) when is_custom_match pv ->
    if not (is_regular_match pv) then
      CErrors.user_err Pp.(str "Cannot mix yet user-given match and general patterns.");
    let branch (ids, _, body) =
      let ids, env' = push (List.rev_map id_of_mlid ids) env in
      ["fn(" ^ String.concat ", " (List.rev_map Id.to_string ids) ^ ") "]
      ^^ block [pp_body table env' body]
    in
    call (paren_custom (find_custom_match pv))
      (Array.to_list (Array.map branch pv) @ [pp_expr table env t])
  | MLcase (typ, t, pv) ->
    let scrut = pp_expr table env t in
    let scrut =
      if is_coinductive_type (State.get_table table) typ
      then (need_lazy := true; call ["rocq_force"] [scrut]) else scrut
    in
    if Array.length pv = 0 then
      (* empty match: the scrutinee inhabits an empty type *)
      ["abort(\"absurd case\")"]
    else
      let arms = Array.to_list (Array.map (pp_branch table env) pv) in
      (["match "] ^^ scrut ^^ [" {"]) @ indent 2 (List.concat arms) @ ["}"]
  | MLfix (i, ids, defs) ->
    let ids', env' = push (List.rev (Array.to_list ids)) env in
    let names = Array.of_list (List.rev ids') in
    let stmts = pp_fix table env' names defs in
    let last = pp_expr table env' (MLrel (Array.length defs - i)) in
    block (stmts @ [last])
  | MLexn s -> ["abort(" ^ string_lit s ^ ")"]
  | MLdummy _ -> ["()"]
  | MLaxiom s -> ["abort(" ^ string_lit ("AXIOM TO BE REALIZED (" ^ s ^ ")") ^ ")"]
  | MLmagic a -> need_magic := true; call ["rocq_magic"] [pp_expr table env a]
  | MLuint i -> [Uint63.to_string i ^ "UL"]
  | MLfloat f -> [float_lit f]
  | MLstring s -> [string_lit (Pstring.to_string s)]
  | MLparray (a, def) ->
    call ["@rocqrt.PArray::of_array"]
      [["["] ^^ concat_with ", " (Array.to_list (Array.map (pp_expr table env) a)) ^^ ["]"];
       pp_expr table env def]

(* A global used as a value (not applied). *)
and pp_global_value table env r : code =
  if is_inline_custom r && not (Option.has_some (Mbt_table.find_fun r.glob)) then [find_custom r]
  else pp_app table env (MLglob r) []

(* [try f(..) catch ..]: turns a raise function call back into a Result. *)
and wrap_try c =
  ["(try "] ^^ c ^^ [" catch { rocq_e => Result::Err(rocq_e) } noraise { rocq_v => Result::Ok(rocq_v) })"]

(* Call of a known function consuming [arity] arguments; [keep] selects
   those passed to [emit].  Missing arguments are eta-expanded; arguments
   are let-bound when [bind] says so (or for partial applications). *)
and pp_known_call table env ~arity ~keep ~emit ~bind ~raise_ args : code =
  let curried head args =
    List.fold_left (fun h a -> call h [pp_expr table env a]) head args
  in
  let k = List.length args in
  let now, later = if k >= arity then CList.chop arity args else args, [] in
  let bound, env1 = fresh_names env "a" (List.length now) in
  let lets, actuals =
    List.split (List.map2 (fun a x ->
        if (not bind && k >= arity) || is_simple a then [], pp_expr table env a
        else [["let " ^ x ^ " = "] ^^ pp_expr table env a], [x])
        now bound)
  in
  let xs, _ = fresh_names env1 "x" (max 0 (arity - k)) in
  let all = actuals @ List.map (fun x -> [x]) xs in
  let kept = List.filteri (fun i _ -> List.nth keep i) all in
  let res = emit kept in
  let res = if raise_ then wrap_try res else res in
  let body = curried_lams xs res in
  let body = if List.is_empty later then body else curried (paren body) later in
  let lets = List.concat lets in
  if List.is_empty lets then body else block (lets @ [body])

and pp_app table env f args : code =
  let curried head args =
    List.fold_left (fun h a -> call h [pp_expr table env a]) head args
  in
  match f with
  | MLglob r when not (is_inline_custom r) || Option.has_some (Mbt_table.find_fun r.glob) ->
    let raise_ = is_raise r in
    begin match find_shape r with
      | Extern e ->
        let n = List.length e.dicts in
        pp_known_call table env ~arity:n ~keep:(List.map not e.dicts)
          ~emit:(apply_template e.template)
          ~bind:(template_needs_binding e.template) ~raise_:false args
      | Func n ->
        let name = Common.pp_global table Term r in
        pp_known_call table env ~arity:n ~keep:(List.init n (fun _ -> true))
          ~emit:(fun kept -> call [name] kept) ~bind:false ~raise_ args
      | Thunk ->
        let name = Common.pp_global table Term r in
        let head = if raise_ then wrap_try [name ^ "()"] else [name ^ "()"] in
        curried (if raise_ && not (List.is_empty args) then paren head else head) args
      | Value -> curried [Common.pp_global table Term r] args
    end
  | MLglob r -> curried (paren_custom (find_custom r)) args
  | MLfix (i, ids, defs) ->
    (* [(fix f x := ..) a] becomes [{ letrec f = ..; f(a) }] *)
    let ids', env' = push (List.rev (Array.to_list ids)) env in
    let names = Array.of_list (List.rev ids') in
    let stmts = pp_fix table env' names defs in
    let last = curried (pp_expr table env' (MLrel (Array.length defs - i))) args in
    block (stmts @ [last])
  | MLrel _ | MLapp _ | MLmagic _ -> curried (pp_expr table env f) args
  | _ -> curried (paren (pp_expr table env f)) args

and pp_branch table env (ids, p, body) : code =
  let ids', env' = push (List.rev_map id_of_mlid ids) env in
  pp_pattern table (List.rev ids') env' p ^^ [" => "] ^^ pp_expr table env' body

and pp_pattern table ids env p : code =
  let cons r l =
    if is_inline_custom r then custom_app (pp_cons table r) l
    else match l with [] -> [pp_cons table r] | l -> call [pp_cons table r] l
  in
  match p with
  | Pusual r -> cons r (List.map (fun id -> [Id.to_string id]) ids)
  | Pcons (r, l) -> cons r (List.map (pp_pattern table ids env) l)
  | Ptuple l -> paren (concat_with ", " (List.map (pp_pattern table ids env) l))
  | Pwild -> ["_"]
  | Prel n -> [Id.to_string (get_db_name n env)]

(* [names] are already pushed in [env]. *)
and pp_fix table env names defs : code list =
  Array.iteri (fun i def -> match def with
      | MLlam _ -> ()
      | _ -> thunk_locals := Id.Set.add names.(i) !thunk_locals) defs;
  Array.to_list (Array.mapi (fun i def ->
      let kw = if i = 0 then "letrec " else "and " in
      let name = Id.to_string names.(i) in
      match def with
      | MLlam _ -> [kw ^ name ^ " = "] ^^ pp_expr table env def
      | _ -> [kw ^ name ^ " = fn() "] ^^ block [pp_body table env def])
      defs)

(* Statements of a block: flattens [let]s. *)
and pp_stmts table env e : code list =
  match e with
  | MLletin (id, a1, a2) ->
    let ids, env' = push [id_of_mlid id] env in
    let x = Id.to_string (List.hd ids) in
    (["let " ^ x ^ " = "] ^^ pp_expr table env a1) :: pp_stmts table env' a2
  | _ -> [pp_expr table env e]

and pp_body table env e : code = match e with
  | MLletin _ -> concat_lines (pp_stmts table env e)
  | _ -> pp_expr table env e

(* Several statements meant to be put into a block by [block]: we need them
   as one statement list.  [pp_body] is only used where the result goes into
   [block [..]], so we encode the statement sequence as lines. *)
and concat_lines stmts = List.concat stmts

(*s Declarations *)

let pp_logical_ind table p =
  ["// " ^ Id.to_string p.ip_typename ^ " : logical inductive, with constructors : "
   ^ String.concat " " (Array.to_list (Array.map Id.to_string p.ip_consnames))]

let pp_enum table ~name ~ntv p : code =
  let kw =
    if GlobRef.Set.mem p.ip_typename_ref.glob !error_types then begin
      if ntv > 0 || Array.length p.ip_types = 0 then
        CErrors.user_err Pp.(str "The error type " ++ str name ++
                             str " of a raise function must be non-empty and have no type parameters.");
      "pub(all) suberror "
    end else "pub(all) enum "
  in
  let cons i tys =
    let c = Common.pp_global table Cons p.ip_consnames_ref.(i) in
    match tys with
    | [] -> c
    | _ -> c ^ "(" ^ String.concat ", " (List.map (pp_type table) tys) ^ ")"
  in
  let cs = Array.to_list (Array.mapi cons p.ip_types) in
  if List.is_empty cs then [kw ^ name ^ generics ntv ^ " {}"]
  else [kw ^ name ^ generics ntv ^ " {"] @ indent 2 cs @ ["}"]

let pp_ind table ind : code list =
  Array.to_list ind.ind_packets |> List.filter_map (fun p ->
      if is_custom p.ip_typename_ref then None
      else if p.ip_logical then Some (pp_logical_ind table p)
      else
        let name = pp_global_str table Type p.ip_typename_ref in
        let ntv = List.length p.ip_vars in
        match ind.ind_kind with
        | Singleton when is_inline_alias p.ip_typename_ref ->
          Some ["// " ^ name ^ " : singleton inductive, expanded at use sites"]
        | Singleton ->
          Some (("pub type " ^ name ^ generics ntv ^ " = " ^ pp_type table (List.hd p.ip_types.(0)))
                :: ["// singleton inductive, whose constructor was "
                    ^ Id.to_string p.ip_consnames.(0)])
        | Coinductive ->
          need_lazy := true;
          let cell = cell_name name in
          type_names := CString.Set.add cell !type_names;
          Some (pp_enum table ~name:cell ~ntv p
                @ ["pub type " ^ name ^ generics ntv ^ " = RocqLazy[" ^ cell ^ generics ntv ^ "]"])
        | Standard | Record _ -> Some (pp_enum table ~name ~ntv p))

let pp_tdecl table r l t : code =
  if is_inline_custom r then []
  else
    let name = pp_global_str table Type r in
    try
      let ids, s = find_type_custom r in
      let ps = match ids with [] -> "" | _ -> "[" ^ String.concat ", " ids ^ "]" in
      ["pub type " ^ name ^ ps ^ " = " ^ s]
    with Not_found when is_inline_alias r ->
      ["// " ^ name ^ " : type alias to a type variable, expanded at use sites"]
    | Not_found ->
      let rhs = if t == Taxiom then pp_type table t ^ " // AXIOM TO BE REALIZED" else pp_type table t in
      ["pub type " ^ name ^ generics (List.length l) ^ " = " ^ rhs]

(* Type parameters, with the trait bounds required by the dictionaries
   ([Extract MoonBit Trait]) occurring in [t]. *)
let bounded_generics t =
  let n = type_maxvar t in
  if n = 0 then "" else
    let bounds = Array.make (n + 1) [] in
    let rec walk = function
      | Tglob (r, l) ->
        (match Mbt_table.find_trait r.glob, l with
         | Some path, Tvar i :: _ when i <= n && not (List.mem path bounds.(i)) ->
           bounds.(i) <- bounds.(i) @ [path]
         | _ -> ());
        List.iter walk l
      | Tarr (a, b) -> walk a; walk b
      | _ -> ()
    in
    walk t;
    "[" ^ String.concat ", " (List.init n (fun i ->
        let v = tvar (i + 1) in
        match bounds.(i + 1) with
        | [] -> v
        | bs -> v ^ " : " ^ String.concat " + " bs)) ^ "]"

(* Body of a raise function: unwrap the Rocq [Result]. *)
let raise_body (c : code) : code list = [
  ["let rocq_result = "] ^^ c;
  ["match rocq_result {"; "  Result::Ok(rocq_v) => rocq_v";
   "  Result::Err(rocq_e) => raise rocq_e"; "}"] ]

(* A top-level term definition. *)
let pp_def table r a t : code =
  let name = Common.pp_global table Term r in
  let gen = bounded_generics t in
  (* the bounds are needed by some uses of the dictionaries only *)
  let attr = if String.contains gen ':' then ["#warnings(\"-unused_trait_bound\")"] else [] in
  attr @ begin
  let ret res =
    if is_raise r then
      let ok, err = raise_result r (find_shape r) t in
      pp_type table ok ^ " raise " ^ pp_type table err
    else pp_type table res
  in
  let def_body env e =
    if is_raise r then raise_body (pp_expr table env e) else [pp_body table env e]
  in
  if is_custom r then
    match find_shape r with
    | Thunk -> ["pub fn" ^ gen ^ " " ^ name ^ "() -> " ^ pp_type table t ^ " { " ^ find_custom r ^ " }"]
    | _ -> ["pub let " ^ name ^ " : " ^ pp_type table t ^ " = " ^ find_custom r]
  else
    let env = empty_env table () in
    match find_shape r with
    | Value -> (["pub let " ^ name ^ " : " ^ pp_type table t ^ " = "] ^^ pp_expr table env a)
    | Thunk ->
      ["pub fn" ^ gen ^ " " ^ name ^ "() -> " ^ ret t ^ " "]
      ^^ block ~force:true (def_body env a)
    | Func n ->
      let ids, body = collect_n_lams n a in
      let ids, env' = push (List.map id_of_mlid ids) env in
      let tys, res = split_arrows n t in
      let params = List.map2 (fun id ty -> Id.to_string id ^ " : " ^ pp_type table ty)
          (List.rev ids) tys in
      ["pub fn" ^ gen ^ " " ^ name ^ "(" ^ String.concat ", " params ^ ") -> "
       ^ ret res ^ " "]
      ^^ block ~force:true (def_body env' body)
    | Extern _ -> []
  end

let pp_decl_code table d : code list =
  thunk_locals := Id.Set.empty;
  match d with
  | Dind ind -> pp_ind table ind
  | Dtype (r, l, t) -> (match pp_tdecl table r l t with [] -> [] | c -> [c])
  | Dterm (r, a, t) ->
    if is_inline_custom r then [] else [pp_def table r a t]
  | Dfix (rv, defs, typs) ->
    Array.to_list rv |> List.mapi (fun i r ->
        let void = is_inline_custom r ||
                   (not (is_custom r) && match defs.(i) with MLexn "UNUSED" -> true | _ -> false)
        in
        if void then [] else [pp_def table r defs.(i) typs.(i)])
    |> List.concat

let sep_decls (cs : code list) : code =
  List.concat (List.map (fun c -> c @ [""]) cs)

let pp_decl table d =
  register_decl d;
  to_pp (sep_decls (pp_decl_code table d))

let rec pp_structure_elem table = function
  | (_, SEdecl d) -> pp_decl_code table d
  | (_, SEmodule m) -> pp_module_expr table m.ml_mod_expr
  | (_, SEmodtype _) -> []

and pp_module_expr table = function
  | MEstruct (_, sel) -> List.concat_map (pp_structure_elem table) sel
  | MEfunctor _ -> [["// functor omitted: functors are not supported by MoonBit extraction"]]
  | MEident _ | MEapply _ -> assert false

let pp_struct table struc =
  if State.get_phase table == Pre then begin
    need_magic := false; need_any := false; need_lazy := false; type_names := CString.Set.empty;
    shapes := GlobRef.Map.empty; inline_aliases := GlobRef.Map.empty;
    error_types := GlobRef.Set.empty;
    List.iter (fun (_, sel) -> List.iter register_struct_elem sel) struc
  end;
  let pp_sel (mp, sel) =
    State.with_visibility table mp [] (fun table ->
        List.concat_map (pp_structure_elem table) sel)
  in
  to_pp (sep_decls (List.concat_map pp_sel struc))

(*s Preamble *)

let magic_warning () =
  Feedback.msg_warning
    Pp.(str "The extracted MoonBit code uses unsafe coercions (rocq_magic)." ++ spc () ++
        str "They only work on backends with a uniform value representation" ++ spc () ++
        str "(e.g. --target wasm); on wasm-gc and native they may be rejected or crash.")

let preamble table mod_name comment used_modules usf =
  if !need_magic then magic_warning ();
  let header = [
    "// Extracted from Rocq by rocq2mbt (MoonBit extraction).";
  ] in
  let comment = match comment with
    | None -> []
    | Some c -> List.map (fun l -> "// " ^ l) (String.split_on_char '\n' (Pp.string_of_ppcmds c))
  in
  let magic = if not !need_magic then [] else [
      "";
      "/// Unsafe coercion used where Rocq terms are not ML-typable.";
      "fn[A, B] rocq_magic(x : A) -> B = \"%identity\"";
    ] in
  let any = if not !need_any then [] else [
      "";
      "/// Placeholder for types that cannot be expressed in MoonBit.";
      "pub(all) struct RocqAny {}";
    ] in
  let lazy_ = if not !need_lazy then [] else [
      "";
      "/// Memoized suspension, used for coinductive types.";
      "pub struct RocqLazy[A] {";
      "  mut value : A?";
      "  mut thunk : (() -> A)?";
      "}";
      "";
      "fn[A] rocq_lazy(f : () -> A) -> RocqLazy[A] {";
      "  { value: None, thunk: Some(f) }";
      "}";
      "";
      "fn[A] rocq_force(l : RocqLazy[A]) -> A {";
      "  match l.value {";
      "    Some(v) => v";
      "    None => {";
      "      let v = (l.thunk.unwrap())()";
      "      l.value = Some(v)";
      "      l.thunk = None";
      "      v";
      "    }";
      "  }";
      "}";
    ] in
  let lines = header @ comment @ magic @ any @ lazy_ in
  Pp.(to_pp lines ++ fnl () ++ fnl ())

(*s Language description *)

let file_naming state mp = file_of_modfile (State.get_table state) mp

let id_of_filename f =
  try Id.of_string f
  with CErrors.UserError _ ->
    CErrors.user_err Pp.(str "Extraction: provided filename is not a valid identifier")

let moonbit_descr = {
  keywords;
  file_suffix = ".mbt";
  file_naming;
  preamble;
  pp_struct;
  sig_suffix = None;
  sig_preamble = (fun _ _ _ _ _ -> Pp.mt ());
  pp_sig = (fun _ _ -> Pp.mt ());
  pp_decl;
  unquote;
  upper_types = true;
  char_type = Some "Char";
  string_type = Some "String";
  modular = false;
  id_of_filename;
}
