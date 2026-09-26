// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class ping_req_agent extends dv_base_agent #(.CFG_T     (ping_req_agent_cfg),
                                             .MONITOR_T (ping_req_monitor));
  `uvm_component_utils(ping_req_agent)

  // An analysis port that broadcasts monitored items from the interface
  uvm_analysis_port #(ping_req_seq_item) m_analysis_port;

  extern function new (string name, uvm_component parent);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);
endclass

function ping_req_agent::new (string name, uvm_component parent);
  super.new(name, parent);
endfunction

function void ping_req_agent::build_phase(uvm_phase phase);
  super.build_phase(phase);

  m_analysis_port = new("m_analysis_port", this);

  // If cfg.vif isn't already supplied, look up a vif interface handle in the config db.
  if (cfg.vif == null &&
      !uvm_config_db#(virtual ping_req_if)::get(this, "", "vif", cfg.vif)) begin
    `uvm_fatal("no_vif", "Failed to get vif from from uvm_config_db")
  end

  // Make sure that the agent isn't configured to be active: that wouldn't make sense for this
  // agent.
  if (cfg.is_active) begin
    `uvm_fatal("passive_agent", "This agent cannot be active.")
  end
endfunction

function void ping_req_agent::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  monitor.analysis_port.connect(m_analysis_port);
endfunction
