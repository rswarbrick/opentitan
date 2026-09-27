// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Sequence item that represents a value that should be forced into a prim_count inside the
// alert_handler_accu instance in alert_handler for a particular class.

class force_class_accum_seq_item extends uvm_sequence_item;
  `uvm_object_utils(force_class_accum_seq_item)

  // The value that should be forced into the prim_count. Note that this will need constraining by
  // the caller to ensure that it is representable in the number of bits actually being used in the
  // design.
  rand bit [MaxAccuCntDw-1:0] m_desired_value;

  // A flag that says that the forcing for this item should be aborted. Set this by calling abort()
  // and check its value by calling wait_aborted().
  local bit                   m_aborted;

  extern function new(string name="");
  extern virtual function void do_print(uvm_printer printer);

  // Set the m_aborted flag, which will cause the driver to stop driving this item
  extern function void abort();

  // Has the item already been aborted?
  extern function bit is_aborted();

  // Wait until the the m_aborted flag is set.
  extern task wait_aborted();
endclass

function force_class_accum_seq_item::new(string name="");
  super.new(name);
endfunction

function void force_class_accum_seq_item::do_print(uvm_printer printer);
  super.do_print(printer);
  printer.print_field_int("m_desired_value", m_desired_value, MaxAccuCntDw, UVM_NORADIX);
  printer.print_field_int("m_aborted", m_aborted, 1, UVM_BIN);
endfunction

function void force_class_accum_seq_item::abort();
  m_aborted = 1;
endfunction

function bit force_class_accum_seq_item::is_aborted();
  return m_aborted;
endfunction

task force_class_accum_seq_item::wait_aborted();
  wait (m_aborted);
endtask
