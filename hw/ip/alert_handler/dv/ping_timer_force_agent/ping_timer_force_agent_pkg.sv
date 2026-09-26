// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package ping_timer_force_agent_pkg;
  import uvm_pkg::*;

  import dv_base_agent_pkg::dv_base_agent;
  import dv_base_agent_pkg::dv_base_agent_cfg;
  import dv_base_agent_pkg::dv_base_sequencer;
  import dv_base_agent_pkg::dv_base_driver;

  // The maximum number of bits used to represent a ping count
  parameter int unsigned MaxPingCntDw = 32;

  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  `include "ping_timer_force_agent_cfg.svh"
  `include "ping_timer_force_seq_item.svh"
  `include "ping_timer_force_driver.svh"
  typedef dv_base_sequencer #(ping_timer_force_seq_item,
                              ping_timer_force_agent_cfg) ping_timer_force_sequencer;
  `include "ping_timer_force_agent.svh"
  `include "ping_timer_force_seq.svh"
endpackage
