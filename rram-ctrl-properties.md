# rram_ctrl: properties inferred from documentation

Sources: `hw/ip/rram_ctrl/README.md`, `doc/interfaces.md`, `doc/registers.md`.

These are properties the documentation implies the block should satisfy. They have not been checked against the RTL. Each is phrased so it could become an assertion, a scoreboard check or a directed test.
"MuBi4False" is `4'h9` and "MuBi4True" is `4'h6`. Several registers use `0x9` as the reset value, which means "false/disabled".

## 1. Geometry and address map

- **GEO-1**: A RRAM word is 128 bits (16 B), a page is 32 words (512 B), and a bus word is 32 bits.
- **GEO-2**: The data partition has 4096 pages (2 MiB, byte addresses `0x000000`–`0x1FFFFF`), which fits the 21-bit `ADDR.START`/`ERR_ADDR` fields.
- **GEO-3**: The info partition has 8 pages. Page 5 is `CreatorInfoPage` (`0xA00`), page 6 is `OwnerInfoPage` (`0xC00`) and page 7 is `IsolatedInfoPage` (`0xE00`).
- **GEO-4**: The data partition and the info partition are separately addressed spaces. Each starts at `0x000000`, and `CONTROL.PARTITION` selects between them.
- **GEO-5**: The top 6 data pages (4090–4095) are reserved for emulated OTP and are never accessible to host or software.
  - Page 4090 (`OtpIntgStartAddr` = `0x1FF400`) holds the OTP integrity words.
  - Pages 4091–4095 (`OtpStartAddr` = `0x1FF600`) hold OTP data.
  - Only `rram_ctrl_otp` (otp-hw-if) can reach these pages.
- **GEO-6**: Data pages 0–4089 are accessible to the host (read only), to software and to the lcmgr hardware interface.
- **GEO-7**: Info pages are accessible to software and to the lcmgr hardware interface, never to the host.
- **GEO-8**: The host-visible address is the RRAM base address (from the top-level map) plus the byte address.

## 2. Bus interfaces

- **BUS-1**: `core_tl` serves the register file and the FIFO windows. It can reach both partitions through software-initiated operations.
- **BUS-2**: `host_tl` is read-only and limited to the data partition.
  - Any write attempt on `host_tl` returns an error response.
  - Any host access to an info page, an OTP page or an emulated info window is blocked and never returns RRAM data.
- **BUS-3**: Both TL-UL interfaces carry end-to-end integrity.
  - A command integrity failure on `core_tl` sets `STD_FAULT_STATUS.reg_intg_err`.
  - Integrity is generated in `rram_phy_rd` and stored with the read-buffer data. It is passed to `host_tl` and to the controller read path.
- **BUS-4**: `wr_fifo` (`0x2b4`) is a write-only, one-word window and `rd_fifo` (`0x2b8`) is a read-only, one-word window.
  - Neither supports byte writes.
  - Both back-pressure the bus when the FIFO is full (write) or empty (read) instead of returning errors.
- **BUS-5**: Software can only push data into `wr_fifo` after a write operation has been started through `CONTROL`. Accidental writes cannot lock up the system.
- **BUS-6**: `rram_ctrl` is a rsp-side device on both TL ports (primary clock `clk_i`, with `clk_otp_i` as a second clock). It is not a bus host and has no chip IO pins.

## 3. Initialisation and global enables

- **INIT-1**: `INIT.VAL` is rw1s. After it is set it cannot be cleared by software.
- **INIT-2**: After `INIT.VAL` is set the controller requests the scramble keys and reads the creator and owner seeds from the info pages. Normal operation is not allowed until this completes.
- **INIT-3**: `STATUS.keys_valid` and `STATUS.init_done` are 0 at reset and rise only after initialisation completes. `PHY_STATUS.init_done` is 0 at reset and means the RRAM is also initialised.
- **INIT-4**: A software operation started before `init_done` and `keys_valid` are both set does not execute. It sets `ERR_CODE.op_err`.
- **INIT-5**: A seed reading failure sets `FAULT_STATUS.seed_err`.
- **INIT-6**: The seeds read during init are forwarded on `keymgr_creator_seed` and `keymgr_owner_seed`.
  - The creator seed is gated by `lc_creator_seed_sw_rw_en`/`lc_seed_hw_rd_en`.
  - The owner seed is gated by `lc_owner_seed_sw_rw_en`/`lc_seed_hw_rd_en`.
