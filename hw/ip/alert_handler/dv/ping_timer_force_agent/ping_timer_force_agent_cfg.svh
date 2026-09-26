// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Configuration class for ping_timer_force_agent

class ping_timer_force_agent_cfg extends dv_base_agent_cfg;
  `uvm_object_utils(ping_timer_force_agent_cfg)

  virtual ping_timer_force_if vif;

  extern function new (string name="");
endclass

function ping_timer_force_agent_cfg::new (string name="");
  super.new(name);
endfunction
