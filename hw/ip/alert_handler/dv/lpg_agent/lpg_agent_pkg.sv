// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package lpg_agent_pkg;
  import uvm_pkg::*;

  import prim_mubi_pkg::mubi4_t;
  import dv_base_agent_pkg::dv_base_agent;
  import dv_base_agent_pkg::dv_base_agent_cfg;
  import dv_base_agent_pkg::dv_base_monitor;
  import dv_base_agent_pkg::dv_base_sequencer;
  import dv_base_agent_pkg::dv_base_driver;
  import status_item_pkg::status_item;

  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // The maximum number of LPGs that lpg_if will support (this needs to be a parameter that is
  // jointly visible to the interface and the components that consume it)
  parameter int unsigned MaxNumLpgs = 128;

  `include "lpg_agent_cfg.svh"
  `include "lpg_seq_item.svh"
  `include "lpg_driver.svh"
  typedef dv_base_sequencer #(lpg_seq_item, lpg_agent_cfg, status_item) lpg_sequencer;
  `include "lpg_monitor.svh"
  `include "lpg_agent.svh"

  `include "lpg_seq.svh"
  `include "lpg_bool_seq.svh"
endpackage
