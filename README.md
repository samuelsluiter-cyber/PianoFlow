# PianoFlow

Klavier lernen am Mac – mit MIDI-Keyboard, Mikrofon oder Computertastatur.
Native SwiftUI-App (macOS 14+), ohne externe Abhängigkeiten.

## Funktionen

- **Lektionen** Takt für Takt: Loop, Warte-Modus („die App wartet auf deine Taste“), Tempo 50/75/100 %
- **Drei Ansichten**: Wasserfall, Laufband-Noten oder beides – plus **„Ganzes Blatt“** mit dem kompletten
  Notenblatt, Zoom (Pinch, ⌘−/⌘+) und automatischem Mitlaufen; Takt anklicken = üben, über Takte ziehen = Bereich
- **Echter Notensatz** aus MIDI: Rhythmus, Balken, Pausen, Haltebögen, Punktierungen, Tonart- und Versetzungszeichen,
  Notennamen im Notenkopf (Kindernoten), Akkordsymbole und Stufen
- **Handerkennung**: Spurnamen, Spuren nach Tonlage, sonst taktweise Trennung nach Griffweite
  (keine Hand muss mehr als ~eine Oktave greifen)
- **Songs entdecken**: Katalog mit hunderten kostenlosen Klavierstücken aus dem
  [Mutopia Project](https://www.mutopiaproject.org) (gemeinfrei / Creative Commons), nach Schwierigkeit sortiert
- Trainer für Notenlesen, Gehör, Tonleitern; Statistik, Streaks, KI-Lehrer

## Bauen

```bash
./build_app.sh          # baut Release und installiert nach ~/Applications/PianoFlow.app
```

Entwicklungswerkzeuge:

```bash
swift build
.build/debug/PianoFlow --parse song.mid              # Kennzahlen + Handtrennungs-Check
.build/debug/PianoFlow --render song.mid out.png 10  # Notenblatt offscreen als PNG
python3 tools/build_catalog.py                       # Song-Katalog neu erzeugen (catalog/songs.json)
```

## Katalog & Lizenzen

`catalog/songs.json` enthält nur Metadaten und Links; die MIDI-Dateien werden erst beim Klick auf
„Holen & üben“ direkt von mutopiaproject.org geladen. Jedes Stück trägt seine Lizenz
(Public Domain, CC BY oder CC BY-SA) – bei CC-Stücken bitte die Namensnennung beachten.
