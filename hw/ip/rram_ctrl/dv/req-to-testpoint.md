# rram_ctrl: requirement to testpoint mapping

This file maps the [requirements](requirements.md) to the way that the requirement will be tested.
There are four lists of places these requirements can be tracked:
- UVM covergroups (**CG**), also listed in the [testplan](../data/rram_ctrl_testplan.hjson)).
- UVM tests (**UVM**), which address a list of testpoints in a [testplan](../data/rram_ctrl_testplan.hjson)).
- Testpoints (**SEC**) (also UVM tests) that are specific to security countermeasures in a [sec_cm testplan](../data/rram_ctrl_sec_cm_testplan.hjson).
- The [FPV test properties](formal/property_list.md) (**FPV**).

The list in this file is in the same order as [requirements](requirements.md).

## 1. Memory organisation and address map

- **1.1**: The RRAM has two separately-addressed partitions: **data** and **info**.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `rewrite_op` (**UVM**)
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)

- **1.2**: Data partition pages 0–4089 are general-purpose data, accessible by host, SW and lcmgr-hw-if.

  To test this, we must see accesses to each end (pages 0 and 4089), plus an access to an interior page.
  These three types of access must be seen from each of the three sources (host, SW and lcmgr-hw-if).

  Addressed by:
  - `data_page_access_cg` (**CG**)
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `host_read_direct` (**UVM**)
  - `rma` (**UVM**)

- **1.3**: Data partition page 4090 (`OtpIntgStartAddr`) holds OTP integrity words, accessible only by otp-hw-if.

  To test this, we must see accesses to the page through otp-hw-if that succeed.
  We must also see attempted accesses from the host and SW sources (which will fail with a memory protection error).

  Addressed by:
  - `otp_page_access_cg` (**CG**)
  - `rewrite_op` (**UVM**)
  - `otp_standalone` (**UVM**)
  - `otp_region_protection` (**UVM**)
  - `otp_write_blank_err` (**UVM**)

- **1.4**: Data partition pages 4091–4095 hold OTP data, accessible only by otp-hw-if; the OTP region is inaccessible to SW, host and the RMA wipe.

  To test this, we must see successful accesses through otp-hw-if to each of the four pages.
  We must also see attempted accesses to the top page from the host and SW sources (which will fail with a memory protection error).
  We must also see that the RMA wipe doesn't touch any of these pages.

  Addressed by:
  - `otp_page_access_cg` (**CG**)
  - `otp_region_protection` (**UVM**)
  - `otp_standalone` (**UVM**)
  - `emul_info_window` (**UVM**)
  - `rma` (**UVM**)

- **1.5**: Info partition: 8 pages, accessible by SW and lcmgr-hw-if only (never the host).

  To test this, we must see access to info pages 0, 5, 6 and 7 (minimum and maximum, and each named info page).
  This must be seen for both SW and lcmgr-hw-if.
  We must also see failed access to an info page from the host interface.

  Addressed by:
  - `info_page_access_cg` (**CG**)
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `memory_protection` (**UVM**)
  - `seed_partition` (**UVM**)
  - `isolated_partition` (**UVM**)
  - `seed_read` (**UVM**)

- **1.6**: Two emulated info page windows live on the data partition, each with up to 12 lockable subregions; host access is always blocked.

  To test this, we must see access to the minimum


  Each has up to 12 independently lockable subregions (24 in total).
  They provide info-page-like storage beyond the 8 physical info pages.
  Host access is always blocked.



  Addressed by:
  - `emul_info_window` (**UVM**)
  - `emul_info_subregion` (**UVM**)
  - `emul_info_permissions` (**UVM**)

- **1.7**: Address granularity (byte-addressed, 16-byte RRAM words, 32 words per page).

  Addressed by:
  - `sw_op` (**UVM**)
  - `host_read_direct` (**UVM**)

- **1.8**: Host addresses: the RRAM base address is dropped by the host adapter.

  Addressed by:
  - `smoke` (**UVM**)
  - `host_read_direct` (**UVM**)

## 2. Bus interfaces (TL-UL)

- **2.1**: `core_tl` is a TL-UL device interface carrying registers, FIFO windows and SW transactions.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `csr_rw` (**UVM**)
  - `tl_d_oob_addr_access` (**UVM**)
  - `tl_d_illegal_access` (**UVM**)
  - `tl_d_outstanding_access` (**UVM**)
  - `tl_d_partial_access` (**UVM**)

- **2.2**: `host_tl` is read-only and limited to the data partition; it cannot reach the info partition or the OTP region.

  Addressed by:
  - `host_read_direct` (**UVM**)
  - `otp_region_protection` (**UVM**)

  **Note**: no testpoint checks that a write on `host_tl` is rejected.

- **2.3**: Two separate FIFO access windows, with bus back-pressure when the write FIFO is full or the read FIFO is empty.

  Addressed by:
  - `sw_op` (**UVM**)
  - `interrupts` (**UVM**)

- **2.4**: `wr_fifo` is write-only, `rd_fifo` is read-only; both are single-word windows without byte writes.

  Addressed by:
  - `sw_op` (**UVM**)

  **Note**: no testpoint checks reads of `wr_fifo`, writes of `rd_fifo` or byte writes.

