// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Assertions for tlul_lc_gate.
// Intended to be used with a formal tool.

`include "prim_assert.sv"

module tlul_adapter_reg_assert_fpv #(
  parameter  bit CmdIntgCheck      = 0,  // 1: Enable command integrity check
  parameter  bit EnableRspIntgGen  = 0,  // 1: Generate response integrity
  parameter  bit EnableDataIntgGen = 0,  // 1: Generate response data integrity
  parameter  int RegAw             = 8,  // Width of register address
  parameter  int RegDw             = 32, // Shall be matched with TL_DW
  parameter  int AccessLatency     = 0,  // 0: same cycle, 1: next cycle
  localparam int RegBw             = RegDw/8
) (
  input logic              clk_i,
  input logic              rst_ni
);

  import prim_secded_pkg::prim_secded_inv_64_57_enc;
  import prim_secded_pkg::prim_secded_inv_39_32_enc;
  import prim_secded_pkg::prim_secded_inv_64_57_dec;
  import prim_secded_pkg::prim_secded_inv_39_32_dec;

  // The number of bits needed to address bytes within a data word
  localparam int SubAW = $clog2(RegDw/8);

  default clocking @(posedge clk_i); endclocking
  default disable iff !rst_ni;

  // This sequence sees the re_o signal high (which means that we've just decoded a read request on
  // the TL A channel).
  sequence read_txn0_S;
    dut.re_o;
  endsequence

  // This sequence sees a read request being passed out through re_o and waits a cycle for the
  // response to come back and be registered in rdata_q.
  //
  // Then we wait an arbitrary number of cycles where the TL D channel is not ready until we finally
  // see the data being accepted.
  sequence read_txn_S;
    read_txn0_S               ##1
    (!dut.tl_i.d_ready)[*0:$] ##1
    dut.tl_i.d_ready;
  endsequence

  // This sequence sees the we_o signal high (which means that we've just decoded a write request on
  // the TL A channel) and there is the write mask and data on be_o and wdata_o.
  sequence write_txn_S;
    dut.we_o;
  endsequence

  // Initial cover properties    ///////////////////////////////////////////////////////////////////

  // We want to see register read and write requests (which will come about from a TLUL A-channel
  // message)
  ReadReq_C:  cover property (dut.re_o);
  WriteReq_C: cover property (dut.we_o);

  // We want to see a register read request on the TL A channel arrive and for the rdata response to
  // be sent back on the TL D channel.
  ReadTxn_C: cover property (read_txn_S);

  // We want to see a register write request pass wdata from the TL A channel to wmask_o / wdata_o
  WriteTxn_C: cover property (write_txn_S);

  // Assuming that RegAw is large enough to have more than one register, we want to see a request
  // with a nonzero address.
  if (RegAw > 2) begin : gen_multiple_regs
    NonzeroAddr_C: cover property ((dut.re_o | dut.we_o) && |dut.addr_o);
  end

  // If integrity checking is enabled (with CmdIntgCheck), we want to see an integrity error being
  // reported.
  if (CmdIntgCheck) begin : gen_intg_check
    IntgError_C: cover property (dut.intg_error_o);
  end

  // Recognising command integrity errors //////////////////////////////////////////////////////////

  // If command integrity checks are enabled, we want to make sure that the integrity checking works
  // properly. The feature means that a message will have its command integrity checked. If it
  // doesn't match, the message will have an integrity error response and, what's more, that error
  // will be latched until reset.
  //
  // We cheat slightly in this file and check the behaviour in two stages. This logic checks that we
  // correctly model the internal intg_error signal.
  logic fpv_cmd_intg_err;

  if (CmdIntgCheck) begin
    tlul_pkg::tl_h2d_cmd_intg_t             cmd_bits;
    logic [63:0]                            encoded_cmd;
    prim_secded_pkg::secded_64_57_t         decoded_cmd;
    prim_secded_pkg::secded_hamming_39_32_t decoded_data;

    // Checking command integrity
    assign cmd_bits = tlul_pkg::extract_h2d_cmd_intg(dut.tl_i);
    assign encoded_cmd = {dut.tl_i.a_user.cmd_intg, tlul_pkg::H2DCmdMaxWidth'(cmd_bits)};
    assign decoded_cmd = prim_secded_inv_64_57_dec(encoded_cmd);

    // Checking data integrity
    assign decoded_data = prim_secded_inv_39_32_dec({dut.tl_i.a_user.data_intg,
                                                     tlul_pkg::DataMaxWidth'(dut.tl_i.a_data)});

    assign fpv_cmd_intg_err = dut.tl_i.a_valid && (decoded_cmd.err | decoded_data.err);
  end else begin
    assign fpv_cmd_intg_err = 1'b0;
  end

  IntgError_A: assert property (dut.intg_error == fpv_cmd_intg_err);
  IntgErrorPort_A: assert property (dut.intg_error |=> dut.intg_error_o);
  IntgErrorPortStable_A: assert property (##1 !$fell(dut.intg_error_o));

  // Translation from A channel message to read request ////////////////////////////////////////////

  // The read or write address requested through the TL A channel gets propagated correctly to the
  // addr_o port.
  AChanAddr_A: assert property (dut.re_o || dut.we_o |->
                                dut.addr_o == {dut.tl_i.a_address[RegAw-1:2], 2'b0});

  // A message is considered reasonable as long as the following properties are all true:
  //
  //  - The a_size field is a known value (0, 1 or 2, giving operations on 1, 2 or 4 bytes).
  //
  //  - The a_address field is aligned as implied by a_size. (If a_size is N, then the operation
  //    addresses 2^N bytes and should be naturally aligned, so the bottom 2^N bits of the address
  //    should be zero).
  //
  //  - The a_mask field is only true for active lanes. The sub-word part of the address gives the
  //    index of the bottom active lane. If a_size is N then there are 2^N active lanes, starting at
  //    that index.
  //
  //  - Either en_ifetch_i is true or the instr_type field is not MuBi4True.
  //
  //  - There is no command integrity error (which would be reflected in the intg_error_o on the
  //    next cycle)

  logic fpv_known_size;
  assign fpv_known_size = dut.tl_i.a_size <= 2;

  // The number of lanes addressed by an operation with the given a_size
  int unsigned lane_count;
  assign lane_count = 1 << dut.tl_i.a_size;

  // The mask of of bits that should be zero at the bottom of the address for it to be correctly
  // aligned. For example, if there are 4 lanes, then the address should be a multiple of 4 and the
  // bottom two bits of the address should be zero.
  logic [RegAw-1:0] bottom_addr_bit_mask;
  assign bottom_addr_bit_mask = RegAw'(lane_count - 1);

  // True if a_address is correctly aligned for a_size
  logic fpv_address_aligned;
  assign fpv_address_aligned = ~|(dut.tl_i.a_address & bottom_addr_bit_mask);

  // The address, modulo the width of a data word.
  logic [SubAW-1:0] subword_address;
  assign subword_address = dut.tl_i.a_address[SubAW-1:0];

  // A mask that gives all the active lanes (implied by a_size and a_address)
  bit [RegBw-1:0] active_lane_mask;
  assign active_lane_mask = RegBw'((1 << lane_count) - 1) << subword_address;

  // True if a bit in the mask is false for every inactive lane.
  logic mask_0_in_inactive_lanes;
  assign mask_0_in_inactive_lanes = ~|(dut.tl_i.a_mask & ~active_lane_mask);

  // True if the instr_type is a valid mubi
  logic is_valid_instr_type;
  assign is_valid_instr_type = dut.tl_i.a_user.instr_type inside {prim_mubi_pkg::MuBi4True,
                                                                  prim_mubi_pkg::MuBi4False};

  // True if fetches are currently allowed
  logic fetches_allowed;
  assign fetches_allowed = dut.en_ifetch_i == prim_mubi_pkg::MuBi4True;

  // True if the current operation is allowed with this instr_type. The instr_type must be a valid
  // mubi value and if it's true then fetches must be allowed and the opcode must be Get.
  logic valid_with_instr_type;
  assign valid_with_instr_type = is_valid_instr_type &&
                                 (dut.tl_i.a_user.instr_type == prim_mubi_pkg::MuBi4True ->
                                  dut.tl_i.a_opcode == tlul_pkg::Get && fetches_allowed);

  // True if the data fields on the A channel are seem reasonable for an operation. Specific
  // operations (Get, PutPartialData and PutFullData) will need extra checks.
  logic fpv_reasonable_a_msg_fields;
  assign fpv_reasonable_a_msg_fields = fpv_known_size && fpv_address_aligned &&
                                       mask_0_in_inactive_lanes && valid_with_instr_type &&
                                       !fpv_cmd_intg_err;

  // True if we can see a valid A-channel message with a Get operation.
  logic fpv_valid_get_message;
  assign fpv_valid_get_message = dut.tl_i.a_opcode == tlul_pkg::Get &&
                                 fpv_reasonable_a_msg_fields;

  // True if we are accepting an A-channel message
  logic fpv_accepted_a_chan_message;
  assign fpv_accepted_a_chan_message = dut.tl_i.a_valid && dut.tl_o.a_ready;

  // True if the current A-channel message has a known opcode (Get, PutFullData or PutPartialData)
  logic fpv_known_opcode;
  assign fpv_known_opcode = dut.tl_i.a_opcode inside {tlul_pkg::Get,
                                                      tlul_pkg::PutFullData,
                                                      tlul_pkg::PutPartialData};

  // If a Get message arrives on the A channel and satisifies the properties for a valid A-channel
  // message, then the re_o signal should go high that cycle.
  //
  // We also want to check that we don't see any spurious requests through re_o, so use iff. Note
  // that ReadReq_C gives a cover for this happening.
  GetToRe_A: assert property (dut.re_o <->
                              (fpv_accepted_a_chan_message &&
                               fpv_valid_get_message));

  // The adapter doesn't allow "overlapped requests", so an accepted message on the A channel means
  // that a_ready will not be high again until the response has been accepted on the D channel.
  NoOverlaps_A: assert property (fpv_accepted_a_chan_message |=>
                                 (!dut.tl_o.a_ready until_with
                                  dut.tl_o.d_valid && dut.tl_i.d_ready));

  // Translation from A channel message to write request ///////////////////////////////////////////

  // The same checks as fpv_reasonable_a_msg_fields, but also requiring that the address is
  // word-aligned.
  logic fpv_reasonable_write_msg_fields;
  assign fpv_reasonable_write_msg_fields = fpv_reasonable_a_msg_fields &&
                                           !|dut.tl_i.a_address[1:0];

  // Checks that the fields are reasonable for a PutFullData message
  logic fpv_valid_pfd_message;
  assign fpv_valid_pfd_message = dut.tl_i.a_opcode == tlul_pkg::PutFullData &&
                                 !|(active_lane_mask & ~dut.tl_i.a_mask) &&
                                 fpv_reasonable_write_msg_fields;

  // Checks that the fields are reasonable for a PutPartialData message (this is weaker than the
  // PutFullData version, because PutPartialData allows an arbitrary mask)
  logic fpv_valid_ppd_message;
  assign fpv_valid_ppd_message = dut.tl_i.a_opcode == tlul_pkg::PutPartialData &&
                                 fpv_reasonable_write_msg_fields;

  // If a reasonable PutFullData or PutPartialData message arrives on the A channel, the we_o signal
  // should go high that cycle. This is the only reason for we_o to be high.
  //
  // Note that WriteReq_C gives a cover for some write request.
  PutToWe_A: assert property (dut.we_o <->
                              (fpv_accepted_a_chan_message &&
                               (fpv_valid_pfd_message || fpv_valid_ppd_message)));

  // Explicit cover from the PutFullData and PutPartialData write requests triggering we_o (not
  // implied by WriteReq_C because there are two possible put messages).
  WriteFromPfd_C: cover property (dut.we_o && dut.tl_i.a_opcode == tlul_pkg::PutFullData);
  WriteFromPpd_C: cover property (dut.we_o && dut.tl_i.a_opcode == tlul_pkg::PutPartialData);

  // If we_o is high, the value of wdata_o should match the A_DATA field of the A-channel message
  // that triggers it. This check could theoretically be qualified by be_o, but the stronger
  // property is true (and easier to state).
  WDataFromWrite_A: assert property (dut.we_o |->
                                     dut.wdata_o == dut.tl_i.a_data);

  // If we_o is high, the be_o signal should match the A_MASK field of the A-channel message that
  // triggers it.
  ByteEnableFromWrite_A: assert property (dut.we_o |->
                                          dut.be_o == dut.tl_i.a_mask);

  // Responses on D channel ////////////////////////////////////////////////////////////////////////

  // The adapter never drops a message on the D channel, so d_valid will not drop unless d_ready is
  // high.
  DValidStable_A: assert property (##1 $fell(dut.tl_o.d_valid) -> $past(dut.tl_i.d_ready));

  // Similarly, d_data should be constant if d_valid is high unless d_ready has been high to receive
  // the message.
  DDataStable_A: assert property (dut.tl_o.d_valid |=>
                                  $stable(dut.tl_o.d_valid) || $past(dut.tl_i.d_ready));

  // If the adapter has seen any request on the A channel, it will respond by tl_o.d_valid going
  // high in exactly one cycle (regardless of AccessLatency).
  DValidWait_A: assert property (fpv_accepted_a_chan_message |=> $rose(dut.tl_o.d_valid));

  // If the adapter sees a request with a bogus opcode, the response on the following cycle with
  // have D_ERROR set.
  DNonsenseGetsError_A: assert property (fpv_accepted_a_chan_message && !fpv_known_opcode |=>
                                         dut.tl_o.d_error);

  // An error response (with D_ERROR true) will always be accompanied by '1 for D_DATA
  DDataOnesIfError_A: assert property (dut.tl_o.d_error |-> &dut.tl_o.d_data);

  logic [RegDw-1:0] fpv_sampled_rdata;
  SampleStable_M: assume property (##1 $stable(fpv_sampled_rdata));

  // If re_o is high (so the adapter has just decoded a Get message on the A channel), it will read
  // and sample rdata_i on this cycle or the next one (depending on AccessLatency). This value will
  // be returned as D_DATA in the response unless there has been an error, in which case D_ERROR
  // will be true.
  RDataToDData_A: assert property (dut.re_o ##AccessLatency dut.rdata_i == fpv_sampled_rdata |->
                                   ##(1 - AccessLatency)
                                   (dut.tl_o.d_data == fpv_sampled_rdata) || dut.tl_o.d_error);

  // Properties about the register interface ///////////////////////////////////////////////////////

  // The adapter never requests a read and a write at the same time
  ReadOrWrite_A: assert property (!(dut.re_o && dut.we_o));

  // If the register interface claims to be busy, the adapter will not accept an A-channel message.
  NoMsgWhenBusy_A: assert property (dut.busy_i |-> !fpv_accepted_a_chan_message);

  // Error responses from the register interface (through error_i) should be reflected in the
  // D-channel message.
  ErrorPropagation_A: assert property ((dut.re_o || dut.we_o) ##AccessLatency dut.error_i |->
                                       ##(1 - AccessLatency)
                                       dut.tl_o.d_error);

  // Because the adapter doesn't allow the request and response to overlap, it's not actually
  // possible for re_o or we_o to be high for multiple consecutive cycles.
  AccessesPulse_A: assert property (not (dut.re_o || dut.we_o)[*2]);

  // Properties about integrity generation and checking ////////////////////////////////////////////

  // If response integrity generation is not enabled, we expect tl_o.d_user.rsp_intg to be exactly
  // zero. If it is enabled, we expect it to match the top D2HRspIntgWidth bits of a SECDED
  // calculation on some response bits.
  if (!EnableRspIntgGen) begin : gen_no_rsp_intg_gen
    RspIntgPassThrough_A: assert property (!|dut.tl_o.d_user.rsp_intg);
  end else begin : gen_rsp_intg_gen
    tlul_pkg::tl_d2h_rsp_intg_t fpv_d2h_rsp;
    assign fpv_d2h_rsp = tlul_pkg::extract_d2h_rsp_intg(dut.tl_o);

    logic [tlul_pkg::D2HRspIntgWidth-1:0] fpv_rsp_intg;
    logic [tlul_pkg::D2HRspMaxWidth-1:0]  fpv_unused_lower_bits;

    assign {fpv_rsp_intg, fpv_unused_lower_bits} = prim_secded_inv_64_57_enc(57'(fpv_d2h_rsp));

    RspIntgGen_A: assert property (dut.tl_o.d_user.rsp_intg == fpv_rsp_intg);
  end

  // If data integrity generation is not enabled, we expect tl_o.d_user.data_intg to be exactly
  // zero. If it is enabled, we expect it to match the top DataIntgWidth bits of a SECDED
  // calculation on the data itself.
  if (!EnableDataIntgGen) begin : gen_no_data_intg_gen
    DataIntgPassThrough_A: assert property (!|dut.tl_o.d_user.data_intg);
  end else begin : gen_data_intg_gen
    logic [tlul_pkg::DataIntgWidth-1:0] fpv_data_intg;
    logic [tlul_pkg::DataMaxWidth-1:0]  fpv_unused_lower_bits;

    assign {fpv_data_intg, fpv_unused_lower_bits} = prim_secded_inv_39_32_enc(32'(dut.tl_o.d_data));

    DataIntgGen_A: assert property (dut.tl_o.d_user.data_intg == fpv_data_intg);
  end

endmodule
