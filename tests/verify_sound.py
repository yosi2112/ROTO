"""Run the delivered 8086 sound driver against explicit 26K/86 IO models."""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import os

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/python'))
sys.path.insert(0, str(ROOT / 'src'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INSN, UC_HOOK_INTR, UC_HOOK_MEM_WRITE
from unicorn.x86_const import *
from make_music import score, pcm, KEYS

BINARY = (ROOT / os.environ.get('ROTO_BINARY', 'ROTO.com')).read_bytes()
BASE = 0x10000
NAMES = ('sound_init sound_service sound_stop sound_tick sound_type fm_base '
         'music_row music_score pcm_table last_time time_debt sound_muted '
         'preview_steps sound_done fm_write probe_opn').split()
SYM = dict(zip(NAMES, struct.unpack_from('<16H', BINARY, BINARY.index(b'ROTO98AUD')+9)))
ROWS = score()


class Board:
    def __init__(self, kind='26', base=0x188, stuck=False, false_response=False):
        self.kind, self.base, self.stuck = kind, base, stuck
        self.present = kind in ('26', '86', 'wss')
        self.false_response = false_response
        self.address = 0
        self.reg = bytearray(256)
        self.reg[0], self.reg[7] = 0x37, 0x80
        self.writes, self.pcm_hits, self.keyons = [], [], []
        self.fifo = bytearray()
        self.control, self.dac, self.mute = 0, 0x32, 0xa1
        self.full = False
        self.clock = 0
        self.dos_times = 0

    def read(self, port):
        if port == 0x5f: return 0
        if port == 0xa460:
            if self.kind in ('86', 'false86'): return 0x40 if self.base == 0x188 else 0x50
            return 0x60 if self.kind == 'wss' else 0xff
        if port in (0x88, 0x188, 0x288):
            if port != self.base or not self.present: return 0xff
            return 0x80 if self.stuck else 0
        if port in (0x8a, 0x18a, 0x28a):
            assert port == self.base+2 and self.present
            return 0 if self.false_response else self.reg[self.address]
        assert self.kind == '86', ('non-86 PCM read', hex(port))
        if port == 0xa66e: return self.mute
        if port == 0xa466: return 0x80 if self.full else 0x40 if not self.fifo else 0
        raise AssertionError(('unmodeled input', hex(port)))

    def write(self, port, value):
        self.writes.append((port, value))
        if port in (0x88, 0x188, 0x288):
            assert port == self.base and self.present
            self.address = value
            return
        if port in (0x8a, 0x18a, 0x28a):
            assert port == self.base+2 and self.present
            self.reg[self.address] = value
            if self.address == 0x28 and value & 0xf0:
                self.keyons.append(value & 3)
            return
        assert self.kind == '86', ('non-86 PCM write', hex(port))
        if port == 0xa468:
            assert value & 0x60 == 0, 'PCM IRQ or recording enabled'
            if (value ^ self.control) & 8: self.fifo.clear()
            self.control = value
            if value & 0x80:
                assert value == 0x84 and self.dac == 0x70
                assert len(self.fifo) == 1920 and self.fifo[-2:] == b'\0\0'
                payload = bytes(self.fifo)
                assert payload in [pcm(i) for i in range(5)]
                self.pcm_hits.append(hashlib.sha256(payload).hexdigest())
        elif port == 0xa46a:
            assert not self.control & 0x20
            self.dac = value
        elif port == 0xa46c:
            assert len(self.fifo) < 32768
            self.fifo.append(value)
        elif port == 0xa466: assert value == 0xa0
        elif port == 0xa66e: self.mute = value
        else: raise AssertionError(('unmodeled output', hex(port)))


class Machine:
    def __init__(self, board):
        self.board = board
        self.uc = u = Uc(UC_ARCH_X86, UC_MODE_16)
        u.mem_map(0, 0x100000)
        u.mem_write(BASE+256, BINARY)
        for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_SS, UC_X86_REG_ES):
            u.reg_write(reg, BASE >> 4)
        u.reg_write(UC_X86_REG_EFLAGS, 0x202)
        u.hook_add(UC_HOOK_INSN, lambda u,p,s,d: board.read(p), None, 1, 0, UC_X86_INS_IN)
        u.hook_add(UC_HOOK_INSN, lambda u,p,s,v,d: board.write(p,v), None, 1, 0, UC_X86_INS_OUT)
        u.hook_add(UC_HOOK_INTR, self.interrupt)
        u.hook_add(UC_HOOK_MEM_WRITE, self.write)

    def interrupt(self, u, number, data):
        assert number == 0x21 and u.reg_read(UC_X86_REG_AX) >> 8 == 0x2c
        self.board.dos_times += 1
        seconds, fraction = divmod(self.board.clock % 6000, 100)
        u.reg_write(UC_X86_REG_CX, 0)
        u.reg_write(UC_X86_REG_DX, (seconds << 8) | fraction)

    def write(self, u, access, address, size, value, data):
        assert BASE+256 <= address and address+size <= BASE+256+len(BINARY)

    def get(self, name, size=2):
        return int.from_bytes(self.uc.mem_read(BASE+SYM[name], size), 'little')

    def put(self, name, value, size=2):
        self.uc.mem_write(BASE+SYM[name], value.to_bytes(size, 'little'))

    def call(self, name, limit=1000000):
        sp = 256+len(BINARY)-2
        self.uc.reg_write(UC_X86_REG_SP, sp)
        self.uc.mem_write(BASE+sp, b'\x80\x00')
        self.uc.emu_start(BASE+SYM[name], BASE+0x80, count=limit)
        assert self.uc.reg_read(UC_X86_REG_IP) == 0x80, ('hung', name)


def check_notes(board, row, previous_bass):
    for channel in range(3):
        note = row[channel] if row[channel] != 255 else previous_bass
        raw = board.reg[0xa0+channel] | board.reg[0xa4+channel] << 8
        block, fnum = (raw >> 11) & 7, raw & 2047
        hz = fnum * 3993600 * 2**block / (144*2**20)
        wanted = 440*2**((note-69)/12)
        assert abs(1200*math.log2(hz/wanted)) < 2, (channel, note, hz, wanted)
    for channel in range(3):
        period = board.reg[channel*2] | board.reg[channel*2+1] << 8
        hz = 1996800 / (16*period)
        wanted = 440*2**((row[3+channel]-69)/12)
        assert abs(1200*math.log2(hz/wanted)) < 20, (channel, hz, wanted)


def main():
    results = {}
    for kind, base, result in [('none',0x188,0), ('26',0x188,1), ('26',0x288,1), ('26',0x88,1),
                                ('86',0x188,2), ('86',0x288,2), ('wss',0x188,1),
                                ('false86',0x188,0)]:
        board = Board(kind, base)
        machine = Machine(board)
        machine.call('sound_init')
        assert machine.get('sound_type', 1) == result
        if result: assert machine.get('fm_base') == base
        machine.call('sound_stop')
        if result:
            assert board.reg[8:11] == b'\0\0\0'
            assert board.reg[7] == 0xbf and board.reg[0x27] == 0x30
            assert board.reg[0x28] == 2
        if result == 2:
            assert not board.control & 0x80 and not board.fifo and board.mute == 0xa1
            assert len(board.pcm_hits) == 1
        results[f'{kind}_{base:x}'] = 'passed'

    for kw in ({'stuck':True}, {'false_response':True}):
        b = Board('26', **kw)
        m = Machine(b)
        m.call('sound_init')
        assert m.get('sound_type', 1) == 0
    b = Board('26')
    m = Machine(b)
    m.uc.reg_write(UC_X86_REG_DX, b.base)
    m.call('probe_opn')
    assert b.reg[0] == 0x37 and not m.uc.reg_read(UC_X86_REG_EFLAGS) & 1
    results['probe_restore_timeout_bad_echo'] = 'passed'

    b = Board('86')
    m = Machine(b)
    m.put('sound_muted', 1, 1)
    m.call('sound_init')
    m.call('sound_stop')
    assert not b.writes and m.get('sound_type', 1) == 0
    results['mute_no_io'] = 'passed'

    b = Board('26')
    m = Machine(b)
    m.call('sound_init')
    previous_bass = ROWS[0][1]
    for i, row in enumerate(ROWS):
        if i: m.call('sound_tick')
        if row[1] != 255: previous_bass = row[1]
        check_notes(b, row, previous_bass)
        for voice in (0,2,3,4,5):
            assert row[voice] == ROWS[i % 64][voice] + i//64
    assert len(ROWS) == 768 and len(KEYS) == 12 and m.get('music_row') == 0
    m.call('sound_tick')
    check_notes(b, ROWS[0], ROWS[0][1])
    assert m.get('music_row') == 1
    results['twelve_keys_768_steps_and_loop'] = 'passed'

    b = Board('86')
    m = Machine(b)
    m.call('sound_init')
    for _ in range(63): m.call('sound_tick')
    assert len(b.pcm_hits) == 64 and len(set(b.pcm_hits)) == 5
    b.full = True
    m.call('sound_tick')
    assert len(b.pcm_hits) == 64 and not b.control & 0x80
    results['all_five_pcm_hits_and_full_fifo'] = 'passed'

    b = Board('26')
    b.clock = 5995
    m = Machine(b)
    m.call('sound_init')
    for clock, wanted in [(5999,1),(5,2),(5,2),(15,3),(1015,7)]:
        b.clock = clock
        sentinel = {r:0x4321+i for i,r in enumerate((UC_X86_REG_AX,UC_X86_REG_BX,
                    UC_X86_REG_CX,UC_X86_REG_DX,UC_X86_REG_SI,UC_X86_REG_DI,UC_X86_REG_BP))}
        for r,v in sentinel.items(): m.uc.reg_write(r,v)
        m.call('sound_service')
        assert all(m.uc.reg_read(r)==v for r,v in sentinel.items())
        assert m.get('music_row') == wanted
    results['clock_wrap_registers_and_catchup_bound'] = 'passed'

    b = Board('26')
    m = Machine(b)
    m.put('preview_steps', 128)
    m.call('sound_init')
    for _ in range(127):
        b.clock += 10
        m.call('sound_service')
    assert m.get('sound_done', 1) == 1 and m.get('music_row') == 128
    m.call('sound_tick')
    assert m.get('music_row') == 128
    results['preview_completion'] = 'passed'
    report = dict(sha256=hashlib.sha256(BINARY).hexdigest(), bytes=len(BINARY), tests=results)
    report_name = 'audio-verification-asw.json' if os.environ.get('ROTO_BINARY') == 'ROTOASW.com' else 'audio-verification.json'
    (ROOT/'build'/report_name).write_text(json.dumps(report, indent=2)+'\n')
    for name in results: print('PASS',name)


if __name__ == '__main__': main()
