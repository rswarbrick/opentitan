// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Monitor that watches a ping_req_if and reports any starts/ends of ping requests

class ping_req_monitor extends dv_base_monitor #(.ITEM_T (ping_req_seq_item),
                                                 .CFG_T  (ping_req_agent_cfg));
  `uvm_component_utils(ping_req_monitor)

  extern function new (string name, uvm_component parent);
  extern virtual task run_phase(uvm_phase phase);

  // Watch the interface while not in reset. This task will be killed when reset is asserted
  extern local task run_between_resets();

  // Report a change in a ping request
  extern local function void report_diff(req_type_e   req_type,
                                         int unsigned idx,
                                         req_stage_e  req_stage);
endclass

function ping_req_monitor::new(string name, uvm_component parent);
  super.new(name, parent);
endfunction

task ping_req_monitor::run_phase(uvm_phase phase);
  if (cfg.vif == null) `uvm_fatal("no_vif", "No virtual interface")

  fork
    super.run_phase(phase);
    forever begin
      wait(cfg.vif.rst_n);
      fork : isolation_fork begin
        fork
          wait(!cfg.vif.rst_n);
          run_between_resets();
        join_any
        disable fork;
      end join
    end
  join_none
endtask

task ping_req_monitor::run_between_resets();
  bit [MaxAlertIfs-1:0]      last_alert_ping_reqs, alert_diff;
  bit [MaxEscalationIfs-1:0] last_esc_ping_reqs, esc_diff;

  forever begin
    last_alert_ping_reqs = cfg.vif.mon_cb.alert_ping_reqs;
    last_esc_ping_reqs   = cfg.vif.mon_cb.esc_ping_reqs;

    @(cfg.vif.mon_cb.alert_ping_reqs or cfg.vif.mon_cb.esc_ping_reqs);

    alert_diff = last_alert_ping_reqs ^ cfg.vif.mon_cb.alert_ping_reqs;
    esc_diff   = last_esc_ping_reqs ^ cfg.vif.mon_cb.esc_ping_reqs;

    for (int unsigned i = 0; i < MaxAlertIfs; i++) begin
      if (alert_diff[i]) begin
        report_diff(AlertPingReq,
                    i,
                    cfg.vif.mon_cb.alert_ping_reqs[i] ? PingReqStart : PingReqEnd);
      end
    end
    for (int unsigned i = 0; i < MaxEscalationIfs; i++) begin
      if (esc_diff[i]) begin
        report_diff(EscPingReq,
                    i,
                    cfg.vif.mon_cb.esc_ping_reqs[i] ? PingReqStart : PingReqEnd);
      end
    end
  end
endtask

function void ping_req_monitor::report_diff(req_type_e   req_type,
                                            int unsigned idx,
                                            req_stage_e  req_stage);
  ping_req_seq_item item = ping_req_seq_item::type_id::create("item");
  item.m_req_type = req_type;
  item.m_idx = idx;
  item.m_req_stage = req_stage;
  analysis_port.write(item);
endfunction
