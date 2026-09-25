// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class ${module_instance_name}_env_cfg extends cip_base_env_cfg #(.RAL_T(${module_instance_name}_reg_block));

  esc_en_vif               esc_en_vif;
  crashdump_vif            crashdump_vif;

  // ext component cfgs
  rand alert_agent_cfg     alert_host_cfg[];
  rand esc_agent_cfg       esc_device_cfg[];
  lpg_agent_cfg            m_lpg_agent_cfg;

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

  ${module_instance_name}_vif ${module_instance_name}_vif;

  `uvm_object_utils_begin(${module_instance_name}_env_cfg)
    `uvm_field_array_object(alert_host_cfg, UVM_DEFAULT)
    `uvm_field_array_object(esc_device_cfg, UVM_DEFAULT)
  `uvm_object_utils_end

  function new (string name="");
    super.new(name);
    m_lpg_agent_cfg = lpg_agent_cfg::type_id::create("m_lpg_agent_cfg");
  endfunction

  virtual function void initialize(bit inherit_ral_models = 1'b0);
    num_edn = 1;
    super.initialize(inherit_ral_models);
    shadow_update_err_status_fields[ral.loc_alert_cause[LocalShadowRegUpdateErr].la] = 1;
    shadow_storage_err_status_fields[ral.loc_alert_cause[LocalShadowRegStorageErr].la] = 1;

    // set num_interrupts & num_alerts
    num_interrupts = ral.intr_state.get_n_used_bits();

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
    // only support 1 outstanding TL items in tlul_adapter
    m_tl_agent_cfg.max_outstanding_req = 1;
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
endclass
