// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class rv_timer_random_vseq extends rv_timer_base_vseq;
  `uvm_object_utils(rv_timer_random_vseq)
  `uvm_object_new

  rand bit [NUM_TIMERS-1:0] en_timers;
  rand bit [NUM_HARTS-1:0]  en_harts;

  rand uint64 timer_val[NUM_HARTS];
  rand uint64 compare_val[NUM_HARTS][NUM_TIMERS];
  rand bit    en_interrupt[NUM_HARTS][NUM_TIMERS];

  rand uint prescale[NUM_HARTS];
  rand uint step[NUM_HARTS];
  rand uint ticks[NUM_HARTS];
  rand bit  assert_reset;

  uint64 max_clks_until_expiry = 5_000;

  constraint assert_reset_c {
    (assert_reset == 1'b0);
  }

  constraint num_trans_c {
    if (cfg.smoke_test) num_trans == 1;
    else                num_trans inside {[1:6]};
  }

  // Enable at least 1 timer.
  constraint en_timers_c {
    (|en_timers == 1'b1);
  }

  // Enable at least 1 hart.
  constraint en_harts_c {
    (|en_harts == 1'b1);
  }

  // Prescaler must be less than max prescale for the enabled hart.
  constraint prescale_c {
    solve en_harts before prescale;
    foreach (prescale[i]) {
      if (en_harts[i]) {
        if (cfg.smoke_test) prescale[i] == 1;
        else                prescale[i] inside {[0:max_prescale]};
      } else {
        prescale[i] == 0;
      }
    }
  }

  // Step value must be less than max step for the enabled hart.
  constraint step_c {
    solve en_harts before step;
    foreach (step[i]) {
      if (en_harts[i]) {
        if (cfg.smoke_test) step[i] == 1;
        else                step[i] inside {[1:max_step]};
      } else {
        step[i] == 0;
      }
    }
  }

  // Ticks * prescale < max clks, to keep the simulated time within bounds.
  constraint ticks_c {
    solve prescale before ticks;
    foreach (ticks[i]) {
      if (en_harts[i]) {
        // For smoke test, timeout between 50 and 200 ticks.
        if (cfg.smoke_test) ticks[i] inside {[50:200]};
        else                (ticks[i] * (prescale[i] + 1)) <= max_clks_until_expiry;
      }
    }
  }

  // Timer expiry needs to occur within reasonable amount of time.
  constraint timer_exp_c {
    solve en_harts before compare_val;
    solve en_timers before compare_val;
    solve timer_val before compare_val;
    solve step before compare_val;
    solve ticks before compare_val;
    foreach (en_harts[i]) {
      foreach (en_timers[j]) {
        if (en_harts[i] && en_timers[j]) {
          compare_val[i][j] == timer_val[i] + step[i] * ticks[i];
        }
      }
    }
  }

  task pre_start();
    super.pre_start();
    // Check Scoreboard is enabled
    `DV_CHECK_EQ_FATAL(cfg.en_scb, 1'b1)
    num_trans.rand_mode(0);
  endtask

  // Repeatedly read the hart's intr_state register until its bits exactly equal the set of enabled
  // timers (en_timers), meaning that the right interrupts have been asserted.
  //
  // Exit if this happens or on a timeout (with the given timeout_ns) or if reset is asserted.
  task intr_state_spinwait_hart(int unsigned hart, int unsigned timeout_ns);
    // This flag gets set once timeout_ns nanoseconds have elapsed (which causes the repeated read
    // thread to finish)
    bit seen_timeout;

    // Pick a random gap between each read of the intr_state register
    int unsigned spinwait_delay_ns = pick_random_delay_ns();

    string  reg_name = $sformatf("intr_state%0d", hart);
    uvm_reg intr_state_reg = ral.get_reg_by_name(reg_name);

    if (intr_state_reg == null) begin
      `uvm_fatal(get_full_name(), $sformatf("No such register: %0s", reg_name))
    end

    fork : isolation_fork begin
      fork
        // The timeout thread, which will run until the timeout, then set a flag and wait forever
        // (allowing us to use join_any to wait for the other thread).
        begin
          #(timeout_ns * 1ns);
          seen_timeout = 1'b1;
          wait(0);
        end

        // The thread that reads the interrupt register, if it sees that all the timers have
        // generated an interrupt. It also stops early on a timeout (looking at seen_timeout) or if
        // reset is asserted.
        while (!seen_timeout) begin
          uvm_status_e   status;
          uvm_reg_data_t reg_value;

          intr_state_reg.read(status, reg_value);
          if (cfg.under_reset) break;

          if (status != UVM_IS_OK) begin
            `uvm_error(get_full_name(), $sformatf("Failed to read %0s", reg_name))
          end

          // We are done if there are no enabled timers that have not generated an interrupt.
          if (!(en_timers & ~reg_value)) break;

          // Otherwise, wait a short time before checking for timeout then reading the register
          // again.
          wait_ns_or_reset(spinwait_delay_ns);
        end
      join_any
      disable fork;
    end join
  endtask

  // Repeatedly read each hart's intr_state register until it shows an interrupt from each enabled
  // timer.
  //
  // This exits (shortly) after timeout_ns or immediately if there is a reset.
  task intr_state_spinwait_all_harts(int unsigned timeout_ns);
    fork : isolation_fork begin
      for (int i = 0; i < NUM_HARTS; i++) begin
        automatic int a_i = i;
        if (en_harts[a_i]) begin
          fork begin
            intr_state_spinwait_hart(a_i, timeout_ns);
          end join_none
        end
      end
      wait fork;
    end join
  endtask

  // Disable every timer on every hart
  //
  // Exits early if reset is asserted.
  task disable_timers();
    // The CTRL multireg has a register per hart and the bits of the register are the enable pins
    // for the timers in the hart. Write zero to disable all of them.
    foreach (ral.ctrl[i]) begin
      uvm_status_e status;
      ral.ctrl[i].write(status, 0);
      if (cfg.under_reset) return;
      if (status != UVM_IS_OK) begin
        `uvm_error(get_full_name(), $sformatf("Failed to write %0s", ral.ctrl[i].get_name()))
      end
    end
  endtask

  // For every hart, enable the timers whose corresponding bit in en_timers is set
  //
  // Exits early if reset is asserted.
  task enable_timers();
    for (int i = 0; i < NUM_HARTS; i++) begin
      for (int j = 0; j < NUM_TIMERS; j++) begin
        cfg_timer(.hart(i), .timer(j), .enable(en_timers[j]));
        if (cfg.under_reset) return;
      end
    end
  endtask

  // Configure the timers of the given hart based on fields in the class
  //
  // Exit early on reset.
  task configure_timers_for_hart(int unsigned hart);
    `uvm_info(get_full_name(),
              $sformatf("Configuring timers for hart %0d: prescale=%0d, step=%0d, timer_val=%0d",
                        hart, prescale[hart], step[hart], timer_val[hart]),
              UVM_MEDIUM)

    cfg_hart(.hart(hart), .prescale(prescale[hart]), .step(step[hart]));
    if (cfg.under_reset) return;

    set_timer_val(.hart(hart), .val(timer_val[hart]));
    if (cfg.under_reset) return;

    for (int tmr = 0; tmr < NUM_TIMERS; tmr++) begin
      `uvm_info(get_full_name(),
                $sformatf("Configuring timer %0d for hart %0d: compare_val=%0d, interrupt %0s",
                          tmr, hart,
                          compare_val[hart][tmr],
                          en_interrupt[hart][tmr] ? "enabled" : "disabled"),
                UVM_MEDIUM)

      set_compare_val(.hart(hart), .timer(tmr), .val(compare_val[hart][tmr]));
      if (cfg.under_reset) return;

      cfg_interrupt(.hart(hart), .timer(tmr), .enable(en_interrupt[hart][tmr]));
      if (cfg.under_reset) return;
    end
  endtask

  // Configure all timers and harts based on fields in the class.
  task cfg_all_timers();
    fork : isolation_fork begin
      for (int i = 0; i < NUM_HARTS; i++) begin
        automatic int hart_ = i;
        fork
          configure_timers_for_hart(hart_);
        join_none
      end
      wait fork;
    end join
  endtask : cfg_all_timers

  // Clear the interrupt status for each timer that was enabled (and so might have generated an
  // interrupt)
  //
  // Exits early if a reset is asserted.
  task clear_all_interrupts();
    for (int i = 0; i < NUM_HARTS; i++) begin
      for (int j = 0; j < NUM_TIMERS; j++) begin
        if (en_harts[i] && en_timers[j]) begin
          clear_intr_state(.hart(i), .timer(j));
          if (cfg.under_reset) return;
        end
      end
    end
  endtask

  // Run a single iteration of the test.
  //
  // This configures the timers, enables them and then waits for all to generate interrupts before
  // disabling the timers and clearing everything again.
  task run_one_trans();
    // This task will run timers and wait until they raise an interrupt. They should have been
    // configured to do this in at most max_clks_until_expiry cycles, from which we derive a timeout
    // here.
    //
    // After the timeout has elapsed, intr_state_spinwait_hart will exit.
    int unsigned intr_timeout_ns = max_clks_until_expiry * (cfg.clk_rst_vif.clk_period_ps / 1000.0);

    // Disable timers before configuring them.
    disable_timers();
    if (cfg.under_reset) return;

    // Configure the timers in each hart
    cfg_all_timers();
    if (cfg.under_reset) return;

    // Enable the timers (based on the flags in en_timers) for each hart
    enable_timers();
    if (cfg.under_reset) return;

    // Wait until all the enabled timers have generated an interrupt, stopping after
    // intr_timeout_ns.
    //
    // If assert_reset is true, run this in parallel with a randomly delayed reset. If that reset
    // arrives before intr_state_spinwait_all_harts completes (likely) then it will cause that task
    // to exit early.
    fork
      intr_state_spinwait_all_harts(intr_timeout_ns);
      if (assert_reset) begin
        // Assert the reset at an arbitrary time in the range 100-200ns (long enough that a timer
        // might have expired, but it's possible that none have.
        #($urandom_range(100, 1000) * 1ns);
        dut_init("HARD");
      end
    join

    // Before we finish, we will clean up again by disabling the timers and clearing any interrupts.
    // This isn't necessary if we just reset the block.
    if (assert_reset) return;

    // Disable the timers again
    disable_timers();
    if (cfg.under_reset) return;

    // Clear the interrupt status for each timer
    clear_all_interrupts();
  endtask

  task body();
    for (int trans = 1; trans <= num_trans; trans++) begin
      `uvm_info(`gfn, $sformatf("Running test iteration %0d/%0d", trans, num_trans), UVM_LOW)
      if (trans > 1) begin
        if (!randomize()) `uvm_fatal(get_full_name(), "Failed to randomize vseq.")
      end
      run_one_trans();
    end
  endtask

endclass : rv_timer_random_vseq
