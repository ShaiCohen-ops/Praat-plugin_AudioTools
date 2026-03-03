"""
eventgen_pbind_ui.py — SuperCollider-style Pbind Event Generator
Part of Praat AudioTools plugin

Usage:
    python3 eventgen_pbind_ui.py analysis.csv pbind.txt out_pitch.csv out_intensity.csv
            --baseHz 220 --seed 42 [--trace trace.csv]

Constraints: stdlib only (csv, re, math, random, argparse, sys, pathlib)

─────────────────────────────────────────────────────────────
GRAMMAR SUPPORTED
─────────────────────────────────────────────────────────────
Pbind(key=<pattern>, ...)

Pitch keys (use exactly one):
  degree=<pattern>    → major-scale index, root = baseHz
                        non-integer degrees are rounded
                        negative degrees map to lower octaves
  midinote=<pattern>  → MIDI note number (60 = middle C)
  freq=<pattern>      → raw Hz value, bypasses all scale logic

Other keys:
  dur=<pattern>       → event spacing in seconds
  amp=<pattern>       → linear amplitude [0..1]
  legato=<pattern>    → tier segment = dur * legato  (default 1.0)
                        values < 1 give staccato phrasing
                        values > 1 give legato overlap

Patterns:
  Pseq([0,1,2,...], inf|N)           cycle list; finite N stops early
  Prand([0,1,2,...], inf|N)          random pick without order
  Pwrand([v,...], [w,...], inf|N)    weighted random pick (weights normalised)
  Pwhite(lo, hi, inf|N)              uniform random float
  Pexprand(lo, hi, inf|N)            exponentially distributed random float
  Pstutter(<pattern>, <count>)       repeat each value of inner pattern N times
  <number>                           constant

Stopping rule:
  Stops when (a) current time >= duration_seconds OR
             (b) any finite pattern exhausts — whichever comes first.

─────────────────────────────────────────────────────────────
EXAMPLES
─────────────────────────────────────────────────────────────
Degree / scale:
  Pbind(degree=Pseq([0,1,2,4,7],inf), dur=0.25, amp=Pwhite(0.1,0.5,inf))

MIDI note:
  Pbind(midinote=Pseq([60,62,64,65,67],inf), dur=0.2, amp=0.4)

Raw frequency:
  Pbind(freq=Pwhite(200,800,inf), dur=0.1, amp=0.3)

Legato phrasing:
  Pbind(degree=Pseq([0,2,4,7],inf), dur=0.3, amp=0.5, legato=0.6)

Weighted random:
  Pbind(degree=Pwrand([0,4,7],[0.5,0.3,0.2],inf), dur=0.2, amp=0.4)

Stutter:
  Pbind(degree=Pstutter(Pseq([0,4,7],inf),3), dur=0.1, amp=0.4)

Exponential random rhythm:
  Pbind(degree=Pseq([0,2,4],inf), dur=Pexprand(0.05,0.5,inf), amp=0.4)
"""

import csv
import re
import math
import random
import argparse
import sys
from pathlib import Path

EXAMPLE_PBIND = "Pbind(degree=Pseq([0,1,2,4,7],inf), dur=0.25, amp=Pwhite(0.1,0.5,inf))"

# ═══════════════════════════════════════════════════════════════════════════
# Argument parsing
# ═══════════════════════════════════════════════════════════════════════════

def parse_args():
    p = argparse.ArgumentParser(
        description="Pbind event generator for Praat",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"Default example:\n  {EXAMPLE_PBIND}"
    )
    p.add_argument("analysis_csv",      help="CSV with duration_seconds,sampling_rate")
    p.add_argument("pbind_txt",         help="Text file containing one Pbind(...) line")
    p.add_argument("out_pitch_csv",     help="Output pitch tier CSV (time,hz)")
    p.add_argument("out_intensity_csv", help="Output intensity tier CSV (time,db)")
    p.add_argument("--baseHz", type=float, default=220.0)
    p.add_argument("--seed",   type=int,   default=42)
    p.add_argument("--trace",  default=None,
                   help="Optional: write event trace CSV (t,dur,degree,amp,hz,db)")
    return p.parse_args()


