// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class rom_ctrl_smoke_vseq extends rom_ctrl_base_vseq;
  `uvm_object_utils(rom_ctrl_smoke_vseq)

  extern function new(string name="");
  extern task pre_start();
  extern task body();

endclass : rom_ctrl_smoke_vseq

function rom_ctrl_smoke_vseq::new(string name="");
  super.new(name);
endfunction

task rom_ctrl_smoke_vseq::pre_start();
  bit send_expected = $urandom_range(0, 1);

  // Queue up a pair of digests in the KMAC app agent, which will match those expected in the ROM
  // if send_expected is true.
  configure_kmac_digests(send_expected);

  super.pre_start();
endtask

task rom_ctrl_smoke_vseq::body();
  // Queue up some memory operations. These will block until the rom check completes.
  do_rand_ops($urandom_range(20, 50));

  // Read all the digest and exp_digest registers, checking they match the values we expect.
  read_digest_regs();
endtask : body
