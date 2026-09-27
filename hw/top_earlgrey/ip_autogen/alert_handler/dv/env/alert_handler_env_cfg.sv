// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class alert_handler_env_cfg extends cip_base_env_cfg #(.RAL_T(alert_handler_reg_block));
  esc_en_vif    esc_en_vif;
  crashdump_vif crashdump_vif;

  // ext component cfgs
  rand alert_agent_cfg        alert_host_cfg[];
  rand esc_agent_cfg          esc_device_cfg[];
  lpg_agent_cfg               m_lpg_agent_cfg;
  ping_req_agent_cfg          m_ping_req_agent_cfg;
  ping_timer_force_agent_cfg  m_ping_timer_force_agent_cfg;
  force_class_accum_agent_cfg m_force_class_accum_agent_cfgs[];

  // The set of names for alert classes
  string m_class_names[NUM_ALERT_CLASSES] = '{"a", "b", "c", "d"};

  // The tracked state of an LPG (with mubi4_t booleans resolved as bits)
  typedef struct {
    bit cg_en;
    bit rst_en;
  } lpg_state_t;

  // The currently tracked states of the various LPGs
  //
  // This is initially empty. It is safe to access once m_lpg_agent_cfg has an associated interface
  // (which means that we know how many LPGs exist). Once this is true, access it with get_lpg_state
  // / set_lpg_state.
  local lpg_state_t m_lpg_states[];

  // The tracked state of alert ping requests (as observed by a bound-in ping_req_if). This is
  // updated by the scoreboard calling update_alert_ping_req() and can be queried by calling
  // get_alert_ping_req().
  local bit [NUM_ALERTS-1:0] m_alert_ping_reqs;

  // The tracked state of escalation ping requests (as observed by a bound-in ping_req_if). This is
  // updated by the scoreboard calling update_esc_ping_req() and can be queried by calling
  // get_esc_ping_req().
  local bit [NUM_ESCS-1:0] m_esc_ping_reqs;

  `uvm_object_utils_begin(alert_handler_env_cfg)
    `uvm_field_array_object(alert_host_cfg, UVM_DEFAULT)
    `uvm_field_array_object(esc_device_cfg, UVM_DEFAULT)
  `uvm_object_utils_end

  function new (string name="");
    super.new(name);

    m_lpg_agent_cfg = lpg_agent_cfg::type_id::create("m_lpg_agent_cfg");

    m_ping_req_agent_cfg = ping_req_agent_cfg::type_id::create("m_ping_req_agent_cfg");
    m_ping_req_agent_cfg.is_active = 1'b0;

    m_ping_timer_force_agent_cfg =
      ping_timer_force_agent_cfg::type_id::create("m_ping_timer_force_agent_cfg");
  endfunction

  virtual function void initialize(bit inherit_ral_models = 1'b0);
    num_edn = 1;
    super.initialize(inherit_ral_models);

    shadow_update_err_status_fields[get_la_field(LocalShadowRegUpdateErr)] = 1;
    shadow_storage_err_status_fields[get_la_field(LocalShadowRegStorageErr)] = 1;

    // Set num_interrupts by counting bits in fields of the intr_state register
    num_interrupts = get_intr_state_reg().get_n_used_bits();

    alert_host_cfg = new[NUM_ALERTS];
    esc_device_cfg = new[NUM_ESCS];
    foreach (alert_host_cfg[i]) begin
      alert_host_cfg[i] = alert_agent_cfg::type_id::create($sformatf("alert_host_cfg[%0d]", i));
      alert_host_cfg[i].if_mode = dv_utils_pkg::Host;
      alert_host_cfg[i].is_async = ASYNC_ON[i];
    end
    foreach (esc_device_cfg[i]) begin
      esc_device_cfg[i] = esc_agent_cfg::type_id::create($sformatf("esc_device_cfg[%0d]", i));
      esc_device_cfg[i].if_mode  = dv_utils_pkg::Device;
    end

    m_force_class_accum_agent_cfgs = new[alert_handler_reg_pkg::N_CLASSES];
    foreach (m_force_class_accum_agent_cfgs[i]) begin
      string name = $sformatf("m_force_class_accum_agent_cfgs[%0d]", i);
      m_force_class_accum_agent_cfgs[i] = force_class_accum_agent_cfg::type_id::create(name);
    end

    // only support 1 outstanding TL items in tlul_adapter
    m_tl_agent_cfg.max_outstanding_req = 1;
  endfunction

  // Return the intr_state register (looking it up by name) as a dv_base_reg
  function dv_base_reg get_intr_state_reg();
    dv_base_reg ret;
    uvm_reg     intr_state_base = ral.get_reg_by_name("intr_state");

    if (intr_state_base == null) `uvm_fatal("no_reg", "Cannot find intr_state register")
    if (!$cast(ret, intr_state_base)) begin
      `uvm_fatal("no_dv_reg", "The intr_state register is not a dv_base_reg.")
    end

    return ret;
  endfunction

  // Get the "la" field from the appropriate member of the loc_alert_cause multireg
  local function dv_base_reg_field get_la_field(local_alert_type_e alert_type);
    string            reg_name = $sformatf("loc_alert_cause_%0d", alert_type);
    uvm_reg           register = ral.get_reg_by_name(reg_name);
    uvm_reg_field     base_fld;
    dv_base_reg_field fld;

    if (register == null) begin
      `uvm_fatal("no_reg",
                 $sformatf("Couldn't find register for %0s at %0s.", alert_type.name(), reg_name))
    end

    base_fld = register.get_field_by_name("la");
    if (base_fld == null) begin
      `uvm_fatal("no_la_field", $sformatf("Couldn't find %0s.la register field.", reg_name))
    end

    if (!$cast(fld, base_fld)) begin
      `uvm_fatal("base_la_field", $sformatf("%0s.la is not a dv_base_reg_field.", reg_name))
    end

    return fld;
  endfunction

  // Override shadow register naming checks. The alert handler does not expose any alert signals,
  // hence no alerts are defined in Hjson.
  virtual function void check_shadow_reg_alerts();
    // Nothing to check.
  endfunction

  // Check that this env_cfg has an array to track states for LPGs. This can only be run after the
  // env_cfg has an interface in m_lpg_agent_cfg.vif.
  local function void ensure_lpg_state_array();
    if (m_lpg_states.size()) return;
    if (m_lpg_agent_cfg.vif == null) begin
      `uvm_fatal("no_vif", "Cannot get number of LPGs from interface: vif is not set.")
    end
    m_lpg_states = new[m_lpg_agent_cfg.vif.num_lpgs]('{default: '0});
  endfunction

  // Get the environment's understanding of the state of the given LPG
  //
  // This should only be called after the environment's build_phase has run and registered an lpg_if
  // (from which the function can get the number of LPGs)
  function void get_lpg_state(int unsigned lpg_idx, output bit cg_en, output bit rst_en);
    ensure_lpg_state_array();
    if (lpg_idx >= m_lpg_states.size()) begin
      `uvm_fatal("no_such_lpg",
                 $sformatf("Cannot get the state of LPG %0d: there are only %0d known.",
                           lpg_idx, m_lpg_states.size()))
    end
    cg_en = m_lpg_states[lpg_idx].cg_en;
    rst_en = m_lpg_states[lpg_idx].rst_en;
  endfunction

  // Update the environment's understanding of the state of the given LPG
  //
  // This should only be called after the environment's build_phase has run and registered an lpg_if
  // (from which the function can get the number of LPGs)
  function void set_lpg_state(int unsigned lpg_idx, bit cg_en, bit rst_en);
    ensure_lpg_state_array();
    if (lpg_idx >= m_lpg_states.size()) begin
      `uvm_fatal("no_such_lpg",
                 $sformatf("Cannot set the state of LPG %0d: there are only %0d known.",
                           lpg_idx, m_lpg_states.size()))
    end
    m_lpg_states[lpg_idx].cg_en = cg_en;
    m_lpg_states[lpg_idx].rst_en = rst_en;
  endfunction

  // Is the indexed LPG in low power mode (clock gated or in reset)?
  function bit is_lpg_low_power(int unsigned lpg_idx);
    bit cg_en, rst_en;
    get_lpg_state(lpg_idx, cg_en, rst_en);
    return cg_en || rst_en;
  endfunction

  function void update_alert_ping_req(int unsigned idx, bit new_value);
    if (idx >= $bits(m_alert_ping_reqs)) begin
      `uvm_fatal("high_alert_idx",
                 $sformatf({"Cannot update the ping request state for alert %0d: ",
                            "there are only %0d alerts known."},
                           idx, $bits(m_alert_ping_reqs)))
    end
    m_alert_ping_reqs[idx] = new_value;
  endfunction

  function bit get_alert_ping_req(int unsigned idx);
    if (idx >= $bits(m_alert_ping_reqs)) begin
      `uvm_fatal("high_alert_idx",
                 $sformatf({"Cannot get the ping request state for alert %0d: ",
                            "there are only %0d alerts known."},
                           idx, $bits(m_alert_ping_reqs)))
    end
    return m_alert_ping_reqs[idx];
  endfunction

  function bit has_alert_ping_req(output int unsigned highest_idx);
    if (|m_alert_ping_reqs) begin
      highest_idx = $clog2(m_alert_ping_reqs);
      return 1'b1;
    end
    return 1'b0;
  endfunction

  function void clear_alert_ping_reqs();
    m_alert_ping_reqs = '0;
  endfunction

  local task wait_no_alert_ping_req();
    wait(~|m_alert_ping_reqs);
  endtask

  function void update_esc_ping_req(int unsigned idx, bit new_value);
    if (idx >= $bits(m_esc_ping_reqs)) begin
      `uvm_fatal("high_esc_idx",
                 $sformatf({"Cannot update the ping request state for escalation %0d: ",
                            "there are only %0d escalations known."},
                           idx, $bits(m_esc_ping_reqs)))
    end
    m_esc_ping_reqs[idx] = new_value;
  endfunction

  function bit get_esc_ping_req(int unsigned idx);
    if (idx >= $bits(m_esc_ping_reqs)) begin
      `uvm_fatal("high_esc_idx",
                 $sformatf({"Cannot get the ping request state for escalation %0d: ",
                            "there are only %0d escalationss known."},
                           idx, $bits(m_esc_ping_reqs)))
    end
    return m_esc_ping_reqs[idx];
  endfunction

  function bit has_esc_ping_req();
    return (|m_alert_ping_reqs);
  endfunction

  function void clear_esc_ping_reqs();
    m_esc_ping_reqs = '0;
  endfunction

  local task wait_no_esc_ping_req();
    wait(~|m_esc_ping_reqs);
  endtask

  task wait_no_ping_req();
    fork
      wait_no_alert_ping_req();
      wait_no_esc_ping_req();
    join
  endtask

  // Get the requested entry from the named (non-compact) multireg.
  function uvm_reg get_multireg_register(string multireg_name, int unsigned idx);
    string  reg_name = $sformatf("%0s_%0d", multireg_name, idx);
    uvm_reg register = ral.get_reg_by_name(reg_name);

    if (register == null) begin
      `uvm_fatal("bad_multireg_idx",
                 $sformatf({"Cannot find the register with index %0d ",
                            "in the multireg '%0s', which would have name '%0s'."},
                           idx, multireg_name, reg_name))
    end
    return register;
  endfunction

  // Get the requested register from the alert_en_shadowed multireg
  function uvm_reg get_alert_en_shadowed(int unsigned idx);
    return get_multireg_register("alert_en_shadowed", idx);
  endfunction

  // Get the requested register from the loc_alert_en_shadowed multireg
  function uvm_reg get_loc_alert_en_shadowed(int unsigned idx);
    return get_multireg_register("loc_alert_en_shadowed", idx);
  endfunction

  // Get the requested register from the alert_class_shadowed multireg
  function uvm_reg get_alert_class_shadowed(int unsigned idx);
    return get_multireg_register("alert_class_shadowed", idx);
  endfunction

  // Get the requested register from the loc_alert_class_shadowed multireg
  function uvm_reg get_loc_alert_class_shadowed(int unsigned idx);
    return get_multireg_register("loc_alert_class_shadowed", idx);
  endfunction

  // Get the a class-specific version of the given register for the requested class.
  function uvm_reg get_class_reg(string reg_name, string class_name);
    string  full_reg_name = $sformatf("class%0s_%0s", class_name, reg_name);
    uvm_reg register = ral.get_reg_by_name(full_reg_name);

    if (register == null) begin
      `uvm_fatal("bad_class_reg",
                 $sformatf({"Cannot find the class-specific register '%0s' ",
                            "for the class '%0s', which would have name '%0s'."},
                           reg_name, class_name, full_reg_name))
    end
    return register;
  endfunction

  // Get the ctrl_shadowed register for the given class
  function uvm_reg get_class_ctrl(string class_name);
    return get_class_reg("ctrl_shadowed", class_name);
  endfunction

  // Get the class<c>_phase<p>_cyc_shadowed register (supplying class and phase)
  function uvm_reg get_class_phase_cyc(string class_name, int unsigned phase);
    return get_class_reg($sformatf("phase%0d_cyc_shadowed", phase), class_name);
  endfunction

  // Get the intr_enable register
  function uvm_reg get_intr_enable();
    uvm_reg register = ral.get_reg_by_name("intr_enable");
    if (register == null) `uvm_fatal("no_reg", "Cannot find intr_enable register.")
    return register;
  endfunction
endclass
