"""
multichannel_play.py — Multichannel Audio Playback Engine

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Plays multichannel WAV files via sounddevice (ASIO / WASAPI / CoreAudio).
Called by PlayMultichannel.praat via runSystem.

On Windows, ASIO is auto-enabled (SD_ENABLE_ASIO) so that multichannel
interfaces appear as a single >2-output device. The interface's own sample
rate must match the file (ASIO does not resample); a mismatch is reported
with a clear message rather than a raw PortAudio error.

Usage:
    python multichannel_play.py path_to_wav
    python multichannel_play.py path_to_wav --device DEVICE_ID
    python multichannel_play.py path_to_wav --device DEVICE_ID --latency low
    python multichannel_play.py --list-devices
"""

import sys
import os
import math
import argparse

# ── Enable ASIO on Windows ────────────────────────────────────────────────
# The pip-installed sounddevice wheel ships an ASIO-capable PortAudio DLL but
# loads the non-ASIO one unless SD_ENABLE_ASIO is set BEFORE sounddevice is
# first imported. Multichannel interfaces (e.g. PreSonus Studio 68c) only
# appear as a single >2-out device under ASIO; under MME/DirectSound/WASAPI/
# WDM-KS they fragment into stereo pairs and cannot do >2 channels. This must
# run before the dependency check below imports sounddevice. setdefault() lets
# an explicit external override stand.
if sys.platform == "win32":
    os.environ.setdefault("SD_ENABLE_ASIO", "1")


def list_devices(out_file=None):
    import sounddevice as sd
    lines = []
    devices  = sd.query_devices()
    hostapis = sd.query_hostapis()

    lines.append("%-4s  %-42s  %-14s  %s"
                 % ("ID", "Device Name", "Host API", "Out Ch"))
    lines.append("-" * 78)
    for i, d in enumerate(devices):
        if d["max_output_channels"] < 1:
            continue
        api_name = hostapis[d["hostapi"]]["name"]
        name     = d["name"][:42]
        lines.append("%-4d  %-42s  %-14s  %d"
                     % (i, name, api_name[:14], d["max_output_channels"]))

    text = "\n".join(lines)
    if out_file:
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        print(text)


def list_devices_tsv(out_file):
    """Write output devices as parseable lines for the Praat picker.

    One line per output-capable device:  <id>\t<label>
    where <label> = "<id>: <name> (<Nch>ch) [<hostapi>]".
    The id before the tab lets Praat map a dropdown choice back to a
    sounddevice device index; the label after the tab is shown in the menu.
    """
    import sounddevice as sd
    devices  = sd.query_devices()
    hostapis = sd.query_hostapis()
    rows = []
    for i, d in enumerate(devices):
        if d["max_output_channels"] < 1:
            continue
        api   = hostapis[d["hostapi"]]["name"]
        name  = d["name"]
        label = "%d: %s (%dch) [%s]" % (i, name, d["max_output_channels"], api)
        label = label.replace("\t", " ").replace("\r", " ").replace("\n", " ")
        rows.append("%d\t%s" % (i, label))
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(rows))
        if rows:
            f.write("\n")


