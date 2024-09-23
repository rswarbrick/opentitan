// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
## PINMUX register template
##
## Parameter (given by Python tool)
##  - n_mio_periph_in:     Number of muxed peripheral inputs
##  - n_mio_periph_out:    Number of muxed peripheral outputs
##  - n_mio_pads:          Number of muxed IO pads
##  - n_dio_periph_in:     Number of dedicated peripheral inputs
##  - n_dio_periph_out:    Number of dedicated peripheral outputs
##  - n_dio_pads:          Number of dedicated IO pads
##  - n_wkup_detect:       Number of wakeup condition detectors
##  - wkup_cnt_width:      Width of wakeup counters
##  - attr_dw:             Width of wakeup counters
{
  name:               "pinmux",
  human_name:         "Pin Multiplexer",
  one_line_desc:      "Multiplexes between on-chip hardware blocks and pins, and can be configured at runtime",
  one_paragraph_desc: '''
  Pin Multiplexer connects on-chip hardware blocks to IC pins and controls the attributes of the pin drivers (such as pull-up/down, open-drain, and drive strength).
  Large parts of its functionality can be controlled by software through registers.
  Further features include per-pin programmable sleep behavior and wakeup pattern detectors as well as support for life-cycle-based JTAG (TAP) isolation and muxing.
  '''
  // Unique comportable IP identifier defined under KNOWN_CIP_IDS in the regtool.
  cip_id:             "18",
  design_spec:        "../doc",
  dv_doc:             "../doc/dv",
  hw_checklist:       "../doc/checklist",
  sw_checklist:       "/sw/device/lib/dif/dif_pinmux",
  version:            "1.1.0",
  life_stage:         "L1",
  design_stage:       "D3",
  verification_stage: "V2S",
  dif_stage:          "S2",
  notes:              "Use FPV to perform block level verification.",
  clocking: [
    {clock: "clk_i", reset: "rst_ni", primary: true},
    {clock: "clk_aon_i", reset: "rst_aon_ni"},
    {reset: "rst_sys_ni"}
  ]
  bus_interfaces: [
    { protocol: "tlul", direction: "device" }
  ],
  regwidth: "32",
  scan: "true",

  alert_list: [
    { name: "fatal_fault",
      desc: '''
      This fatal alert is triggered when a fatal TL-UL bus integrity fault is detected.
      '''
    }
  ],

  wakeup_list: [
    { name: "pin_wkup_req",
      desc: "pin wake request"
    },
    { name: "usb_wkup_req",
      desc: "usb wake request"
    },
  ],

  inter_signal_list: [
    // Life cycle inputs
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_hw_debug_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg",
      desc:    '''
               Debug enable qualifier coming from life cycle controller, used for HW strap qualification.
               '''
    }
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_dft_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg",
      desc:    '''
               Test enable qualifier coming from life cycle controller, used for HW strap qualification.
               '''
    }
    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_escalate_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg",
      desc:    '''
               Escalation enable signal coming from life cycle controller, used for invalidating
               the latched lc_hw_debug_en state inside the strap sampling logic.
               ''',}

    { struct:  "lc_tx"
      type:    "uni"
      name:    "lc_check_byp_en"
      act:     "rcv"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg",
      desc:    '''
               Check bypass enable signal coming from life cycle controller, used for invalidating
               the latched lc_hw_debug_en state inside the strap sampling logic. This signal is asserted
               whenever the life cycle controller performs a life cycle transition. Its main use is
               to skip any background checks inside the life cycle partition of the OTP controller while
               a life cycle transition is in progress.
               ''',}

    { struct:  "lc_tx"
      type:    "uni"
      name:    "pinmux_hw_debug_en"
      act:     "req"
      default: "lc_ctrl_pkg::Off"
      package: "lc_ctrl_pkg",
      desc:    '''
               This is the latched version of lc_hw_debug_en_i. We use it exclusively to gate the JTAG
               signals and TAP side of the RV_DM so that RV_DM can remain live during an NDM reset cycle.
               ''',}

    // JTAG TAPs
    { struct:  "jtag"
      type:    "req_rsp"
      name:    "lc_jtag"
      act:     "req"
      package: "jtag_pkg"
      desc:    '''
               Qualified JTAG signals for life cycle controller TAP.
               ''',}

    { struct:  "jtag"
      type:    "req_rsp"
      name:    "rv_jtag"
      act:     "req"
      package: "jtag_pkg"
      desc:    '''
               Qualified JTAG signals for RISC-V processor TAP.
               ''',}

    { struct:  "jtag"
      type:    "req_rsp"
      name:    "dft_jtag"
      act:     "req"
      package: "jtag_pkg"
      desc:    '''
               Qualified JTAG signals for DFT TAP.
               ''',}

    // Testmode signals to AST
    { struct:  "dft_strap_test_req",
      type:    "uni",
      name:    "dft_strap_test",
      act:     "req",
      package: "pinmux_pkg",
      desc:    '''
               Sampled DFT strap values, going to the DFT TAP.
               ''',
      default: "'0"
    }
    // DFT indication to stop tap strap sampling
    { struct:  "logic",
      type:    "uni",
      name:    "dft_hold_tap_sel",
      act:     "rcv",
      package: "",
      desc:    '''
               TAP selection hold indication, asserted by the DFT TAP during boundary scan.
               ''',
      default: "'0"
    }
    // Define pwr mgr <-> pinmux signals
    { struct:  "logic",
      type:    "uni",
      name:    "sleep_en",
      act:     "rcv",
      package: "",
      desc:    '''
               Level signal that is asserted when the power manager enters sleep.
               ''',
      default: "1'b0"
    },
    { struct:  "logic",
      type:    "uni",
      name:    "strap_en",
      act:     "rcv",
      package: "",
      desc:    '''
               This signal is pulsed high by the power manager after reset in order to sample the HW straps.
               ''',
      default: "1'b0"
    },
    { struct:  "logic",
      type:    "uni",
      name:    "strap_en_override",
      act:     "rcv",
      desc:    '''
               This signal transitions from 0 -> 1 by the lc_ctrl manager after volatile RAW_UNLOCK in order to re-sample the HW straps.
               The signal must stay at 1 until reset.
               Note that this is only used in test chips when SecVolatileRawUnlockEn = 1.
               Otherwise this signal is unused.
               ''',
      default: "1'b0"
    },
    { struct:  "logic",
      type:    "uni",
      name:    "pin_wkup_req",
      act:     "req",
      package: "",
      desc:    '''
               Wakeup request from wakeup detectors, to the power manager, running on the AON clock.
               ''',
      default: "1'b0"
    },
    { name:    "usbdev_dppullup_en",
      type:    "uni",
      act:     "rcv",
      package: "",
      desc:    '''
               Pullup enable signal coming from the USB IP.
               ''',
      struct:  "logic",
      width:   "1"
    },
    { name:    "usbdev_dnpullup_en",
      type:    "uni",
      act:     "rcv",
      package: "",
      desc:    '''
               Pullup enable signal coming from the USB IP.
               ''',
      struct:  "logic",
      width:   "1"
    },
    { name:    "usb_dppullup_en",
      type:    "uni",
      act:     "req",
      package: "",
      desc:    '''
                Pullup enable signal going to USB PHY, needs to be maintained in low-power mode.
               ''',
      struct:  "logic",
      width:   "1"
      default: "1'b0"
    },
    { name:    "usb_dnpullup_en",
      type:    "uni",
      act:     "req",
      package: "",
      desc:    '''
               Pullup enable signal going to USB PHY, needs to be maintained in low-power mode.
               ''',
      struct:  "logic",
      width:   "1"
      default: "1'b0"
    },
    { struct:  "logic",
      type:    "uni",
      name:    "usb_wkup_req",
      act:     "req",
      package: "",
      desc:    '''
               Wakeup request from USB wakeup detector, going to the power manager, running on the AON clock.
               ''',
      default: "1'b0"
    },
    { name:    "usbdev_suspend_req",
      type:    "uni",
      act:     "rcv",
      package: "",
      desc:    '''
               Indicates whether USB is in suspended state, coming from the USB device.
               ''',
      struct:  "logic",
      width:   "1"
    },
    { name:    "usbdev_wake_ack",
      type:    "uni",
      act:     "rcv",
      package: "",
      desc:    '''
               Acknowledges the USB wakeup request, coming from the USB device.
               ''',
      struct:  "logic",
      width:   "1"
    },
    { name:    "usbdev_bus_not_idle",
      type:    "uni",
      act:     "req",
      package: "",
      desc:    '''
               Event signal that indicates that the USB was not idle while monitoring.
               ''',
      struct:  "logic",
      width:   "1",
      default: "1'b0"
    },
    { name:    "usbdev_bus_reset",
      type:    "uni",
      act:     "req",
      package: "",
      desc:    '''
               Event signal that indicates that the USB issued a Bus Reset while monitoring.
               ''',
      struct:  "logic",
      width:   "1",
      default: "1'b0"
    },
    { name:    "usbdev_sense_lost",
      type:    "uni",
      act:     "req",
      package: "",
      desc:    '''
               Event signal that indicates that USB SENSE signal was lost while monitoring.
               ''',
      struct:  "logic",
      width:   "1",
      default: "1'b0"
    },
    { name:    "usbdev_wake_detect_active",
      type:    "uni",
      act:     "req",
      package: "",
      desc:    '''
               State debug information.
               ''',
      struct:  "logic",
      width:   1,
      default: "1'b0"
    },
  ]

  param_list: [
    // Secure parameters
    { name:    "SecVolatileRawUnlockEn",
      type:    "bit",
      default: "1'b0",
      desc:    '''
        Disable (0) or enable (1) volatile RAW UNLOCK capability.
        If enabled, the strap_en_override_i input can be used to re-sample the straps at runtime.

        IMPORTANT NOTE: This should only be used in test chips. The parameter must be set
        to 0 in production tapeouts since this weakens the security posture of the RAW
        UNLOCK mechanism.
      '''
      local:   "false",
      expose:  "true"
    },
    { name: "AttrDw",
      desc: "Pad attribute data width",
      type: "int",
      default: "${attr_dw}",
      local: "true"
    },
    { name: "NMioPeriphIn",
      desc: "Number of muxed peripheral inputs",
      type: "int",
      default: "${n_mio_periph_in}",
      local: "true"
    },
    { name: "NMioPeriphOut",
      desc: "Number of muxed peripheral outputs",
      type: "int",
      default: "${n_mio_periph_out}",
      local: "true"
    },
    { name: "NMioPads",
      desc: "Number of muxed IO pads",
      type: "int",
      default: "${n_mio_pads}",
      local: "true"
    },
    { name: "NDioPads",
      desc: "Number of dedicated IO pads",
      type: "int",
      default: "${n_dio_pads}",
      local: "true"
    },
    { name: "NWkupDetect",
      desc: "Number of wakeup detectors",
      type: "int",
      default: "${n_wkup_detect}",
      local: "true"
    },
    { name: "WkupCntWidth",
      desc: "Number of wakeup counter bits",
      type: "int",
      default: "${wkup_cnt_width}",
      local: "true"
    },
    // Since the target-specific top-levels often have slightly
    // different debug signal positions, we need a way to pass
    // this info from the target specific top-level into the pinmux
    // logic. The parameter struct below serves this purpose.
   { name: "TargetCfg",
      desc:    "Target specific pinmux configuration.",
      type:    "pinmux_pkg::target_cfg_t",
      default: "pinmux_pkg::DefaultTargetCfg",
      local:   "false",
      expose:  "true"
    },
  ],
  countermeasures: [
    { name: "BUS.INTEGRITY",
      desc: "End-to-end bus integrity scheme."
    }
    { name: "LC_DFT_EN.INTERSIG.MUBI",
      desc: "The life cycle DFT enable signal is multibit encoded."
    }
    { name: "LC_HW_DEBUG_EN.INTERSIG.MUBI",
      desc: "The life cycle hardware debug enable signal is multibit encoded."
    }
    { name: "LC_CHECK_BYP_EN.INTERSIG.MUBI",
      desc: "The life cycle check bypass signal is multibit encoded."
    }
    { name: "LC_ESCALATE_EN.INTERSIG.MUBI",
      desc: "The life cycle check bypass signal is multibit encoded."
    }
    { name: "PINMUX_HW_DEBUG_EN.INTERSIG.MUBI",
      desc: '''In order to support the NDM reset feature in RV_DM,
               the pinmux latches the LC_HW_DEBUG_EN signal so that it can survive
               the NDM reset, and sends that signal on to the RV_DM for use in
               gating circuitry. This signal is also multibit encoded
            '''
    }
    { name: "TAP.MUX.LC_GATED",
      desc: '''The TAP selection mux/demux in the strap sampling module
               is gated by life cycle signals so that the RV_DM can only
               be selected during when LC_HW_DEBUG_EN is asserted, and
               the DFT TAP can only be selected when LC_DFT_EN is asserted.
            '''
    }
  ]

  registers: [
//////////////////////////
// MIO Inputs           //
//////////////////////////
    { multireg: { name:     "MIO_PERIPH_INSEL_REGWEN",
                  desc:     "Register write enable for MIO peripheral input selects.",
                  count:    "NMioPeriphIn",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "MIO_PERIPH_INSEL",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding MIO_PERIPH_INSEL
                              is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:         "MIO_PERIPH_INSEL",
                  desc:         "For each peripheral input, this selects the muxable pad input.",
                  count:        "NMioPeriphIn",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "MIO_PERIPH_INSEL_REGWEN",
                  regwen_multi: "true",
                  cname:        "IN",
                  fields: [
                    { bits: "${(n_mio_pads+1).bit_length()-1}:0",
                      name: "IN",
                      desc: '''
                      0: tie constantly to zero, 1: tie constantly to 1,
                      >=2: MIO pads (i.e., add 2 to the native MIO pad index).
                      '''
                      resval: 0,
                    }
                  ]
                }
    },

//////////////////////////
// MIO Outputs          //
//////////////////////////
    { multireg: { name:     "MIO_OUTSEL_REGWEN",
                  desc:     "Register write enable for MIO output selects.",
                  count:    "NMioPads",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "MIO_OUTSEL",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding MIO_OUTSEL
                              is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:         "MIO_OUTSEL",
                  desc:         "For each muxable pad, this selects the peripheral output.",
                  count:        "NMioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "MIO_OUTSEL_REGWEN",
                  regwen_multi: "true",
                  cname:        "OUT",
                  fields: [
                    { bits: "${(n_mio_periph_out+2).bit_length()-1}:0",
                      name: "OUT",
                      desc: '''
                      0: tie constantly to zero, 1: tie constantly to 1, 2: high-Z,
                      >=3: peripheral outputs (i.e., add 3 to the native peripheral pad index).
                      '''
                      resval: 2,
                    }
                  ]
                  // Random writes to this field may result in pad drive conflicts,
                  // which in turn leads to propagating Xes and assertion failures.
                  tags: ["excl:CsrAllTests:CsrExclWrite"]
                }
    },

//////////////////////////
// MIO PAD attributes   //
//////////////////////////
    { multireg: { name:     "MIO_PAD_ATTR_REGWEN",
                  desc:     "Register write enable for MIO PAD attributes.",
                  count:    "NMioPads",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "MIO_PAD",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding !!MIO_PAD_ATTR
                              is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:     "MIO_PAD_ATTR",
                  desc:     '''
                            Muxed pad attributes.
                            This register has WARL behavior since not each pad type may support
                            all attributes.
                            The muxed pad that is used for TAP strap 0 has a different reset value, with `pull_en` set to 1.
                            ''',
                  count:        "NMioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hrw",
                  hwext:        "true",
                  hwqe:         "true",
                  regwen:       "MIO_PAD_ATTR_REGWEN",
                  regwen_multi: "true",
                  cname:        "MIO_PAD",
                  fields: [
                    { bits: "0",
                      name: "invert",
                      desc: "Invert input and output levels."
                      resval: 0
                    },
                    { bits: "1",
                      name: "virtual_od_en",
                      desc: "Enable virtual open drain."
                      resval: 0
                    },
                    { bits: "2",
                      name: "pull_en",
                      desc: "Enable pull-up or pull-down resistor."
                      resval: 0
                    },
                    { bits: "3",
                      name: "pull_select",
                      desc: "Pull select (0: pull-down, 1: pull-up)."
                      enum: [
                        { value: "0",
                          name:  "pull_down",
                          desc:  "Select the pull-down resistor."
                        },
                        { value: "1",
                          name:  "pull_up",
                          desc:  "Select the pull-up resistor."
                        }
                      ]
                      resval: 0
                    },
                    { bits: "4",
                      name: "keeper_en",
                      desc: "Enable keeper termination. This weakly drives the previous pad output value when output is disabled, similar to a verilog `trireg`."
                      resval: 0
                    },
                    { bits: "5",
                      name: "schmitt_en",
                      desc: "Enable the schmitt trigger."
                      resval: 0
                    },
                    { bits: "6",
                      name: "od_en",
                      desc: "Enable open drain."
                      resval: 0
                    },
                    { bits: "7",
                      name: "input_disable",
                      desc: '''
                            Disable input drivers.
                            Setting this to 1 for pads that are not used as input can reduce their leakage current.
                            '''
                      resval: 0
                    },
                    { bits: "17:16",
                      name: "slew_rate",
                      desc: "Slew rate (0x0: slowest, 0x3: fastest)."
                      resval: 0
                    },
                    { bits: "23:20",
                      name: "drive_strength",
                      desc: "Drive strength (0x0: weakest, 0xf: strongest)"
                      resval: 0
                    }
                  ],
                  // these CSRs have WARL behavior and may not
                  // read back the same value that was written to them.
                  // further, they have hardware side effects since they drive the
                  // pad attributes, and hence no random data should be written to them.
                  // Additionally, their reset value is defined by the RTL implementation and may not equal `resval` for all instances (#24621).
                  tags: ["excl:CsrAllTests:CsrExclAll"]
                }
    },

//////////////////////////
// DIO PAD attributes   //
//////////////////////////
    { multireg: { name:     "DIO_PAD_ATTR_REGWEN",
                  desc:     "Register write enable for DIO PAD attributes.",
                  count:    "NDioPads",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "DIO_PAD",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding !!DIO_PAD_ATTR
                              is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:     "DIO_PAD_ATTR",
                  desc:     '''
                            Dedicated pad attributes.
                            This register has WARL behavior since not each pad type may support
                            all attributes.
                            ''',
                  count:        "NDioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hrw",
                  hwext:        "true",
                  hwqe:         "true",
                  regwen:       "DIO_PAD_ATTR_REGWEN",
                  regwen_multi: "true",
                  cname:        "DIO_PAD",
                  resval:       0,
                  fields: [
                    { bits: "0",
                      name: "invert",
                      desc: "Invert input and output levels."
                    },
                    { bits: "1",
                      name: "virtual_od_en",
                      desc: "Enable virtual open drain."
                    },
                    { bits: "2",
                      name: "pull_en",
                      desc: "Enable pull-up or pull-down resistor."
                    },
                    { bits: "3",
                      name: "pull_select",
                      desc: "Pull select (0: pull-down, 1: pull-up)."
                      enum: [
                        { value: "0",
                          name:  "pull_down",
                          desc:  "Select the pull-down resistor."
                        },
                        { value: "1",
                          name:  "pull_up",
                          desc:  "Select the pull-up resistor."
                        }
                      ]
                    },
                    { bits: "4",
                      name: "keeper_en",
                      desc: "Enable keeper termination. This weakly drives the previous pad output value when output is disabled, similar to a verilog `trireg`."
                    },
                    { bits: "5",
                      name: "schmitt_en",
                      desc: "Enable the schmitt trigger."
                    },
                    { bits: "6",
                      name: "od_en",
                      desc: "Enable open drain."
                    },
                    { bits: "7",
                      name: "input_disable",
                      desc: '''
                            Disable input drivers.
                            Setting this to 1 for pads that are not used as input can reduce their leakage current.
                            '''
                    },
                    { bits: "17:16",
                      name: "slew_rate",
                      desc: "Slew rate (0x0: slowest, 0x3: fastest)."
                    },
                    { bits: "23:20",
                      name: "drive_strength",
                      desc: "Drive strength (0x0: weakest, 0xf: strongest)"
                    }
                  ],
                  // these CSRs have WARL behavior and may not
                  // read back the same value that was written to them.
                  // further, they have hardware side effects since they drive the
                  // pad attributes, and hence no random data should be written to them.
                  tags: ["excl:CsrAllTests:CsrExclWrite"]
                }
    },

//////////////////////////
// MIO PAD sleep mode   //
//////////////////////////
    { multireg: { name:     "MIO_PAD_SLEEP_STATUS",
                  desc:     "Register indicating whether the corresponding pad is in sleep mode.",
                  count:    "NMioPads",
                  swaccess: "rw0c",
                  hwaccess: "hrw",
                  cname:    "MIO_PAD",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              This register is set to 1 if the deep sleep mode of the corresponding
                              pad has been enabled (!!MIO_PAD_SLEEP_EN) upon deep sleep entry.
                              The sleep mode of the corresponding pad will remain active until SW
                              clears this bit.
                              ''',
                      resval: "0",
                    }
                  ]
                }
    },
    { multireg: { name:     "MIO_PAD_SLEEP_REGWEN",
                  desc:     "Register write enable for MIO sleep value configuration.",
                  count:    "NMioPads",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "MIO_PAD",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding !!MIO_PAD_SLEEP_MODE
                              is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:         "MIO_PAD_SLEEP_EN",
                  desc:         '''Enables the sleep mode of the corresponding muxed pad.
                                '''
                  count:        "NMioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "MIO_PAD_SLEEP_REGWEN",
                  regwen_multi: "true",
                  cname:        "OUT",
                  fields: [
                    { bits: "0",
                      name: "EN",
                      resval: 0,
                      desc: '''
                            Deep sleep mode enable.
                            If this bit is set to 1 the corresponding pad will enable the sleep behavior
                            specified in !!MIO_PAD_SLEEP_MODE upon deep sleep entry, and the corresponding bit
                            in !!MIO_PAD_SLEEP_STATUS will be set to 1.
                            The pad remains in deep sleep mode until the corresponding bit in
                            !!MIO_PAD_SLEEP_STATUS is cleared by SW.
                            Note that if an always on peripheral is connected to a specific MIO pad,
                            the corresponding !!MIO_PAD_SLEEP_EN bit should be set to 0.
                            '''
                    }
                  ]
                }
    },
    { multireg: { name:         "MIO_PAD_SLEEP_MODE",
                  desc:         '''Defines sleep behavior of the corresponding muxed pad.
                                '''
                  count:        "NMioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "MIO_PAD_SLEEP_REGWEN",
                  regwen_multi: "true",
                  cname:        "OUT",
                  fields: [
                    { bits:  "1:0",
                      name:  "OUT",
                      resval: 2,
                      desc:  "Value to drive in deep sleep."
                      enum: [
                        { value: "0",
                          name: "Tie-Low",
                          desc: "The pad is driven actively to zero in deep sleep mode."
                        },
                        { value: "1",
                          name: "Tie-High",
                          desc: "The pad is driven actively to one in deep sleep mode."
                        },
                        { value: "2",
                          name: "High-Z",
                          desc: '''
                                The pad is left undriven in deep sleep mode. Note that the actual
                                driving behavior during deep sleep will then depend on the pull-up/-down
                                configuration of in !!MIO_PAD_ATTR.
                                '''
                        },
                        { value: "3",
                          name: "Keep",
                          desc: "Keep last driven value (including high-Z)."
                        },
                      ]
                    }
                  ]
                }
    },
//////////////////////////
// DIO PAD sleep mode   //
//////////////////////////
    { multireg: { name:     "DIO_PAD_SLEEP_STATUS",
                  desc:     "Register indicating whether the corresponding pad is in sleep mode.",
                  count:    "NDioPads",
                  swaccess: "rw0c",
                  hwaccess: "hrw",
                  cname:    "DIO_PAD",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              This register is set to 1 if the deep sleep mode of the corresponding
                              pad has been enabled (!!DIO_PAD_SLEEP_MODE) upon deep sleep entry.
                              The sleep mode of the corresponding pad will remain active until SW
                              clears this bit.
                              ''',
                      resval: "0",
                    }
                  ]
                }
    },
    { multireg: { name:     "DIO_PAD_SLEEP_REGWEN",
                  desc:     "Register write enable for DIO sleep value configuration.",
                  count:    "NDioPads",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "DIO_PAD",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding !!DIO_PAD_SLEEP_MODE
                              is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:         "DIO_PAD_SLEEP_EN",
                  desc:         '''Enables the sleep mode of the corresponding dedicated pad.
                                '''
                  count:        "NDioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "DIO_PAD_SLEEP_REGWEN",
                  regwen_multi: "true",
                  cname:        "OUT",
                  fields: [
                    { bits: "0",
                      name: "EN",
                      resval: 0,
                      desc: '''
                            Deep sleep mode enable.
                            If this bit is set to 1 the corresponding pad will enable the sleep behavior
                            specified in !!DIO_PAD_SLEEP_MODE upon deep sleep entry, and the corresponding bit
                            in !!DIO_PAD_SLEEP_STATUS will be set to 1.
                            The pad remains in deep sleep mode until the corresponding bit in
                            !!DIO_PAD_SLEEP_STATUS is cleared by SW.
                            Note that if an always on peripheral is connected to a specific DIO pad,
                            the corresponding !!DIO_PAD_SLEEP_EN bit should be set to 0.
                            '''
                    }
                  ]
                }
    },
    { multireg: { name:         "DIO_PAD_SLEEP_MODE",
                  desc:         '''Defines sleep behavior of the corresponding dedicated pad.
                                '''
                  count:        "NDioPads",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "DIO_PAD_SLEEP_REGWEN",
                  regwen_multi: "true",
                  cname:        "OUT",
                  fields: [
                    { bits:  "1:0",
                      name:  "OUT",
                      resval: 2,
                      desc:  "Value to drive in deep sleep."
                      enum: [
                        { value: "0",
                          name: "Tie-Low",
                          desc: "The pad is driven actively to zero in deep sleep mode."
                        },
                        { value: "1",
                          name: "Tie-High",
                          desc: "The pad is driven actively to one in deep sleep mode."
                        },
                        { value: "2",
                          name: "High-Z",
                          desc: '''
                                The pad is left undriven in deep sleep mode. Note that the actual
                                driving behavior during deep sleep will then depend on the pull-up/-down
                                configuration of in !!DIO_PAD_ATTR.
                                '''
                        },
                        { value: "3",
                          name: "Keep",
                          desc: "Keep last driven value (including high-Z)."
                        },
                      ]
                    }
                  ]
                }
    },