- **2.5**: `wr_fifo` writes with no operation in progress are discarded without error; with RRAM disabled they return a TL-UL error.

  Addressed by: *(none)*

- **2.6**: Host reads carry integrity from `rram_phy_rd`; address infection is removed in `u_tl_adapter_host`.

  Addressed by:
  - `smoke` (**UVM**)
  - `host_read_direct` (**UVM**)
  - `sec_cm_host_bus_integrity` (**UVM**)
  - `sec_cm_mem_addr_infection` (**UVM**)

- **2.7**: TL-UL gating primitives (`HOST_TL_LC_GATE`, `WR_TL_LC_GATE`) have sparse FSMs.

  Addressed by:
  - `sec_cm_host_tl_lc_gate_fsm_sparse` (**UVM**)
  - `sec_cm_wr_tl_lc_gate_fsm_sparse` (**UVM**)

- **2.8**: Command integrity is checked on both `core_tl` and `host_tl`.

  Addressed by:
  - `tl_intg_err` (**UVM**)
  - `sec_cm_reg_bus_integrity` (**UVM**)
  - `sec_cm_host_bus_integrity` (**UVM**)

- **2.9**: Host reads are subject to memory protection.

  Addressed by:
  - `smoke` (**UVM**)
  - `memory_protection` (**UVM**)
  - `otp_region_protection` (**UVM**)
  - `emul_info_window` (**UVM**)
  - `emul_info_window_overlap` (**UVM**)

- **2.10**: Host read error responses (correctable errors fixed and reported; uncorrectable errors give a TL-UL error).

  Addressed by:
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

## 3. Software operation interface (CONTROL / ADDR / FIFOs)

- **3.1**: SW starts an operation by programming `CONTROL` and `ADDR`, then setting `CONTROL.START`.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)

- **3.2**: Supported ops are `Read`, `Write` and `Rewrite`; other values give `ERR_CODE.op_err`.

  Addressed by:
  - `sw_op` (**UVM**)
  - `rewrite_op` (**UVM**)
  - `error_invalid_op` (**UVM**)

- **3.3**: `CONTROL.NUM` is the number of bus words minus 1 (max 1024); it is ignored for a `Rewrite`.

  Addressed by:
  - `sw_op` (**UVM**)
  - `rewrite_op` (**UVM**)

  **Note**: `rewrite_op` does not randomise `NUM` or check that it is ignored.

- **3.4**: Writes must be a multiple of 4 bus words and 16 B aligned.

  Addressed by:
  - `sw_op` (**UVM**)

- **3.5**: `ADDR.START` truncation (reads to bus word, writes to RRAM word).

  Addressed by:
  - `sw_op` (**UVM**)

- **3.6**: `CTRL_REGWEN.EN` is HW-controlled and locks `CONTROL`/`ADDR` during an operation.

  Addressed by:
  - `sec_cm_ctrl_config_regwen` (**UVM**)

- **3.7**: `OP_STATUS.done` and `.err` are set by HW and cleared by SW.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `error_invalid_op` (**UVM**)
  - `rma_sw_dis` (**UVM**)

- **3.8**: `INTR_STATE.op_done` signals completion of Read, Write and Rewrite.

  Addressed by:
  - `sw_op` (**UVM**)
  - `interrupts` (**UVM**)

  **Note**: no testpoint checks `op_done` for a `Rewrite`.

- **3.9**: Write FIFO is 4 entries, read FIFO is 16 entries.

  Addressed by:
  - `sw_op` (**UVM**)
  - `interrupts` (**UVM**)

- **3.10**: `FIFO_LVL.WR`/`FIFO_LVL.RD` set the `wr_lvl`/`rd_lvl` interrupt watermarks.

  Addressed by:
  - `interrupts` (**UVM**)

- **3.11**: `CURR_FIFO_LVL` gives the current WR and RD levels.

  Addressed by:
  - `sw_op` (**UVM**)

- **3.12**: `FIFO_CLR` clears the write and read FIFOs individually.

  Addressed by: *(none)*

- **3.13**: `STATUS` fields and reset value 0xA.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `seed_read` (**UVM**)
  - `csr_hw_reset` (**UVM**)

- **3.14**: An operation started when RRAM is not accessible (before init/key load, or after RMA entry) is rejected with `ERR_CODE.op_err`.

  Addressed by:
  - `rma_sw_dis` (**UVM**)

  **Note**: no testpoint starts an operation before init and key load have completed.

- **3.15**: FIFO pointers use duplicate counters (`FIFO.CTR.REDUN`).

  Addressed by:
  - `sec_cm_fifo_ctr_redun` (**UVM**)

- **3.16**: Starting a write clears the write FIFO.

  Addressed by: *(none)*

- **3.17**: FIFO flow control during an operation (stall on full read FIFO / empty write FIFO).

  Addressed by:
  - `sw_op` (**UVM**)

- **3.18**: A multi-word operation aborts at the first error and `ERR_ADDR` records its address.

  Addressed by:
  - `memory_protection` (**UVM**)
  - `otp_region_protection` (**UVM**)
  - `emul_info_window` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

