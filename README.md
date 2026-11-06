# rocq2mbt — 把 Rocq 程序提取（extract）为 MoonBit

一个 Rocq **外部插件**，通过 Rocq 9.4 新增的可扩展 extraction API
（[rocq-prover/rocq#22541](https://github.com/rocq-prover/rocq/pull/22541)，
起源于 [#22487](https://github.com/rocq-prover/rocq/pull/22487) 的讨论）注册
`MoonBit` 提取语言。

```coq
From RocqMbt Require Import MoonBit.        (* 或 ExtrMoonBitBasic *)
Extraction Language MoonBit.
Extraction "pkg/out.mbt" my_function.
```

## 环境

- Rocq：`9.4+alpha`，即 rocq master 上的开发版。注意 git tag `V9.4+alpha`
  （2026-06-29）**早于** extraction 插件 API 的合并（2026-10-05），因此
  `scripts/setup-opam.sh` pin 的是一个包含该 API 的 master commit。
- opam：项目本地 switch。项目在 `/mnt/c` 上时，switch 实际放在
  `~/.local/share/rocq2mbt/_opam`（9p 文件系统上编译太慢），项目根的 `_opam`
  是指向它的符号链接。
- MoonBit 工具链：`~/.moon/bin`（只用于测试生成的代码）。

```bash
bash scripts/setup-opam.sh   # 一次性：建 switch，装 OCaml 5.4.1 + rocq-runtime/rocq-core (dev)
source scripts/env.sh        # 进入本地 switch
dune build                   # 编译插件 rocq-mbt.plugin 与 theories/（逻辑路径 RocqMbt）
bash tests/run.sh            # 提取 tests/*.v，并在 wasm-gc/wasm/native 上跑 moon test
```

不安装时使用插件：`OCAMLPATH=$PWD/_build/install/default/lib rocq c -Q _build/default/theories RocqMbt foo.v`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `src/moonbit.ml` | MoonBit 打印器（`language_descr`） |
| `src/g_moonbit.mlg` | `DECLARE PLUGIN "rocq-mbt.plugin"`，加载时 `register_language (External "MoonBit")` |
| `theories/MoonBit.v` | 加载 extraction 与本插件 |
| `theories/ExtrMoonBitBasic.v` | `bool/sumbool → Bool`、`option → Option`、`unit → Unit` |
| `tests/*.v` | 提取用例，输出到 `tests/moon/<pkg>/` |
| `tests/moon/` | MoonBit 测试模块，每个 `.v` 一个包，`*_wbtest.mbt` 是运行时测试 |

## 翻译方案

| Rocq / MiniML | MoonBit |
| --- | --- |
| 归纳类型 | `pub(all) enum T[A, B] { C(A, T[A, B]) }`，构造子一律限定 `T::C(..)` |
| 记录 | 单构造子 enum；投影是普通函数（match） |
| singleton 归纳类型 / 类型定义 | `pub type T[A] = ...`；若右边是类型变量（MoonBit 禁止）则在使用处展开 |
| 余归纳类型 `T` | `enum TCell` + `pub type T = RocqLazy[TCell]`；构造用 `rocq_lazy(fn() {..})`，match 前 `rocq_force` |
| 类型变量 | 按位置命名 `A, B, …`，自动跳过与本文件类型名冲突的字母 |
| 顶层函数 | **非柯里化**：`n` = 前导 λ 个数与类型箭头数的较小值，`pub fn f(x : A, y : B) -> C` |
| 调用 | 实参 ≥ n 直接调用（多余的柯里化调用）；不足 n 时先把非平凡实参 `let` 绑定（保证只求值一次），再 η 展开成柯里化闭包；作为值引用时也 η 展开 |
| 函数类型的值 | 一律是单参闭包 `(A) -> (B) -> C` |
| 多态常量（无参数且类型含变量）及非函数的 fixpoint | 无参泛型函数 `pub fn[A] c() -> List[A]`，引用写 `c()` |
| 单态常量 | `pub let c : T = ...` |
| 局部 `fix` | `letrec f = fn(x) {..} and g = ..`；非函数体的局部 cofix 变成 `fn() {..}` 并以 `f()` 引用 |
| `let ... in` | 语句块 `{ let x = ..; .. }`（连续 let 会被拉平） |
| `Obj.magic` | `rocq_magic`（`"%identity"`），见下文限制 |
| 无法表达的类型 (`Tunknown`/公理类型) | `RocqAny` |
| 被擦除的逻辑部分 | `Unit` / `()` |
| 异常分支、未实现公理 | `abort("...")` |
| 原生字符串 (`PrimString`) | MoonBit 字符串字面量（合法 UTF-8 原样输出） |

### 自定义提取（Extract Constant / Inductive）

- `Extract Constant c => "e"`：`e` 是具有**柯里化提取类型**的 MoonBit 表达式，
  例如 `Extract Inlined Constant Nat.add => "(fn(a) { fn(b) { a + b } })"`。
- `Extract Inductive t => "Ty" [ "c1" "c2" ] "m"`：构造子字符串在构造时被当作函数
  应用 `c2(x, y)`，在模式中被当作模式；可选的 match 函数 `m` 以
  `m(fn(..) { branch1 }, fn(..) { branch2 }, scrutinee)` 调用，每个分支是一个
  **非柯里化**函数（零参数构造子对应 `fn() {..}`）。示例见 `tests/Advanced.v`：

  ```coq
  Extract Inductive nat => "Int" [ "0" "(fn(n) { n + 1 })" ]
    "(fn(fO, fS, n) { if n == 0 { fO() } else { fS(n - 1) } })".
  ```

### 限制

- **`rocq_magic` 只在值表示统一的后端可用**：实测 `--target wasm` 正常，
  wasm-gc 编译失败、native 段错误（js 未测）。需要 magic 时插件会给出 warning。
  简单类型程序不会产生 magic，在所有后端都正确。
- 只支持单文件（monolithic）提取：`Extraction "f.mbt" ...`、`Recursive Extraction`、
  `Extraction foo`。`Separate Extraction`/`Extraction Library` 报错。
- 模块被拉平，同名定义由 Rocq 的 `Common` 自动改名（如 `k`、`k0`）；未应用的函子被省略。
- MoonBit 局部闭包没有 let 多态：Rocq 中局部 `let` 绑定的多态函数若在不同类型上使用会无法通过 MoonBit 类型检查。
- `Uint63`/`Float64`/原生数组常量尚未实现（生成 `abort`）。

## 测试

`tests/run.sh` 当前结果：`basic`（4 组）和 `advanced`（6 组）在 wasm-gc / wasm / native
上全部通过；`magic`（1 组）在 wasm 上通过。覆盖：递归/互递归、局部 fix、let、部分应用、
多态与高阶函数、多态常量、参数化归纳类型、记录、逻辑参数擦除、sig/sumbool、余归纳流、
互归纳类型、空类型、公理 + `Extract Constant`、自定义 `nat → Int`（含自定义 match）、模块拉平、
记录中的函数、原生字符串、依赖类型元数（magic）。
