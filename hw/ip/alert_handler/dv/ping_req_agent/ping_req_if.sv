// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Interface for ping request signals seen inside an alert_handler
//
// This interface uses a "max footprint" approach, which allows it not to be parameterised by the
// number of escalation or alert interfaces

interface ping_req_if(input clk, input rst_n);
  import uvm_pkg::*;
  import ping_req_agent_pkg::MaxAlertIfs;
  import ping_req_agent_pkg::MaxEscalationIfs;

  logic [MaxAlertIfs-1:0]      alert_ping_reqs;
  logic [MaxEscalationIfs-1:0] esc_ping_reqs;

  clocking mon_cb @(posedge clk);
    input alert_ping_reqs;
    input esc_ping_reqs;
  endclocking

endinterface