# ═══════════════════════════════════════════════════════════════════════════
# Read analysis CSV
# ═══════════════════════════════════════════════════════════════════════════

def read_analysis(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            return float(row["duration_seconds"]), float(row.get("sampling_rate", 44100))
    raise ValueError("analysis.csv is empty or malformed")


# ═══════════════════════════════════════════════════════════════════════════
# Parser
# ═══════════════════════════════════════════════════════════════════════════

class ParseError(Exception):
    pass


def _s(s):
    return s.strip()


def parse_number(s):
    s = _s(s)
    try:
        return float(s)
    except ValueError:
        raise ParseError(f"Expected a number, got: {s!r}\nExample: {EXAMPLE_PBIND}")


def parse_int_list(s):
    s = _s(s)
    if not (s.startswith("[") and s.endswith("]")):
        raise ParseError(f"Expected [...], got: {s!r}")
    inner = s[1:-1].strip()
    if not inner:
        return []
    result = []
    for part in inner.split(","):
        part = part.strip()
        try:
            result.append(int(part))
        except ValueError:
            try:
                result.append(float(part))
            except ValueError:
                raise ParseError(f"Non-numeric element in list: {part!r}")
    return result


def parse_float_list(s):
    """Like parse_int_list but always returns floats (used for Pwrand weights)."""
    items = parse_int_list(s)
    return [float(x) for x in items]


def parse_repeat(s):
    s = _s(s)
    if s == "inf":
        return float("inf")
    try:
        return int(s)
    except ValueError:
        raise ParseError(f"Expected 'inf' or integer, got: {s!r}")


def split_top_level_commas(s):
    """Split on commas not inside brackets or parentheses."""
    parts, depth, start = [], 0, 0
    for i, ch in enumerate(s):
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(s[start:i])
            start = i + 1
    parts.append(s[start:])
    return parts


def parse_pattern(s):
    """
    Parse a pattern expression. Returns a descriptor dict with 'type' key.
    Supported types: const, pseq, prand, pwrand, pwhite, pexprand, pstutter
    """
    s = _s(s)

    # ── Pseq ──────────────────────────────────────────────────────────────
    m = re.fullmatch(r"Pseq\s*\(\s*(\[[^\]]*\])\s*,\s*([^)]+)\s*\)", s)
    if m:
        return {"type": "pseq", "list": parse_int_list(m.group(1)),
                "repeats": parse_repeat(_s(m.group(2)))}

    # ── Prand ─────────────────────────────────────────────────────────────
    m = re.fullmatch(r"Prand\s*\(\s*(\[[^\]]*\])\s*,\s*([^)]+)\s*\)", s)
    if m:
        return {"type": "prand", "list": parse_int_list(m.group(1)),
                "count": parse_repeat(_s(m.group(2)))}

    # ── Pwrand ────────────────────────────────────────────────────────────
    # Pwrand([vals], [weights], count)
    m = re.fullmatch(
        r"Pwrand\s*\(\s*(\[[^\]]*\])\s*,\s*(\[[^\]]*\])\s*,\s*([^)]+)\s*\)", s)
    if m:
        vals    = parse_int_list(m.group(1))
        weights = parse_float_list(m.group(2))
        if len(vals) != len(weights):
            raise ParseError(
                f"Pwrand: values and weights must have the same length.\n"
                f"  values={vals}\n  weights={weights}"
            )
        total = sum(weights)
        if total <= 0:
            raise ParseError(f"Pwrand: weights must sum to > 0, got {weights}")
        weights = [w / total for w in weights]   # normalise
        return {"type": "pwrand", "list": vals, "weights": weights,
                "count": parse_repeat(_s(m.group(3)))}

    # ── Pwhite ────────────────────────────────────────────────────────────
    m = re.fullmatch(r"Pwhite\s*\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^)]+)\s*\)", s)
    if m:
        return {"type": "pwhite",
                "lo": parse_number(m.group(1)), "hi": parse_number(m.group(2)),
                "count": parse_repeat(_s(m.group(3)))}

    # ── Pexprand ──────────────────────────────────────────────────────────
    m = re.fullmatch(r"Pexprand\s*\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^)]+)\s*\)", s)
    if m:
        lo = parse_number(m.group(1))
        hi = parse_number(m.group(2))
        if lo <= 0 or hi <= 0:
            raise ParseError(f"Pexprand: lo and hi must be > 0, got ({lo}, {hi})")
        return {"type": "pexprand", "lo": lo, "hi": hi,
                "count": parse_repeat(_s(m.group(3)))}

    # ── Pstutter ──────────────────────────────────────────────────────────
    # Pstutter(<inner_pattern>, <count_int>)
    # We need to split the two top-level arguments manually.
    m = re.fullmatch(r"Pstutter\s*\((.+)\)", s, re.DOTALL)
    if m:
        parts = split_top_level_commas(m.group(1))
        if len(parts) != 2:
            raise ParseError(
                f"Pstutter expects exactly 2 arguments: Pstutter(<pattern>, <count>)\n"
                f"Got: {s!r}"
            )
        inner_pat = parse_pattern(_s(parts[0]))
        count     = int(parse_number(_s(parts[1])))
        if count < 1:
            raise ParseError(f"Pstutter count must be >= 1, got {count}")
        return {"type": "pstutter", "inner": inner_pat, "count": count}

    # ── Numeric constant ──────────────────────────────────────────────────
    try:
        return {"type": "const", "value": parse_number(s)}
    except ParseError:
        pass

    raise ParseError(
        f"Unrecognised pattern expression: {s!r}\n"
        f"Supported: Pseq  Prand  Pwrand  Pwhite  Pexprand  Pstutter  <number>\n"
        f"Example: {EXAMPLE_PBIND}"
    )


def parse_pbind(line):
    """
    Parse Pbind(...). Returns dict of key → pattern descriptor.
    Required: (degree OR midinote OR freq), dur, amp.
    Optional: legato.
    """
    line = _s(line)
    m = re.fullmatch(r"Pbind\s*\((.+)\)", line, re.DOTALL)
    if not m:
        raise ParseError(
            f"Line does not match Pbind(...) form.\n"
            f"Input: {line!r}\nExample: {EXAMPLE_PBIND}"
        )

    result = {}
    for pair in split_top_level_commas(m.group(1)):
        pair = _s(pair)
        if not pair:
            continue
        if "=" not in pair:
            raise ParseError(
                f"Expected 'key=value' pair, got: {pair!r}\n"
                f"Example: {EXAMPLE_PBIND}"
            )
        eq  = pair.index("=")
        key = _s(pair[:eq])
        val = _s(pair[eq + 1:])
        result[key] = parse_pattern(val)

    # Validate pitch key
    pitch_keys = [k for k in ("degree", "midinote", "freq") if k in result]
    if len(pitch_keys) == 0:
        raise ParseError(
            f"Pbind must have one of: degree, midinote, freq\n"
            f"Found keys: {list(result.keys())}\nExample: {EXAMPLE_PBIND}"
        )
    if len(pitch_keys) > 1:
        raise ParseError(
            f"Pbind may only have ONE of: degree, midinote, freq — got {pitch_keys}"
        )

    for required in ("dur", "amp"):
        if required not in result:
            raise ParseError(
                f"Pbind is missing required key: '{required}'\n"
                f"Found keys: {list(result.keys())}\nExample: {EXAMPLE_PBIND}"
            )

    return result


# ═══════════════════════════════════════════════════════════════════════════
# Pattern iterators
# ═══════════════════════════════════════════════════════════════════════════

class PatternExhausted(Exception):
    pass


def make_iterator(pat, rng):
    """
    Returns a callable () -> value.
    Raises PatternExhausted when a finite pattern is done.
    Pstutter wraps another iterator and repeats each value N times.
    """

    if pat["type"] == "const":
        v = pat["value"]
        return lambda: v

    elif pat["type"] == "pseq":
        lst      = pat["list"]
        n        = len(lst)
        max_vals = float("inf") if pat["repeats"] == float("inf") else int(pat["repeats"]) * n
        state    = {"i": 0}
        if n == 0:
            return lambda: (_ for _ in ()).throw(PatternExhausted())
        def pseq():
            if state["i"] >= max_vals:
                raise PatternExhausted
            v = lst[state["i"] % n]
            state["i"] += 1
            return v
        return pseq

    elif pat["type"] == "prand":
        lst   = pat["list"]
        max_n = float("inf") if pat["count"] == float("inf") else int(pat["count"])
        state = {"n": 0}
        def prand():
            if state["n"] >= max_n:
                raise PatternExhausted
            state["n"] += 1
            return rng.choice(lst)
        return prand

    elif pat["type"] == "pwrand":
        lst     = pat["list"]
        weights = pat["weights"]
        max_n   = float("inf") if pat["count"] == float("inf") else int(pat["count"])
        state   = {"n": 0}
        def pwrand():
            if state["n"] >= max_n:
                raise PatternExhausted
            state["n"] += 1
            r = rng.random()
            cumulative = 0.0
            for v, w in zip(lst, weights):
                cumulative += w
                if r <= cumulative:
                    return v
            return lst[-1]   # float rounding safety
        return pwrand

    elif pat["type"] == "pwhite":
        lo    = pat["lo"]
        hi    = pat["hi"]
        max_n = float("inf") if pat["count"] == float("inf") else int(pat["count"])
        state = {"n": 0}
        def pwhite():
            if state["n"] >= max_n:
                raise PatternExhausted
            state["n"] += 1
            return rng.uniform(lo, hi)
        return pwhite

    elif pat["type"] == "pexprand":
        lo    = pat["lo"]
        hi    = pat["hi"]
        log_lo = math.log(lo)
        log_hi = math.log(hi)
        max_n  = float("inf") if pat["count"] == float("inf") else int(pat["count"])
        state  = {"n": 0}
        def pexprand():
            if state["n"] >= max_n:
                raise PatternExhausted
            state["n"] += 1
            return math.exp(rng.uniform(log_lo, log_hi))
        return pexprand

    elif pat["type"] == "pstutter":
        inner_iter = make_iterator(pat["inner"], rng)
        count      = pat["count"]
        state      = {"buf": None, "left": 0}
        def pstutter():
            if state["left"] == 0:
                state["buf"]  = inner_iter()   # may raise PatternExhausted
                state["left"] = count
            state["left"] -= 1
            return state["buf"]
        return pstutter

    else:
        raise ParseError(f"Unknown pattern type: {pat['type']!r}")


# ═══════════════════════════════════════════════════════════════════════════
# Pitch conversion helpers
# ═══════════════════════════════════════════════════════════════════════════

MAJOR_SCALE = [0, 2, 4, 5, 7, 9, 11]


def degree_to_hz(degree, base_hz):
    """Major-scale index → Hz. Rounds to nearest int. Negative = lower octave."""
    d        = int(round(degree))
    octave   = d // 7
    semitone = MAJOR_SCALE[d % 7] + octave * 12
    return base_hz * (2.0 ** (semitone / 12.0))


def midinote_to_hz(midinote):
    """MIDI note number → Hz. 69 = 440 Hz."""
    return 440.0 * (2.0 ** ((midinote - 69) / 12.0))


def amp_to_db(amp):
    return 70.0 + 20.0 * math.log10(max(amp, 1e-6))


# ═══════════════════════════════════════════════════════════════════════════
# Event generation
# ═══════════════════════════════════════════════════════════════════════════

def generate_events(pbind_dict, duration_seconds, base_hz, rng):
    """
    Returns list of dicts: {t, dur, segment_dur, pitch_key, pitch_val, amp, hz, db}
    pitch_key is 'degree', 'midinote', or 'freq'.
    segment_dur = dur * legato (what gets written to the pitch tier).
    """
    # Determine pitch key
    pitch_key = next(k for k in ("degree", "midinote", "freq") if k in pbind_dict)

    pitch_iter  = make_iterator(pbind_dict[pitch_key], rng)
    dur_iter    = make_iterator(pbind_dict["dur"],      rng)
    amp_iter    = make_iterator(pbind_dict["amp"],      rng)
    legato_iter = (make_iterator(pbind_dict["legato"], rng)
                   if "legato" in pbind_dict else None)

    events = []
    t      = 0.0

    while True:
        if t >= duration_seconds:
            break

        try:
            pitch_val = pitch_iter()
            dur       = dur_iter()
            amp       = amp_iter()
            legato    = legato_iter() if legato_iter else 1.0
        except PatternExhausted:
            print("  [stop] A finite pattern was exhausted — stopping early.",
                  file=sys.stderr)
            break

        if dur <= 0:
            print(f"  [stop] dur={dur} <= 0 — stopping.", file=sys.stderr)
            break

        # Pitch → Hz
        if pitch_key == "degree":
            hz = degree_to_hz(pitch_val, base_hz)
        elif pitch_key == "midinote":
            hz = midinote_to_hz(pitch_val)
        else:   # freq
            hz = float(pitch_val)

        hz = max(hz, 1.0)   # floor at 1 Hz — Praat PitchTier minimum

        db           = amp_to_db(amp)
        segment_dur  = dur * max(legato, 0.001)

        events.append({
            "t":           t,
            "dur":         dur,
            "segment_dur": segment_dur,
            "pitch_key":   pitch_key,
            "pitch_val":   pitch_val,
            "amp":         amp,
            "hz":          hz,
            "db":          db,
        })
        t += dur

    return events


# ═══════════════════════════════════════════════════════════════════════════
# Tier point generation
# ═══════════════════════════════════════════════════════════════════════════

EPS = 1e-6


def events_to_tier_points(events, duration_seconds):
    """
    Stepwise tier: each event occupies [t, t + segment_dur - eps].
    segment_dur = dur * legato, so legato < 1 creates gaps (staccato),
    legato > 1 creates overlaps.
    Appends a closing point at exactly duration_seconds to ensure full coverage.
    """
    pitch_pts     = []
    intensity_pts = []

    for ev in events:
        t     = max(0.0, min(ev["t"],                            duration_seconds))
        t_end = max(0.0, min(ev["t"] + ev["segment_dur"] - EPS,  duration_seconds))

        pitch_pts.append((t,     ev["hz"]))
        pitch_pts.append((t_end, ev["hz"]))

        intensity_pts.append((t,     ev["db"]))
        intensity_pts.append((t_end, ev["db"]))

    # Ensure coverage through xmax
    if events:
        last_hz = events[-1]["hz"]
        last_db = events[-1]["db"]
        if pitch_pts and pitch_pts[-1][0] < duration_seconds - EPS:
            pitch_pts.append((duration_seconds, last_hz))
            intensity_pts.append((duration_seconds, last_db))

    return pitch_pts, intensity_pts


# ═══════════════════════════════════════════════════════════════════════════
# CSV writers
# ═══════════════════════════════════════════════════════════════════════════

def write_pitch_csv(path, points):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "hz"])
        for t, hz in points:
            w.writerow([f"{t:.9f}", f"{hz:.6f}"])