////////////////////////
// Wakeup detectors   //
////////////////////////
    { multireg: { name:     "WKUP_DETECTOR_REGWEN",
                  desc:     "Register write enable for wakeup detectors.",
                  count:    "NWkupDetect",
                  compact:  "false",
                  swaccess: "rw0c",
                  hwaccess: "none",
                  cname:    "WKUP_DETECTOR",
                  fields: [
                    { bits:   "0",
                      name:   "EN",
                      desc:   '''
                              Register write enable bit.
                              If this is cleared to 0, the corresponding WKUP_DETECTOR
                              configuration is not writable anymore.
                              ''',
                      resval: "1",
                    }
                  ]
                }
    },
    { multireg: { name:         "WKUP_DETECTOR_EN",
                  desc:         '''
                                Enables for the wakeup detectors.
                                Note that these registers are synced to the always-on clock.
                                The first write access always completes immediately.
                                However, read/write accesses following a write will block until that write has completed.
                                '''
                  count:        "NWkupDetect",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "WKUP_DETECTOR_REGWEN",
                  regwen_multi: "true",
                  cname:        "DETECTOR",
                  async:        "clk_aon_i",
                  fields: [
                    { bits: "0:0",
                      name: "EN",
                      resval: 0,
                      desc: '''
                      Setting this bit activates the corresponding wakeup detector.
                      The behavior is as specified in !!WKUP_DETECTOR,
                      !!WKUP_DETECTOR_CNT_TH and !!WKUP_DETECTOR_PADSEL.
                      '''
                      // In CSR tests, we do not touch the chip IOs. Thet are either pulled low or
                      // or undriven.
                      //
                      // Random writes to the wkup detect CSRs may result in the case where the
                      // wakeup gets enabled and signaled due to a pin being low for a programmed
                      // time, which results in wkup_cause register to mismatch, OR, result in
                      // assertion error due to a pin programmed for wakeup detection is undriven
                      // Also exclude write for csr_hw_reset, otherwise, X may be detected and propagating.
                      tags: ["excl:CsrAllTests:CsrExclWrite"]
                    }
                  ]
                }

    },
    { multireg: { name:         "WKUP_DETECTOR",
                  desc:         '''
                                Configuration of wakeup condition detectors.
                                Note that these registers are synced to the always-on clock.
                                The first write access always completes immediately.
                                However, read/write accesses following a write will block until that write has completed.

                                Note that the wkup detector should be disabled by setting !!WKUP_DETECTOR_EN_0 before changing the detection mode.
                                The reason for that is that the pulse width counter is NOT cleared upon a mode change while the detector is enabled.
                                '''
                  count:        "NWkupDetect",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "WKUP_DETECTOR_REGWEN",
                  regwen_multi: "true",
                  cname:        "DETECTOR",
                  async:        "clk_aon_i",
                  fields: [
                    { bits: "2:0",
                      name: "MODE",
                      resval: 0,
                      desc: "Wakeup detection mode. Out of range values default to Posedge."
                      enum: [
                        { value: "0",
                          name: "Posedge",
                          desc: "Trigger a wakeup request when observing a positive edge."
                        },
                        { value: "1",
                          name: "Negedge",
                          desc: "Trigger a wakeup request when observing a negative edge."
                        },
                        { value: "2",
                          name: "Edge",
                          desc: "Trigger a wakeup request when observing an edge in any direction."
                        },
                        { value: "3",
                          name: "TimedHigh",
                          desc: '''
                            Trigger a wakeup request when pin is driven HIGH for a certain amount
                            of always-on clock cycles as configured in !!WKUP_DETECTOR_CNT_TH.
                            '''
                        },
                        { value: "4",
                          name: "TimedLow",
                          desc: '''
                            Trigger a wakeup request when pin is driven LOW for a certain amount
                            of always-on clock cycles as configured in !!WKUP_DETECTOR_CNT_TH.
                            '''
                        },

                      ]
                    }
                    { bits: "3",
                      name: "FILTER",
                      resval: 0,
                      desc: '''0: signal filter disabled, 1: signal filter enabled. the signal must
                        be stable for 4 always-on clock cycles before the value is being forwarded.
                        can be used for debouncing.
                        '''
                    }
                    { bits: "4",
                      name: "MIODIO",
                      resval: 0,
                      desc: '''0: select index !!WKUP_DETECTOR_PADSEL from MIO pads,
                        1: select index !!WKUP_DETECTOR_PADSEL from DIO pads.
                        '''
                    }
                  ]
                }

    },
    { multireg: { name:         "WKUP_DETECTOR_CNT_TH",
                  desc:         '''
                                Counter thresholds for wakeup condition detectors.
                                Note that these registers are synced to the always-on clock.
                                The first write access always completes immediately.
                                However, read/write accesses following a write will block until that write has completed.
                                '''
                  count:        "NWkupDetect",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "WKUP_DETECTOR_REGWEN",
                  regwen_multi: "true",
                  cname:        "DETECTOR",
                  async:        "clk_aon_i",
                  fields: [
                    { bits: "WkupCntWidth-1:0",
                      name: "TH",
                      resval: 0,
                      desc: '''Counter threshold for TimedLow and TimedHigh wakeup detector modes (see !!WKUP_DETECTOR).
                      The threshold is in terms of always-on clock cycles.
                      '''
                    }
                  ]
                }

    },
    { multireg: { name:         "WKUP_DETECTOR_PADSEL",
                  desc:         '''
                                Pad selects for pad wakeup condition detectors.
                                This register is NOT synced to the AON domain since the muxing mechanism is implemented in the same way as the pinmux muxing matrix.
                                '''
                  count:        "NWkupDetect",
                  compact:      "false",
                  swaccess:     "rw",
                  hwaccess:     "hro",
                  regwen:       "WKUP_DETECTOR_REGWEN",
                  regwen_multi: "true",
                  cname:        "DETECTOR",
                  fields: [
                    { bits: "${max(2 + n_mio_pads-1, n_dio_periph_in-1).bit_length()-1}:0",
                      name: "SEL",
                      resval: 0,
                      desc: '''Selects a specific MIO or DIO pad (depending on !!WKUP_DETECTOR configuration).
                      In case of MIO, the pad select index is the same as used for !!MIO_PERIPH_INSEL, meaning that index
                      0 and 1 just select constants 0 and 1, and the MIO pads live at indices >= 2. In case of DIO pads,
                      the pad select index corresponds 1:1 to the DIO pad to be selected.
                      '''
                    }
                  ]
                }

    },
    { multireg: { name:     "WKUP_CAUSE",
                  desc:     '''
                            Cause registers for wakeup detectors.
                            Note that these registers are synced to the always-on clock.
                            The first write access always completes immediately.
                            However, read/write accesses following a write will block until that write has completed.
                            '''
                  count:    "NWkupDetect",
                  swaccess: "rw0c",
                  hwaccess: "hrw",
                  cname:    "DETECTOR",
                  async:    "clk_aon_i",
                  fields: [
                    { bits: "0",
                      name: "CAUSE",
                      resval: 0,
                      desc: '''Set to 1 if the corresponding detector has detected a wakeup pattern. Write 0 to clear.
                      '''
                    }
                  ]
                }

    },
  ],
}