- **3.19**: On a multi-word read error, the full number of words is returned, all-ones from the failing word onwards.

  Addressed by:
  - `ecc_uncorr_err` (**UVM**)

  **Note**: only checked for uncorrectable ECC errors, not for reads that fail memory protection part-way.

## 4. Memory protection

- **4.1**: 10 data-partition MP regions (`MP_REGION_n`, `MP_REGION_CFG_n`), disabled at reset.

  Addressed by:
  - `smoke` (**UVM**)
  - `memory_protection` (**UVM**)
  - `csr_hw_reset` (**UVM**)

- **4.2**: A disabled region is not matched.

  Addressed by:
  - `memory_protection` (**UVM**)

- **4.3**: `DEFAULT_REGION` applies when no region matches, and denies all access at reset.

  Addressed by:
  - `memory_protection` (**UVM**)
  - `csr_hw_reset` (**UVM**)

- **4.4**: Per-page info partition protection with `INFO_PAGE_CFG_n`, disabled at reset.

  Addressed by:
  - `smoke` (**UVM**)
  - `memory_protection` (**UVM**)
  - `seed_partition` (**UVM**)
  - `isolated_partition` (**UVM**)

- **4.5**: Separate `rw0c` REGWENs for data regions and info pages.

  Addressed by:
  - `regwen_csr_and_corresponding_lockable_csr` (**UVM**)
  - `sec_cm_data_regions_config_regwen` (**UVM**)
  - `sec_cm_info_page_config_regwen` (**UVM**)

- **4.6**: Two emulated info windows (`EMUL_INFO_REGION_n`), lockable with `EMUL_INFO_REGWEN_n`, placed anywhere in the data partition.

  Addressed by:
  - `emul_info_window` (**UVM**)
  - `regwen_csr_and_corresponding_lockable_csr` (**UVM**)

- **4.7**: Window `EN` bits: deny gaps, block host, fail closed on overlap, deny entry independent of REGWEN.

  Addressed by:
  - `emul_info_window` (**UVM**)
  - `emul_info_window_overlap` (**UVM**)

  **Note**: no testpoint varies the order in which overlapping windows are configured and locked, or checks the fault case where the regwen flips back to 1.

- **4.8**: 24 emulated subregions with top-of-range addressing.

  Addressed by:
  - `emul_info_subregion` (**UVM**)

- **4.9**: Conditions for a subregion to be active.

  Addressed by:
  - `emul_info_subregion` (**UVM**)
  - `emul_info_window_overlap` (**UVM**)

- **4.10**: Subregion permissions in `EMUL_INFO_SUBREGION_CFG_n`, with an optional separate lock.

  Addressed by:
  - `emul_info_permissions` (**UVM**)

- **4.11**: `HW_INFO_CFG_OVERRIDE` (`SCRAMBLE_DIS`, `ECC_DIS`) for the lcmgr info page (MuBi4True disables, MuBi4False keeps the hardwired rules).

  Addressed by: *(none)*

- **4.12**: Info-partition access is gated by `lc_ctrl` enables, ANDed with `INFO_PAGE_CFG_n`.

  Addressed by:
  - `seed_partition` (**UVM**)
  - `isolated_partition` (**UVM**)

- **4.13**: A permission violation in a SW-initiated transaction sets `ERR_CODE.mp_err` and latches `ERR_ADDR`.

  Addressed by:
  - `smoke` (**UVM**)
  - `memory_protection` (**UVM**)
  - `otp_region_protection` (**UVM**)
  - `seed_partition` (**UVM**)
  - `isolated_partition` (**UVM**)
  - `emul_info_window` (**UVM**)
  - `emul_info_permissions` (**UVM**)

- **4.14**: Four controller-path requesters (`SwSel`, `HwOtpSel`, `HwLcMgrSel`, `HwLoopBack`).

  Addressed by:
  - `smoke` (**UVM**)
  - `rewrite_op` (**UVM**)
  - `hw_sw_arb` (**UVM**)
  - `rma` (**UVM**)

- **4.15**: Priority order for software data-partition accesses (OTP exclusion, subregions, window deny, MP regions, default).

  Addressed by:
  - `otp_region_protection` (**UVM**)
  - `emul_info_window` (**UVM**)
  - `emul_info_window_overlap` (**UVM**)

- **4.16**: Hardware requesters bypass software-configured protection.

  Addressed by:
  - `smoke` (**UVM**)
  - `rewrite_op` (**UVM**)
  - `rma` (**UVM**)

  **Note**: no testpoint makes the software configuration deny OTP or lcmgr accesses and checks they still succeed.

- **4.17**: OTP hardware plug protection: OTP pages only, fixed attributes.

  Addressed by:
  - `otp_standalone` (**UVM**)

- **4.18**: LCMGR hardware plug protection is phase-dependent (`PhaseSeed`, `PhaseRma`).

  Addressed by:
  - `seed_read` (**UVM**)
  - `rma` (**UVM**)

  **Note**: only the allowed accesses are checked; nothing checks that accesses outside the current phase are denied.

- **4.19**: `addr_xor_en` is hardwired, not software-configurable.

  Addressed by:
  - `smoke` (**UVM**)
  - `otp_standalone` (**UVM**)
  - `sec_cm_mem_addr_infection` (**UVM**)

