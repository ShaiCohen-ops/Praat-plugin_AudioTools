#!/usr/bin/env python3
# ============================================================
# Praat AudioTools - wave_capture.py
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4 (2026) - MIDI activity report: which CCs the ring really sends
#
# v2.4: a take with the wrong CC numbers used to look "fine" - the three
#   values just stayed at their start value 64 (= 0.504) and the render
#   played almost one sound. Now every take logs ALL incoming MIDI: each
#   CC number with its message count and value range (plus channels), and
#   any non-CC message types (pitch bend, notes...). If a configured CC
#   shows no or almost no activity, a WARNING names the active CCs to use
#   instead. Nothing is remapped automatically - the user decides.
#   Also fixed: the old "no MIDI received" warning could never fire (a
#   sample row is written every tick whether MIDI arrived or not).
#   Header example corrected to the real defaults (CC 1/2/3).
#
# v2.1: Praat runs this helper with runSystem, which WAITS until Python
#   exits - so if any MIDI call blocks (port enumeration, opening a port
#   held by another app, a stuck BLE-MIDI driver), Praat freezes with it.
#   A watchdog thread now ends the process after
#   countdown + seconds + 20 s, writing "error" to the done file and the
#   stage it was stuck in to the log. Every potentially blocking call is
#   logged BEFORE it runs, so wave_log.txt shows where it stopped.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Genki Wave ring gesture capture for the Praat gesture-path
#   performance system. The only component that touches MIDI/Bluetooth.
#
#   Receives (from Praat): capture parameters via CLI args.
#   Produces:
#     1. A gesture CSV (tab-delimited): time, tilt, pan, roll  (0..1)
#     2. A log file (human-readable progress, echoed by Praat)
#     3. A done-sentinel containing "ok" or "error"
#
#   Maps later (Praat-side): Tilt -> path position, Pan -> scrub,
#   Roll -> velocity/volume.
#
# Dependencies:
#   pip install mido python-rtmidi
#
# I/O contract (mirrors ai_conductor_mix.py):
#   wave_capture.py <gesture_csv> <log_file> <done_file>
#       --seconds 8.0 --take 1 --port "" --countdown 3
#       --cc_tilt 1 --cc_pan 2 --cc_roll 3 --rate_hz 100
# ============================================================

import argparse
import csv
import os
import sys
import threading
import time

STAGE = ["starting"]          # last stage reached, reported by the watchdog


def start_watchdog(limit_s, log, done_path):
    """Hard stop so a blocking MIDI call can never freeze Praat forever."""
    def fire():
        try:
            log(f"ERROR: watchdog - no progress after {limit_s:.0f} s, "
                f"stuck at stage: {STAGE[0]}")
            log("  Likely causes: the MIDI port is held by another program "
                "(Softwave, a DAW), or the BLE-MIDI driver is not responding. "
                "Close other MIDI apps / re-pair the ring and try again.")
            write_done(done_path, "error")
        finally:
            os._exit(3)
    t = threading.Timer(limit_s, fire)
    t.daemon = True
    t.start()
    return t


def beep(freq_hz=880, ms=200):
    """Audible cue. winsound.Beep on Windows (precise tone); elsewhere the
    terminal bell. Never raises - a missing beep must not break capture."""
    try:
        import winsound
        winsound.Beep(int(freq_hz), int(ms))
        return
    except Exception:
        pass
    try:
        sys.stdout.write("\a")
        sys.stdout.flush()
    except Exception:
        pass


# -----------------------------------------------------------------------------
# I/O HELPERS
# -----------------------------------------------------------------------------

class Logger:
    """Writes to stdout (flushed, so Praat sees it live) and to a log
    file that Praat reads and echoes into its Info window."""

    def __init__(self, log_path):
        self.log_path = log_path
        self._lines = []

    def __call__(self, msg):
        print(msg, flush=True)
        self._lines.append(msg)
        try:
            with open(self.log_path, "w", encoding="utf-8") as f:
                f.write("\n".join(self._lines) + "\n")
        except OSError:
            pass


def write_done(done_path, status):
    with open(done_path, "w", encoding="utf-8") as f:
        f.write(status + "\n")


def pick_port(requested, log):
    """Return (port_name, all_names). If 'requested' is empty, auto-detect
    a port whose name looks like the Wave / a BLE-MIDI bridge; else the
    first available port."""
    import mido
    STAGE[0] = "listing MIDI input ports (mido.get_input_names)"
    log("Listing MIDI input ports...")
    names = mido.get_input_names()
    log(f"  {len(names)} port(s): " + (", ".join(names) if names else "none"))
    if requested:
        for n in names:
            if n == requested:
                return n, names
        for n in names:
            if requested.lower() in n.lower():
                return n, names
        return None, names
    for key in ("wave", "genki", "bluetooth", "ble"):
        for n in names:
            if key in n.lower():
                return n, names
    return (names[0] if names else None), names


