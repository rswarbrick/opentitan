// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Testbench module for tlul_adapter_reg (for a formal tool)

module tlul_adapter_reg_tb
  import tlul_pkg::*;
  import prim_mubi_pkg::mubi4_t;
#(
  parameter  bit CmdIntgCheck      = 1,  // 1: Enable command integrity check
  parameter  int RegAw             = 8,  // Width of register address
  parameter  int RegDw             = 32, // Shall be matched with TL_DW
  localparam int RegBw             = RegDw/8
) (
  input logic              clk_i,
  input logic              rst_ni,
  input  tl_h2d_t          tl_i,
  input  mubi4_t           en_ifetch_i,
  input logic              busy_i,
  input logic  [RegDw-1:0] rdata_i,
  input logic              error_i
);

  for (genvar latency = 0; latency < 2; latency++) begin : gen_latency
    for (genvar intg_gen = 0; intg_gen < 4; intg_gen++) begin : gen_intg_gen
      tl_d2h_t          tl_out;
      logic             intg_error_out;
      logic             re_out;
      logic             we_out;
      logic [RegAw-1:0] addr_out;
      logic [RegDw-1:0] wdata_out;
      logic [RegBw-1:0] be_out;

      tlul_adapter_reg #(
        .CmdIntgCheck(CmdIntgCheck),
        .EnableRspIntgGen(intg_gen[0]),
        .EnableDataIntgGen(intg_gen[1]),
        .RegAw(RegAw),
        .RegDw(RegDw),
        .AccessLatency(latency)
      ) dut (
        .clk_i,
        .rst_ni,
        .tl_i,
        .tl_o         (tl_out),
        .en_ifetch_i,
        .intg_error_o (intg_error_out),
        .re_o         (re_out),
        .we_o         (we_out),
        .addr_o       (addr_out),
        .wdata_o      (wdata_out),
        .be_o         (be_out),
        .busy_i,
        .rdata_i,
        .error_i
      );

      // Add properties that assume tl_i is being driven in a valid way by the outside world and assert
      // that the tl_o signal we produce behaves correctly.
      tlul_assert #(.EndpointType("Device")) i_tlul_assert(.clk_i, .rst_ni,
                                                           .h2d (tl_i), .d2h (tl_out));

      // Assertions about the exact dut behaviour.
      tlul_adapter_reg_assert_fpv #(
        .CmdIntgCheck(1),
        .EnableRspIntgGen(intg_gen[0]),
        .EnableDataIntgGen(intg_gen[1]),
        .RegAw(RegAw),
        .RegDw(RegDw),
        .AccessLatency(latency)
      ) i_assert_fpv (.clk_i, .rst_ni);
    end
  end

endmodule
