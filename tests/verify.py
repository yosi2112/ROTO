"""Execute the delivered COM, model PC-98 ports, check independent pixel results.
Requires Unicorn and Pillow. This is not a ROM/BIOS compatibility test.
"""
from pathlib import Path
import hashlib
import json
import math
import struct
import sys
import os

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/python'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_INSN, UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.x86_const import *
from PIL import Image

BINARY = (ROOT / os.environ.get('ROTO_BINARY', 'ROTO.com')).read_bytes()
BASE = 0x10000
names = 'frame du dv row_u row_v texture transforms stack_bottom program_end'.split()
offset = BINARY.index(b'ROTO98SYM') + 9
SYM = dict(zip(names, struct.unpack_from('<9H', BINARY, offset)))
assert 0 < len(BINARY) <= 65280
assert SYM['program_end'] == len(BINARY) + 256


def expected(angle):
    theta = angle * math.tau / 256
    scale = .72 + .32 * math.sin(2 * theta)
    a, b = round(256 * scale * math.cos(theta)), round(256 * scale * math.sin(theta))
    pixels = bytearray()
    for y in range(100):
        for x in range(160):
            u = ((8192 + (x - 80)*a - (y - 50)*b) >> 8) & 63
            v = ((8192 + (x - 80)*b + (y - 50)*a) >> 8) & 63
            tx, ty = u & 31, v & 31
            d = abs(tx-16) + abs(ty-16)
            c = [1, 5, 3, 6][(u >> 5) + 2*(v >> 5)]
            if tx < 2 or ty < 2: c = 0
            elif tx == 2 or ty == 2: c = 7
            elif tx == 31 or ty == 31: c = 1
            elif d < 6: c = 7
            elif d < 9: c = 0
            pixels.extend([c]*4)
        line = pixels[-640:]
        pixels.extend(line*3)
    return bytes(pixels)


def decode(planes):
    pixels = bytearray(640*400)
    for i in range(32000):
        for bit in range(8):
            mask = 128 >> bit
            pixels[i*8+bit] = sum((1 << p) for p in range(3) if planes[p][i] & mask)
    return bytes(pixels)


