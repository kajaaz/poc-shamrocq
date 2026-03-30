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
│   └── poc_boilerplate.rs       # Shamrocq VM test suite (11 tests)
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

```sh
# from your local shamrocq clone — copy our files
cp poc/poc_clean.scm /path/to/shamrocq/scheme/poc.scm
cp tests/poc_boilerplate.rs /path/to/shamrocq/crates/shamrocq/tests/poc_boilerplate.rs
cd /path/to/shamrocq
cargo test --test poc_boilerplate -- --nocapture
```

### Step 5 — Build bare-metal binary and measure size

To get the actual firmware size on a Cortex-M4 target:

```sh
# install the bare-metal target if not already done
rustup target add thumbv7em-none-eabihf

# go to the shamrocq baremetal example
cd /path/to/shamrocq/examples/baremetal

# replace the demo scheme with our boilerplate code
cp /path/to/poc-shamrocq/boilerplate/boilerplate_clean.scm scheme/demo.scm

# build in release mode (opt-level "s", LTO enabled)
cargo build --release

# measure the binary size
arm-none-eabi-size target/thumbv7em-none-eabihf/release/shamrocq-baremetal
# or, if cargo-binutils is installed:
cargo size --release
```

The `text` column in the output is the total flash footprint (VM runtime +
bytecode + glue code).

### Measured results (boilerplate transaction module)

| Component | Size |
|---|---|
| Shamrocq VM runtime (baseline, no app bytecode) | 11,872 bytes `.text` |
| Boilerplate bytecode (`bytecode.bin`) | 9,171 bytes |
| **Total bare-metal firmware** | **22,012 bytes `.text`** |
| Ledger FLASH budget (`memory.x`) | 16,384 bytes (16 KB) |
| **Overflow** | **5,628 bytes over budget** |

> Measured on `thumbv7em-none-eabihf`, release mode, `opt-level = "s"`, LTO
> enabled. The equivalent C transaction module compiles to ~1–2 KB `.text`.

The firmware does not fit in 16 KB FLASH today. See
[Current limitations](#current-limitations) for the path to reducing this.

## Current limitations

### Does not fit in 16 KB FLASH

The bare-metal binary (22 KB) exceeds the Ledger device budget (16 KB) by
~6 KB. The two main contributors:

1. **Shamrocq VM runtime (~12 KB)** — this is the interpreter itself,
   which is a fixed cost shared by all bytecode programs.
2. **Peano-encoded constants (~7 KB of bytecode)** — `MAX_TX_LEN` (510),
   `MAX_MEMO_LEN` (465), and `127` each expand into hundreds of nested
   `S(S(S(...O...)))` constructor chains because Rocq's default `nat`
   extracts to Peano naturals.

### Path to fitting in 16 KB

| Optimization | Expected saving | Difficulty |
|---|---|---|
| `Extract Inductive nat` — map `nat` to Scheme integers | ~7 KB bytecode | Low (Rocq directive) |
| Shamrocq FFI for integer constants (`foreign_fn`) | ~7 KB bytecode | Low (host-side) |
| VM size reduction (unused opcode removal, etc.) | ~1–3 KB | Medium (upstream) |

With `Extract Inductive nat` alone, the bytecode drops from 9.2 KB to
~2 KB, bringing total firmware to ~14 KB — within the 16 KB budget.

### No direct bare-metal output

`shamrocq-compiler` produces bytecode for the Shamrocq VM, not a standalone
`.elf`. The final firmware is built from the shamrocq repo's
`examples/baremetal/` scaffold, which embeds the bytecode via
`include_bytes!` and compiles the VM + bytecode together.

## Roadmap

- [x] Rocq spec + proofs + Scheme extraction
- [x] Shamrocq bytecode compilation
- [x] VM-level test suite (11 tests passing)
- [x] Bare-metal binary build + size measurement (22,012 B, overflows 16 KB by 5.6 KB)
- [ ] `Extract Inductive nat` optimization (expected to bring total under 16 KB)
- [ ] Marshalling layer for raw byte buffers (FFI)
- [ ] Replace `transaction_deserialize()` in app-boilerplate
- [ ] Validate with Speculos + Ragger test suite

## License

MIT
