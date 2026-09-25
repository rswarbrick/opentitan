// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Driver that sends settings for LPGs
//
// Any item will be given a status response (which should be consumed by the sequence)

class lpg_driver extends dv_base_driver #(lpg_seq_item, lpg_agent_cfg, status_item);
  `uvm_component_utils(lpg_driver)

  extern function new(string name, uvm_component parent);
  extern virtual task run_phase(uvm_phase phase);

  // Drive the given item through cfg.vif.cb, then put a response to seq_item_port.
  //
  // This will normally take one cycle (the next edge of the clocking block) but will complete
  // immediately on reset.
  extern local task drive_item(lpg_seq_item req_item);
endclass

function lpg_driver::new(string name, uvm_component parent);
  super.new(name, parent);
endfunction

task lpg_driver::run_phase(uvm_phase phase);
  if (cfg.vif == null) begin
    `uvm_fatal("no_vif", "Cannot drive interface: vif is null.")
    return;
  end

  forever begin
    lpg_seq_item req_item;

    seq_item_port.get(req_item);

    // Fork off a background thread that drives the item and then sends a response to the sequencer.
    // This will complete on the next clocking event or reset.
    fork begin
      automatic lpg_seq_item req_item_ = req_item;
      drive_item(req_item_);
    end join_none
  end
endtask

task lpg_driver::drive_item(lpg_seq_item req_item);
  status_item rsp_item = status_item::type_id::create("rsp_item");

  // Check that the requested LPG index is possible for the interface
  if (req_item.m_lpg_idx >= cfg.vif.num_lpgs) begin
    `uvm_fatal("bad_lpg_idx",
               $sformatf("Can't drive item with m_lpg_idx=%0d: the interface has num_lpg=%0d.",
                         req_item.m_lpg_idx, cfg.vif.num_lpgs))
  end

  // Try to drive the item to the clocking block, which will complete on the clocking event or
  // complete early if reset is asserted.
  fork : isolation_fork begin
    fork
      wait(!cfg.vif.rst_n);
      begin
        cfg.vif.cb.lpg_cg_en[req_item.m_lpg_idx]  <= mubi4_t'(req_item.m_cg_en);
        cfg.vif.cb.lpg_rst_en[req_item.m_lpg_idx] <= mubi4_t'(req_item.m_rst_en);
        @cfg.vif.cb;
      end
    join_any
    disable fork;
  end join

  // Send a response to the item that was just sent (which allows us to tell the sequence that the
  // item is done, and whether we have seen a reset). Sending is complete if cfg.vif.rst_n is still
  // true (because that means the fork above completed with a clocking event).
  rsp_item.set_id_info(req_item);
  rsp_item.m_sending_complete = cfg.vif.rst_n;
  seq_item_port.put_response(rsp_item);
endtask
