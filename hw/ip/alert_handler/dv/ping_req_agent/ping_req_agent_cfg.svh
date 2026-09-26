// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Configuration class for ping_req_agent

class ping_req_agent_cfg extends dv_base_agent_cfg;
  `uvm_object_utils(ping_req_agent_cfg)

  virtual ping_req_if vif;

  extern function new (string name="");
endclass

function ping_req_agent_cfg::new (string name="");
  super.new(name);
endfunction
