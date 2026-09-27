// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This sequence forces the alert accumulation count to large value, then checks the count will
// saturate rather than overflowing.

class ${module_instance_name}_alert_accum_saturation_vseq extends ${module_instance_name}_smoke_vseq;
  `uvm_object_utils(${module_instance_name}_alert_accum_saturation_vseq)

  // The class that should be saturated (which should be less than NUM_ALERT_CLASSES), guaranteed by
  // the valid_saturated_class_c constraint.
  rand int unsigned saturated_class;

  // The number of alerts that need to be generated to saturate the chosen class (because all alerts
  // will be assigned to that class)
  rand int unsigned num_alerts_to_saturate;

  // One sequence per class. These get created and started in this virtual sequence's pre_start
  // task, and will run until they see a reset or they are aborted.
  local force_class_accum_agent_pkg::force_class_accum_seq m_force_seqs[$];

  // The class that is selected for saturation should exist
  constraint valid_saturated_class_c {
    saturated_class < NUM_ALERT_CLASSES;
  }

  // Constrain num_alerts_to_saturate to be a small positive number. Also constrain alert_trigger
  // (the mask of alerts that should be triggered) to be one-hot, which means that each call to
  // drive_alert() will cause exactly one alert to be sent.
  constraint num_alerts_to_saturate_c {
    num_alerts_to_saturate inside {[1 : 10]};
    $countones(alert_trigger) == 1;
  }

  function new(string name="");
    super.new(name);
  endfunction

  function void pre_randomize();
    this.enable_one_alert_c.constraint_mode(0);
    this.enable_classa_only_c.constraint_mode(0);
  endfunction

  virtual task pre_start();
    // Create a sequence to force the count value for the accumulation counter in each of the
    // classes.
    //
    // For each of the classes, pick a value that's near the class's saturation count: just
    // num_alerts_to_saturate less.
    foreach (m_force_class_accum_sequencers[i]) begin
      import force_class_accum_agent_pkg::force_class_accum_seq;

      int unsigned max_accum_cnt = get_max_accum_count(i);
      string seq_name = $sformatf("seq[%0d]", i);
      force_class_accum_seq seq = force_class_accum_seq::type_id::create(seq_name);

      if (!seq.randomize() with {
             m_item.m_desired_value == (max_accum_cnt - num_alerts_to_saturate);
           }) begin
        `uvm_fatal(get_full_name(), $sformatf("Failed to randomize %0s sequence", seq_name))
      end

      m_force_seqs.push_back(seq);

      fork
        seq.start(m_force_class_accum_sequencers[i]);
      join_none
    end

    super.pre_start();
  endtask

  virtual task body();
    // Assign all alerts to one class.
    foreach (alert_class_map[i]) alert_class_map[i] = saturated_class;
    alert_handler_init(.intr_en('1),
                       .alert_en('1),
                       .alert_class(alert_class_map),
                       .loc_alert_en(0),
                       .loc_alert_class(0));

    `uvm_info(get_full_name(), "Setting maximum accumulation thresholds", UVM_MEDIUM)
    set_maximum_thresholds();

    `uvm_info(get_full_name(), "Enabling and locking all classes of alert", UVM_MEDIUM)
    enable_and_lock_classes();

    // Release the forced counts (the forces only really had to last a single cycle). The sequences
    // in question will all still be running: tell each to abort and wait for them all to finish.
    fork : isolation_fork0 begin
      foreach (m_force_seqs[i]) begin
        fork
          m_force_seqs[i].abort();
        join_none
      end

      // All of the sequences have been told to abort. Wait for them to finish.
      wait fork;
    end join
    m_force_seqs.delete();

    `uvm_info(`gfn, $sformatf("Saturate class %0d, alerts to saturate %0d", saturated_class,
                              num_alerts_to_saturate), UVM_LOW)

    // First round will reach the max count value. Later rounds should saturate and not overflow.
    repeat ($urandom_range(2, 5)) begin
      repeat (num_alerts_to_saturate) send_alert_and_clear_interrupt();

      fork : isolation_fork1 begin
        for (int unsigned i = 0; i < NUM_ALERT_CLASSES; i++) begin
          automatic int unsigned i_ = i;
          fork check_alert_accum_count(i_); join_none
        end
        wait fork;
      end join
    end
  endtask

  local function uvm_reg get_accum_count_register(int unsigned class_idx);
    return cfg.get_class_reg("accum_cnt", cfg.m_class_names[class_idx]);
  endfunction

  // Calculate the maximum possible accumulation count for a particular alert class, by looking at
  // the class's associated accumulation count register and checking the width of that register's
  // only field.
  local function int unsigned get_max_accum_count(int unsigned class_idx);
    uvm_reg_field fields[$];
    uvm_reg       cnt_reg = get_accum_count_register(class_idx);

    cnt_reg.get_fields(fields);
    if (fields.size() != 1) begin
      `uvm_fatal(get_full_name(),
                 $sformatf("Expected a single field in %0s but there were %0d.",
                           cnt_reg.get_name(), fields.size()))
    end

    return (1 << fields[0].get_n_bits()) - 1;
  endfunction

  // Check that the given alert class has the expected accumulation count. If this wasn't the
  // targeted alert class, this should be the value to which we forced it (the maximum value minus
  // num_alerts_to_saturate). If it *is* the targeted alert class, this should be the saturation
  // value.
  local task check_alert_accum_count(int unsigned class_idx);
    int unsigned max_accum_count = get_max_accum_count(class_idx);
    int unsigned exp_count = ((class_idx == saturated_class) ?
                              max_accum_count :
                              max_accum_count - num_alerts_to_saturate);
    csr_rd_check(.ptr(get_accum_count_register(class_idx)), .compare_value(exp_count));
  endtask

  // Set a maximal value for the threshold for the indexed alert class by writing to the shadowed
  // class<n>_accum_thresh_shadowed register.
  local task set_maximum_threshold(int unsigned class_idx);
    csr_wr(cfg.get_class_reg("accum_thresh_shadowed", cfg.m_class_names[class_idx]), '1);
  endtask

  // Set a maximal value for the threshold for all alert classes
  local task set_maximum_thresholds();
    fork : isolation_fork begin
      for (int unsigned i = 0; i < NUM_ALERT_CLASSES; i++) begin
        automatic int unsigned i_ = i;
        fork set_maximum_threshold(i_); join_none
      end
      wait fork;
    end join
  endtask

  // Enable and lock the indexed alert class by writing to the shadowed class<n>_ctrl_shadowed
  // register, setting its en field.
  local task enable_and_lock_class(int unsigned class_idx);
    uvm_reg       ctrl_reg = cfg.get_class_reg("ctrl_shadowed", cfg.m_class_names[class_idx]);
    uvm_reg_field en_field = ctrl_reg.get_field_by_name("en");

    if (en_field == null) begin
      `uvm_fatal(get_full_name(), $sformatf("Cannot find %0s.en", ctrl_reg.get_name()))
    end

    en_field.set(1);
    csr_update(ctrl_reg);
  endtask

  // Enable and lock all the alert classes
  local task enable_and_lock_classes();
    fork : isolation_fork begin
      for (int unsigned i = 0; i < NUM_ALERT_CLASSES; i++) begin
        automatic int unsigned i_ = i;
        fork enable_and_lock_class(i_); join_none
      end
      wait fork;
    end join
  endtask

  // Re-randomise the alert_trigger class variable and drive that alert. Then read the intr_state
  // CSR. We know that we have configured all interrupts to belong to saturated_class, so the
  // interrupt for that class should have fired. Finally, write to intr_state to clear the interrupt
  // again.
  local task send_alert_and_clear_interrupt();
    uvm_reg intr_state = cfg.ral.get_reg_by_name("intr_state");
    if (intr_state == null) begin
      `uvm_fatal(get_full_name(), "Cannot find 'intr_state' register.")
    end

    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(alert_trigger)

    drive_alert(alert_trigger, alert_int_err);
    csr_rd_check(.ptr(intr_state), .compare_value(1 << saturated_class));
    csr_wr(.ptr(intr_state), .value(1 << saturated_class));
  endtask

endclass : ${module_instance_name}_alert_accum_saturation_vseq
