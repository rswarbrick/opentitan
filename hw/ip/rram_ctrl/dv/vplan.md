# Questions

- I don't think the ECC behaviour is properly defined in "RRAM
  controller features"
- What controls whether SW can issue a Rewrite operation?
- Feature desc for Rewrite doesn't specify behaviour.
- What is an "isolated info partition page" (for RMA wipe)?
- Is the XEX scrambling engine in RRAM phy features configurable?
- Are the fields of `rram_macro_req_t` and `rram_macro_rsp_t` defined
  anywhere?
- Description of `lc_ctrl` interface should probably be something like
  "restricts NVM backdoor access to certain lifecycle states", rather
  than talking about enables.
- Are the `lc_ctrl` restriction details written down anywhere?
- In the "System Interactions" section, the active party needs
  switching. At the moment, it looks like the interface (inside
  `rram_ctrl` is causing actions), rather than other IP blocks doing
  it.
- How should I interpret the picture under "RRAM Memory Overview"?
- OTP region is "transparent" to SW? What does that mean?
- Why is the OTP region given address locations at all?
- Rather strange description of `DIS.SW_DIS`
- The `EXEC` register should probably talk about fetches, rather than
  execution.
- Description of `INIT` needs tweaking: the register doesn't
  initialise the controller.
- Is the initialisation procedure defined anywhere other than the
  `INIT` register?
- The `CONTROL` register probably needs a link that points at the "do
  an operation" description.
- Similarly, the descriptions of that register's fields probably need
  to more explicitly explain *which* operation they are talking about.
- What happens if `CONTROL.NUM` is not 3 mod 4 for a write operation?
- The `CONTROL.START` description is a bit weird, given that atomic
  writes to a register are obviously possible...
- The `REGION_CFG_REGWEN` description needs something that explicitly
  links the multireg index to the region that is being configured.
- `MP_REGION_CFG` doesn't explicitly say MuBi4.
- `MP_REGION_CFG` could benefit from explicitly saying what `h9` means.
- In definition of `MP_REGION_CFG.SCRAMBLE_EN`, is "scramble enabled"
  defined anywhere?
- The configuration in `MP_REGION_CFG` doesn't explain what it applies
  to. (SW; "host"; ??)
- In definition of `MP_REGION_CFG.EN`, the order needs dropping from
  "following fields".
- The off-by-one behaviour in `MP_REGION.SIZE` isn't explicit.
- `DEFAULT_REGION` doesn't explicitly say MuBi4.
- `DEFAULT_REGION` could benefit from explicitly saying what `h9` means.
- Why is it `INFO_REGWEN` and `REGION_CFG_ERGWEN`?
- `INFO_PAGE_CFG` doesn't explicitly say MuBi4.
- `INFO_PAGE_CFG` could benefit from explicitly saying what `h9` means.

# Intro features:

- Manage access to RRAM
- Host-side read-only memory-mapped access
- SW read and write transactions via FIFOs
- Memory protection
- HW accelerated scrambling
- Secure HW interface to OTP controller
- Secure HW interface to keymgr
- Secure HW interface to lc_ctrl

# Named ports:

- otp-hwif
- lcmgr-hwif
- pwrmgr interface

# Features:

- Read commands to RRAM
- Write commands to RRAM
- core_tl interface for register bank and FIFOs, which can reach data
  and information partitions
- host_tl read-only interface that can only see data partition
- Interaction with lc_ctrl
- Interaction with otp_ctrl
- Interaction with keymgr

## RRAM controller features

- core_tl registers; FIFOs; SW initiated transactions
- host_tl RO memory access to data partition (for fetch and read)
- read, write, rewrite FIFOs
- FIFOs have configurable depth and interrupt watermarks
- FIFOs support burst writes for 4 word chunks, aligned to 16 bytes
- FIFOs support up to 1024 words per transaction
- Data partition has 10 configurable MP regions
- Default region configuration when no rule matches
- Per-page protection for the information partition
- Configurable XEX scrambling with PRINCE cipher
- Scrambling keys side-loaded through otp_ctrl.
- Address-XOR integrity (except for OTP partitions)
- UNDEFINED ECC BEHAVIOUR
- Correctable errors reported through corr_err interrupt
- Counter for the corr_err interrupt
- OTP semantics (no clear) for OTP partition
- Support for OtpRead, ..., OtpZeroize
- Separate integrity page with 8 bits of Hamming integrity per 64 bits of data
- OtpRead recomputes and checks integrity
- OtpWrite updates both data and integrity words
- RMA request from lc_ctrl causes seed pages, "isolated info partition
  pages", and non-OTP partition pages to be wiped, then asserts
  `rma_ack`.
