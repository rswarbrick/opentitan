// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
#ifndef OPENTITAN_HW_IP_OTBN_DV_MODEL_OTBN_TRACE_ENTRY_H_
#define OPENTITAN_HW_IP_OTBN_DV_MODEL_OTBN_TRACE_ENTRY_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

// This models a body line in an OTBN trace entry (type '<', '>', 'R' or 'W').
// Each of these lines is of the format
//
//   TYPE ' ' LOC ': ' VALUE
//
// and we parse them accordingly here. The point is that we want to merge
// successive writes to the same location and thus need to unpack things enough
// to see them.
class OtbnTraceBodyLine {
 public:
  // Parse a line into this object, based on the format above. On success,
  // return true. On failure, write an error message to stderr (using src to
  // say where the line came from) and return false.
  bool fill_from_string(const std::string &src, const std::string &line);

  bool operator==(const OtbnTraceBodyLine &other) const;

  // Return the location that is being read or written
  const std::string &get_loc() const { return loc_; }

  // Return the original string format for the entry
  const std::string &get_string() const { return raw_; }

 private:
  std::string raw_;
  char type_;
  std::string loc_;
  std::string value_;
};

class OtbnTraceEntry {
 public:
  enum trace_type_t {
    Invalid,
    Stall,
    Exec,
    WipeInProgress,
    WipeComplete,
  };

  virtual ~OtbnTraceEntry(){};

  void print(const std::string &indent, std::ostream &os) const;

  void take_writes(const OtbnTraceEntry &other, bool other_first);

  trace_type_t trace_type() const { return trace_type_; }

  // True if this is an acceptable line to follow other (assumed to
  // have been of type Stall or WipeInProgress)
  bool is_compatible(const OtbnTraceEntry &other) const;

  // True if this entry is "partial" (Stall or WipeInProgress)
  bool is_partial() const;

  // True if this entry is "final" (Exec or WipeComplete)
  bool is_final() const;

  const std::string &get_hdr() const;

  // Return a pointer to a vector of writes to the given location, or
  // null if there are none.
  const std::vector<OtbnTraceBodyLine> *get_writes(const std::string &location) const;

  // Return the number of locations that get written by one or more
  // trace lines in this entry
  unsigned num_locations() const;

 protected:
  // Return true if the writes in rtl_lines are compatible with those in
  // iss_lines.
  //
  // If they are not compatible, return false and write a description of
  // the mismatch to *err_desc.
  static bool check_writes_compatible(
      trace_type_t type, const std::string &key,
      const std::vector<OtbnTraceBodyLine> &rtl_lines,
      const std::vector<OtbnTraceBodyLine> &iss_lines,
      bool no_sec_wipe_data_chk, std::string *err_desc);

  static trace_type_t hdr_to_trace_type(const std::string &hdr);

  trace_type_t trace_type_;
  std::string hdr_;
  // The register writes for this trace entry, keyed by destination
  std::map<std::string, std::vector<OtbnTraceBodyLine>> writes_;
};

class OtbnIssTraceEntry : public OtbnTraceEntry {
 public:
  bool from_iss_trace(const std::vector<std::string> &lines);

  // Fields that are populated from the "special" line for ISS entries
  struct IssData {
    uint32_t insn_addr;
    std::string mnemonic;
  };

  IssData data_;
};

class OtbnRtlTraceEntry : public OtbnTraceEntry {
 public:
  // Parse a trace entry from the RTL into this object. On an error, print a
  // message to stderr and return false.
  bool from_rtl_trace(const std::string &trace);

  // Compare this trace entry with one from the ISS.
  //
  // Returns true if the two entries are compatible. If they are not,
  // it returns false and writes a textual description of what is
  // wrong to err_desc.
  bool compare_with_iss_entry(const OtbnIssTraceEntry &iss_entry,
                              bool no_sec_wipe_data_chk,
                              std::string *err_desc) const;
};

#endif  // OPENTITAN_HW_IP_OTBN_DV_MODEL_OTBN_TRACE_ENTRY_H_
