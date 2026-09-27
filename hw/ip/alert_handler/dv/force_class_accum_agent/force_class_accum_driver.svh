// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Driver that interacts with a force_class_accum_if to request forcing a count.
//
// This drives a single item at a time, driving that item until reset. There is no response item
// sent back to the sequencer.
//
// An item can request that its forcing action is aborted, in which case, the driver will finish the
// item immediately. If this is not done, the item will be driven until the next reset.

class force_class_accum_driver extends dv_base_driver #(force_class_accum_seq_item,
                                                       force_class_accum_agent_cfg);
  `uvm_component_utils(force_class_accum_driver)

  extern function new(string name, uvm_component parent);
  extern virtual task run_phase(uvm_phase phase);
endclass

function force_class_accum_driver::new(string name, uvm_component parent);
  super.new(name, parent);
endfunction

task force_class_accum_driver::run_phase(uvm_phase phase);
  if (cfg.vif == null) begin
    `uvm_fatal("no_vif", "Cannot drive interface: vif is null.")
    return;
  end

  forever begin
    seq_item_port.get_next_item(req);
    if (!req.is_aborted()) begin
      fork : isolation_fork begin
        bit aborting;
        fork
          cfg.vif.apply_override(req.m_desired_value);
          begin
            req.wait_aborted();
            aborting = 1;
            cfg.vif.abort_override();
          end
        join_any

        // If aborting is false then the override has finished and wait_aborted() is still waiting.
        // Use disable fork to clear up the process.
        if (!aborting) begin
          disable fork;
        end

        // At this point, we've either just disabled the process that hadn't finished or we had
        // started aborting the item. Wait for all remaining processes either way.
        wait fork;
      end join
    end
    seq_item_port.item_done();
  end
endtask
