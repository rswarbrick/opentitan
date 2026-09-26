// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Interface for that allows a ping_timer_force_agent to interact with the ports of an
// alert_handler_ping_timer in the design.

interface ping_timer_force_if (
  input                                                     clk_i,
  input                                                     rst_ni,

  output bit                                                override_wait_cyc_mask_o,
  output bit [ping_timer_force_agent_pkg::MaxPingCntDw-1:0] desired_wait_cyc_mask_val_o,
  input bit                                                 wait_cyc_mask_overridden_i
);
  import uvm_pkg::*;
  import ping_timer_force_agent_pkg::MaxPingCntDw;

  // Request that the wait_cyc_mask_i input to ping timer is forced to equal desired_value. This
  // force will remain until a reset is seen, at which point the task will finish.
  //
  // The implementation works by communicating with ping_timer_force_bound_if, which will flip the
  // value of wait_cyc_mask_overridden_i when the override has finished.
  task automatic override_wait_cyc_mask(bit [MaxPingCntDw-1:0] desired_value);
    if (override_wait_cyc_mask_o) begin
      `uvm_fatal($sformatf("%m"), "Overlapping calls to override_wait_cyc_mask.")
    end

    desired_wait_cyc_mask_val_o = desired_value;
    override_wait_cyc_mask_o = 1;
    @(wait_cyc_mask_overridden_i);
    override_wait_cyc_mask_o = 0;
  endtask
endinterface