- `wr_empty` interrupt
- `wr_lvl` interrupt
- `rd_full` interrupt
- `rd_lvl` interrupt
- `fatal_macro_err` interrupt
- `recov_macro_err` interrupt
- Fetches from RRAM controlled by an `EXEC` register with a magic value.
- Idle indication to `pwrmgr`.

## RRAM phy features

- 4-entry read buffer
- Buffer entries invalidated by write to same page
- Every RRAM read is duplicated (shadow reads)
- Fatal alert on shadow read mismatch
- XEX scrambling engine
- Address-XOR applied per bus word

## System interactions

### lc_ctrl

- The lc_ctrl interface can restrict NVM backdoor access to specific
  LC states.
- Access to specified pages (owner, creator, isolated info pages) are
  controlled by four dedicated enable bits.
- req/ack interface for RMA wipe requests

### otp_ctrl

- Handle OtpInit
- Handle OtpRead
- Handle OtpWrite
- Handle OtpZeroize
- Take scrambling keys

### pwrmgr

- Correctness of idle signal
- Power good input. When false, write operations are rejected with an
  error.

### keymgr_dpe

- During initialisation, read owner and creator seeds from specific
  info pages and forward them to keymgr.

### alerts / interrupts

- (Listed separately)

## RRAM memory

- The data partition has a 5-page region at the top that is only
  accessible through the OTP hardware interface.
- Info partition has the two secret seed pages and also the
  manufacturing authentication page.
- Each word has 16 bytes (128 bits)
- Access to INFO / DATA is muxed with `CONTROL.PARTITION`
- OTP pages are only accessible to otp_ctrl, which can't access the
  other pages.

# Registers

## INTR*

- Interrupt state register should match the current state of the
  relevant interrupts, masked by `inter_enable`.
- The `corr_err` and `op_done` bits in `intr_state` should be `rw1c`.
- The `intr_test` register should control `intr_state`.

## ALERT_TEST

- Writes to the bits trigger the associated alerts

## DIS
### `RELBL_ERR_FATAL`
- Controls reliability error feature.
- If set to `MuBi4True` any fault will immediately disable the RRAM.
- If this bit is not set then `FAULT_STATUS.PHY_RELBL_ERR` is excluded
  from local escalation.
- rw1s behaviour.
### `SW_DIS`
- Disable functionality completely if equal to `MuBi4True`
- rw1s behaviour.

## EXEC
- Magic value enable
- Controls code execution (fetches)

## INIT
- Set bottom bit to initialise RRAM controller.
- This requests address and data scramble keys and reads out the root
  seeds before anything else can get in.

## CTRL_REGWEN
- RO register
- Reflects the fact that an RRAM operation is in progress.

## CONTROL
### `NUM`
- One less than number of words that should be touched by an RRAM operation.
### `PARTITION`
- INFO / DATA
### `OP`
- Read / Write / Rewrite
### `START`
- "Do it."

## ADDR
- 21-bit `START` field gives byte address for operation

## `REGION_CFG_REGWEN`
- Multireg.
- One bit per region; rw0c.
- Acts as a write-enable for configuring the regions.

## `MP_REGION_CFG`
- Multireg
- `ECC_EN`: Enable ECC for the region
- `SCRAMBLE_EN`: ?? "scramble enabled"
- `WR_EN`: Write enable for the region
- `RD_EN`: Read enable for the region
- `EN`: Configuration register applies

## `MP_REGION`
-  Multireg
- Size and base defined in pages.

## `DEFAULT_REGION`
- `ECC_EN`: Enable ECC for the region
- `SCRAMBLE_EN`: ?? "scramble enabled"
- `WR_EN`: Write enable for the region
- `RD_EN`: Read enable for the region

## `INFO_REGWEN`
- Multireg
- One bit per page; rw0c.
- Write-enable for page configuration.

## `INFO_PAGE_CFG`
- `ECC_EN`: Enable ECC for the region
- `SCRAMBLE_EN`: ?? "scramble enabled"
- `WR_EN`: Write enable for the region
- `RD_EN`: Read enable for the region



# Interrupts

## Security countermeasures

# Alerts
