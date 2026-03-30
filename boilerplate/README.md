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
| Source lines (logic only) | ~130 lines across 4 files | 155 lines in `Boilerplate.v` |
| Source lines (total) | ~250 lines (incl. headers, includes) | 344 lines (incl. 190 lines of proofs) |
| Extracted Scheme | — | 183 lines (`boilerplate_clean.scm`) |
| Bytecode only | — | 9,171 bytes (`bytecode.bin`) |
| VM runtime (baseline) | — | 11,872 bytes `.text` (no app bytecode) |
| **Total bare-metal `.text`** | **~1–2 KB** (estimated) | **22,012 bytes** (measured) |
| **Fits in 16 KB FLASH?** | Yes | **No** (overflows by 5,628 bytes) |

> **Measured on:** `thumbv7em-none-eabihf`, release mode, `opt-level = "s"`,
> LTO enabled, using `shamrocq/examples/baremetal/` scaffold.
> VM baseline (11,872 B) was measured with the original demo Scheme program.

The bytecode is ~10 KB, and the VM runtime adds ~12 KB, for a total of
**~22 KB** — exceeding the 16 KB FLASH budget by ~6 KB.

Most of the bytecode bloat comes from **Peano-encoded constants** —
`MAX_TX_LEN` (510), `MAX_MEMO_LEN` (465), and `127` each expand into
hundreds of nested `S(S(S(...O...)))` constructor chains in the Scheme
output (see lines 49–121 of `boilerplate_clean.scm`). This is a known
limitation of Rocq's default `nat` extraction.

### How to reduce bytecode size

- **`Extract Inductive nat`** — tell Rocq to map `nat` to Scheme integers
  instead of Peano constructors. Removes ~7 KB of constant encoding.
- **Shamrocq FFI for integer constants** — use `foreign_fn` to provide
  `MAX_TX_LEN` etc. as native 32-bit words from the host.
- Both approaches are straightforward; the current PoC intentionally uses
  unoptimized extraction to show the baseline.

## Functionality comparison

| Feature | C | Rocq/Shamrocq |
|---|---|---|
| Parse nonce (8 bytes) | pointer arithmetic | `parse_field 8 data` |
| Parse to address (20 bytes) | pointer arithmetic | `parse_field ADDRESS_LEN rest` |
| Parse value (8 bytes) | pointer arithmetic | `parse_field 8 rest` |
| Memo length check (≤ 465) | `if (offset + memo_len > buf_len)` | `leb (length memo) MAX_MEMO_LEN` |
| Memo ASCII check (≤ 0x7F) | `for` loop | `check_encoding` (recursive) |
| Error codes | `return NONCE_PARSING_ERROR` etc. | `inl NONCE_PARSING_ERROR` etc. |
| Return parsed struct | fill `transaction_t` by pointer | `inr (MkTransaction ...)` |

**Identical behavior.** Both reject inputs that are too long, too short for
any field, or contain non-ASCII memo bytes, and return the same error codes.

## What the proofs guarantee (that C cannot)

The Rocq version includes 6 machine-checked theorems that hold for any
successful parse:

| Theorem | Statement |
|---|---|
| `deserialize_nonce_len` | `length (tx_nonce tx) = 8` |
| `deserialize_to_len` | `length (tx_to tx) = ADDRESS_LEN` |
| `deserialize_value_len` | `length (tx_value tx) = 8` |
| `deserialize_memo_bounded` | `length (tx_memo tx) ≤ MAX_MEMO_LEN` |
| `deserialize_encoding_valid` | every byte in `tx_memo tx` is ≤ 127 |
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

To get the **actual** flash footprint (VM + bytecode + glue), build the
shamrocq baremetal example with our bytecode:

```sh
# 1. Install the bare-metal Rust target
rustup target add thumbv7em-none-eabihf

# 2. Go to the shamrocq baremetal example
cd /path/to/shamrocq/examples/baremetal

# 3. Replace the demo scheme file with our boilerplate code
cp /path/to/poc-shamrocq/boilerplate/boilerplate_clean.scm scheme/demo.scm

# 4. Build in release mode (opt-level "s", LTO enabled)
cargo build --release

# 5. Measure the binary size
arm-none-eabi-size target/thumbv7em-none-eabihf/release/shamrocq-baremetal
```

The `text` column in the output is the total flash footprint. Compare
with the C boilerplate compiled for the same target to get an accurate
side-by-side comparison.

To run on QEMU (requires `qemu-system-arm`):

```sh
cargo run --release
```

## Running the VM tests

The PoC functions have been tested on the Shamrocq VM (11 tests passing):

```sh
cd /path/to/shamrocq
cp /path/to/poc-shamrocq/scheme/poc.scm scheme/poc.scm
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
├── boilerplate_clean.scm     # Extracted Scheme (header stripped)
├── README.md                 # This file
└── out/                      # Generated by shamrocq-compiler (in .gitignore)
    ├── bytecode.bin           # 9,171 bytes — Shamrocq VM bytecode
    ├── ctors.rs               # Constructor tag constants (23 tags)
    ├── funcs.rs               # Function entry-point constants (16 globals)
    └── foreign_fns.rs         # FFI declarations (empty — no host calls)
```