- **DIS-1**: `DIS.SW_DIS` and `DIS.LOCAL_ESC_RELBL_ERR` reset to MuBi4False and are rw1s.
  - Once a field is non-False it cannot return to False until reset.
  - Writing MuBi4True to `SW_DIS` disables the RRAM permanently until reset.
- **DIS-2**: While disabled (by `DIS`, by local escalation, by `lc_escalate_en` or after RMA) the memory is inaccessible.
  - Host reads are not served from the RRAM.
  - Software operations are rejected.
  - Instruction fetches are blocked.
- **DIS-3**: `FAULT_STATUS.phy_relbl_err` locally disables the RRAM only if `DIS.LOCAL_ESC_RELBL_ERR` is not MuBi4False.
  - The `fatal_err` alert is raised regardless of that setting.
  - Clearing `phy_relbl_err` does not undo an escalation that has already happened.
- **EXEC-1**: `EXEC.EN` resets to 0. Code execution fetches from the RRAM are permitted only when `EXEC.EN == 32'ha26a38f7`. Any other value blocks them.
- **EXEC-2**: `EXEC.EN` is a plain rw register with no lock.

## 4. Software-initiated operations

- **OP-1**: `CTRL_REGWEN.EN` resets to 1 and is hardware controlled.
  - It drops to 0 when an operation starts.
  - It returns to 1 when the operation completes, whether it succeeds or fails.
  - While it is 0, writes to `CONTROL` and `ADDR` are ignored.
- **OP-2**: `CONTROL.OP` encodes Read (0), Write (1) and Rewrite (2). Other values are reserved. Starting an operation with a reserved `OP` value sets `ERR_CODE.op_err`.
- **OP-3**: `CONTROL.NUM` is the transfer length minus one, so one operation moves 1–1024 bus words.
  - For a Write the word count (`NUM+1`) must be a multiple of 4.
  - A Write is aligned to a 16 B RRAM word.
- **OP-4**: `ADDR.START` is a byte address within the selected partition.
  - Reads truncate it down to a 32-bit word boundary.
  - Writes truncate it down to a 128-bit RRAM word boundary.
- **OP-5**: Completion sets `OP_STATUS.done` and the `op_done` interrupt. An error also sets `OP_STATUS.err`.
  - `OP_STATUS` is set by hardware and cleared by software.
  - `op_done` is an event: it is rw1c in `INTR_STATE` and can be forced through `INTR_TEST`.
- **OP-6**: A Read of N words pushes exactly N words into `rd_fifo` in address order, and the data equals what was previously written (after descramble, address-XOR removal and ECC correction).
- **OP-7**: A Write of N words consumes exactly N words from `wr_fifo`.
  - A write followed by a read of the same location returns the written data.
  - Write data must pass the integrity check in `rram_phy_wr`. A failure sets `STD_FAULT_STATUS.phy_wr_intg_err`.
- **OP-8**: A Rewrite reads the addressed word and writes the corrected value back to the same location. After it, the stored word is ECC-clean, and the logical content is unchanged.
- **OP-9**: Software and hardware operations are arbitrated between three sources: software, lcmgr and otp. The controller handles one at a time. All three share `wr_fifo`, `ctrl_rd`, `ctrl_wr` and pass through the memory protection module (`rram_ctrl_mp`).
- **OP-10**: Software operations are rejected with `ERR_CODE.op_err` while software access is disabled, starting from the beginning of the RMA entry process.
- **OP-11**: `ERR_CODE` bits are rw1c and all count as recoverable.
  - A software operation that completes with any `ERR_CODE` bit set fires `recov_err`.
  - `wr_err`, `rd_err` and `mp_err` are synchronous. `ERR_ADDR` captures the failing address for `rd_err` and `mp_err`.

