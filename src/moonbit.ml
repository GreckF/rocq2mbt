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
      (* runtime support of the generated code *)
      "RocqAny"; "RocqLazy"; "rocq_magic"; "rocq_lazy"; "rocq_force" ])
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
    pp_global_str table Type r ^ "[" ^ String.concat ", " (List.map (pp_type table) l) ^ "]"
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

let shapes : (global * shape) list GlobRef.Map.t ref = ref GlobRef.Map.empty

let find_shape r =
  try
    let l = GlobRef.Map.find r.glob !shapes in
    snd (List.find (fun (r', _) -> InfvInst.equal r.inst r'.inst) l)
  with Not_found -> Value

let add_shape r s =
  let l = try GlobRef.Map.find r.glob !shapes with Not_found -> [] in
  shapes := GlobRef.Map.add r.glob ((r, s) :: l) !shapes

let compute_shape ~in_fix r a t =
  if is_custom r then (if type_maxvar t > 0 then Thunk else Value)
  else
    let n = min (nb_lams a) (nb_arrows t) in
    if n > 0 then Func n
    else if in_fix || type_maxvar t > 0 then Thunk
    else Value

let rec register_decl = function
  | Dterm (r, a, t) -> add_shape r (compute_shape ~in_fix:false r a t)
  | Dfix (rv, defs, typs) ->
    Array.iteri (fun i r -> add_shape r (compute_shape ~in_fix:true r defs.(i) typs.(i))) rv
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
  | MLglob r -> (match find_shape r with Thunk -> false | _ -> true)
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
      let v = match args with
        | [] -> [head]
        | _ -> call [head] (List.map (pp_expr table env) args)
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
    call (paren [find_custom_match pv])
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
  | MLuint _ -> ["abort(\"EXTRACTION OF UINT NOT IMPLEMENTED\")"]
  | MLfloat _ -> ["abort(\"EXTRACTION OF FLOAT NOT IMPLEMENTED\")"]
  | MLstring s -> [string_lit (Pstring.to_string s)]
  | MLparray _ -> ["abort(\"EXTRACTION OF ARRAY NOT IMPLEMENTED\")"]

(* A global used as a value (not applied). *)
and pp_global_value table env r : code =
  if is_inline_custom r then [find_custom r]
  else
    let name = Common.pp_global table Term r in
    match find_shape r with
    | Value -> [name]
    | Thunk -> [name ^ "()"]
    | Func n ->
      let xs, _ = fresh_names env "x" n in
      curried_lams xs [name ^ "(" ^ String.concat ", " xs ^ ")"]

and pp_app table env f args : code =
  let curried head args =
    List.fold_left (fun h a -> call h [a]) head (List.map (pp_expr table env) args)
  in
  match f with
  | MLglob r when not (is_inline_custom r) ->
    let name = Common.pp_global table Term r in
    begin match find_shape r with
      | Func n when List.length args >= n ->
        let now, later = CList.chop n args in
        curried (call [name] (List.map (pp_expr table env) now)) later
      | Func n ->
        (* partial application: bind non-trivial arguments, then eta-expand *)
        let k = List.length args in
        let bound, env1 = fresh_names env "a" k in
        let lets, actuals =
          List.split (List.map2 (fun a x ->
              if is_simple a then [], pp_expr table env a
              else [["let " ^ x ^ " = "] ^^ pp_expr table env a], [x])
              args bound)
        in
        let xs, _ = fresh_names env1 "x" (n - k) in
        let body = curried_lams xs (call [name] (actuals @ List.map (fun x -> [x]) xs)) in
        let lets = List.concat lets in
        if List.is_empty lets then body else block (lets @ [body])
      | Thunk -> curried [name ^ "()"] args
      | Value -> curried [name] args
    end
  | MLfix (i, ids, defs) ->
    (* [(fix f x := ..) a] becomes [{ letrec f = ..; f(a) }] *)
    let ids', env' = push (List.rev (Array.to_list ids)) env in
    let names = Array.of_list (List.rev ids') in
    let stmts = pp_fix table env' names defs in
    let last = curried (pp_expr table env' (MLrel (Array.length defs - i))) args in
    block (stmts @ [last])
  | MLglob _ | MLrel _ | MLapp _ | MLmagic _ -> curried (pp_expr table env f) args
  | _ -> curried (paren (pp_expr table env f)) args

and pp_branch table env (ids, p, body) : code =
  let ids', env' = push (List.rev_map id_of_mlid ids) env in
  pp_pattern table (List.rev ids') env' p ^^ [" => "] ^^ pp_expr table env' body

and pp_pattern table ids env p : code =
  let cons r = function
    | [] -> [pp_cons table r]
    | l -> call [pp_cons table r] l
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
  let cons i tys =
    let c = Common.pp_global table Cons p.ip_consnames_ref.(i) in
    match tys with
    | [] -> c
    | _ -> c ^ "(" ^ String.concat ", " (List.map (pp_type table) tys) ^ ")"
  in
  let cs = Array.to_list (Array.mapi cons p.ip_types) in
  if List.is_empty cs then ["pub(all) enum " ^ name ^ generics ntv ^ " {}"]
  else ["pub(all) enum " ^ name ^ generics ntv ^ " {"] @ indent 2 cs @ ["}"]

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

(* A top-level term definition. *)
let pp_def table r a t : code =
  let name = Common.pp_global table Term r in
  let gen = generics (type_maxvar t) in
  if is_custom r then
    match find_shape r with
    | Thunk -> ["pub fn" ^ gen ^ " " ^ name ^ "() -> " ^ pp_type table t ^ " { " ^ find_custom r ^ " }"]
    | _ -> ["pub let " ^ name ^ " : " ^ pp_type table t ^ " = " ^ find_custom r]
  else
    let env = empty_env table () in
    match find_shape r with
    | Value -> (["pub let " ^ name ^ " : " ^ pp_type table t ^ " = "] ^^ pp_expr table env a)
    | Thunk ->
      ["pub fn" ^ gen ^ " " ^ name ^ "() -> " ^ pp_type table t ^ " "]
      ^^ block ~force:true [pp_body table env a]
    | Func n ->
      let ids, body = collect_n_lams n a in
      let ids, env' = push (List.map id_of_mlid ids) env in
      let tys, res = split_arrows n t in
      let params = List.map2 (fun id ty -> Id.to_string id ^ " : " ^ pp_type table ty)
          (List.rev ids) tys in
      ["pub fn" ^ gen ^ " " ^ name ^ "(" ^ String.concat ", " params ^ ") -> "
       ^ pp_type table res ^ " "]
      ^^ block ~force:true [pp_body table env' body]

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
