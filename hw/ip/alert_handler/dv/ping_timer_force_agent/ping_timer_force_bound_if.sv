// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// An interface that is designed to be bound into an alert_handler_ping_timer instance called
// u_ping_timer (which lives inside alert_handler). This can then cleanly access the ports of that
// instance by a named upwards hierarchical reference, without needing to know the type of the
// templated module.
//
// This interface is connected to the environment through u_force_if, an instance of
// ping_timer_force_if that is instantiated inside it. That interface can be safely connected to the
// environment.
//
// The Bound parameter is passed with a value of 1 whenever this interface is bound into the design
// and everything inside the interface that uses hierarchical references is in a generate block that
// depends on it. This avoids elaboration-time errors from the EDA tool if we don't happen to
// instantiate the interface anywhere.

interface ping_timer_force_bound_if #(
  parameter bit Bound=0
) (
  input wire clk_i,
  input wire rst_ni
);
  import uvm_pkg::*;
  import ping_timer_force_agent_pkg::MaxPingCntDw;

  if (Bound) begin : gen_bound
    bit                    override_wait_cyc_mask;
    bit [MaxPingCntDw-1:0] desired_wait_cyc_mask_val;
    bit                    wait_cyc_mask_overridden;

    initial begin
      wait_cyc_mask_overridden = 0;
      forever begin
        wait(override_wait_cyc_mask);

        // Check that desired_wait_cyc_mask_val is a plausible value that will fit in the
        // wait_cyc_mask_i port. Rather than relying on a PING_CNT_DW global, compare with $bits()
        // on the port itself.
        if (|(desired_wait_cyc_mask_val >> $bits(u_ping_timer.wait_cyc_mask_i))) begin
          `uvm_fatal($sformatf("%m"),
                     $sformatf({"Cannot represent the desired wait_cyc_mask_i value of 0x%0h: the ",
                                "port has only %0d bits."},
                               desired_wait_cyc_mask_val,
                               $bits(u_ping_timer.wait_cyc_mask_i)))
        end

        // Force the value and then wait until reset is asserted
        force u_ping_timer.wait_cyc_mask_i = desired_wait_cyc_mask_val;

        wait(!rst_ni);

        release u_ping_timer.wait_cyc_mask_i;
        wait_cyc_mask_overridden ^= 1;
        wait(!override_wait_cyc_mask);
      end
    end

    ping_timer_force_if u_force_if (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),

      .override_wait_cyc_mask_o    (override_wait_cyc_mask),
      .desired_wait_cyc_mask_val_o (desired_wait_cyc_mask_val),
      .wait_cyc_mask_overridden_i  (wait_cyc_mask_overridden)
    );
  end
endinterface