## 5. FIFOs

- **FIFO-1**: `wr_fifo` has 4 entries of 32 bits. `rd_fifo` has 16 entries of 32 bits.
- **FIFO-2**: At reset the write FIFO is empty and the read FIFO is empty.
  - `STATUS.wr_empty` = 1, `STATUS.rd_empty` = 1, `STATUS.wr_full` = 0 and `STATUS.rd_full` = 0.
  - `CURR_FIFO_LVL` is 0.
  - `INTR_STATE.wr_empty` and `INTR_STATE.wr_lvl` read 1.
- **FIFO-3**: `STATUS.*_full` and `STATUS.*_empty` are consistent with `CURR_FIFO_LVL`. The `wr_empty` and `rd_empty` status bits match a level of 0. `wr_full` and `rd_full` match a full FIFO.
- **FIFO-4**: `INTR_STATE.wr_empty` and `INTR_STATE.rd_full` mirror the FIFO state. They are ro status interrupts and need no software clear.
- **FIFO-5**: `INTR_STATE.wr_lvl` is set when the write FIFO level is at or below `FIFO_LVL.WR`. `INTR_STATE.rd_lvl` is set when the read FIFO level is at or above `FIFO_LVL.RD`. Both are ro status interrupts.
- **FIFO-6**: `FIFO_LVL` resets to `WR = RD = 0xf`. The `rd_lvl` interrupt does not fire at reset, and `wr_lvl` fires at reset because the write FIFO is empty.
- **FIFO-7**: Writing 1 to `FIFO_CLR.WR` or `FIFO_CLR.RD` empties the matching FIFO. The register is wo and reads as 0.
- **FIFO-8**: The FIFO read and write pointers use duplicated counters. A mismatch sets `STD_FAULT_STATUS.ctrl_fifo_err` or `phy_fifo_err`.

## 6. Memory protection

- **MP-1**: The data partition has 10 programmable MP regions (`MP_REGION_CFG_n`, `MP_REGION_n`, `REGION_CFG_REGWEN_n`) plus `DEFAULT_REGION`.
- **MP-2**: A region matches an access if `EN == MuBi4True` and the access falls in pages `BASE .. BASE+SIZE`, with `SIZE` encoded as pages minus 1.
  - A disabled region (`EN != MuBi4True`) is never matched.
- **MP-3**: If no region matches, `DEFAULT_REGION` applies. It has no `EN` field.
- **MP-4**: Each region field (`EN`, `RD_EN`, `WR_EN`, `SCRAMBLE_EN`, `ECC_EN`) is a MuBi4 value. Only MuBi4True enables the feature. A value of 0x9 or any invalid encoding means "not enabled".
- **MP-5**: After reset every field is `0x9`, so all accesses (reads, writes, scrambling, ECC) are denied or disabled until software configures them.
- **MP-6**: An access that matches a region but lacks the needed permission (`RD_EN` for a read, `WR_EN` for a write or rewrite) is denied.
  - It sets `ERR_CODE.mp_err`.
  - The address is captured in `ERR_ADDR`.
  - No RRAM write occurs.
- **MP-7**: A denied or failing host read gets a TL-UL error response.
- **MP-8**: Each info page has its own `INFO_PAGE_CFG_n` and `INFO_REGWEN_n` (8 pages, one per page). Info page rules use the same field layout as the MP regions.
- **MP-9**: The software interface uses a mix of software-configured and hardware-overridden rules.
  - Hardware interfaces (lcmgr and otp) use fixed compile-time rules.
  - `HW_INFO_CFG_OVERRIDE.SCRAMBLE_DIS` and `ECC_DIS` are ANDed with the hardwired rules. They can only turn scramble or ECC off for the hardware interfaces, never on.
