// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A single item sequence that forces the an accumulator to a particular value until reset (or until
// abort() is called).

class force_class_accum_seq extends uvm_sequence #(force_class_accum_seq_item);
  `uvm_object_utils(force_class_accum_seq)

  // The single item that should be sent. This gets randomised with the rest of the sequence (*not*
  // late randomisation: practically speaking there won't be any delay, so that wouldn't give any
  // benefit)
  rand force_class_accum_seq_item m_item;

  extern function new(string name="");
  extern task body();

  // Mark m_item as aborted and then wait until this sequence finishes (which should be immediate)
  extern task abort();
endclass

function force_class_accum_seq::new(string name="");
  super.new(name);
  m_item = force_class_accum_seq_item::type_id::create("m_item");
endfunction

task force_class_accum_seq::body();
  start_item(m_item);
  finish_item(m_item);
endtask

task force_class_accum_seq::abort();
  m_item.abort();
  wait_for_sequence_state(UVM_FINISHED | UVM_STOPPED);
endtask
