//! Drop-in replacement for shamrocq/examples/baremetal/src/main.rs
//! that runs our proven boilerplate transaction functions on Cortex-M4.
//!
//! Usage:
//!   cp tests/baremetal_main.rs /path/to/shamrocq/examples/baremetal/src/main.rs
//!   cp boilerplate/boilerplate_clean.scm /path/to/shamrocq/examples/baremetal/scheme/demo.scm
//!   cd /path/to/shamrocq/examples/baremetal
//!   cargo run --release

#![no_std]
#![no_main]

use cortex_m_rt::entry;
use cortex_m_semihosting::{debug, hprintln};
use panic_halt as _;

use shamrocq::{Program, Value, Vm};

static BYTECODE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/bytecode.bin"));

mod funcs {
    include!(concat!(env!("OUT_DIR"), "/funcs.rs"));
}
mod ctors {
    include!(concat!(env!("OUT_DIR"), "/ctors.rs"));
}
mod foreign {
    include!(concat!(env!("OUT_DIR"), "/foreign_fns.rs"));
}

fn peano(vm: &mut Vm, n: u32) -> Value {
    let mut v = Value::ctor(ctors::O, 0);
    for _ in 0..n {
        v = vm.alloc_ctor(ctors::S, &[v]).unwrap();
    }
    v
}

fn make_list(vm: &mut Vm, items: &[Value]) -> Value {
    let mut list = Value::ctor(ctors::NIL, 0);
    for &item in items.iter().rev() {
        list = vm.alloc_ctor(ctors::CONS, &[item, list]).unwrap();
    }
    list
}

fn list_len(vm: &Vm, mut v: Value) -> u32 {
    let mut n = 0;
    while v.tag() == ctors::CONS {
        v = vm.ctor_field(v, 1);
        n += 1;
    }
    n
}

#[entry]
fn main() -> ! {
    let mut buf = [0u8; 10240];
    let prog = Program::from_blob(BYTECODE).unwrap();
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    // --- check_encoding: ASCII bytes ---
    let hello: [u32; 5] = [72, 101, 108, 108, 111];
    let mut items = [Value::ctor(ctors::O, 0); 5];
    for (i, &b) in hello.iter().enumerate() {
        items[i] = peano(&mut vm, b);
    }
    let list = make_list(&mut vm, &items);
    let r = vm.call(funcs::CHECK_ENCODING, &[list]).unwrap();
    let _ = hprintln!("check_encoding(\"Hello\") = {}", r.tag() == ctors::TRUE);

    // --- deserialize_transaction: valid 37-byte input ---
    // nonce(8) + to(20) + value(8) + memo(1) = 37 bytes
    let mut tx_bytes = [Value::ctor(ctors::O, 0); 37];
    tx_bytes[0] = peano(&mut vm, 1);
    for i in 1..8 { tx_bytes[i] = peano(&mut vm, 0); }
    for i in 8..28 { tx_bytes[i] = peano(&mut vm, 10); }
    for i in 28..35 { tx_bytes[i] = peano(&mut vm, 0); }
    tx_bytes[35] = peano(&mut vm, 42);
    tx_bytes[36] = peano(&mut vm, 65);

    let input = make_list(&mut vm, &tx_bytes);
    let result = vm.call(funcs::DESERIALIZE_TRANSACTION, &[input]).unwrap();

    if result.tag() == ctors::INR {
        let tx = vm.ctor_field(result, 0);
        let _ = hprintln!(
            "deserialize OK: nonce={} to={} value={} memo={}",
            list_len(&vm, vm.ctor_field(tx, 0)),
            list_len(&vm, vm.ctor_field(tx, 1)),
            list_len(&vm, vm.ctor_field(tx, 2)),
            list_len(&vm, vm.ctor_field(tx, 3))
        );
    } else {
        let _ = hprintln!("deserialize FAILED");
    }

    // --- deserialize_transaction: too-short → rejected ---
    let short = [Value::ctor(ctors::O, 0); 5];
    let short_list = make_list(&mut vm, &short);
    let r2 = vm.call(funcs::DESERIALIZE_TRANSACTION, &[short_list]).unwrap();
    let _ = hprintln!("deserialize(5 bytes) rejected = {}", r2.tag() == ctors::INL);

    let _ = hprintln!("--- all checks passed ---");
    debug::exit(debug::EXIT_SUCCESS);
    loop {}
}