## 5. Scrambling, address infection and ECC

- **5.1**: Optional per-region XEX/PRINCE scrambling (`SCRAMBLE_EN`).

  Addressed by:
  - `smoke` (**UVM**)
  - `memory_protection` (**UVM**)
  - `emul_info_permissions` (**UVM**)
  - `sec_cm_mem_scramble` (**UVM**)

- **5.2**: Scrambling keys are sideloaded from OTP and not readable by SW.

  Addressed by:
  - `smoke` (**UVM**)
  - `sec_cm_scramble_key_sideload` (**UVM**)

- **5.3**: Address-XOR infection on write, removed on read; disabled for OTP accesses.

  Addressed by:
  - `smoke` (**UVM**)
  - `host_read_direct` (**UVM**)
  - `otp_standalone` (**UVM**)
  - `sec_cm_mem_addr_infection` (**UVM**)

- **5.4**: ECC is done by the macro, controlled by `ecc_en` from the region config.

  Addressed by:
  - `memory_protection` (**UVM**)
  - `emul_info_permissions` (**UVM**)
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

- **5.5**: Correctable ECC counters (`CORR1_ERR_CNT`, `CORR2_ERR_CNT`) and interrupts.

  Addressed by:
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)
  - `otp_macro_ecc_err` (**UVM**)

- **5.6**: The counters are 8 bits wide and saturate.

  Addressed by: *(none)*

- **5.7**: `CORR1_ERR_LOC`/`CORR2_ERR_LOC` hold the last corrected address and partition.

  Addressed by:
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)
  - `otp_macro_ecc_err` (**UVM**)

- **5.8**: Uncorrectable ECC error sets `FAULT_STATUS.phy_relbl_err` and raises `fatal_err`.

  Addressed by:
  - `ecc_uncorr_err` (**UVM**)
  - `local_esc_relbl_err` (**UVM**)
  - `otp_macro_ecc_err` (**UVM**)

- **5.9**: `Rewrite` reads and writes back one corrected RRAM word.

  Addressed by:
  - `rewrite_op` (**UVM**)
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)

  **Note**: no testpoint checks `OP_STATUS.done`/`op_done` after a rewrite, or the error reporting when the internal read or write fails.

- **5.10**: Read-set-write capability used for emulated OTP semantics.

  Addressed by:
  - `otp_standalone` (**UVM**)
  - `otp_write_blank_err` (**UVM**)

- **5.11**: Corrected errors don't abort operations.

  Addressed by:
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)

- **5.12**: A corrected error is reported once per RRAM read (not again by the shadow read).

  Addressed by:
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)

- **5.13**: XEX construction with two interleaved PRINCE instances and `cipher_switch`.

  Addressed by:
  - `smoke` (**UVM**)
  - `sec_cm_mem_scramble` (**UVM**)
  - `sec_cm_mem_readback` (**UVM**)

- **5.14**: Scrambling key management (netlist constants before `keys_valid`, random keys after disable).

  Addressed by:
  - `smoke` (**UVM**)
  - `sec_cm_scramble_key_sideload` (**UVM**)

  **Note**: no testpoint checks the keys used before `keys_valid` or the switch to random keys after disable.

- **5.15**: Write data path ordering, with zero-fill and `wr_intg_err` on bus-integrity failure.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `sec_cm_mem_bus_integrity` (**UVM**)

- **5.16**: Read data path integrity computation.

  Addressed by:
  - `smoke` (**UVM**)
  - `host_read_direct` (**UVM**)

- **5.17**: Scrambling setting is not stored in the macro.

  Addressed by:
  - `memory_protection` (**UVM**)
  - `emul_info_permissions` (**UVM**)

## 6. Emulated OTP (`rram_ctrl_otp`)

- **6.1**: `rram_ctrl` implements the `otp_macro` request/response interface.

  Addressed by:
  - `smoke` (**UVM**)
  - `otp_standalone` (**UVM**)

- **6.2**: OTP command set and access sizes.

  Addressed by:
  - `otp_standalone` (**UVM**)

- **6.3**: OTP bits can only be set; clearing gives `MacroWriteBlankError`.

  Addressed by:
  - `otp_standalone` (**UVM**)
  - `otp_write_blank_err` (**UVM**)

- **6.4**: Hamming (72,64) OTP integrity page.

  Addressed by:
  - `otp_standalone` (**UVM**)
  - `otp_intg_err` (**UVM**)
  - `sec_cm_otp_mem_integrity` (**UVM**)

- **6.5**: Integrity checking and update per OTP command.

  Addressed by:
  - `otp_standalone` (**UVM**)
  - `otp_intg_err` (**UVM**)
  - `sec_cm_mem_readback` (**UVM**)

  **Note**: no testpoint makes the post-write readback compare fail.

- **6.6**: Response signals `fatal_lc_fsm_err`, `fatal_alert` and `recov_alert` on `otp_macro_o`.

  Addressed by: *(none)*

