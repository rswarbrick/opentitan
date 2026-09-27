// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class force_class_accum_agent extends dv_base_agent #(.CFG_T      (force_class_accum_agent_cfg),
                                                      .DRIVER_T   (force_class_accum_driver),
                                                      .SEQUENCER_T(force_class_accum_sequencer));
  `uvm_component_utils(force_class_accum_agent)

  extern function new (string name, uvm_component parent);
  extern function void build_phase(uvm_phase phase);
endclass

function force_class_accum_agent::new (string name, uvm_component parent);
  super.new(name, parent);
endfunction

function void force_class_accum_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);
  // If cfg.vif isn't already supplied, look up a vif interface handle in the config db.
  if (cfg.vif == null &&
      !uvm_config_db#(virtual force_class_accum_if)::get(this, "", "vif", cfg.vif)) begin
    `uvm_fatal(get_full_name(), "Failed to get vif from from uvm_config_db")
  end
endfunction
