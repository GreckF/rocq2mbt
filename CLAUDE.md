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
  多态常量变成无参泛型函数。遇到新的 extraction 设计问题先问用户。
- MoonBit 语法要点（moonc v0.10.8 实测）：类型别名是 `type A = B`（不是 `typealias`）；
  别名右边不能是类型参数；`derive(Show)` 已废弃；`%identity` 在 wasm-gc/native 上不能跨表示转换。
