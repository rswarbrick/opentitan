// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//

module otbn_start_stop_control_bind_fpv;


  bind otbn_start_stop_control otbn_start_stop_control_assert_fpv #(
    .SecMuteUrnd(SecMuteUrnd),
    .SecSkipUrndReseedAtStart(SecSkipUrndReseedAtStart)
  ) i_otbn_start_stop_control_assert_fpv (
    .clk_i,
    .rst_ni,
    .start_i,
    .escalate_en_i,
    .rma_req_i,
    .rma_ack_o,
    .controller_start_o,
    .urnd_reseed_req_o,
    .urnd_reseed_ack_i,
    .urnd_reseed_err_o,
    .urnd_advance_o,
    .secure_wipe_req_i,
    .secure_wipe_ack_o,
    .secure_wipe_running_o,
    .done_o,
    .sec_wipe_wdr_o,
    .sec_wipe_wdr_urnd_o,
    .sec_wipe_base_o,
    .sec_wipe_base_urnd_o,
    .sec_wipe_addr_o,
    .sec_wipe_acc_urnd_o,
    .sec_wipe_mod_urnd_o,
    .sec_wipe_zero_o,
    .ispr_init_o,
    .state_reset_o,
    .fatal_error_o
  );


endmodule : otbn_start_stop_control_bind_fpv