- **6.7**: OTP error reporting in `FAULT_STATUS` and `STD_FAULT_STATUS`.

  Addressed by:
  - `otp_macro_ecc_err` (**UVM**)
  - `sec_cm_ctrl_fsm_sparse` (**UVM**)
  - `sec_cm_ctr_redun` (**UVM**)
  - `sec_cm_mem_bus_integrity` (**UVM**)

  **Note**: nothing triggers `otp_op_err` or `otp_mp_err`.

- **6.8**: The OTP region is only reachable through the OTP HW interface, without scrambling or address infection.

  Addressed by:
  - `otp_standalone` (**UVM**)
  - `otp_region_protection` (**UVM**)
  - `emul_info_window` (**UVM**)

- **6.9**: `rram_ctrl_otp` FSM is sparse and its counters are redundant.

  Addressed by:
  - `sec_cm_ctrl_fsm_sparse` (**UVM**)
  - `sec_cm_ctr_redun` (**UVM**)

- **6.10**: OTP clock domain crossing.

  Addressed by: *(none)*

- **6.11**: Macro ECC on the OTP path: correctable errors are invisible, uncorrectable errors give `MacroError`.

  Addressed by:
  - `otp_macro_ecc_err` (**UVM**)

  **Note**: the testplan disagrees with the requirement. `otp_macro_ecc_err` expects corrected OTP words to raise `corr1_err`/`corr2_err` and update the counters, but 6.11 says they "never surface as an error".

- **6.12**: OTP bus integrity on read words; integrity added to written words.

  Addressed by:
  - `sec_cm_mem_bus_integrity` (**UVM**)

## 7. Life cycle, key manager and power manager interactions

### 7a. Initialisation and seeds

- **7a.1**: `INIT.VAL` requests keys and reads seeds before allowing other use.

  Addressed by:
  - `smoke` (**UVM**)
  - `seed_read` (**UVM**)

- **7a.2**: Initialisation status reporting (`STATUS.init_done`, `STATUS.keys_valid`, `PHY_STATUS.init_done`).

  Addressed by:
  - `smoke` (**UVM**)
  - `seed_read` (**UVM**)

- **7a.3**: Seeds read twice, compared, and forwarded to `keymgr_dpe` with `seed_valid`.

  Addressed by:
  - `seed_read` (**UVM**)
  - `seed_read_err` (**UVM**)

  **Note**: no testpoint checks that `seed_valid` is cleared when the controller is disabled by `DIS.SW_DIS` or escalation.

- **7a.4**: `lc_seed_hw_rd_en` gates the HW seed read.

  Addressed by:
  - `seed_read` (**UVM**)

- **7a.5**: Phy initialisation precedes all accesses.

  Addressed by:
  - `smoke` (**UVM**)

  **Note**: `smoke` waits for `PHY_STATUS.init_done`; no testpoint checks that accesses before then are blocked.

- **7a.6**: Seed integrity checking in `rram_ctrl_lcmgr`.

  Addressed by:
  - `seed_read_err` (**UVM**)

- **7a.7**: RMA request during initialisation skips the rest of init; RMA entry after initialisation reseeds the LFSR from `rma_seed`.

  Addressed by:
  - `rma` (**UVM**)

### 7b. Life cycle controller

- **7b.1**: `lc_escalate_en` disables all RRAM accesses.

  Addressed by:
  - `sec_cm_mem_ctrl_global_esc` (**UVM**)

- **7b.2**: `lc_tx` signals use MuBi-style encodings.

  Addressed by:
  - `seed_partition` (**UVM**)
  - `isolated_partition` (**UVM**)
  - `seed_read` (**UVM**)
  - `sec_cm_lc_ctrl_intersig_mubi` (**UVM**)

### 7c. RMA secure wipe

- **7c.1**: On `rma_req`, the lcmgr wipes the seed, isolated and non-OTP data pages with LFSR data, then asserts `rma_ack`.

  Addressed by:
  - `rma` (**UVM**)
  - `sec_cm_rma_entry_mem_sec_wipe` (**UVM**)

- **7c.2**: After RMA, SW access is disabled until reset; OTP and lcmgr interfaces are unaffected.

  Addressed by:
  - `rma` (**UVM**)
  - `rma_sw_dis` (**UVM**)

- **7c.3**: SW access is disabled from the start of RMA entry.

  Addressed by:
  - `rma_sw_dis` (**UVM**)

- **7c.d**: RMA-phase counters are redundant.

  Addressed by:
  - `sec_cm_ctr_redun` (**UVM**)

- **7c.e**: LCMGR errors are reported in `FAULT_STATUS` and `STD_FAULT_STATUS`.

  Addressed by:
  - `seed_read_err` (**UVM**)
  - `sec_cm_ctrl_fsm_sparse` (**UVM**)
  - `sec_cm_ctr_redun` (**UVM**)

  **Note**: nothing triggers `lcmgr_op_err`, `lcmgr_mp_err`, `lcmgr_rd_err` or `lcmgr_wr_err`.

- **7c.6**: RMA waits for an in-progress software operation.

  Addressed by:
  - `rma` (**UVM**)
  - `rma_sw_dis` (**UVM**)

- **7c.7**: Wipe and verify procedure with running XOR digests.

  Addressed by:
  - `rma` (**UVM**)
  - `sec_cm_rma_entry_mem_sec_wipe` (**UVM**)

