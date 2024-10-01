# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

from typing import Any, Dict, List, Optional

from design.mubi import prim_mubi  # type: ignore

from reggen.access import SWAccess, HWAccess
from reggen.bits import Bits
from reggen.enum_entry import EnumEntry
from reggen.lib import (check_keys, check_str, check_name, check_bool,
                        check_list, check_str_list, check_xint)
from reggen.params import ReggenParams

REQUIRED_FIELDS = {
    'bits': ['b', "bit or bit range (msb:lsb)"]
}

OPTIONAL_FIELDS = {
    'name': ['s', "name of the field"],
    'desc': [
        't',
        "description of field (required if the field has a name). "
        "This field supports the markdown syntax."
    ],
    'alias_target': [
        's',
        "name of the field to apply the alias definition to."
    ],
    'swaccess': [
        's', "software access permission, copied from "
        "register if not provided in field. "
        "(Tool adds if not provided.)"
    ],
    'hwaccess': [
        's', "hardware access permission, copied from "
        "register if not provided in field. "
        "(Tool adds if not provided.)"
    ],
    'hwqe': [
        'b', "'true' if hardware uses 'q' enable signal, "
        "which is latched signal of software write pulse. "
        "Copied from register if not provided in field. "
        "(Tool adds if not provided.)"
    ],
    'resval': [
        'x', "reset value, comes from register resval "
        "if not provided in field. Zero if neither "
        "are provided and the field is readable, "
        "x if neither are provided and the field "
        "is wo. Must match if both are provided."
    ],
    'enum': ['l', "list of permitted enumeration groups"],
    'tags': [
        's',
        "tags for the field, followed by the format 'tag_name:item1:item2...'"
    ],
    'mubi': [
        'b',
        "boolean flag for whether the field is a multi-bit type"
    ],
    'auto_split': [
        'b',
        "boolean flag which determines whether the field "
        "should be automatically separated into 1-bit sub-fields."
        "This flag is used as a hint for automatically generated "
        "software headers with register description."
    ]
}


