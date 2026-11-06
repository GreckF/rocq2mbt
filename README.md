# rocq2mbt — Rocq 与 MoonBit 的提取与互操作

**中文** | [English](README.en.md)

由三部分组成：

1. **Rocq 外部插件** `rocq-mbt.plugin`：通过 Rocq 9.4 新增的可扩展 extraction API
   （[rocq-prover/rocq#22541](https://github.com/rocq-prover/rocq/pull/22541)，
   起源于 [#22487](https://github.com/rocq-prover/rocq/pull/22487) 的讨论）注册
   `MoonBit` 提取语言，并提供互操作命令（`Extract MoonBit Function/Trait/Raise`）。
2. **配套 Rocq 模块**（`theories/`，逻辑路径 `RocqMbt`）：Rocq 原生类型
   （`PrimInt63`/`PrimFloat`/`PrimArray`/`PrimString`）的提取、MoonBit 内建类型与 trait。
3. **MoonBit 工具**（`mbt/`）：运行时包 `rocqrt`，以及从 `.mbti` 生成 Rocq 公理的
   `mbti2rocq`，提取时这些公理还原为对原 MoonBit 包的调用。

```coq
From RocqMbt Require Import Prelude.     (* 或 MoonBit / ExtrMoonBitBasic / ExtrMoonBitPrim *)
Extraction "pkg/out.mbt" my_function.
```

**完整的安装与使用说明见 [docs/USAGE.md](docs/USAGE.md)**：包括安装步骤、三个可运行的
快速上手示例、各模块和命令的参考，以及常见问题。

## 环境

- Rocq：`9.4+alpha`，即 rocq master 上的开发版。注意 git tag `V9.4+alpha`
  （2026-06-29）**早于** extraction 插件 API 的合并（2026-10-05），因此
  `scripts/setup-opam.sh` pin 的是一个包含该 API 的 master commit。
- opam：项目本地 switch。项目在 `/mnt/c` 上时，switch 实际放在
  `~/.local/share/rocq2mbt/_opam`（9p 文件系统上编译太慢），项目根的 `_opam`
  是指向它的符号链接。
- MoonBit 工具链：`~/.moon/bin`（moonc v0.10.20，2026-11-05；也在 v0.10.8 上测试过）。
  `mbti2rocq` 依赖 `moonbitlang/x@0.5.7`。

```bash
bash scripts/setup-opam.sh   # 一次性：建 switch，装 OCaml 5.4.1 + rocq-runtime/rocq-core (dev)
source scripts/env.sh        # 进入本地 switch
dune build                   # 编译插件与 theories/
bash tests/run.sh            # 全部测试（见下文）
```

不安装时使用插件：`OCAMLPATH=$PWD/_build/install/default/lib rocq c -Q _build/default/theories RocqMbt foo.v`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `src/moonbit.ml` | MoonBit 打印器（`language_descr`） |
| `src/mbt_table.ml` | 互操作命令的表（libobject，随 `Require` 持久化） |
| `src/g_moonbit.mlg` | 插件声明、语言注册、`Extract MoonBit ...` 命令 |
| `theories/MoonBit.v` | 加载 extraction 与本插件 |
| `theories/ExtrMoonBitBasic.v` | `bool/sumbool → Bool`、`option → Option`、`unit → Unit`、`prod → 元组` |
| `theories/ExtrMoonBitPrim.v` | `int → UInt64`、`float → Double`、`array → @rocqrt.PArray`、`string → String` 及全部原生运算 |
| `theories/Prelude.v` | `Result`、MoonBit 内建类型（`Int`、`String`、`Array` …）、trait 类 `Eq/Compare/Show/Hash` 与实例 |
| `mbt/rocqrt/` | MoonBit 运行时（模块 `GreckF/rocqrt`）：Uint63、Float64、diff-array 持久数组 |
| `mbt/mbti2rocq/` | MoonBit 工具：`.mbti` → Rocq |
| `tests/*.v` | 提取用例，输出到 `tests/moon/<pkg>/` |
| `tests/moon/` | MoonBit 测试模块（`moon.work` 引入 `rocqrt`）；`mlib` 是互操作示例库 |
| `tests/gen/Mlib.v` | `mbti2rocq` 由 `tests/moon/mlib` 生成（测试时重新生成） |

## 提取：翻译方案

| Rocq / MiniML | MoonBit |
| --- | --- |
| 归纳类型 | `pub(all) enum T[A, B] { C(A, T[A, B]) }`，构造子一律限定 `T::C(..)` |
| 记录 | 单构造子 enum；投影是普通函数（match） |
| singleton 归纳类型 / 类型定义 | `pub type T[A] = ...`；若右边是类型变量（MoonBit 禁止）则在使用处展开 |
| 余归纳类型 `T` | `enum TCell` + `pub type T = RocqLazy[TCell]`；构造用 `rocq_lazy(fn() {..})`，match 前 `rocq_force` |
| 类型变量 | 按位置命名 `A, B, …`，自动跳过与本文件类型名冲突的字母 |
| 顶层函数 | **非柯里化**：`n` = 前导 λ 个数与类型箭头数的较小值，`pub fn f(x : A, y : B) -> C` |
| 调用 | 实参 ≥ n 直接调用；不足 n 时先把非平凡实参 `let` 绑定（只求值一次），再 η 展开成柯里化闭包；作为值引用时也 η 展开 |
| 函数类型的值 | 一律是单参闭包 `(A) -> (B) -> C` |
| 多态常量 / 非函数的 fixpoint | 无参泛型函数 `pub fn[A] c() -> List[A]`，引用写 `c()` |
| 单态常量 | `pub let c : T = ...` |
| 局部 `fix` | `letrec f = fn(x) {..} and g = ..`；非函数体的局部 cofix 变成 `fn() {..}` |
| `let ... in` | 语句块 `{ let x = ..; .. }`（连续 let 会被拉平） |
| `Obj.magic` | `rocq_magic`（`"%identity"`），见限制 |
| 无法表达的类型 | `RocqAny` |
| 被擦除的逻辑部分 | `Unit` / `()` |
| 异常分支、未实现公理 | `abort("...")` |
| 原生字面量 | `42UL`（int63）、`0x1.8p3` / `(0.0 / 0.0)`（float）、`@rocqrt.PArray::of_array([..], def)`（array）、字符串字面量 |

### 自定义提取

- `Extract Constant c => "e"`：`e` 是具有**柯里化提取类型**的 MoonBit 表达式。
- `Extract Inductive t => "Ty" [ "c1" "c2" ] "m"`：构造子字符串在构造时当函数应用
  `c2(x, y)`、在模式里当模式；字符串中含 `$i` 时作为模板（如
  `"@pkg.Shape::Rect(w=$0, h=$1)"`）。可选 match 函数 `m` 以
  `m(fn(..) { 分支1 }, …, 被匹配值)` 调用，分支是**非柯里化**函数。
  `"(,)"` 表示 MoonBit 元组。

### 互操作命令（本插件新增）

| 命令 | 作用 |
| --- | --- |
| `Extract MoonBit Function f [n] => "tpl".` | 用调用模板实现 `f`：`$i` 是第 i 个非字典实参，`n`（默认为占位符个数）是消耗的实参数。饱和调用直接展开模板，部分应用 η 展开，模板含闭包或重复占位符时先绑定实参 |
| `Extract MoonBit Trait C => "@pkg.Trait".` | 类（record）`C` 是 MoonBit trait 的字典类型：调用外部函数时丢掉 `C` 类型的字典实参（MoonBit 静态分派），有 `C A` 参数的泛型函数自动加约束 `A : Trait` |
| `Extract MoonBit Raise f.` | Rocq 函数 `f : .. -> Result T E` 提取为 `-> T raise E`；调用处用 `try … catch … noraise` 转回 `Result`；`E` 若是 Rocq 归纳类型则打印成 `suberror` |

## 配套 Rocq 模块

- **`ExtrMoonBitPrim`**：Rocq 原生 63 位整数用 `UInt64` 表示（值保持 < 2^63，
  有符号运算按第 62 位作符号位）；`float` 即 `Double`；`PrimArray.array` 是
  `@rocqrt.PArray`（Baker diff-array，线性使用 O(1)，访问旧版本时重根）。
  语义逐一对照 Rocq 内核的 `uint63_63.ml` / `float64_common.ml` / `parray.ml`。
  `comparison`、`carry`、`float_class`、`float_comparison` 映射到 `@rocqrt` 中的枚举。
- **`Prelude`**（含上面两个）：`Result`（对应 MoonBit `Result`）；内建类型
  `Int Int64 UInt UInt64 Byte Char String Bytes Error Array`，`Double := float`；
  转换（`Int_of_uint63` 等）、`Int` 算术、`String`、纯函数式 `Array` 操作；
  trait 类 `Eq Compare Show Hash` 及内建类型实例（实例方法统一用
  `Builtin.equal` 等泛型公理，提取后在具体类型或带约束处静态分派）。

提取后的 MoonBit 包需要在 `moon.pkg` 里 `import { "GreckF/rocqrt" @rocqrt }`，
模块层面依赖 `GreckF/rocqrt`（本仓库用 `moon.work`）。

## mbti2rocq

```bash
cd mbt/mbti2rocq && moon build --target native --release
_build/native/release/build/cmd/main/main.exe path/pkg.generated.mbti -o Pkg.v [--alias @pkg]
```

把 `moon info` 生成的接口翻译成 `From RocqMbt Require Import Prelude.` 之上的 Rocq 文件：

| MoonBit | Rocq |
| --- | --- |
| `pub fn f(A, B) -> C` | `Axiom f : A -> B -> C.` + `Extract MoonBit Function f => "@pkg.f($0, $1)".` |
| 方法 `fn T::m(Self, ..)` | `T_m`，模板 `@pkg.T::m(..)` |
| 无参函数 | `unit -> R`（推迟副作用） |
| 带标签参数 `x~ : T` / 可选参数 `x? : T` | 位置参数、模板写 `x=$i` / 省略（用默认值） |
| `fn[A : Eq] ..` | `forall {A : Type} `{Eq A}, ..` |
| `-> T raise E` | `-> Result T E`，模板包 `try … catch … noraise` |
| 多参函数类型 `(A, B) -> C` | 柯里化 `A -> B -> C`，模板里双向转换（参数和返回值） |
| `pub(all) enum` / `suberror` | `Inductive` + `Extract Inductive`（带标签构造子用模板） |
| `pub(all) struct`（≥2 字段、无 `mut`） | `Record` + `Extract Inductive`（构造模板 + 自定义 match） |
| 其他类型（私有字段、`mut`、单字段/单构造子包装、不满足严格正性的递归） | `Axiom T : Type.` + 字段读取/构造/析构公理 |
| `pub let` / `pub const` | `Axiom` + 模板 `@pkg.x` |
| `trait T { m(Self) -> X }` | `Class T (Self : Type) := { m : Self -> X }.` + `Extract MoonBit Trait` + 泛型方法公理 |
| `impl T for X` | `#[global] Instance T_X : T X.`（Prelude trait 用 `Builtin.*`） |
| 外部包类型 `@json.Json` 等 | 自动生成 `Axiom json_Json : Type.` + 提取指令 |

不能翻译的声明（`async`、`&Trait`、未知 trait 约束、容器里的多参函数、3 元以上元组等）
跳过，原因写在生成文件末尾的注释里。已在 core 的 `@math`/`@list`/`@json` 上验证生成文件可被
Rocq 编译。

## 限制

- **`rocq_magic` 只在值表示统一的后端可用**：实测 `--target wasm` 正常，
  wasm-gc 编译失败、native 段错误（js 未测）。需要时插件会给出 warning。
- 只支持单文件（monolithic）提取。`Separate Extraction`/`Extraction Library` 报错。
- 模块被拉平，同名定义自动改名（如 `k`、`k0`）；未应用的函子被省略。
- MoonBit 局部闭包没有 let 多态。
- trait 字典与 MoonBit 静态分派的桥接：Rocq 中用户自己写的实例只在 Rocq 代码里经字典
  使用；传给外部 MoonBit 函数时，MoonBit 用的是该类型自己的 `impl`（第一版不为 Rocq
  实例生成 MoonBit `impl`）。
- `PrimString` 只映射类型和字面量（Rocq 字符串是字节串，MoonBit 是 UTF-16）。

## 测试

`bash tests/run.sh`：`rocqrt` 单元测试（5 组）；`basic`(4) / `advanced`(6) /
`prim`(5) / `interop`(5) 在 wasm-gc、wasm、native 上全部通过；`magic`(1) 在 wasm 上通过。
`interop` 是完整链路：`tests/moon/mlib` → `moon info` → `mbti2rocq` → `tests/gen/Mlib.v`
→ `tests/Interop.v` 调用 → 提取 → `tests/moon/interop` 运行。
