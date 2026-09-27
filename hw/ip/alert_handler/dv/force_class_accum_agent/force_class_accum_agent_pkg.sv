// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package force_class_accum_agent_pkg;
  import uvm_pkg::*;

  import dv_base_agent_pkg::dv_base_agent;
  import dv_base_agent_pkg::dv_base_agent_cfg;
  import dv_base_agent_pkg::dv_base_sequencer;
  import dv_base_agent_pkg::dv_base_driver;

  // The maximum number of bits used to represent an accumulation count
  parameter int unsigned MaxAccuCntDw = 32;

  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  `include "force_class_accum_agent_cfg.svh"
  `include "force_class_accum_seq_item.svh"
  `include "force_class_accum_driver.svh"
  typedef dv_base_sequencer #(force_class_accum_seq_item,
                              force_class_accum_agent_cfg) force_class_accum_sequencer;
  `include "force_class_accum_agent.svh"
  `include "force_class_accum_seq.svh"
endpackage