class Field:
    def __init__(self,
                 name: str,
                 alias_target: Optional[str],
                 desc: Optional[str],
                 tags: List[str],
                 swaccess: SWAccess,
                 hwaccess: HWAccess,
                 hwqe: bool,
                 bits: Bits,
                 resval: Optional[int],
                 enum: Optional[List[EnumEntry]],
                 mubi: bool,
                 auto_split: bool):
        self.name = name
        self.alias_target = alias_target
        self.desc = desc
        self.tags = tags
        self.swaccess = swaccess
        self.hwaccess = hwaccess
        self.hwqe = hwqe
        self.bits = bits
        self.resval = resval
        self.enum = enum
        self.mubi = mubi
        self.auto_split = auto_split

    @staticmethod
    def resval_from_raw(field_bits: Bits,
                        bindings: Dict[str, int],
                        raw_value: Any,
                        is_mubi: bool,
                        where: str) -> Optional[int]:
        '''Calculate any specific resval for the field

        field_bits is an object giving the (indices of the) bits that make up
        the field in the register.

        The bindings dictionary gives values to zero or more named local
        variables that may used when evaluating the field reset value
        (described below).

        If raw_value is not None, this is a value from the hjson input, giving
        the resval that is specified for the field itself. This value can be
        specified in several different ways:

         - A boolean (parsed by check_bool)

         - An integer (parsed by check_xint)

         - A string that contains a (Python) expression that evaluates to an
           integer. This evaluation is performed with bindings supplied by the
           local_bindings dictionary.

        The result of interpreting this string/bool/int will be an integer,
        which is interpreted as the logical reset value for the field.

        If is_mubi is true, the field is encoded as a multi-bit boolean with a
        width that can be calculated from field_bits. This has no effect if
        raw_value is None (because we are computing the field reset value by
        extracting bits from reg_resval). If raw_value is not None, on the
        other hand, it must have evaluated to an integer that is 0 or 1. This
        logical reset value will be encoded as the appropriate mubi physical
        value.

        The where argument is a string that describes where the reset value is
        being specified (used in error messages).
        '''
        if raw_value is None:
            return None

        what = 'resval field for {}'.format(where)

        resval = None  # type: Any

        # Start by checking whether raw_value can be interpreted as a boolean.
        # If not, it's no problem: just leave resval equal to None.
        try:
            resval = check_bool(raw_value, what)
        except ValueError:
            pass

        # Now check whether raw_value can be interpreted as an integer. Allow
        # 'x', which means there is no resval specifically defined for this
        # field and we return None. Again: this interpretation might not be
        # possible. That's fine: still leave resval equal to None.
        if resval is None:
            try:
                resval = check_xint(raw_value, what)
                if resval is None:
                    return None
            except ValueError:
                pass

        # If we still haven't managed to parse things, we want to evaluate
        # raw_value as Python code.
        if resval is None:
            # raw_value should be a string which we can evaluate as Python
            # code.
            if not isinstance(raw_value, str):
                raise ValueError(f'{what} is not a bool or integer, so it '
                                 f'should be a string containing a Python '
                                 f'expression. Instead, it is {raw_value!r}')

            try:
                resval = eval(raw_value, bindings)
            except Exception as err:
                raise ValueError(f'Failed to evaluate Python expression for '
                                 f'value of {what}: {err}')

            if not isinstance(resval, int):
                raise ValueError(f'The expression for the value of {what} '
                                 f'was {raw_value!r}, which evaluated to '
                                 f'{resval!r} rather than an integer.')

        assert isinstance(resval, int)

        # At this point, we have parsed resval to some integer which gives the
        # logical reset value for the field. If this field is a multi-bit
        # boolean, encode it as the corresponding multi-bit value now.
        if is_mubi:
            if resval not in [0, 1]:
                raise ValueError(f'The resval for {where} is {resval!r}, '
                                 f'which cannot be encoded as a mubi value.')

            if not prim_mubi.is_width_valid(field_bits.width()):
                raise ValueError(f'The field {where} is defined as a mubi '
                                 f'value of the unsupported width '
                                 f'{field_bits.width()}.')

            physval = prim_mubi.mubi_value_as_int(resval == 1,
                                                  field_bits.width())
        else:
            physval = resval

        assert isinstance(physval, int)

        # Now we have an encoding, check that it can actually be represented in
        # the field's bits.
        if not (0 <= physval <= field_bits.max_value()):
            raise ValueError(f'The resval {where} is {physval!r}, which '
                             f'isn\'t representable as an unsigned '
                             f'{field_bits.width()}-bit integer.')

        return physval

    @staticmethod
    def from_raw(reg_name: str,
                 field_idx: int,
                 num_fields: int,
                 default_swaccess: SWAccess,
                 default_hwaccess: HWAccess,
                 reg_resval: Optional[int],
                 reg_width: int,
                 params: ReggenParams,
                 hwext: bool,
                 default_hwqe: bool,
                 shadowed: bool,
                 is_alias: bool,
                 raw: object) -> 'Field':
        where = 'field {} of {} register'.format(field_idx, reg_name)
        rd = check_keys(raw, where,
                        list(REQUIRED_FIELDS.keys()),
                        list(OPTIONAL_FIELDS.keys()))

        raw_name = rd.get('name')
        if raw_name is None:
            name = ('field{}'.format(field_idx + 1)
                    if num_fields > 1 else reg_name)
        else:
            name = check_name(raw_name, 'name of {}'.format(where))

        alias_target = None
        if rd.get('alias_target') is not None:
            if is_alias:
                alias_target = check_name(rd.get('alias_target'),
                                          'name of alias target register')
            else:
                raise ValueError('Field {} may not have an alias_target key.'
                                 .format(name))

        raw_desc = rd.get('desc')
        if raw_desc is None and raw_name is not None:
            raise ValueError('Missing desc field for {}'
                             .format(where))
        if raw_desc is None:
            desc = None
        else:
            desc = check_str(raw_desc, 'desc field for {}'.format(where))

        tags = check_str_list(rd.get('tags', []),
                              'tags for {}'.format(where))

        raw_mubi = rd.get('mubi', False)
        is_mubi = check_bool(raw_mubi, 'mubi field for {}'.format(where))
        raw_swaccess = rd.get('swaccess')
        if raw_swaccess is not None:
            swaccess = SWAccess(where, raw_swaccess, is_mubi)
        else:
            swaccess = default_swaccess
            swaccess.is_mubi = is_mubi

        raw_hwaccess = rd.get('hwaccess')
        if raw_hwaccess is not None:
            hwaccess = HWAccess(where, raw_hwaccess)
        else:
            hwaccess = default_hwaccess

        raw_hwqe = rd.get('hwqe', default_hwqe)
        hwqe = check_bool(raw_hwqe, 'hwqe field for {}'.format(where))
        raw_auto_split = rd.get('auto_split', False)
        is_auto_split = check_bool(raw_auto_split, 'auto_split field for {}'.format(where))

        # Currently internal shadow registers do not support hw write type
        if not hwext and shadowed and hwaccess.allows_write():
            raise ValueError('Internal Shadow registers do not currently support '
                             'hardware write')

        bits = Bits.from_raw(where, reg_width, params, rd['bits'])

        # Try to evaluate any 'resval' that has been defined for the field
        # directly. If it is 'x' then field_resval will be None.
        field_resval_raw = rd.get('resval')
        field_resval = Field.resval_from_raw(bits,
                                             {},  # TODO: Bindings for multiregs
                                             field_resval_raw,
                                             is_mubi,
                                             where)

        # Interpret the reset value for the field implied by the register reset
        # value. Normally this defaults to zero if we don't actually have a
        # register reset value (because the implied default is zero), but it
        # defaults to None (an unknown reset value) if the register is hwext.
        resval_from_reg = None  # type: Optional[int]
        if reg_resval is not None:
            resval_from_reg = bits.extract_field(reg_resval)
        elif hwext:
            resval_from_reg = None
        else:
            resval_from_reg = 0

        # Resolve the two resvals.
        #
        #   - If neither is defined (or both are 'x'), they resolve to None.
        #
        #   - If only one is defined, it takes precedence.
        #
        #   - If both are defined, check that they match.
        if field_resval_raw is None:
            merged_resval = resval_from_reg
        else:
            merged_resval = field_resval
            if reg_resval is not None and field_resval != resval_from_reg:
                raise ValueError(f'resval for {where} is {field_resval}, '
                                 f'but the register defines a resval as '
                                 f'well, where the field\'s bits would '
                                 f'give {resval_from_reg}.')

        raw_enum = rd.get('enum')
        if raw_enum is None:
            enum = None
        else:
            enum = []
            raw_entries = check_list(raw_enum,
                                     'enum field for {}'.format(where))
            enum_val_to_name = {}  # type: Dict[int, str]
            for idx, raw_entry in enumerate(raw_entries):
                entry = EnumEntry('entry {} in enum list for {}'
                                  .format(idx + 1, where),
                                  bits.max_value(),
                                  raw_entry)
                if entry.value in enum_val_to_name:
                    raise ValueError('In {}, duplicate enum entries for '
                                     'value {} ({} and {}).'
                                     .format(where,
                                             entry.value,
                                             enum_val_to_name[entry.value],
                                             entry.name))
                enum.append(entry)
                enum_val_to_name[entry.value] = entry.name

        return Field(name, alias_target, desc, tags, swaccess, hwaccess,
                     hwqe, bits, merged_resval, enum, is_mubi, is_auto_split)

    def has_incomplete_enum(self) -> bool:
        return (self.enum is not None and
                len(self.enum) != 1 + self.bits.max_value())

    def get_n_bits(self, hwext: bool, hwre: bool, bittype: List[str]) -> int:
        '''Get the size of this field in bits

        bittype should be a list of the types of signals to count. The elements
        should come from the following list:

        - 'q': A signal for the value of the field. Only needed if HW can read
          its contents.

        - 'd': A signal for the next value of the field. Only needed if HW can
          write its contents.

        - 'de': A write enable signal for hardware accesses. Only needed if HW
          can write the field's contents and the register data is stored in the
          register block (true if the hwext flag is false).

        '''
        n_bits = 0
        if "q" in bittype and self.hwaccess.allows_read():
            n_bits += self.bits.width()
        if "d" in bittype and self.hwaccess.allows_write():
            n_bits += self.bits.width()
        if "qe" in bittype and self.hwaccess.allows_read():
            n_bits += int(self.hwqe)
        if "re" in bittype and self.hwaccess.allows_read():
            n_bits += int(hwre)
        if "de" in bittype and self.hwaccess.allows_write():
            n_bits += int(not hwext)
        return n_bits

    def replicate(self,
                  idx0: int,
                  count: int,
                  desc: Optional[str],
                  strip_enum: bool) -> List['Field']:
        '''Return a list of one or more copies of this field

        The copies are indexed from idx0 to idx0+count-1 and their names are
        constructed by appending the index in the form "field_name_123". If the
        field is an alias, the target of the alias is renamed in the same way
        ("target_name_123").

        If desc is not None, this is used as the description for the field
        copies, overriding self.desc.

        Values of field might be from an enumerated type, with known values in
        self.enum. If strip_enum is true, the copies of the field have their
        enum type stripped and just become blocks of bits.
        '''

        assert 0 <= idx0
        assert count > 0
        field_width = self.bits.msb + 1

        enum = None if strip_enum else self.enum

        ret = []
        for idx in range(idx0, idx0 + count):
            name = '{}_{}'.format(self.name, idx)
            # In case this is an alias register, we need to make sure that
            # the alias_target name is expanded as well.
            alias_target = None
            if self.alias_target is not None:
                alias_target = '{}_{}'.format(self.alias_target, idx)

            bit_offset = field_width * (idx - idx0)
            bits = self.bits.make_translated(bit_offset)

            ret.append(Field(name, alias_target, desc or self.desc,
                             self.tags, self.swaccess, self.hwaccess,
                             self.hwqe, bits, self.resval, enum, self.mubi,
                             self.auto_split))

        return ret

    def make_suffixed(self, suffix: str,
                      cname: str,
                      creg_idx: int,
                      stripped: bool) -> 'Field':
        desc = ('For {}{}'.format(cname, creg_idx)
                if stripped else self.desc)
        enum = None if stripped else self.enum

        alias_target = None
        if self.alias_target is not None:
            alias_target = self.alias_target + suffix

        return Field(self.name + suffix, alias_target,
                     desc, self.tags, self.swaccess, self.hwaccess, self.hwqe,
                     self.bits, self.resval, enum, self.mubi, self.auto_split)

    def _asdict(self) -> Dict[str, object]:
        rd = {
            'bits': self.bits.as_str(),
            'name': self.name,
            'swaccess': self.swaccess.key,
            'hwaccess': self.hwaccess.key,
            'resval': 'x' if self.resval is None else str(self.resval),
            'tags': self.tags
        }  # type: Dict[str, object]

        if self.desc is not None:
            rd['desc'] = self.desc
        if self.enum is not None:
            rd['enum'] = self.enum
        if self.alias_target is not None:
            rd['alias_target'] = self.alias_target
        return rd

    def sw_readable(self) -> bool:
        return self.swaccess.key not in ['wo', 'r0w1c']

    def sw_writable(self) -> bool:
        return self.swaccess.key != 'ro'

    def apply_alias(self, alias_field: 'Field', where: str) -> None:
        '''Compare all attributes and replace overridable values.

        This updates the overridable field attributes with the alias values and
        ensures that all non-overridable attributes have identical values.
        '''

        # Attributes to be crosschecked
        attrs = ['bits', 'swaccess', 'hwaccess', 'hwqe', 'mubi']
        for attr in attrs:
            if getattr(self, attr) != getattr(alias_field, attr):
                raise ValueError('Value mismatch for attribute {} between '
                                 'alias field {} and field {} in {}.'
                                 .format(attr, self.name,
                                         alias_field.name, where))

        # These attributes can be overridden by the aliasing mechanism.
        self.name = alias_field.name
        self.desc = alias_field.desc
        self.enum = alias_field.enum
        self.resval = alias_field.resval
        self.tags = alias_field.tags
        # We also keep track of the alias_target when overriding attributes.
        # This gives us a way to check whether a register has been overridden
        # or not, and what the name of the original register was.
        self.alias_target = alias_field.alias_target

    def scrub_alias(self, where: str) -> None:
        '''Replaces sensitive fields in field with generic names

        This function can be used to create the generic field descriptions
        from full alias hjson definitions.
        '''
        # These attributes are scrubbed. Note that the name is scrubbed in
        # register.py already.
        self.desc = ''
        self.enum = []
        self.resval = 0
        self.tags = []
        self.alias_target = None