- **MP-10**: Info partition access for the seed pages and the isolated page is further gated by life cycle signals.
  - The creator page by `lc_creator_seed_sw_rw_en`.
  - The owner page by `lc_owner_seed_sw_rw_en`.
  - The isolated page by `lc_iso_part_sw_rd_en` and `lc_iso_part_sw_wr_en`.
  - A signal that is not MuBi4True (including an invalid encoding) denies the access.
- **MP-11**: Every `*_REGWEN_n` register is rw0c with reset 1.
  - Once cleared it stays 0 until reset.
  - While it is 0, writes to the associated configuration register have no effect.
  - This covers `REGION_CFG_REGWEN`, `INFO_REGWEN`, `EMUL_INFO_REGWEN`, `EMUL_INFO_SUBREGION_REGWEN` and `EMUL_INFO_SUBREGION_CFG_REGWEN`.

## 7. Emulated info windows

- **EMU-1**: There are 2 windows (`EMUL_INFO_REGION_0/1`), each with 12 subregions (24 subregion registers in total).
- **EMU-2**: Host access to an emulated window is always blocked, regardless of configuration.
- **EMU-3**: Once a window is enabled (`EN == MuBi4True`), any access in the window that no enabled subregion covers is denied.
- **EMU-4**: A disabled window, and all its subregions, is not matched against any access.
- **EMU-5**: If two enabled windows overlap, both windows are fully denied and their subregions are disabled.
- **EMU-6**: Subregions use top-of-range addressing relative to the window base. A subregion spans `previous TOP + 1 .. own TOP`.
  - For subregion 0 of a window the range starts at the window base.
  - `TOP` is 8 bits.
- **EMU-7**: A subregion is active only if all of the following hold.
  - Its window is enabled.
  - Its window is locked through `EMUL_INFO_REGWEN`.
  - Its own `EMUL_INFO_SUBREGION_REGWEN` and those of all lower-indexed subregions in the same window are locked.
  - Its `TOP` does not exceed the window `SIZE`.
  - Its window overlaps no other enabled window.
- **EMU-8**: A subregion has no `EN` field. Its permissions (`RD_EN`, `WR_EN`, `SCRAMBLE_EN`, `ECC_EN`) sit at bits [19:4], matching `MP_REGION_CFG`. They are locked independently through `EMUL_INFO_SUBREGION_CFG_REGWEN`.
- **EMU-9**: Reset defaults are `EMUL_INFO_REGION.EN = MuBi4False`, all subregion permissions `0x9` (all off), and all `*_REGWEN = 1`. After reset no emulated window is usable.

## 8. Scrambling, address-XOR and ECC

- **SEC-1**: Scrambling uses PRINCE in an XEX construction. It is applied per region, info page or subregion when `SCRAMBLE_EN` is MuBi4True. Unscrambled regions store data in plaintext.
- **SEC-2**: Reads and writes share one scrambling module, which can both scramble and descramble.
- **SEC-3**: Scrambling keys come from `otp_key` (sideloaded from emulated OTP) and software cannot read them. No register exposes key material. `STATUS.keys_valid` reflects only whether they are loaded.
- **SEC-4**: Write then read through a scramble-enabled region returns the original data. The RRAM macro holds scrambled data, which differs from the plaintext.
- **SEC-5**: Address-XOR is applied to each bus word before storage (in `rram_phy_wr`) and inverted on every read.
  - Host reads are inverted in `u_tl_adapter_host`.
  - Controller reads are inverted in `u_rram_ctrl_rd`.
  - This is disabled for OTP partition accesses.
