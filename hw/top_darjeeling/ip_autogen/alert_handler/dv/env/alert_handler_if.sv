// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Interface for crashdump output.
interface alert_handler_if(input clk, input rst_n);
  import uvm_pkg::*;
  import alert_handler_pkg::*;
  import prim_mubi_pkg::*;
  import cip_base_pkg::*;
  import alert_handler_env_pkg::*;

  logic [NUM_ALERTS-1:0] alert_ping_reqs;
  logic [NUM_ESCS-1:0]   esc_ping_reqs;

  string msg_id = "alert_handler_if";

  task automatic set_wait_cyc_mask(logic [PING_CNT_DW-1:0] val);
    static logic [PING_CNT_DW-1:0] val_static;
    begin
      val_static = val;
      force tb.dut.u_ping_timer.wait_cyc_mask_i = val_static;
    end
  endtask

  task automatic release_wait_cyc_mask();
    release tb.dut.u_ping_timer.wait_cyc_mask_i;
  endtask
endinterface
