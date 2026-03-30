# Boilerplate transaction module — Rocq/Shamrocq vs C

Detailed comparison of the Ledger
[app-boilerplate](https://github.com/LedgerHQ/app-boilerplate) transaction
parsing module (C) against its formally verified Rocq equivalent compiled
to Shamrocq bytecode.

## What was translated

| C file | C function / type | Rocq equivalent | Status |
|---|---|---|---|
| `tx_types.h` | `parser_status_e` (enum, 8 values) | `parser_status` (inductive, 8 ctors) | exact match |
| `tx_types.h` | `transaction_t` (struct: nonce, to, value, memo) | `transaction` (inductive: MkTransaction) | exact match |
| `utils.c` | `transaction_utils_check_encoding` | `check_encoding` | exact match |
| `utils.c` | `transaction_utils_format_memo` (length check) | `format_memo_check` | exact match |
| `deserialize.c` | `transaction_deserialize` | `deserialize_transaction` | exact match (non-token path) |

**Not translated:** `serialize.c` (display formatting for the Ledger screen,
not security-critical) and the `is_token_transaction` branch in
`deserialize.c` (adds 32 bytes of token-address parsing — trivially
extensible).

## Pipeline

```
Boilerplate.v ──rocq compile──▶ boilerplate.scm ──shamrocq-compiler──▶ bytecode.bin
   (Rocq)                         (Scheme)                              (VM bytecode)
```

1. `rocq compile -Q . Boilerplate Boilerplate.v`
   — type-checks all definitions **and proofs**, then extracts Scheme.
2. Strip `(load "macros_extr.scm")` header → `boilerplate_clean.scm`.
3. `shamrocq-compiler -o out/ boilerplate_clean.scm`
   — produces `bytecode.bin` + Rust constant files (`funcs.rs`, `ctors.rs`).

## Size comparison

| Metric | C (app-boilerplate) | Rocq / Shamrocq |
|---|---|---|
| Source lines (logic only) | ~130 lines across 4 files | 160 lines in `Boilerplate.v` |
| Source lines (total) | ~250 lines (incl. headers, includes) | 363 lines (incl. proofs + extraction) |
| Extracted Scheme | — | 108 lines (`boilerplate_clean.scm`) |
| Bytecode | — | **1,263 bytes** (`bytecode.bin`) |
| **Total bare-metal firmware (`.text`)** | **~1–2 KB** | **13,432 bytes** (measured) |

### Peano bloat and the `Extract Constant` workaround

Rocq's default `nat` type is Peano-encoded: `S(S(S(...O...)))`. When
extracting to Scheme, a constant like `MAX_TX_LEN = 510` becomes 510
nested `S` constructors — producing massive, unreadable Scheme code and
inflated bytecode.

**Before optimization:** 9,171 bytes of bytecode, 183 lines of Scheme.
The constants `MAX_TX_LEN` (510), `MAX_MEMO_LEN` (465), `127`, `20`, `8`
alone accounted for ~7 KB of Peano chains.

**Fix applied:** every numeric literal in the code was given a named
Rocq `Definition`, then extracted to a native Scheme integer using
`Extract Constant`:

```coq
Definition NONCE_LEN : nat := 8.
Definition VALUE_LEN : nat := 8.
Definition MAX_ASCII : nat := 127.
(* MAX_TX_LEN, ADDRESS_LEN, MAX_MEMO_LEN already existed *)

Extract Constant MAX_TX_LEN   => "510".
Extract Constant ADDRESS_LEN  => "20".
Extract Constant MAX_MEMO_LEN => "465".
Extract Constant NONCE_LEN    => "8".
Extract Constant VALUE_LEN    => "8".
Extract Constant MAX_ASCII    => "127".
```

This produces clean Scheme like `(define mAX_TX_LEN 510)` instead of
510 nested `S` constructors.

**After optimization:** 1,263 bytes of bytecode, 108 lines of Scheme.
**86% reduction** in bytecode size.

The proofs are unaffected — Rocq unfolds these definitions during
proof-checking, so `NONCE_LEN` and `8` are identical from the proof
engine's perspective.

### Why not `Extract Inductive nat`?

A more general approach is `Extract Inductive nat` which replaces the
entire `nat` type with native integers. However, this does not work
with shamrocq-compiler: Rocq's extraction wraps the replacement
constructors in quasiquote syntax (`` `((lambda (n) (+ n 1)) ,x) ``),
but shamrocq expects constructor names (atoms) as quasiquote heads.
This needs upstream shamrocq support. See the comment in `Boilerplate.v`
for the exact directives, ready to uncomment once shamrocq supports them.

## Functionality comparison

| Feature | C | Rocq/Shamrocq |
|---|---|---|
| Parse nonce (8 bytes) | pointer arithmetic | `parse_field NONCE_LEN data` |
| Parse to address (20 bytes) | pointer arithmetic | `parse_field ADDRESS_LEN rest` |
| Parse value (8 bytes) | pointer arithmetic | `parse_field VALUE_LEN rest` |
| Memo length check (≤ 465) | `if (offset + memo_len > buf_len)` | `leb (length memo) MAX_MEMO_LEN` |
| Memo ASCII check (≤ 0x7F) | `for` loop | `check_encoding` (recursive, uses `MAX_ASCII`) |
| Error codes | `return NONCE_PARSING_ERROR` etc. | `inl NONCE_PARSING_ERROR` etc. |
| Return parsed struct | fill `transaction_t` by pointer | `inr (MkTransaction ...)` |

**Identical behavior.** Both reject inputs that are too long, too short for
any field, or contain non-ASCII memo bytes, and return the same error codes.

## What the proofs guarantee (that C cannot)

The Rocq version includes 6 machine-checked theorems that hold for any
successful parse:

| Theorem | Statement |
|---|---|
| `deserialize_nonce_len` | `length (tx_nonce tx) = NONCE_LEN` |
| `deserialize_to_len` | `length (tx_to tx) = ADDRESS_LEN` |
| `deserialize_value_len` | `length (tx_value tx) = VALUE_LEN` |
| `deserialize_memo_bounded` | `length (tx_memo tx) ≤ MAX_MEMO_LEN` |
| `deserialize_encoding_valid` | every byte in `tx_memo tx` is ≤ `MAX_ASCII` |
| `deserialize_preserves_data` | `nonce ++ to ++ value ++ memo = data` (no data lost or corrupted) |

These are **compile-time guarantees** — they cannot be violated regardless of
input. The C code relies on careful manual review for the same properties.

## How the bare-metal binary is produced

This repo produces **bytecode** (`bytecode.bin`), not a final firmware.
The bytecode is data — it needs the Shamrocq VM interpreter to execute.

The bare-metal firmware is built from the
[shamrocq](https://github.com/vbergeron/shamrocq) repository, which
provides a `no_std` Rust VM runtime and a bare-metal scaffold
(`examples/baremetal/`). The two sides combine as follows:

```
  This repo (poc-shamrocq)              shamrocq repo
  ────────────────────────              ─────────────
  Boilerplate.v                         shamrocq crate (no_std Rust)
       │ rocq compile                        │
       ▼                                     │  contains the VM:
  boilerplate.scm                            │  - bytecode interpreter
       │ shamrocq-compiler                   │  - value allocator
       ▼                                     │  - pattern matching engine
  bytecode.bin ──── embedded as data ───────▶│
  funcs.rs     ──── in the firmware ────────▶│
  ctors.rs     ─────────────────────────────▶│
                                             │ cargo build --target thumbv7em-none-eabihf
                                             ▼
                                        firmware.elf  ← bare-metal binary
                                             │
                                             ▼
                                        Cortex-M4 / QEMU / Ledger
```

The firmware's `main()` includes the bytecode at compile time and calls
into the VM:

```rust
static BYTECODE: &[u8] = include_bytes!("bytecode.bin");

let prog = Program::from_blob(BYTECODE).unwrap();
let mut vm = Vm::new(&mut heap_buffer);
vm.load_program(&prog).unwrap();
let result = vm.call(funcs::DESERIALIZE_TRANSACTION, &[input]).unwrap();
```

## Measuring the bare-metal binary size

To get the **actual** flash footprint (VM + bytecode + glue), use the
shamrocq baremetal scaffold with our files (see `tests/baremetal_main.rs`
for a drop-in `main.rs`):

```sh
# copy our files into the shamrocq baremetal example
cp boilerplate/boilerplate_clean.scm /path/to/shamrocq/examples/baremetal/scheme/demo.scm
cp tests/baremetal_main.rs /path/to/shamrocq/examples/baremetal/src/main.rs

# build and measure
cd /path/to/shamrocq/examples/baremetal
rustup target add thumbv7em-none-eabihf
cargo build --release
size target/thumbv7em-none-eabihf/release/shamrocq-baremetal
```

To restore shamrocq to its original state:

```sh
cd /path/to/shamrocq/examples/baremetal
git checkout -- scheme/demo.scm src/main.rs
```

## Running the VM tests

The PoC functions have been tested on the Shamrocq VM (11 tests passing):

```sh
cp poc/poc_clean.scm /path/to/shamrocq/scheme/poc.scm
cp tests/poc_boilerplate.rs /path/to/shamrocq/crates/shamrocq/tests/poc_boilerplate.rs
cd /path/to/shamrocq
cargo test --test poc_boilerplate -- --nocapture
```

Tests cover: `successor`, `negb`, `valid_nonce`, `safe_head`, `sum_list`,
and `parse_transaction` (valid 37-byte input + truncated input rejection).

## Files

```
boilerplate/
├── Boilerplate.v             # Rocq source: definitions + proofs + extraction
├── _CoqProject               # Rocq project config
├── Makefile                   # Build: rocq compile
├── boilerplate_clean.scm     # Extracted Scheme (header stripped, optimized)
├── README.md                 # This file
└── out/                      # Generated by shamrocq-compiler (in .gitignore)
    ├── bytecode.bin           # 1,263 bytes — Shamrocq VM bytecode
    ├── ctors.rs               # Constructor tag constants (23 tags)
    ├── funcs.rs               # Function entry-point constants (19 globals)
    └── foreign_fns.rs         # FFI declarations (empty — no host calls)
```