def play_file(wav_path, device_id=None, latency="low", debug=False,
              downmix=False, status_file=None):
    import numpy as np
    import soundfile as sf
    import sounddevice as sd

    # ── Load audio ────────────────────────────────────────────────────────
    if not os.path.isfile(wav_path):
        print("ERROR: File not found: %s" % wav_path, file=sys.stderr)
        sys.exit(1)

    audio, sr = sf.read(wav_path, always_2d=True)
    audio     = audio.astype(np.float32)
    n_samples, n_channels = audio.shape

    if debug:
        print("  File:     %s" % wav_path)
        print("  Channels: %d" % n_channels)
        print("  SR:       %d Hz" % sr)
        print("  Duration: %.3f s" % (n_samples / sr))
        print("  Device:   %s" % (str(device_id) if device_id is not None else "default"))

    # ── Resolve device ────────────────────────────────────────────────────
    if device_id is not None:
        try:
            dev_info = sd.query_devices(device_id, "output")
        except Exception as e:
            print("ERROR: Cannot query device %d: %s" % (device_id, e), file=sys.stderr)
            sys.exit(1)
    else:
        dev_info = sd.query_devices(kind="output")

    dev_max_ch = int(dev_info["max_output_channels"])
    dev_name   = dev_info["name"]

    if debug:
        print("  Dev name: %s" % dev_name)
        print("  Dev ch:   %d" % dev_max_ch)

    # ── Channel safety check / downmix ───────────────────────────────────
    if n_channels > dev_max_ch:
        if downmix:
            # Fold-down: sum channels in round-robin onto the available outs.
            n_out  = min(2, dev_max_ch)
            folded = np.zeros((n_samples, n_out), dtype=np.float32)
            gain   = 1.0 / math.ceil(n_channels / n_out)
            for ch in range(n_channels):
                folded[:, ch % n_out] += audio[:, ch] * gain
            # Peak-safe normalise
            peak = float(np.max(np.abs(folded)))
            if peak > 0.99:
                folded *= 0.99 / peak
            print("  Downmix: %d ch -> %d ch (fold-down)" % (n_channels, n_out))
            audio      = folded
            n_channels = n_out
        else:
            print("ERROR: Audio has %d channels but device '%s' supports only %d."
                  % (n_channels, dev_name, dev_max_ch), file=sys.stderr)
            print("       Use --downmix to fold down to stereo,", file=sys.stderr)
            print("       or use --list-devices to find a device with enough outputs.",
                  file=sys.stderr)
            sys.exit(1)

    if n_channels < dev_max_ch and debug:
        print("  INFO: Audio has fewer channels (%d) than device max (%d)."
              % (n_channels, dev_max_ch))

    # ── Pre-flight check: can this device actually open these settings? ───
    # ASIO does not resample, so a sample-rate mismatch otherwise surfaces as
    # a cryptic PortAudio exception. Validate first and report it plainly.
    check_kwargs = dict(channels=n_channels, samplerate=sr, dtype="float32")
    if device_id is not None:
        check_kwargs["device"] = device_id
    try:
        sd.check_output_settings(**check_kwargs)
    except Exception as e:
        print("ERROR: Device '%s' cannot play this file as-is." % dev_name,
              file=sys.stderr)
        print("       Reason: %s" % e, file=sys.stderr)
        print("       File: %d Hz, %d channel(s)." % (sr, n_channels),
              file=sys.stderr)
        try:
            print("       Device default sample rate: %d Hz."
                  % int(round(dev_info["default_samplerate"])), file=sys.stderr)
        except Exception:
            pass
        print("       Common causes: the interface is set to a different sample "
              "rate (ASIO does not resample \u2014 match it in the device control "
              "panel, e.g. PreSonus Universal Control), or the device is already "
              "in use by another app (ASIO is exclusive).", file=sys.stderr)
        sys.exit(1)

    # ── Playback ──────────────────────────────────────────────────────────
    play_kwargs = dict(
        samplerate = sr,
        latency    = latency,
    )
    if device_id is not None:
        play_kwargs["device"] = device_id

    try:
        sd.play(audio, **play_kwargs)
        sd.wait()
    except KeyboardInterrupt:
        sd.stop()
        print("\nPlayback interrupted by user.")
        sys.exit(0)
    except Exception as e:
        print("ERROR during playback: %s" % e, file=sys.stderr)
        sys.exit(1)

    if debug:
        print("  Playback complete.")

    if status_file:
        with open(status_file, "w") as f:
            f.write("ok")


def main():
    parser = argparse.ArgumentParser(
        description="Multichannel audio playback engine for Praat AudioTools"
    )
    parser.add_argument("wav_file", nargs="?",
        help="Path to WAV file to play")
    parser.add_argument("--device", type=int, default=None,
        help="Output device ID (use --list-devices to find IDs)")
    parser.add_argument("--latency", default="low",
        choices=["low", "high"],
        help="Buffer latency: low (default, ASIO) or high (more stable)")
    parser.add_argument("--list-devices", action="store_true",
        help="List all available output devices and exit")
    parser.add_argument("--list-devices-file", default=None,
        help="Write device list to this file instead of stdout")
    parser.add_argument("--devices-tsv", default=None,
        help="Write output devices as <id>\\t<label> lines to this file and exit "
             "(parseable device picker used by the Praat front-end)")
    parser.add_argument("--downmix", action="store_true",
        help="Fold all channels to stereo if device supports fewer channels than audio")
    parser.add_argument("--status-file", default=None,
        help="Path to write 'ok' on successful playback completion (used by Praat)")
    parser.add_argument("--debug", action="store_true",
        help="Print debug information")

    args = parser.parse_args()

    # Dependency check
    missing = []
    for pkg in ["soundfile", "sounddevice", "numpy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        sys.exit(1)

    if args.list_devices:
        list_devices(out_file=args.list_devices_file)
        sys.exit(0)

    if args.devices_tsv:
        list_devices_tsv(args.devices_tsv)
        sys.exit(0)

    if not args.wav_file:
        parser.print_help()
        sys.exit(1)

    play_file(
        wav_path    = args.wav_file,
        device_id   = args.device,
        latency     = args.latency,
        debug       = args.debug,
        downmix     = args.downmix,
        status_file = args.status_file,
    )


if __name__ == "__main__":
    main()
