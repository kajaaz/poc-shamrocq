# poc-shamrocq

Proof-of-concept: replacing critical C logic in a Ledger embedded app with
formally verified [Rocq](https://rocq-prover.org/) code, compiled to
bytecode via [Shamrocq](https://github.com/vbergeron/shamrocq) and executed
on a `no_std` VM targeting Cortex-M4 microcontrollers.

## Goal

Demonstrate that security-critical transaction parsing code (currently
hand-written C in
[LedgerHQ/app-boilerplate](https://github.com/LedgerHQ/app-boilerplate))
can be:

1. **Specified and proven correct** in Rocq (Gallina)
2. **Extracted** to Scheme automatically
3. **Compiled** to compact bytecode with `shamrocq-compiler`
4. **Executed** on bare-metal hardware via the Shamrocq VM (~12 KB `no_std` Rust)

The result is transaction parsing logic with **machine-checked guarantees**
(field lengths, encoding validity, data preservation) that the C version
cannot provide.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        This repo (poc-shamrocq)                     │
│                                                                     │
│  Rocq source (.v)                                                   │
│       │  rocq compile (type-check proofs + extract)                 │
│       ▼                                                             │
│  Scheme (.scm)                                                      │
│       │  shamrocq-compiler                                          │
│       ▼                                                             │
│  bytecode.bin + funcs.rs + ctors.rs                                 │
└──────────────────────────┬──────────────────────────────────────────┘
                           │  embedded as static data
┌──────────────────────────▼──────────────────────────────────────────┐
│                   Firmware (shamrocq repo)                           │
│                                                                     │
│  Shamrocq VM runtime (no_std Rust, ~12 KB)                          │
│       + bytecode.bin (our proven logic)                              │
│       │  cargo build --target thumbv7em-none-eabi                   │
│       ▼                                                             │
│  firmware.elf  →  runs on Cortex-M4 / QEMU / Ledger                │
└─────────────────────────────────────────────────────────────────────┘
```

The bytecode is **data**, not native code. It requires the Shamrocq VM
interpreter to execute. The final bare-metal binary is built from the
[shamrocq](https://github.com/vbergeron/shamrocq) repo, which provides
the `no_std` VM runtime and a bare-metal `main()` scaffold (see
`examples/baremetal/`).

## Repository structure

```
poc-shamrocq/
├── poc/                         # Initial PoC — simple Rocq functions
│   ├── Poc.v                    # Rocq definitions + proofs + extraction
│   ├── _CoqProject
│   └── Makefile
├── boilerplate/                 # Ledger boilerplate transaction module
│   ├── Boilerplate.v            # Rocq equivalent of deserialize.c / utils.c
│   ├── boilerplate_clean.scm    # Extracted Scheme (header stripped)
│   ├── README.md                # Detailed comparison with C version
│   ├── _CoqProject
│   └── Makefile
├── tests/
│   ├── poc_boilerplate.rs       # Shamrocq VM test suite (11 tests)
│   └── baremetal_main.rs        # Drop-in main.rs for bare-metal firmware
└── README.md                    # This file
```

## What was translated

### `poc/Poc.v` — graduated PoC functions

| # | Function | Type | Purpose |
|---|----------|------|---------|
| 1 | `successor` | `nat → nat` | Simplest roundtrip (Peano +1) |
| 2 | `negb` | `bool → bool` | Boolean negation |
| 3 | `valid_nonce` | `nat → bool` | Nonzero check |
| 4 | `in_range` | `nat → nat → nat → bool` | Bounds check `lo ≤ n ≤ hi` |
| 5 | `sum_list` | `list nat → nat` | Fold over list |
| 6 | `safe_head` | `list nat → option nat` | Head with `None` for empty |
| 7 | `take` / `drop` | `nat → list nat → list nat` | Buffer slicing |
| 8 | `parse_field` | `nat → list nat → option (list nat × list nat)` | Fixed-size field parser |
| 9 | `parse_transaction` | `list nat → option transaction` | Full transaction parser |

### `boilerplate/Boilerplate.v` — Ledger app-boilerplate transaction module

Direct translation of C code from `src/transaction/` in the Ledger
boilerplate app:

| C file | C function / type | Rocq equivalent |
|---|---|---|
| `tx_types.h` | `parser_status_e` | `parser_status` (8 error codes) |
| `tx_types.h` | `transaction_t` | `transaction` (MkTransaction) |
| `utils.c` | `transaction_utils_check_encoding` | `check_encoding` |
| `deserialize.c` | `transaction_deserialize` | `deserialize_transaction` |

See [`boilerplate/README.md`](boilerplate/README.md) for the full
comparison (size, functionality, proofs).

## Proven properties

### PoC (`Poc.v`)

| Theorem | Statement |
|---------|-----------|
| `negb_involutive` | `negb (negb b) = b` |
| `valid_nonce_spec` | `valid_nonce n = true ↔ n ≠ 0` |
| `in_range_spec` | `in_range lo hi n = true ↔ lo ≤ n ∧ n ≤ hi` |
| `sum_list_app` | `sum_list (l₁ ++ l₂) = sum_list l₁ + sum_list l₂` |
| `take_drop` | `take n l ++ drop n l = l` |
| `parse_field_sound` | Parsed field has correct length, data preserved |

### Boilerplate (`Boilerplate.v`)

| Theorem | Statement |
|---------|-----------|
| `deserialize_nonce_len` | nonce is exactly 8 bytes |
| `deserialize_to_len` | address is exactly 20 bytes |
| `deserialize_value_len` | value is exactly 8 bytes |
| `deserialize_memo_bounded` | memo length ≤ `MAX_MEMO_LEN` |
| `deserialize_encoding_valid` | every memo byte ≤ 127 (ASCII) |
| `deserialize_preserves_data` | `nonce ++ to ++ value ++ memo = input` |

These are **compile-time guarantees** — they hold for any input and cannot
be violated. The C code relies on manual review for the same invariants.

## How to build

### Prerequisites

- [Rocq](https://rocq-prover.org/) ≥ 9.0 (`opam install rocq-prover`)
- [shamrocq](https://github.com/vbergeron/shamrocq) cloned locally
  (provides `shamrocq-compiler`)
- Rust toolchain with `thumbv7em-none-eabihf` target (for bare-metal build)

### Step 1 — Compile Rocq and extract Scheme

```sh
cd poc && make            # produces poc.scm
cd boilerplate && make    # produces boilerplate.scm
```

### Step 2 — Strip the extraction header

Rocq's Scheme extraction inserts `(load "macros_extr.scm")` at the top of
the output. This must be removed because `shamrocq-compiler` handles the
required macros (`lambdas`, `@`, `match`, quasiquote) natively.

```sh
grep -v '(load ' poc/poc.scm > poc/poc_clean.scm
grep -v '(load ' boilerplate/boilerplate.scm > boilerplate/boilerplate_clean.scm
```

### Step 3 — Compile to Shamrocq bytecode

```sh
shamrocq-compiler -o poc/out/ poc/poc_clean.scm
shamrocq-compiler -o boilerplate/out/ boilerplate/boilerplate_clean.scm
```

### Step 4 — Run tests on the Shamrocq VM

This repo does not duplicate the shamrocq build infrastructure. Instead,
the `tests/` directory contains files that are copied into a local
[shamrocq](https://github.com/vbergeron/shamrocq) clone to run.

```sh
# copy our files into your local shamrocq clone
cp poc/poc_clean.scm /path/to/shamrocq/scheme/poc.scm
cp tests/poc_boilerplate.rs /path/to/shamrocq/crates/shamrocq/tests/poc_boilerplate.rs

# run the tests
cd /path/to/shamrocq
cargo test --test poc_boilerplate -- --nocapture
```

### Step 5 — Build and run the bare-metal firmware

The bare-metal firmware is built using shamrocq's existing
`examples/baremetal/` scaffold. We provide a drop-in `main.rs` and Scheme
file — the scaffold itself (Cargo.toml, build.rs, memory.x, linker config)
stays in the shamrocq repo and does not need to be duplicated.

```sh
# copy our files into the shamrocq baremetal example
cp boilerplate/boilerplate_clean.scm /path/to/shamrocq/examples/baremetal/scheme/demo.scm
cp tests/baremetal_main.rs /path/to/shamrocq/examples/baremetal/src/main.rs

# install the bare-metal target if not already done
rustup target add thumbv7em-none-eabihf

# build and measure size
cd /path/to/shamrocq/examples/baremetal
cargo build --release
size target/thumbv7em-none-eabihf/release/shamrocq-baremetal

# run on QEMU (requires qemu-system-arm)
cargo run --release
```

Expected output:

```
check_encoding("Hello") = true
deserialize OK: nonce=8 to=20 value=8 memo=1
deserialize(5 bytes) rejected = true
--- all checks passed ---
```

To restore the shamrocq example to its original state:

```sh
cd /path/to/shamrocq/examples/baremetal
git checkout -- scheme/demo.scm src/main.rs
```

### Measured results (boilerplate transaction module)

| Component | Before optimization | After `Extract Constant` |
|---|---|---|
| Boilerplate bytecode (`bytecode.bin`) | 9,171 bytes | **1,263 bytes** |
| Extracted Scheme lines | 183 | 108 |
| **Total bare-metal firmware (`.text`)** | **21,428 bytes** | **13,432 bytes** |
| Ledger FLASH budget (`memory.x`) | 16,384 bytes (16 KB) | 16,384 bytes |

> Measured on `thumbv7em-none-eabihf`, release mode, `opt-level = "s"`, LTO
> enabled. The equivalent C transaction module compiles to ~1–2 KB `.text`.

The `Extract Constant` workaround reduced bytecode by **86%** (9.2 KB →
1.3 KB) and brought the total bare-metal firmware from 21.4 KB down to
**13.4 KB** — now fitting within the 16 KB Ledger FLASH budget with
~3 KB to spare. See [Peano bloat workaround](#peano-bloat-and-the-extract-constant-workaround)
below.

## Peano bloat and the `Extract Constant` workaround

Rocq's default `nat` type is Peano-encoded: every number N is represented
as N nested `S(S(S(...O...)))` constructors. When extracting to Scheme,
constants like `MAX_TX_LEN = 510` become enormous nested trees, inflating
bytecode.

**The problem:** `Extract Inductive nat` (the standard Rocq directive to
replace the entire `nat` type with native integers) does not work with
shamrocq-compiler. Rocq wraps the replacement constructors in quasiquote
syntax (`` `((lambda (n) (+ n 1)) ,x) ``), but shamrocq expects atoms
as quasiquote list heads. This needs upstream shamrocq support.

**The workaround:** every numeric literal used in the code was given a
named Rocq `Definition`, then extracted directly to a native Scheme integer
using `Extract Constant`:

```coq
Definition NONCE_LEN : nat := 8.
Definition VALUE_LEN : nat := 8.
Definition MAX_ASCII : nat := 127.

Extract Constant NONCE_LEN => "8".
Extract Constant VALUE_LEN => "8".
Extract Constant MAX_ASCII => "127".
(* same for MAX_TX_LEN, ADDRESS_LEN, MAX_MEMO_LEN *)
```

This produces `(define nONCE_LEN 8)` in Scheme instead of 8 nested `S`
constructors — and the proofs are unaffected because Rocq unfolds these
definitions during type-checking.

**Result:** bytecode dropped from **9,171 → 1,263 bytes** (86% reduction),
Scheme from 183 → 108 lines.

## Current limitations

### Bare-metal firmware fits in 16 KB

After the `Extract Constant` optimization, the bare-metal firmware is
**13,432 bytes** (`.text`) — fitting within the 16 KB Ledger FLASH
budget with 2,952 bytes to spare. Before the optimization it was 21,428
bytes and overflowed by ~5 KB.

### `Extract Inductive nat` not yet supported

The more general `Extract Inductive nat` directive (which would eliminate
**all** Peano encoding, not just named constants) does not work with
shamrocq-compiler today. The `Extract Constant` workaround covers the
named constants but small inline numbers (e.g., loop counters) may still
use Peano encoding. See the comment in `Boilerplate.v` for the exact
directives, ready to uncomment once shamrocq adds support.

### Path to further optimization

| Optimization | Expected saving | Difficulty |
|---|---|---|
| `Extract Inductive nat` upstream support in shamrocq | Eliminates all remaining Peano | Medium (upstream) |
| VM size reduction (unused opcode removal, etc.) | ~1–3 KB | Medium (upstream) |

### Bare-metal build uses shamrocq's scaffold

`shamrocq-compiler` produces bytecode for the Shamrocq VM, not a standalone
`.elf`. The final firmware is built from the shamrocq repo's
`examples/baremetal/` scaffold, which provides the `no_std` VM runtime,
linker script, and build infrastructure. We only provide a drop-in
`main.rs` and the Scheme file — we don't duplicate the scaffold to avoid
maintaining a copy that can go out of sync with upstream.

## Roadmap

- [x] Rocq spec + proofs + Scheme extraction
- [x] Shamrocq bytecode compilation
- [x] VM-level test suite (11 tests passing)
- [x] Bare-metal binary build + size measurement
- [x] `Extract Constant` workaround — bytecode 9.2 KB → 1.3 KB, firmware 21.4 KB → **13.4 KB** (fits in 16 KB)
- [ ] `Extract Inductive nat` upstream support in shamrocq (eliminates all Peano encoding)
- [ ] Marshalling layer for raw byte buffers (FFI)
- [ ] Replace `transaction_deserialize()` in app-boilerplate
- [ ] Validate with Speculos + Ragger test suite

## License

MIT
