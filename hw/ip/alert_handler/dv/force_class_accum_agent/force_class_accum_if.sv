// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Interface for that allows a force_class_accum_agent to interact with a prim_count inside the
// accumulator for a class in the design.

interface force_class_accum_if (
  input                                                      clk_i,
  input                                                      rst_ni,

  output bit                                                 override_prim_count_o,
  output bit [force_class_accum_agent_pkg::MaxAccuCntDw-1:0] desired_prim_count_o,
  input bit                                                  prim_count_overridden_i,
  output bit                                                 stop_prim_count_override_o
);
  import uvm_pkg::*;
  import force_class_accum_agent_pkg::MaxAccuCntDw;

  // Request that the count in the related alert_handler_accu instance is forced to equal
  // desired_value. This force will remain applied until either a reset is seen or the
  // stop_prim_count_override_o signal goes high. When either of these happens, the
  // force_class_accum_bound_if with which we are communicating will change the value of
  // prim_count_overridden_i and this task will finish.
  task automatic apply_override(bit [MaxAccuCntDw-1:0] desired_value);
    if (override_prim_count_o) begin
      `uvm_fatal($sformatf("%m"), "Overlapping calls to apply_override.")
    end

    desired_prim_count_o = desired_value;
    override_prim_count_o = 1;
    @(prim_count_overridden_i);
    override_prim_count_o = 0;
  endtask

  // Abort a request that is currently in place for a prim_count override. This will end (at the
  // same time as the override_prim_count task) when the bound interface changes
  // prim_count_overridden_i.
  task automatic abort_override();
    if (stop_prim_count_override_o) begin
      `uvm_fatal($sformatf("%m"), "Overlapping calls to abort_override.")
    end
    if (!override_prim_count_o) begin
      `uvm_fatal($sformatf("%m"), "Cannot abort an override: there is not one in progress.")
    end

    stop_prim_count_override_o = 1;
    wait(!override_prim_count_o);
    stop_prim_count_override_o = 0;
  endtask

endinterface
