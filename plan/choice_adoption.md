# Choice/Life Adoption Plan: sp

## Summary

- **lattice.nim**: defines Result[T, E] (no error type in lattice)
- **Error type**: defined in wire.nim -- stays in place
- **Files to modify**: 7 + re-export module + tests
- **Result sites**: 106 (81 are Result[void, E] -> Choice[bool])
- **Life**: Not applicable

## Steps

1. Delete `src/sp/lattice.nim`
2. In every file importing lattice:
   - Replace `import.*lattice` with `import basis/code/choice`
   - Replace `Result[T, E].good(v)` with `good(v)`
   - Replace `Result[T, E].bad(e[])` with `bad[T]("sp", e.msg)`
   - Replace `Result[T, E].bad(XError(msg: "x"))` with `bad[T]("sp", "x")`
   - Replace `Result[void, E](ok: true)` with `good(true)`
   - Replace return type `Result[T, E]` with `Choice[T]`
   - Replace return type `Result[void, E]` with `Choice[bool]`
3. Update re-export: `export lattice` -> `export choice`
4. Add `requires "basis >= 0.1.0"` to nimble if missing
5. Update tests