def write_intensity_csv(path, points):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "db"])
        for t, db in points:
            w.writerow([f"{t:.9f}", f"{db:.6f}"])


def write_trace_csv(path, events):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t", "dur", "segment_dur", "pitch_key", "pitch_val",
                    "amp", "hz", "db"])
        for ev in events:
            w.writerow([
                f"{ev['t']:.6f}",
                f"{ev['dur']:.6f}",
                f"{ev['segment_dur']:.6f}",
                ev["pitch_key"],
                f"{ev['pitch_val']:.4f}",
                f"{ev['amp']:.6f}",
                f"{ev['hz']:.4f}",
                f"{ev['db']:.4f}",
            ])


# ═══════════════════════════════════════════════════════════════════════════
# Diagnostics helper
# ═══════════════════════════════════════════════════════════════════════════

def describe_pattern(key, pat):
    t = pat["type"]
    if t == "const":
        return f"constant {pat['value']}"
    elif t == "pseq":
        rep    = "inf" if pat["repeats"] == float("inf") else pat["repeats"]
        finite = "" if pat["repeats"] == float("inf") \
                    else f"  [FINITE → stops at {int(pat['repeats']) * len(pat['list'])} values]"
        return f"Pseq({pat['list']}, {rep}){finite}"
    elif t == "prand":
        rep    = "inf" if pat["count"] == float("inf") else pat["count"]
        finite = "" if pat["count"] == float("inf") else f"  [FINITE → stops at {int(pat['count'])} values]"
        return f"Prand({pat['list']}, {rep}){finite}"
    elif t == "pwrand":
        rep    = "inf" if pat["count"] == float("inf") else pat["count"]
        finite = "" if pat["count"] == float("inf") else f"  [FINITE → stops at {int(pat['count'])} values]"
        wfmt   = [f"{w:.3f}" for w in pat["weights"]]
        return f"Pwrand({pat['list']}, [{', '.join(wfmt)}], {rep}){finite}"
    elif t == "pwhite":
        rep    = "inf" if pat["count"] == float("inf") else pat["count"]
        finite = "" if pat["count"] == float("inf") else f"  [FINITE → stops at {int(pat['count'])} values]"
        return f"Pwhite({pat['lo']}, {pat['hi']}, {rep}){finite}"
    elif t == "pexprand":
        rep    = "inf" if pat["count"] == float("inf") else pat["count"]
        finite = "" if pat["count"] == float("inf") else f"  [FINITE → stops at {int(pat['count'])} values]"
        return f"Pexprand({pat['lo']}, {pat['hi']}, {rep}){finite}"
    elif t == "pstutter":
        return f"Pstutter({describe_pattern('inner', pat['inner'])}, {pat['count']})"
    return str(pat)


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    args = parse_args()

    # ---- Read analysis ----
    duration_seconds, sampling_rate = read_analysis(args.analysis_csv)
    print(f"  Duration: {duration_seconds:.3f}s | SR: {sampling_rate}")

    if duration_seconds <= 0:
        print("  Error: duration_seconds must be > 0", file=sys.stderr)
        sys.exit(1)

    # ---- Read Pbind line ----
    pbind_line = Path(args.pbind_txt).read_text().strip().splitlines()[0].strip()
    print(f"  Pbind: {pbind_line}")

    # ---- Parse ----
    try:
        pbind_dict = parse_pbind(pbind_line)
    except ParseError as e:
        print(f"\nPARSE ERROR:\n{e}", file=sys.stderr)
        sys.exit(1)

    print(f"  Keys: {list(pbind_dict.keys())}")
    for key, pat in pbind_dict.items():
        print(f"    {key}: {describe_pattern(key, pat)}")

    # ---- Config ----
    base_hz = args.baseHz
    seed    = args.seed
    rng     = random.Random(seed)
    print(f"  BaseHz: {base_hz:.2f} Hz | Seed: {seed}")

    # ---- Generate ----
    events = generate_events(pbind_dict, duration_seconds, base_hz, rng)

    if not events:
        print("  Warning: no events generated — inserting fallback single event.",
              file=sys.stderr)
        events = [{
            "t": 0.0, "dur": duration_seconds, "segment_dur": duration_seconds,
            "pitch_key": "freq", "pitch_val": base_hz,
            "amp": 0.1, "hz": base_hz, "db": amp_to_db(0.1),
        }]

    print(f"  Events: {len(events)}")
    for i, ev in enumerate(events[:6]):
        print(f"    [{i}] t={ev['t']:.3f}s  dur={ev['dur']:.3f}s  "
              f"seg={ev['segment_dur']:.3f}s  "
              f"{ev['pitch_key']}={ev['pitch_val']:.2f}  "
              f"amp={ev['amp']:.3f}  hz={ev['hz']:.1f}  db={ev['db']:.1f}")
    if len(events) > 6:
        print(f"    ... ({len(events) - 6} more)")

    # ---- Tier points ----
    pitch_pts, intensity_pts = events_to_tier_points(events, duration_seconds)
    print(f"  Pitch pts: {len(pitch_pts)}  |  Intensity pts: {len(intensity_pts)}")

    # ---- Write ----
    write_pitch_csv(args.out_pitch_csv, pitch_pts)
    write_intensity_csv(args.out_intensity_csv, intensity_pts)
    print(f"  Wrote: {args.out_pitch_csv}")
    print(f"  Wrote: {args.out_intensity_csv}")

    if args.trace:
        write_trace_csv(args.trace, events)
        print(f"  Wrote trace: {args.trace}")

    print("OK")


if __name__ == "__main__":
    main()
