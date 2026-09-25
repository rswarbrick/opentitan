// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Interface for LPG signals passed to an alert_handler.
//
// This interface uses a "max footprint" approach, which allows it not to be parameterised by the
// number of LPGs.

interface lpg_if(input clk, input rst_n);
  import uvm_pkg::*;
  import prim_mubi_pkg::mubi4_t;
  import lpg_agent_pkg::MaxNumLpgs;

  // The number of LPGs tracked by the interface. Set this by calling set_num_lpgs()
  int unsigned num_lpgs;

  // A mask based on num_lpgs that can be used to pull out just supported LPGs from lpg_cg_en_driven
  // and lpg_rst_en_driven.
  bit [4*MaxNumLpgs-1:0] lpg_mask;

  // If is_active is true, the signals that will be connected to its input ports are driven by cb.
  // If is_active is false, they are driven with 'z here, which allows the interface to monitor a
  // larger design that drives the alert handler itself.
  //
  // The flag is defined as a wire with a weak pull-up. This ensures that a testbench that doesn't
  // customise is_active will see the interface be driven actively, but allows a testbench that
  // *does* want to customise the signal to pull it low.
  wire is_active;
  assign (weak0, weak1) is_active = 1'b1;

  // Clock gating enables for the different LPGs, with the same layout as expected by the
  // alert_handler's lpg_cg_en_i port
  wire mubi4_t [MaxNumLpgs-1:0] lpg_cg_en;

  // Reset enables for the different LPGs, with the same layout as expected by the alert_handler's
  // lpg_rst_en_i port
  wire mubi4_t [MaxNumLpgs-1:0] lpg_rst_en;

  // "Internal" and "driven" versions of the wires above. The "driven" version is the output of the
  // clocking block. This gets reflected in the "internal" version when not in reset.
  mubi4_t [MaxNumLpgs-1:0] lpg_cg_en_internal, lpg_cg_en_driven;
  mubi4_t [MaxNumLpgs-1:0] lpg_rst_en_internal, lpg_rst_en_driven;

  // When the interface is actively driven, drive lpg_cg_en and lpg_rst_en. If not, leave the
  // signals high-impedence (to allow passive mode).
  assign lpg_cg_en  = is_active ? lpg_cg_en_internal : 'z;
  assign lpg_rst_en = is_active ? lpg_rst_en_internal : 'z;

  // For LPGs that exist, copy the "driven" signals to the "internal" signals when not in reset
  always_comb begin
    lpg_cg_en_internal  = rst_n ? lpg_cg_en_driven & lpg_mask  : '0;
    lpg_rst_en_internal = rst_n ? lpg_rst_en_driven & lpg_mask : '0;
  end

  // An active clocking block for the lpg_cg_en and lpg_rst_en signals, which are driven on the
  // posedge of the clock.
  clocking cb @(posedge clk);
    output lpg_cg_en  = lpg_cg_en_driven;
    output lpg_rst_en = lpg_rst_en_driven;
  endclocking

  // A monitor clocking block for lpg_cg_en and lpg_rst_en
  clocking mon_cb @(posedge clk);
    input lpg_cg_en;
    input lpg_rst_en;
  endclocking

  // Set the number of LPGs to be supported by the interface
  function automatic void set_num_lpgs(int unsigned num);
    if (!num) `uvm_fatal($sformatf("%m::set_num_lpgs"), "Must have at least one LPG")
    if (num > MaxNumLpgs) begin
      `uvm_fatal($sformatf("%m::set_num_lpgs"),
                 $sformatf("Cannot set num_lpgs = %0d: MaxNumLpgs is %0d.", num, MaxNumLpgs))
    end

    num_lpgs = num;
    lpg_mask = ((MaxNumLpgs*4)'(1) << (4 * num)) - 1;
  endfunction
endinterface
