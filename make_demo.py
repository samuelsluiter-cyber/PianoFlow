#!/usr/bin/env python3
"""Erzeugt den Demo-Song 'Für Elise' (Anfang, gemeinfrei) als 2-Hand-MIDI."""
import struct, sys

TPQ = 480
S = 120  # Sechzehntel in Ticks

# (start in 16teln, dauer in 16teln, pitch)
RH = [(0,1,76),(1,1,75),
      (2,1,76),(3,1,75),(4,1,76),(5,1,71),(6,1,74),(7,1,72),
      (8,2,69),(11,1,60),(12,1,64),(13,1,69),
      (14,2,71),(17,1,64),(18,1,68),(19,1,71),
      (20,2,72),(23,1,64),(24,1,76),(25,1,75),
      (26,1,76),(27,1,75),(28,1,76),(29,1,71),(30,1,74),(31,1,72),
      (32,2,69),(35,1,60),(36,1,64),(37,1,69),
      (38,2,71),(41,1,64),(42,1,72),(43,1,71),
      (44,4,69)]
LH = [(8,1,45),(9,1,52),(10,1,57),
      (14,1,40),(15,1,52),(16,1,56),
      (20,1,45),(21,1,52),(22,1,57),
      (32,1,45),(33,1,52),(34,1,57),
      (38,1,40),(39,1,52),(40,1,56),
      (44,1,45),(45,1,52),(46,3,57)]

def vlq(n):
    out = [n & 0x7F]; n >>= 7
    while n: out.insert(0, (n & 0x7F) | 0x80); n >>= 7
    return bytes(out)

def track(events):
    data = b""; last = 0
    for t, ev in sorted(events, key=lambda e: (e[0], e[1][0] & 0xF0 == 0x90)):
        data += vlq(t - last) + ev; last = t
    data += b"\x00\xFF\x2F\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + data

def notes(lst, ch, offset=S*2):
    ev = []
    for s, d, p in lst:
        t0 = s * S + offset
        ev.append((t0, bytes([0x90 | ch, p, 80])))
        ev.append((t0 + d * S - 10, bytes([0x80 | ch, p, 0])))
    return ev

tempo = 60_000_000 // 66  # Viertel = 66 BPM
meta = [(0, b"\xFF\x51\x03" + tempo.to_bytes(3, "big")), (0, b"\xFF\x58\x04\x03\x03\x18\x08")]
out = b"MThd" + struct.pack(">IHHH", 6, 1, 3, TPQ) + track(meta) + track(notes(RH, 0)) + track(notes(LH, 1))
open(sys.argv[1], "wb").write(out)
print("Demo geschrieben:", sys.argv[1])
