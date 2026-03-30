(** * Shamrocq PoC — Proven-correct functions for embedded execution

    This file defines pure functions in Gallina, proves correctness
    properties, and extracts them to Scheme for compilation with
    shamrocq-compiler.

    Pipeline:
      Rocq (this file) → Scheme (poc.scm) → shamrocq-compiler → bytecode → Shamrocq VM

    Functions are graduated in complexity:
      1. successor      — nat → nat          (simplest roundtrip)
      2. negb           — bool → bool        (constructor dispatch)
      3. valid_nonce     — nat → bool         (single match)
      4. in_range        — nat³ → bool        (composed conditions)
      5. sum_list        — list nat → nat     (recursive fold)
      6. safe_head       — list nat → option  (option return type)
      7. take/drop       — byte buffer slicing
      8. parse_field     — option (list × list) return
      9. parse_transaction — full transaction parser
*)

From Stdlib Require Import Bool List Lia.
Import ListNotations.

(* ================================================================== *)
(** * Helpers                                                          *)
(* ================================================================== *)

Fixpoint leb (n m : nat) : bool :=
  match n with
  | 0 => true
  | S n' => match m with
            | 0 => false
            | S m' => leb n' m'
            end
  end.

Lemma leb_iff : forall n m, leb n m = true <-> n <= m.
Proof.
  induction n as [|n' IH]; destruct m as [|m']; simpl;
    split; intro H; try discriminate; try reflexivity; try lia.
  - apply IH in H. lia.
  - apply IH. lia.
Qed.

(* ================================================================== *)
(** * 1. Successor — simplest possible nat → nat roundtrip            *)
(* ================================================================== *)

Definition successor (n : nat) : nat := S n.

(* ================================================================== *)
(** * 2. Boolean negation                                              *)
(* ================================================================== *)

(** We use the standard library [negb] (from Init.Datatypes).
    Re-proving involutivity here as a sanity check. *)

Theorem negb_involutive : forall b : bool, negb (negb b) = b.
Proof. destruct b; reflexivity. Qed.

(* ================================================================== *)
(** * 3. Nonce validation — nonzero check                              *)
(* ================================================================== *)

Definition valid_nonce (n : nat) : bool :=
  match n with
  | O => false
  | S _ => true
  end.

Theorem valid_nonce_spec : forall n : nat,
  valid_nonce n = true <-> n <> 0.
Proof.
  destruct n; simpl; split; intro H.
  - discriminate.
  - exfalso. apply H. reflexivity.
  - intro Hc. discriminate.
  - reflexivity.
Qed.

(* ================================================================== *)
(** * 4. Range check — is n in [lo, hi]?                               *)
(* ================================================================== *)

Definition in_range (lo hi n : nat) : bool :=
  andb (leb lo n) (leb n hi).

Theorem in_range_spec : forall lo hi n : nat,
  in_range lo hi n = true <-> lo <= n /\ n <= hi.
Proof.
  unfold in_range. intros lo hi n. split; intro H.
  - apply andb_true_iff in H. destruct H as [H1 H2].
    split; [exact (proj1 (leb_iff _ _) H1) | exact (proj1 (leb_iff _ _) H2)].
  - destruct H as [H1 H2].
    apply andb_true_iff. split;
    [exact (proj2 (leb_iff _ _) H1) | exact (proj2 (leb_iff _ _) H2)].
Qed.

(* ================================================================== *)
(** * 5. List sum                                                      *)
(* ================================================================== *)

Fixpoint sum_list (l : list nat) : nat :=
  match l with
  | nil => 0
  | x :: rest => x + sum_list rest
  end.

Theorem sum_list_app : forall l1 l2 : list nat,
  sum_list (l1 ++ l2) = sum_list l1 + sum_list l2.
