(* Interop tables of the MoonBit backend, filled by the commands

     Extract MoonBit Function f [n] => "template".
     Extract MoonBit Trait C => "@pkg.Trait".
     Extract MoonBit Raise f.

   They are stored in libobjects, so they survive [Require]. *)

open Names

type extern_fun = {
  arity : int option;   (* number of non-dictionary arguments *)
  template : string;    (* MoonBit code, [$i] = i-th non-dictionary argument *)
}

let funs : extern_fun GlobRef.Map.t Summary.Ref.t =
  Summary.ref ~name:"rocq2mbt-functions" GlobRef.Map.empty

let traits : string GlobRef.Map.t Summary.Ref.t =
  Summary.ref ~name:"rocq2mbt-traits" GlobRef.Map.empty

let raises : GlobRef.Set.t Summary.Ref.t =
  Summary.ref ~name:"rocq2mbt-raises" GlobRef.Set.empty

open Summary.Ref

let find_fun r = GlobRef.Map.find_opt r !funs
let find_trait r = GlobRef.Map.find_opt r !traits
let is_raise r = GlobRef.Set.mem r !raises

let subst_ref s r = fst (Globnames.subst_global s r)

let in_fun : GlobRef.t * extern_fun -> Libobject.obj =
  Libobject.declare_object @@
  Libobject.superglobal_object_nodischarge "MoonBit Function"
    ~cache:(fun (r, f) -> funs := GlobRef.Map.add r f !funs)
    ~subst:(Some (fun (s, (r, f)) -> (subst_ref s r, f)))

let in_trait : GlobRef.t * string -> Libobject.obj =
  Libobject.declare_object @@
  Libobject.superglobal_object_nodischarge "MoonBit Trait"
    ~cache:(fun (r, p) -> traits := GlobRef.Map.add r p !traits)
    ~subst:(Some (fun (s, (r, p)) -> (subst_ref s r, p)))

let in_raise : GlobRef.t -> Libobject.obj =
  Libobject.declare_object @@
  Libobject.superglobal_object_nodischarge "MoonBit Raise"
    ~cache:(fun r -> raises := GlobRef.Set.add r !raises)
    ~subst:(Some (fun (s, r) -> subst_ref s r))

let extract_function qid arity template =
  let r = Smartlocate.global_with_alias qid in
  (match r with
   | GlobRef.ConstRef _ -> ()
   | _ -> CErrors.user_err Pp.(str "Extract MoonBit Function expects a constant."));
  Extraction_plugin.Table.extract_constant_inline true qid [] template;
  Lib.add_leaf (in_fun (r, { arity; template }))

let extract_trait qid path =
  let r = Smartlocate.global_with_alias qid in
  Lib.add_leaf (in_trait (r, path))

let extract_raise qid =
  let r = Smartlocate.global_with_alias qid in
  Lib.add_leaf (in_raise r)
