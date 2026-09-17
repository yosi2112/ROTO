"""Execute both COMs with independent VRAM/charger models, not a real BIOS ROM."""
import hashlib
import json
import struct
from pathlib import Path
from verify import expected, decode, BASE
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_INSN, UC_HOOK_MEM_WRITE, UC_HOOK_CODE
from unicorn.x86_const import *

ROOT = Path(__file__).resolve().parents[1]


def run(binary, kind, args=' /M', angle=0, bios_failure=None):
    sym = struct.unpack_from('<9H', binary, binary.index(b'ROTO98SYM') + 9)
    vid = struct.unpack_from('<10H', binary, binary.index(b'ROTO98VID') + 9)
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x100000)
    u.mem_write(BASE + 256, binary)
    u.mem_write(BASE + 128, bytes([len(args)]) + args.encode() + b'\r')
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        u.reg_write(reg, BASE >> 4)
    u.reg_write(UC_X86_REG_SP, 65534)
    u.reg_write(UC_X86_REG_EFLAGS, 0x202)
    hires = kind == 'hires'
    grcg = kind in ('grcg', 'egc', 'pegc')
    egc = kind in ('egc', 'pegc')
    u.mem_write(0x501, bytes([8 if hires else 0]))
    u.mem_write(0x54c, bytes([2 if grcg else 0]))
    u.mem_write(0x54d, bytes([64 if egc else 0]))
    u.mem_write(0x45c, bytes([64 if kind == 'pegc' else 0]))
    planes = [[bytearray(b'\xa5' * (131072 if hires else 32768)) for _ in range(4)] for _ in range(2)]
    packed = bytearray(b'\xa5' * 524288)
    state = dict(mode=0, tiles=[], draw=0, bank=0, packed=False, index=0,
                 palette={}, ports=[], bios=[], frames=0, exit=None, polls=0, banks=set())

    def write(cpu, access, address, size, value, data):
        raw = value.to_bytes(size, 'little')
        if hires and 0xc0000 <= address < 0xe0000:
            offset = address - 0xc0000
            assert offset + size <= 131072
            for p in range(4):
                if not state['mode'] & (1 << p):
                    planes[0][p][offset:offset + size] = raw
        elif not hires and state['packed'] and 0xe0000 <= address < 0xe0200:
            assert (address, size) in ((0xe0004, 2), (0xe0006, 2), (0xe0100, 2), (0xe0102, 2))
            if address == 0xe0004:
                assert value < 8
                state['bank'] = value
                state['banks'].add(value)
            elif address in (0xe0100, 0xe0102):
                assert value == 0
        elif not hires and 0xa8000 <= address < 0xc0000:
            if state['packed']:
                assert address + size <= 0xb0000
                offset = state['bank'] * 32768 + address - 0xa8000
                assert offset + size <= 256000
                packed[offset:offset + size] = raw
            else:
                p, offset = divmod(address - 0xa8000, 32768)
                assert offset + size <= 32000
                if state['mode'] & 128:
                    assert grcg and not state['mode'] & 64 and len(state['tiles']) == 4
                    for p in range(4):
                        planes[state['draw']][p][offset:offset + size] = bytes([state['tiles'][p]]) * size
                else:
                    planes[state['draw']][p][offset:offset + size] = raw
        else:
            assert BASE + 128 <= address and address + size <= BASE + sym[8], hex(address)

    def output(cpu, port, size, value, data):
        assert size == 1
        state['ports'].append((port, value))
        if port == (0xa4 if hires else 0x7c):
            state['mode'] = value
            state['tiles'] = []
        elif port == 0x7e:
            assert grcg and not hires
            state['tiles'].append(value)
        elif port == 0xa6:
            assert not hires, 'A6 is tile data on high-resolution machines'
            state['draw'] = value
        elif port == 0x6a:
            if value in (7, 4, 6):
                assert egc
            if value == 0x21:
                assert kind == 'pegc'
                state['packed'] = True
            elif value == 0x20:
                state['packed'] = False
        elif state['packed'] and port == 0xa8:
            state['index'] = value
        elif state['packed'] and port in (0xaa, 0xac, 0xae):
            state['palette'][state['index'], port] = value

    def input_port(cpu, port, size, data):
        assert port == 0xa0
        state['polls'] += 1
        return 32 if state['polls'] % 2 == 0 else 0

    def interrupt(cpu, number, data):
        ax = cpu.reg_read(UC_X86_REG_AX)
        ah = ax >> 8
        if number == 0x1d:
            assert hires and ah in (0, 0x11, 0x12, 0x13)
            state['bios'].append(0x100 + ah)
            work = cpu.reg_read(UC_X86_REG_DS) * 16
            assert BASE + 256 <= work and work + 896 < BASE + sym[8]
            if ah == 0:
                callback, segment = struct.unpack('<HH', cpu.mem_read(work+256, 4))
                assert segment == BASE >> 4
                assert cpu.mem_read(BASE + callback, 1) == b'\xcb'
                state['ucw'] = work
            else:
                assert state['ucw'] == work
            cpu.reg_write(UC_X86_REG_AX, 0x0500 if ah == bios_failure else 0)
        elif number == 0x18:
            state['bios'].append(ah)
            assert ah in (0x41, 0x42, 0x0d, 0x40, 0x0c)
            if hires:
                assert ah in (0x0d, 0x0c), 'normal graphics BIOS on a high-resolution machine'
        else:
            assert number == 0x21
            if ah == 0x4c:
                state['exit'] = ax & 255
                cpu.emu_stop()
            elif ah == 6:
                cpu.reg_write(UC_X86_REG_EFLAGS, cpu.reg_read(UC_X86_REG_EFLAGS) & ~64)
                cpu.reg_write(UC_X86_REG_AX, 27)
            elif ah == 0x2c:
                cpu.reg_write(UC_X86_REG_CX, 0)
                cpu.reg_write(UC_X86_REG_DX, 0)
            else:
                assert ah == 9

    def start_frame(cpu, address, size, data):
        cpu.mem_write(BASE + sym[1] - 2, struct.pack('<H', angle))

    def check_frame(cpu, address, size, data):
        state['frames'] += 1
        if state['packed']:
            a, b = struct.unpack('<hh', cpu.mem_read(BASE + sym[1], 4))
            target = bytearray()
            for y in range(100):
                line = bytearray()
                for x in range(160):
                    tx = ((8192 + (x-80)*a - (y-50)*b) >> 8) & 63
                    ty = ((8192 + (x-80)*b + (y-50)*a) >> 8) & 63
                    colour = tx//8 | ((ty//8) << 3) | ((((tx+ty)//4) & 3) << 6)
                    line.extend([colour] * 4)
                target.extend(line * 4)
            assert packed[:256000] == target, 'packed pixel mismatch'
            assert packed[256000:] == b'\xa5' * (524288-256000)
            assert state['banks'] == set(range(8))
            for i in range(256):
                assert state['palette'][i, 0xae] == round((i & 7)*255/7)
                assert state['palette'][i, 0xac] == round(((i >> 3) & 7)*255/7)
                assert state['palette'][i, 0xaa] == (i >> 6)*85
            pixels = bytes(target)
        elif hires:
            want = expected(angle)
            for p in range(4):
                target = bytearray(131072)
                if p < 3:
                    for y in range(400):
                        for x in range(640):
                            if want[y*640+x] & (1 << p):
                                target[(y+175)*140 + (x+240)//8] |= 128 >> ((x+240) & 7)
                assert planes[0][p] == target, ('hires plane mismatch', p)
            pixels = want
        else:
            pixels = decode(planes[state['draw']])
            assert pixels == expected(angle)
            if grcg:
                assert planes[state['draw']][3][:32000] == bytes(32000)
        state['hash'] = hashlib.sha256(pixels).hexdigest()

    u.hook_add(UC_HOOK_MEM_WRITE, write)
    u.hook_add(UC_HOOK_INTR, interrupt)
    u.hook_add(UC_HOOK_INSN, output, None, 1, 0, UC_X86_INS_OUT)
    u.hook_add(UC_HOOK_INSN, input_port, None, 1, 0, UC_X86_INS_IN)
    u.hook_add(UC_HOOK_CODE, start_frame, begin=BASE+sym[0], end=BASE+sym[0])
    u.hook_add(UC_HOOK_CODE, check_frame, begin=BASE+vid[9], end=BASE+vid[9])
    u.emu_start(BASE+256, 0xfffff, count=6000000)
    rejected = '/256' in args and kind != 'pegc'
    if bios_failure is not None:
        assert state['exit'] == 1 and state['frames'] == 0
        if bios_failure == 0:
            assert state['bios'] == [0x100] and not state['ports']
        else:
            assert state['bios'][-3:] == [0x112, 0x113, 0x0c]
        return dict(kind=kind, bios_failure=bios_failure, frames=0)
    assert state['exit'] == (1 if rejected else 0), (kind, args, angle, state['exit'], state['frames'])
    if rejected:
        assert not state['bios'] and not state['ports'] and state['frames'] == 0
    else:
        assert state['frames'] == 1
        if hires:
            assert state['bios'] == [0x100, 0x0d, 0x111, 0x112, 0x113, 0x0c]
        else:
            assert state['bios'][-2:] == [0x41, 0x0c]
        assert state['mode'] == 0 and state['draw'] == 0 and not state['packed']
    return dict(kind=kind, args=args, angle=angle, frames=state['frames'], hash=state.get('hash'))


if __name__ == '__main__':
    results = {}
    cases = [(k, ' /M', a) for k in ('plain', 'grcg', 'egc', 'pegc', 'hires') for a in (0, 64, 160)]
    cases += [('pegc', ' /256 /M', a) for a in (0, 64, 160)]
    cases += [(k, ' /256 /M', 0) for k in ('plain', 'grcg', 'egc', 'hires')]
    cases += [('pegc', ' /256 /8 /M', 0), ('hires', ' /S /M', 0)]
    cases += [('hires', ' /M', 0, f) for f in (0, 0x11)]
    for name in ('ROTO.com', 'ROTOASW.com'):
        binary = (ROOT / name).read_bytes()
        results[name] = [run(binary, *case) for case in cases]
        print(f'PASS {name}: {len(cases)} video cases', flush=True)
    assert results['ROTO.com'] == results['ROTOASW.com'], 'ASW/NASM behavior differs'
    (ROOT / 'build/video-verification.json').write_text(json.dumps(results, indent=2) + '\n')
