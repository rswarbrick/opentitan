// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

//
// The ROM checker FSM module
//
// This is an FSM that controls the interaction with KMAC to calculate a digest from the ROM
// contents.
//
// The digest_i and exp_digest_i ports are wide signals for digests that are computed (from KMAC) or
// expected (read from the top of ROM). Both digests are stored in CSR registers. Note that these
// are used for the KAT as well as for the digest of the data section.
//
// The digest_o port gives a computed digest from KMAC and its value is valid if digest_vld_o is
// true. This value will be written into the DIGEST register.
//
// Similarly, the exp_digest_o port gives a 32-bit word of the expected digest with index
// exp_digest_idx_o. The value is valid if exp_digest_vld_o is true.
//
// The pwrmgr_data_o port gives the data that should be sent to pwrmgr. This consists of a "done"
// field (showing that the digest has been computed and checked against the expected value) and a
// "good" field (which shows that the two digests matched).
//
// The keymgr_data_o port gives the data that should be sent to keymgr. This is the computed hash
// (from digest_i) with a valid signal to show the data field is valid.
//
// The kmac_rom_* ports are sending ROM data to KMAC. The kmac_rom_rdy_i / kmac_rom_vld_o signals
// give a ready/valid interface to control the handshake that passes ROM data to KMAC to be hashed.
// The kmac_rom_last_o signal is high when the word being offered is the last word of the input.
//
// Normally, the rom_ctrl module passes the ROM data from rom_ctrl_mux directly to kmac. For the
// KAT, it should send a different (fixed) message. The send_kat_to_kmac_o signal tells rom_ctrl to
// override the rom_ctrl_mux data with this fixed message.
//
// The kmac_* input ports are for the digest coming back from KMAC. The kmac_digest_i signal is the
// computed digest, which is valid if kmac_done_i is true, unless kmac_err_i is true, in which case
// the KMAC block encountered an error when computing the digest.
//
// Immediately after reset, the FSM is in control of ROM requests. The rom_select_bus_o signal
// becomes MuBi4True when we have read the entire contents and the mux should instead give access to
// the bus. Until that happens, the FSM makes requests by sending an address in rom_addr_o.
//
// Raw words from ROM appear in rom_data_i (to be incorporated into the expected digest).
//
// The alert_o signal goes high if an error has been seen, which should cause a fatal alert.

