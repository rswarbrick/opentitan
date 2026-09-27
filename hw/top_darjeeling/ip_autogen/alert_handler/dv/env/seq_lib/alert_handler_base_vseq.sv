// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class alert_handler_base_vseq extends cip_base_vseq #(
    .CFG_T               (alert_handler_env_cfg),
    .RAL_T               (alert_handler_reg_block),
    .COV_T               (alert_handler_env_cov),
    .VIRTUAL_SEQUENCER_T (alert_handler_virtual_sequencer)
  );
  `uvm_object_utils(alert_handler_base_vseq)

  // A sequencer to use to send LPG updates. Set this with set_sequencer() before calling start().
  protected lpg_sequencer m_lpg_sequencer;

  // A sequencer to use in a sequence that forces an input signal on a ping timer
  protected ping_timer_force_sequencer m_ping_timer_force_sequencer;

  // An array of sequencers (one for each alert class), which can be used in a sequence that wants
  // to force the accumulation count for an alert class.
  protected force_class_accum_sequencer m_force_class_accum_sequencers[$];

  // various knobs to enable certain routines
  bit do_alert_handler_init = 1'b0;
  bit config_locked         = 1'b0;

  function new(string name="");
    super.new(name);
  endfunction

  // Set the LPG sequencer
  function void set_lpg_sequencer(lpg_sequencer sequencer);
    m_lpg_sequencer = sequencer;
  endfunction

  // Set the sequencer for forcing ping timers
  function void set_ping_timer_force_sequencer(ping_timer_force_sequencer sequencer);
    m_ping_timer_force_sequencer = sequencer;
  endfunction

  // Provide sequencers for forcing accumulation counts for the various alert classes
  function void set_force_class_accum_sequencers(force_class_accum_sequencer sequencers[$]);
    if (sequencers.size != NUM_ALERT_CLASSES) begin
      `uvm_fatal(get_full_name(),
                 $sformatf({"Wrong number of sequencers. NUM_ALERT_CLASSES=%0d, ",
                            "but there are %0d sequencers."},
                           NUM_ALERT_CLASSES, sequencers.size()))
    end
    m_force_class_accum_sequencers = sequencers;
  endfunction

  virtual task pre_start();
    if (m_lpg_sequencer == null) begin
      `uvm_fatal(get_full_name(), "m_lpg_sequencer has not been supplied")
    end
    if (m_ping_timer_force_sequencer == null) begin
      `uvm_fatal(get_full_name(), "m_ping_timer_force_sequencer has not been supplied")
    end
    if (m_force_class_accum_sequencers.size == 0) begin
      `uvm_fatal(get_full_name(), "No force_class_accum_sequencers supplied.")
    end

    super.pre_start();
  endtask

  virtual task dut_init(string reset_kind = "HARD");
    bit saw_reset;
    fork
      super.dut_init();
      clear_all_lpgs(saw_reset);
    join

    // If we have seen a reset when clearing LPGs, there's nothing more to do. Drop out immediately.
    if (saw_reset) return;

    if (do_alert_handler_init) alert_handler_init();

    config_locked = 0;
  endtask

  virtual task dut_shutdown();
    // nothing special yet
  endtask

  // setup basic alert_handler features
  // alert_class default 0 -> all alert will trigger interrupt classA
  virtual task alert_handler_init(
      bit [NUM_ALERT_CLASSES-1:0]                       intr_en = '1,
      bit [NUM_ALERTS-1:0]                              alert_en = '1,
      bit [NUM_ALERTS-1:0][NUM_ALERT_CLASSES-1:0]       alert_class = 'h0,
      bit [NUM_LOCAL_ALERTS-1:0]                        loc_alert_en = '1,
      bit [NUM_LOCAL_ALERTS-1:0][NUM_ALERT_CLASSES-1:0] loc_alert_class = 'h0);

    csr_wr(.ptr(ral.intr_enable), .value(intr_en));
    foreach (alert_en[i])        csr_wr(.ptr(ral.alert_en_shadowed[i]),
                                        .value(alert_en[i]));
    foreach (alert_class[i])     csr_wr(.ptr(ral.alert_class_shadowed[i]),
                                        .value(alert_class[i]));
    foreach (loc_alert_en[i])    csr_wr(.ptr(ral.loc_alert_en_shadowed[i]),
                                        .value(loc_alert_en[i]));
    foreach (loc_alert_class[i]) csr_wr(.ptr(ral.loc_alert_class_shadowed[i]),
                                        .value(loc_alert_class[i]));
  endtask

  // Randomize and write the ctrl register for a class, but constraining the LOCK and EN fields to
  // have the provided values.
  local task randomize_and_write_one_class_ctrl(int unsigned class_idx,
                                                bit          lock_bit,
                                                bit          class_en);
    uvm_reg_field fields[$];
    uvm_reg       register = cfg.get_class_ctrl(cfg.m_class_names[class_idx]);

    register.get_fields(fields);

    // Walk through the fields. Set LOCK and EN as expected, and disable randomisation for those
    // fields.
    foreach (fields[i]) begin
      case (fields[i].get_name())
        "lock": begin
          fields[i].set(lock_bit);
          fields[i].rand_mode(0);
        end
        "en": begin
          fields[i].set(class_en);
          fields[i].rand_mode(0);
        end
        default: begin end
      endcase
    end

    // Now randomise the register, which won't touch the LOCK and EN fields that we just configured.
    if (!register.randomize()) begin
      `uvm_fatal(get_full_name(), $sformatf("Failed to randomize %0s.", register.get_name()))
    end

    // Re-enable randomisation of all the fields
    foreach (fields[i]) fields[i].rand_mode(1);

    // Finally, update the register to contain the value that we have just chosen.
    csr_update(register);
  endtask

  // Randomize and write the CTRL_SHADOWED registers for the various alert classes, but constraining
  // those classes' LOCK and EN fields to have the values in the lock_bit and class_en arguments.
  task alert_handler_rand_wr_class_ctrl(bit [NUM_ALERT_CLASSES-1:0] lock_bit,
                                        bit [NUM_ALERT_CLASSES-1:0] class_en);
    fork : isolation_fork begin
      for (int unsigned i = 0; i < NUM_ALERT_CLASSES; i++) begin
        automatic int unsigned class_idx = i;
        fork
          randomize_and_write_one_class_ctrl(class_idx, lock_bit[class_idx], class_en[class_idx]);
        join_none
      end
      wait fork;
    end join
  endtask

  virtual task alert_handler_wr_regwen_regs(bit [NUM_ALERT_CLASSES-1:0] regwen = 0,
                                            bit [NUM_ALERTS-1:0]        alert_regwen = 0,
                                            bit [NUM_LOCAL_ALERTS-1:0]  loc_alert_regwen = 0,
                                            bit                         ping_timer_regwen = 0,
                                            bit [NUM_ALERT_CLASSES-1:0] class_regwen = 0);

    csr_wr(.ptr(ral.classa_clr_regwen), .value(regwen[0]));
    csr_wr(.ptr(ral.classb_clr_regwen), .value(regwen[1]));
    csr_wr(.ptr(ral.classc_clr_regwen), .value(regwen[2]));
    csr_wr(.ptr(ral.classd_clr_regwen), .value(regwen[3]));

    foreach (alert_regwen[i]) csr_wr(.ptr(ral.alert_regwen[i]), .value(alert_regwen[i]));

    foreach (loc_alert_regwen[i]) begin
      csr_wr(.ptr(ral.loc_alert_regwen[i]), .value(loc_alert_regwen[i]));
    end

    csr_wr(.ptr(ral.ping_timer_regwen), .value(ping_timer_regwen));

    csr_wr(.ptr(ral.classa_regwen), .value(class_regwen[0]));
    csr_wr(.ptr(ral.classb_regwen), .value(class_regwen[1]));
    csr_wr(.ptr(ral.classc_regwen), .value(class_regwen[2]));
    csr_wr(.ptr(ral.classd_regwen), .value(class_regwen[3]));
  endtask

  // If do_lock_config is set, write value 1 to ping_timer_en register.
  // If not set, this task has 50% of chance to write value 1 to ping_timer_en register.
  virtual task lock_config(bit do_lock_config);
    if (do_lock_config || $urandom_range(0, 1)) begin
      csr_wr(.ptr(ral.ping_timer_en_shadowed), .value(do_lock_config));
    end
  endtask

  virtual task drive_alert(bit[NUM_ALERTS-1:0] alert_trigger, bit[NUM_ALERTS-1:0] alert_int_err);
    fork
      begin : isolation_fork
        foreach (alert_trigger[i]) begin
          if (alert_trigger[i]) begin
            automatic int index = i;
            fork
              begin
                alert_sender_seq alert_seq;
                `uvm_create_on(alert_seq, p_sequencer.alert_host_seqr_h[index]);
                `DV_CHECK_RANDOMIZE_WITH_FATAL(alert_seq, int_err == alert_int_err[index];)
                `uvm_send(alert_seq)
              end
            join_none
          end
        end
        wait fork;
      end
    join
  endtask

  // This sequence will drive standalone esc_resp_p/n without esc_p/n
  virtual task drive_esc_rsp(bit [NUM_ESCS-1:0] esc_int_errs);
    fork
      begin : isolation_fork
        foreach (cfg.esc_device_cfg[i]) begin
          automatic int index = i;
          if (esc_int_errs[index]) begin
            fork
              begin
                esc_receiver_base_seq esc_seq = esc_receiver_base_seq::type_id::create("esc_seq");
                if (!esc_seq.randomize() with {
                       int_err == 1; standalone_int_err == 1; ping_timeout == 0;
                     }) begin
                  `uvm_fatal(get_full_name(), "Failed to randomize esc_seq.")
                end
                esc_seq.start(p_sequencer.esc_device_seqr_h[index]);
              end
            join_none
          end
        end
        wait fork;
      end
    join
  endtask

  // alert_handler scb will compare the read value with expected value
  // Not using "clear_all_interrupts" function in cip_base_vseq because of the signal integrity
  // error: after clearing intr_state, intr_state might come back to 1 in the next cycle.
  virtual task check_alert_interrupts();
    uvm_status_e txn_status;

    // Wait until there is no ping handshake.
    // This will avoid the case where interrupt is set and cleared at the same cycle.
    cfg.wait_no_ping_req();
    ral.intr_state.mirror(txn_status);
    if (cfg.under_reset) return;
    if (txn_status != UVM_IS_OK) `uvm_error(get_full_name(), "Failed to mirror INTR_STATE.")

    cfg.wait_no_ping_req();
    ral.intr_state.write(txn_status, '1);
    if (cfg.under_reset) return;
    if (txn_status != UVM_IS_OK) `uvm_error(get_full_name(), "Failed to write INTR_STATE.")
  endtask

  virtual task clear_esc();
    csr_wr(.ptr(ral.classa_clr_shadowed), .value(1));
    csr_wr(.ptr(ral.classb_clr_shadowed), .value(1));
    csr_wr(.ptr(ral.classc_clr_shadowed), .value(1));
    csr_wr(.ptr(ral.classd_clr_shadowed), .value(1));
  endtask

  // checking for csr_rd is done in scb
  virtual task read_alert_cause();
    bit [TL_DW-1:0] alert_cause;
    foreach (ral.alert_cause[i]) begin
      if ($urandom_range(0, 1)) begin
        csr_rd(.ptr(ral.alert_cause[i]), .value(alert_cause));
      end
    end
    foreach (ral.loc_alert_cause[i]) begin
      if ($urandom_range(0, 1)) begin
        csr_rd(.ptr(ral.loc_alert_cause[i]), .value(alert_cause));
      end
    end
  endtask

  virtual task read_esc_status();
    bit [TL_DW-1:0] csr_val;
    csr_rd(.ptr(ral.classa_accum_cnt), .value(csr_val));
    csr_rd(.ptr(ral.classb_accum_cnt), .value(csr_val));
    csr_rd(.ptr(ral.classc_accum_cnt), .value(csr_val));
    csr_rd(.ptr(ral.classd_accum_cnt), .value(csr_val));

    csr_rd(.ptr(ral.classa_state), .value(csr_val));
    csr_rd(.ptr(ral.classb_state), .value(csr_val));
    csr_rd(.ptr(ral.classc_state), .value(csr_val));
    csr_rd(.ptr(ral.classd_state), .value(csr_val));

    csr_rd(.ptr(ral.classa_esc_cnt), .value(csr_val));
    csr_rd(.ptr(ral.classb_esc_cnt), .value(csr_val));
    csr_rd(.ptr(ral.classc_esc_cnt), .value(csr_val));
    csr_rd(.ptr(ral.classd_esc_cnt), .value(csr_val));
  endtask

  virtual task wait_alert_handshake_done();
    cfg.clk_rst_vif.wait_clks(2);
    foreach (cfg.alert_host_cfg[i]) begin
      if (!cfg.alert_host_cfg[i].en_alert_lpg) cfg.alert_host_cfg[i].vif.wait_ack_complete();
    end
  endtask

  virtual function bit check_esc_done(bit[TL_DW-1:0] vals[$]);
    foreach (vals[i]) begin
      esc_state_e val = esc_state_e'(vals[i]);
      if (val inside {EscStatePhase0, EscStatePhase1, EscStatePhase2, EscStatePhase3}) return 0;
    end
    return 1;
  endfunction

  virtual task wait_esc_handshake_done();
    bit [TL_DW-1:0] csr_vals[4];
    do begin
      csr_rd(.ptr(ral.classa_state), .value(csr_vals[0]));
      csr_rd(.ptr(ral.classb_state), .value(csr_vals[1]));
      csr_rd(.ptr(ral.classc_state), .value(csr_vals[2]));
      csr_rd(.ptr(ral.classd_state), .value(csr_vals[3]));
    end while (!check_esc_done(csr_vals));
    // check if there is any esc ping
    foreach (cfg.esc_device_cfg[i]) cfg.esc_device_cfg[i].vif.wait_esc_complete();
  endtask

  // This task wait until any alert or esc protocol received a ping from LFSR.
  // This task will also return the protocol index:
  // alert index starts from 1; esc index stats from NUM_ALERTS
  virtual task wait_alert_esc_ping(ref int ping_index);
    int ping_i;
    fork
      begin : isolation_fork
        foreach (cfg.alert_host_cfg[i]) begin
          automatic int index = i;
          fork
            begin
              cfg.alert_host_cfg[index].vif.wait_alert_ping();
              ping_i = index + 1;
            end
          join_none
        end
        foreach (cfg.esc_device_cfg[i]) begin
          automatic int index = i;
          fork
            begin
              cfg.esc_device_cfg[index].vif.wait_esc_ping();
              ping_i = index + NUM_ALERTS + 1;
            end
          join_none
        end
        wait (ping_i > 0);
        disable fork;
        ping_index = ping_i;
      end
    join
  endtask

  // Configure the LPGs so that every group that is used by an alert whose bit is set in alerts is
  // put into low power mode.
  protected task enable_lpg_group(bit [NUM_ALERTS-1:0] alerts);
    bit [lpg_agent_pkg::MaxNumLpgs-1:0] lpgs_for_low_power;

    // This bit is set if any of the LPG sequences sees a reset. The task doesn't report resets at
    // the moment (because the task's only call site doesn't need it), but this bit could be wired
    // out if we need that in future.
    bit saw_reset;

    // Work through the alerts in alerts and set the corresponding bit in lpgs_for_low_power for any
    // alert whose bit is set.
    foreach (alerts[i]) begin
      if (alerts[i]) begin
        int unsigned lpg_idx = alert_handler_reg_pkg::LpgMap[i];
        lpgs_for_low_power[lpg_idx] = 1'b1;
      end
    end

    // Finally, drive sequences that put the appropriate LPGs into low power mode, (skipping LPGs
    // that cfg thinks are already in low power mode).
    fork : isolation_fork begin
      for (int unsigned lpg_idx = 0; lpg_idx < cfg.m_lpg_agent_cfg.vif.num_lpgs; lpg_idx++) begin
        if (lpgs_for_low_power[lpg_idx] && !cfg.is_lpg_low_power(lpg_idx)) begin
          automatic int unsigned lpg_idx_ = lpg_idx;
          fork begin
            bit saw_reset_;
            set_lpg(lpg_idx_, saw_reset_);
            if (saw_reset_) saw_reset = 1;
          end join_none
        end
      end

      // One or more of those sequences might now be running in parallel. Wait for them to finish.
      wait fork;
    end join

    // If we have seen a reset, the saw_reset output has already been set and we have nothing more
    // to do.
    if (saw_reset) return;

    // Inform all alert agents whose alerts are in a low-power LPG. This has to be performed by the
    // sequence because we don't yet track this in the environment.
    for (int unsigned alert_idx = 0; alert_idx < NUM_ALERTS; alert_idx++) begin
      int unsigned lpg_idx = alert_handler_reg_pkg::LpgMap[alert_idx];
      if (lpgs_for_low_power[lpg_idx]) begin
        cfg.alert_host_cfg[alert_idx].en_alert_lpg = 1;
      end
    end
  endtask

  // Put the given LPG into low power mode
  //
  // Set saw_reset if a reset was applied when the LPG sequence was running.
  local task set_lpg(int unsigned lpg_idx, output bit saw_reset);
    import lpg_agent_pkg::lpg_bool_seq;
    lpg_bool_seq lpg_seq = lpg_bool_seq::type_id::create("lpg_seq");

    // Randomise the LPG sequence so that it either asserts clock gating enable or reset enable (or
    // possibly both) for lpg_idx.
    if (!lpg_seq.randomize() with {
           m_lpg_idx == local::lpg_idx;
           m_cg_en || m_rst_en;
         }) begin
      `uvm_fatal(get_full_name(), "Failed to randomize lpg_seq")
    end

    lpg_seq.start(m_lpg_sequencer);

    saw_reset = !lpg_seq.m_rsp.m_sending_complete;
  endtask

  // Make sure the given LPG is not in low power mode
  //
  // Set saw_reset if a reset was applied when the LPG sequence was running.
  local task clear_lpg(int unsigned lpg_idx, output bit saw_reset);
    import lpg_agent_pkg::lpg_bool_seq;
    lpg_bool_seq lpg_seq = lpg_bool_seq::type_id::create("lpg_seq");

    // Randomise the LPG sequence so that it sets both assert clock gating enable and reset enable
    // for lpg_idx to a value other than MuBi4True.
    if (!lpg_seq.randomize() with {
           m_lpg_idx == local::lpg_idx;
           !m_cg_en;
           !m_rst_en;
         }) begin
      `uvm_fatal(get_full_name(), "Failed to randomize lpg_seq")
    end

    lpg_seq.start(m_lpg_sequencer);

    saw_reset = !lpg_seq.m_rsp.m_sending_complete;
  endtask

  // Write values to the lpg_if to make sure that none of the LPGs is in low power mode
  //
  // Set saw_reset if a reset is seen when running
  local task clear_all_lpgs(output bit saw_reset);
    fork : isolation_fork begin
      for (int unsigned i = 0; i < cfg.m_lpg_agent_cfg.vif.num_lpgs; i++) begin
        automatic int i_ = i;
        fork begin
          bit saw_reset_;
          clear_lpg(i_, saw_reset_);
          if (saw_reset_) saw_reset = 1;
        end join_none
      end

      wait fork;
    end join
  endtask

  virtual task alert_handler_crashdump_phases(bit [1:0] classa_phase = $urandom(),
                                              bit [1:0] classb_phase = $urandom(),
                                              bit [1:0] classc_phase = $urandom(),
                                              bit [1:0] classd_phase = $urandom());
    csr_wr(.ptr(ral.classa_crashdump_trigger_shadowed), .value(classa_phase));
    csr_wr(.ptr(ral.classb_crashdump_trigger_shadowed), .value(classb_phase));
    csr_wr(.ptr(ral.classc_crashdump_trigger_shadowed), .value(classc_phase));
    csr_wr(.ptr(ral.classd_crashdump_trigger_shadowed), .value(classd_phase));
  endtask

  // Choose a random phase cycle value that is at most max_phase_cyc and write it to the unique
  // field in register 'class<C>_phase<P>_cyc_shadowed', where C and P are class_idx and phase.
  local task rand_and_write_one_phase_cycle(int unsigned class_idx,
                                            int unsigned phase,
                                            int unsigned max_phase_cyc);
    uvm_reg_field fields[$];
    uvm_reg       register = cfg.get_class_phase_cyc(cfg.m_class_names[class_idx], phase);

    register.get_fields(fields);
    if (fields.size() != 1) begin
      `uvm_fatal(get_full_name(),
                 $sformatf("Cannot randomise register %0s: we expect it to have a single field.",
                           register.get_name()))
    end

    if (!fields[0].randomize() with { value <= local::max_phase_cyc; }) begin
      `uvm_fatal(get_full_name(), $sformatf("Failed to randomise the %0s field in %0s",
                                            fields[0].get_name(), register.get_name()))
    end

    csr_update(register);
  endtask

  // Randomise and write the four phase cycle values for the given alert class.
  local task rand_and_write_phases_cycle_for_class(int unsigned class_idx,
                                                   int unsigned max_phase_cyc);
    fork : isolation_fork begin
      for (int unsigned i = 0; i < 4; i++) begin
        automatic int unsigned phase = i;
        fork
          rand_and_write_one_phase_cycle(class_idx, phase, max_phase_cyc);
        join_none
      end
      wait fork;
    end join
  endtask

  // Randomise and write all the phase cycle counts for all of the alert classes
  protected task wr_phases_cycle(int max_phase_cyc);
    fork : isolation_fork begin
      for (int unsigned i = 0; i < NUM_ALERT_CLASSES; i++) begin
        automatic int unsigned class_idx = i;
        fork
          rand_and_write_phases_cycle_for_class(class_idx, max_phase_cyc);
        join_none
      end
      wait fork;
    end join
  endtask

  virtual task wr_intr_timeout_cycle(bit[TL_DW-1:0] intr_timeout_cyc[NUM_ALERT_CLASSES]);
    csr_wr(.ptr(ral.classa_timeout_cyc_shadowed), .value(intr_timeout_cyc[0]));
    csr_wr(.ptr(ral.classb_timeout_cyc_shadowed), .value(intr_timeout_cyc[1]));
    csr_wr(.ptr(ral.classc_timeout_cyc_shadowed), .value(intr_timeout_cyc[2]));
    csr_wr(.ptr(ral.classd_timeout_cyc_shadowed), .value(intr_timeout_cyc[3]));
  endtask

  virtual task wr_class_accum_threshold(bit[TL_DW-1:0] accum_thresh[NUM_ALERT_CLASSES]);
    csr_wr(.ptr(ral.classa_accum_thresh_shadowed), .value(accum_thresh[0]));
    csr_wr(.ptr(ral.classb_accum_thresh_shadowed), .value(accum_thresh[1]));
    csr_wr(.ptr(ral.classc_accum_thresh_shadowed), .value(accum_thresh[2]));
    csr_wr(.ptr(ral.classd_accum_thresh_shadowed), .value(accum_thresh[3]));
  endtask

  virtual task wr_ping_timeout_cycle(bit[TL_DW-1:0] timeout_val);
    csr_wr(.ptr(ral.ping_timeout_cyc_shadowed), .value(timeout_val));
    if (`gmv(ral.ping_timer_regwen)) begin
      if (timeout_val == 0) timeout_val = 1;
      foreach (cfg.alert_host_cfg[i]) cfg.alert_host_cfg[i].ping_timeout_cycle = timeout_val;
      foreach (cfg.esc_device_cfg[i]) cfg.esc_device_cfg[i].ping_timeout_cycle = timeout_val;
    end
  endtask

  // This sequence will automatically response to all escalation ping and esc responses
  virtual task run_esc_rsp_seq_nonblocking(bit [NUM_ESCS-1:0] esc_int_errs = '0,
                                           bit [NUM_ESCS-1:0] ping_timeout_errs = '0);
    foreach (cfg.esc_device_cfg[i]) begin
      automatic int index = i;
      fork
        forever begin
          bit esc_int_err      = esc_int_errs[index]      ? $urandom_range(0, 1) : 0;
          bit ping_timeout_err = ping_timeout_errs[index] ? $urandom_range(0, 1) : 0;
          esc_receiver_base_seq esc_seq = esc_receiver_base_seq::type_id::create("esc_seq");
          if (!esc_seq.randomize() with {
                 int_err            == local::esc_int_err;
                 standalone_int_err == 0;
                 ping_timeout       == local::ping_timeout_err;
               }) begin
            `uvm_fatal(get_full_name(), "Failed to randomize esc_seq.")
          end
          esc_seq.start(p_sequencer.esc_device_seqr_h[index]);

          // The sequence has finished, which either means that we have seen an escalation and sent
          // a response, or it means that a reset has happened. Watch the agent's configuration to
          // wait until it is out of reset before starting a sequence to respond to the next
          // escalation.
          wait(!cfg.esc_device_cfg[index].in_reset);
        end
      join_none
    end
  endtask

endclass : alert_handler_base_vseq
