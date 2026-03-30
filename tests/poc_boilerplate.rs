mod common;

use common::{compile_scheme, make_list, peano, unpeano, print_stats, Compiled};
use shamrocq::{Program, Value, Vm};

fn setup() -> Compiled {
    compile_scheme(&["poc.scm"])
}

// ---- 1. successor: nat -> nat ----

#[test]
fn successor_of_5_is_6() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let n5 = peano(&mut vm, c.tag("O"), c.tag("S"), 5);
    let result = vm.call(c.func("successor"), &[n5]).unwrap();
    assert_eq!(unpeano(&vm, c.tag("S"), result), 6);
    print_stats("successor(5)", &vm);
}

#[test]
fn successor_of_0_is_1() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let n0 = Value::ctor(c.tag("O"), 0);
    let result = vm.call(c.func("successor"), &[n0]).unwrap();
    assert_eq!(unpeano(&vm, c.tag("S"), result), 1);
    print_stats("successor(0)", &vm);
}

// ---- 2. negb: bool -> bool ----

#[test]
fn negb_true_is_false() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let result = vm.call(c.func("negb"), &[Value::ctor(c.tag("True"), 0)]).unwrap();
    assert_eq!(result.tag(), c.tag("False"));
    print_stats("negb(True)", &vm);
}

#[test]
fn negb_false_is_true() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let result = vm.call(c.func("negb"), &[Value::ctor(c.tag("False"), 0)]).unwrap();
    assert_eq!(result.tag(), c.tag("True"));
    print_stats("negb(False)", &vm);
}

// ---- 3. valid_nonce: nat -> bool ----

#[test]
fn valid_nonce_nonzero() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let n3 = peano(&mut vm, c.tag("O"), c.tag("S"), 3);
    let result = vm.call(c.func("valid_nonce"), &[n3]).unwrap();
    assert_eq!(result.tag(), c.tag("True"));
    print_stats("valid_nonce(3)", &vm);
}

#[test]
fn valid_nonce_zero() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let n0 = Value::ctor(c.tag("O"), 0);
    let result = vm.call(c.func("valid_nonce"), &[n0]).unwrap();
    assert_eq!(result.tag(), c.tag("False"));
    print_stats("valid_nonce(0)", &vm);
}

// ---- 4. safe_head: list nat -> option nat ----

#[test]
fn safe_head_nonempty() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let n7 = peano(&mut vm, c.tag("O"), c.tag("S"), 7);
    let n3 = peano(&mut vm, c.tag("O"), c.tag("S"), 3);
    let list = make_list(&mut vm, c.tag("Nil"), c.tag("Cons"), &[n7, n3]);
    let result = vm.call(c.func("safe_head"), &[list]).unwrap();
    assert_eq!(result.tag(), c.tag("Some"));
    let head = vm.ctor_field(result, 0);
    assert_eq!(unpeano(&vm, c.tag("S"), head), 7);
    print_stats("safe_head([7,3])", &vm);
}

#[test]
fn safe_head_empty() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let empty = Value::ctor(c.tag("Nil"), 0);
    let result = vm.call(c.func("safe_head"), &[empty]).unwrap();
    assert_eq!(result.tag(), c.tag("None"));
    print_stats("safe_head([])", &vm);
}

// ---- 5. sum_list: list nat -> nat ----

#[test]
fn sum_list_example() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    let n1 = peano(&mut vm, c.tag("O"), c.tag("S"), 1);
    let n2 = peano(&mut vm, c.tag("O"), c.tag("S"), 2);
    let n3 = peano(&mut vm, c.tag("O"), c.tag("S"), 3);
    let list = make_list(&mut vm, c.tag("Nil"), c.tag("Cons"), &[n1, n2, n3]);
    let result = vm.call(c.func("sum_list"), &[list]).unwrap();
    assert_eq!(unpeano(&vm, c.tag("S"), result), 6);
    print_stats("sum_list([1,2,3])", &vm);
}

// ---- 6. parse_transaction: list nat -> option transaction ----

#[test]
fn parse_transaction_valid() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 131072];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    // nonce: 4 bytes [1,2,3,4]
    // to:   20 bytes [10; 20]
    // value: 8 bytes [0,0,0,0,0,0,0,42]
    // memo:  5 bytes [72,101,108,108,111] = "Hello"
    let mut bytes: Vec<Value> = Vec::new();

    for &b in &[1u32, 2, 3, 4] {
        bytes.push(peano(&mut vm, c.tag("O"), c.tag("S"), b));
    }
    for _ in 0..20 {
        bytes.push(peano(&mut vm, c.tag("O"), c.tag("S"), 10));
    }
    for &b in &[0u32, 0, 0, 0, 0, 0, 0, 42] {
        bytes.push(peano(&mut vm, c.tag("O"), c.tag("S"), b));
    }
    for &b in &[72u32, 101, 108, 108, 111] {
        bytes.push(peano(&mut vm, c.tag("O"), c.tag("S"), b));
    }

    let input = make_list(&mut vm, c.tag("Nil"), c.tag("Cons"), &bytes);
    let result = vm.call(c.func("parse_transaction"), &[input]).unwrap();

    assert_eq!(result.tag(), c.tag("Some"), "expected Some(tx), got None");
    let tx = vm.ctor_field(result, 0);
    assert_eq!(tx.tag(), c.tag("MkTransaction"));

    // Verify nonce length = 4
    let nonce = vm.ctor_field(tx, 0);
    let nonce_items = common::list_to_vec(&vm, c.tag("Cons"), nonce);
    assert_eq!(nonce_items.len(), 4);

    // Verify to length = 20
    let to = vm.ctor_field(tx, 1);
    let to_items = common::list_to_vec(&vm, c.tag("Cons"), to);
    assert_eq!(to_items.len(), 20);

    // Verify value length = 8
    let value = vm.ctor_field(tx, 2);
    let value_items = common::list_to_vec(&vm, c.tag("Cons"), value);
    assert_eq!(value_items.len(), 8);

    // Verify memo length = 5
    let memo = vm.ctor_field(tx, 3);
    let memo_items = common::list_to_vec(&vm, c.tag("Cons"), memo);
    assert_eq!(memo_items.len(), 5);

    // Verify first byte of nonce is 1
    assert_eq!(unpeano(&vm, c.tag("S"), nonce_items[0]), 1);

    // Verify last byte of value is 42
    assert_eq!(unpeano(&vm, c.tag("S"), value_items[7]), 42);

    print_stats("parse_transaction(37 bytes valid)", &vm);
}

#[test]
fn parse_transaction_too_short() {
    let c = setup();
    let prog = Program::from_blob(&c.blob).unwrap();
    let mut buf = vec![0u8; 65536];
    let mut vm = Vm::new(&mut buf);
    vm.load_program(&prog).unwrap();

    // Only 10 bytes — not enough for nonce(4) + to(20) + value(8)
    let mut bytes: Vec<Value> = Vec::new();
    for _ in 0..10 {
        bytes.push(Value::ctor(c.tag("O"), 0));
    }

    let input = make_list(&mut vm, c.tag("Nil"), c.tag("Cons"), &bytes);
    let result = vm.call(c.func("parse_transaction"), &[input]).unwrap();

    assert_eq!(result.tag(), c.tag("None"));
    print_stats("parse_transaction(10 bytes too short)", &vm);
}
