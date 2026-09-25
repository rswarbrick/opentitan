// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A simple sequence that sends exactly one lpg_item, which sets up the flags for a single LPG.
//
// The lpg_item that this sequence sends is randomised with the sequence and the status_item that
// shows the response (telling the caller whether the item was interrupted) is visible in
// m_rsp.

class lpg_seq extends uvm_sequence #(lpg_seq_item, status_item);
  `uvm_object_utils(lpg_seq)

  // The single item that should be sent. This gets randomised with the rest of the sequence (*not*
  // late randomisation: practically speaking there won't be any delay, so that wouldn't give any
  // benefit)
  rand lpg_seq_item m_item;

  // An item that gives the response to m_item. This will be null until the sequence has run, at
  // which point it will be given the response from the driver.
  status_item m_rsp;

  extern function new(string name="");
  extern task body();
endclass

function lpg_seq::new(string name="");
  super.new(name);
  m_item = lpg_seq_item::type_id::create("m_item");
endfunction

task lpg_seq::body();
  start_item(m_item);
  finish_item(m_item);
  get_response(m_rsp, m_item.get_transaction_id());
endtask
