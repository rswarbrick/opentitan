// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A module that tracks emulated info regions and subregions, as configured by registers. The exact
// rules for when a region or a subregion is active are complicated. This module tracks the regions
// and subregions that are enabled.
//
// It has no output ports: the testbench can see the computed values with hierarchical references.

module emul_info_tracker
  import prim_mubi_pkg::MuBi4True;
  import rram_ctrl_pkg::EmulInfoSubregionsPerRegion;
  import rram_ctrl_reg_pkg::NumEmulInfoRegions;
  import rram_ctrl_reg_pkg::NumEmulInfoSubregions;
  import rram_ctrl_reg_pkg::BytesPerPage;
  import rram_ctrl_reg_pkg::rram_ctrl_reg2hw_emul_info_region_mreg_t;
  import rram_ctrl_reg_pkg::rram_ctrl_reg2hw_emul_info_regwen_mreg_t;
  import rram_ctrl_reg_pkg::rram_ctrl_reg2hw_emul_info_subregion_regwen_mreg_t;
  import rram_ctrl_reg_pkg::rram_ctrl_reg2hw_emul_info_subregion_mreg_t;
(
  // The EMUL_INFO_REGWEN multireg
  input wire rram_ctrl_reg2hw_emul_info_regwen_mreg_t [NumEmulInfoRegions-1:0] emul_info_regwen_i,

  // The EMUL_INFO_REGION multireg
  input wire rram_ctrl_reg2hw_emul_info_region_mreg_t [NumEmulInfoRegions-1:0] emul_info_region_i,

  // The EMUL_INFO_SUBREGION_REGWEN multireg
  input wire rram_ctrl_reg2hw_emul_info_subregion_regwen_mreg_t [NumEmulInfoSubregions-1:0]
    emul_info_subregion_regwen_i,

  // The EMUL_INFO_SUBREGION multireg
  input wire rram_ctrl_reg2hw_emul_info_subregion_mreg_t [NumEmulInfoSubregions-1:0]
    emul_info_subregion_i
);

  // Each emulated info region defines a window. That region is only enabled if the EN value in its
  // EMUL_INFO_REGION register is MuBi4True and if the associated regwen is locked.
  logic [NumEmulInfoRegions-1:0] region_enabled_flags;
  logic [NumEmulInfoRegions-1:0] region_regwen_locked;
  logic [NumEmulInfoRegions-1:0] region_enabled;

  // The minimum and maximum (inclusive) address inside each region.
  logic [NumEmulInfoRegions-1:0] region_base, region_top;

  // The window for a region might overlap with another region's window, in which case both regions'
  // windows will be disabled. To detect this, build the symmetrical windows_overlap
  // matrix where the value at (i, j) is true if the window for region i overlaps with the window
  // for region j.
  logic [NumEmulInfoRegions-1:0][NumEmulInfoRegions-1:0] windows_overlap;

  // A region can only be used if it doesn't overlap with any other regions, which means that the
  // only region it overlaps with is itself.
  logic [NumEmulInfoRegions-1:0] region_separate;

  for (genvar i = 0; i < NumEmulInfoRegions; i++) begin : gen_region_i
    assign region_enabled_flags[i] = (emul_info_region_i[i].en.q == MuBi4True);
    assign region_regwen_locked[i] = ~emul_info_regwen_i[i].q;

    assign region_base[i] = emul_info_region_i[i].base.q;
    assign region_top[i] = region_base[i] + ((1 + emul_info_region_i[i].size.q) * BytesPerPage);

    for (genvar j = 0; j < NumEmulInfoRegions; j++) begin : gen_region_j
      assign windows_overlap[i][j] =
        ((region_base[i] <= region_base[j]) && (region_base[j] <= region_top[i])) ||
        ((region_base[j] <= region_base[i]) && (region_base[i] <= region_top[j]));
    end

    // A region is separate if there is at most a single bit set in windows_overlap[i]. To check
    // this, check that "x & (x - 1)" has no bits set.
    assign region_separate[i] = ~|(windows_overlap[i] & (windows_overlap[i] - 1));
  end

  assign region_enabled = region_enabled_flags & region_regwen_locked;

  // A flag that says a subregion's placement is locked (not taking earlier subregions into account)
  logic [NumEmulInfoSubregions-1:0] subregion_placement_locked;

  // A flag that says a subregion is the first that applies to its target region
  logic [NumEmulInfoSubregions-1:0] subregion_first_for_region;

  // A flag that says a subregion is the either first that applies to its target region *or* the
  // chain of subregions before this one are all locked. This might depend on the previous item of
  // subregion_locked_chain.
  logic [NumEmulInfoSubregions-1:0] prev_subregions_locked;

  // A flag that says the placement of this subregion and all subregions that come before it in the
  // same region are locked.
  logic [NumEmulInfoSubregions-1:0] subregion_locked_chain;

  // A flag that says the TOP of this subregion doesn't exceed its window's SIZE
  logic [NumEmulInfoSubregions-1:0] subregion_fits;

  // A flag that says whether subregions are enabled. The rules for this are defined in the
  // specification of EMUL_INFO_SUBREGION with the following text:
  //
  //  A subregion is enabled once all of the following hold.
  //  - Its window is enabled via !!EMUL_INFO_REGION.EN and locked via !!EMUL_INFO_REGWEN.
  //
  //    - True if region_enabled[i / EmulInfoSubregionsPerRegion]
  //
  //  - Its own placement and that of every lower-indexed subregion of its window are locked via
  //    !!EMUL_INFO_SUBREGION_REGWEN, i.e., the whole lock chain back to the first subregion of its
  //    window.
  //
  //    - True if subregion_locked_chain[i]
  //
  //  - Its TOP does not exceed its window's SIZE.
  //
  //    - True if subregion_fits[i]
  //
  //  - Its window does not overlap any other enabled window.
  //
  //    - True if region_separate[i / EmulInfoSubregionsPerRegion]
  logic [NumEmulInfoSubregions-1:0] subregion_enabled;

  for (genvar i = 0; i < NumEmulInfoSubregions; i++) begin : gen_subregion_i
    assign subregion_placement_locked[i] = !emul_info_subregion_regwen_i[i].q;
    assign subregion_first_for_region[i] = ((i % EmulInfoSubregionsPerRegion) == 0);

    if (i == 0) begin : gen_first
      // The first subregion is the first subregion of the first region, so there are no subregions
      // that come before it. As such, prev_subregions_locked is trivially true.
      assign prev_subregions_locked[0] = 1;
    end else begin : gen_rest
      // Is every earlier subregion for this region locked? Yes if this is the first subregion of
      // the region. If there are earlier subregions, check subregion_locked_chain for the previous
      // subregion.
      assign prev_subregions_locked[i] = (subregion_first_for_region[i] ?
                                          1 :
                                          subregion_locked_chain[i - 1]);
    end

    assign subregion_locked_chain[i] = (subregion_placement_locked[i] && prev_subregions_locked[i]);
    assign subregion_fits[i] =
      (emul_info_subregion_i[i].q < region_top[i / EmulInfoSubregionsPerRegion]);

    assign subregion_enabled[i] =
      region_enabled[i / EmulInfoSubregionsPerRegion] &&
      subregion_locked_chain[i] &&
      subregion_fits[i] &&
      region_separate[i / EmulInfoSubregionsPerRegion];
  end
endmodule
