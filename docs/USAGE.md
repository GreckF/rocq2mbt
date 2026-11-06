# rocq2mbt 安装与使用说明

**中文** | [English](USAGE.en.md)

本文档说明如何安装 rocq2mbt，并用它完成三件事：

1. 把 Rocq 程序**提取**（extract）成 MoonBit 代码；
2. 在 Rocq 里使用 Rocq 原生类型（63 位整数、浮点、持久数组、字符串）和 MoonBit
   内建类型，提取后得到对应的 MoonBit 类型；
3. 用 `mbti2rocq` 把已有 MoonBit 包的接口（`.mbti`）翻译成 Rocq 公理，在 Rocq
   里调用 MoonBit 代码，提取时还原成对原包的调用。

文中所有命令都在 Linux 或 WSL 的 bash 里执行。`$ROCQ2MBT` 指 rocq2mbt 仓库的
根目录，例如：

```bash
export ROCQ2MBT=/path/to/rocq2mbt
```

---

## 目录

1. [组成部分](#1-组成部分)
2. [环境要求](#2-环境要求)
3. [安装](#3-安装)
4. [快速上手一：纯 Rocq 程序的提取](#4-快速上手一纯-rocq-程序的提取)
5. [快速上手二：原生类型与 MoonBit 内建类型](#5-快速上手二原生类型与-moonbit-内建类型)
6. [快速上手三：在 Rocq 里调用 MoonBit 包](#6-快速上手三在-rocq-里调用-moonbit-包)
7. [提取参考](#7-提取参考)
8. [配套 Rocq 模块参考](#8-配套-rocq-模块参考)
9. [互操作命令参考](#9-互操作命令参考)
10. [mbti2rocq 参考](#10-mbti2rocq-参考)
11. [后端兼容性与限制](#11-后端兼容性与限制)
12. [常见问题](#12-常见问题)
13. [开发与测试](#13-开发与测试)

---

## 1. 组成部分

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| Rocq 插件 `rocq-mbt.plugin` | `src/` | 注册提取语言 `MoonBit`，提供 `Extract MoonBit ...` 命令 |
| Rocq 库 `RocqMbt` | `theories/` | `MoonBit`、`ExtrMoonBitBasic`、`ExtrMoonBitPrim`、`Prelude` 四个模块 |
| MoonBit 运行时 `GreckF/rocqrt` | `mbt/rocqrt/` | 原生 63 位整数、浮点、持久数组的实现，提取出的代码在用到原生类型时依赖它 |
| MoonBit 工具 `mbti2rocq` | `mbt/mbti2rocq/` | `.mbti` → Rocq 文件 |

## 2. 环境要求

| 软件 | 版本 | 说明 |
| --- | --- | --- |
| Linux 或 WSL2 | — | Windows 上请在 WSL 里操作 |
| opam | ≥ 2.1 | 用于建项目本地 switch |
| 系统构建工具 | gcc、make、git、curl、pkg-config、libgmp-dev | 编译 OCaml、zarith、Rocq 需要 |
| OCaml | 5.4.1（脚本自动安装） | 其他 ≥ 4.14 的版本一般也可以，用 `OCAML_VERSION` 指定 |
| Rocq | 9.4+alpha，即 rocq master（脚本自动安装） | 见下方说明 |
| MoonBit 工具链 | 已在 moonc v0.10.20 / moon 0.1.20261104 上测试 | 只在编译、运行提取出的代码和 `mbti2rocq` 时需要 |

**关于 Rocq 版本。** 插件依赖 Rocq 的可扩展提取 API（rocq-prover/rocq PR #22541，
2026-10-05 合并）。git tag `V9.4+alpha` 打在 2026-06-29，**不包含**这个 API。
所以安装脚本 pin 的是 rocq master 上的一个 commit（版本号同样显示为 `9.4+alpha`）。
这个 commit 写在 `scripts/setup-opam.sh` 的 `ROCQ_COMMIT` 里。

Ubuntu 上安装系统依赖：

```bash
sudo apt install build-essential git curl pkg-config libgmp-dev opam
opam init        # 第一次使用 opam 时
```

安装 MoonBit 工具链（装到 `~/.moon/bin`）：

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

## 3. 安装

### 3.1 建立本地 opam switch 并安装 Rocq

```bash
cd $ROCQ2MBT
bash scripts/setup-opam.sh
```

脚本做了这些事：

1. 在项目里建一个本地 switch，装 `ocaml-base-compiler.5.4.1`。
   如果项目在 Windows 盘上（路径以 `/mnt/` 开头），在 9p 文件系统上编译会非常慢，
   所以 switch 实际放在 `~/.local/share/rocq2mbt/_opam`，再在项目根目录建一个指向它的
   符号链接 `_opam`。
2. 把 `rocq-runtime` 和 `rocq-core` pin 到 `ROCQ_COMMIT` 指定的 rocq commit，然后安装。
3. 最后打印 `rocq --version`，应当显示 `The Rocq Prover, version 9.4+alpha`。

整个过程需要从头编译 OCaml 和 Rocq，大约需要 15–40 分钟。可以用环境变量改默认值：

```bash
ROCQ_COMMIT=<rocq master 上的 commit> OCAML_VERSION=5.3.0 bash scripts/setup-opam.sh
```

脚本可以重复运行：已存在的 switch 不会重建，pin 会更新。

### 3.2 进入环境

之后每次打开新 shell 都执行：

```bash
source $ROCQ2MBT/scripts/env.sh
```

它会切到本地 switch，并把 `~/.moon/bin` 加进 `PATH`。

### 3.3 编译插件和 Rocq 库

```bash
cd $ROCQ2MBT
dune build
```

产物有两处：

- `_build/install/default/lib/rocq-mbt/plugin/`：插件（findlib 包名 `rocq-mbt.plugin`）；
- `_build/default/theories/`：编译好的 Rocq 库，逻辑路径 `RocqMbt`。

### 3.4 使用插件：两种方式

**方式 A：不安装，直接用构建目录（开发时推荐）。** 设置 `OCAMLPATH` 让 Rocq 找到插件，
用 `-Q` 映射 Rocq 库：

```bash
export OCAMLPATH=$ROCQ2MBT/_build/install/default/lib:$OCAMLPATH
rocq c -Q $ROCQ2MBT/_build/default/theories RocqMbt Foo.v
```

可以把这两部分写成一个函数：

```bash
rocq2mbt_c() {
  OCAMLPATH=$ROCQ2MBT/_build/install/default/lib:$OCAMLPATH \
    rocq c -Q $ROCQ2MBT/_build/default/theories RocqMbt "$@"
}
```

**方式 B：装进当前 switch。**

```bash
cd $ROCQ2MBT && dune install
```

装好后 `rocq c Foo.v` 直接就能 `From RocqMbt Require Import ...`，不需要额外参数。
修改插件后要重新执行 `dune build && dune install`。

### 3.5 编译 MoonBit 工具（可选）

只有用到 `mbti2rocq` 时才需要：

```bash
cd $ROCQ2MBT/mbt/mbti2rocq
moon build --target native --release
# 可执行文件：
ls _build/native/release/build/cmd/main/main.exe
```

方便起见，可以加一个别名：

```bash
alias mbti2rocq=$ROCQ2MBT/mbt/mbti2rocq/_build/native/release/build/cmd/main/main.exe
```

`mbti2rocq` 依赖 `moonbitlang/x@0.5.7`（用它读写文件），第一次构建时会自动下载。
如果只有 moonc v0.10.8（2026-08）这样较旧的工具链，要改用 `moonbitlang/x@0.4.50`。

### 3.6 验证安装

```bash
cd $ROCQ2MBT && bash tests/run.sh
```

所有测试都应输出 `failed: 0`。第 13 节说明了这个脚本具体测试了什么。

---

## 4. 快速上手一：纯 Rocq 程序的提取

这一节不需要 MoonBit 运行时。新建一个目录：

```bash
mkdir -p ~/hello/lib ~/hello/cmd/main && cd ~/hello
```

**Rocq 程序** `Hello.v`：

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

`ExtrMoonBitBasic` 加载插件，把提取语言设为 MoonBit，并把 `bool`、`option`、
`unit` 和二元组映射成 MoonBit 内建的 `Bool`、`Option`、`Unit` 和元组。

**提取：**

```bash
rocq2mbt_c Hello.v          # 或者方式 B 下：rocq c Hello.v
```

`lib/hello.mbt` 大致如下：

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

**MoonBit 工程。** 新建三个文件：

`moon.mod`：

```text
name = "me/hello"

version = "0.1.0"
```

`lib/moon.pkg`：内容为空。

`cmd/main/moon.pkg`：

```text
import {
  "me/hello/lib" @lib,
}

pkgtype(kind: "executable")
```

`cmd/main/main.mbt`：

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

运行：

```bash
moon run cmd/main --target native     # 输出 55
```

用 `wasm-gc`、`wasm`、`native` 哪个后端都可以。

---

## 5. 快速上手二：原生类型与 MoonBit 内建类型

`Prelude` 提供 MoonBit 内建类型（`Int`、`String`、`Array` …）、`Result`、
trait 对应的类，并包含 Rocq 原生类型的提取设置。用到这些时，提取出的代码依赖运行时
包 `GreckF/rocqrt`。

```bash
mkdir -p ~/prelude-demo/lib && cd ~/prelude-demo
```

`Demo.v`：

```coq
From RocqMbt Require Import Prelude.
From Corelib Require Import PrimInt63 PrimString PrimArray.

(* MoonBit Int：用 Int_of_uint63 写字面量 *)
Definition i (n : PrimInt63.int) : Int := Int_of_uint63 n.

Definition area (w h : Int) : Int := Int_mul w h.

(* 类型类 Show 就是 MoonBit 的 trait Show *)
Definition describe {A} `{Show A} (x : A) : String :=
  String_append (String_of_pstring "value = "%pstring) (to_string x).

(* Rocq 原生 63 位整数和持久数组 *)
Definition table : array PrimInt63.int := [| 1; 2; 3 | 0 |]%uint63.
Definition second : PrimInt63.int := table.[1].

(* 返回 Result 的 Rocq 函数，提取成 MoonBit 的 raise 函数 *)
Inductive DemoError := Negative | TooLarge.
Definition checked (x : Int) : Result Int DemoError :=
  if Int_ltb x (i 0) then Err Negative
  else if Int_ltb (i 100) x then Err TooLarge
  else Ok x.
Extract MoonBit Raise checked.

(* Show_Int 是字典，列出来才会被提取，MoonBit 侧调用 describe 时要用 *)
Extraction "lib/demo.mbt" area describe Show_Int second checked.
```

提取：

```bash
rocq2mbt_c Demo.v
```

得到的 MoonBit 代码中：

```moonbit
#warnings("-unused_trait_bound")
pub fn[A : Show] describe(h : Show0[A], x : A) -> String { ... }   // 自动加了 A : Show

pub let table : Array0[UInt64] = @rocqrt.PArray::of_array([1UL, 2UL, 3UL], 0UL)
pub let second : UInt64 = @rocqrt.PArray::get(table, 1UL)

pub(all) suberror DemoError {
  Negative
  TooLarge
}

pub fn checked(x : Int) -> Int raise DemoError { ... }
```

注意：错误类型必须带计算内容。像 `Inductive E := C.` 这种只有一个无参构造子的类型会被
提取擦除，插件会报错。

**MoonBit 工程需要能找到 `rocqrt`。** 在本地开发时用 `moon.work` 把运行时模块加进工作区：

`moon.work`：

```text
members = [
  ".",
  "/path/to/rocq2mbt/mbt/rocqrt",
]
```

（第二项写 `$ROCQ2MBT/mbt/rocqrt` 的实际路径，也可以写相对路径。）

`moon.mod`：

```text
name = "me/demo"

version = "0.1.0"

import {
  "GreckF/rocqrt@0.1.0",
}
```

`lib/moon.pkg`，提取出的包必须用 `@rocqrt` 这个别名导入运行时：

```text
import {
  "GreckF/rocqrt" @rocqrt,
}
```

然后就可以 `moon check` / `moon test`，或者在其他包里使用这些函数。例如在
`lib/demo_wbtest.mbt` 里：

```moonbit
test {
  assert_eq(area(3)(4), 12)                  // area 被提取成柯里化的值，见下面说明
  assert_eq(describe(show_Int, 5), "value = 5")
  assert_eq(second, 2UL)
  assert_eq(checked(7), 7)
  let r : Result[Int, DemoError] = try checked(-1) catch { e => Err(e) } noraise { v => Ok(v) }
  assert_eq(r is Err(DemoError::Negative), true)
}
```

`area` 的定义 `fun w h => Int_mul w h` 会被提取优化成 `Int_mul` 本身，没有前导 λ，
所以变成值 `pub let area : (Int) -> (Int) -> Int`，调用时写 `area(3)(4)`。
函数体不能被 η 化简时（例如 `describe`），得到的就是普通的多参数函数。

---

## 6. 快速上手三：在 Rocq 里调用 MoonBit 包

工作流程：

```text
MoonBit 包 ──moon info──▶ pkg.generated.mbti ──mbti2rocq──▶ Geom.v（公理 + 提取指令）
                                                              │
                              你的 Rocq 程序 Use.v ◀── Require ┘
                                     │ Extraction
                                     ▼
                     提取出的 MoonBit 代码，直接调用原来的 MoonBit 包
```

### 6.1 准备一个 MoonBit 包

```bash
mkdir -p ~/interop/geom ~/interop/app && cd ~/interop
```

`moon.mod`：

```text
name = "me/interop"

version = "0.1.0"

import {
  "GreckF/rocqrt@0.1.0",
}
```

`moon.work`：同第 5 节，包含 `"."` 和 `rocqrt` 的路径。

`geom/moon.pkg`：内容为空。`geom/geom.mbt`：

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

### 6.2 生成接口并翻译成 Rocq

```bash
moon info --target native -p me/interop/geom     # 生成 geom/pkg.generated.mbti
mbti2rocq geom/pkg.generated.mbti -o Geom.v
```

生成的 `Geom.v`（节选）：

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

编译它：

```bash
rocq2mbt_c -R . Interop Geom.v
```

`-R . Interop` 把当前目录映射为逻辑路径 `Interop`，下一步用
`From Interop Require Import Geom.` 引入。

### 6.3 在 Rocq 里使用

`Use.v`：

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

`app/moon.pkg` 要导入原包，**别名必须和 `mbti2rocq` 使用的一致**（默认是包路径的最后一段，
这里是 `@geom`），同时导入运行时：

```text
import {
  "GreckF/rocqrt" @rocqrt,
  "me/interop/geom" @geom,
}
```

提取出的代码直接调用原包，例如：

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

MoonBit 包改了接口之后，重新执行 `moon info` 和 `mbti2rocq`，再重新编译 Rocq 文件即可。

---

## 7. 提取参考

### 7.1 加载

| 写法 | 效果 |
| --- | --- |
| `From RocqMbt Require Import MoonBit.` | 只加载提取框架和插件，之后需要手动 `Extraction Language MoonBit.` |
| `From RocqMbt Require Import ExtrMoonBitBasic.` | 加载插件，切换到 MoonBit，映射 `bool/sumbool/option/unit/prod` |
| `From RocqMbt Require Import ExtrMoonBitPrim.` | 在上一项的基础上映射原生类型（需要 `rocqrt`） |
| `From RocqMbt Require Import Prelude.` | 在上一项的基础上提供 MoonBit 内建类型、`Result` 和 trait 类 |

### 7.2 支持的提取命令

| 命令 | 支持 |
| --- | --- |
| `Extraction "dir/file.mbt" f g ...` | ✅ 推荐用法，一个文件就是 MoonBit 包里的一个源文件 |
| `Recursive Extraction f.` | ✅ 打印到屏幕 |
| `Extraction f.` | ✅ 打印单个定义 |
| `Separate Extraction` / `Extraction Library` | ❌ 不支持模块化提取，会报错并提示用单文件提取 |

输出文件的路径相对于 `rocq c` 的当前目录，或者用 `Set Extraction Output Directory`
指定。没有指定输出目录时 Rocq 会给出 `extraction-default-directory` 警告，可以用
`-w -extraction-default-directory` 关掉。

提取出的 `.mbt` 文件要放进一个 MoonBit 包。一个包里只能放**一次**提取的结果，因为两次
提取都会生成 `Nat`、`List` 之类的同名类型。

### 7.3 翻译规则

| Rocq | MoonBit |
| --- | --- |
| 归纳类型 `nat`、`list A` | `pub(all) enum Nat { O; S(Nat) }`、`pub(all) enum List[A] { Nil; Cons(A, List[A]) }`，构造子都写成限定形式 `Nat::S(..)` |
| 记录 | 单构造子 enum，投影是普通函数 |
| 余归纳类型 `T` | `enum TCell` 加上 `pub type T = RocqLazy[TCell]`，带记忆化的惰性求值 |
| 顶层函数 | **非柯里化**的 `pub fn f(x : A, y : B) -> C` |
| 部分应用、把函数当值使用 | η 展开成柯里化闭包 `fn(x) { fn(y) { f(x, y) } }`；非平凡的实参先 `let` 绑定，保证只求值一次 |
| 函数类型的值 | 单参数闭包 `(A) -> (B) -> C` |
| 多态常量（如 `@nil`） | 无参泛型函数 `pub fn[A] c() -> List[A]`，引用时写 `c()` |
| 单态常量 | `pub let c : T = ...` |
| 局部 `fix` | `letrec f = fn(x) { .. } and g = ..` |
| 逻辑部分（证明、`Prop`） | 被擦除；残留的写成 `Unit` / `()` |
| 类型变量 | 按位置命名为 `A`、`B`、…，会避开与类型名冲突的字母 |
| 不可能的分支、未实现的公理 | `abort("...")` |
| `Obj.magic`（依赖类型等） | `rocq_magic`，见 11 节 |

名字转换：类型和构造子首字母大写，函数首字母小写；`'` 变成 `_`；与 MoonBit 关键字或内建名字
（`Int`、`String`、`Eq`、`Show` …）冲突时加数字后缀（如 `Eq0`）。Rocq 模块会被拉平，
重名的定义由 Rocq 自动改名（如 `k`、`k0`）。

### 7.4 自定义提取

**`Extract Constant` / `Extract Inlined Constant`**：右边的字符串是一个 MoonBit 表达式，
类型按柯里化方式理解。

```coq
Extract Inlined Constant Nat.add => "(fn(a) { fn(b) { a + b } })".
```

想要直接生成 `f(a, b)` 这样的多参数调用，用第 9 节的 `Extract MoonBit Function`。

**`Extract Inductive`**：

```coq
Extract Inductive nat => "Int" [ "0" "(fn(n) { n + 1 })" ]
  "(fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })".
```

- 构造子字符串在构造值时当作函数调用（`c(x, y)`），在模式里当作构造子模式；
- 构造子字符串里如果有 `$0`、`$1` …，就当作模板（例如带标签参数的
  `"@pkg.Shape::Rect(w=$0, h=$1)"`），构造和模式都用它；
- 可选的 match 函数以 `m(fn(..) { 分支1 }, fn(..) { 分支2 }, 被匹配的值)` 的形式调用。
  每个分支是**非柯里化**的函数，无参构造子对应 `fn() { .. }`；
- `"(,)"` 是特殊写法，表示 MoonBit 元组（`ExtrMoonBitBasic` 用它映射 `prod`）。

---

## 8. 配套 Rocq 模块参考

### 8.1 `ExtrMoonBitPrim`：Rocq 原生类型

| Rocq | MoonBit | 说明 |
| --- | --- | --- |
| `PrimInt63.int` | `UInt64` | 值始终小于 2^63；`divs`、`ltsb`、`asr` 等有符号运算把第 62 位当作符号位 |
| `PrimFloat.float` | `Double` | IEEE 754 双精度 |
| `PrimArray.array A` | `@rocqrt.PArray[A]` | 持久数组（diff-array）：按线性方式使用时 get/set 是 O(1)，访问旧版本时会重新定根 |
| `PrimString.string` | `String` | 只映射类型和字面量 |
| `comparison` | `@rocqrt.Comparison` | `Eq`、`Lt`、`Gt` |
| `carry`、`float_class`、`float_comparison` | `@rocqrt` 中的同名枚举 | |

字面量直接打印成 MoonBit 字面量：

| Rocq | MoonBit |
| --- | --- |
| `42%uint63` | `42UL` |
| `0.5%float` | `0x1.0p-1` |
| `PrimFloat.infinity`、`nan`、`neg_zero` | `(1.0 / 0.0)`、`(0.0 / 0.0)`、`(-0x0.0p0)` |
| `[| 1; 2 | 0 |]` | `@rocqrt.PArray::of_array([1UL, 2UL], 0UL)` |
| `"abc"%pstring` | `"abc"`（合法 UTF-8 原样输出，其余字节转义） |

`PrimInt63`、`PrimFloat`、`PrimArray` 的所有运算都映射到 `@rocqrt` 中的函数，
语义逐一对照 Rocq 内核的实现（`uint63_63.ml`、`float64_common.ml`、`parray.ml`）。

在 MoonBit 一侧可以用这些函数转换：`@rocqrt.u63_of_int` / `u63_to_int`、
`PArray::to_array` 等。

### 8.2 `Prelude`：MoonBit 内建类型

**类型**

| Rocq | MoonBit |
| --- | --- |
| `Int Int64 UInt UInt64 Byte Char String Bytes Error` | 同名内建类型 |
| `Double`（即 `PrimFloat.float`） | `Double` |
| `Array A` | `Array[A]`（只通过下面的纯函数式操作使用） |
| `Result T E`（构造子 `Ok` / `Err`） | `Result[T, E]` |
| `bool` / `option A` / `unit` / `A * B` | `Bool` / `A?` / `Unit` / `(A, B)` |

**转换与字面量**：`Int_of_uint63`、`Int_to_uint63`、`Int64_of_int`、`Int64_to_int`、
`UInt_of_int`、`UInt_to_int`、`UInt64_of_uint63`、`UInt64_to_uint63`、`Double_of_int`、
`Char_of_int`、`Char_to_int`、`String_of_pstring`。

**运算**：`Int_add Int_sub Int_mul Int_div Int_mod Int_neg Int_eqb Int_ltb Int_leb`；
`String_append String_length`；`Array_make Array_length Array_get Array_push Array_set
Array_map Array_fold Array_of_parray`。`Array_push`、`Array_set` 先复制再修改，不会改动参数。

**trait 类**

```coq
Class Eq (Self : Type)      := { equal : Self -> Self -> bool }.
Class Compare (Self : Type) := { compare : Self -> Self -> Int }.
Class Show (Self : Type)    := { to_string : Self -> String }.
Class Hash (Self : Type)    := { hash : Self -> Int }.
```

内建类型都有实例：`Eq`、`Compare`、`Show`、`Hash` 对 `Int`、`String` 等，`Eq` 和
`Compare` 还有 `Array A` 的实例，`Eq` 有 `option A` 的实例。

在 Rocq 里写 `` {A} `{Eq A} `` 的泛型函数，提取后会变成
`fn[A : Eq] f(d : Eq0[A], ...)`。字典 `d` 照常传递，MoonBit 的约束让函数体里的
外部调用能通过静态分派的类型检查。

---

## 9. 互操作命令参考

这三个命令由插件提供，写在任何加载了插件的 `.v` 文件里都可以。它们随 `Require`
持久化，可以放进库文件中。

### 9.1 `Extract MoonBit Function f [n] => "模板".`

用一个 MoonBit 调用模板实现常量 `f`（一般是 `Axiom`）。

- `$0`、`$1`、… 依次代表 `f` 的实参，类型类字典实参不计入（见 9.2）；
- `n` 是 `f` 消耗的实参个数，省略时取占位符个数。没有占位符但需要一个 `unit` 实参时
  （例如 `unit -> T` 的无参函数），要写 `1`；`n = 0` 表示一个值；
- 实参个数足够时直接展开模板，多出来的实参再按柯里化方式调用；不足时 η 展开成闭包；
- 如果模板里有 `fn(`（实参可能被推迟求值）或者同一个占位符出现多次，非平凡的实参会先
  `let` 绑定，保证只求值一次；
- 占位符后面紧跟 `(`、`.`、`[` 时，会在需要的地方给实参加括号。

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

声明 Rocq 类（record）`C` 是 MoonBit trait 的字典类型。效果有两个：

1. 调用 `Extract MoonBit Function` 实现的函数时，类型为 `C _` 的实参（字典）不会传给
   MoonBit，由 MoonBit 按实参类型静态分派；
2. 提取出的泛型函数如果有类型为 `C A` 的参数，就给类型参数加上约束 `A : @pkg.Trait`，
   同时加上 `#warnings("-unused_trait_bound")`。

```coq
Class Pretty (Self : Type) := { pretty : Self -> String }.
Extract MoonBit Trait Pretty => "@mlib.Pretty".
```

### 9.3 `Extract MoonBit Raise f.`

`f` 是 Rocq 里定义的函数，返回 `Prelude.Result T E`。提取后：

- 签名是 `-> T raise E`，函数体最后把 `Result::Err(e)` 变成 `raise e`；
- Rocq 代码里对 `f` 的调用会写成 `(try f(..) catch { e => Result::Err(e) } noraise { v => Result::Ok(v) })`，
  得到的仍然是 `Result`；
- 如果 `E` 是 Rocq 里定义的归纳类型，会打印成 `pub(all) suberror E { ... }`。这要求
  `E` 至少有一个构造子，而且不带类型参数。

`f` 必须是 Rocq 里有定义的函数，不能是公理。外部 MoonBit 的 raise 函数由 `mbti2rocq`
处理，它直接生成返回 `Result` 的公理。

---

## 10. mbti2rocq 参考

### 10.1 命令行

```text
mbti2rocq <input.mbti> [-o <Output.v>] [--alias <@pkg>]
```

| 参数 | 说明 |
| --- | --- |
| `<input.mbti>` | `moon info` 生成的 `pkg.generated.mbti` |
| `-o <Output.v>` | 输出文件，省略时打印到标准输出 |
| `--alias <@pkg>` | 生成代码里引用该包用的别名，默认是包路径的最后一段（`me/x/geom` → `@geom`）。必须和使用方 `moon.pkg` 里的 import 别名一致 |

生成的文件以 `From RocqMbt Require Import Prelude.` 开头，编译它需要先能找到 `RocqMbt`。

### 10.2 翻译规则

| MoonBit 接口 | 生成的 Rocq |
| --- | --- |
| `pub fn f(A, B) -> C` | `Axiom f : A -> B -> C.` 加上 `Extract MoonBit Function f => "@pkg.f($0, $1)".` |
| 方法 `pub fn T::m(Self, ..)` | `Axiom T_m`，模板 `@pkg.T::m(..)` |
| 无参函数 `fn f() -> T` | `unit -> T`（推迟副作用） |
| 带标签参数 `x~ : T` | 普通位置参数，模板里写 `x=$i` |
| 可选参数 `x? : T` | 省略，使用 MoonBit 的默认值 |
| 泛型 `fn[A, B : Show]` | `forall {A B : Type} `{Show B}, ...` |
| `-> T raise E` / 只写 `raise` | `-> Result T E` / `-> Result T Error`，模板包上 `try ... noraise` |
| `raise?` | 当作不 raise |
| 多参数函数类型 `(A, B) -> C` | 柯里化的 `A -> B -> C`，模板里自动转换（作为参数时包一层 `fn(a, b) { $k(a)(b) }`，作为返回值时反向转换） |
| `() -> T` | `unit -> T` |
| `T?`、`Result[T, E]`、`Array[T]`、`(A, B)` | `option T`、`Result T E`、`Array T`、`A * B` |
| `pub(all) enum`、`suberror` | `Inductive`（可以互递归）加 `Extract Inductive`；带标签的构造子用模板 |
| `pub(all) struct`，字段 ≥ 2 且没有 `mut` | `Record`，用 `Extract Inductive` 给出构造模板和自定义 match |
| 其他类型：私有字段、只读 `pub struct`、有 `mut` 字段、单字段结构体、只有一个单参数构造子的 enum / suberror（Rocq 提取会把它擦成参数本身）、递归不满足严格正性的 | `Axiom T : Type.`，外加字段读取 `T_f`、构造 `T_new` / `T_C`、析构 `T_unC` 公理 |
| `pub type A = B` | `Definition A := B.` |
| `pub let x : T`、`pub const X : T = ..` | `Axiom` 加模板 `@pkg.x` |
| `trait T { m(Self, X) -> Y }` | `Class T (Self : Type) := { m : Self -> X -> Y }.`，`Extract MoonBit Trait`，以及泛型方法公理 `T_m_impl` |
| `impl T for X` | `#[global] Instance T_X : T X := {\| m := T_m_impl \|}.`；Prelude 中的 trait（Eq、Compare、Show、Hash）用 `Builtin.*` |
| 外部类型 `@json.Json`、`Iter[A]` 等 | 自动声明成公理类型 `json_Json`、`Iter`，并给出提取指令 |

Rocq 名字与 Prelude 冲突，或者是 Rocq 保留字时，会加包名前缀或 `_` 后缀，例如
`mlib_Point_x`、`end_`。

**跳过的声明**：`async` 函数、trait 对象 `&T`、未知的 trait 约束（例如
`@json.FromJson`）、放在容器里的多参数函数（如 `Array[(A, B) -> C]`）、三元及以上元组、
有泛型方法的 trait、会 raise 的回调。这些都会列在生成文件末尾的注释
`(* Not translated: ... *)` 中，并附上原因。

### 10.3 建议的工程布局

```text
myproject/
├── moon.mod, moon.work        # 工作区里包含 rocqrt
├── geom/                      # 原 MoonBit 包
│   └── pkg.generated.mbti     # moon info 生成
├── rocq/
│   ├── Geom.v                 # mbti2rocq 生成，不要手改
│   └── Use.v                  # 你的 Rocq 代码
└── app/                       # 提取的输出包，moon.pkg 导入 @rocqrt 和 @geom
```

用一个脚本把各步串起来：

```bash
moon info --target native -p me/myproject/geom
mbti2rocq geom/pkg.generated.mbti -o rocq/Geom.v
(cd rocq && rocq2mbt_c -R . My Geom.v && rocq2mbt_c -R . My Use.v)
moon test
```

**注意**：生成文件里全是公理，Rocq 并不知道 MoonBit 函数的行为。关于外部函数的性质，
只能作为额外的公理自己补充，并由你负责保证它们成立。

---

## 11. 后端兼容性与限制

| 情况 | wasm-gc | wasm | native | js |
| --- | --- | --- | --- | --- |
| 普通提取、原生类型、Prelude、互操作 | ✅ | ✅ | ✅ | 未测（本机没有 node） |
| 需要 `rocq_magic` 的代码 | ❌ 编译失败 | ✅ | ❌ 段错误 | 理论上可以 |

- **`rocq_magic`**：依赖类型等无法用 ML 类型表达的项需要 `Obj.magic`，MoonBit 里用
  `"%identity"` 实现，只在值表示统一的后端上有效。用到时插件会给出 warning。
  简单类型的程序不会产生 magic。
- 只支持单文件提取；未应用的函子会被省略。
- MoonBit 局部闭包没有 let 多态：Rocq 里局部 `let` 绑定的多态函数，如果在不同类型上使用，
  提取后过不了类型检查。
- trait 桥接：在 Rocq 里为某个类型自己写的实例，只在 Rocq 代码中通过字典起作用；
  把值交给外部 MoonBit 函数时，MoonBit 使用的是该类型在 MoonBit 中的 `impl`。
  目前不会为 Rocq 实例生成 MoonBit `impl`。
- `PrimString` 只映射类型和字面量：Rocq 字符串是字节串，MoonBit 字符串是 UTF-16，
  两边的运算语义不同。
- MoonBit 已不推荐对集合类型使用 `Show`，所以 Prelude 没有 `Show (Array A)` 实例。

---

## 12. 常见问题

**`Unknown extraction language MoonBit` / `Cannot find library rocq-mbt.plugin`**
Rocq 找不到插件。检查是否设置了
`OCAMLPATH=$ROCQ2MBT/_build/install/default/lib`（方式 A），或者执行过 `dune install`
（方式 B），以及当前是否在本地 switch 中（`source scripts/env.sh`）。

**`Unable to locate library ... with prefix RocqMbt`**
缺少 `-Q $ROCQ2MBT/_build/default/theories RocqMbt`，或者还没执行 `dune build`。

**`Cannot find a physical path bound to logical path Gen`（或你自己的前缀）**
`-R <目录> <前缀>` 中的目录不对。它应当指向生成的 `.v` 所在的目录，并且这个 `.v`
已经编译出 `.vo`。

**Rocq 报 `The term "0" has type "int" while it is expected to have type "nat"`**
`Open Scope uint63_scope` 之后数字字面量会被解释成 `int`。可以给字面量加作用域，如
`%nat`、`%uint63`，或者把作用域关掉。另外 `compare`、`length` 等名字可能被后导入的模块
覆盖，必要时写全名，如 `PrimInt63.compare`。

**MoonBit 报 `@rocqrt` 未定义 / 找不到包 `GreckF/rocqrt`**
提取出的包的 `moon.pkg` 必须写 `import { "GreckF/rocqrt" @rocqrt }`，模块的
`moon.mod` 里要导入 `GreckF/rocqrt@0.1.0`，并且 `moon.work` 中包含 `rocqrt` 的路径。

**MoonBit 报 `@geom` 等外部包未定义**
导入别名要和 `mbti2rocq --alias`（默认是包路径的最后一段）一致。

**同一个包里出现重复的 `Nat`、`List` 定义**
一个 MoonBit 包只能放一次提取的结果。多次提取请放到不同的包里，或者合并成一次提取。

**提取时出现 `The extracted MoonBit code uses unsafe coercions (rocq_magic)` 警告**
见第 11 节。只能用 `--target wasm` 运行，或者调整 Rocq 代码，避免依赖类型出现在计算部分。

**`AXIOM TO BE REALIZED` 或生成了 `RocqAny`**
有公理没有提取实现。可以用 `Extract Constant`、`Extract MoonBit Function` 实现它，
或者为公理类型写 `Extract Inlined Constant T => "MoonBitType"`。

**编译 `mbti2rocq` 时报 `The type Int32 is undefined`**
`moonbitlang/x` 的版本比工具链新。升级工具链，或者在旧工具链（moonc v0.10.8）上把 `mbt/mbti2rocq/moon.mod` 改为 `moonbitlang/x@0.4.50`；
改好后删除 `.mooncakes` 目录重新构建。

**`setup-opam.sh` 报 `Directory ... already exists`**
可能是之前的 switch 只建了一半。删除 `~/.local/share/rocq2mbt` 和项目里的 `_opam`
符号链接后重新运行。

---

## 13. 开发与测试

```bash
source scripts/env.sh
bash tests/run.sh                 # 默认在 wasm-gc wasm native 上测试
bash tests/run.sh native          # 只测某个后端
```

`tests/run.sh` 依次执行：

1. `dune build`（插件和 Rocq 库）；
2. `rocqrt` 的单元测试；
3. 构建 `mbti2rocq`；对 `tests/moon/mlib` 执行 `moon info` 和 `mbti2rocq`，生成
   `tests/gen/Mlib.v` 并编译；
4. 把 `tests/*.v` 分别提取到 `tests/moon/<pkg>/`；
5. 对 `basic`、`advanced`、`prim`、`interop` 在每个后端运行 `moon test`；
   对 `magic` 只在 wasm 上运行。

添加新特性时，在 `tests/*.v` 中加入用例，在对应的 `tests/moon/<pkg>/*_wbtest.mbt`
中加入运行时断言。插件源码在 `src/moonbit.ml`（打印器）和 `src/mbt_table.ml`
（互操作命令表），参考实现见 Rocq 源码 `plugins/extraction/haskell.ml`。
