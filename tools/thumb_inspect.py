#!/usr/bin/env python3
"""Inspect an owned ARM ELF; this tool never edits or patches the file."""
import argparse
from pathlib import Path
import struct
from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB
from capstone.arm import ARM_OP_REG, ARM_OP_MEM, ARM_REG_PC
from elftools.elf.elffile import ELFFile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', type=Path)
    parser.add_argument('start', nargs='?', type=lambda x: int(x, 0))
    parser.add_argument('end', nargs='?', type=lambda x: int(x, 0))
    parser.add_argument('--find', help='find an ASCII string and print its virtual addresses')
    args = parser.parse_args()
    data = args.elf.read_bytes()
    with args.elf.open('rb') as stream:
        elf = ELFFile(stream)
        if not elf.little_endian or elf['e_machine'] != 'EM_ARM':
            parser.error('expected little-endian ARM ELF')
        segments = [(s['p_vaddr'], s['p_offset'], s['p_filesz'])
                    for s in elf.iter_segments() if s['p_type'] == 'PT_LOAD']

    def offset(address, size=1):
        for va, off, count in segments:
            if va <= address and address + size <= va + count:
                return off + address - va
        raise ValueError(f'unmapped virtual address 0x{address:x}')

    if args.find:
        needle = args.find.encode('ascii')
        found = False
        for va, off, count in segments:
            position = data.find(needle, off, off + count)
            while position >= 0:
                print(f'0x{va + position - off:x} file+0x{position:x} {args.find}')
                found = True
                position = data.find(needle, position + 1, off + count)
        return 0 if found else 1
    if args.start is None or args.end is None or args.end <= args.start:
        parser.error('provide START END or --find STRING')
    start = offset(args.start, args.end - args.start)
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    md.detail = True
    loaded = {}
    for instruction in md.disasm(data[start:start + args.end - args.start], args.start):
        annotation = ''
        operands = instruction.operands
        if (instruction.mnemonic.startswith('ldr') and len(operands) == 2 and
                operands[0].type == ARM_OP_REG and operands[1].type == ARM_OP_MEM and
                operands[1].mem.base == ARM_REG_PC):
            address = ((instruction.address + 4) & ~3) + operands[1].mem.disp
            try:
                value = struct.unpack_from('<I', data, offset(address, 4))[0]
                loaded[operands[0].reg] = (value, instruction.address)
                annotation = f' ; literal 0x{value:x}'
            except ValueError:
                pass
        if (instruction.mnemonic == 'add' and len(operands) == 2 and
                operands[1].type == ARM_OP_REG and operands[1].reg == ARM_REG_PC):
            previous = loaded.get(operands[0].reg)
            if previous and instruction.address - previous[1] < 120:
                address = (previous[0] + instruction.address + 4) & 0xffffffff
                try:
                    off = offset(address)
                    string = data[off:off + 160].split(b'\0', 1)[0]
                    if string and all(32 <= b < 127 for b in string):
                        annotation = f' ; 0x{address:x} {string.decode("ascii")}'
                except ValueError:
                    pass
        print(f'{instruction.address:08x}: {instruction.mnemonic} {instruction.op_str}{annotation}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
