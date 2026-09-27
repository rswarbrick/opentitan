// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class alert_handler_base_test extends cip_base_test #(
    .ENV_T(alert_handler_env),
    .CFG_T(alert_handler_env_cfg)
  );

  `uvm_component_utils(alert_handler_base_test)

  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_sequence(uvm_sequence seq);
    import force_class_accum_agent_pkg::force_class_accum_sequencer;

    alert_handler_base_vseq vseq;
    force_class_accum_sequencer       force_class_sequencers[$];

    super.configure_sequence(seq);

    if (!$cast(vseq, seq)) begin
      `uvm_fatal(get_full_name(),
                 "Cannot configure sequence: it is not a alert_handler_base_vseq.")
    end
    foreach(env.m_force_class_accum_agents[i]) begin
      force_class_sequencers.push_back(env.m_force_class_accum_agents[i].sequencer);
    end

    vseq.set_lpg_sequencer(env.m_lpg_agent.sequencer);
    vseq.set_ping_timer_force_sequencer(env.m_ping_timer_force_agent.sequencer);
    vseq.set_force_class_accum_sequencers(force_class_sequencers);
  endfunction
endclass : alert_handler_base_test
