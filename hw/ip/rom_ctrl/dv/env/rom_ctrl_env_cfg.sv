// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class rom_ctrl_env_cfg extends cip_base_env_cfg #(.RAL_T(rom_ctrl_regs_reg_block));

  `uvm_object_utils(rom_ctrl_env_cfg)

  // ext component cfgs
  rand kmac_app_agent_cfg m_kmac_agent_cfg;

  // The upper bound to use for response delays in the KMAC app agent
  //
  // This is randomised with rom_ctrl_env_cfg, then copied to m_kmac_agent_cfg in post_randomize().
  // (Doing so works because nothing in the randomisation of m_kmac_agent_cfg depends on its
  // rsp_delay_max).
  rand int unsigned m_kmac_rsp_delay_max;

  // Memory backdoor util instance for ROM.
  rom_ctrl_bkdr_util rom_ctrl_bkdr_util_h;

  // ext interfaces
  rom_ctrl_vif rom_ctrl_vif;

  // The number of ROM words that should be sent to KMAC for hashing.
  //
  // This is less than the size of the entire ROM (which can be seen, measured in bytes, with
  // get_rom_size_bytes()) because the ROM also contains KAT information and an expected digest.
  //
  // Getter / setter: get_data_size_words() / set_data_size_words().
  //
  // Configure this before building the environment.
  local int unsigned m_data_size_words;

  // The number of bits used for a digest. Getter / setter: get_digest_size_bits() /
  // set_digest_size_bits().
  //
  // Configure this before building the environment.
  local int unsigned m_digest_size_bits;

  // For block-level testing, there's a parameterized reg_block class that was added manually to
  // allow the testbench infrastructure to support memories with configurable size. Top-level
  // testing is much easier: there, the top-level has configured the size of the memory for us.
  //
  // These are the names of the RAL to use for block-level and chip-level tests, respectively.
  local string m_block_level_rom_ral_name = "rom_ctrl_prim_reg_block";
  local string m_chip_level_rom_ral_name  = "rom_ctrl_rom_reg_block";

  // An interface bound into the rom_ctrl_compare module
  virtual rom_ctrl_compare_if compare_vif;

  // An interface bound into the rom_ctrl_fsm module
  //
  // This might be null. If so, the environment won't investigate integrity checks at all (probably
  // because the FSM doesn't exist in the device).
  virtual rom_ctrl_fsm_if fsm_vif;

  // A handle to the scoreboard, used to flag expected errors.
  rom_ctrl_scoreboard scoreboard;

  // A flag that tells the environment to use rom_ctrl_fsm_if to force the value of the ROM address
  // counter, skipping over the middle of ROM.
  //
  // Access this with get_skip_middle / set_skip_middle.
  local bit m_skip_middle;

  // A flag that tells the environment to create a sequencer that can use rom_ctrl_fsm_if to
  // override the digest in responses that come back from kmac to match the expected value from the
  // ROM. This is useful at the chip level if we have set m_skip_middle and only send a small
  // portion of the ROM to the digest computation.
  //
  // Access this with get_force_expected_kmac_rsp / set_force_expected_kmac_rsp.
  local bit m_force_expected_kmac_rsp;

  extern function new (string name="");
  extern function void post_randomize();

  // Configure whether the env_cfg is active (configuring the agents too)
  //
  // This extends the definition in dv_base_env_cfg.
  extern function void set_is_active(bit active);

  extern virtual function void initialize(bit inherit_ral_models = 1'b0);
  extern virtual protected function dv_base_reg_block create_ral_by_name(string name);

  // Set the flag that says whether we should skip reading the middle of ROM
  extern function void set_skip_middle(bit skip);

  // Retrieve the flag that says whether we should skip reading the middle of ROM.
  extern function bit get_skip_middle();

  // Set the size of the data section of ROM (the contents sent to be hashed) in words.
  //
  // This should be called before the environment's build_phase. Stored in m_data_size_words.
  extern function void set_data_size_words(int unsigned data_size_words);

  // Get the size of the hashed part of ROM.
  extern function int unsigned get_data_size_words();

  // Set the size of the digest that should be read from KMAC.
  //
  // This should be called before the environment's build_phase. Stored in m_digest_size_bits.
  extern function void set_digest_size_bits(int unsigned digest_size_bits);

  // Get the size of the digest that should be read from KMAC.
  extern function int unsigned get_digest_size_bits();

  // Return true if ral_name is the name of the RAL for the ROM itself (rather than the CSRs)
  extern function bit is_rom_ral_name(string ral_name);

  // Return a uvm_mem representing the ROM itself (from either the RAL called
  // m_block_level_rom_ral_name or the one called m_chip_level_rom_ral_name).
  extern function uvm_mem get_rom_ral();

  // Set the flag that says whether to override digests from kmac to match the ROM expected value.
  extern function void set_force_expected_kmac_rsp(bit force_expected);

  // Retrieve the flag that says whether to override digests from kmac to match the ROM expected
  // value.
  extern function bit get_force_expected_kmac_rsp();

  // Return the size of ROM in bytes
  //
  // Note that this is the size of the entire ROM (not just the hashable data section): the TL
  // window also provides access to the words containing a KAT and the expected digest. Since these
  // are actually used without unscrambling, the values visible through the TL window will not be
  // very useful.
  extern function int unsigned get_rom_size_bytes();

  // Read the expected digest from the top bits of ROM (through a backdoor)
  //
  // If is_data_hash is true, this is the expected digest from the m_digest_size_bits immediately
  // after the top of the data bits. If not, it is the expected digest from the m_digest_size_bits
  // at the very top of ROM.
  extern function bit [AppDigestW-1:0] get_expected_digest(bit is_data_hash);

  // Control the device-side delay for the kmac app agent that talks to the dut. If it is large,
  // rom_ctrl will spend all its time waiting for kmac to accept words that rom_ctrl is trying to
  // send to kmac. Randomise this to be small with high probability and occasionally make it 10 (to
  // check that the interface from rom_ctrl to kmac can be stalled properly).
  extern constraint rsp_delay_max_c;
endclass

function rom_ctrl_env_cfg::new (string name="");
  super.new(name);

  can_reset_with_csr_accesses = 1'b1;

  list_of_alerts = rom_ctrl_env_pkg::LIST_OF_ALERTS;
  tl_intg_alert_name = "fatal";

  num_interrupts = 0;

  m_kmac_agent_cfg = kmac_app_agent_cfg::type_id::create("m_kmac_agent_cfg");
  m_kmac_agent_cfg.if_mode = dv_utils_pkg::Device;
  m_kmac_agent_cfg.constant_share_means_error = 1'b0;
  // The checker reads the upper 8 words of ROM which takes 9 cycles. The rsp_delay_max has been
  // rounded off by 9*2=18 cycles along with adding 2 just to give an extra precision.
  m_kmac_agent_cfg.rsp_delay_min = 'd0;
  m_kmac_agent_cfg.rsp_delay_max = 'd20;

  sec_cm_alert_name = "fatal";
endfunction

function void rom_ctrl_env_cfg::post_randomize();
  super.post_randomize();
  m_kmac_agent_cfg.rsp_delay_max = m_kmac_rsp_delay_max;
endfunction

function void rom_ctrl_env_cfg::set_is_active(bit active);
  super.set_is_active(active);
  m_kmac_agent_cfg.is_active = active;
endfunction

function void rom_ctrl_env_cfg::initialize(bit inherit_ral_models = 1'b0);
  // Use the inherit_ral_models argument to infer the key for the memory uvm_reg_block in
  // ral_model_names. If inherit_ral_models is false, this is a block-level test and we should use
  // "rom_ctrl_prim_reg_block" (the manually defined block in the environment). If it is true, this
  // is a chip-level test, which should already have an instance of "rom_ctrl_rom_reg_block" (but we
  // need to add that name to ral_model_names so that this environment finds it).
  string rom_ral_name = inherit_ral_models ? m_chip_level_rom_ral_name : m_block_level_rom_ral_name;

  ral_model_names[rom_ral_name] = 1'b0;

  super.initialize(inherit_ral_models);

  // default TLUL supports 1 outstanding item, the rom TLUL supports 2 outstanding items.
  m_tl_agent_cfgs[RAL_T::type_name].max_outstanding_req = 1;
  m_tl_agent_cfgs[rom_ral_name].max_outstanding_req = 2;

  // Tell the CIP base code what bit gets set if we see a TL fault.
  tl_intg_alert_fields[ral.fatal_alert_cause.integrity_error] = 1;

  // Default is 10ms (see default_spinwait_timeout_ns in csr_utils_pkg.sv, assigned in
  // cip_base_env_cfg)
  // We have to increase this here since the ROM check may actually take longer than that,
  // which sometimes causes blocked TL accesses to time out.
  tl_access_timeout_ns = 40_000_000; // 40ms
endfunction

// Override the default implementation in dv_base_env_cfg.
//
// This is required for the ROM environment for reuse at the chip level as 2 different
// parameterizations of the design and testbench exist, as a result the custom RAL model for the
// ROM memory primitive must also be explicitly parameterized.
//
// We cannot instantiate parameterized UVM objects/components using the standard factory
// mechanisms, so a custom instantiation method is required here.
//
// Note that the ROM only has 2 RAL models, one is the "default" CSR model,
// and the other is the custom model to represent the memory primitive.
function dv_base_reg_block rom_ctrl_env_cfg::create_ral_by_name(string name);
  if (name == RAL_T::type_name) begin
    return super.create_ral_by_name(name);
  end else if (name == m_block_level_rom_ral_name) begin
    return rom_ctrl_prim_reg_block#(ROM_SIZE_WORDS)::type_id::create(m_block_level_rom_ral_name);
  end else begin
    `uvm_error(`gfn, $sformatf("%0s is an illegal RAL model name", name))
  end
endfunction

function void rom_ctrl_env_cfg::set_skip_middle(bit skip);
  m_skip_middle = skip;
endfunction

function bit rom_ctrl_env_cfg::get_skip_middle();
  return m_skip_middle;
endfunction

function void rom_ctrl_env_cfg::set_data_size_words(int unsigned data_size_words);
  if (!data_size_words) `uvm_fatal("bad_data_size", "Cannot set data_size_words to zero.")
  m_data_size_words = data_size_words;
endfunction

function int unsigned rom_ctrl_env_cfg::get_data_size_words();
  if (!m_data_size_words) `uvm_fatal("no_data_size", "No data size has been set.")
  return m_data_size_words;
endfunction

function void rom_ctrl_env_cfg::set_digest_size_bits(int unsigned digest_size_bits);
  if (!digest_size_bits) `uvm_fatal("bad_digest_size", "Cannot set digest_size_bits to zero.")
  if (digest_size_bits & 31) begin
    `uvm_fatal("bad_digest_size",
               $sformatf("Cannot set digest_size_bits = %0d: not a multiple of 32.",
                         digest_size_bits))

  end
  if (digest_size_bits > AppDigestW) begin
    `uvm_fatal("bad_digest_size",
               $sformatf("Cannot set digest_size_bits = %0d: the maximum supported size is %0d.",
                         digest_size_bits, AppDigestW))
  end
  m_digest_size_bits = digest_size_bits;
endfunction

function int unsigned rom_ctrl_env_cfg::get_digest_size_bits();
  if (!m_digest_size_bits) `uvm_fatal("no_digest_size", "No digest size has been set.")
  return m_digest_size_bits;
endfunction

function bit rom_ctrl_env_cfg::is_rom_ral_name(string ral_name);
  return (ral_name inside {m_block_level_rom_ral_name, m_chip_level_rom_ral_name});
endfunction

function uvm_mem rom_ctrl_env_cfg::get_rom_ral();
  uvm_reg_block block;
  uvm_mem       mems[$];

  if (ral_models.exists(m_block_level_rom_ral_name)) begin
    block = ral_models[m_block_level_rom_ral_name];
  end else if (ral_models.exists(m_chip_level_rom_ral_name)) begin
    block = ral_models[m_chip_level_rom_ral_name];
  end else begin
    `uvm_fatal("no_ral", "Cannot find a RAL for the interface with ROM.")
  end

  block.get_memories(mems);

  if (mems.size() != 1) begin
    `uvm_error("not_one_mem",
               $sformatf("The set of memories for block %0s has size %0d (not 1).",
                         block.get_name(), mems.size()))
  end

  return mems[0];
endfunction

function void rom_ctrl_env_cfg::set_force_expected_kmac_rsp(bit force_expected);
  m_force_expected_kmac_rsp = force_expected;
endfunction

function bit rom_ctrl_env_cfg::get_force_expected_kmac_rsp();
  return m_force_expected_kmac_rsp;
endfunction

function int unsigned rom_ctrl_env_cfg::get_rom_size_bytes();
  uvm_mem mem = get_rom_ral();

  return mem.get_size() * mem.get_n_bits() / 8;
endfunction

function bit [AppDigestW-1:0] rom_ctrl_env_cfg::get_expected_digest(bit is_data_hash);
  bit [AppDigestW-1:0] digest;
  int unsigned         digest_size_words = get_digest_size_bits() / 32;

  // Read the size of ROM in bytes and divide by 4 to get the number of 32-bit words. Then subtract
  // digest_size_words to get the index of first 32-bit word of the digest: once if this is the KAT
  // expected digest (at the top of ROM) and twice if this is the expected data hash.
  int unsigned dig_addr = get_rom_size_bytes() / 4 - ((1 + is_data_hash) * digest_size_words);

  // Backdoor read the digest in 32-bit words.
  for (int unsigned i = 0; i < digest_size_words; i++) begin
    bit [38:0] raw_word = rom_ctrl_bkdr_util_h.rom_encrypt_read32(4 * (dig_addr + i), 1'b0);

    // Ignore the top 7 bits (which contain ECC data) and just accumulate the other 32.
    digest[32 * i +: 32] = raw_word[31:0];
  end

  return digest;
endfunction

constraint rom_ctrl_env_cfg::rsp_delay_max_c {
  // Note that this doesn't involve m_kmac_agent_cfg.zero_delays. If that bit is set, the agent will
  // ignore its rsp_delay_max field (copied from this value in post_randomize), so this variable
  // will have no effect.
  m_kmac_rsp_delay_max dist { 1 :/ 10, 10 :/ 1 };
}
