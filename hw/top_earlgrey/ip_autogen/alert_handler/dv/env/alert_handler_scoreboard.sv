// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`uvm_analysis_imp_decl(_lpg)
`uvm_analysis_imp_decl(_ping_req)

class alert_handler_scoreboard extends cip_base_scoreboard #(
    .CFG_T(alert_handler_env_cfg),
    .RAL_T(alert_handler_reg_block),
    .COV_T(alert_handler_env_cov)
  );
  `uvm_component_utils(alert_handler_scoreboard)

  // esc_phase_cyc_per_class_q: each class has four phase cycles, stores each cycle length
  // --- class --- phase0_cyc    ---    phase1_cyc   ---    phase2_cyc   ---     phase3_cyc  ---
  // ---   A   -classa_phase0_cyc - classa_phase1_cyc - classa_phase2_cyc - classa_phase3_cyc --
  // ---   B   -classb_phase0_cyc - classb_phase1_cyc - classb_phase2_cyc - classb_phase3_cyc --
  // ---   C   -classc_phase0_cyc - classc_phase1_cyc - classc_phase2_cyc - classc_phase3_cyc --
  // ---   D   -classd_phase0_cyc - classd_phase1_cyc - classd_phase2_cyc - classd_phase3_cyc --
  uvm_reg reg_esc_phase_cycs_per_class_q[NUM_ALERT_CLASSES][$];

  uvm_reg_field intr_state_fields[$];
  uvm_reg_field intr_state_field;
  // once escalation triggers, no alerts can trigger another escalation in the same class
  // until the class esc is cleared
  bit [NUM_ALERT_CLASSES-1:0] under_esc_classes;
  bit [NUM_ALERT_CLASSES-1:0] under_intr_classes;
  bit [NUM_ALERT_CLASSES-1:0] clr_esc_under_intr;
  int intr_cnter_per_class    [NUM_ALERT_CLASSES];
  int accum_cnter_per_class   [NUM_ALERT_CLASSES];
  esc_state_e state_per_class [NUM_ALERT_CLASSES];
  int  esc_signal_release  [NUM_ESC_SIGNALS];
  int  esc_sig_class       [NUM_ESC_SIGNALS]; // one class can increment one esc signal at a time
  // For different alert classify in the same class and trigger at the same cycle, design only
  // count once. So record the alert triggered timing here
  realtime last_triggered_alert_per_class[NUM_ALERT_CLASSES];

  bit [TL_DW-1:0] intr_state_val;

  bit [NUM_ALERT_CLASSES-1:0] crashdump_triggered = 0;

  bit ping_timer_en;

  // TLM agent fifos
  uvm_tlm_analysis_fifo #(alert_seq_item) alert_fifo[NUM_ALERTS];
  uvm_tlm_analysis_fifo #(esc_seq_item)   esc_fifo[NUM_ESCS];

  // An import for LPG changes seen by the lpg_monitor
  uvm_analysis_imp_lpg #(lpg_seq_item, alert_handler_scoreboard) m_lpg_imp;

  // An import for changes to ping request state
  uvm_analysis_imp_ping_req #(ping_req_seq_item, alert_handler_scoreboard) m_ping_req_imp;

  `uvm_component_new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg.get_intr_state_reg().get_fields(intr_state_fields);
    for (int unsigned i = 0; i < $size(cfg.m_class_names); i++) begin
      reg_esc_phase_cycs_per_class_q[i].delete();

      for (int unsigned phase = 0; phase < 4; phase++) begin
        uvm_reg register = cfg.get_class_phase_cyc(cfg.m_class_names[i], phase);
        reg_esc_phase_cycs_per_class_q[i].push_back(register);
      end
    end

    foreach (alert_fifo[i]) alert_fifo[i] = new($sformatf("alert_fifo[%0d]", i), this);
    foreach (esc_fifo[i])   esc_fifo[i]   = new($sformatf("esc_fifo[%0d]"  , i), this);

    m_lpg_imp = new("m_lpg_imp", this);
    m_ping_req_imp = new("m_ping_req_imp", this);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    fork
      process_alert_fifo();
      process_esc_fifo();
      process_edn_fifos();
      check_ping_timer();
      check_crashdump();
      check_intr_timeout_trigger_esc();
      esc_phase_signal_cnter();
      release_esc_signal();
    join_none
  endtask

  virtual task process_alert_fifo();
    foreach (alert_fifo[i]) begin
      automatic int index = i;
      automatic int lpg_index = alert_handler_reg_pkg::LpgMap[index];
      fork
        forever begin
          bit alert_en, loc_alert_en;
          alert_seq_item act_item;
          alert_fifo[index].get(act_item);
          alert_en = (cfg.get_alert_en_shadowed(index).get_mirrored_value() &&
                      !cfg.is_lpg_low_power(lpg_index));

          // Check that ping mechanism will only ping alerts that have been enabled and locked.
          if (act_item.m_trans_type == AlertPingTrans) begin
            `DV_CHECK(alert_en, $sformatf("alert %0s ping triggered but not enabled", index))
            `DV_CHECK((cfg.get_alert_regwen(index).get_mirrored_value() == 0),
                      $sformatf("alert %0s ping triggered but not locked", index))
          end

          if (alert_en) begin
            // alert detected
            if (act_item.m_trans_type == AlertSigTrans && !act_item.m_ping_timeout &&
                act_item.m_alert_handshake_sta == AlertReceived) begin
              process_alert_sig(index, 0);
            // alert integrity fail
            end else if (act_item.m_trans_type == AlertIntFail) begin
              loc_alert_en = cfg.get_loc_alert_en_shadowed(LocalAlertIntFail).get_mirrored_value();
              if (loc_alert_en) process_alert_sig(index, 1, LocalAlertIntFail);
            end else if (act_item.m_trans_type == AlertPingTrans &&
                         act_item.m_ping_timeout) begin
              loc_alert_en = cfg.get_loc_alert_en_shadowed(LocalAlertPingFail).get_mirrored_value();
              if (loc_alert_en) begin
                process_alert_sig(index, 1, LocalAlertPingFail);
                `uvm_info(`gfn, $sformatf("alert %0d ping timeout, timeout_cyc reg is %0d",
                          index, get_ping_timeout_cyc_shadowed().get_mirrored_value()), UVM_LOW);
              end
            end
          end
        end
      join_none
    end
  endtask : process_alert_fifo

  virtual task process_esc_fifo();
    foreach (esc_fifo[i]) begin
      automatic int index = i;
      fork
        forever begin
          esc_seq_item act_item;
          esc_fifo[index].get(act_item);
          // escalation triggered, check signal length
          if (act_item.m_trans_type == EscSigTrans &&
              act_item.m_esc_handshake_sta == EscRespComplete) begin
            check_esc_signal(act_item.m_sig_cycle_cnt, index);
          // escalation integrity fail
          end else if (act_item.m_trans_type == EscIntFail ||
               (act_item.m_esc_handshake_sta == EscHSIntFail && !act_item.m_ping_timeout)) begin
            uvm_reg loc_alert_en = cfg.get_loc_alert_en_shadowed(LocalEscIntFail);
            if (loc_alert_en.get_mirrored_value()) process_alert_sig(index, 1, LocalEscIntFail);
          // escalation ping timeout
          end else if (act_item.m_trans_type == EscPingTrans) begin
            if (act_item.m_ping_timeout) begin
              uvm_reg loc_alert_en = cfg.get_loc_alert_en_shadowed(LocalEscPingFail);
              if (loc_alert_en.get_mirrored_value()) begin
                process_alert_sig(index, 1, LocalEscPingFail);
                `uvm_info(`gfn,
                          $sformatf("esc %0d ping timeout, timeout_cyc reg is %0d",
                                    index, get_ping_timeout_cyc_shadowed().get_mirrored_value()),
                          UVM_LOW);
              end
            end
          end
        end
      join_none
    end
  endtask : process_esc_fifo

  // Alert_handler ping timer is designed to fetch EDN value periodically.
  virtual task process_edn_fifos();
    fork begin: isolation_fork
      int num_edn_reqs;
      forever begin
        wait (cfg.under_reset == 0);
        fork
          begin
             check_edn_request_cycles();
             num_edn_reqs++;
            if (cfg.en_cov) cov.num_edn_reqs_cg.sample(num_edn_reqs);
          end
          begin
            wait (cfg.under_reset == 1);
            num_edn_reqs = 0;
          end
        join_any
        disable fork;
      end
    end join
  endtask

  function void write_lpg(lpg_seq_item item);
    import prim_mubi_pkg::mubi4_t;
    import prim_mubi_pkg::mubi4_test_true_strict;

    cfg.set_lpg_state(item.m_lpg_idx,
                      mubi4_test_true_strict(mubi4_t'(item.m_cg_en)),
                      mubi4_test_true_strict(mubi4_t'(item.m_rst_en)));
  endfunction

  function void write_ping_req(ping_req_seq_item item);
    import ping_req_agent_pkg::AlertPingReq, ping_req_agent_pkg::EscPingReq;
    import ping_req_agent_pkg::PingReqStart, ping_req_agent_pkg::PingReqEnd;

    bit new_state;
    case (item.m_req_stage)
      PingReqStart: new_state = 1'b1;
      PingReqEnd:   new_state = 1'b0;
      default: `uvm_fatal("bad_stage",
                          $sformatf("Unknown req_stage_e value: %0d", item.m_req_stage))
    endcase

    case (item.m_req_type)
      AlertPingReq: cfg.update_alert_ping_req(item.m_idx, new_state);
      EscPingReq:   cfg.update_esc_ping_req(item.m_idx, new_state);
      default: `uvm_fatal("bad_req_type",
                          $sformatf("Unknown req_type_e value: %0d", item.m_req_type))
    endcase
  endfunction

  virtual task check_edn_request_cycles();
    int edn_wait_cycles;
    fork
      begin : isolation_fork
        fork
          begin
            while (edn_wait_cycles < MAX_EDN_REQ_WAIT_CYCLES) begin
              cfg.clk_rst_vif.wait_clks(1);
              edn_wait_cycles++;
            end
            `uvm_error(`gfn, "Timeout occured waiting for an EDN request!");
          end
          begin
            push_pull_item#(.DeviceDataWidth(EDN_DATA_WIDTH)) edn_item;
            edn_fifos[0].get(edn_item);
          end
        join_any
        disable fork;
      end
    join
  endtask

  // this task process alert signal by checking if intergrity fail, then classify it to the
  // mapping classes, then check if escalation is triggered by accumulation
  // this task delayed to a negedge clk to avoid updating and checking regs at the same time
  virtual task process_alert_sig(int alert_i, bit is_int_err,
                                 local_alert_type_e local_alert_type = LocalAlertIntFail);
    fork
      begin
        cfg.clk_rst_vif.wait_n_clks(1);
        if (!under_reset) begin
          bit [TL_DW-1:0] intr_en, class_ctrl;
          bit [NUM_ALERT_CLASS_MSB:0] class_i;
          if (!is_int_err) begin
            class_i = cfg.get_alert_class_shadowed(alert_i).get_mirrored_value();
            if (!get_alert_cause(alert_i).predict(1)) begin
              `uvm_fatal("prediction_failed",
                         $sformatf("Failed to predict value for %0s.",
                                   get_alert_cause(alert_i).get_name()))
            end
            if (cfg.en_cov) begin
              cov.alert_cause_cg.sample(alert_i, class_i);
            end
          end else begin
            class_i = cfg.get_loc_alert_class_shadowed(local_alert_type).get_mirrored_value();
            if (!get_loc_alert_cause(local_alert_type).predict(1, UVM_PREDICT_READ)) begin
              `uvm_fatal("prediction_failed",
                         $sformatf("Failed to predict value for %0s.",
                                   get_loc_alert_cause(local_alert_type).get_name()))
            end
            if (local_alert_type inside {LocalAlertPingFail, LocalAlertIntFail}) begin
              if (cfg.en_cov) begin
                cov.alert_loc_alert_cause_cg.sample(local_alert_type, alert_i, class_i);
              end
            end else begin
              // Check the local alert type equals to the ones defined in the CG:
              `DV_CHECK(local_alert_type inside {LocalEscPingFail, LocalEscIntFail})
              if (cfg.en_cov) begin
                cov.esc_loc_alert_cause_cg.sample(local_alert_type, alert_i, class_i);
              end
            end
          end
          // Check to ensure alert_i and class_i is within bounds
          `DV_CHECK(alert_i < NUM_ALERTS && class_i < NUM_ALERT_CLASSES)

          intr_state_field = intr_state_fields[class_i];
          void'(intr_state_field.predict(.value(1), .kind(UVM_PREDICT_READ)));
          intr_en = cfg.get_intr_enable().get_mirrored_value();

          // calculate escalation
          class_ctrl = cfg.get_class_ctrl(cfg.m_class_names[class_i]).get_mirrored_value();
          `uvm_info(`gfn, $sformatf("class %0d is triggered, class ctrl=%0h, under_esc=%0b",
                                    class_i, class_ctrl, under_esc_classes[class_i]), UVM_DEBUG)
          // if class escalation is enabled, add alert to accumulation count
          if (class_ctrl[AlertClassCtrlEn] &&
              (class_ctrl[AlertClassCtrlEnE3:AlertClassCtrlEnE0] > 0)) begin
            alert_accum_cal(class_i);
          end

          // according to issue #841, interrupt will have one clock cycle delay
          // add an extra cycle for synchronizers from clk_edn to clk
          cfg.clk_rst_vif.wait_n_clks(1);
          if (!under_reset && (cfg.intr_vif.pins[class_i] !== intr_en[class_i])) begin
            `uvm_error(get_full_name(),
                       $sformatf({"Unexpected interrupt value in cfg.intr_vif.pins[%0d]: ",
                                  "saw %0d, but expected %0d. ",
                                  "(is_int_err = %0b, local_alert_type = %0p)"},
                                 class_i, cfg.intr_vif.pins[class_i], intr_en[class_i],
                                 is_int_err, local_alert_type))
          end
          if (!under_intr_classes[class_i] && intr_en[class_i]) under_intr_classes[class_i] = 1;
        end
      end
    join_none
  endtask

  // calculate alert accumulation count per class, if accumulation exceeds the threshold,
  // and if current class is not under escalation, then predict escalation
  // note: if more than one alerts triggered on the same clk cycle, only accumulates one
  virtual function void alert_accum_cal(int class_i);
    bit [TL_DW-1:0] accum_thresh;
    realtime curr_time = $realtime();
    accum_thresh = get_class_accum_thresh(cfg.m_class_names[class_i]).get_mirrored_value();
    if (curr_time != last_triggered_alert_per_class[class_i] && !cfg.under_reset) begin
      last_triggered_alert_per_class[class_i] = curr_time;
      // avoid accum_cnt saturate
      if (accum_cnter_per_class[class_i] < 'hffff) begin
        accum_cnter_per_class[class_i] += 1;
        if (accum_cnter_per_class[class_i] > accum_thresh && !under_esc_classes[class_i]) begin
          predict_esc(class_i);
        end
      end
    end
    `uvm_info(`gfn,
              $sformatf("alert_accum: class=%0d, alert_cnt=%0d, thresh=%0d, under_esc=%0b",
              class_i, accum_cnter_per_class[class_i], accum_thresh,
              under_esc_classes[class_i]), UVM_DEBUG)
  endfunction

  // if clren register is disabled, predict escalation signals by setting the corresponding
  // under_esc_classes bit based on class_ctrl's lock bit
  virtual function void predict_esc(int class_i);
    string class_name = cfg.m_class_names[class_i];
    bit [TL_DW-1:0] class_ctrl = cfg.get_class_ctrl(class_name).get_mirrored_value();
    if (class_ctrl[AlertClassCtrlLock]) begin
      void'(cfg.get_class_clr_regwen(class_name).predict(0));
    end
    under_esc_classes[class_i] = 1;
  endfunction

  // check if escalation signal's duration length is correct
  virtual function void check_esc_signal(int cycle_cnt, int esc_sig_i);
    int class_a = cfg.get_class_ctrl("a").get_mirrored_value();
    int class_b = cfg.get_class_ctrl("b").get_mirrored_value();
    int class_c = cfg.get_class_ctrl("c").get_mirrored_value();
    int class_d = cfg.get_class_ctrl("d").get_mirrored_value();
    int sig_index = AlertClassCtrlEnE0+esc_sig_i;
    bit [NUM_ALERT_CLASSES-1:0] select_class = {class_d[sig_index], class_c[sig_index],
                                                class_b[sig_index], class_a[sig_index]};


    // Only compare the escalation signal length if exactly one class is assigned to this signal.
    // Otherwise scb cannot predict the accurate cycle length if multiple classes are merged.
    if ($countones(select_class) == 1) begin
      uvm_reg phase_cyc_reg;
      int     class_i, phase, exp_cycle;

      // Find the class that triggers the escalation, and find which phase the escalation signal is
      // reflecting.
      for (class_i = 0; class_i < NUM_ALERT_CLASSES; class_i++) begin
        if (select_class[class_i] == 1) begin
          phase = cfg.get_class_ctrl(cfg.m_class_names[class_i]).get_mirrored_value();
          break;
        end
      end

      phase         = phase[(AlertClassCtrlMapE0 + esc_sig_i * 2) +: 2];
      phase_cyc_reg = cfg.get_class_phase_cyc(cfg.m_class_names[class_i], phase);
      exp_cycle     = phase_cyc_reg.get_mirrored_value() + 1;

      // Minimal phase length is 2 cycles.
      if (exp_cycle < 2) exp_cycle = 2;

      `uvm_info(`gfn,
                $sformatf("esc_signal_%0d, esc phase %0d, esc class %0d",
                          esc_sig_i, phase, class_i),
                UVM_HIGH);

      // If the escalation signal is interrupted by reset or esc_clear, we expect the signal length
      // to be shorter than the phase_cycle_length.
      if (cfg.under_reset || under_esc_classes[class_i] == 0) begin
        `DV_CHECK_LE(cycle_cnt, exp_cycle)
      end else begin
        `DV_CHECK_EQ(cycle_cnt, exp_cycle)
      end
      if (cfg.en_cov) cov.esc_sig_length_cg.sample(esc_sig_i, cycle_cnt);
    end
    esc_sig_class[esc_sig_i] = 0;
  endfunction

  virtual task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);
    dv_base_reg    dv_base_csr;
    bit            do_read_check   = 1'b1;
    bit            write           = item.is_write();
    uvm_reg_addr_t csr_addr = {item.a_addr[TL_AW-1:2], 2'b00};
    uvm_reg        csr = cfg.ral_models[ral_name].get_default_map().get_reg_by_offset(csr_addr);

    if (csr == null) begin
      // we hit an oob addr - expect error response and return
      `DV_CHECK_EQ(item.d_error, 1'b1)
      return;
    end

    `downcast(dv_base_csr, csr)

    if (channel == AddrChannel) begin
      // if incoming access is a write to a valid csr, then make updates right away
      if (write) begin
        string csr_name = csr.get_name();
        void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask)));
        // process the csr req
        // for write, update local variable and fifo at address phase
        case (csr_name)
          // add individual case item for each csr
          "intr_test": begin
            uvm_reg         intr_state = cfg.ral.get_reg_by_name("intr_state");
            bit [TL_DW-1:0] intr_state_exp;

            if (intr_state == null) `uvm_fatal("no_reg", "Cannot get intr_state register.")

            intr_state_exp = intr_state.get_mirrored_value() | item.a_data;

            if (cfg.en_cov) begin
              bit [TL_DW-1:0] intr_en = cfg.get_intr_enable().get_mirrored_value();
              for (int i = 0; i < NUM_ALERT_CLASSES; i++) begin
                cov.intr_test_cg.sample(i, item.a_data[i], intr_en[i], intr_state_exp[i]);
              end
            end
            if (!intr_state.predict(intr_state_exp)) begin
              `uvm_fatal("prediction_failed", "Failed to predict intr_state register.")
            end
          end
          // disable intr_enable or clear intr_state will clear the interrupt timeout cnter
          "intr_state": begin
            fork
              begin
                // after interrupt is set, it needs one clock cycle to update the value and stop
                // the intr_timeout counter
                cfg.clk_rst_vif.wait_clks(1);
                if (!cfg.under_reset) begin
                  foreach (under_intr_classes[i]) begin
                    if (item.a_data[i]) begin
                      under_intr_classes[i] = 0;
                      clr_esc_under_intr[i] = 0;
                      if (!under_esc_classes[i]) state_per_class[i] = EscStateIdle;
                    end
                  end
                  void'(csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE),
                                    .be(item.a_mask)));
                end
              end
            join_none
          end
          "intr_enable": begin
            foreach (under_intr_classes[i]) begin
              if (item.a_data[i] == 0) under_intr_classes[i] = 0;
            end
          end
          "classa_clr_shadowed": on_class_clr_shadowed_write(0);
          "classb_clr_shadowed": on_class_clr_shadowed_write(1);
          "classc_clr_shadowed": on_class_clr_shadowed_write(2);
          "classd_clr_shadowed": on_class_clr_shadowed_write(3);
          "ping_timer_en_shadowed": begin
            if (shadowed_reg_wr_completed(dv_base_csr) &&
                item.a_data &&
                get_ping_timer_regwen().get_mirrored_value()) begin
              ping_timer_en = 1;
            end
          end
         "alert_test", "ping_timeout_cyc_shadowed", "ping_timer_regwen": begin
            // Do nothing. Already auto update mirrored value.
          end
          default: begin
            // The following regs only need to auto update mirrored value.
            if (!uvm_re_match("*alert_en_shadowed*", csr_name) ||
                !uvm_re_match("*alert_class_shadowed*", csr_name) ||
                !uvm_re_match("class*_ctrl_shadowed", csr_name) ||
                !uvm_re_match("class*_crashdump_trigger_shadowed", csr_name) ||
                !uvm_re_match("class*_phase*_cyc_shadowed", csr_name) ||
                !uvm_re_match("class*_timeout_cyc_shadowed", csr_name) ||
                !uvm_re_match("class*_accum_thresh_shadowed", csr_name) ||
                !uvm_re_match("class*_clr_regwen", csr_name) ||
                !uvm_re_match("class*_regwen", csr_name) ||
                !uvm_re_match("*alert_regwen_*", csr_name)) begin
            end else begin
              `uvm_fatal(`gfn, $sformatf("invalid csr: %0s", csr.get_full_name()))
            end
          end
        endcase
      end
    end

    // process the csr req
    // for read, update prediction at address phase and compare at data phase

    if (!write) begin
      // On reads, if do_read_check, is set, then check mirrored_value against item.d_data
      if (channel == DataChannel) begin
        if (cfg.en_cov) begin
          if (csr.get_name() == "intr_state") begin
            bit [TL_DW-1:0] intr_en = cfg.get_intr_enable().get_mirrored_value();
            for (int i = 0; i < NUM_ALERT_CLASSES; i++) begin
              cov.intr_cg.sample(i, intr_en[i], item.d_data[i]);
              cov.intr_pins_cg.sample(i, cfg.intr_vif.pins[i]);
            end
          end else begin
            for (int i = 0; i < NUM_ALERT_CLASSES; i++) begin
              if (csr.get_name() == $sformatf("class%s_accum_cnt", cfg.m_class_names[i])) begin
                cov.accum_cnt_cg.sample(i, item.d_data);
              end
            end
          end
        end
        if (csr.get_name == "intr_state") begin
          `DV_CHECK_EQ(intr_state_val, item.d_data, $sformatf("reg name: %0s", "intr_state"))
          do_read_check = 0;
        end
        if (do_read_check) begin
          `DV_CHECK_EQ(csr.get_mirrored_value(), item.d_data,
                       $sformatf("reg name: %0s", csr.get_full_name()))
        end
        void'(csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ)));
      end else begin
        // predict in address phase to avoid the register's value changed during the read
        for (int i = 0; i < NUM_ALERT_CLASSES; i++) begin
          string class_pfx = $sformatf("class%0s", cfg.m_class_names[i]);

          if (csr.get_name() == $sformatf("%0s_esc_cnt", class_pfx)) begin
            void'(csr.predict(.value(intr_cnter_per_class[i]), .kind(UVM_PREDICT_READ)));
          end else if (csr.get_name() == $sformatf("%0s_accum_cnt", class_pfx)) begin
            void'(csr.predict(.value(accum_cnter_per_class[i]), .kind(UVM_PREDICT_READ)));
          end else if (csr.get_name() == $sformatf("%0s_state", class_pfx)) begin
            void'(csr.predict(.value(state_per_class[i]), .kind(UVM_PREDICT_READ)));
          end
        end
        if (csr.get_name() == "intr_state") intr_state_val = csr.get_mirrored_value();
      end
    end
  endtask

  // Update the model for the indexed class after a write to its class*_clr_shadowed register
  //
  // Since the scoreboard calls this for both writes to the shadowed register, it can return
  // immediately if the register has just become staged.
  local function void on_class_clr_shadowed_write(int unsigned class_idx);
    string      class_name = cfg.m_class_names[class_idx];
    uvm_reg     regwen = cfg.get_class_clr_regwen(class_name);
    uvm_reg     csr_base = get_class_clr(class_name);
    dv_base_reg csr;

    if (!$cast(csr, csr_base)) begin
      `uvm_fatal("base_csr",
                 $sformatf("The register %0s is not a dv_base_reg.", csr_base.get_name()))
    end

    if (!csr.is_staged() && regwen.get_mirrored_value()) begin
      // Trigger a process that clears accum and escalation counters for the class. This process
      // consumes time and lasts two cycles.
      fork
        clr_reset_esc_class(class_idx);
      join_none
    end
  endfunction

  virtual task check_ping_timer();
    int num_checked_pings;
    fork begin : isolation_fork
      forever begin
        wait (ping_timer_en == 1);
        fork
          begin
            wait (cfg.under_reset == 1);
            ping_timer_en = 0;
            num_checked_pings = 0;
          end
          begin
            check_ping_triggered_cycles();
            num_checked_pings++;
            if (cfg.en_cov) cov.num_checked_pings_cg.sample(num_checked_pings);
          end
        join_any
        disable fork;
      end
    end join
  endtask

  // This task checks if pings are triggered within the expected time.
  //
  // The ping timer is 16 bits so ideally we should see alert_ping -> esc_ping ->  alert_ping ...
  // with the max length of 16'hFFFF clock cycle. However alert_ping is randomly selected so we
  // can not guarantee the random alert index is valid (exists), enabled, and locked.
  // However, esc ping timer should are always expected to trigger.
  // So the max wait time is 'hFFFF*2.
  // This task also used the probed design signal instead of detected ping requests from monitor.
  // Because if esc ping request and real esc request come at the same time, design will ignore the
  // ping requests. But the probed signal will still set to 1.
  virtual task check_ping_triggered_cycles();
    int ping_wait_cycs;

    while (ping_wait_cycs <= MAX_PING_WAIT_CYCLES * 2) begin
      int unsigned alert_id;

      if (cfg.has_alert_ping_req(alert_id)) begin
        if (cfg.en_cov) begin
          cov.ping_with_lpg_cg_wrap[alert_id].alert_ping_with_lpg_cg.sample(
              cfg.alert_host_cfg[alert_id].en_alert_lpg);
        end
        break;
      end

      if (cfg.has_esc_ping_req()) break;

      cfg.clk_rst_vif.wait_clks(1);
      ping_wait_cycs++;
    end

    if (ping_wait_cycs > MAX_PING_WAIT_CYCLES * 2) begin
      `uvm_error(`gfn, "Timeout occured waiting for a ping.");
    end
    if (cfg.en_cov) cov.cycles_between_pings_cg.sample(ping_wait_cycs);

    // Wait for ping request to finish to avoid infinite loop.
    cfg.wait_no_ping_req();
  endtask

  virtual task check_crashdump();
    forever begin
      wait (cfg.under_reset == 0 && cfg.en_scb == 1);
      @(cfg.crashdump_vif.pins) begin
        alert_handler_pkg::alert_crashdump_t crashdump_val =
            alert_handler_pkg::alert_crashdump_t'(cfg.crashdump_vif.sample());

        // Wait two negedge clock cycles to make sure csr mirrored values are updated.
        `DV_SPINWAIT_EXIT(cfg.clk_rst_vif.wait_n_clks(2);, wait (cfg.under_reset == 1);)

        if (!cfg.under_reset) begin
          // If crashdump reached the phase programmed at `crashdump_trigger_shadowed`,
          // `crashdump_o` value should keep stable until reset.
          if (crashdump_triggered) begin
            `uvm_fatal(`gfn,
                       "crashdump value should not change after trigger condition is reached!")
          end

          foreach (crashdump_val.class_esc_state[i]) begin
            uvm_reg_data_t trig_val;
            trig_val = get_class_crashdump_trigger(cfg.m_class_names[i]).get_mirrored_value();
            if (crashdump_val.class_esc_state[i] == (trig_val + 3'b100)) begin
              crashdump_triggered[i] = 1;
              if (cfg.en_cov) cov.crashdump_trigger_cg.sample(trig_val);
              break;
             end
          end

          // Check that the value that came from the crashdump reflects the alert_cause and
          // loc_alert_cause registers that we have predicted in the register model.
          for (int i = 0; i < NUM_ALERTS; i++) begin
            if (crashdump_val.alert_cause[i] != get_alert_cause(i).get_mirrored_value()) begin
              `uvm_error(get_full_name(),
                         $sformatf({"Register/crashdump mismatch. alert_cause[%0d] is ",
                                    "0x%0h in the crashdump and 0x%0h in the register model."},
                                   i,
                                   crashdump_val.alert_cause[i],
                                   get_alert_cause(i).get_mirrored_value()))
            end
          end
          for (int i = 0; i < NUM_LOCAL_ALERTS; i++) begin
            if (crashdump_val.loc_alert_cause[i] !=
                get_loc_alert_cause(i).get_mirrored_value()) begin
              `uvm_error(get_full_name(),
                         $sformatf({"Register/crashdump mismatch. loc_alert_cause[%0d] is ",
                                    "0x%0h in the crashdump and 0x%0h in the register model."},
                                   i,
                                   crashdump_val.loc_alert_cause[i],
                                   get_loc_alert_cause(i).get_mirrored_value()))
            end
          end
        end
      end
    end
  endtask

  // a counter to count how long each interrupt pins stay high until it is being reset
  // if counter exceeds threshold, call predict_esc() function to calculate related esc
  virtual task check_intr_timeout_trigger_esc();
    for (int i = 0; i < NUM_ALERT_CLASSES; i++) begin
      fork
        automatic int class_i = i;
        begin : intr_sig_counter
          forever @(under_intr_classes[class_i] && !under_esc_classes[class_i]) begin
            fork
              begin
                bit [TL_DW-1:0] timeout_cyc, class_ctrl;
                // if escalation cleared but interrupt not cleared, wait one more clk cycle for the
                // FSM to reset to Idle, then start to count
                if (clr_esc_under_intr[class_i]) cfg.clk_rst_vif.wait_n_clks(1);
                clr_esc_under_intr[class_i] = 0;
                // wait a clk for esc signal to go high
                cfg.clk_rst_vif.wait_n_clks(1);
                class_ctrl = cfg.get_class_ctrl(cfg.m_class_names[class_i]).get_mirrored_value();
                if (class_ctrl[AlertClassCtrlEn] &&
                    class_ctrl[AlertClassCtrlEnE3:AlertClassCtrlEnE0] > 0) begin
                  intr_cnter_per_class[class_i] = 1;
                  `uvm_info(`gfn, $sformatf("Class %0d start counter", class_i), UVM_HIGH)
                  timeout_cyc = get_class_timeout_cyc(class_i).get_mirrored_value();
                  if (timeout_cyc > 0) begin
                    state_per_class[class_i] = EscStateTimeout;
                    while (under_intr_classes[class_i]) begin
                      @(cfg.clk_rst_vif.cbn);
                      if (intr_cnter_per_class[class_i] >= timeout_cyc) begin
                        predict_esc(class_i);
                        if (cfg.en_cov) cov.intr_timeout_cnt_cg.sample(class_i, timeout_cyc);
                      end
                      intr_cnter_per_class[class_i] += 1;
                      `uvm_info(`gfn, $sformatf("counter_%0d value: %0d", class_i,
                                intr_cnter_per_class[class_i]), UVM_HIGH)
                    end
                  end
                  intr_cnter_per_class[class_i] = 0;
                end
              end
              begin
                wait(under_esc_classes[class_i]);
              end
            join_any
            disable fork;
          end // end forever
        end
      join_none
    end
  endtask

  // two counters for phases cycle length and esc signals cycle length
  // phase cycle cnter: "intr_cnter_per_class" is used to check "esc_cnt" registers
  virtual task esc_phase_signal_cnter();
    for (int i = 0; i < NUM_ALERT_CLASSES; i++) begin
      fork
        automatic int class_i = i;
        begin : esc_phases_counter
          forever @(!cfg.under_reset && under_esc_classes[class_i]) begin
            fork
              begin : inc_esc_cnt
                for (int phase_i = 0; phase_i < NUM_ESC_PHASES; phase_i++) begin
                  int phase_thresh = `gmv(reg_esc_phase_cycs_per_class_q[class_i][phase_i]);
                  bit [TL_DW-1:0] class_ctrl;
                  int enabled_sig_q[$];

                  class_ctrl = cfg.get_class_ctrl(cfg.m_class_names[class_i]).get_mirrored_value();
                  for (int sig_i = 0; sig_i < NUM_ESC_SIGNALS; sig_i++) begin
                    if (class_ctrl[sig_i*2+7 -: 2] == phase_i && class_ctrl[sig_i+2]) begin
                      enabled_sig_q.push_back(sig_i);
                    end
                  end
                  if (under_esc_classes[class_i]) begin
                    intr_cnter_per_class[class_i] = 1;
                    state_per_class[class_i] = esc_state_e'(phase_i + int'(EscStatePhase0));
                    cfg.clk_rst_vif.wait_n_clks(1);
                    while (under_esc_classes[class_i] &&
                           intr_cnter_per_class[class_i] < phase_thresh) begin
                      intr_cnter_per_class[class_i]++;
                      cfg.clk_rst_vif.wait_n_clks(1);
                    end
                    foreach (enabled_sig_q[i]) begin
                      int index = enabled_sig_q[i];
                      if (esc_sig_class[index] == (class_i + 1)) esc_signal_release[index] = 1;
                    end
                  end
                end  // end four phases
                intr_cnter_per_class[class_i] = 0;
                if (under_esc_classes[class_i]) state_per_class[class_i] = EscStateTerminal;
              end
              begin
                wait(cfg.under_reset || !under_esc_classes[class_i]);
                if (!under_esc_classes[class_i]) begin
                  // wait 1 clk cycles until esc_signal_release is set
                  cfg.clk_rst_vif.wait_clks(1);
                end
              end
            join_any
            disable fork;
            intr_cnter_per_class[class_i] = 0;
          end // end forever
        end
      join_none
    end
  endtask

  // release escalation signal after one clock cycle, to ensure happens at the end of the clock
  // cycle, waited 1 clks here
  virtual task release_esc_signal();
    for (int i = 0; i < NUM_ESC_SIGNALS; i++) begin
      fork
        automatic int sig_i = i;
        forever @ (esc_signal_release[sig_i]) begin
          cfg.clk_rst_vif.wait_clks(1);
          esc_sig_class[sig_i] = 0;
          esc_signal_release[sig_i] = 0;
        end
      join_none
    end
  endtask

  virtual function void reset(string kind = "HARD");
    super.reset(kind);
    under_intr_classes    = '{default:0};
    intr_cnter_per_class  = '{default:0};
    under_esc_classes     = '{default:0};
    esc_sig_class         = '{default:0};
    accum_cnter_per_class = '{default:0};
    state_per_class       = '{default:EscStateIdle};
    clr_esc_under_intr    = 0;
    crashdump_triggered   = 0;
    ping_timer_en         = 0;
    last_triggered_alert_per_class = '{default:$realtime};

    // Update our tracked lpg states so that they are all disabled again (no longer in a low power
    // mode).
    for (int unsigned i = 0; i < cfg.m_lpg_agent_cfg.vif.num_lpgs; i++) begin
      cfg.set_lpg_state(i, 0, 0);
    end

    cfg.clear_alert_ping_reqs();
    cfg.clear_esc_ping_reqs();
  endfunction

  // clear accumulative counters, and escalation counters if they are under escalation
  // interrupt timeout counters cannot be cleared by this
  task clr_reset_esc_class(int i);
    fork
      automatic int class_i = i;
      begin
        cfg.clk_rst_vif.wait_clks(1);
        crashdump_triggered[class_i] = 0;
        if (under_intr_classes[class_i]) begin
          if (cfg.en_cov) cov.clear_intr_cnt_cg.sample(class_i);
          clr_esc_under_intr[class_i] = 1;
        end
        if (under_esc_classes [class_i]) begin
          if (cfg.en_cov) cov.clear_esc_cnt_cg.sample(class_i);
          intr_cnter_per_class[class_i] = 0;
        end
        under_esc_classes[class_i] = 0;
        cfg.clk_rst_vif.wait_n_clks(1);
        last_triggered_alert_per_class[class_i] = $realtime;
        accum_cnter_per_class[class_i] = 0;
        if (state_per_class[class_i] != EscStateTimeout) state_per_class[class_i] = EscStateIdle;
      end
    join_none
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
  endfunction

  function bit shadowed_reg_wr_completed(dv_base_reg dv_base_reg);
    return (!dv_base_reg.is_staged() && !dv_base_reg.get_shadow_update_err());
  endfunction

  // Get the requested register from the alert_cause multireg
  local function uvm_reg get_alert_cause(int unsigned idx);
    return cfg.get_multireg_register("alert_cause", idx);
  endfunction

  // Get the requested register from the loc_alert_cause multireg
  local function uvm_reg get_loc_alert_cause(int unsigned idx);
    return cfg.get_multireg_register("loc_alert_cause", idx);
  endfunction

  // Get the clr_shadowed register for the given class
  local function uvm_reg get_class_clr(string class_name);
    return cfg.get_class_reg("clr_shadowed", class_name);
  endfunction

  // Get the crashdump_trigger_shadowed register for the given class
  local function uvm_reg get_class_crashdump_trigger(string class_name);
    return cfg.get_class_reg("crashdump_trigger_shadowed", class_name);
  endfunction

  // Get the accum_thresh register for the given class
  local function uvm_reg get_class_accum_thresh(string class_name);
    return cfg.get_class_reg("accum_thresh_shadowed", class_name);
  endfunction

  // Get the timeout_cyc register for the given class
  local function uvm_reg get_class_timeout_cyc(string class_name);
    return cfg.get_class_reg("timeout_cyc_shadowed", class_name);
  endfunction

  // Get the ping_timeout_cyc_shadowed register
  function uvm_reg get_ping_timeout_cyc_shadowed();
    uvm_reg register = cfg.ral.get_reg_by_name("ping_timeout_cyc_shadowed");
    if (register == null) `uvm_fatal("no_reg", "Cannot find ping_timeout_cyc_shadowed register.")
    return register;
  endfunction

  // Get the ping_timer_regwen register
  function uvm_reg get_ping_timer_regwen();
    uvm_reg register = cfg.ral.get_reg_by_name("ping_timer_regwen");
    if (register == null) `uvm_fatal("no_reg", "Cannot find ping_timer_regwen register.")
    return register;
  endfunction

endclass