`include "prim_assert.sv"

module rom_ctrl_fsm
  import prim_mubi_pkg::mubi4_t;
  import prim_util_pkg::vbits;
  import rom_ctrl_pkg::*;
#(
  // The depth of the physical ROM in words (including KAT bits and expected digest)
  parameter int RomDepth = 16,
  // The size of the data contents (the words to be hashed, which start at the bottom of ROM)
  parameter int DataCount = 8,
  // The size of the expected digest stored at the top of ROM
  parameter int ExpDigestCount = 8
) (
  input logic                              clk_i,
  input logic                              rst_ni,

  // CSR inputs for DIGEST and EXP_DIGEST. To make the indexing look nicer, these are ordered so
  // that DIGEST_0 is the bottom 32 bits (they get reversed while we're shuffling around the wires
  // in rom_ctrl).
  input logic [ExpDigestCount*32-1:0]      digest_i,
  input logic [ExpDigestCount*32-1:0]      exp_digest_i,

  // CSR outputs for DIGEST and EXP_DIGEST. Ordered with word 0 as LSB.
  output logic [ExpDigestCount*32-1:0]     digest_o,
  output logic                             digest_vld_o,
  output logic [31:0]                      exp_digest_o,
  output logic                             exp_digest_vld_o,
  output logic [vbits(ExpDigestCount)-1:0] exp_digest_idx_o,

  // To power manager and key manager
  output pwrmgr_data_t                     pwrmgr_data_o,
  output keymgr_data_t                     keymgr_data_o,

  // To KMAC (ROM data)
  input logic                              kmac_rom_rdy_i,
  output logic                             kmac_rom_vld_o,
  output logic                             kmac_rom_last_o,

  // An instruction to send KMAC a fixed, one-packet message
  output logic                             send_kat_to_kmac_o,

  // From KMAC (digest data)
  input logic                              kmac_done_i,
  input logic [ExpDigestCount*32-1:0]      kmac_digest_i,
  input logic                              kmac_err_i,

  // To ROM mux
  output mubi4_t                           rom_select_bus_o,
  output logic [vbits(RomDepth)-1:0]       rom_addr_o,

  // Raw bits from ROM
  input logic [31:0]                       rom_data_i,

  // To alert system
  output logic                             alert_o
);

  import prim_mubi_pkg::mubi4_test_true_loose;
  import prim_mubi_pkg::MuBi4False, prim_mubi_pkg::MuBi4True;

  // The width for word indexes into the ROM
  localparam int AW = vbits(RomDepth);

  // The width for word indexes into a digest
  localparam int DAW = vbits(ExpDigestCount);

  // The word index for the start of the "expected KAT result" in ROM
  localparam bit [AW-1:0] KATStartAddr = AW'(RomDepth - ExpDigestCount);

  // The word index for the start of the "expected digest" in ROM
  localparam bit [AW-1:0] TopStartAddr = AW'(RomDepth - 2 * ExpDigestCount);

  // The counter / address generator
  logic          counter_last;
  logic          counter_done;
  logic [AW-1:0] counter_read_addr;
  logic [AW-1:0] counter_data_addr;
  logic          counter_data_rdy;
  rom_ctrl_counter #(
    .RomDepth (RomDepth),
    .DataCount (DataCount),
    .ExpDigestCount (ExpDigestCount)
  ) u_counter (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .last_o             (counter_last),
    .done_o             (counter_done),
    .read_addr_o        (counter_read_addr),
    .data_addr_o        (counter_data_addr),
    .data_rdy_i         (counter_data_rdy)
  );

  // The compare block (responsible for comparing CSR data and forwarding it to the key manager)
  logic   start_checker;
  logic   checker_done, checker_alert;
  mubi4_t checker_good;
  rom_ctrl_compare #(
    .NumWords  (ExpDigestCount)
  ) u_compare (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .start_i      (start_checker),
    .done_o       (checker_done),
    .good_o       (checker_good),
    .digest_i     (digest_i),
    .exp_digest_i (exp_digest_i),
    .alert_o      (checker_alert)
  );

  // Main FSM
  //
  // There are the following logical states
  //
  //    ReadingKAT:   We're reading the expected digest for the known answer test.
  //    SendingKAT:   We're sending the KAT message to KMAC.
  //    WaitingKAT:   We're waiting for a response from KMAC (for the known answer test result).
  //    CheckingKAT:  We're checking that the KMAC response matched the expected KAT result.
  //    ReadingLow:   We're reading the low part of ROM and passing it to KMAC
  //    ReadingHigh:  We're reading the high part of ROM and waiting for KMAC.
  //    RomAhead:     We've finished reading the high part of ROM, but are still waiting for KMAC.
  //    KmacAhead:    KMAC is done, but we're still reading the high part of ROM.
  //    Checking:     We are comparing DIGEST and EXP_DIGEST and sending data to keymgr.
  //    Done:         Terminal state
  //    Invalid:      Terminal and invalid state (only reachable by a glitch)
  //
  // The FSM is linear, except for the branch where reading the high part of ROM races with getting
  // the result back from KMAC.
  //
  //     digraph fsm {
  //       ReadingKAT -> SendingKAT;
  //       SendingKAT -> WaitingKAT;
  //       WaitingKAT -> CheckingKAT;
  //       CheckingKAT -> ReadingLow;
  //       ReadingLow -> ReadingHigh;
  //       ReadingHigh -> RomAhead;
  //       ReadingHigh -> KmacAhead;
  //       RomAhead -> Checking;
  //       KmacAhead -> Checking;
  //       Checking -> Done;
  //       Done [peripheries=2];
  //     }
  // SEC_CM: FSM.SPARSE
  // SEC_CM: INTERSIG.MUBI

  fsm_state_e state_d, state_q;
  logic       fsm_alert;

  `PRIM_FLOP_SPARSE_FSM(u_state_regs, state_d, state_q, fsm_state_e, ReadingKAT)

  // The main FSM block. This drives the signals:
  //
  //    - state_d
  //    - counter_data_rdy
  //    - fsm_alert
  always_comb begin
    state_d = state_q;

    counter_data_rdy = 1'b0;
    fsm_alert        = 1'b0;

    unique case (state_q)
      ReadingKAT: begin
        // While we are in ReadingKAT, the counter generates reads for each of the words in the
        // expected digest for the KAT. These get fed straight into the registers, so there is no
        // backpressure.
        counter_data_rdy = 1'b1;

        // When the counter_last signal is true, the ROM word that just came back is the last one of
        // the expected digest. Switch to SendingKAT.
        if (counter_last) state_d = SendingKAT;
      end

      SendingKAT: begin
        // While we are in SendingKAT, the send_kat_to_kmac_o signal is asserted (by a continuous
        // assignment), which means that the surrounding block will pass a known message to KMAC.
        // When that message is been accepted by kmac, kmac_rom_rdy_i will be asserted and we can
        // jump to waiting for kmac's response.
        if (kmac_rom_rdy_i) state_d = WaitingKAT;
      end

      WaitingKAT: begin
        // While we are in WaitingKAT, we are waiting for kmac to send a digest response, which will
        // immediately be written into registers. Once that has happened, we should jump to the
        // CheckingKMAC state unless kmac has reported an error, in which case we should jump to the
        // terminal Invalid state.
        if (kmac_done_i) state_d = kmac_err_i ? Invalid : CheckingKAT;
      end

      CheckingKAT: begin
        // If checker_done is true, this is the end of the known answer test. If checker_good is
        // true, we have passed and should move to ReadingLow. If not, this is a terminal error.
        // Jump to the Invalid state.
        //
        // This next state calculation is encoded with mubi4_sel4, so operates on the different bits
        // of the mubi signal without squashing down to a single bit. This ensures that an injected
        // single-bit error in checker_good will give a single bit error in state_d and jump to an
        // invalid state.
        if (checker_done) state_d = fsm_state_e'(mubi4_sel12(checker_good, ReadingLow, Invalid));
      end

      ReadingLow: begin
        // Switch to ReadingHigh when counter_last is true and kmac_rom_rdy_i & kmac_rom_vld_o
        // (implying kmac has accepted the last word of the data section).
        //
        // If counter_last is true then we requested the last non-top word from the ROM on the last
        // cycle and the response will be available now. This gets taken if kmac_rom_rdy_i.
        if (counter_last && kmac_rom_rdy_i) begin
          state_d = ReadingHigh;
        end

        counter_data_rdy = kmac_rom_rdy_i;
      end

      ReadingHigh: begin
        counter_data_rdy = 1;

        unique case ({kmac_done_i, counter_done})
          2'b01: state_d = RomAhead;
          2'b10: state_d = kmac_err_i ? Invalid : KmacAhead;
          2'b11: state_d = kmac_err_i ? Invalid : Checking;
          default: ; // No change
        endcase
      end

      RomAhead: begin
        if (kmac_done_i) state_d = kmac_err_i ? Invalid : Checking;
      end

      KmacAhead: begin
        counter_data_rdy = 1;

        if (counter_done) state_d = Checking;
      end

      Checking: begin
        if (checker_done) state_d = Done;
      end

      Done: begin
        // Final state
      end

      default: begin
        // An invalid state (includes the explicit Invalid state)
        fsm_alert = 1'b1;
        state_d = Invalid;
      end
    endcase

    // Consistency checks for done signals.
    //
    // - checker_done should only ever be high in states CheckingKAT, Checking and Done.
    //
    // - counter_done should only be high after we have finished reading the data section, so are in
    //   a state from ReadingHigh, RomAhead, KmacAhead, Checking and Done.
    //
    // - kmac_done_i should only be high when we are waiting for kmac to send a response, so are in
    //   WaitingKAT, ReadingHigh or RomAhead.
    //
    // If any of these consistency requirements doesn't hold, jump to the Invalid state. This will
    // also raise an alert on the following cycle.
    //
    // SEC_CM: CHECKER.CTRL_FLOW.CONSISTENCY
    if ((checker_done && !(state_q inside {CheckingKAT, Checking, Done})) ||
        (counter_done && !(state_q inside {ReadingHigh, RomAhead, KmacAhead, Checking, Done})) ||
        (kmac_done_i  && !(state_q inside {WaitingKAT, ReadingHigh, RomAhead}))) begin
      state_d = Invalid;
    end

    // Jump to an invalid state if sending out an alert for any other reason
    //
    // SEC_CM: CHECKER.FSM.LOCAL_ESC
    if (alert_o) begin
      state_d = Invalid;
    end
  end

  // Check that the FSM is linear and does not contain any loops
  `ASSERT_FPV_LINEAR_FSM(SecCmCFILinear_A, state_q, fsm_state_e)

  assign send_kat_to_kmac_o = (state_q == SendingKAT);

  // The in_state_done signal is supposed to be true iff we're in FSM state Done. Grabbing just the
  // bottom 4 bits of state_q is equivalent to "mubi4_bool_to_mubi(state_q == Done)" except that it
  // doesn't have a 1-bit signal on the way.
  logic [9:0] state_q_bits;
  logic       unused_state_q_top_bits;
  assign state_q_bits = {state_q};
  assign unused_state_q_top_bits = ^state_q_bits[9:4];

  mubi4_t in_state_done;
  assign in_state_done = mubi4_t'(state_q_bits[3:0]);

  // Route digest signals coming back from KMAC straight to the CSRs
  assign digest_o     = kmac_digest_i;
  assign digest_vld_o = kmac_done_i;

  // Snoop on ROM reads to populate EXP_DIGEST, one word at a time
  logic reading_exp_digest;
  logic [AW-1:0] exp_digest_addr0, rel_addr_wide;
  logic [DAW-1:0] rel_addr;

  assign reading_exp_digest = (state_q inside {ReadingKAT, ReadingHigh, KmacAhead}) & ~counter_done;

  // Compute the current word index, which should be valid if we are reading an expected digest from
  // ROM. This will be used as a write address for storing the expected digest into registers.
  assign exp_digest_addr0 = (state_q == ReadingKAT) ? KATStartAddr : TopStartAddr;
  assign rel_addr_wide    = counter_data_addr - exp_digest_addr0;
  assign rel_addr         = rel_addr_wide[DAW-1:0];

  // The top bits of rel_addr_wide should always be zero if we're reading an expected digest
  // (because DAW bits should be enough to encode the difference between counter_data_addr and
  // exp_digest_addr0)
  //
  // Consider them unused and add an assertion to check that they are indeed zero.
  logic unused_top_rel_addr_wide;
  assign unused_top_rel_addr_wide = |rel_addr_wide[AW-1:DAW];
  `ASSERT(RelAddrWide_A, exp_digest_vld_o |-> !unused_top_rel_addr_wide)

  assign exp_digest_o = rom_data_i;
  assign exp_digest_vld_o = reading_exp_digest;
  assign exp_digest_idx_o = rel_addr;

  // The 'done' signal for pwrmgr is asserted once we get into the Done state. The 'good' signal
  // comes directly from the checker.
  assign pwrmgr_data_o = '{done: in_state_done, good: checker_good};

  // Pass the digest all-at-once to the keymgr. The loose check means that glitches will add
  // spurious edges to the valid signal that can be caught at the other end.
  assign keymgr_data_o = '{data: digest_i, valid: mubi4_test_true_loose(in_state_done)};

  // KMAC rom data interface
  logic kmac_rom_vld_d, kmac_rom_vld_q;
  always_comb begin
    // Hold kmac_rom_vld_q high once it has been asserted, only clearing it for next cycle if
    // kmac_rom_rdy_i shows that kmac is accepting the word we are sending.
    kmac_rom_vld_d = kmac_rom_vld_q;

    if (kmac_rom_rdy_i) kmac_rom_vld_d = 0;

    // Is there a new word to pass to kmac? We pass data for kmac in the SendingKAT and ReadingLow
    // states.
    //
    // In SendingKAT, it's just a single word that we start to provide on the first cycle in the
    // state. As such, we set kmac_rom_vld_d on the last cycle in the ReadingKAT state.
    //
    // There will be a word available in all cycles in ReadingLow after the first, but not one in
    // the first cycle of ReadingHigh. To represent this, we set kmac_rom_vld_d in ReadingLow unless
    // counter_last is true.
    if ((state_q == ReadingKAT && counter_last) ||
        (state_q == ReadingLow && !counter_last)) begin
      kmac_rom_vld_d = 1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      kmac_rom_vld_q <= 0;
    end else begin
      kmac_rom_vld_q <= kmac_rom_vld_d;
    end
  end

  assign kmac_rom_vld_o = kmac_rom_vld_q;
  assign kmac_rom_last_o = (state_q == SendingKAT) | ((state_q == ReadingLow) && counter_last);

  // The "last" flag means when we're sending the last word of a KMAC message. This is either the
  // only word (for the KAT) or it is the last message of the data section of the ROM. As a quick
  // consistency check, this should only happen when the "valid" flag is also high.
  `ASSERT(LastImpliesValid_A, kmac_rom_last_o |-> kmac_rom_vld_o,
          clk_i, !rst_ni || (state_q == Invalid))

  // Start the checker when transitioning into the "Checking" state
  logic in_checking_state_q, in_checking_state_d;
  assign in_checking_state_d = (state_d inside {Checking, CheckingKAT});

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      in_checking_state_q <= 1'b0;
    end else begin
      in_checking_state_q <= in_checking_state_d;
    end
  end

  assign start_checker = in_checking_state_d & ~in_checking_state_q;

  // The counter is supposed to run from zero up to the top of memory and then tell us that it's
  // done with the counter_done signal. We would like to be sure that no-one can fiddle with the
  // counter address once the hash has been computed (if they could subvert the mux as well, this
  // would allow them to generate a useful wrong address for a fetch). Fortunately, doing so would
  // cause the counter_done signal to drop again and we *know* that it should stay high when our FSM
  // is in the Done state.
  //
  // SEC_CM: CHECKER.CTR.CONSISTENCY
  logic unexpected_counter_change;
  assign unexpected_counter_change = mubi4_test_true_loose(in_state_done) & !counter_done;

  // We keep control of the ROM mux from reset until we're done.
  assign rom_select_bus_o = in_state_done;

  assign rom_addr_o = counter_read_addr;

  assign alert_o = fsm_alert | checker_alert | unexpected_counter_change;

  `ASSERT(CounterLastImpliesKmacRomVldO_A,
          state_q == ReadingLow && counter_last -> kmac_rom_vld_o)

endmodule
