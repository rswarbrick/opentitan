// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "verilator_memutil.h"

#include <cassert>
#include <cstring>
#include <fcntl.h>
#include <gelf.h>
#include <getopt.h>
#include <iostream>
#include <libelf.h>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include "sv_scoped.h"

// DPI Exports
extern "C" {

/**
 * Write |file| to a memory
 *
 * @param file path to a SystemVerilog $readmemh()-compatible file (VMEM file)
 */
extern void simutil_verilator_memload(const char *file);

/**
 * Write a 32 bit word |val| to memory at index |index|
 *
 * @return 1 if successful, 0 otherwise
 */
extern int simutil_verilator_set_mem(int index, const svBitVecVal *val);
}

namespace {
// Convenience class for runtime errors when loading an ELF file
class ElfError : public std::exception {
 public:
  ElfError(const std::string &path, const std::string &msg) {
    std::ostringstream oss;
    oss << "Failed to load ELF file at `" << path << "': " << msg;
    msg_ = oss.str();
  }

  const char *what() const noexcept override { return msg_.c_str(); }

 private:
  std::string msg_;
};

// Class wrapping an open ELF file
class ElfFile {
 public:
  ElfFile(const std::string &path) {
    fd_ = open(path.c_str(), O_RDONLY, 0);
    if (fd_ < 0) {
      throw ElfError(path, "could not open file.");
    }

    ptr_ = elf_begin(fd_, ELF_C_READ, NULL);
    if (!ptr_) {
      close(fd_);
      throw ElfError(path, elf_errmsg(-1));
    }

    if (elf_kind(ptr_) != ELF_K_ELF) {
      elf_end(ptr_);
      close(fd_);
      throw ElfError(path, "not an ELF file.");
    }
  }

  ~ElfFile() {
    elf_end(ptr_);
    close(fd_);
  }

  int fd_;
  Elf *ptr_;
};
}  // namespace

// Print a usage message to stdout
static void PrintHelp() {
  std::cout << "Simulation memory utilities:\n\n"
               "-r|--rominit=FILE\n"
               "  Initialize the ROM with FILE (elf/vmem)\n\n"
               "-m|--raminit=FILE\n"
               "  Initialize the RAM with FILE (elf/vmem)\n\n"
               "-f|--flashinit=FILE\n"
               "  Initialize the FLASH with FILE (elf/vmem)\n\n"
               "-l|--meminit=NAME,FILE[,TYPE]\n"
               "  Initialize memory region NAME with FILE [of TYPE]\n"
               "  TYPE is either 'elf' or 'vmem'\n\n"
               "-l list|--meminit=list\n"
               "  Print registered memory regions\n\n"
               "-h|--help\n"
               "  Show help\n\n";
}

// Convert a string to a MemImageType, returning kMemImageUnknown if it's not a
// known name.
static MemImageType GetMemImageTypeByName(const std::string &name) {
  if (name == "elf")
    return kMemImageElf;
  if (name == "vmem")
    return kMemImageVmem;
  return kMemImageUnknown;
}

// Return a MemImageType for the file at filepath, or kMemImageUnknown if not
// known.
static MemImageType DetectMemImageType(const std::string &filepath) {
  size_t ext_pos = filepath.find_last_of(".");
  std::string ext = filepath.substr(ext_pos + 1);

  if (ext_pos == std::string::npos) {
    // Assume ELF files if no file extension is given.
    // TODO: Make this more robust by actually checking the file contents.
    return kMemImageElf;
  }
  return GetMemImageTypeByName(ext);
}

// Parse a meminit command-line argument. This should be of the form
// mem_area,file[,type].
static bool ParseMemArg(std::string mem_argument, std::string &name,
                        std::string &filepath, MemImageType &type) {
  std::array<std::string, 3> args;
  size_t pos = 0;
  size_t end_pos = 0;
  size_t i;

  for (i = 0; i < 3; ++i) {
    end_pos = mem_argument.find(",", pos);
    // Check for possible exit conditions
    if (pos == end_pos) {
      std::cerr << "ERROR: empty field in: " << mem_argument << std::endl;
      return false;
    }
    if (end_pos == std::string::npos) {
      args[i] = mem_argument.substr(pos);
      break;
    }
    args[i] = mem_argument.substr(pos, end_pos - pos);
    pos = end_pos + 1;
  }
  // mem_argument is not empty as getopt requires an argument,
  // but not a valid argument for memory initialization
  if (i == 0) {
    std::cerr << "ERROR: meminit must be in \"name,file[,type]\""
              << " got: " << mem_argument << std::endl;
    return false;
  }

  name = args[0];
  filepath = args[1];

  if (i == 1) {
    // Type not set explicitly
    type = DetectMemImageType(filepath);
  } else {
    type = GetMemImageTypeByName(args[2]);
  }

  return true;
}

