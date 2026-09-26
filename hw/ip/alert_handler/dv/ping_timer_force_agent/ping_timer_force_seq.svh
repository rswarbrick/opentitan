// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A single item sequence that forces the wait_cyc_mask_i input to an instance of
// alert_handler_ping_timer to a particular value and then waits until reset before releasing the
// force.

class ping_timer_force_seq extends uvm_sequence #(ping_timer_force_seq_item);
  `uvm_object_utils(ping_timer_force_seq)

  // The single item that should be sent. This gets randomised with the rest of the sequence (*not*
  // late randomisation: practically speaking there won't be any delay, so that wouldn't give any
  // benefit)
  rand ping_timer_force_seq_item m_item;

  extern function new(string name="");
  extern task body();
endclass

function ping_timer_force_seq::new(string name="");
  super.new(name);
  m_item = ping_timer_force_seq_item::type_id::create("m_item");
endfunction

task ping_timer_force_seq::body();
  start_item(m_item);
  finish_item(m_item);
endtask
