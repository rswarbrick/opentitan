// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class lpg_agent extends dv_base_agent #(.CFG_T      (lpg_agent_cfg),
                                        .DRIVER_T   (lpg_driver),
                                        .SEQUENCER_T(lpg_sequencer),
                                        .MONITOR_T  (lpg_monitor));
  `uvm_component_utils(lpg_agent)

  // An analysis port that broadcasts monitored items from the LPG interface
  uvm_analysis_port #(lpg_seq_item) m_analysis_port;

  extern function new (string name, uvm_component parent);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);
endclass

function lpg_agent::new (string name, uvm_component parent);
  super.new(name, parent);
endfunction

function void lpg_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  m_analysis_port = new("m_analysis_port", this);

  // If cfg.vif isn't already supplied, look up a vif interface handle in the config db.
  if (cfg.vif == null &&
      !uvm_config_db#(virtual lpg_if)::get(this, "", "vif", cfg.vif)) begin
    `uvm_fatal(get_full_name(), "Failed to get vif from from uvm_config_db")
  end

  // If the agent is configured to be active, make sure that the is_active flag in the interface is
  // also set: if it isn't our updates to the *_internal signals will have no effect.
  if (cfg.is_active && !cfg.vif.is_active) begin
    `uvm_fatal(get_full_name(), "Agent is active but the interface's is_active signal is false.")
  end
endfunction

function void lpg_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  monitor.analysis_port.connect(m_analysis_port);
endfunction
