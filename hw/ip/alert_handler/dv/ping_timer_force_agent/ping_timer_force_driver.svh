// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Driver that interacts with a ping_timer_force_if to request forcing a port value
//
// This drives a single item at a time, driving that item until reset. There is no response item
// sent back to the sequencer.

class ping_timer_force_driver extends dv_base_driver #(ping_timer_force_seq_item,
                                                       ping_timer_force_agent_cfg);
  `uvm_component_utils(ping_timer_force_driver)

  extern function new(string name, uvm_component parent);
  extern virtual task run_phase(uvm_phase phase);
endclass

function ping_timer_force_driver::new(string name, uvm_component parent);
  super.new(name, parent);
endfunction

task ping_timer_force_driver::run_phase(uvm_phase phase);
  if (cfg.vif == null) begin
    `uvm_fatal("no_vif", "Cannot drive interface: vif is null.")
    return;
  end

  forever begin
    seq_item_port.get_next_item(req);
    cfg.vif.override_wait_cyc_mask(req.m_desired_value);
    seq_item_port.item_done();
  end
endtask
