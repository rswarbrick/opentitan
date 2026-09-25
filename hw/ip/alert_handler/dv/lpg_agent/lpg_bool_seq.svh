// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A specialisation of lpg_seq where the single sequence item that will be sent is constrained more
// explicitly from boolean values.

class lpg_bool_seq extends lpg_seq;
  `uvm_object_utils(lpg_bool_seq)

  // The LPG index that should be addressed by the sequence. This will be used for m_item.m_lpg_idx.
  rand int unsigned m_lpg_idx;

  // Should clock gating be enabled?
  rand bit          m_cg_en;

  // Should reset be enabled?
  rand bit          m_rst_en;

  extern function new(string name="");

  // Reflect the LPG index and the boolean values in m_lpg_idx, m_cg_en and m_rst_en in the
  // randomisation of m_item. True gets mapped to MuBi4True and false gets mapped to MuBi4False.
  //
  // Note that we don't select an arbitrary different 4-bit value for an item value for "false". The
  // reason is that the cg_en and rst_en signals are combined with mubi4_or_hi. There exist values
  // A, B other than MuBi4True such that mubi4_or_hi(A, B) = MuBi4True and we don't want to disable
  // an LPG by accident.
  //
  // This sequence isn't designed for use in a security test where we assert stability of whether
  // the alert channels are enabled.
  extern constraint item_c;
endclass

function lpg_bool_seq::new(string name="");
  super.new(name);
endfunction

constraint lpg_bool_seq::item_c {
  m_item.m_lpg_idx == m_lpg_idx;
  m_item.m_cg_en   == (m_cg_en ? prim_mubi_pkg::MuBi4True : prim_mubi_pkg::MuBi4False);
  m_item.m_rst_en  == (m_rst_en ? prim_mubi_pkg::MuBi4True : prim_mubi_pkg::MuBi4False);
}
