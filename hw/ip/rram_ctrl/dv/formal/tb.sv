// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// A formal testbench module for rram_ctrl
//
// This testbench doesn't include "resets of rst_ni in the middle of a run". Instead, we constrain
// rst_ni to be 0 at the start and for it to clear afterwards. rst_otp_ni is addressed separately.

module tb
  import rram_ctrl_pkg::*;
  import rram_ctrl_reg_pkg::NumAlerts;
  import tlul_pkg::tl_h2d_t;
  import tlul_pkg::tl_d2h_t;
#(
  parameter logic [NumAlerts-1:0] AlertAsyncOn    = {NumAlerts{1'b1}},
  // Number of cycles a differential skew is tolerated on the alert signal
  parameter int unsigned          AlertSkewCycles = 1,
  parameter rram_key_t            RndCnstAddrKey  = RndCnstAddrKeyDefault,
  parameter rram_key_t            RndCnstDataKey  = RndCnstDataKeyDefault,
  parameter all_seeds_t           RndCnstAllSeeds = RndCnstAllSeedsDefault,
  parameter lfsr_seed_t           RndCnstLfsrSeed = RndCnstLfsrSeedDefault,
  parameter lfsr_perm_t           RndCnstLfsrPerm = RndCnstLfsrPermDefault,
  parameter int unsigned          WrFifoDepth     = MaxFifoDepth,
  parameter int unsigned          RdFifoDepth     = MaxFifoDepth,
  parameter bit                   SecScrambleEn   = 1'b1
) (
  input logic clk_i,
  input logic rst_ni,
  input logic clk_otp_i,
  input logic rst_otp_ni,
  input lc_ctrl_pkg::lc_tx_t lc_creator_seed_sw_rw_en_i,
  input lc_ctrl_pkg::lc_tx_t lc_owner_seed_sw_rw_en_i,
  input lc_ctrl_pkg::lc_tx_t lc_iso_part_sw_rd_en_i,
  input lc_ctrl_pkg::lc_tx_t lc_iso_part_sw_wr_en_i,
  input lc_ctrl_pkg::lc_tx_t lc_seed_hw_rd_en_i,
  input lc_ctrl_pkg::lc_tx_t lc_escalate_en_i,
  input  tl_h2d_t                                  core_tl_i,
  output tl_d2h_t                                  core_tl_o,
  input  tl_h2d_t                                  host_tl_i,
  output tl_d2h_t                                  host_tl_o,
  input  otp_ctrl_macro_pkg::otp_ctrl_macro_req_t  otp_macro_i,
  output otp_ctrl_macro_pkg::otp_ctrl_macro_rsp_t  otp_macro_o,
  output otp_ctrl_pkg::nvm_otp_key_req_t           otp_key_o,
  input  otp_ctrl_pkg::nvm_otp_key_rsp_t           otp_key_i,
  input  lc_ctrl_pkg::lc_tx_t                      rma_req_i,
  input  lc_ctrl_pkg::lc_nvm_rma_seed_t            rma_seed_i,
  output lc_ctrl_pkg::lc_tx_t                      rma_ack_o,
  output keymgr_dpe_pkg::keymgr_dpe_creator_seed_t keymgr_creator_seed_o,
  output keymgr_dpe_pkg::keymgr_dpe_owner_seed_t   keymgr_owner_seed_o,
  output pwrmgr_pkg::pwr_nvm_t                     pwrmgr_o,
  output logic intr_corr1_err_o, // Correctable single-bit error encountered
  output logic intr_corr2_err_o, // Correctable double-bit error encountered
  output logic intr_wr_empty_o, // Write fifo is empty
  output logic intr_wr_lvl_o,   // Write FIFO drained to level
  output logic intr_rd_full_o,  // Read fifo is full
  output logic intr_rd_lvl_o,   // Read FIFO filled to level
  output logic intr_op_done_o,  // Requested rram operation (rd/wr) done
  input  prim_alert_pkg::alert_rx_t [rram_ctrl_reg_pkg::NumAlerts-1:0] alert_rx_i,
  output prim_alert_pkg::alert_tx_t [rram_ctrl_reg_pkg::NumAlerts-1:0] alert_tx_o,
  output rram_macro_req_t rram_macro_o,
  input  rram_macro_rsp_t rram_macro_i
);
  import rram_ctrl_reg_pkg::BytesPerPage;
  import rram_ctrl_reg_pkg::NumEmulInfoRegions;
  import rram_ctrl_reg_pkg::NumEmulInfoSubregions;
  import top_pkg::TL_AW;

  // Model a "local reset" that applies at the start of time and no reset afterwards. Then add an
  // assumption that says this signal matches rst_ni on every clock edge.
  //
  // This formal TB will not prove any properties that span resets.
  logic local_rst_n = 1'b0;
  always_ff @(posedge clk_i) local_rst_n <= 1'b1;

  ResetMatchesLocal_M: assume property (@(posedge clk_i) rst_ni == local_rst_n);

  rram_ctrl #(
    .AlertAsyncOn(AlertAsyncOn),
    .AlertSkewCycles(AlertSkewCycles),
    .RndCnstAddrKey(RndCnstAddrKey),
    .RndCnstDataKey(RndCnstDataKey),
    .RndCnstAllSeeds(RndCnstAllSeeds),
    .RndCnstLfsrSeed(RndCnstLfsrSeed),
    .RndCnstLfsrPerm(RndCnstLfsrPerm),
    .WrFifoDepth(WrFifoDepth),
    .RdFifoDepth(RdFifoDepth),
    .SecScrambleEn(SecScrambleEn)
  ) dut (
    .clk_i,
    .rst_ni,
    .clk_otp_i,
    .rst_otp_ni,
    .lc_creator_seed_sw_rw_en_i,
    .lc_owner_seed_sw_rw_en_i,
    .lc_iso_part_sw_rd_en_i,
    .lc_iso_part_sw_wr_en_i,
    .lc_seed_hw_rd_en_i,
    .lc_escalate_en_i,
    .core_tl_i,
    .core_tl_o,
    .host_tl_i,
    .host_tl_o,
    .otp_macro_i,
    .otp_macro_o,
    .otp_key_o,
    .otp_key_i,
    .rma_req_i,
    .rma_seed_i,
    .rma_ack_o,
    .keymgr_creator_seed_o,
    .keymgr_owner_seed_o,
    .pwrmgr_o,
    .intr_corr1_err_o,
    .intr_corr2_err_o,
    .intr_wr_empty_o,
    .intr_wr_lvl_o,
    .intr_rd_full_o,
    .intr_rd_lvl_o,
    .intr_op_done_o,
    .alert_rx_i,
    .alert_tx_o,
    .rram_macro_o,
    .rram_macro_i
  );

  // Track which emulated info regions are enabled
  emul_info_tracker u_emul_info_tracker (
    .emul_info_regwen_i           (dut.reg2hw.emul_info_regwen),
    .emul_info_region_i           (dut.reg2hw.emul_info_region),
    .emul_info_subregion_regwen_i (dut.reg2hw.emul_info_subregion_regwen),
    .emul_info_subregion_i        (dut.reg2hw.emul_info_subregion)
  );

  // An undriven variable that decides to take a snapshot. This will only have any effect if
  // have_taken_snapshot_q is false. Track whether it has fired since the last reset.
  logic fpv_take_snapshot, have_taken_snapshot_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      have_taken_snapshot_q <= 1'b0;
    end else begin
      if (fpv_take_snapshot) have_taken_snapshot_q <= 1'b1;
    end
  end

  // A pulse that is true for a cycle the first time that fpv_take_snapshot is true after a reset
  logic fpv_snapshot;
  assign fpv_snapshot = fpv_take_snapshot & ~have_taken_snapshot_q;

  // A snapshotted A-channel transaction through host_tl_i / host_tl_o
  logic    have_host_tl_req_snapshot;
  tl_h2d_t host_tl_req_snapshot;

  // If host_tl_snapshot_rsp_now is true if have_host_tl_req_snapshot is true and it is currently
  // getting a D channel response.
  logic host_tl_snapshot_rsp_now;
  assign host_tl_snapshot_rsp_now = have_host_tl_req_snapshot &&
                                    host_tl_o.d_valid && host_tl_i.d_ready &&
                                    host_tl_o.d_source == host_tl_req_snapshot.a_source;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      have_host_tl_req_snapshot <= 1'b0;
      host_tl_req_snapshot      <= '0;
    end else begin
      if (!have_host_tl_req_snapshot) begin
        // If fpv_snapshot is true and there's an A channel transaction happening, take its
        // snapshot.
        if (fpv_snapshot && host_tl_i.a_valid && host_tl_o.a_ready) begin
          have_host_tl_req_snapshot <= 1'b1;
          host_tl_req_snapshot      <= host_tl_i;
        end
      end else begin
        // If have_host_tl_req_snapshot is true then we should clear it again when the request gets
        // a response.
        if (host_tl_snapshot_rsp_now) have_host_tl_req_snapshot <= 1'b0;
      end
    end
  end

  // True if request in host_tl_req_snapshot addresses a word that is in one of the emulated info
  // regions. (Note that this is only meaningful if have_host_tl_req_snapshot is true)
  logic host_tl_req_snapshot_in_info_region;

  always_comb begin
    host_tl_req_snapshot_in_info_region = 1'b0;
    for (int unsigned i = 0; i < NumEmulInfoRegions; i++) begin
      logic [TL_AW-1:0] region_start, region_end;

      region_start = dut.reg2hw.emul_info_region[i].base;
      region_end = (region_start + ((dut.reg2hw.emul_info_region[i].size + 1) * BytesPerPage));

      if (region_start <= host_tl_req_snapshot.a_address &&
          host_tl_req_snapshot.a_address <= region_end) begin
        host_tl_req_snapshot_in_info_region = 1'b1;
      end
    end
  end

  // This file is generated by psgen in the build directory. We expect the Yosys script
  // (build_all.ys) to pass a -I flag that lets us see the built file.
  `include "psgen-yosys.svh"

endmodule