static bool IsFileReadable(std::string filepath) {
  struct stat statbuf;
  return stat(filepath.data(), &statbuf) == 0;
}

// Generate a single array of bytes representing the contents of PT_LOAD
// segments of the ELF file. Like objcopy, this generates a single "giant
// segment" whose first byte corresponds to the first byte of the lowest
// addressed segment and whose last byte corresponds to the last byte of the
// highest address.
//
// The data for any intermediate addresses that don't appear in a segment are
// set to zero.
static std::vector<uint8_t> FlattenElfFile(const std::string &filepath) {
  (void)elf_errno();

  if (elf_version(EV_CURRENT) == EV_NONE) {
    throw std::runtime_error(elf_errmsg(-1));
  }

  ElfFile elf(filepath);
  // TODO: add support for ELFCLASS64
  if (gelf_getclass(elf.ptr_) != ELFCLASS32) {
    throw ElfError(filepath, "ELF file is not 32-bit.");
  }

  size_t phnum;
  if (elf_getphdrnum(elf.ptr_, &phnum) != 0) {
    throw ElfError(filepath, elf_errmsg(-1));
  }

  // To mimic what objcopy does (that is, the binary target of BFD), we need to
  // iterate over all loadable program headers, find the lowest address, and
  // then copy in our loadable data based on their offset with respect to the
  // found base address.
  bool any = false;
  GElf_Addr high = 0;
  GElf_Addr low = (GElf_Addr)-1;
  for (size_t i = 0; i < phnum; i++) {
    GElf_Phdr phdr;
    if (gelf_getphdr(elf.ptr_, i, &phdr) == NULL) {
      std::ostringstream oss;
      oss << "in segment number " << i << ": " << elf_errmsg(-1);
      throw ElfError(filepath, oss.str());
    }

    if (phdr.p_type != PT_LOAD) {
      std::cout << "Program header number " << i << " in `" << filepath
                << "' is not of type PT_LOAD; ignoring." << std::endl;
      continue;
    }

    if (phdr.p_memsz == 0) {
      continue;
    }

    if (!any || phdr.p_paddr < low) {
      low = phdr.p_paddr;
    }

    if (!any || phdr.p_paddr + phdr.p_memsz > high) {
      high = phdr.p_paddr + phdr.p_memsz;
    }

    any = true;
  }

  assert(low <= high);
  size_t len_bytes = high - low;

  std::vector<uint8_t> buf(len_bytes);

  for (size_t i = 0; i < phnum; i++) {
    GElf_Phdr phdr;
    (void)gelf_getphdr(elf.ptr_, i, &phdr);

    if (phdr.p_type != PT_LOAD || phdr.p_filesz == 0) {
      continue;
    }

    Elf_Data *elf_data = elf_getdata_rawchunk(elf.ptr_, phdr.p_offset,
                                              phdr.p_filesz, ELF_T_BYTE);
    if (elf_data == NULL) {
      std::ostringstream oss;
      oss << "failed to load data for segment number " << i << ".";
      throw ElfError(filepath, oss.str());
    }

    // Actually copy the data across. elf_getdata_rawchunk has checked that
    // there are elf_data->d_size bytes of data available, and the loop that
    // picked low/high above ensured that we have space to store for p_memsz
    // bytes: use the smaller of the two numbers.
    memcpy(&buf[phdr.p_paddr - low], (uint8_t *)elf_data->d_buf,
           std::min(elf_data->d_size, phdr.p_memsz));
  }

  return buf;
}

static bool WriteElfToMem(const svScope &scope, const std::string &filepath,
                          size_t size_byte) {
  SVScoped scoped(scope);

  std::vector<uint8_t> elf_data;
  try {
    elf_data = FlattenElfFile(filepath);
  } catch (const ElfError &err) {
    std::cerr << "ERROR: " << err.what() << std::endl;
    return false;
  }

  size_t data_len = elf_data.size();

  // elf_data isn't necessarily a whole number of 256-bit words long. Round it
  // up if necessary, padding with zeros. That way, we can safely pass even the
  // last byte to simutil_verilator_set_mem (defined in prim_util_memload.svh),
  // whose "val" argument has SystemVerilog type bit [255:0].
  elf_data.resize((elf_data.size() + 31) / 32 * 32, 0);

  size_t num_words = (data_len + size_byte - 1) / size_byte;
  for (int i = 0; i < num_words; ++i) {
    auto *bvv = reinterpret_cast<const svBitVecVal *>(&elf_data[i * size_byte]);
    if (!simutil_verilator_set_mem(i, bvv)) {
      std::cerr << "ERROR: Could not set memory byte: " << i * size_byte << "/"
                << elf_data.size() << std::endl;
      return false;
    }
  }

  return true;
}

