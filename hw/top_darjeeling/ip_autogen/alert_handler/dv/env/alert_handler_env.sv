// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class alert_handler_env extends cip_base_env #(
    .CFG_T              (alert_handler_env_cfg),
    .COV_T              (alert_handler_env_cov),
    .VIRTUAL_SEQUENCER_T(alert_handler_virtual_sequencer),
    .SCOREBOARD_T       (alert_handler_scoreboard)
  );
  `uvm_component_utils(alert_handler_env)

  `uvm_component_new

  alert_agent alert_host_agent[];
  esc_agent   esc_device_agent[];

  // An agent for the interface that configures LPGs for alert_handler
  lpg_agent m_lpg_agent;

  // A passive agent for the interface that reports ping requests inside alert_handler
  ping_req_agent m_ping_req_agent;

  // An agent that can be used to force signals in an alert_handler_ping_timer inside the device
  ping_timer_force_agent m_ping_timer_force_agent;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Build alert agents
    alert_host_agent                    = new[NUM_ALERTS];
    virtual_sequencer.alert_host_seqr_h = new[NUM_ALERTS];
    foreach (alert_host_agent[i]) begin
      string agent_name = $sformatf("alert_host_agent[%0d]", i);
      alert_host_agent[i] = alert_agent::type_id::create(agent_name, this);
      uvm_config_db#(alert_agent_cfg)::set(this, agent_name, "cfg", cfg.alert_host_cfg[i]);
      cfg.alert_host_cfg[i].en_cov = cfg.en_cov;
      cfg.alert_host_cfg[i].clk_freq_mhz = int'(cfg.clk_freq_mhz);
    end

    // Build escalator agents
    esc_device_agent                    = new[NUM_ESCS];
    virtual_sequencer.esc_device_seqr_h = new[NUM_ESCS];
    foreach (esc_device_agent[i]) begin
      string agent_name = $sformatf("esc_device_agent[%0d]", i);
      esc_device_agent[i] = esc_agent::type_id::create(agent_name, this);
      uvm_config_db#(esc_agent_cfg)::set(this, agent_name, "cfg", cfg.esc_device_cfg[i]);
      cfg.esc_device_cfg[i].en_cov = cfg.en_cov;
    end

    // Build LPG agent
    m_lpg_agent = lpg_agent::type_id::create("m_lpg_agent", this);
    m_lpg_agent.cfg = cfg.m_lpg_agent_cfg;

    // Build ping request agent
    m_ping_req_agent = ping_req_agent::type_id::create("m_ping_req_agent", this);
    m_ping_req_agent.cfg = cfg.m_ping_req_agent_cfg;

    // Build ping timer forcing agent
    m_ping_timer_force_agent = ping_timer_force_agent::type_id::create("m_ping_timer_force_agent",
                                                                       this);
    m_ping_timer_force_agent.cfg = cfg.m_ping_timer_force_agent_cfg;

    // Get vifs
    if (!uvm_config_db#(crashdump_vif)::get(this, "", "crashdump_vif", cfg.crashdump_vif)) begin
      `uvm_fatal("no_vif", "Failed to get crashdump_vif from uvm_config_db")
    end
    if (!uvm_config_db#(virtual lpg_if)::get(this, "", "lpg_vif", cfg.m_lpg_agent_cfg.vif)) begin
      `uvm_fatal("no_vif", "Failed to get lpg_vif from uvm_config_db.")
    end
    if (!uvm_config_db#(virtual ping_req_if)::get(this, "", "ping_req_vif",
                                                  cfg.m_ping_req_agent_cfg.vif)) begin
      `uvm_fatal("no_vif", "Failed to get ping_req_vif from uvm_config_db.")
    end
    if (!uvm_config_db#(virtual ping_timer_force_if)::get(
           this, "", "ping_timer_force_vif", cfg.m_ping_timer_force_agent_cfg.vif)
        ) begin
      `uvm_fatal("no_vif", "Failed to get ping_timer_force_vif from uvm_config_db.")
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.en_scb) begin
      foreach (alert_host_agent[i]) begin
        alert_host_agent[i].m_alert_port.connect(scoreboard.alert_fifo[i].analysis_export);
      end
      foreach (esc_device_agent[i]) begin
        esc_device_agent[i].m_esc_port.connect(scoreboard.esc_fifo[i].analysis_export);
      end
    end
    if (cfg.is_active) begin
      foreach (alert_host_agent[i]) begin
        if (cfg.alert_host_cfg[i].is_active) begin
          virtual_sequencer.alert_host_seqr_h[i] = alert_host_agent[i].sequencer;
        end
      end
    end
    foreach (esc_device_agent[i]) begin
      if (cfg.esc_device_cfg[i].is_active) begin
        virtual_sequencer.esc_device_seqr_h[i] = esc_device_agent[i].sequencer;
      end
    end

    m_lpg_agent.m_analysis_port.connect(scoreboard.m_lpg_imp);
    m_ping_req_agent.m_analysis_port.connect(scoreboard.m_ping_req_imp);
  endfunction

endclass
