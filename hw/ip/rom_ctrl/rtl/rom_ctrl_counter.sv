// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

//
// A counter module that drives the ROM accesses from the checker.
//
// ROM access will start by reading the expected KAT digest (which is at the end of the ROM, with
// addresses RomDepth-ExpDigestCount .. RomDepth-1). We will then jump to address zero and read the
// whole data area, followed by a second digest.
//
// As such, this module counts through three "sections" of data. With the last address of each of
// the sections, it asserts the last_o output. After the third section has been read, it will assert
// done_o.
//
// This module doesn't need state hardening: an attacker that glitches its behaviour can stall the
// chip or read ROM data in the wrong order. Assuming we've picked a key for the ROM that ensures
// all words have different values, exploiting a glitch in this module to hide a ROM modification
// would still need a pre-image attack on SHA-3.
//
// The last_o and done_o signals are as described above, and report the ends of the sections that
// the counter is reading.
//
// The read_addr_o signal gives the address where ROM should be read.
//
// The data_addr_o signal holds the address of the last word that was requested from ROM. Since ROM
// responds in a single cycle, this will be the address that corresponds to the data that is
// currently being presented to KMAC (through the chk_rdata_o port of the mux), or is currently
// being written to a register.
//
// Finally, the data_rdy_i port is a ready response for the data that is being presented by the ROM.
// This allows the counter to tell whether the last ROM word it read has been consumed, which means
// the counter can step forwards to the next word.

`include "prim_assert.sv"

module rom_ctrl_counter
  import prim_util_pkg::vbits;
#(
  parameter int unsigned RomDepth = 16,
  parameter int unsigned DataCount = 14,
  parameter int unsigned ExpDigestCount = 2
) (
  input                        clk_i,
  input                        rst_ni,

  output                       last_o,
  output                       done_o,

  output [vbits(RomDepth)-1:0] read_addr_o,

  output [vbits(RomDepth)-1:0] data_addr_o,

  input                        data_rdy_i
);

  // The ROM is expected to have two expected digests at the top (each with ExpDigestCount words)
  // and data at the bottom (with DataCount words). These should all fit in RomDepth words.
  `ASSERT_INIT(EndsFit_A, 2 * ExpDigestCount + DataCount <= RomDepth)

  // There should be at least one word in an expected digest
  `ASSERT_INIT(TopCountValid_A, 1 <= ExpDigestCount)

  // There should be at least two words of data
  `ASSERT_INIT(DataCountValid_A, 2 <= DataCount)

  localparam int AW = vbits(RomDepth);

  // The highest address in the ROM (which will hold the last word of the KAT expected digest)
  localparam bit [AW-1:0] TopAddr              = AW'(RomDepth - 1);

  // The address of the KAT expected digest
  localparam bit [AW-1:0] KatExpDigestAddr     = AW'(RomDepth - ExpDigestCount);

  // The address of the data section's expected digest
  localparam bit [AW-1:0] TopDataExpDigestAddr = AW'(DataCount + ExpDigestCount - 1);

  // The address of the data section's expected digest
  localparam bit [AW-1:0] DataExpDigestAddr    = AW'(DataCount);

  // The address of the last data word in the ROM
  localparam bit [AW-1:0] TopDataAddr          = AW'(DataCount - 1);

  // The address of the penultimate data word in the ROM
  localparam bit [AW-1:0] PenultimateDataAddr  = AW'(DataCount - 2);

  // The req_q signal means that at least one request has been sent to ROM. (This gets set on the
  // first clock edge after reset ends). The vld_q signal is delayed by one more cycle and says ROM
  // has responded to a request and the data is available.
  logic          req_q, vld_q;

  // addr_q is the current address in the counter. It starts at KatExpDigestAddr, runs up to
  // TopAddr, then wraps to zero (the start of ROM) and counts up to DataCount + ExpDigestCount - 1
  // (the end of expected data digest).
  //
  // section_top_addr is the address of the last word in the current section
  logic [AW-1:0] addr_q, addr_d, section_top_addr;

  // done_d is true if the word being read on this cycle is the last word that needs reading. done_q
  // is a flag to say that the counter has now requested a read of everything it needs to read.
  // Because the last thing that gets read is passed to a register, there is no possibility of
  // back-pressure, so done_q can be computed without looking at the pause signal.
  logic          done_q, done_d;

  // last_d means that the word in addr_d is the last word in a section (the top of the KAT expected
  // digest, data, or the data expected digest). last_q means that the word currently coming back
  // from ROM is the last word of a section.
  logic          last_q, last_d;

  // If this signal is high, it means that the word that has just come back has not yet been
  // accepted by its intended recipient (either KMAC or the surrounding FSM). If so, pause the
  // counter and send the same address to ROM again.
  logic          pause;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_q <= 1'b0;
      vld_q <= 1'b0;
    end else begin
      // The first ROM request goes out immediately after reset. Once we reach the top of ROM, we
      // signal done_o, after which the request signal is unused. We could clear it again when we
      // are done, but there's no need: the mux will switch away from us anyway.
      req_q <= 1'b1;

      // ROM data is valid from one cycle after the request goes out.
      vld_q <= req_q;
    end
  end

  // Compute the top of the section containing addr_q
  always_comb begin
    if (addr_q <= DataCount - 1) begin
      section_top_addr = DataCount - 1;
    end else if (addr_q <= DataCount + ExpDigestCount - 1) begin
      section_top_addr = DataCount + ExpDigestCount - 1;
    end else begin
      section_top_addr = TopAddr;
    end
  end

  // The "next address" is usually addr_q + 1, but is zero (wrapping around) when addr_q is
  // TopAddr (RomDepth-1).
  assign addr_d = (addr_q == TopAddr) ? 0 : (addr_q + AW'(1));

  // Is the word that has just been read at the top of the expected digest for ROM data?
  assign done_d = (addr_q == TopDataExpDigestAddr);

  // Is the word that we are requesting to read at the top of its section?
  assign last_d = (addr_d == section_top_addr);

  // If the data consumer is not ready to consume the data it is getting on this cycle then we
  // should assert the pause signal.
  //
  // This pauses the counter increment. It also ensures we request the same word again this cycle
  // (see the calculation of read_addr_o), so that word will be available for the consumer next
  // cycle.
  assign pause = ~(data_rdy_i & vld_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // The first thing to read is the expected KAT digest. This is the last ExpDigestCount words
      // of ROM.
      addr_q <= RomDepth - ExpDigestCount;
      last_q <= 1'b0;
      done_q <= 1'b0;
    end else if (!pause) begin
      last_q <= last_d;
      done_q <= done_d;

      if (!done_d) begin
        addr_q <= addr_d;
      end
    end
  end

  assign last_o             = last_q;
  assign done_o             = done_q;
  assign read_addr_o        = pause ? addr_q : addr_d;
  assign data_addr_o        = addr_q;

endmodule
