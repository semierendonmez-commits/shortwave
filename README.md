# shortwave

a shortwave radio simulator for [norns](https://monome.org/docs/norns/). tune through a frequency band and discover 6 generative stations. between stations: static, crackle, heterodyne whistles. every station is a different algorithmic world.

---

## the experience

turn the dial. you hear static. crackle. a distant whistle that shifts as you tune. then a station fades in — maybe a ghostly drone, maybe morse code, maybe fragmented melodies from somewhere far away. the stations drift slowly — the ionosphere is unstable. what was at 28 MHz a minute ago might be at 29.5 now.

```
0 MHz ─────────────────────────────────────── 100 MHz
   │         │         │         │       │        │
  DRONE   NUMBERS   PULSE    VOICE   MORSE    MUSIC
 (15)     (28)      (42)     (58)    (72)     (88)
               ↕ drift               ↕ drift
                    ⟨ static ⟩
                    ⟨ crackle ⟩
                  ⟨ heterodyne ⟩
```

## stations

**DRONE (15 MHz)** — slowly evolving filtered noise. two bandpass filters sweep independently through low frequencies. an ambient transmission from nowhere.

**NUMBERS (28 MHz)** — sine tone beeps in repeating patterns. stepped frequencies, mechanical rhythm. inspired by real numbers stations — coded broadcasts that no one claims to send.

**PULSE (42 MHz)** — rhythmic impulses like a radar ping or time signal. variable rate, resonant filtered. precise and cold.

**VOICE (58 MHz)** — formant synthesis from noise. vowel-like textures that morph slowly between shapes. ghostly speech from a language you almost recognize.

**MORSE (72 MHz)** — keyed sine wave in pseudo-random dot/dash patterns. the tone frequency shifts occasionally. an automated message on repeat.

**MUSIC (88 MHz)** — detuned harmonic series playing fragmented melodies. like catching a distant FM broadcast through heavy interference. notes from a concert happening on the other side of the world.

## atmosphere

between stations, you hear:

- **static**: broadband noise that gets louder the further you are from any station
- **crackle**: random atmospheric pops (Dust), like electrical storms
- **heterodyne**: the classic shortwave whistle — a beat frequency between the tuner and the nearest station. gets higher pitched as you move away from a station.

## controls

| control | function |
|---------|----------|
| **E1** | fine tune (0.05 MHz steps) |
| **E2** | coarse tune (sweep the dial) |
| **E3** | bandwidth / static / station vol (per page) |
| **K1 hold** | show guide |
| **K2** | auto-scan on/off |
| **K3** | bookmark frequency |
| **K1+K3** | cycle pages |

## pages

**DIAL** — main tuning interface. large frequency display, dial bar with station markers, signal strength meter (12 bars), tuned station name. bookmark dots below the dial. scanning indicator when auto-scan is active.

**ATMO** — atmosphere controls. noise visualization (random dots scaled to static level). displays static, crackle, interference, drift, quality values.

**STATIONS** — all 6 stations listed with frequency, name, volume bar, and "tuned" indicator dot. E3 adjusts the nearest station's volume.

## parameters

**tuner**: 0-100 MHz. the main dial.

**bandwidth**: how wide the reception window is. narrow = precise tuning required. wide = hear multiple stations blended.

**quality**: signal degradation. 1.0 = clean, 0.0 = noisy and distorted even when tuned.

**ionosphere (drift)**: stations slowly wander in frequency. drift speed and amount control the instability. high drift = stations are hard to find, they keep moving.

**per-station volume**: each station has independent volume control. turn off stations you don't want, or create your own mix.

## auto-scan

press K2 to start scanning. the tuner sweeps across the band automatically. as it passes stations, they fade in and out. press K2 again to stop at the current position.

## bookmarks

press K3 to bookmark the current frequency. bookmarks appear as small marks below the dial. up to 8 bookmarks stored.

## requirements

- norns (shield, standard, or fates)
- no additional libraries or sc3-plugins

## install

```
;install https://github.com/semierendonmez-commits/shortwave
```

## architecture

```
shortwave/
  shortwave.lua              main script, params, UI (3 pages + guide)
  lib/
    Engine_Shortwave.sc      SC engine (single SynthDef, 6 stations + atmosphere)
```

all 6 stations run simultaneously in a single SynthDef. gaussian proximity envelopes control which stations are audible based on tuner position. `LFNoise1` drives station frequency drift. the heterodyne whistle is a sine oscillator at the beat frequency between tuner and nearest station.

## license

MIT