def run(args=' /T', key=None, stuck=None, spread=False):
    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(0, 0x100000)
    uc.mem_write(BASE+256, BINARY)
    uc.mem_write(BASE+128, bytes([len(args)])+args.encode()+b'\r')
    for r in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        uc.reg_write(r, BASE >> 4)
    uc.reg_write(UC_X86_REG_SP, 65534)
    uc.reg_write(UC_X86_REG_EFLAGS, 0x202)
    pages = [[bytearray(32768) for _ in range(3)] for _ in range(2)]
    state = dict(draw=0, display=0, graphics=False, text=True, frames=0,
                 polls=0, exited=False, angle=0, hashes=[], ports={}, bios=[])

    def write_mem(u, access, address, size, value, data):
        if 0xa8000 <= address < 0xc0000:
            plane, at = divmod(address-0xa8000, 32768)
            assert at + size <= 32000, ('VRAM overrun', hex(address))
            pages[state['draw']][plane][at:at+size] = value.to_bytes(size, 'little')
        else:
            assert BASE+128 <= address and address+size <= BASE+SYM['program_end'], hex(address)

    def interrupt(u, number, data):
        ax = u.reg_read(UC_X86_REG_AX)
        ah = ax >> 8
        if number == 0x18:
            state['bios'].append(ah)
            if ah == 0x42: assert u.reg_read(UC_X86_REG_CX) >> 8 == 0xc0
            elif ah == 0x40: state['graphics'] = True
            elif ah == 0x41: state['graphics'] = False
            elif ah == 0x0c: state['text'] = True
            elif ah == 0x0d: state['text'] = False
            else: raise AssertionError(('BIOS', hex(ax)))
        elif number == 0x21:
            if ah == 0x4c:
                assert ax & 255 == 0
                state['exited'] = True
                u.emu_stop()
            elif ah == 6:
                flags = u.reg_read(UC_X86_REG_EFLAGS)
                u.reg_write(UC_X86_REG_EFLAGS, flags | 64 if key is None else flags & ~64)
                u.reg_write(UC_X86_REG_AX, (ax & 0xff00) | (key or 0))
            elif ah == 0x2c:
                u.reg_write(UC_X86_REG_CX, 0)
                u.reg_write(UC_X86_REG_DX, 0)
            elif ah != 9: raise AssertionError(('DOS', hex(ax)))
        else: raise AssertionError(number)

    def input_port(u, port, size, data):
        if port in (0x5f, 0xa460, 0x88, 0x8a, 0x188, 0x18a, 0x288, 0x28a): return 255  # no board in visual regressions
        if port == 0x5f: return 0
        assert port == 0xa0 and size == 1
        state['polls'] += 1
        return stuck if stuck is not None else (0x20 if state['polls'] % 2 == 0 else 0)

    def output_port(u, port, size, value, data):
        assert size == 1
        assert port in (0x6a, 0x7c, 0xa4, 0xa6, 0xa8, 0xaa, 0xac, 0xae,
                        0x88, 0x8a, 0x188, 0x18a, 0x288, 0x28a,
                        0xa460, 0xa466, 0xa468, 0xa46a, 0xa46c, 0xa66e)
        state['ports'][port] = value
        if port == 0xa6:
            state['draw'] = value
            assert value in (0, 1)
        if port == 0xa4:
            state['display'] = value
            if state['graphics']:
                assert value == state['draw']
                assert value == (0 if 'S' in args else (state['frames']+1) % 2)
                pixels = decode(pages[value])
                assert pixels == expected(state['angle']), ('pixel mismatch', state['angle'])
                assert all(not any(p[32000:]) for p in pages[value])
                if spread and state['frames'] in (0, 2, 4, 6):
                    im = Image.frombytes('P', (640, 400), pixels)
                    im.putpalette([component for i in range(256) for component in
                                   (255 if i&2 else 0, 255 if i&4 else 0, 255 if i&1 else 0)])
                    suffix = '-asw' if os.environ.get('ROTO_BINARY') == 'ROTOASW.com' else ''
                    im.save(ROOT / f'build/frame-{state["angle"]:03}{suffix}.png')
                state['hashes'].append(hashlib.sha256(pixels).hexdigest())
                state['frames'] += 1

    def frame_start(u, address, size, data):
        angle_addr = BASE + SYM['du'] - 2
        if spread:
            u.mem_write(angle_addr, struct.pack('<H', (state['frames']*16) % 256))
        state['angle'] = int.from_bytes(u.mem_read(angle_addr, 2), 'little')

    uc.hook_add(UC_HOOK_MEM_WRITE, write_mem)
    uc.hook_add(UC_HOOK_INTR, interrupt)
    uc.hook_add(UC_HOOK_INSN, input_port, None, 1, 0, UC_X86_INS_IN)
    uc.hook_add(UC_HOOK_INSN, output_port, None, 1, 0, UC_X86_INS_OUT)
    uc.hook_add(UC_HOOK_CODE, frame_start, begin=BASE+SYM['frame'], end=BASE+SYM['frame'])
    uc.emu_start(BASE+256, 0xfffff, count=30000000)
    assert state['exited'], 'Program did not return to DOS'
    assert state['text'] and not state['graphics']
    assert state['display'] == state['draw'] == 0
    if '?' not in args:
        assert state['ports'][0x7c] == 0
        assert [state['ports'][p] for p in (0xa8,0xaa,0xac,0xae)] == [0x37,0x15,0x26,4]
        assert state['frames'] == (1 if key is not None else 16)
    return {k: state[k] for k in ('frames', 'polls', 'hashes')}


if __name__ == '__main__':
    (ROOT / 'build').mkdir(exist_ok=True)
    cases = [('double_page', {}), ('all_quadrants', {'spread': True}),
             ('single_page', {'args': ' /S /T'}), ('escape', {'args': '', 'key': 27}),
             ('quit_key', {'args': '', 'key': ord('q')}),
             ('vsync_low', {'args': '', 'key': 27, 'stuck': 0}),
             ('vsync_high', {'args': '', 'key': 27, 'stuck': 32}),
             ('help', {'args': ' /?'})]
    results = {}
    for name, kwargs in cases:
        results[name] = run(**kwargs)
        print(f'PASS {name}: {results[name]["frames"]} frame(s)', flush=True)
    report = dict(binary_sha256=hashlib.sha256(BINARY).hexdigest(), bytes=len(BINARY), cases=results)
    report_name = 'verification-asw.json' if os.environ.get('ROTO_BINARY') == 'ROTOASW.com' else 'verification.json'
    (ROOT / 'build' / report_name).write_text(json.dumps(report, indent=2)+'\n')