def write_gesture_csv(path, rows):
    """Tab-delimited, header row, to match the conductor's CSV style."""
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["time", "tilt", "pan", "roll"])
        for r in rows:
            w.writerow([f"{r[0]:.4f}", f"{r[1]:.5f}",
                        f"{r[2]:.5f}", f"{r[3]:.5f}"])


# -----------------------------------------------------------------------------
# CAPTURE
# -----------------------------------------------------------------------------

def capture(seconds, take, port, countdown, cc_tilt, cc_pan, cc_roll,
            rate_hz, log):
    """Record the ring's Tilt/Pan/Roll CC streams for `seconds`.
    Returns a list of (t, tilt01, pan01, roll01) sampled on a fixed grid."""
    import mido

    port_name, all_names = pick_port(port, log)
    if port_name is None:
        listing = "\n  ".join(all_names) if all_names else "(none found)"
        log("ERROR: no usable MIDI input port.")
        log(f"  Requested: '{port}'")
        log(f"  Available ports:\n  {listing}")
        log("  Pair the Wave ring (BLE MIDI) / open Softwave, or set the "
            "exact port name in the Praat form.")
        return None

    log(f"Using MIDI port: {port_name}")

    # Countdown so the performer can get ready.
    STAGE[0] = "countdown"
    for c in range(countdown, 0, -1):
        log(f"Take {take}: starting in {c}...")
        beep(660, 120)          # short mid tick each second
        time.sleep(1.0)
    log(f"Take {take}: RECORDING ({seconds:.1f}s)")
    beep(990, 400)              # higher, longer = GO / record start

    tilt = pan = roll = 64                  # latest CC values (0..127)
    cc_stats = {}       # cc -> [count, min, max, set(channels)]
    other_types = {}    # non-CC message type -> count
    rows = []
    sample_dt = 1.0 / max(1.0, rate_hz)

    t0 = time.monotonic()
    t_end = t0 + seconds
    next_sample = t0

    try:
        STAGE[0] = f"opening MIDI port '{port_name}'"
        log(f"Opening port '{port_name}'...")
        with mido.open_input(port_name) as inport:
            STAGE[0] = "recording"
            while True:
                now = time.monotonic()
                if now >= t_end:
                    break
                for msg in inport.iter_pending():
                    if msg.type == "control_change":
                        st = cc_stats.setdefault(msg.control,
                                                 [0, 127, 0, set()])
                        st[0] += 1
                        st[1] = min(st[1], msg.value)
                        st[2] = max(st[2], msg.value)
                        st[3].add(getattr(msg, "channel", 0) + 1)
                        if msg.control == cc_tilt:
                            tilt = msg.value
                        elif msg.control == cc_pan:
                            pan = msg.value
                        elif msg.control == cc_roll:
                            roll = msg.value
                    else:
                        other_types[msg.type] = other_types.get(msg.type, 0) + 1
                if now >= next_sample:
                    rows.append((now - t0,
                                 tilt / 127.0, pan / 127.0, roll / 127.0))
                    next_sample += sample_dt
                time.sleep(0.001)
    except Exception as e:                  # noqa - report to Praat via log
        log(f"ERROR: MIDI capture failed on port '{port_name}': {e}")
        return None

    beep(440, 250)              # lower = record finished, stop moving
    log(f"Take {take}: recording finished.")

    report_midi_activity(cc_stats, other_types, seconds,
                         {"Tilt": cc_tilt, "Pan": cc_pan, "Roll": cc_roll}, log)

    if not rows:
        rows = [(0.0, 0.5, 0.5, 0.5), (seconds, 0.5, 0.5, 0.5)]

    log(f"Take {take}: captured {len(rows)} samples.")
    return rows


