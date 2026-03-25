// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Very simple sequence that sends a single item with the given mode values (which can all be
// randomised)

class rv_dm_mode_seq extends dv_base_seq #(.REQ (rv_dm_mode_seq_item),
                                           .SEQUENCER_T (rv_dm_mode_sequencer));
  `uvm_object_utils(rv_dm_mode_seq)

  bit m_has_next_dm_addr;
  rand bit [31:0] m_next_dm_addr;

  bit      m_has_lc_ctrl_signals;
  rand bit m_lc_hw_debug_clr;
  rand bit m_lc_hw_debug_en;
  rand bit m_lc_dft_en;
  rand bit m_lc_check_byp_en;
  rand bit m_lc_escalate_en;
  rand bit m_lc_init_done;
  rand bit m_strap_en_override;

  bit      m_has_pinmux_signals;
  rand bit m_pinmux_hw_debug_en;

  bit      m_has_pwrmgr_signals;
  rand bit m_strap_en;

  bit      m_has_otp_ctrl_signals;
  rand bit m_otp_dis_rv_dm_late_debug;

  bit      m_has_scanmode;
  rand bit m_scanmode;

  extern function new (string name="");
  extern virtual task body();

  extern static function bit [31:0] bool_to_something(bit          bool_val,
                                                      int unsigned width,
                                                      bit [31:0]   true_val);
  extern static function bit [3:0] bool_to_lc_tx_t(bit bool_val);
  extern static function bit [3:0] bool_to_mubi4_t(bit bool_val);
  extern static function bit [7:0] bool_to_mubi8_t(bit bool_val);
endclass

function rv_dm_mode_seq::new (string name="");
  super.new(name);
endfunction

task rv_dm_mode_seq::body();
  rv_dm_mode_seq_item item = rv_dm_mode_seq_item::type_id::create("item");
  item.m_has_next_dm_addr = m_has_next_dm_addr;
  item.m_has_lc_ctrl_signals = m_has_lc_ctrl_signals;
  item.m_has_pinmux_signals = m_has_pinmux_signals;
  item.m_has_pwrmgr_signals = m_has_pwrmgr_signals;
  item.m_has_otp_ctrl_signals = m_has_otp_ctrl_signals;
  item.m_has_scanmode = m_has_scanmode;

  start_item(item);
  if (!item.randomize() with {
          if (m_has_next_dm_addr) {
            item.m_next_dm_addr == local::m_next_dm_addr;
          }
          if (m_has_lc_ctrl_signals) {
            item.m_lc_hw_debug_clr == bool_to_lc_tx_t(local::m_lc_hw_debug_clr);
            item.m_lc_hw_debug_en == bool_to_lc_tx_t(local::m_lc_hw_debug_en);
            item.m_lc_dft_en == bool_to_lc_tx_t(local::m_lc_dft_en);
            item.m_lc_check_byp_en == bool_to_lc_tx_t(local::m_lc_check_byp_en);
            item.m_lc_escalate_en == bool_to_lc_tx_t(local::m_lc_escalate_en);
            item.m_lc_init_done == bool_to_lc_tx_t(local::m_lc_init_done);
            item.m_strap_en_override == local::m_strap_en_override;
          }
          if (m_has_pinmux_signals) {
            item.m_pinmux_hw_debug_en == bool_to_lc_tx_t(local::m_pinmux_hw_debug_en);
          }
          if (m_has_pwrmgr_signals) {
            item.m_strap_en == local::m_strap_en;
          }
          if (m_has_otp_ctrl_signals) {
            item.m_otp_dis_rv_dm_late_debug == bool_to_mubi8_t(local::m_otp_dis_rv_dm_late_debug);
          }
          if (m_has_scanmode) {
            item.m_scanmode == bool_to_mubi4_t(local::m_scanmode);
          }
       }) begin
    `uvm_fatal(get_name(), "Failed to randomize item")
  end
  finish_item(item);
endtask

function bit [31:0] rv_dm_mode_seq::bool_to_something(bit          bool_val,
                                                      int unsigned width,
                                                      bit [31:0]   true_val);
  bit [31:0] val;
  if (bool_val) begin
    val = true_val;
  end else begin
    // Pick a random value of width bits that isn't equal to true_val by using $urandom_range to
    // pick a nonzero value that fits in width bits, then xor that with true_val.
    bit [31:0] max_val = '1;
    max_val >>= (32 - width);
    val = $urandom_range(1, max_val) ^ true_val;
  end
  return val;
endfunction

function bit [3:0] rv_dm_mode_seq::bool_to_lc_tx_t(bit bool_val);
  return lc_ctrl_pkg::lc_tx_t'(bool_to_something(bool_val, 4, lc_ctrl_pkg::On));
endfunction

function bit [3:0] rv_dm_mode_seq::bool_to_mubi4_t(bit bool_val);
  return prim_mubi_pkg::mubi4_t'(bool_to_something(bool_val, 4, prim_mubi_pkg::MuBi4True));
endfunction

function bit [7:0] rv_dm_mode_seq::bool_to_mubi8_t(bit bool_val);
  return prim_mubi_pkg::mubi8_t'(bool_to_something(bool_val, 8, prim_mubi_pkg::MuBi8True));
endfunction
