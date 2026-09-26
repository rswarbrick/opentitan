// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Sequence item that represents a value that should be forced onto the wait_cyc_mask_i port of an
// isntance of alert_handler_ping_timer.

class ping_timer_force_seq_item extends uvm_sequence_item;
  `uvm_object_utils(ping_timer_force_seq_item)

  // The value that should be forced onto the port. Note that this will need constraining by the
  // caller to ensure that it is representable in the number of bits actually being used in the
  // design.
  rand bit [MaxPingCntDw-1:0] m_desired_value;

  extern function new(string name="");
  extern virtual function void do_print(uvm_printer printer);
endclass

function ping_timer_force_seq_item::new(string name="");
  super.new(name);
endfunction

function void ping_timer_force_seq_item::do_print(uvm_printer printer);
  super.do_print(printer);
  printer.print_field_int("m_desired_value", m_desired_value, MaxPingCntDw, UVM_NORADIX);
endfunction
