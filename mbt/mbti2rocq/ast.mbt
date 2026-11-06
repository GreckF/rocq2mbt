// Abstract syntax of the subset of .mbti files we understand.

///|
pub(all) enum Ty {
  /// A (possibly package-qualified) type constructor, e.g. `Int`,
  /// `@json.Json`, `Self`, `Array[A]`.
  TName(String, Array[Ty])
  TTuple(Array[Ty])
  /// Function type: parameters, result, effect.
  TFun(Array[Ty], Ty, Effect)
  /// Trait object `&Trait`.
  TObj(String)
} derive(Eq, Debug)

///|
pub(all) enum Effect {
  NoRaise
  Raise(Ty) // raise E (`raise` alone is `raise Error`)
  RaisePoly // raise?
} derive(Eq, Debug)

///|
pub(all) struct Param {
  label : String? // `x~ : T` / `x? : T`
  optional : Bool // `x? : T`
  ty : Ty
} derive(Eq, Debug)

///|
/// Type parameters with their trait bounds: `[A, B : Show + Eq]`.
pub(all) struct TParam {
  name : String
  bounds : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct FnDecl {
  tparams : Array[TParam]
  owner : String? // `T` in `fn T::m(..)`
  name : String
  params : Array[Param]
  ret : Ty
  effect : Effect
  is_async : Bool
} derive(Eq, Debug)

///|
pub(all) struct CtorArg {
  label : String?
  is_mut : Bool
  ty : Ty
} derive(Eq, Debug)

///|
pub(all) struct Ctor {
  name : String
  args : Array[CtorArg]
} derive(Eq, Debug)

///|
pub(all) struct Field {
  name : String
  is_mut : Bool
  ty : Ty
} derive(Eq, Debug)

///|
pub(all) enum TypeKind {
  Abstract
  Enum(Array[Ctor])
  ErrorType(Array[Ctor])
  /// fields; `all` = constructible (`pub(all)`), `private` = has private fields
  Struct(Array[Field], Bool, Bool)
  Alias(Ty)
} derive(Eq, Debug)

///|
pub(all) struct TraitMethod {
  name : String
  params : Array[Ty]
  ret : Ty
} derive(Eq, Debug)

///|
pub(all) enum Decl {
  DFn(FnDecl)
  DValue(String, Ty) // pub let / pub const
  DType(String, Array[String], TypeKind, Bool) // name, params, kind, pub(all)
  DTrait(String, Array[TraitMethod])
  DImpl(Array[TParam], String, Ty) // tparams, trait, for type
  /// A declaration we could not parse: line number and reason.
  DSkipped(Int, String)
} derive(Eq, Debug)

///|
pub(all) struct Interface {
  pkg : String
  decls : Array[Decl]
} derive(Debug)
