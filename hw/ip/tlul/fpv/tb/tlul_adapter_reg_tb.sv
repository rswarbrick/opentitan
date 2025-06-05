// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Testbench module for tlul_adapter_reg (for a formal tool)

module tlul_adapter_reg_tb
  import tlul_pkg::*;
  import prim_mubi_pkg::mubi4_t;
#(
  parameter  bit CmdIntgCheck      = 0,  // 1: Enable command integrity check
  parameter  bit EnableRspIntgGen  = 0,  // 1: Generate response integrity
  parameter  bit EnableDataIntgGen = 0,  // 1: Generate response data integrity
  parameter  int RegAw             = 8,  // Width of register address
  parameter  int RegDw             = 32, // Shall be matched with TL_DW
  parameter  int AccessLatency     = 0,  // 0: same cycle, 1: next cycle
  localparam int RegBw             = RegDw/8
) (
  input logic              clk_i,
  input logic              rst_ni,
  input  tl_h2d_t          tl_i,
  output tl_d2h_t          tl_o,
  input  mubi4_t           en_ifetch_i,
  output logic             intg_error_o,
  output logic             re_o,
  output logic             we_o,
  output logic [RegAw-1:0] addr_o,
  output logic [RegDw-1:0] wdata_o,
  output logic [RegBw-1:0] be_o,
  input logic              busy_i,
  input logic  [RegDw-1:0] rdata_i,
  input logic              error_i
);

  tlul_adapter_reg #(
    .CmdIntgCheck(CmdIntgCheck),
    .EnableRspIntgGen(EnableRspIntgGen),
    .EnableDataIntgGen(EnableDataIntgGen),
    .RegAw(RegAw),
    .RegDw(RegDw),
    .AccessLatency(AccessLatency)
  ) dut (.*);

  // Add properties that assume tl_i is being driven in a valid way by the outside world and assert
  // that the tl_o signal we produce behaves correctly.
  tlul_assert #(.EndpointType("Device")) i_tlul_assert(.clk_i, .rst_ni, .h2d (tl_i), .d2h (tl_o));

  // Assertions about the exact dut behaviour.
  tlul_adapter_reg_assert_fpv #(
    .CmdIntgCheck(CmdIntgCheck),
    .EnableRspIntgGen(EnableRspIntgGen),
    .EnableDataIntgGen(EnableDataIntgGen),
    .RegAw(RegAw),
    .RegDw(RegDw),
    .AccessLatency(AccessLatency)
  ) i_assert_fpv (.clk_i, .rst_ni);

endmodule