- **7c.8**: RMA failure leaves the FSM in `StInvalid`, disables the controller and withholds `rma_ack`.

  Addressed by: *(none)*

- **7c.9**: Registers remain accessible after RMA.

  Addressed by:
  - `rma` (**UVM**)

### 7d. Power manager

- **7d.1**: Idle reporting to `pwrmgr`.

  Addressed by:
  - `idle` (**UVM**)

- **7d.2**: `PHY_STATUS.wr_busy` indicates the phy is writing.

  Addressed by: *(none)*

## 8. RRAM phy behaviour

- **8.1**: The phy bridges 32-bit bus words to the 128-bit macro word and arbitrates host vs controller.

  Addressed by:
  - `smoke` (**UVM**)
  - `host_controller_arb` (**UVM**)

- **8.2**: Data paths through `rram_phy_rd` and `rram_phy_wr`.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)
  - `host_read_direct` (**UVM**)
  - `rd_buf_eviction` (**UVM**)

- **8.3**: The 4-entry read buffer, invalidated on writes to the same page.

  Addressed by:
  - `host_read_direct` (**UVM**)
  - `rd_buf_eviction` (**UVM**)

- **8.4**: Shadow reads, with a mismatch raising `FAULT_STATUS.phy_rd_intg_err`.

  Addressed by:
  - `sec_cm_mem_readback` (**UVM**)
  - `sec_cm_phy_rd_buf_ctrl_integrity` (**UVM**)

- **8.5**: Up to 2 outstanding host reads; one outstanding controller operation.

  Addressed by:
  - `host_read_direct` (**UVM**)

- **8.6**: Phy consistency checks (host grant, origin metadata, `spurious_done`).

  Addressed by:
  - `sec_cm_phy_host_grant_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rsp_ctrl_consistency` (**UVM**)

- **8.7**: Read path control flow checks (`phy_rd_ctrl_err`).

  Addressed by:
  - `sec_cm_phy_rd_rsp_ctrl_integrity` (**UVM**)
  - `sec_cm_phy_rsp_ctrl_consistency` (**UVM**)

- **8.8**: Duplicated phy arbiters, sparse `rram_phy_wr` FSM, redundant counters.

  Addressed by:
  - `sec_cm_phy_arbiter_ctrl_redun` (**UVM**)
  - `sec_cm_phy_wr_fsm_sparse` (**UVM**)
  - `sec_cm_ctr_redun` (**UVM**)

- **8.9**: Phy arbitration suppression rules.

  Addressed by:
  - `host_controller_arb` (**UVM**)
  - `hw_sw_arb` (**UVM**)

- **8.10**: Read pipeline latency and buffer states.

  Addressed by:
  - `host_read_direct` (**UVM**)

- **8.11**: Multi-page writes are split into per-page macro writes.

  Addressed by:
  - `sw_op` (**UVM**)

## 9. RRAM macro interface

- **9.1**: Macro request signals.

  Addressed by:
  - `smoke` (**UVM**)
  - `sw_op` (**UVM**)

  **Note**: only covered implicitly by the datapath testpoints.

- **9.2**: Macro response signals.

  Addressed by:
  - `smoke` (**UVM**)
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

  **Note**: no testpoint drives the macro's `err`, `fatal_err` or `recov_err` responses.

- **9.3**: `ecc_err` one-hot0 encoding.

  Addressed by:
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

- **9.4**: Macro handshake (stable until `ack`, one `ack` per request).

  Addressed by: *(none)*

- **9.5**: Macro write sequence (push words, commit with `wr_last`).

  Addressed by:
  - `sw_op` (**UVM**)

## 10. Interrupts

- **10.1**: Seven interrupts (`wr_empty`, `wr_lvl`, `rd_full`, `rd_lvl`, `op_done`, `corr1_err`, `corr2_err`).

  Addressed by:
  - `interrupts` (**UVM**)
  - `intr_test` (**UVM**)
  - `ecc_corr1_err` (**UVM**)
  - `ecc_corr2_err` (**UVM**)

- **10.2**: `INTR_STATE` reset is 0x3.

  Addressed by:
  - `csr_hw_reset` (**UVM**)

- **10.3**: Level interrupts `wr_lvl` and `rd_lvl`.

  Addressed by:
  - `interrupts` (**UVM**)

- **10.4**: `INTR_ENABLE`/`INTR_TEST` follow the standard pattern.

  Addressed by:
  - `intr_test` (**UVM**)

## 11. Alerts, error and fault reporting

- **11.1**: Five alerts and `ALERT_TEST`.

  Addressed by:
  - `alert_test` (**UVM**)

- **11.2**: `recov_err` fires when a SW operation completes with any `ERR_CODE` bit set.

  Addressed by:
  - `memory_protection` (**UVM**)
  - `emul_info_window` (**UVM**)
  - `error_invalid_op` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

