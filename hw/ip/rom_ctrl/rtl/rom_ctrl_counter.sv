// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

//
// A counter module that drives the ROM accesses from the checker.
//
// The ROM accesses will start by reading the whole data area (from word 0 to word DataCount-1), and
// the module will then read the expected digest (from word DataCount to word
// DataCount+ExpDigestCount-1).
//
// This module doesn't need state hardening: an attacker that glitches its behaviour can stall the
// chip or read ROM data in the wrong order. Assuming we've picked a key for the ROM that ensures
// all words have different values, exploiting a glitch in this module to hide a ROM modification
// would still need a pre-image attack on SHA-3.
//
// RomDepth is the number of words in the ROM. DataCount is the number of those words (starting at
// the bottom of the address space) that are data to be hashed. ExpDigestCount is the size of a
// single (expected) digest in the same unit. Words in the expected digests at the top of ROM are
// not data that will be included in the hash computation.
//
// The counter works through the ROM, starting at address zero. For each address, it will supply
// that address in read_addr_o and will set read_req_o. This combination makes a request to the ROM.
//
// The data_addr_o signal holds the address of the last word that was requested from ROM. Since ROM
// responds in a single cycle, this will be the address that corresponds to the data that is
// currently being presented to KMAC (through the chk_rdata_o port of the mux).
//
// The data_last_nontop_o signal is true if the most recent word read from ROM was the final word in
// the data that should be sent to KMAC.
//
// Finally, the data_rdy_i port is the ready response from KMAC. Knowing this means that the counter
// can tell whether the last ROM word it read is being passed to KMAC, which means the counter can
// step forwards to the next word.

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

  output                       done_o,

  output [vbits(RomDepth)-1:0] read_addr_o,
  output                       read_req_o,

  output [vbits(RomDepth)-1:0] data_addr_o,

  input                        data_rdy_i,
  output                       data_last_nontop_o
);

  // The ROM is expected to have expected digests at the top (with a multiple of ExpDigestCount
  // words) and data at the bottom (with DataCount words). These should all fit in RomDepth words.
  `ASSERT_INIT(EndsFit_A, ExpDigestCount + DataCount <= RomDepth)

  // There should be at least one word of expected digest
  `ASSERT_INIT(TopCountValid_A, 1 <= ExpDigestCount)

  // There should be at least two words of data
  `ASSERT_INIT(DataCountValid_A, 2 <= DataCount)

  localparam int AW = vbits(RomDepth);

  // The highest address in the ROM (which will hold the last word of the last expected digest)
  localparam int unsigned TopAddrInt = RomDepth - 1;

  // The address of the penultimate data word in the ROM
  localparam int unsigned PenultimateDataAddrInt = DataCount - 2;

  // The address of the first word in the first expected digest
  localparam int unsigned ExpDigestAddrInt = DataCount;

  localparam bit [AW-1:0] TopAddr             = TopAddrInt[0 +: AW];
  localparam bit [AW-1:0] PenultimateDataAddr = PenultimateDataAddrInt[0 +: AW];
  localparam bit [AW-1:0] ExpDigestAddr       = ExpDigestAddrInt[0 +: AW];

  logic          go;
  logic          req_q, vld_q;
  logic [AW-1:0] addr_q, addr_d, succ_addr;
  logic          done_q, done_d;
  logic          last_nontop_q, last_nontop_d;

  assign done_d = addr_q == TopAddr;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      done_q <= 1'b0;
    end else begin
      done_q <= done_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_q        <= '0;
      last_nontop_q <= 1'b0;
    end else if (go) begin
      addr_q        <= addr_d;
      last_nontop_q <= last_nontop_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_q <= 1'b0;
      vld_q <= 1'b0;
    end else begin
      // The first ROM request goes out immediately after reset (once we reach the top of ROM, we
      // signal done_o, after which the request signal is unused). We could clear it again when we
      // are done, but there's no need: the mux will switch away from us anyway.
      req_q <= 1'b1;

      // ROM data is valid from one cycle after the request goes out.
      vld_q <= req_q;
    end
  end

  assign go        = data_rdy_i & vld_q & ~done_d;
  assign succ_addr = addr_q + {{AW-1{1'b0}}, 1'b1};
  assign addr_d    = last_nontop_q ? ExpDigestAddr : succ_addr;

  assign last_nontop_d = addr_q == PenultimateDataAddr;

  assign done_o             = done_q;
  assign read_addr_o        = go ? addr_d : addr_q;
  assign read_req_o         = req_q;
  assign data_addr_o        = addr_q;
  assign data_last_nontop_o = last_nontop_q;

endmodule
