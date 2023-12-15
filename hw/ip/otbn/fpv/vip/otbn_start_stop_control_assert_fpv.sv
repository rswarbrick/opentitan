// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Assertions for otbn_start_stop_control.
// Intended to be used with a formal tool.

`include "prim_assert.sv"

module otbn_start_stop_control_assert_fpv
  import otbn_pkg::*;
  import prim_mubi_pkg::*;
#(
  parameter bit SecMuteUrnd = 1'b0,
  parameter bit SecSkipUrndReseedAtStart = 1'b0
) (
  input logic clk_i,
  input logic rst_ni,
  input logic start_i,
  input mubi4_t escalate_en_i,
  input mubi4_t rma_req_i,
  input mubi4_t rma_ack_o,
  input logic controller_start_o,
  input logic urnd_reseed_req_o,
  input logic urnd_reseed_ack_i,
  input logic urnd_reseed_err_o,
  input logic urnd_advance_o,
  input logic secure_wipe_req_i,
  input logic secure_wipe_ack_o,
  input logic secure_wipe_running_o,
  input logic done_o,
  input logic sec_wipe_wdr_o,
  input logic sec_wipe_wdr_urnd_o,
  input logic sec_wipe_base_o,
  input logic sec_wipe_base_urnd_o,
  input logic[4:0] sec_wipe_addr_o,
  input logic sec_wipe_acc_urnd_o,
  input logic sec_wipe_mod_urnd_o,
  input logic sec_wipe_zero_o,
  input logic ispr_init_o,
  input logic state_reset_o,
  input logic fatal_error_o
);

  ///////////////////////////////
  // Declarations & Parameters //
  ///////////////////////////////

  /////////////////
  // Assumptions //
  /////////////////

  // `ASSUME(MyAssumption_M, ...)

  ////////////////////////
  // Forward Assertions //
  ////////////////////////

  // `ASSERT(MyFwdAssertion_A, ...)

  /////////////////////////
  // Backward Assertions //
  /////////////////////////

  // `ASSERT(MyBkwdAssertion_A, ...)

endmodule : otbn_start_stop_control_assert_fpv
