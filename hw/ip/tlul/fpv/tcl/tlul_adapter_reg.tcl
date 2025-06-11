# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# TCL script used as after_load for verification of tlul_adapter_reg.tcl

# Waive coverage for the contents of prim_secded_inv_64_57_dec and prem_secded_inv_39. We don't
# connect some of the output ports (data_o, syndrome_o) in the design so the combinatorial logic
# that callculates their value isn't checked.
#
# We *do* check their err_o signals, which are modelled as decoded_cmd.err and decoded_data.err in
# the FPV code.
foreach dec_path [list \
                      [get_filename -module prim_secded_inv_64_57_dec] \
                      [get_filename -module prim_secded_inv_39_32_dec]] {
    check_cov \
        -waiver -add \
        -source_file ${dec_path} \
        -comment {
            Waive coverage for the guts of the decoder because some of the logic isn't
            actually connected and the other bits *are* checked elsewhere.
        }
}