- **11.3**: `fatal_std_err` fires when any `STD_FAULT_STATUS` bit is set.

  Addressed by:
  - `tl_intg_err` (**UVM**)
  - `seed_read_err` (**UVM**)
  - `sec_cm_reg_bus_integrity` (**UVM**)
  - `sec_cm_ctrl_fsm_sparse` (**UVM**)
  - `sec_cm_ctr_redun` (**UVM**)
  - `sec_cm_fifo_ctr_redun` (**UVM**)
  - `sec_cm_phy_arbiter_ctrl_redun` (**UVM**)
  - `sec_cm_phy_wr_fsm_sparse` (**UVM**)

- **11.4**: `fatal_err` fires when any `FAULT_STATUS` bit is set.

  Addressed by:
  - `ecc_uncorr_err` (**UVM**)
  - `local_esc_relbl_err` (**UVM**)
  - `otp_macro_ecc_err` (**UVM**)
  - `seed_read_err` (**UVM**)
  - `sec_cm_mem_readback` (**UVM**)
  - `sec_cm_phy_host_grant_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rsp_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rd_rsp_ctrl_integrity` (**UVM**)

- **11.5**: Macro error alerts `fatal_macro_err` and `recov_macro_err`.

  Addressed by:
  - `alert_test` (**UVM**)

  **Note**: only `ALERT_TEST` is covered; no testpoint triggers the alerts from the macro.

- **11.6**: `ERR_CODE` (`op_err`, `mp_err`, `rd_err`, `wr_err`) and `ERR_ADDR`.

  Addressed by:
  - `memory_protection` (**UVM**)
  - `error_invalid_op` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

  **Note**: nothing triggers `ERR_CODE.wr_err`.

- **11.7**: `phy_relbl_err` is clearable but clearing it doesn't undo escalation.

  Addressed by:
  - `ecc_uncorr_err` (**UVM**)
  - `local_esc_relbl_err` (**UVM**)

- **11.8**: `FAULT_STATUS` bit list.

  Addressed by:
  - `ecc_uncorr_err` (**UVM**)
  - `otp_macro_ecc_err` (**UVM**)
  - `seed_read_err` (**UVM**)
  - `sec_cm_mem_readback` (**UVM**)
  - `sec_cm_phy_host_grant_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rsp_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rd_rsp_ctrl_integrity` (**UVM**)

- **11.9**: An integrity-caused `rd_err`/`wr_err` also sets the matching fault bit.

  Addressed by:
  - `sec_cm_mem_bus_integrity` (**UVM**)

## 12. Disable, execute and escalation controls

- **12.1**: `DIS.SW_DIS` disables RRAM until reset.

  Addressed by:
  - `sec_cm_mem_disable_config_mubi` (**UVM**)

- **12.2**: `DIS.LOCAL_ESC_RELBL_ERR` makes `phy_relbl_err` disable the RRAM.

  Addressed by:
  - `local_esc_relbl_err` (**UVM**)
  - `ecc_uncorr_err` (**UVM**)

  **Note**: `ecc_uncorr_err` refers to this field by an old name, `DIS.RELBL_ERR_FATAL`.

- **12.3**: `EXEC.EN` magic value controls code execution from RRAM.

  Addressed by:
  - `sec_cm_exec_config_redun` (**UVM**)

- **12.4**: Global escalation makes memory inaccessible.

  Addressed by:
  - `sec_cm_mem_ctrl_global_esc` (**UVM**)

- **12.5**: Local escalation on a subset of fatal errors, latched until reset.

  Addressed by:
  - `sec_cm_mem_ctrl_local_esc` (**UVM**)
  - `local_esc_relbl_err` (**UVM**)
  - `seed_read_err` (**UVM**)

- **12.6**: Effect of disable (requests blocked, random keys, `seed_valid` cleared, registers accessible).

  Addressed by:
  - `sec_cm_mem_ctrl_global_esc` (**UVM**)
  - `sec_cm_mem_ctrl_local_esc` (**UVM**)
  - `sec_cm_mem_disable_config_mubi` (**UVM**)
  - `local_esc_relbl_err` (**UVM**)

  **Note**: no testpoint checks the switch to random keys or the clearing of `seed_valid`.

## 13. Security countermeasures

- **Bus integrity**: `REG.BUS.INTEGRITY`, `HOST.BUS.INTEGRITY`, `MEM.BUS.INTEGRITY` (**UVM**)

  Addressed by:
  - `tl_intg_err` (**UVM**)
  - `sec_cm_reg_bus_integrity` (**UVM**)
  - `sec_cm_host_bus_integrity` (**UVM**)
  - `sec_cm_mem_bus_integrity` (**UVM**)

- **Data protection**: `MEM.ADDR_INFECTION`, `MEM.SCRAMBLE`, `SCRAMBLE.KEY.SIDELOAD`, `MEM.INTEGRITY`, `OTP.MEM.INTEGRITY`, `MEM.READBACK` (**UVM**)

  Addressed by:
  - `sec_cm_mem_addr_infection` (**UVM**)
  - `sec_cm_mem_scramble` (**UVM**)
  - `sec_cm_scramble_key_sideload` (**UVM**)
  - `sec_cm_mem_integrity` (**UVM**)
  - `sec_cm_otp_mem_integrity` (**UVM**)
  - `sec_cm_mem_readback` (**UVM**)

