// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Testbench module for otbn_start_stop_control.
// Intended to be used with a formal tool.

module otbn_start_stop_control_tb
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
  output mubi4_t rma_ack_o,
  output logic controller_start_o,
  output logic urnd_reseed_req_o,
  input logic urnd_reseed_ack_i,
  output logic urnd_reseed_err_o,
  output logic urnd_advance_o,
  input logic secure_wipe_req_i,
  output logic secure_wipe_ack_o,
  output logic secure_wipe_running_o,
  output logic done_o,
  output logic sec_wipe_wdr_o,
  output logic sec_wipe_wdr_urnd_o,
  output logic sec_wipe_base_o,
  output logic sec_wipe_base_urnd_o,
  output logic[4:0] sec_wipe_addr_o,
  output logic sec_wipe_acc_urnd_o,
  output logic sec_wipe_mod_urnd_o,
  output logic sec_wipe_zero_o,
  output logic ispr_init_o,
  output logic state_reset_o,
  output logic fatal_error_o
);


  otbn_start_stop_control #(
    .SecMuteUrnd(SecMuteUrnd),
    .SecSkipUrndReseedAtStart(SecSkipUrndReseedAtStart)
  ) dut (
    .clk_i,
    .rst_ni,
    .start_i,
    .escalate_en_i,
    .rma_req_i,
    .rma_ack_o,
    .controller_start_o,
    .urnd_reseed_req_o,
    .urnd_reseed_ack_i,
    .urnd_reseed_err_o,
    .urnd_advance_o,
    .secure_wipe_req_i,
    .secure_wipe_ack_o,
    .secure_wipe_running_o,
    .done_o,
    .sec_wipe_wdr_o,
    .sec_wipe_wdr_urnd_o,
    .sec_wipe_base_o,
    .sec_wipe_base_urnd_o,
    .sec_wipe_addr_o,
    .sec_wipe_acc_urnd_o,
    .sec_wipe_mod_urnd_o,
    .sec_wipe_zero_o,
    .ispr_init_o,
    .state_reset_o,
    .fatal_error_o
  );


endmodule : otbn_start_stop_control_tb
