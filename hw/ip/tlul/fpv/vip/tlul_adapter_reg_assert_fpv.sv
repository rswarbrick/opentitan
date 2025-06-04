// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Assertions for tlul_lc_gate.
// Intended to be used with a formal tool.

`include "prim_assert.sv"

module tlul_adapter_reg_assert_fpv #(
  parameter  bit CmdIntgCheck      = 0,  // 1: Enable command integrity check
  parameter  bit EnableRspIntgGen  = 0,  // 1: Generate response integrity
  parameter  bit EnableDataIntgGen = 0,  // 1: Generate response data integrity
  parameter  int RegAw             = 8,  // Width of register address
  parameter  int RegDw             = 32, // Shall be matched with TL_DW
  parameter  int AccessLatency     = 0,  // 0: same cycle, 1: next cycle
  localparam int RegBw             = RegDw/8
) (
  input logic              clk_i,
  input logic              rst_ni
);

  default clocking @(posedge clk_i); endclocking
  default disable iff !rst_ni;

  // This sequence sees the re_o signal high (which means that we've just decoded a read request on
  // the TL A channel). It then waits AccessLatency cycles for the response to come back, and a
  // cycle for it to be registered (in rdata_q).
  //
  // Then we wait an arbitrary number of cycles where the TL D channel is not ready until we finally
  // see the data being accepted.
  sequence read_txn_S;
    dut.re_o                  ##(AccessLatency + 1)
    (!dut.tl_i.d_ready)[*0:$] ##1
    dut.tl_i.d_ready;
  endsequence

  // This sequence sees the we_o signal high (which means that we've just decoded a write request on
  // the TL A channel) and there is the write mask and data on be_o and wdata_o.
  sequence write_txn_S;
    dut.we_o;
  endsequence

  // Initial cover properties    ///////////////////////////////////////////////////////////////////

  // We want to see register read and write requests (which will come about from a TLUL A-channel
  // message)
  ReadReq_C:  cover property (dut.re_o);
  WriteReq_C: cover property (dut.we_o);

  // We want to see a register read request on the TL A channel arrive and for the rdata response to
  // be sent back on the TL D channel.
  ReadTxn_C: cover property (read_txn_S);

  // We want to see a register write request pass wdata from the TL A channel to wmask_o / wdata_o
  WriteTxn_C: cover property (write_txn_S);

  // Assuming that RegAw is large enough to have more than one register, we want to see a request
  // with a nonzero address.
  if (RegAw > 2) begin : gen_multiple_regs
    NonzeroAddr_C: cover property ((dut.re_o | dut.we_o) && |dut.addr_o);
  end

  // If integrity checking is enabled (with CmdIntgCheck), we want to see an integrity error being
  // reported.
  if (CmdIntgCheck) begin : gen_intg_check
    IntgError_C: cover property (dut.intg_error_o);
  end

endmodule
