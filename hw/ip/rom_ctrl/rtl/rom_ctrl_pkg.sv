// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "prim_assert.sv"

package rom_ctrl_pkg;

  typedef struct packed {
    prim_mubi_pkg::mubi4_t done;
    prim_mubi_pkg::mubi4_t good;
  } pwrmgr_data_t;

  parameter pwrmgr_data_t PWRMGR_DATA_DEFAULT = '{
    done: prim_mubi_pkg::MuBi4True,
    good: prim_mubi_pkg::MuBi4True
  };

  typedef struct packed {
    logic [255:0] data;
    logic         valid;
  } keymgr_data_t;

  // Encoding generated using Python 3.12.13 with:
  // $ util/design/sparse-fsm-encode.py --language=sv --seed 2 --distance 3 --states 11 --bits 8
  //
  // Hamming distance histogram:
  //
  //  0: --
  //  1: --
  //  2: --
  //  3: |||||||||||||||| (29.09%)
  //  4: |||||||||||||||||||| (34.55%)
  //  5: ||||||||||| (20.00%)
  //  6: |||||| (10.91%)
  //  7: ||| (5.45%)
  //  8: --
  //
  // Minimum Hamming distance: 3
  // Maximum Hamming distance: 7
  // Minimum Hamming weight: 1
  // Maximum Hamming weight: 6
  //
  // However, we add on an extra 4 bits to hold a mubi4_t that encodes "state == Done". The idea is
  // that we can use them for the rom_select_bus_o signal without needing an intermediate 1-bit
  // signal which would need burying.

  typedef enum logic [11:0] {
    ReadingKAT  = {8'b11011100, prim_mubi_pkg::MuBi4False},
    SendingKAT  = {8'b11110010, prim_mubi_pkg::MuBi4False},
    WaitingKAT  = {8'b00001110, prim_mubi_pkg::MuBi4False},
    CheckingKAT = {8'b00010111, prim_mubi_pkg::MuBi4False},
    ReadingLow  = {8'b00101011, prim_mubi_pkg::MuBi4False},
    ReadingHigh = {8'b11001111, prim_mubi_pkg::MuBi4False},
    RomAhead    = {8'b01000000, prim_mubi_pkg::MuBi4False},
    KmacAhead   = {8'b10011011, prim_mubi_pkg::MuBi4False},
    Checking    = {8'b10000010, prim_mubi_pkg::MuBi4False},
    Done        = {8'b01110001, prim_mubi_pkg::MuBi4True},
    Invalid     = {8'b01101100, prim_mubi_pkg::MuBi4False}
  } fsm_state_e;

  // A selector function with a mubi4 test and two twelve-bit results.
  //
  // This is designed so that a single-bit error in sel will cause a single-bit error in the return
  // value.
  function automatic bit [11:0] mubi4_sel12(bit [3:0] sel, bit [11:0] if_true, bit [11:0] if_false);
    bit [3:0] true_val = prim_mubi_pkg::MuBi4True;
    bit [11:0] ret;
    for (int unsigned i = 0; i < 12; i++) begin
      ret[i] = (sel[i / 4] == true_val[i / 4]) ? if_true[i] : if_false[i];
    end
    return ret;
  endfunction
endpackage