Proof.
  induction l1 as [|a l1' IH]; simpl; intros l2.
  - reflexivity.
  - rewrite IH. lia.
Qed.

(* ================================================================== *)
(** * 6. Safe head — option-returning function                         *)
(* ================================================================== *)

Definition safe_head (l : list nat) : option nat :=
  match l with
  | nil => None
  | x :: _ => Some x
  end.

Theorem safe_head_cons : forall x l,
  safe_head (x :: l) = Some x.
Proof. reflexivity. Qed.

(* ================================================================== *)
(** * 7. Byte buffer slicing                                           *)
(* ================================================================== *)

Fixpoint take (n : nat) (l : list nat) : list nat :=
  match n with
  | 0 => nil
  | S n' => match l with
            | nil => nil
            | x :: rest => x :: take n' rest
            end
  end.

Fixpoint drop (n : nat) (l : list nat) : list nat :=
  match n with
  | 0 => l
  | S n' => match l with
            | nil => nil
            | _ :: rest => drop n' rest
            end
  end.

Theorem take_drop : forall n l,
  take n l ++ drop n l = l.
Proof.
  induction n as [|n' IH]; simpl; intros [|x rest];
    try reflexivity.
  simpl. f_equal. apply IH.
Qed.

Theorem take_length : forall n l,
  n <= length l -> length (take n l) = n.
Proof.
  induction n as [|n' IH]; simpl; intros [|x rest] Hlen;
    try reflexivity; simpl in Hlen; try lia.
  simpl. f_equal. apply IH. lia.
Qed.

(* ================================================================== *)
(** * 8. Field parser                                                  *)
(* ================================================================== *)

Definition validate_memo_length (max_len : nat) (memo : list nat) : bool :=
  leb (length memo) max_len.

Theorem validate_memo_length_spec : forall max_len memo,
  validate_memo_length max_len memo = true <-> length memo <= max_len.
Proof.
  intros. unfold validate_memo_length. apply leb_iff.
Qed.

Definition parse_field (size : nat) (data : list nat)
  : option (list nat * list nat) :=
  if leb size (length data) then
    Some (take size data, drop size data)
  else
    None.

Theorem parse_field_sound : forall size data field rest,
  parse_field size data = Some (field, rest) ->
  field ++ rest = data /\ length field = size.
Proof.
  intros size data field rest H.
  unfold parse_field in H.
  destruct (leb size (length data)) eqn:E; [|discriminate].
  inversion H; subst; clear H.
  apply leb_iff in E. split.
  - apply take_drop.
  - apply take_length. exact E.
Qed.

(* ================================================================== *)
(** * 9. Transaction parser                                            *)
(* ================================================================== *)

Inductive transaction : Type :=
  | MkTransaction (nonce : list nat)
                   (to_addr : list nat)
                   (value : list nat)
                   (memo : list nat).

Definition tx_nonce (tx : transaction) : list nat :=
  match tx with MkTransaction n _ _ _ => n end.

Definition tx_to (tx : transaction) : list nat :=
  match tx with MkTransaction _ t _ _ => t end.

Definition tx_value (tx : transaction) : list nat :=
  match tx with MkTransaction _ _ v _ => v end.

Definition tx_memo (tx : transaction) : list nat :=
  match tx with MkTransaction _ _ _ m => m end.

Definition max_memo_len : nat := 50.

Definition parse_transaction (data : list nat) : option transaction :=
  match parse_field 4 data with
  | None => None
  | Some (nonce, rest1) =>
    match parse_field 20 rest1 with
    | None => None
    | Some (to_addr, rest2) =>
      match parse_field 8 rest2 with
      | None => None
      | Some (value, memo) =>
        if validate_memo_length max_memo_len memo then
          Some (MkTransaction nonce to_addr value memo)
        else
          None
      end
    end
  end.

(** Parsed nonce is always exactly 4 bytes. *)
Theorem parse_transaction_nonce_len : forall data tx,
  parse_transaction data = Some tx ->
  length (tx_nonce tx) = 4.
Proof.
  unfold parse_transaction; intros data tx H.
  destruct (parse_field 4 data) as [[nonce rest1]|] eqn:E1; [|discriminate].
  destruct (parse_field 20 rest1) as [[to_addr rest2]|] eqn:E2; [|discriminate].
  destruct (parse_field 8 rest2) as [[value memo]|] eqn:E3; [|discriminate].
  destruct (validate_memo_length max_memo_len memo) eqn:E4; [|discriminate].
  inversion H; subst; clear H. simpl.
  exact (proj2 (parse_field_sound _ _ _ _ E1)).
Qed.

(** Parsed destination address is always exactly 20 bytes. *)
Theorem parse_transaction_to_len : forall data tx,
  parse_transaction data = Some tx ->
  length (tx_to tx) = 20.
Proof.
  unfold parse_transaction; intros data tx H.
  destruct (parse_field 4 data) as [[nonce rest1]|] eqn:E1; [|discriminate].
  destruct (parse_field 20 rest1) as [[to_addr rest2]|] eqn:E2; [|discriminate].
  destruct (parse_field 8 rest2) as [[value memo]|] eqn:E3; [|discriminate].
  destruct (validate_memo_length max_memo_len memo) eqn:E4; [|discriminate].
  inversion H; subst; clear H. simpl.
  exact (proj2 (parse_field_sound _ _ _ _ E2)).
Qed.

(** Parsed value is always exactly 8 bytes. *)
Theorem parse_transaction_value_len : forall data tx,
  parse_transaction data = Some tx ->
  length (tx_value tx) = 8.
Proof.
  unfold parse_transaction; intros data tx H.
  destruct (parse_field 4 data) as [[nonce rest1]|] eqn:E1; [|discriminate].
  destruct (parse_field 20 rest1) as [[to_addr rest2]|] eqn:E2; [|discriminate].
  destruct (parse_field 8 rest2) as [[value memo]|] eqn:E3; [|discriminate].
  destruct (validate_memo_length max_memo_len memo) eqn:E4; [|discriminate].
  inversion H; subst; clear H. simpl.
  exact (proj2 (parse_field_sound _ _ _ _ E3)).
Qed.

(** Parsed memo length is bounded by [max_memo_len]. *)
Theorem parse_transaction_memo_bounded : forall data tx,
  parse_transaction data = Some tx ->
  length (tx_memo tx) <= max_memo_len.
Proof.
  unfold parse_transaction; intros data tx H.
  destruct (parse_field 4 data) as [[nonce rest1]|] eqn:E1; [|discriminate].
  destruct (parse_field 20 rest1) as [[to_addr rest2]|] eqn:E2; [|discriminate].
  destruct (parse_field 8 rest2) as [[value memo]|] eqn:E3; [|discriminate].
  destruct (validate_memo_length max_memo_len memo) eqn:E4; [|discriminate].
  inversion H; subst; clear H. simpl.
  apply validate_memo_length_spec. exact E4.
Qed.

(** Data is fully consumed: nonce ++ to ++ value ++ memo = original data. *)
Theorem parse_transaction_preserves : forall data tx,
  parse_transaction data = Some tx ->
  tx_nonce tx ++ tx_to tx ++ tx_value tx ++ tx_memo tx = data.
Proof.
  unfold parse_transaction; intros data tx H.
  destruct (parse_field 4 data) as [[nonce rest1]|] eqn:E1; [|discriminate].
  destruct (parse_field 20 rest1) as [[to_addr rest2]|] eqn:E2; [|discriminate].
  destruct (parse_field 8 rest2) as [[value memo]|] eqn:E3; [|discriminate].
  destruct (validate_memo_length max_memo_len memo) eqn:E4; [|discriminate].
  inversion H; subst; clear H. simpl.
  apply parse_field_sound in E1 as [E1a _].
  apply parse_field_sound in E2 as [E2a _].
  apply parse_field_sound in E3 as [E3a _].
  rewrite E3a, E2a, E1a. reflexivity.
Qed.

(* ================================================================== *)
(** * Extraction to Scheme                                             *)
(* ================================================================== *)

From Stdlib Require Extraction.
Extraction Language Scheme.

Definition poc_exports :=
  (negb, successor, valid_nonce, in_range, sum_list,
   safe_head, take, drop, validate_memo_length, parse_field,
   parse_transaction, tx_nonce, tx_to, tx_value, tx_memo).

Extraction "poc" poc_exports.
