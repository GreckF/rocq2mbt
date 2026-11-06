# rocq2mbt Installation and Usage Guide

[中文](USAGE.md) | **English**

This document explains how to install rocq2mbt and use it to do three things:

1. **Extract** Rocq programs into MoonBit code;
2. Use Rocq native types (63-bit integers, floats, persistent arrays, strings) and MoonBit
   built-in types in Rocq, and get the corresponding MoonBit types after extraction;
3. Use `mbti2rocq` to translate the interface (`.mbti`) of an existing MoonBit package into Rocq
   axioms, call MoonBit code from Rocq, and have extraction turn those back into calls to the original package.

All commands in this document are run in bash on Linux or WSL. `$ROCQ2MBT` refers to the root
directory of the rocq2mbt repository, for example:

```bash
export ROCQ2MBT=/path/to/rocq2mbt
```

---

## Table of contents

1. [Components](#1-components)
2. [Requirements](#2-requirements)
3. [Installation](#3-installation)
4. [Quick start 1: extracting a pure Rocq program](#4-quick-start-1-extracting-a-pure-rocq-program)
5. [Quick start 2: native types and MoonBit built-in types](#5-quick-start-2-native-types-and-moonbit-built-in-types)
6. [Quick start 3: calling a MoonBit package from Rocq](#6-quick-start-3-calling-a-moonbit-package-from-rocq)
7. [Extraction reference](#7-extraction-reference)
8. [Companion Rocq modules reference](#8-companion-rocq-modules-reference)
9. [Interop commands reference](#9-interop-commands-reference)
10. [mbti2rocq reference](#10-mbti2rocq-reference)
11. [Backend compatibility and limitations](#11-backend-compatibility-and-limitations)
12. [FAQ](#12-faq)
13. [Development and testing](#13-development-and-testing)

---

## 1. Components

| Component | Location | Purpose |
| --- | --- | --- |
| Rocq plugin `rocq-mbt.plugin` | `src/` | Registers the extraction language `MoonBit` and provides the `Extract MoonBit ...` commands |
| Rocq library `RocqMbt` | `theories/` | Four modules: `MoonBit`, `ExtrMoonBitBasic`, `ExtrMoonBitPrim`, `Prelude` |
| MoonBit runtime `GreckF/rocqrt` | `mbt/rocqrt/` | Implementation of native 63-bit integers, floats and persistent arrays; extracted code depends on it when it uses native types |
| MoonBit tool `mbti2rocq` | `mbt/mbti2rocq/` | `.mbti` → Rocq file |

## 2. Requirements

| Software | Version | Notes |
| --- | --- | --- |
| Linux or WSL2 | — | On Windows, work inside WSL |
| opam | ≥ 2.1 | Used to create a project-local switch |
| System build tools | gcc, make, git, curl, pkg-config, libgmp-dev | Needed to compile OCaml, zarith and Rocq |
| OCaml | 5.4.1 (installed automatically by the script) | Other versions ≥ 4.14 usually work too; select one with `OCAML_VERSION` |
| Rocq | 9.4+alpha, i.e. rocq master (installed automatically by the script) | See the note below |
| MoonBit toolchain | Tested on moonc v0.10.20 / moon 0.1.20261104 | Only needed to compile and run extracted code and `mbti2rocq` |

**About the Rocq version.** The plugin depends on Rocq's extensible extraction API (rocq-prover/rocq PR #22541,
merged 2026-10-05). The git tag `V9.4+alpha` was created on 2026-06-29 and does **not** contain this API.
So the installation script pins a commit on rocq master (whose version is also shown as `9.4+alpha`).
This commit is recorded in `ROCQ_COMMIT` in `scripts/setup-opam.sh`.

Installing the system dependencies on Ubuntu:

```bash
sudo apt install build-essential git curl pkg-config libgmp-dev opam
opam init        # the first time you use opam
```

Installing the MoonBit toolchain (into `~/.moon/bin`):

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

## 3. Installation

### 3.1 Create a local opam switch and install Rocq

```bash
cd $ROCQ2MBT
bash scripts/setup-opam.sh
```

The script does the following:

1. Creates a local switch in the project and installs `ocaml-base-compiler.5.4.1`.
   If the project is on a Windows drive (its path starts with `/mnt/`), compiling on the 9p file system is very slow,
   so the switch actually lives in `~/.local/share/rocq2mbt/_opam`, and a symbolic link `_opam`
   pointing to it is created in the project root.
2. Pins `rocq-runtime` and `rocq-core` to the rocq commit given by `ROCQ_COMMIT`, then installs them.
3. Finally prints `rocq --version`, which should show `The Rocq Prover, version 9.4+alpha`.

The whole process compiles OCaml and Rocq from scratch and takes roughly 15–40 minutes. The defaults can be changed with environment variables:

```bash
ROCQ_COMMIT=<commit on rocq master> OCAML_VERSION=5.3.0 bash scripts/setup-opam.sh
```

The script can be run repeatedly: an existing switch is not rebuilt, and the pins are updated.

### 3.2 Enter the environment

Run this every time you open a new shell:

```bash
source $ROCQ2MBT/scripts/env.sh
```

It switches to the local switch and adds `~/.moon/bin` to `PATH`.

### 3.3 Build the plugin and the Rocq library

```bash
cd $ROCQ2MBT
dune build
```

The build produces two things:

- `_build/install/default/lib/rocq-mbt/plugin/`: the plugin (findlib package name `rocq-mbt.plugin`);
- `_build/default/theories/`: the compiled Rocq library, logical path `RocqMbt`.

### 3.4 Using the plugin: two ways

**Option A: use the build directory directly without installing (recommended during development).** Set `OCAMLPATH` so that Rocq finds the plugin,
and map the Rocq library with `-Q`:

```bash
export OCAMLPATH=$ROCQ2MBT/_build/install/default/lib:$OCAMLPATH
rocq c -Q $ROCQ2MBT/_build/default/theories RocqMbt Foo.v
```

You can combine the two into a function:

```bash
rocq2mbt_c() {
  OCAMLPATH=$ROCQ2MBT/_build/install/default/lib:$OCAMLPATH \
    rocq c -Q $ROCQ2MBT/_build/default/theories RocqMbt "$@"
}
```

**Option B: install into the current switch.**

```bash
cd $ROCQ2MBT && dune install
```

Once installed, `rocq c Foo.v` can `From RocqMbt Require Import ...` directly, with no extra arguments.
After modifying the plugin, rerun `dune build && dune install`.

### 3.5 Build the MoonBit tool (optional)

Only needed if you use `mbti2rocq`:

```bash
cd $ROCQ2MBT/mbt/mbti2rocq
moon build --target native --release
# Executable:
ls _build/native/release/build/cmd/main/main.exe
```

For convenience, you can add an alias:

```bash
alias mbti2rocq=$ROCQ2MBT/mbt/mbti2rocq/_build/native/release/build/cmd/main/main.exe
```

`mbti2rocq` depends on `moonbitlang/x@0.5.7` (used to read and write files), which is downloaded automatically on the first build.
With an older toolchain such as moonc v0.10.8 (2026-08), use `moonbitlang/x@0.4.50` instead.

### 3.6 Verify the installation

```bash
cd $ROCQ2MBT && bash tests/run.sh
```

All tests should print `failed: 0`. Section 13 describes what exactly this script tests.

---

## 4. Quick start 1: extracting a pure Rocq program

This section does not need the MoonBit runtime. Create a new directory:

```bash
mkdir -p ~/hello/lib ~/hello/cmd/main && cd ~/hello
```

**Rocq program** `Hello.v`:

```coq
From RocqMbt Require Import ExtrMoonBitBasic.

Fixpoint fib (n : nat) : nat :=
  match n with
  | O => O
  | S p => match p with O => S O | S q => fib p + fib q end
  end.

Fixpoint map {A B} (f : A -> B) (l : list A) : list B :=
  match l with nil => nil | cons x t => cons (f x) (map f t) end.

Definition fibs (l : list nat) : list nat := map fib l.

Extraction "lib/hello.mbt" fib fibs.
```

`ExtrMoonBitBasic` loads the plugin, sets the extraction language to MoonBit, and maps `bool`, `option`,
`unit` and pairs to MoonBit's built-in `Bool`, `Option`, `Unit` and tuples.

**Extract:**

```bash
rocq2mbt_c Hello.v          # or, with option B: rocq c Hello.v
```

`lib/hello.mbt` looks roughly like this:

```moonbit
pub(all) enum Nat {
  O
  S(Nat)
}

pub fn add(n : Nat, m : Nat) -> Nat { ... }

pub fn fib(n : Nat) -> Nat {
  match n {
    Nat::O => Nat::O
    Nat::S(p) => match p {
      Nat::O => Nat::S(Nat::O)
      Nat::S(q) => add(fib(p), fib(q))
    }
  }
}

pub fn[A, B] map(f : (A) -> B, l : List[A]) -> List[B] { ... }

pub fn fibs(l : List[Nat]) -> List[Nat] {
  map(fn(x1) { fib(x1) }, l)
}
```

**MoonBit project.** Create three files:

`moon.mod`:

```text
name = "me/hello"

version = "0.1.0"
```

`lib/moon.pkg`: empty.

`cmd/main/moon.pkg`:

```text
import {
  "me/hello/lib" @lib,
}

pkgtype(kind: "executable")
```

`cmd/main/main.mbt`:

```moonbit
fn to_int(n : @lib.Nat) -> Int {
  match n {
    @lib.Nat::O => 0
    @lib.Nat::S(p) => 1 + to_int(p)
  }
}

fn of_int(i : Int) -> @lib.Nat {
  if i <= 0 { @lib.Nat::O } else { @lib.Nat::S(of_int(i - 1)) }
}

fn main {
  println(to_int(@lib.fib(of_int(10))))
}
```

Run:

```bash
moon run cmd/main --target native     # prints 55
```

Any of the `wasm-gc`, `wasm` and `native` backends works.

---

## 5. Quick start 2: native types and MoonBit built-in types

`Prelude` provides MoonBit built-in types (`Int`, `String`, `Array` ...), `Result`,
classes corresponding to traits, and includes the extraction setup for Rocq native types. When these are used, the extracted code depends on the runtime
package `GreckF/rocqrt`.

```bash
mkdir -p ~/prelude-demo/lib && cd ~/prelude-demo
```

`Demo.v`:

```coq
From RocqMbt Require Import Prelude.
From Corelib Require Import PrimInt63 PrimString PrimArray.

(* MoonBit Int: write literals with Int_of_uint63 *)
Definition i (n : PrimInt63.int) : Int := Int_of_uint63 n.

Definition area (w h : Int) : Int := Int_mul w h.

(* The type class Show is MoonBit's trait Show *)
Definition describe {A} `{Show A} (x : A) : String :=
  String_append (String_of_pstring "value = "%pstring) (to_string x).

(* Rocq native 63-bit integers and persistent arrays *)
Definition table : array PrimInt63.int := [| 1; 2; 3 | 0 |]%uint63.
Definition second : PrimInt63.int := table.[1].

(* A Rocq function returning Result, extracted to a MoonBit raise function *)
Inductive DemoError := Negative | TooLarge.
Definition checked (x : Int) : Result Int DemoError :=
  if Int_ltb x (i 0) then Err Negative
  else if Int_ltb (i 100) x then Err TooLarge
  else Ok x.
Extract MoonBit Raise checked.

(* Show_Int is a dictionary; it is only extracted if listed, and the MoonBit side needs it to call describe *)
Extraction "lib/demo.mbt" area describe Show_Int second checked.
```

Extract:

```bash
rocq2mbt_c Demo.v
```

The resulting MoonBit code contains:

```moonbit
#warnings("-unused_trait_bound")
pub fn[A : Show] describe(h : Show0[A], x : A) -> String { ... }   // A : Show added automatically

pub let table : Array0[UInt64] = @rocqrt.PArray::of_array([1UL, 2UL, 3UL], 0UL)
pub let second : UInt64 = @rocqrt.PArray::get(table, 1UL)

pub(all) suberror DemoError {
  Negative
  TooLarge
}

pub fn checked(x : Int) -> Int raise DemoError { ... }
```

Note: the error type must carry computational content. A type with a single constructor without arguments, such as `Inductive E := C.`, is
erased by extraction, and the plugin reports an error.

**The MoonBit project must be able to find `rocqrt`.** For local development, add the runtime module to the workspace with `moon.work`:

`moon.work`:

```text
members = [
  ".",
  "/path/to/rocq2mbt/mbt/rocqrt",
]
```

(For the second entry, write the actual path of `$ROCQ2MBT/mbt/rocqrt`; a relative path also works.)

`moon.mod`:

```text
name = "me/demo"

version = "0.1.0"

import {
  "GreckF/rocqrt@0.1.0",
}
```

`lib/moon.pkg`; the extracted package must import the runtime under the alias `@rocqrt`:

```text
import {
  "GreckF/rocqrt" @rocqrt,
}
```

Then you can run `moon check` / `moon test`, or use these functions from other packages. For example, in
`lib/demo_wbtest.mbt`:

```moonbit
test {
  assert_eq(area(3)(4), 12)                  // area is extracted as a curried value, see the explanation below
  assert_eq(describe(show_Int, 5), "value = 5")
  assert_eq(second, 2UL)
  assert_eq(checked(7), 7)
  let r : Result[Int, DemoError] = try checked(-1) catch { e => Err(e) } noraise { v => Ok(v) }
  assert_eq(r is Err(DemoError::Negative), true)
}
```

The definition of `area`, `fun w h => Int_mul w h`, is optimized by extraction into `Int_mul` itself, with no leading λ,
so it becomes the value `pub let area : (Int) -> (Int) -> Int`, and is called as `area(3)(4)`.
When the function body cannot be η-reduced (e.g. `describe`), you get an ordinary multi-parameter function.

---

## 6. Quick start 3: calling a MoonBit package from Rocq

Workflow:

```text
MoonBit package ──moon info──▶ pkg.generated.mbti ──mbti2rocq──▶ Geom.v (axioms + extraction directives)
                                                                   │
                               your Rocq program Use.v ◀── Require ┘
                                                   │ Extraction
                                                   ▼
                     extracted MoonBit code, calling the original MoonBit package directly
```

### 6.1 Prepare a MoonBit package

```bash
mkdir -p ~/interop/geom ~/interop/app && cd ~/interop
```

`moon.mod`:

```text
name = "me/interop"

version = "0.1.0"

import {
  "GreckF/rocqrt@0.1.0",
}
```

`moon.work`: same as in section 5, containing `"."` and the path of `rocqrt`.

`geom/moon.pkg`: empty. `geom/geom.mbt`:

```moonbit
pub(all) struct Vec {
  x : Double
  y : Double
}

pub fn Vec::add(self : Vec, other : Vec) -> Vec {
  { x: self.x + other.x, y: self.y + other.y }
}

pub fn Vec::norm(self : Vec) -> Double {
  (self.x * self.x + self.y * self.y).sqrt()
}

pub(all) enum Shape {
  Circle(center~ : Vec, r~ : Double)
  Poly(Array[Vec])
}

pub suberror GeomError {
  Degenerate(String)
  Empty
}

pub fn perimeter(s : Shape) -> Double raise GeomError {
  match s {
    Circle(r~, ..) => 2.0 * 3.141592653589793 * r
    Poly(ps) => {
      if ps.length() == 0 { raise Empty }
      if ps.length() < 2 { raise Degenerate("polygon") }
      let mut sum = 0.0
      for i in 0..<ps.length() {
        let a = ps[i]
        let b = ps[(i + 1) % ps.length()]
        sum = sum + Vec::norm({ x: b.x - a.x, y: b.y - a.y })
      }
      sum
    }
  }
}
```

### 6.2 Generate the interface and translate it to Rocq

```bash
moon info --target native -p me/interop/geom     # generates geom/pkg.generated.mbti
mbti2rocq geom/pkg.generated.mbti -o Geom.v
```

The generated `Geom.v` (excerpt):

```coq
From RocqMbt Require Import Prelude.

Record Vec : Type := Build_Vec { Vec_x : Double; Vec_y : Double }.
Extract Inductive Vec => "@geom.Vec" [ "@geom.Vec::{ x: $0, y: $1 }" ]
  "(fn(rocq_k, rocq_s : @geom.Vec) { rocq_k(rocq_s.x, rocq_s.y) })".
Inductive GeomError : Type :=
| Degenerate : String -> GeomError
| Empty : GeomError.
Inductive Shape : Type :=
| Circle : Vec -> Double -> Shape
| Poly : (Array Vec) -> Shape.
Extract Inductive Shape => "@geom.Shape"
  [ "@geom.Shape::Circle(center=$0, r=$1)" "@geom.Shape::Poly" ].

Axiom perimeter : Shape -> (Result Double GeomError).
Extract MoonBit Function perimeter => "(try @geom.perimeter($0) catch { ... } noraise { ... })".
Axiom Vec_add : Vec -> Vec -> Vec.
Extract MoonBit Function Vec_add => "@geom.Vec::add($0, $1)".
Axiom Vec_norm : Vec -> Double.
Extract MoonBit Function Vec_norm => "@geom.Vec::norm($0)".
```

Compile it:

```bash
rocq2mbt_c -R . Interop Geom.v
```

`-R . Interop` maps the current directory to the logical path `Interop`; the next step imports it with
`From Interop Require Import Geom.`.

### 6.3 Use it from Rocq

`Use.v`:

```coq
From RocqMbt Require Import Prelude.
From Interop Require Import Geom.
From Corelib Require Import PrimFloat.

Definition unit_x : Vec := {| Vec_x := 1%float; Vec_y := 0%float |}.
Definition far : Vec := Vec_add unit_x {| Vec_x := 2%float; Vec_y := 4%float |}.
Definition far_norm : Double := Vec_norm far.

Definition safe_perimeter (s : Shape) : Double :=
  match perimeter s with
  | Ok p => p
  | Err (Degenerate _) => 0%float
  | Err Empty => (-1)%float
  end.

Definition is_circle (s : Shape) : bool :=
  match s with Circle _ _ => true | Poly _ => false end.

Extraction "app/app.mbt" far_norm safe_perimeter is_circle.
```

```bash
rocq2mbt_c -R . Interop Use.v
```

`app/moon.pkg` must import the original package, **with the same alias that `mbti2rocq` uses** (by default the last segment of the package path,
here `@geom`), and also import the runtime:

```text
import {
  "GreckF/rocqrt" @rocqrt,
  "me/interop/geom" @geom,
}
```

The extracted code calls the original package directly, for example:

```moonbit
pub fn safe_perimeter(s : @geom.Shape) -> Double {
  match (try @geom.perimeter(s) catch { rocq_e => Result::Err(rocq_e) } noraise { rocq_v => Result::Ok(rocq_v) }) {
    Result::Ok(p) => p
    Result::Err(g) => match g {
      @geom.GeomError::Degenerate(_) => 0x0.0p0
      @geom.GeomError::Empty => (-0x1.0p0)
    }
  }
}
```

When the MoonBit package's interface changes, rerun `moon info` and `mbti2rocq`, then recompile the Rocq files.

---

## 7. Extraction reference

### 7.1 Loading

| Form | Effect |
| --- | --- |
| `From RocqMbt Require Import MoonBit.` | Loads only the extraction framework and the plugin; you then need `Extraction Language MoonBit.` manually |
| `From RocqMbt Require Import ExtrMoonBitBasic.` | Loads the plugin, switches to MoonBit, maps `bool/sumbool/option/unit/prod` |
| `From RocqMbt Require Import ExtrMoonBitPrim.` | On top of the previous one, maps native types (requires `rocqrt`) |
| `From RocqMbt Require Import Prelude.` | On top of the previous one, provides MoonBit built-in types, `Result` and trait classes |

### 7.2 Supported extraction commands

| Command | Supported |
| --- | --- |
| `Extraction "dir/file.mbt" f g ...` | ✅ Recommended; one file is one source file in a MoonBit package |
| `Recursive Extraction f.` | ✅ Prints to the screen |
| `Extraction f.` | ✅ Prints a single definition |
| `Separate Extraction` / `Extraction Library` | ❌ Modular extraction is not supported; reports an error suggesting single-file extraction |

The output file path is relative to the current directory of `rocq c`, or can be set with `Set Extraction Output Directory`.
When no output directory is set, Rocq emits an `extraction-default-directory` warning, which can be disabled with
`-w -extraction-default-directory`.

The extracted `.mbt` file must be placed in a MoonBit package. A package can hold the result of only **one** extraction, because two
extractions would both generate same-named types such as `Nat` and `List`.

### 7.3 Translation rules

| Rocq | MoonBit |
| --- | --- |
| Inductive types `nat`, `list A` | `pub(all) enum Nat { O; S(Nat) }`, `pub(all) enum List[A] { Nil; Cons(A, List[A]) }`; constructors are always written in qualified form `Nat::S(..)` |
| Records | Single-constructor enum; projections are ordinary functions |
| Coinductive type `T` | `enum TCell` plus `pub type T = RocqLazy[TCell]`, lazy evaluation with memoization |
| Top-level functions | **Uncurried** `pub fn f(x : A, y : B) -> C` |
| Partial application, functions used as values | η-expanded into curried closures `fn(x) { fn(y) { f(x, y) } }`; non-trivial arguments are `let`-bound first so they are evaluated only once |
| Values of function type | Single-parameter closures `(A) -> (B) -> C` |
| Polymorphic constants (e.g. `@nil`) | Parameterless generic functions `pub fn[A] c() -> List[A]`, referenced as `c()` |
| Monomorphic constants | `pub let c : T = ...` |
| Local `fix` | `letrec f = fn(x) { .. } and g = ..` |
| Logical parts (proofs, `Prop`) | Erased; any leftovers are written as `Unit` / `()` |
| Type variables | Named by position as `A`, `B`, ..., avoiding letters that clash with type names |
| Impossible branches, unrealized axioms | `abort("...")` |
| `Obj.magic` (dependent types etc.) | `rocq_magic`, see section 11 |

Name conversion: types and constructors are capitalized, functions start with a lowercase letter; `'` becomes `_`; names that clash with MoonBit keywords or built-in names
(`Int`, `String`, `Eq`, `Show` ...) get a numeric suffix (e.g. `Eq0`). Rocq modules are flattened,
and definitions with duplicate names are renamed automatically by Rocq (e.g. `k`, `k0`).

### 7.4 Custom extraction

**`Extract Constant` / `Extract Inlined Constant`**: the string on the right is a MoonBit expression,
whose type is understood in curried form.

```coq
Extract Inlined Constant Nat.add => "(fn(a) { fn(b) { a + b } })".
```

To generate a multi-argument call like `f(a, b)` directly, use `Extract MoonBit Function` from section 9.

**`Extract Inductive`**:

```coq
Extract Inductive nat => "Int" [ "0" "(fn(n) { n + 1 })" ]
  "(fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })".
```

- When constructing values, a constructor string is used as a function call (`c(x, y)`); in patterns, it is used as a constructor pattern;
- If a constructor string contains `$0`, `$1` ..., it is treated as a template (e.g. the labelled-argument
  `"@pkg.Shape::Rect(w=$0, h=$1)"`), used for both construction and patterns;
- The optional match function is called as `m(fn(..) { branch1 }, fn(..) { branch2 }, scrutinee)`.
  Each branch is an **uncurried** function; constructors without arguments correspond to `fn() { .. }`;
- `"(,)"` is a special form denoting a MoonBit tuple (`ExtrMoonBitBasic` uses it to map `prod`).

---

## 8. Companion Rocq modules reference

### 8.1 `ExtrMoonBitPrim`: Rocq native types

| Rocq | MoonBit | Notes |
| --- | --- | --- |
| `PrimInt63.int` | `UInt64` | Values are always less than 2^63; signed operations such as `divs`, `ltsb`, `asr` treat bit 62 as the sign bit |
| `PrimFloat.float` | `Double` | IEEE 754 double precision |
| `PrimArray.array A` | `@rocqrt.PArray[A]` | Persistent array (diff-array): get/set are O(1) under linear use; accessing an old version re-roots it |
| `PrimString.string` | `String` | Only the type and literals are mapped |
| `comparison` | `@rocqrt.Comparison` | `Eq`, `Lt`, `Gt` |
| `carry`, `float_class`, `float_comparison` | Same-named enums in `@rocqrt` | |

Literals are printed directly as MoonBit literals:

| Rocq | MoonBit |
| --- | --- |
| `42%uint63` | `42UL` |
| `0.5%float` | `0x1.0p-1` |
| `PrimFloat.infinity`, `nan`, `neg_zero` | `(1.0 / 0.0)`, `(0.0 / 0.0)`, `(-0x0.0p0)` |
| `[| 1; 2 | 0 |]` | `@rocqrt.PArray::of_array([1UL, 2UL], 0UL)` |
| `"abc"%pstring` | `"abc"` (valid UTF-8 is output as is, other bytes are escaped) |

All operations of `PrimInt63`, `PrimFloat` and `PrimArray` are mapped to functions in `@rocqrt`,
whose semantics follow the Rocq kernel implementation one by one (`uint63_63.ml`, `float64_common.ml`, `parray.ml`).

On the MoonBit side you can convert with these functions: `@rocqrt.u63_of_int` / `u63_to_int`,
`PArray::to_array`, etc.

### 8.2 `Prelude`: MoonBit built-in types

**Types**

| Rocq | MoonBit |
| --- | --- |
| `Int Int64 UInt UInt64 Byte Char String Bytes Error` | Same-named built-in types |
| `Double` (i.e. `PrimFloat.float`) | `Double` |
| `Array A` | `Array[A]` (used only through the purely functional operations below) |
| `Result T E` (constructors `Ok` / `Err`) | `Result[T, E]` |
| `bool` / `option A` / `unit` / `A * B` | `Bool` / `A?` / `Unit` / `(A, B)` |

**Conversions and literals**: `Int_of_uint63`, `Int_to_uint63`, `Int64_of_int`, `Int64_to_int`,
`UInt_of_int`, `UInt_to_int`, `UInt64_of_uint63`, `UInt64_to_uint63`, `Double_of_int`,
`Char_of_int`, `Char_to_int`, `String_of_pstring`.

**Operations**: `Int_add Int_sub Int_mul Int_div Int_mod Int_neg Int_eqb Int_ltb Int_leb`;
`String_append String_length`; `Array_make Array_length Array_get Array_push Array_set
Array_map Array_fold Array_of_parray`. `Array_push` and `Array_set` copy before modifying and do not change their argument.

**Trait classes**

```coq
Class Eq (Self : Type)      := { equal : Self -> Self -> bool }.
Class Compare (Self : Type) := { compare : Self -> Self -> Int }.
Class Show (Self : Type)    := { to_string : Self -> String }.
Class Hash (Self : Type)    := { hash : Self -> Int }.
```

Built-in types all have instances: `Eq`, `Compare`, `Show`, `Hash` for `Int`, `String` etc.; `Eq` and
`Compare` also have instances for `Array A`, and `Eq` has an instance for `option A`.

A generic function written in Rocq as `` {A} `{Eq A} `` becomes, after extraction,
`fn[A : Eq] f(d : Eq0[A], ...)`. The dictionary `d` is passed as usual, and the MoonBit constraint lets external calls
in the function body pass type checking with static dispatch.

---

## 9. Interop commands reference

These three commands are provided by the plugin and can be written in any `.v` file that loads the plugin. They persist through `Require`,
so they can be put in library files.

### 9.1 `Extract MoonBit Function f [n] => "template".`

Implements the constant `f` (usually an `Axiom`) with a MoonBit call template.

- `$0`, `$1`, ... stand for the arguments of `f` in order; type class dictionary arguments are not counted (see 9.2);
- `n` is the number of arguments `f` consumes; if omitted, it is the number of placeholders. When there are no placeholders but a `unit` argument is needed
  (e.g. a parameterless function `unit -> T`), write `1`; `n = 0` denotes a value;
- When there are enough arguments, the template is expanded directly, and extra arguments are applied in curried form; when there are too few, it is η-expanded into a closure;
- If the template contains `fn(` (arguments may be evaluated later) or the same placeholder appears more than once, non-trivial arguments are first
  `let`-bound so they are evaluated only once;
- When a placeholder is immediately followed by `(`, `.` or `[`, the argument is parenthesized where needed.

```coq
Axiom hypot : Double -> Double -> Double.
Extract MoonBit Function hypot => "@math.hypot($0, $1)".

Axiom now : unit -> UInt64.
Extract MoonBit Function now 1 => "@env.now()".

Axiom PI : Double.
Extract MoonBit Function PI 0 => "@math.PI".

Axiom fold : forall {A B}, Array A -> B -> (B -> A -> B) -> B.
Extract MoonBit Function fold =>
  "$0.fold(init=$1, fn(b, a) { $2(b)(a) })".
```

### 9.2 `Extract MoonBit Trait C => "@pkg.Trait".`

Declares that the Rocq class (record) `C` is the dictionary type of a MoonBit trait. This has two effects:

1. When calling a function implemented by `Extract MoonBit Function`, arguments of type `C _` (dictionaries) are not passed to
   MoonBit; MoonBit dispatches statically on the argument type;
2. If an extracted generic function has a parameter of type `C A`, the type parameter gets the constraint `A : @pkg.Trait`,
   and `#warnings("-unused_trait_bound")` is added as well.

```coq
Class Pretty (Self : Type) := { pretty : Self -> String }.
Extract MoonBit Trait Pretty => "@mlib.Pretty".
```

### 9.3 `Extract MoonBit Raise f.`

`f` is a function defined in Rocq that returns `Prelude.Result T E`. After extraction:

- Its signature is `-> T raise E`, and at the end of the function body `Result::Err(e)` becomes `raise e`;
- Calls to `f` in Rocq code are written as `(try f(..) catch { e => Result::Err(e) } noraise { v => Result::Ok(v) })`,
  which still yields a `Result`;
- If `E` is an inductive type defined in Rocq, it is printed as `pub(all) suberror E { ... }`. This requires
  `E` to have at least one constructor and no type parameters.

`f` must be a function with a definition in Rocq, not an axiom. External MoonBit raise functions are handled by `mbti2rocq`,
which directly generates axioms returning `Result`.

---

## 10. mbti2rocq reference

### 10.1 Command line

```text
mbti2rocq <input.mbti> [-o <Output.v>] [--alias <@pkg>]
```

| Argument | Description |
| --- | --- |
| `<input.mbti>` | The `pkg.generated.mbti` generated by `moon info` |
| `-o <Output.v>` | Output file; prints to standard output if omitted |
| `--alias <@pkg>` | The alias used to refer to the package in generated code; defaults to the last segment of the package path (`me/x/geom` → `@geom`). Must match the import alias in the user's `moon.pkg` |

The generated file starts with `From RocqMbt Require Import Prelude.`; compiling it requires `RocqMbt` to be findable.

### 10.2 Translation rules

| MoonBit interface | Generated Rocq |
| --- | --- |
| `pub fn f(A, B) -> C` | `Axiom f : A -> B -> C.` plus `Extract MoonBit Function f => "@pkg.f($0, $1)".` |
| Method `pub fn T::m(Self, ..)` | `Axiom T_m`, template `@pkg.T::m(..)` |
| Parameterless function `fn f() -> T` | `unit -> T` (defers side effects) |
| Labelled parameter `x~ : T` | Ordinary positional parameter, written `x=$i` in the template |
| Optional parameter `x? : T` | Omitted; MoonBit's default value is used |
| Generics `fn[A, B : Show]` | `forall {A B : Type} `{Show B}, ...` |
| `-> T raise E` / bare `raise` | `-> Result T E` / `-> Result T Error`, template wrapped in `try ... noraise` |
| `raise?` | Treated as not raising |
| Multi-parameter function type `(A, B) -> C` | Curried `A -> B -> C`, converted automatically in the template (wrapped as `fn(a, b) { $k(a)(b) }` when used as an argument, converted the other way when used as a return value) |
| `() -> T` | `unit -> T` |
| `T?`, `Result[T, E]`, `Array[T]`, `(A, B)` | `option T`, `Result T E`, `Array T`, `A * B` |
| `pub(all) enum`, `suberror` | `Inductive` (may be mutually recursive) plus `Extract Inductive`; labelled constructors use templates |
| `pub(all) struct` with ≥ 2 fields and no `mut` | `Record`, with `Extract Inductive` giving a construction template and a custom match |
| Other types: private fields, read-only `pub struct`, `mut` fields, single-field structs, enums / suberrors with only one single-argument constructor (Rocq extraction would erase it to the argument itself), recursion that is not strictly positive | `Axiom T : Type.`, plus axioms for field access `T_f`, construction `T_new` / `T_C`, and destruction `T_unC` |
| `pub type A = B` | `Definition A := B.` |
| `pub let x : T`, `pub const X : T = ..` | `Axiom` plus template `@pkg.x` |
| `trait T { m(Self, X) -> Y }` | `Class T (Self : Type) := { m : Self -> X -> Y }.`, `Extract MoonBit Trait`, and a generic method axiom `T_m_impl` |
| `impl T for X` | `#[global] Instance T_X : T X := {\| m := T_m_impl \|}.`; traits from the Prelude (Eq, Compare, Show, Hash) use `Builtin.*` |
| External types `@json.Json`, `Iter[A]` etc. | Automatically declared as axiom types `json_Json`, `Iter`, with extraction directives |

When a Rocq name clashes with the Prelude or is a Rocq reserved word, a package-name prefix or a `_` suffix is added, e.g.
`mlib_Point_x`, `end_`.

**Skipped declarations**: `async` functions, trait objects `&T`, unknown trait constraints (e.g.
`@json.FromJson`), multi-parameter functions inside containers (e.g. `Array[(A, B) -> C]`), tuples of three or more elements,
traits with generic methods, and callbacks that raise. These are all listed, with reasons, in the comment
`(* Not translated: ... *)` at the end of the generated file.

### 10.3 Suggested project layout

```text
myproject/
├── moon.mod, moon.work        # the workspace includes rocqrt
├── geom/                      # the original MoonBit package
│   └── pkg.generated.mbti     # generated by moon info
├── rocq/
│   ├── Geom.v                 # generated by mbti2rocq, do not edit by hand
│   └── Use.v                  # your Rocq code
└── app/                       # extracted output package; moon.pkg imports @rocqrt and @geom
```

Chain the steps together with a script:

```bash
moon info --target native -p me/myproject/geom
mbti2rocq geom/pkg.generated.mbti -o rocq/Geom.v
(cd rocq && rocq2mbt_c -R . My Geom.v && rocq2mbt_c -R . My Use.v)
moon test
```

**Note**: the generated file consists entirely of axioms; Rocq knows nothing about the behavior of the MoonBit functions. Properties of external functions
can only be added by you as extra axioms, and you are responsible for ensuring that they hold.

---

## 11. Backend compatibility and limitations

| Case | wasm-gc | wasm | native | js |
| --- | --- | --- | --- | --- |
| Ordinary extraction, native types, Prelude, interop | ✅ | ✅ | ✅ | Untested (no node on this machine) |
| Code that needs `rocq_magic` | ❌ Compilation fails | ✅ | ❌ Segfault | Should work in theory |

- **`rocq_magic`**: terms that cannot be expressed with ML types, such as those involving dependent types, need `Obj.magic`; in MoonBit it is implemented with
  `"%identity"`, which only works on backends with a uniform value representation. The plugin emits a warning when it is used.
  Simply typed programs do not produce magic.
- Only single-file extraction is supported; unapplied functors are omitted.
- MoonBit local closures have no let-polymorphism: a polymorphic function bound by a local `let` in Rocq that is used at different types
  will not type-check after extraction.
- Trait bridging: instances you write yourself in Rocq for some type only take effect through dictionaries in Rocq code;
  when values are passed to external MoonBit functions, MoonBit uses that type's `impl` in MoonBit.
  No MoonBit `impl` is currently generated for Rocq instances.
- `PrimString` maps only the type and literals: Rocq strings are byte strings, MoonBit strings are UTF-16,
  and the operations on the two sides have different semantics.
- MoonBit no longer recommends using `Show` on collection types, so the Prelude has no `Show (Array A)` instance.

---

## 12. FAQ

**`Unknown extraction language MoonBit` / `Cannot find library rocq-mbt.plugin`**
Rocq cannot find the plugin. Check whether
`OCAMLPATH=$ROCQ2MBT/_build/install/default/lib` is set (option A) or `dune install` has been run
(option B), and whether you are in the local switch (`source scripts/env.sh`).

**`Unable to locate library ... with prefix RocqMbt`**
`-Q $ROCQ2MBT/_build/default/theories RocqMbt` is missing, or `dune build` has not been run yet.

**`Cannot find a physical path bound to logical path Gen` (or your own prefix)**
The directory in `-R <dir> <prefix>` is wrong. It should point to the directory containing the generated `.v`, and that `.v`
must already be compiled to a `.vo`.

**Rocq reports `The term "0" has type "int" while it is expected to have type "nat"`**
After `Open Scope uint63_scope`, number literals are interpreted as `int`. Add a scope to the literal, such as
`%nat` or `%uint63`, or close the scope. Also, names like `compare` and `length` may be shadowed by modules imported later;
use the full name when necessary, e.g. `PrimInt63.compare`.

**MoonBit reports `@rocqrt` undefined / cannot find package `GreckF/rocqrt`**
The `moon.pkg` of the extracted package must contain `import { "GreckF/rocqrt" @rocqrt }`, the module's
`moon.mod` must import `GreckF/rocqrt@0.1.0`, and `moon.work` must include the path of `rocqrt`.

**MoonBit reports an external package such as `@geom` as undefined**
The import alias must match `mbti2rocq --alias` (by default the last segment of the package path).

**Duplicate `Nat`, `List` definitions in the same package**
A MoonBit package can hold the result of only one extraction. Put multiple extractions into different packages, or merge them into a single extraction.

**Extraction warns `The extracted MoonBit code uses unsafe coercions (rocq_magic)`**
See section 11. You can only run with `--target wasm`, or adjust the Rocq code to keep dependent types out of the computational parts.

**`AXIOM TO BE REALIZED` or `RocqAny` is generated**
Some axiom has no extraction implementation. Implement it with `Extract Constant` or `Extract MoonBit Function`,
or write `Extract Inlined Constant T => "MoonBitType"` for an axiom type.

**Building `mbti2rocq` reports `The type Int32 is undefined`**
The version of `moonbitlang/x` is newer than the toolchain. Upgrade the toolchain, or on an old toolchain (moonc v0.10.8) set `moonbitlang/x@0.4.50` in `mbt/mbti2rocq/moon.mod`;
after fixing it, delete the `.mooncakes` directory and rebuild.

**`setup-opam.sh` reports `Directory ... already exists`**
A previous switch may have been only half created. Delete `~/.local/share/rocq2mbt` and the `_opam`
symbolic link in the project, then rerun.

---

## 13. Development and testing

```bash
source scripts/env.sh
bash tests/run.sh                 # tests on wasm-gc wasm native by default
bash tests/run.sh native          # test only one backend
```

`tests/run.sh` runs, in order:

1. `dune build` (the plugin and the Rocq library);
2. Unit tests of `rocqrt`;
3. Builds `mbti2rocq`; runs `moon info` and `mbti2rocq` on `tests/moon/mlib`, generating
   `tests/gen/Mlib.v` and compiling it;
4. Extracts each `tests/*.v` into `tests/moon/<pkg>/`;
5. Runs `moon test` for `basic`, `advanced`, `prim`, `interop` on every backend;
   runs `magic` only on wasm.

When adding a new feature, add test cases to `tests/*.v` and runtime assertions to the corresponding `tests/moon/<pkg>/*_wbtest.mbt`.
The plugin source is in `src/moonbit.ml` (printer) and `src/mbt_table.ml`
(interop command tables); for a reference implementation, see `plugins/extraction/haskell.ml` in the Rocq source.
