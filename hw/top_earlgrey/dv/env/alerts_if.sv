// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This interface should be bound in to an alert_handler instance, where it can report alerts that
// have been seen by the alert_handler's prim_alert_receiver instances.

interface alerts_if (input clk_i, input rst_ni);

  // This interface intentionally avoids being parameterised on the number of alerts and uses a
  // max-footprint strategy.
  //
  // See get_nalerts and the check in the initial block below.
  localparam MaxNAlerts = 256;

  // Use an upwards hierarchical reference to see the alert_trig signal inside the alert_handler
  // into which we have been bound.
  //
  // The initial block below checks that the width is large enough.
  logic [MaxNAlerts-1:0] alerts;
  assign alerts = alert_handler.alert_trig;

  clocking alerts_cb @(posedge clk_i);
    input alerts;
  endclocking

  function automatic int unsigned get_nalerts();
    // This is an upwards hierarchical reference that reports the number of alerts in the
    // alert_handler instance into which this interface has been bound.
    return $bits(alert_handler.alert_trig);
  endfunction

  // Return the hierarchical path to the alert_handler instance into which this interface is bound.
  function string alert_handler_hier_path();
    return dv_utils_pkg::get_parent_hier($sformatf("%m"));
  endfunction

  // Sample/force/release the ping timer signal
 `DV_CREATE_SIGNAL_PROBE_FUNCTION(signal_probe_ping_timer_wait_cyc_mask_i,
                                  alert_handler.u_ping_timer.wait_cyc_mask_i)

  initial begin
    import uvm_pkg::*;
    if (get_nalerts() > MaxNAlerts) begin
      `uvm_error($sformatf("%m"),
                 $sformatf("Bound into alert_handler with NAlerts=%0d but MaxNAlerts is just %0d.",
                           get_nalerts(), MaxNAlerts))
    end
  end
endinterface : alerts_if