def report_midi_activity(cc_stats, other_types, seconds, wanted, log):
    """Log what actually arrived, and warn when a configured CC was silent."""
    if not cc_stats and not other_types:
        log("WARNING: NO MIDI messages arrived during the take - the gesture "
            "is flat (all values 0.50). Is the ring awake and sending on "
            "this port?")
        return
    log("Detected CC activity (this take):")
    for cc, (cnt, lo, hi, chans) in sorted(cc_stats.items(),
                                            key=lambda kv: -kv[1][0]):
        tags = [name for name, num in wanted.items() if num == cc]
        tag = ("  <- " + "/".join(tags)) if tags else ""
        ch = ",".join(str(c) for c in sorted(chans))
        log(f"  CC {cc:3d}: {lo:3d}-{hi:3d}   ({cnt} messages, ch {ch}){tag}")
    for t, cnt in sorted(other_types.items(), key=lambda kv: -kv[1]):
        log(f"  {t}: {cnt} messages")
    # "active" = enough messages to be a gesture stream, with real movement
    min_msgs = max(10, int(2 * seconds))
    active = [cc for cc, (cnt, lo, hi, _) in cc_stats.items()
              if cnt >= min_msgs and hi - lo >= 8]
    for name, num in wanted.items():
        cnt, lo, hi = (cc_stats[num][:3] if num in cc_stats else (0, 0, 0))
        if cnt < min_msgs or hi - lo < 8:
            others = [c for c in active if c not in wanted.values()]
            hint = (" Active CCs detected: " + ", ".join(str(c) for c in sorted(others))
                    + ".") if others else ""
            log(f"WARNING: configured {name} CC {num} showed almost no "
                f"activity ({cnt} messages, range {lo}-{hi}).{hint}")


# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

def list_ports_to_file(out_path):
    """Write the available MIDI input port names, one per line, to
    out_path. First line is a status: 'ok N' or 'error <msg>'. Praat
    reads this to build the selection dropdown."""
    try:
        import mido
    except ImportError:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write("error mido-not-installed\n")
        print("ERROR: mido not installed (pip install mido python-rtmidi)",
              flush=True)
        return
    try:
        names = mido.get_input_names()
    except Exception as e:  # noqa
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(f"error {e}\n")
        print(f"ERROR listing ports: {e}", flush=True)
        return
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(f"ok {len(names)}\n")
        for n in names:
            f.write(n + "\n")
    print(f"Found {len(names)} MIDI input port(s):", flush=True)
    for n in names:
        print("  " + n, flush=True)


def main():
    ap = argparse.ArgumentParser(description="Wave ring gesture capture")
    # Port-listing mode (no capture). When set, positionals are optional.
    ap.add_argument("--list_ports", type=str, default="",
                    help="write available MIDI input ports to this file, "
                         "then exit")
    ap.add_argument("gesture_csv", type=str, nargs="?", default="")
    ap.add_argument("log_file", type=str, nargs="?", default="")
    ap.add_argument("done_file", type=str, nargs="?", default="")
    ap.add_argument("--seconds", type=float, default=8.0)
    ap.add_argument("--take", type=int, default=1)
    ap.add_argument("--port", type=str, default="Wave 1")
    ap.add_argument("--countdown", type=int, default=3)
    ap.add_argument("--cc_tilt", type=int, default=1)
    ap.add_argument("--cc_pan", type=int, default=2)
    ap.add_argument("--cc_roll", type=int, default=3)
    ap.add_argument("--rate_hz", type=float, default=100.0)
    args = ap.parse_args()

    # --- list-ports mode: just enumerate and exit ---
    if args.list_ports:
        list_ports_to_file(args.list_ports)
        return

    if not (args.gesture_csv and args.log_file and args.done_file):
        print("ERROR: gesture_csv, log_file, done_file are required "
              "for capture.", flush=True)
        sys.exit(2)

    # clear a stale done sentinel
    try:
        os.remove(args.done_file)
    except FileNotFoundError:
        pass

    log = Logger(args.log_file)
    log("=== Wave Gesture Capture v2.4 ===")
    log(f"Take: {args.take} | {args.seconds:.1f}s | "
        f"CC tilt/pan/roll = {args.cc_tilt}/{args.cc_pan}/{args.cc_roll}")

    # watchdog: countdown + take + generous margin for port setup
    start_watchdog(args.countdown + args.seconds + 20.0, log, args.done_file)

    STAGE[0] = "importing mido"
    try:
        import mido  # noqa
    except ImportError:
        log("ERROR: python package 'mido' not installed. Run:")
        log("    pip install mido python-rtmidi")
        write_done(args.done_file, "error")
        sys.exit(1)

    rows = capture(args.seconds, args.take, args.port, args.countdown,
                   args.cc_tilt, args.cc_pan, args.cc_roll, args.rate_hz, log)

    if rows is None:
        write_done(args.done_file, "error")
        sys.exit(1)

    STAGE[0] = "writing gesture CSV"
    write_gesture_csv(args.gesture_csv, rows)
    log(f"Gesture CSV: {args.gesture_csv} ({len(rows)} rows)")
    write_done(args.done_file, "ok")
    log("OK: capture done")


if __name__ == "__main__":
    main()