- **SEC-6**: ECC is computed by the macro. `ECC_EN` per region, page or subregion drives the `ecc_en` signal in `rram_macro_req_t` for each access.
- **SEC-7**: The emulation model protects each 128-bit word with two independent Hamming(72,64) SECDED codes, one for each 64-bit half.
- **SEC-8**: On a macro `ecc_err` response (`001`/`010`/`100`):
  - `001` (single-bit corrected) increments `CORR1_ERR_CNT`, updates `CORR1_ERR_LOC` and sets `INTR_STATE.corr1_err`.
  - `010` (double-bit corrected) increments `CORR2_ERR_CNT`, updates `CORR2_ERR_LOC` and sets `INTR_STATE.corr2_err`.
  - `100` (uncorrectable) sets `FAULT_STATUS.phy_relbl_err` and fires `fatal_err`.
  - `000` has no effect.
- **SEC-9**: `CORR1_ERR_CNT` and `CORR2_ERR_CNT` are 8 bits and saturate at 0xff without wrapping. They are writable (software can clear them).
- **SEC-10**: `CORR*_ERR_LOC` hold the address (`[20:0]`) and partition (bit 24) of the last corrected error. They are ro.
- **SEC-11**: Every RRAM read is issued twice (shadow read), and a mismatch between the two sets `FAULT_STATUS.phy_rd_intg_err`.
- **SEC-12**: The read buffer has 4 entries of 128 bits, and an entry is invalidated by any write to the same RRAM page.
  - Reads of the same RRAM word do not cause a second macro access while the entry is valid.
  - A read after a write to that page returns the new data, never a stale buffer entry.
- **SEC-13**: Up to 2 host reads can be outstanding in the read pipeline.
- **SEC-14**: The write path rejects writes when the analog "power stable" indication to the macro is low, and an error is returned.

## 9. Emulated OTP (`rram_ctrl_otp`)

- **OTP-1**: `otp_macro` is the rsp-side interface. It accepts `OtpRead`, `OtpWrite`, `OtpReadRaw`, `OtpWriteRaw`, `OtpInit` and `OtpZeroize`.
- **OTP-2**: OTP accesses reach only the reserved OTP pages (GEO-5). They never touch the regular data partition or the info partition.
- **OTP-3**: OTP write has OR semantics, so bits can only be set and never cleared. The implementation is a read-set-write: the old word is read, ORed with the new value and written back.
- **OTP-4**: Each 64 bits of OTP data have an 8-bit Hamming integrity value in the OTP integrity page.
  - `OtpWrite` updates the data word and its integrity word as one operation.
  - `OtpRead` recomputes and checks the integrity.
  - An integrity mismatch on read is reported as an error on the `otp_macro` response and sets the matching status bit (`STD_FAULT_STATUS.otp_intg_err`, or `FAULT_STATUS.otp_rd_err`).
  - `OtpReadRaw` and `OtpWriteRaw` bypass the integrity step.
- **OTP-5**: `OtpZeroize` overwrites the addressed OTP word, and the following read does not return the previous content.
- **OTP-6**: Address-XOR is disabled for OTP accesses. Scrambling and ECC for OTP accesses follow the hardwired hardware rules, subject to `HW_INFO_CFG_OVERRIDE`.
- **OTP-7**: Every command gets exactly one response on `otp_macro` (`ready`/`rvalid`/`err`).
- **OTP-8**: OTP-side faults are reported as:
  - `otp_op_err`
  - `otp_mp_err`
  - `otp_rd_err`
  - `otp_wr_err`
  - `otp_err` (FSM or counter fault)
  - `otp_intg_err`

## 10. Life cycle, RMA and key manager

- **LC-1**: `lc_*` signals are `lc_tx_t` MuBi4. Only the True encoding enables an action. Any value that is not True or False is treated as not enabled and should be flagged.
- **LC-2**: `lc_escalate_en` (any non-False value) makes the memory inaccessible, as for the local escalation in DIS-2.
- **RMA-1**: When `rma_req` is True, `rram_ctrl_lcmgr` runs the wipe sequence.
  - It overwrites the creator seed page, the owner seed page and the isolated info page.
  - It overwrites all the non-OTP data pages.
  - The data written is pseudo-random, from a 64-bit LFSR seeded with `rma_seed`.
  - Only after the wipe is finished does it assert `rma_ack`.