static bool WriteVmemToMem(const svScope &scope, const std::string &filepath) {
  SVScoped scoped(scope);

  // TODO: Add error handling.
  simutil_verilator_memload(filepath.data());

  return true;
}

static bool WriteFileToMem(const MemArea &m, const std::string &filepath,
                           MemImageType type) {
  if (!IsFileReadable(filepath)) {
    std::cerr << "ERROR: Memory initialization file "
              << "'" << filepath << "'"
              << " is not readable." << std::endl;
    return false;
  }

  svScope scope = svGetScopeFromName(m.location.data());
  if (!scope) {
    std::cerr << "ERROR: No memory found at " << m.location << std::endl;
    return false;
  }

  if ((m.width_bit % 8) != 0) {
    std::cerr << "ERROR: width for: " << m.name
              << "must be a multiple of 8 (was : " << m.width_bit << ")"
              << std::endl;
    return false;
  }
  size_t size_byte = m.width_bit / 8;

  switch (type) {
    case kMemImageElf:
      if (!WriteElfToMem(scope, filepath, size_byte)) {
        std::cerr << "ERROR: Writing ELF file to memory \"" << m.name << "\" ("
                  << m.location << ") failed." << std::endl;
        return false;
      }
      break;
    case kMemImageVmem:
      if (!WriteVmemToMem(scope, filepath)) {
        std::cerr << "ERROR: Writing VMEM file to memory \"" << m.name << "\" ("
                  << m.location << ") failed." << std::endl;
        return false;
      }
      break;
    case kMemImageUnknown:
    default:
      std::cerr << "ERROR: Unknown file type for " << m.name << std::endl;
      return false;
  }
  return true;
}

bool VerilatorMemUtil::RegisterMemoryArea(const std::string name,
                                          const std::string location) {
  // Default to 32bit width and no address
  return RegisterMemoryArea(name, location, 32, nullptr);
}

bool VerilatorMemUtil::RegisterMemoryArea(const std::string name,
                                          const std::string location,
                                          size_t width_bit,
                                          const MemAreaLoc *addr_loc) {
  assert((width_bit <= 256) &&
         "TODO: Memory loading only supported up to 256 bits.");

  // First, create and register the memory by name
  MemArea mem = {.name = name,
                 .location = location,
                 .width_bit = width_bit,
                 .addr_loc = {.base = 0, .size = 0}};
  auto ret = name_to_mem_.emplace(name, mem);
  if (ret.second == false) {
    std::cerr << "ERROR: Can not register \"" << name << "\" at: \"" << location
              << "\" (Previously defined at: \"" << ret.first->second.location
              << "\")" << std::endl;
    return false;
  }

  MemArea *stored_mem_area = &ret.first->second;

  // If we have no address information, there's nothing more to do. However, if
  // we do have address information, we should add an entry to addr_to_mem_.
  if (!addr_loc) {
    return true;
  }

  // Check that the size of the new area is positive, and that we don't overflow
  // the address space.
  if (addr_loc->size == 0) {
    std::cerr << "ERROR: Can not register '" << name
              << "' because it has zero size.\n";
    return false;
  }
  uint32_t addr_top = addr_loc->base + (addr_loc->size - 1);
  if (addr_top < addr_loc->base) {
    std::cerr << "ERROR: Can not register '" << name
              << "' because it overflows the top of the address space.\n";
    return false;
  }

  // If the existing map is non-empty, we must check for overlaps
  if (!addr_to_mem_.empty()) {
    // We start by checking for an overlap "from the right". This would be a
    // region that starts strictly above addr_loc->base, but where it's low
    // address is still less than addr_top. We can use std::map::upper_bound to
    // find the first region strictly above addr_loc->base (which returns the
    // end iterator if there isn't one).
    auto right_it = addr_to_mem_.upper_bound(addr_loc->base);
    if (right_it != addr_to_mem_.end()) {
      const MemAreaLoc &ub_loc = right_it->second->addr_loc;
      assert(ub_loc.size != 0);
      if (ub_loc.base <= addr_top) {
        std::cerr << "ERROR: Can not register '" << name
                  << "' because its address range overlaps to left of '"
                  << right_it->second->name << "'.\n";
        return false;
      }
    }

    // We also need to check from the other side. This would be a region that
    // starts at or before addr_loc->base and extends past it. If right_it is
    // addr_to_mem_.begin(), there is no such region (because the lowest
    // addressed region already starts above addr_loc->base). Otherwise,
    // decrement right_it to get the highest addressed region that starts at or
    // before addr_loc->base. Note this still works if right_it is the end
    // iterator: we just pick up the last region, which we know exists because
    // addr_to_mem_ is not empty.
    if (right_it != addr_to_mem_.begin()) {
      auto left_it = std::prev(right_it);
      const MemAreaLoc &lb_loc = left_it->second->addr_loc;
      assert(lb_loc.size != 0);
      uint32_t lb_max = lb_loc.base + lb_loc.size;
      if (addr_loc->base <= lb_max) {
        std::cerr << "ERROR: Can not register '" << name
                  << "' because its address range overlaps to right of '"
                  << left_it->second->name << "'.\n";
        return false;
      }
    }
  }

  // Phew, no overlap!
  addr_to_mem_.insert(std::make_pair(addr_loc->base, stored_mem_area));
  stored_mem_area->addr_loc = *addr_loc;
  return true;
}

