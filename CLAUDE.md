# rocq2mbt 工作约定

- 先读 `README.md`（环境、翻译方案、限制）。用中文交流。
- 一切构建在 WSL Ubuntu 里进行：`source scripts/env.sh` 进入项目本地 opam switch
  （真实位置 `~/.local/share/rocq2mbt/_opam`，`_opam` 是符号链接）。不要往全局 switch 装东西。
- Rocq 是 master 上的 9.4+alpha 开发版，commit 固定在 `scripts/setup-opam.sh` 的
  `ROCQ_COMMIT`。extraction 源码参考：`~/src/rocq/plugins/extraction`（`common.mli`、
  `miniml.mli`、`haskell.ml` 最接近本插件）。MoonBit 文档：`~/src/moonbit-docs`。
- 改完插件后跑 `bash tests/run.sh`；新特性要在 `tests/*.v` 加用例并在
  `tests/moon/<pkg>/*_wbtest.mbt` 加运行时断言。每个 `.v` 提取到自己的 moon 包。
- 翻译设计已与用户确认：顶层非柯里化 + 调用点饱和/η 展开；Obj.magic 用 `%identity` + warning；
  多态常量变成无参泛型函数；Uint63 用 UInt64（< 2^63）；PArray 用 diff-array；外部函数用
  `Extract MoonBit Function` 模板；trait ↔ Rocq Class + 静态分派桥接（外部调用丢字典、泛型加约束）；
  raise → Result，async 跳过，`Extract MoonBit Raise` 把 Rocq 的 Result 函数提取成 raise 函数。
  遇到新的 extraction 设计问题先问用户。
- MoonBit 部分在 `mbt/`：`rocqrt`（运行时）和 `mbti2rocq`（工具，依赖 `moonbitlang/x@0.4.50`，
  因为本机工具链是 2026-08-14 的，0.5.x 不兼容）。改了 `rocqrt` 后 `tests/moon/moon.work` 自动引用。
- 外部 MoonBit 包的语义只在 MoonBit 侧：生成的 Rocq 文件全是公理，不要往里面加定理。
- MoonBit 语法要点（moonc v0.10.8 实测）：类型别名是 `type A = B`（不是 `typealias`）；
  别名右边不能是类型参数；`derive(Show)` 已废弃；`%identity` 在 wasm-gc/native 上不能跨表示转换；
  `try?` 已废弃（用 `try e catch { .. } noraise { .. }`）；十六进制浮点要有小数部分（`0x1.0p3`）；
  跨包结构体不能写 `@pkg.S::{..}` 模式（用自定义 match）；带标签构造子必须带标签构造。
