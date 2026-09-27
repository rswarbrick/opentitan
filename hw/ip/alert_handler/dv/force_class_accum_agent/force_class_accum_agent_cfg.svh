// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Configuration class for force_class_accum_agent

class force_class_accum_agent_cfg extends dv_base_agent_cfg;
  `uvm_object_utils(force_class_accum_agent_cfg)

  virtual force_class_accum_if vif;

  extern function new (string name="");
endclass

function force_class_accum_agent_cfg::new (string name="");
  super.new(name);
endfunction
