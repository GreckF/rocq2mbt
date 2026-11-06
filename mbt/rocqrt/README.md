# GreckF/rocqrt

Runtime support for MoonBit code extracted from [Rocq](https://rocq-prover.org) by
[rocq2mbt](https://github.com/GreckF/rocq2mbt): Rocq's native 63-bit integers (`Uint63`),
floats (`Float64`) and persistent arrays (`PArray`, as diff-arrays).

Extracted code that uses Rocq's native types depends on this module:

```
// moon.mod
import { "GreckF/rocqrt@0.1.0" }

// moon.pkg of the extracted package
import { "GreckF/rocqrt" @rocqrt }
```

See the rocq2mbt repository for the extraction plugin and its documentation.