- **RMA-2**: `rma_ack` is never asserted before the wipe has covered every page in scope, and is never asserted without a prior `rma_req`.
- **RMA-3**: RRAM access is disabled from RMA entry until the next reset.
  - Software operations during that time give `op_err`.
  - The disable is permanent and not undone by `rma_req` going low.
- **RMA-4**: The wipe does not overwrite the OTP region pages (4090–4095).
- **RMA-5**: Faults in the lcmgr are reported through `lcmgr_op_err`, `lcmgr_mp_err`, `lcmgr_rd_err`, `lcmgr_wr_err` (FAULT_STATUS) and `lcmgr_err` or `lcmgr_intg_err` (STD_FAULT_STATUS).
- **KM-1**: The seeds sent to `keymgr_dpe` match the contents of the creator and owner info pages. They are valid only after init and when `lc_seed_hw_rd_en` is True.

## 11. Power manager

- **PWR-1**: `pwrmgr` idle is deasserted whenever a write, an OTP operation or a RMA wipe is in progress, and `PHY_STATUS.wr_busy` is 1 whenever the phy is writing.
- **PWR-2**: Idle is asserted when no write or OTP operation is in progress.

## 12. Interrupts

- **INT-1**: The block has 7 interrupts: `wr_empty`, `wr_lvl`, `rd_full`, `rd_lvl` (Status type) and `op_done`, `corr1_err`, `corr2_err` (Event type).
- **INT-2**: The `INTR_STATE` reset value is 0x3. This is `wr_empty` and `wr_lvl`, both set because the write FIFO is empty.
- **INT-3**: The event interrupts are rw1c. The status interrupts are ro and follow the underlying state.
- **INT-4**: `INTR_ENABLE` resets to 0, and each `intr_o` line equals `INTR_STATE & INTR_ENABLE`.
- **INT-5**: Writing 1 to a bit of `INTR_TEST` sets the matching `INTR_STATE` bit. `INTR_TEST` is wo and reads as 0.

## 13. Alerts

- **ALERT-1**: There are 5 alerts: `recov_err`, `fatal_std_err`, `fatal_err`, `fatal_macro_err` and `recov_macro_err`.
- **ALERT-2**: `recov_err` fires when a software-initiated operation completes with any `ERR_CODE` bit set.
- **ALERT-3**: `fatal_std_err` fires whenever any bit in `STD_FAULT_STATUS` is set. The register is ro and sticky until reset.
- **ALERT-4**: `fatal_err` fires whenever any bit in `FAULT_STATUS` is set. It keeps firing for as long as a bit stays set.
  - All bits except `phy_relbl_err` stay set until reset.
  - `phy_relbl_err` is rw0c and software can clear it. Once cleared it no longer causes the alert.
- **ALERT-5**: `fatal_macro_err` fires on macro-reported fatal errors (including TL-UL integrity faults on the test interface). `recov_macro_err` fires on macro-reported recoverable errors.
- **ALERT-6**: A write of 1 to `ALERT_TEST.<alert>` fires one alert event of that kind.
  - `ALERT_TEST.regwen` (bit 31) resets to 1 and is rw0c. Once written 0, alert testing is disabled until the next reset.
- **ALERT-7**: `STD_FAULT_STATUS` and `FAULT_STATUS` are ro (except `phy_relbl_err`). Software cannot clear or force them.
- **ALERT-8**: Any bit in `STD_FAULT_STATUS` and `FAULT_STATUS` causes the local escalation (DIS-2), with `phy_relbl_err` as the exception described in DIS-3.

## 14. Countermeasure properties

For the checks that are not covered above:

- **CM-1**: The controller FSMs (`rram_ctrl_lcmgr`, `rram_ctrl_otp`, `rram_ctrl_arb`, `rram_ctrl_rd`, `rram_ctrl_wr`), `rram_phy_wr` and the TL-UL gate FSMs (`host_tl` and `wr` gates) use sparse encoding.
  - A forced invalid state sets `ctrl_fsm_err`, `phy_fsm_err`, `lcmgr_err` or `otp_err` and fires `fatal_std_err`.
- **CM-2**: The counters in the `rram_ctrl_otp`, `rram_ctrl_rd`/`wr` and `rram_phy_wr` blocks are redundantly encoded. A forced mismatch sets `ctrl_cnt_err`, `phy_cnt_err`, `lcmgr_err` or `otp_err`.
- **CM-3**: Both phy arbiters (controller/host and scramble) run in duplicate. A mismatch sets `phy_arb_err`.
- **CM-4**: A host grant to an info partition access, or a host grant without a pending request, sets `FAULT_STATUS.host_gnt_err`.
- **CM-5**: A done indication from the macro that nobody asked for sets `FAULT_STATUS.spurious_done`.
- **CM-6**: Read-pipeline control errors set `FAULT_STATUS.phy_rd_ctrl_err`:
  - Valid data with no pending request (meta FIFO empty).
  - Valid data while a verify operation completes.
  - An RRAM request with no internal request generated.
  - Response integrity that does not match the request in the meta FIFO.
- **CM-7**: A verify (shadow) read that differs from the original read sets `phy_rd_intg_err`.

## 15. Register-level properties

- **REG-1**: The reset value and reset mask of every register match the register summary (for example `INTR_STATE` 0x3, `DIS` 0x99, `STATUS` 0xa, `FIFO_LVL` 0xf0f, `ALERT_TEST` 0x80000000).
- **REG-2**: Reserved bits read as 0 and writes to them have no effect.
- **REG-3**: `CONTROL` and `ADDR` are guarded by `CTRL_REGWEN`. `MP_REGION_CFG`/`MP_REGION` by `REGION_CFG_REGWEN`. `INFO_PAGE_CFG` by `INFO_REGWEN`. `EMUL_INFO_REGION` by `EMUL_INFO_REGWEN`. `EMUL_INFO_SUBREGION` by `EMUL_INFO_SUBREGION_REGWEN`. `EMUL_INFO_SUBREGION_CFG` by `EMUL_INFO_SUBREGION_CFG_REGWEN`.
- **REG-4**: `SCRATCH` is a plain 32-bit rw register with no side effects.
- **REG-5**: `CONTROL.START` is written together with, or after, the other `CONTROL` fields and `ADDR`.

## 16. Open questions (gaps or ambiguities in the docs)

- The docs do not say whether the MP region configuration for the data partition applies to the lcmgr and OTP hardware interfaces. They only say those use "fixed compile-time rules".
- It is not stated what happens when a Write has `NUM+1` not a multiple of 4. It may be `op_err` or it may be silently rounded.
- It is not stated which partition `CORR*_ERR_LOC.part` uses for encoding 0/1. The `CONTROL.PARTITION` encoding of 0 = data and 1 = info is the likely one.
- The README says the macro asserts `ecc_err` encoding `100` as uncorrectable (fatal), but also lists correctable-error interrupts only for the single and double-bit cases. The path from `100` to `phy_relbl_err` is inferred.
- The behaviour of regions that overlap each other in the data partition is not described. The priority rule, as in `flash_ctrl` (lowest index wins), is assumed but not stated.
- `OP_STATUS` bits are rw but only clear-by-software is described. The effect of writing 1 is not stated.
- The `wr_fifo` depth is 4 entries, but `FIFO_LVL.WR` has 5 bits.
- The `rd_fifo` depth is 16 entries, but `FIFO_LVL.RD` has 5 bits.
- The effects of programming values above those depths are not described.