- **Config locking**: `CTRL.CONFIG.REGWEN`, `DATA_REGIONS.CONFIG.REGWEN`, `INFO_PAGE.CONFIG.REGWEN` (**UVM**)

  Addressed by:
  - `sec_cm_ctrl_config_regwen` (**UVM**)
  - `sec_cm_data_regions_config_regwen` (**UVM**)
  - `sec_cm_info_page_config_regwen` (**UVM**)

- **Disable and escalation**: `MEM.CTRL.GLOBAL_ESC`, `MEM.CTRL.LOCAL_ESC`, `MEM_DISABLE.CONFIG.MUBI`, `EXEC.CONFIG.REDUN`, `LC_CTRL.INTERSIG.MUBI` (**UVM**)

  Addressed by:
  - `sec_cm_mem_ctrl_global_esc` (**UVM**)
  - `sec_cm_mem_ctrl_local_esc` (**UVM**)
  - `sec_cm_mem_disable_config_mubi` (**UVM**)
  - `sec_cm_exec_config_redun` (**UVM**)
  - `sec_cm_lc_ctrl_intersig_mubi` (**UVM**)

- **Secure wipe**: `RMA_ENTRY.MEM.SEC_WIPE` (**UVM**)

  Addressed by:
  - `sec_cm_rma_entry_mem_sec_wipe` (**UVM**)
  - `rma` (**UVM**)

- **Sparse FSMs**: `CTRL.FSM.SPARSE`, `PHY_WR.FSM.SPARSE`, `HOST_TL_LC_GATE.FSM.SPARSE`, `WR_TL_LC_GATE.FSM.SPARSE` (**UVM**)

  Addressed by:
  - `sec_cm_ctrl_fsm_sparse` (**UVM**)
  - `sec_cm_phy_wr_fsm_sparse` (**UVM**)
  - `sec_cm_host_tl_lc_gate_fsm_sparse` (**UVM**)
  - `sec_cm_wr_tl_lc_gate_fsm_sparse` (**UVM**)

- **Redundant counters, arbiters and FIFOs**: `CTR.REDUN`, `FIFO.CTR.REDUN`, `PHY_ARBITER.CTRL.REDUN` (**UVM**)

  Addressed by:
  - `sec_cm_ctr_redun` (**UVM**)
  - `sec_cm_fifo_ctr_redun` (**UVM**)
  - `sec_cm_phy_arbiter_ctrl_redun` (**UVM**)

- **Consistency checks**: `PHY_HOST_GRANT.CTRL.CONSISTENCY`, `PHY_RSP.CTRL.CONSISTENCY`, `PHY_RD_RSP.CTRL.INTEGRITY`, `PHY_RD_BUF.CTRL.INTEGRITY` (**UVM**)

  Addressed by:
  - `sec_cm_phy_host_grant_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rsp_ctrl_consistency` (**UVM**)
  - `sec_cm_phy_rd_rsp_ctrl_integrity` (**UVM**)
  - `sec_cm_phy_rd_buf_ctrl_integrity` (**UVM**)

## 14. Register-level conventions

- **14.1**: MuBi4 encoding for enable/disable fields, reset to MuBi4False.

  Addressed by:
  - `csr_hw_reset` (**UVM**)
  - `memory_protection` (**UVM**)
  - `emul_info_permissions` (**UVM**)
  - `sec_cm_mem_disable_config_mubi` (**UVM**)

- **14.2**: Software-writable REGWENs are `rw0c`, reset 1, one-way.

  Addressed by:
  - `csr_rw` (**UVM**)
  - `regwen_csr_and_corresponding_lockable_csr` (**UVM**)
  - `sec_cm_data_regions_config_regwen` (**UVM**)
  - `sec_cm_info_page_config_regwen` (**UVM**)

- **14.3**: `DIS` fields, `INIT.VAL` and similar are `rw1s`.

  Addressed by:
  - `csr_rw` (**UVM**)
  - `csr_bit_bash` (**UVM**)

- **14.4**: Registers have the reset values described in the hjson.

  Addressed by:
  - `csr_hw_reset` (**UVM**)

- **14.5**: Register bus integrity is checked and sets `STD_FAULT_STATUS.reg_intg_err`.

  Addressed by:
  - `tl_intg_err` (**UVM**)
  - `sec_cm_reg_bus_integrity` (**UVM**)

## Summary of gaps

No testpoint addresses these requirements:
- **2.5**: `wr_fifo` writes with no operation in progress, or with RRAM disabled
- **3.12**: `FIFO_CLR`
- **3.16**: starting a write clears the write FIFO
- **4.11**: `HW_INFO_CFG_OVERRIDE`
- **5.6**: saturation of the correctable error counters
- **6.6**: `otp_macro_o` alert / LC FSM error signals
- **6.10**: OTP clock domain crossing
- **7c.8**: RMA wipe or verify failure
- **7d.2**: `PHY_STATUS.wr_busy`
- **9.4**: macro handshake rules

These are only partly addressed (see the **Note** on each):
2.2, 2.4, 3.3, 3.8, 3.14, 3.19, 4.7, 4.16, 4.18, 5.9, 5.14, 6.5, 6.7, 6.11, 7a.3, 7a.5, 7c.e, 9.1, 9.2, 11.5, 11.6, 12.2, 12.6.
