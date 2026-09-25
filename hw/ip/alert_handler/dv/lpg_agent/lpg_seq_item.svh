// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Sequence item that represents an LPG setting

class lpg_seq_item extends uvm_sequence_item;
  `uvm_object_utils(lpg_seq_item)

  // The low power group that is addressed
  rand int unsigned m_lpg_idx;

  // Clock gating enable for the LPG (as a mubi4_t)
  rand bit [3:0] m_cg_en;

  // Reset enable for the LPG (as a mubi4_t)
  rand bit [3:0] m_rst_en;

  extern function new(string name="");
  extern virtual function void do_print(uvm_printer printer);

  extern local function void print_mubi4_t_field(uvm_printer printer, string name, bit [3:0] value);
endclass

function lpg_seq_item::new(string name="");
  super.new(name);
endfunction

function void lpg_seq_item::do_print(uvm_printer printer);
  super.do_print(printer);
  printer.print_field_int("m_lpg_idx", m_lpg_idx, 32, UVM_NORADIX);
  print_mubi4_t_field(printer, "m_cg_en", m_cg_en);
  print_mubi4_t_field(printer, "m_rst_en", m_rst_en);
endfunction

function void lpg_seq_item::print_mubi4_t_field(uvm_printer printer,
                                                string      name,
                                                bit [3:0]   value);
  import prim_mubi_pkg::mubi4_t;

  mubi4_t as_enum = mubi4_t'(value);
  string  str = as_enum.name();

  if (str == "") begin
    str = "(?)";
  end

  printer.print_generic(name, "mubi4_t", 4, $sformatf("%-10s = 4'b%04b", str, value));
endfunction
