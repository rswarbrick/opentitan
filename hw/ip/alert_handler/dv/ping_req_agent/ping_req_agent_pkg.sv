// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package ping_req_agent_pkg;
  import uvm_pkg::*;

  import dv_base_agent_pkg::dv_base_agent;
  import dv_base_agent_pkg::dv_base_agent_cfg;
  import dv_base_agent_pkg::dv_base_monitor;

  `include "uvm_macros.svh"
  `include "dv_macros.svh"

  // The maximum number of escalation interfaces ping_req_if will support (this needs to be a
  // parameter that is jointly visible to the interface and the components that consume it)
  parameter int unsigned MaxEscalationIfs = 128;

  // The maximum number of alert interfaces ping_req_if will support (this needs to be a
  // parameter that is jointly visible to the interface and the components that consume it)
  parameter int unsigned MaxAlertIfs = 128;

  // The type of ping request (is this for an alert or escalation interface)
  typedef enum bit {
    AlertPingReq,
    EscPingReq
  } req_type_e;

  // How is the ping request changing? (start or end of the request)
  typedef enum bit {
    PingReqStart,
    PingReqEnd
  } req_stage_e;

  `include "ping_req_agent_cfg.svh"
  `include "ping_req_seq_item.svh"
  `include "ping_req_monitor.svh"
  `include "ping_req_agent.svh"
endpackage
