// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Monitor that watches an lpg_if and reports updates to low power groups

class lpg_monitor extends dv_base_monitor #(.ITEM_T (lpg_seq_item), .CFG_T (lpg_agent_cfg));
  `uvm_component_utils(lpg_monitor)

  extern function new (string name, uvm_component parent);
  extern virtual task run_phase(uvm_phase phase);

  // Watch the interface while not in reset. This task will be killed when reset is asserted
  extern local task run_between_resets();
endclass

function lpg_monitor::new(string name, uvm_component parent);
  super.new(name, parent);
endfunction

task lpg_monitor::run_phase(uvm_phase phase);
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

task lpg_monitor::run_between_resets();
  mubi4_t [MaxNumLpgs-1:0] last_cg_en, last_rst_en;

  last_cg_en  = cfg.vif.mon_cb.lpg_cg_en & cfg.vif.lpg_mask;
  last_rst_en = cfg.vif.mon_cb.lpg_rst_en & cfg.vif.lpg_mask;

  forever begin
    mubi4_t [MaxNumLpgs-1:0] cg_diff, rst_diff;

    @(cfg.vif.mon_cb.lpg_cg_en & cfg.vif.lpg_mask,
      cfg.vif.mon_cb.lpg_rst_en & cfg.vif.lpg_mask);

    cg_diff  = (cfg.vif.mon_cb.lpg_cg_en ^ last_cg_en) & cfg.vif.lpg_mask;
    rst_diff = (cfg.vif.mon_cb.lpg_rst_en ^ last_rst_en) & cfg.vif.lpg_mask;

    for (int unsigned i = 0; i < cfg.vif.num_lpgs; i++) begin
      // If there has been a change to cg_en or rst_en for LPG i then bits 4*i .. 4*i + 3 of cg_diff
      // or rst_diff will have some bits set.
      if (((cg_diff | rst_diff) >> (4 * i)) & 4'hf) begin
        lpg_seq_item item = lpg_seq_item::type_id::create("item");
        item.m_lpg_idx = i;
        item.m_cg_en   = (cfg.vif.mon_cb.lpg_cg_en >> (4 * i));
        item.m_rst_en  = (cfg.vif.mon_cb.lpg_rst_en >> (4 * i));
        analysis_port.write(item);
      end
    end
  end
endtask
