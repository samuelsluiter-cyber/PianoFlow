#!/usr/bin/env python3
"""Band-MIDI → spielbare Klavierfassung.
Linke Hand = Bass-Spur, rechte Hand = Haupt-Gitarre (max. 3 Töne pro Anschlag).
Aufruf: band2piano.py <eingabe.mid> <ausgabe.mid> [rechts_spur] [links_spur]
"""
import sys
import mido

if len(sys.argv) < 3:
    sys.exit('Aufruf: band2piano.py <band.mid> <klavier.mid> [rechte-spur] [bass-spur]')
src, dst = sys.argv[1], sys.argv[2]
mid = mido.MidiFile(src)

def notes_of(track):
    """(start_tick, end_tick, pitch, velocity, channel) einer Spur"""
    t, open_, out = 0, {}, []
    for m in track:
        t += m.time
        if m.type == 'note_on' and m.velocity > 0:
            open_[(m.channel, m.note)] = (t, m.velocity)
        elif m.type in ('note_off', 'note_on'):
            k = (m.channel, m.note)
            if k in open_:
                s, v = open_.pop(k)
                out.append((s, t, m.note, v, m.channel))
    return out

tracks = [(i, tr.name, notes_of(tr)) for i, tr in enumerate(mid.tracks)]
tracks = [x for x in tracks if x[2] and all(n[4] != 9 for n in x[2])]   # Schlagzeug raus

def pick(name_hint, fallback):
    for i, name, ns in tracks:
        if name_hint.lower() in name.lower():
            return ns
    return fallback

bass = pick(sys.argv[4] if len(sys.argv) > 4 else 'bass', [])
right = pick(sys.argv[3] if len(sys.argv) > 3 else 'gtr.1', max((x[2] for x in tracks), key=len, default=[]))  # J105: nur Schlagzeug -> kein Absturz

def fold(p, lo, hi):
    while p < lo: p += 12
    while p > hi: p -= 12
    return p

# Intro/Lücken: solange die Hauptspur schweigt, die anderen Instrumente übernehmen
first = min((n[0] for n in right), default=0)
others = [n for i, name, ns in tracks if ns is not right and ns is not bass for n in ns]
right = right + [n for n in others if n[0] < first]

# Rechte Hand: pro Anschlag die 3 höchsten Töne, in C4–A5 gefaltet
by_onset = {}
for s, e, p, v, ch in right:
    by_onset.setdefault(s, []).append((s, e, p, v))
rh = []
for s, group in by_onset.items():
    seen = set()
    for (s_, e, p, v) in sorted(group, key=lambda g: -g[2]):
        q = fold(p, 60, 81)
        if q in seen:
            continue
        seen.add(q)
        rh.append((s_, e, q, v))
        if len(seen) == 3:
            break

# Linke Hand: Bass einstimmig, in E1–H3 → für Klavier E2–C4 gefaltet
lh = []
for s, e, p, v, ch in sorted(bass):
    q = fold(p, 40, 59)
    if lh and lh[-1][0] == s:
        continue
    lh.append((s, e, q, v))

out = mido.MidiFile(ticks_per_beat=mid.ticks_per_beat)
meta = mido.MidiTrack()
t = 0
events = []
for m in mido.merge_tracks(mid.tracks):
    t += m.time
    if m.is_meta and m.type in ('set_tempo', 'time_signature', 'key_signature'):
        events.append((t, m.copy(time=0)))
last = 0
for tt, m in events:
    meta.append(m.copy(time=tt - last))
    last = tt
meta.append(mido.MetaMessage('track_name', name='Tempo', time=0))
out.tracks.append(meta)

def make(notes, ch, name):
    tr = mido.MidiTrack()
    tr.append(mido.MetaMessage('track_name', name=name, time=0))
    tr.append(mido.Message('program_change', program=0, channel=ch, time=0))
    ev = []
    for s, e, p, v in notes:
        ev.append((s, 1, mido.Message('note_on', note=p, velocity=max(40, min(110, v)), channel=ch)))
        ev.append((max(e, s + 1), 0, mido.Message('note_off', note=p, velocity=0, channel=ch)))
    ev.sort(key=lambda x: (x[0], x[1]))
    last = 0
    for tt, _, m in ev:
        tr.append(m.copy(time=tt - last))
        last = tt
    return tr

out.tracks.append(make(rh, 0, 'Rechte Hand (Gitarre)'))
out.tracks.append(make(lh, 1, 'Linke Hand (Bass)'))
out.save(dst)
print(f"Klavierfassung: rechts {len(rh)} Noten, links {len(lh)} Noten → {dst}")
