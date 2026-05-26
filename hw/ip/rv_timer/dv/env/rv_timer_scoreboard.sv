// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class rv_timer_scoreboard extends cip_base_scoreboard #(.CFG_T (rv_timer_env_cfg),
                                                        .RAL_T (rv_timer_reg_block),
                                                        .COV_T (rv_timer_env_cov));

  `uvm_component_utils(rv_timer_scoreboard)
  `uvm_component_new

  // local variables
  local uint64 prescale[NUM_HARTS];
  local uint64 step[NUM_HARTS];
  local uint64 timer_val[NUM_HARTS];
  local uint64 compare_val[NUM_HARTS][NUM_TIMERS];
  local uint   num_clks[NUM_HARTS][NUM_TIMERS];
  local bit [NUM_HARTS-1:0][NUM_TIMERS-1:0] en_timers;
  local bit [NUM_HARTS-1:0][NUM_TIMERS-1:0] en_timers_prev;
  local bit [NUM_HARTS-1:0][NUM_TIMERS-1:0] en_interrupt;
  local bit [NUM_HARTS-1:0][NUM_TIMERS-1:0] ignore_period;
  local bit [NUM_HARTS-1:0] num_clk_update_due;
  local bit ctimecmp_update_on_fly;

  // expected values
  local uint intr_status_exp[NUM_HARTS];

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    compute_and_check_interrupt();
  endtask

  // Return true if str matches the pattern <base_name>%d and write the index to idx
  //
  // This uses $sscanf if str starts with base_name. Some EDA tools spit out a runtime warning
  // message if this fails, so it's better not to do something like
  //
  //    is_indexed_register("foobar0", "foo", idx)
  local function bit is_indexed_register(string str, string base_name, output int unsigned idx);
    int unsigned base_size = base_name.len();
    if (str.len() < base_size) return 0;
    if (str.substr(0, base_size - 1) != base_name) return 0;
    return $sscanf(str.substr(base_size, str.len() - 1), "%d", idx);
  endfunction

  // Return true if str matches the pattern <base_name>%d_%d and write the indices to idx0 and idx1.
  //
  // This uses $sscanf if str starts with base_name. Some EDA tools spit out a runtime warning
  // message if this fails, so it's better not to do something like
  //
  //    is_indexed_register2("foobar0", "foo", idx0, idx1)
  local function bit is_indexed_register2(string              str,
                                          string              base_name,
                                          output int unsigned idx0,
                                          output int unsigned idx1);
    int unsigned base_size = base_name.len();
    string       suffix;

    if (str.len() < base_size) return 0;
    if (str.substr(0, base_size - 1) != base_name) return 0;

    // Annoyingly, $sscanf(xxx, "%d_%d", idx0, idx1) doesn't work here, because "_" is a valid
    // number separator is SystemVerilog (the 123_456 literal is the same thing as 123456).
    // Tokenizing manually is tricky, so we cheat and make a version of str where "_" has been
    // replaced with " ".
    suffix = str.substr(base_size, str.len() - 1);
    for (int unsigned pos = 0; pos < suffix.len(); pos++) begin
      suffix[pos] = (suffix[pos] == "_") ? " " : suffix[pos];
    end

    return ($sscanf(suffix, "%d %d", idx0, idx1) == 2);
  endfunction

  virtual task process_tl_access(tl_seq_item item, tl_channels_e channel, string ral_name);
    string       csr_name;
    int unsigned hart_idx, timer_idx;
    bit          write = item.is_write();

    uvm_reg_addr_t csr_addr = cfg.ral_models[ral_name].get_word_aligned_addr(item.a_addr);
    uvm_reg csr = cfg.ral_models[ral_name].get_default_map().get_reg_by_offset(csr_addr);

    if (csr == null) begin
      `uvm_fatal(`gfn, $sformatf("Access unexpected addr 0x%0h", csr_addr))
    end

    csr_name = csr.get_name();

    if (!write && channel == AddrChannel) begin
      // If this is a read of an intr_status register, update the prediction in the uvm_reg to match
      // intr_status_exp (which has contains predictions of when interrupts will be asserted).
      if (is_indexed_register(csr_name, "intr_state", hart_idx)) begin
        if (!ignore_period[hart_idx]) begin
          if (!csr.predict(.value(intr_status_exp[hart_idx]), .kind(UVM_PREDICT_READ))) begin
            `uvm_error(get_full_name(), $sformatf("Failed to predict %0s", csr_name))
          end
        end
      end
    end

    // grab write transactions from address channel; grab completed transactions from data channel

    // if incoming access is a write to a valid csr, then make updates right away
    if (write && channel == AddrChannel) begin
      if (!csr.predict(.value(item.a_data), .kind(UVM_PREDICT_WRITE), .be(item.a_mask))) begin
        `uvm_error(get_full_name(), $sformatf("Failed to predict %0s", csr_name))
      end

      if (csr_name == "ctrl") begin
        // This is a write to the ctrl register (a packed multireg with one bit per hart). Update
        // en_timers, our prediction of which timers are enabled. This is in the same format.
        en_timers = cfg.ral.ctrl[0].active.get_mirrored_value();

        // Sample all timers active coverage for each hart
        if (cfg.en_cov) cov.ctrl_reg_cov_obj[hart_idx].timer_active_cg.sample(en_timers[hart_idx]);
      end else if (is_indexed_register(csr_name, "cfg", hart_idx)) begin
        // This is a write to the cfg register for the hart with index hart_idx
        prescale[hart_idx] = csr.get_field_by_name("prescale").get_mirrored_value();
        step[hart_idx]     = csr.get_field_by_name("step").get_mirrored_value();
      end else if (is_indexed_register(csr_name, "timer_v_lower", hart_idx)) begin
        // This is a write to the lower 32 bits of the timer for the hart with index hart_idx
        timer_val[hart_idx][31:0] = csr.get_mirrored_value();
        num_clk_update_due[hart_idx] = 1;
      end else if (is_indexed_register(csr_name, "timer_v_upper", hart_idx)) begin
        // This is a write to the upper 32 bits of the timer for the hart with index hart_idx
        timer_val[hart_idx][63:32] = csr.get_mirrored_value();
        num_clk_update_due[hart_idx] = 1;
      end else if (is_indexed_register2(csr_name, "compare_lower", hart_idx, timer_idx)) begin
        // This is a write to the lower 32 bits of the comparator with index timer_idx in the hart
        // with index hart_idx.
        compare_val[hart_idx][timer_idx][31:0] = csr.get_mirrored_value();
        if (en_timers[hart_idx][timer_idx] == 0) begin
          // Reset the interrupt when mtimecmp is updated and timer is not active
          intr_status_exp[hart_idx][timer_idx] = 0;
          if (cfg.en_cov) cov.sample_intr_pin(timer_idx, 0);
        end else begin
          // intr stays sticky if timer is active
          ctimecmp_update_on_fly = 1;
          if (cfg.en_cov) cov.sample_intr_pin(timer_idx, intr_status_exp[hart_idx][timer_idx]);
        end
      end else if (is_indexed_register2(csr_name, "compare_upper", hart_idx, timer_idx)) begin
        // This is a write to the upper 32 bits of the comparator with index timer_idx in the hart
        // with index hart_idx.
        compare_val[hart_idx][timer_idx][63:32] = csr.get_mirrored_value();
        if (en_timers[hart_idx][timer_idx] == 0) begin
          // Reset the interrupt when mtimecmp is updated and timer is not active
          intr_status_exp[hart_idx][timer_idx] = 0;
          if (cfg.en_cov) cov.sample_intr_pin(timer_idx, 0);
        end else begin
          // intr stays sticky if timer is active
          ctimecmp_update_on_fly = 1;
          if (cfg.en_cov) cov.sample_intr_pin(timer_idx, intr_status_exp[hart_idx][timer_idx]);
        end
      end else if (is_indexed_register(csr_name, "intr_enable", hart_idx)) begin
        // This is a write to the interrupt enable register for the hart with index hart_idx
        en_interrupt[hart_idx] = csr.get_mirrored_value();
      end else if (is_indexed_register(csr_name, "intr_state", hart_idx)) begin
        // This is a write to the interrupt status register for the hart with index hart_idx.
        //
        // The register is W1C
        for (int j = 0; j < NUM_TIMERS; j++) begin
          int full_timer_idx = hart_idx * NUM_TIMERS + j;
          if (item.a_data[j] == 1) begin
            if (en_timers[hart_idx][j] == 0) begin
              intr_status_exp[hart_idx][j] = 0;
            end
            if (cfg.en_cov) cov.sample_intr_pin(full_timer_idx, en_timers[hart_idx][j]);
          end
        end
      end else if (is_indexed_register(csr_name, "intr_test", hart_idx)) begin
        // This is a write to the interrupt test register for the hart with index hart_idx
        int unsigned intr_test_val = item.a_data;
        for (int j = 0 ; j < NUM_TIMERS; j++) begin
          int intr_pin_idx = hart_idx * NUM_TIMERS + j;
          if (intr_test_val[j]) intr_status_exp[hart_idx][j] = intr_test_val[j];
          //Sample intr_test coverage for each bit of test reg
          if (cfg.en_cov) cov.intr_test_cg.sample(intr_pin_idx,
                                                  intr_test_val[j],
                                                  en_interrupt[hart_idx][j],
                                                  intr_status_exp[hart_idx][j]);
        end
      end else begin
        `uvm_error(get_full_name(), $sformatf("Unrecognised CSR: %0s", csr.get_full_name()))
      end
    end

    if (channel == DataChannel) begin
      // Check all interrupts in DataChannel of every Read/Write except when ctimecmp updated
      // during timer active. This scenario is checked in base sequence by reading the intr_state.
      // Ignored checking here because sticky intr_pin update has one cycle delay.
      if (!ctimecmp_update_on_fly) check_interrupt_pin();
      ctimecmp_update_on_fly = 0;

      // On reads, check mirrored_value against item.d_data
      if (!write) begin
        bit reading_timer, is_upper;

        if (is_indexed_register(csr_name, "timer_v_lower", hart_idx)) begin
          reading_timer = 1;
        end if (is_indexed_register(csr_name, "timer_v_upper", hart_idx)) begin
          reading_timer = 1;
          is_upper = 1;
        end

        // If reading_timer is true then one of the two $sscanf calls above managed to get
        // hart_idx. Are we reading a timer that is enabled?
        if (reading_timer && en_timers[hart_idx]) begin
          // Since the timer is enabled, we don't check the value we read (since it's changing!) but
          // we do update our mirrored value.
          if (is_upper) timer_val[hart_idx][63:32] = item.d_data;
          else          timer_val[hart_idx][31:0]  = item.d_data;

          // If this is a read of the lower bits, update num_clks.
          if (!is_upper) num_clk_update_due[hart_idx] = 1;

          // Update our prediction of the register (based on the value we just read)
          if (!csr.predict(.value(item.d_data), .kind(UVM_PREDICT_READ))) begin
            `uvm_error(get_full_name(),
                       $sformatf("Failed to update prediction for %0s", csr.get_full_name()))
          end
        end else begin
          // Our register read is not of an enabled timer. As such, it is of a register whose value
          // we have predicted. Check the prediction matches.
          if (item.d_data != csr.get_mirrored_value()) begin
            `uvm_error(get_full_name(),
                       $sformatf({"Mismatch when reading %0s. ",
                                  "Register read returned 0x%0x but mirrored value was 0x%0x."},
                                 csr.get_full_name(),
                                 item.d_data,
                                 csr.get_mirrored_value()))
          end
        end
      end
    end
  endtask

  // Task : compute_and_check_interrupt
  // wait for expected # of clocks and check for interrupt state reg and pin
  virtual task compute_and_check_interrupt();
    bit [NUM_HARTS-1:0][NUM_TIMERS-1:0] reset_count;

    fork
      begin
        forever begin : compute_num_clks
          // calculate number of clocks required to have interrupt
          @(en_timers or num_clk_update_due);
          wait(under_reset == 0);
          foreach (en_timers[i, j]) begin
            uint64 mtime_diff = compare_val[i][j] - timer_val[i];
            num_clks[i][j] = ((mtime_diff / step[i]) +
                              ((mtime_diff % step[i]) != 0)) * (prescale[i] + 1) + 1;
          end
          // reset count if timer is enabled and num_clks got updated
          for (int i = 0; i < NUM_HARTS; i++) begin
            if (num_clk_update_due[i]) reset_count[i] = en_timers[i];
          end
          num_clk_update_due = '0;
        end // compute_num_clks
      end
    join_none

    forever begin : wait_for_interrupt
      @(en_timers or under_reset);
      wait(under_reset == 0);
      // fork a thread for enabled timer on all enabled hart
      foreach (en_timers[i, j]) begin
        automatic int a_i = i;
        automatic int a_j = j;
        fork
          if (en_timers[a_i][a_j] & !en_timers_prev[a_i][a_j]) begin
            fork
              begin
                uint64 count = 0;
                en_timers_prev[a_i][a_j] = 1'b1;
                forever begin
                  @cfg.clk_rst_vif.cb;
                  count = count + 1;
                  if (reset_count[a_i][a_j] == 1'b1) begin
                    count = 0;
                    reset_count[a_i][a_j] = 1'b0;
                  end
                  if (count >= num_clks[a_i][a_j]) break;
                end
                // enabling one clock cycle of ignore period
                ignore_period[a_i][a_j] = 1'b1;

                // If the step is set to 0, it means the counter is not incremented since the
                // counter evaluates as: count = count + step.
                // Also, if the count is not greater than the comparison value, skip the iteration
                // and wait until the step and/or timecmp/mtime are re-configured
                if ( !(step[a_i] == 0 && (compare_val[a_i][a_j] - timer_val[a_i]) > 0)) begin
                  `uvm_info(`gfn, $sformatf("Timer expired check for interrupt"), UVM_MEDIUM)
                  // Update exp val and predict it in read address_channel
                  intr_status_exp[a_i][a_j] = 1'b1;
                  `uvm_info(`gfn,
                            $sformatf("check_interrupt_pin#1 - intr_status_exp = %p",
                                      intr_status_exp),
                            UVM_MEDIUM)
                  check_interrupt_pin();
                  if (cfg.en_cov) begin
                    int timer_idx = a_i * NUM_TIMERS + a_j;
                    //Sample cfg coverage for each timer
                    cov.cfg_values_cov_obj[timer_idx].timer_cfg_cg.sample(step[a_i],
                                                                          prescale[a_i],
                                                                          timer_val[a_i],
                                                                          compare_val[a_i][a_j]);
                    //Sample toggle coverage for each prescale bit
                    for (int i = 0; i < 12; i++) begin
                      cov.rv_timer_prescale_values_cov_obj[a_i][i].sample(prescale[a_i][i]);
                    end
                  end
                  @cfg.clk_rst_vif.cb;
                  ignore_period[a_i][a_j] = 1'b0;
                  end // if ( !(step[a_i] == 0 && (compare_val[a_i][a_j] - timer_val[a_i]) > 0))
              end // if (en_timers[a_i][a_j] & !en_timers_prev[a_i][a_j])
              begin
                wait((en_timers[a_i][a_j] == 0) | (under_reset == 1));
              end
            join_any
            en_timers_prev[a_i][a_j] = 1'b0;
            // kill forked threads if timer disabled or interrupt occurred or under reset
            disable fork;
          end
        join_none
      end
    end // wait_for_interrupt
  endtask : compute_and_check_interrupt

  // task : check_interrupt_pin
  // check all interrupt output pins with expected intr state & pin enable
  // according to issue #841, interrupt will have one clock cycle delay
  task check_interrupt_pin();
    fork
      begin
        // store the `intr_status_exp` and `en_interrupt` values into an automatic local variable
        // in case the values are being updated during the one clock cycle wait.
        automatic uint stored_intr_status_exp[NUM_HARTS] = intr_status_exp;
        automatic bit [NUM_HARTS-1:0][NUM_TIMERS-1:0] stored_en_interrupt = en_interrupt;
        cfg.clk_rst_vif.wait_clks(1);
        if (!under_reset) begin
          for (int i = 0; i < NUM_HARTS; i++) begin
            for (int j = 0; j < NUM_TIMERS; j++) begin
              int intr_pin_idx = i * NUM_TIMERS + j;
              `DV_CHECK_CASE_EQ(cfg.intr_vif.sample_pin(.idx(intr_pin_idx)),
                                (stored_intr_status_exp[i][j] & stored_en_interrupt[i][j]))
              // Sample interrupt and interrupt pin coverage for each timer
              if (cfg.en_cov) begin
                cov.intr_cg.sample(intr_pin_idx, stored_en_interrupt[i][j],
                                   stored_intr_status_exp[i][j]);
                cov.intr_pins_cg.sample(intr_pin_idx, cfg.intr_vif.sample_pin(.idx(intr_pin_idx)));
              end
            end
          end
        end
      end
    join_none
  endtask

  virtual function void reset(string kind = "HARD");
    super.reset(kind);
    // reset the local values
    step            = '{default:1};
    prescale        = '{default:0};
    timer_val       = '{default:0};
    compare_val     = '{default:'1};
    en_timers       = '{default:0};
    en_interrupt    = '{default:0};
    intr_status_exp = '{default:0};
    ignore_period   = '{default:0};
    en_timers_prev  = '{default:0};
    ctimecmp_update_on_fly = 0;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
  endfunction

endclass