bool VerilatorMemUtil::ParseCLIArguments(int argc, char **argv,
                                         bool &exit_app) {
  const struct option long_options[] = {
      {"rominit", required_argument, nullptr, 'r'},
      {"raminit", required_argument, nullptr, 'm'},
      {"flashinit", required_argument, nullptr, 'f'},
      {"meminit", required_argument, nullptr, 'l'},
      {"help", no_argument, nullptr, 'h'},
      {nullptr, no_argument, nullptr, 0}};

  // Reset the command parsing index in-case other utils have already parsed
  // some arguments
  optind = 1;
  while (1) {
    int c = getopt_long(argc, argv, ":r:m:f:l:h", long_options, nullptr);
    if (c == -1) {
      break;
    }

    // Disable error reporting by getopt
    opterr = 0;

    switch (c) {
      case 0:
        break;
      case 'r':
        if (!MemWrite("rom", optarg)) {
          std::cerr << "ERROR: Unable to initialize memory." << std::endl;
          return false;
        }
        break;
      case 'm':
        if (!MemWrite("ram", optarg)) {
          std::cerr << "ERROR: Unable to initialize memory." << std::endl;
          return false;
        }
        break;
      case 'f':
        if (!MemWrite("flash", optarg)) {
          std::cerr << "ERROR: Unable to initialize memory." << std::endl;
          return false;
        }
        break;
      case 'l': {
        if (strcasecmp(optarg, "list") == 0) {
          PrintMemRegions();
          exit_app = true;
          return true;
        }

        std::string name;
        std::string filepath;
        MemImageType type;
        if (!ParseMemArg(optarg, name, filepath, type)) {
          std::cerr << "ERROR: Unable to parse meminit arguments." << std::endl;
          return false;
        }

        if (!MemWrite(name, filepath, type)) {
          std::cerr << "ERROR: Unable to initialize memory." << std::endl;
          return false;
        }
      } break;
      case 'h':
        PrintHelp();
        return true;
      case ':':  // missing argument
        std::cerr << "ERROR: Missing argument." << std::endl << std::endl;
        return false;
      case '?':
      default:;
        // Ignore unrecognized options since they might be consumed by
        // other utils
    }
  }

  return true;
}

void VerilatorMemUtil::PrintMemRegions() const {
  std::cout << "Registered memory regions:" << std::endl;
  for (const auto &pr : name_to_mem_) {
    const MemArea &m = pr.second;
    std::cout << "\t'" << m.name << "' (" << m.width_bit
              << "bits) at location: '" << m.location << "'";
    if (m.addr_loc.size) {
      uint32_t low = m.addr_loc.base;
      uint32_t high = m.addr_loc.base + m.addr_loc.size - 1;
      std::cout << " (LMA range [0x" << std::hex << low << ", 0x" << high
                << "])" << std::dec;
    }
    std::cout << std::endl;
  }
}

bool VerilatorMemUtil::MemWrite(const std::string &name,
                                const std::string &filepath) {
  MemImageType type = DetectMemImageType(filepath);
  if (type == kMemImageUnknown) {
    std::cerr << "ERROR: Unable to detect file type for: " << filepath
              << std::endl;
    // Continuing for more error messages
  }
  return MemWrite(name, filepath, type);
}

bool VerilatorMemUtil::MemWrite(const std::string &name,
                                const std::string &filepath,
                                MemImageType type) {
  // Search for corresponding registered memory based on the name
  auto it = name_to_mem_.find(name);
  if (it == name_to_mem_.end()) {
    std::cerr << "ERROR: Memory location not set for: '" << name << "'"
              << std::endl;
    PrintMemRegions();
    return false;
  }

  if (!WriteFileToMem(it->second, filepath, type)) {
    std::cerr << "ERROR: Setting memory '" << name << "' failed." << std::endl;
    return false;
  }
  return true;
}
