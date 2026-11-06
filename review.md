## Summary
Commit reviewed: `bd7d8ba804` "[rram_ctrl,dv] Track STATUS.init_done/seeds_valid in scoreboard".

The commit connects the core register predictor's `reg_ap` to a new scoreboard imp and counts the OTP key transactions. That gives four checks on the hardware-updated fields `STATUS.init_done` and `STATUS.keys_valid`, which `CsrExclAll` had left unchecked.

Scope: OpenTitan, `hw/ip/rram_ctrl`, block level. Only the scoreboard changes, so the blast radius is just this IP.

Verification risk: this strengthens checking. Before, these two fields had no check at all. The comparison is sound: `item.value[0]` is the read data the predictor actually observed, and the expectation comes independently from the OTP key monitor. Using `reg_ap` is also the right hook, because the filter has already dropped errored reads. One modelling issue in check 4 will cause false failures once disable tests land.

## Blockers
None.

## Major
1. `hw/ip/rram_ctrl/dv/uvm/env/rram_ctrl_scoreboard.sv:260-276`: check 4's prediction of `keys_valid` races `DIS.SW_DIS` and doesn't cover every disable source.

   **Failure scenario (race):** a test does `csr_wr(ral.dis, MuBi4True)` and then reads `STATUS` straight away.
   - The mirror changes when the write's D response is seen, one cycle after the write is accepted (cycle 1).
   - In the RTL, `reg2hw.dis.sw_dis` is visible in cycle 1. `u_disable_buf` (`AsyncOn(0)`) passes it through combinationally to lcmgr `disable_i`. `keys_valid_q` clears in cycle 2 (`rram_ctrl_lcmgr.sv:640-645`), and the `STATUS` flop updates through `hw2reg` in cycle 3.
   - A `STATUS` read accepted in cycle 1 or 2 returns `keys_valid=1` while the mirror already says disabled, so `keys_valid_wrong` fires on correct RTL. An outstanding read issued alongside the write hits the same window.

   **Failure scenario (incomplete model):** the comment says LC escalation and `SW_DIS` are the only reasons `keys_valid` can be 0 after `init_done`. Local escalation (any `fault_status`/`std_fault_status` fault feeds `local_esc_q`) and RMA (`rma_dis_access`) also drive `disable_i`. Any future fault-injection or sec_cm test that reads `STATUS` afterwards would therefore false-fail. In the other direction, the `!rma_done` term leaves `keys_valid` at 1 after a successful RMA even though access is disabled.

   **Spec gap:** `theory_of_operation.md` says disable swaps the scrambler to random keys. It does not say `STATUS.keys_valid` clears. The expectation here comes from the RTL. Please raise a doc issue so the spec states it, rather than letting the TB encode it silently.

   Nothing runs into this today: `DIS` is `CsrExclWrite`, no vseq writes it, and `tb.sv` ties `lc_escalate_en_i` to `Off`. It will bite as soon as the `rma_sw_dis` / SW-disable testpoints arrive.

   **Fix:**
   - Treat `keys_valid` as unconstrained from the moment any disable is requested until a few cycles later, and only demand 0 after that window.
   - Widen the TODO to cover local escalation and RMA, not just #32226.
   - Correct the comment.

## Minor
2. `rram_ctrl_scoreboard.sv:200-209, 242-252`: checks 1 and 2 are weaker than the spec and than the comment at line 230. ToO step 3 says `keys_valid` is set after *both* keys are acknowledged, but check 1 accepts it after one. The bare count also can't tell an addr key from a data key, so an FSM bug that requests the addr key twice passes checks 1 and 2. `item.m_req.m_is_data_req` already has the information. **Fix:** track addr and data keys separately, require both for `keys_valid` as well as for `init_done`, and flag a repeated key of either kind. There is no false-failure risk in doing this: the monitor sees the ack in the OTP domain before it crosses `prim_sync_reqack`, so the count always leads `keys_valid`.
3. Commit subject says `seeds_valid`, but the body and the code are about `keys_valid`.
4. Batched cleanup:
   - The report IDs are literal strings rather than `` `gfn `` (DVCodingStyle requires `gfn`/`gtn` as the first argument).
   - `endfunction` at lines 209 and 280 has no `: write_key_txn` / `: write_reg_item` label.
   - `case (item.element.get_name())` with the string `"status"` would be more robust as `if (item.element == ral.status)`: a rename then breaks at compile time instead of silently skipping the check.

## Questions
5. The predictor path isn't gated on `cfg.en_scb`, so these checks also run in the CSR tests, which pass `+en_scb=0`. That matches how the existing check-on-read already behaves, so it may well be intended. If not, add an early `if (!cfg.en_scb) return;` in `write_reg_item`.
6. What ran, and on how many seeds? Did anything show the checks actually fire, for example a local run forcing `lcmgr_init_done` high early? Checks 2 and 4 do run in every test through the `csr_spinwait` in `rram_ctrl_init()`. Check 3 only fires if something reads `STATUS` again after init.

## Artefacts not updated
- `hw/ip/rram_ctrl/dv/README.md` (Scoreboard section) still says the `CsrExclCheck` fields "get no check at all right now" and that `on_reg_access()` is where such checks would go. They now live in `write_reg_item()`, so mention the `reg_ap` path there.
- The comment and `TODO(#31290)` in `on_reg_access()` (`rram_ctrl_scoreboard.sv:171-176`) are stale for the same reason.

## Not verified
- I didn't run any simulation, and the commit message gives no test or seed evidence.
- The cycle-level race in item 1 comes from reading the RTL, not from a waveform. I assumed the usual one-cycle `tlul_adapter_reg` response latency.
- The spec doesn't say whether `keys_valid` clears on disable.
- I only skimmed the otp_key agent from the previous commits (monitor ordering and item fields), not reviewed it.
