// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// An interface that is designed to be bound into an alert_handler_accu instance called u_accu in
// alert_handler. The specific name allows it to access ports of that instance by a named upwards
// hierarchical reference, without needing to know the type of the templated module.
//
// This interface is connected to the environment through u_force_if, an instance of
// force_class_accum_if that is instantiated inside it. That interface can be safely connected to
// the environment.
//
// The Bound parameter is passed with a value of 1 whenever this interface is bound into the design
// and everything inside the interface that uses hierarchical references is in a generate block that
// depends on it. This avoids elaboration-time errors from the EDA tool if we don't happen to
// instantiate the interface anywhere.

interface force_class_accum_bound_if #(
  parameter bit          Bound=0,
  parameter int unsigned AccuCntDw=1
) (
  input wire clk_i,
  input wire rst_ni
);
  import uvm_pkg::*;
  import force_class_accum_agent_pkg::MaxAccuCntDw;

  if (Bound) begin : gen_bound
    bit                    override_prim_count;
    bit [MaxAccuCntDw-1:0] desired_prim_count;
    bit                    prim_count_overridden;
    bit                    stop_prim_count_override;

    initial begin
      prim_count_overridden = 0;
      forever begin
        static bit [AccuCntDw-1:0] max_count = '1;
        static bit [AccuCntDw-1:0] desired_neg_count;

        wait(override_prim_count);

        // Check that desired_prim_count will actually fit in AccuCntDw bits (a parameter inferred
        // from the bind site).
        if (|(desired_prim_count >> AccuCntDw)) begin
          `uvm_fatal($sformatf("%m"),
                     $sformatf({"Cannot represent the desired count value of 0x%0h: the ",
                                "counter width is only %0d bits."},
                               desired_prim_count,
                               AccuCntDw))
        end
        desired_neg_count = max_count - desired_prim_count;

        // To force both sides of the prim_count still summing to (1 << AccuCntDw) - 1), compute
        // "desired" values of the correct width for the two sides.
        force u_prim_count.cnt_q[0] = desired_prim_count;
        force u_prim_count.cnt_q[1] = desired_neg_count;

        // Maintain the forcing until either reset is asserted or stop_prim_count_override is
        // asserted (allowing a sequence to cancel the forcing).
        wait(stop_prim_count_override || !rst_ni);

        release u_prim_count.cnt_q[0];
        release u_prim_count.cnt_q[1];

        prim_count_overridden ^= 1;

        wait(!override_prim_count);
      end
    end

    force_class_accum_if u_force_if (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),

      .override_prim_count_o      (override_prim_count),
      .desired_prim_count_o       (desired_prim_count),
      .prim_count_overridden_i    (prim_count_overridden),
      .stop_prim_count_override_o (stop_prim_count_override)
    );
  end
endinterface
