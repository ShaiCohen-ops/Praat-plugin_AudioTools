"""
multichannel_play.py — Multichannel Audio Playback Engine
Version: 1.4.1 (2026)

Part of Praat AudioTools plugin
Author: Shai Cohen, Department of Music, Bar-Ilan University

Plays multichannel WAV files via sounddevice (ASIO / WASAPI / CoreAudio).
Called by PlayMultichannel.praat via runSystem.

v1.4.1:
  - Replace blocking OutputStream.write() playback with the callback + bounded
    queue architecture recommended by python-sounddevice for very long files.
    This avoids PortAudio/ASIO Pa_StopStream "Wait timed out" failures seen
    with blocking I/O while retaining bounded-memory streaming.
  - Callback blocksize is left at PortAudio's optimal host-selected value (0),
    which is the sounddevice recommendation for the most robust callback path.
    A bounded 8192-frame disk queue decouples file I/O from the real-time thread;
    callback underruns abort explicitly instead of silently inserting a gap.

v1.4:
  - Stream audio from disk with OutputStream.write() instead of loading the
    entire multichannel file into RAM before playback.
  - Stable device fingerprints (name + host API + output channel count)
    are emitted for the Praat picker so remembered devices survive PortAudio
    index changes across reboots / reconnects.
  - Downmix uses per-destination averaging, fixing level imbalance for odd
    source channel counts (e.g. 5 -> 2).
  - Device/debug diagnostics include host API and stream underflow counts.

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
import argparse

VERSION = "1.4.1"
IO_BLOCK_FRAMES = 8192
LOW_BUFFER_BLOCKS = 8
HIGH_BUFFER_BLOCKS = 16
SCAN_BLOCK_FRAMES = 65536

# Enable ASIO before sounddevice is imported.
if sys.platform == "win32":
    os.environ.setdefault("SD_ENABLE_ASIO", "1")


def _safe_field(value):
    """Make a one-line TSV-safe text field."""
    return str(value).replace("\t", " ").replace("\r", " ").replace("\n", " ")


def device_fingerprint(device_info, api_name):
    """Return a stable-ish key that does not depend on the PortAudio index."""
    return "%s|%s|out=%d" % (
        _safe_field(device_info.get("name", "")),
        _safe_field(api_name),
        int(device_info.get("max_output_channels", 0)),
    )


def _device_api_name(device_info, hostapis):
    try:
        return hostapis[int(device_info["hostapi"])]["name"]
    except Exception:
        return "Unknown"


def list_devices(out_file=None):
    import sounddevice as sd
    lines = []
    devices = sd.query_devices()
    hostapis = sd.query_hostapis()

    lines.append("%-4s  %-42s  %-14s  %s" % ("ID", "Device Name", "Host API", "Out Ch"))
    lines.append("-" * 78)
    for i, d in enumerate(devices):
        if d["max_output_channels"] < 1:
            continue
        api_name = _device_api_name(d, hostapis)
        name = str(d["name"])[:42]
        lines.append("%-4d  %-42s  %-14s  %d" %
                     (i, name, api_name[:14], d["max_output_channels"]))

    text = "\n".join(lines)
    if out_file:
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        print(text)


def list_devices_tsv(out_file):
    """Write output devices for the Praat picker.

    One line per device:
        <id> TAB <stable-key> TAB <label>

    The stable key is used only to remember the user's device between runs;
    the live PortAudio id from this run is always used for actual playback.
    """
    import sounddevice as sd
    devices = sd.query_devices()
    hostapis = sd.query_hostapis()
    rows = []
    for i, d in enumerate(devices):
        if d["max_output_channels"] < 1:
            continue
        api = _device_api_name(d, hostapis)
        name = _safe_field(d["name"])
        api = _safe_field(api)
        label = "%d: %s (%dch) [%s]" % (i, name, d["max_output_channels"], api)
        key = device_fingerprint(d, api)
        rows.append("%d\t%s\t%s" % (i, _safe_field(key), _safe_field(label)))
    with open(out_file, "w", encoding="utf-8") as f:
        f.write("\n".join(rows))
        if rows:
            f.write("\n")


def fold_down_block(audio, n_out):
    """Round-robin fold-down with equal averaging per destination channel.

    For even layouts this is identical to the v1.3 gain law.  For odd source
    counts (e.g. 5 -> 2), each destination is divided by the number of source
    channels actually feeding it, avoiding a systematic level imbalance.
    """
    import numpy as np

    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim != 2:
        raise ValueError("audio block must be 2-D (frames, channels)")
    n_frames, n_channels = audio.shape
    n_out = int(n_out)
    if n_out < 1:
        raise ValueError("n_out must be >= 1")
    if n_channels <= n_out:
        return audio.copy()

    folded = np.zeros((n_frames, n_out), dtype=np.float32)
    counts = np.zeros(n_out, dtype=np.int32)
    for ch in range(n_channels):
        dest = ch % n_out
        folded[:, dest] += audio[:, ch]
        counts[dest] += 1
    for dest in range(n_out):
        if counts[dest] > 1:
            folded[:, dest] /= np.float32(counts[dest])
    return folded



def scan_downmix_peak(wav_path, n_out):
    """Measure the global peak of the folded signal with bounded memory."""
    import numpy as np
    import soundfile as sf
    peak = 0.0
    with sf.SoundFile(wav_path, mode="r") as snd:
        while True:
            block = snd.read(SCAN_BLOCK_FRAMES, dtype="float32", always_2d=True)
            if len(block) == 0:
                break
            folded = fold_down_block(block, n_out)
            peak = max(peak, float(np.max(np.abs(folded))))
    return peak

def _resolve_device_info(sd, device_id):
    if device_id is not None:
        try:
            return sd.query_devices(device_id, "output")
        except Exception as e:
            print("ERROR: Cannot query device %d: %s" % (device_id, e), file=sys.stderr)
            raise SystemExit(1)
    try:
        return sd.query_devices(kind="output")
    except Exception as e:
        print("ERROR: Cannot query the system default output device: %s" % e,
              file=sys.stderr)
        raise SystemExit(1)


def play_file(wav_path, device_id=None, latency="low", debug=False,
              downmix=False, status_file=None):
    """Play a WAV file with bounded-memory callback streaming.

    v1.4 used PortAudio's blocking WriteStream path.  On some Windows ASIO
    drivers that can play the data but then fail in Pa_StopStream with
    paTimedOut (-9987).  v1.4.1 follows python-sounddevice's official
    play_long_file architecture instead: a callback consumes a bounded queue
    of disk blocks and raises CallbackStop after the final short block.
    """
    import queue
    import threading
    import numpy as np
    import soundfile as sf
    import sounddevice as sd

    if not os.path.isfile(wav_path):
        print("ERROR: File not found: %s" % wav_path, file=sys.stderr)
        raise SystemExit(1)

    try:
        info = sf.info(wav_path)
    except Exception as e:
        print("ERROR: Cannot read audio file: %s" % e, file=sys.stderr)
        raise SystemExit(1)

    sr = int(info.samplerate)
    n_samples = int(info.frames)
    n_channels = int(info.channels)
    if n_samples <= 0 or n_channels <= 0:
        print("ERROR: Audio file is empty or has no channels.", file=sys.stderr)
        raise SystemExit(1)

    dev_info = _resolve_device_info(sd, device_id)
    dev_max_ch = int(dev_info["max_output_channels"])
    dev_name = str(dev_info["name"])
    hostapis = sd.query_hostapis()
    api_name = _device_api_name(dev_info, hostapis)

    if dev_max_ch < 1:
        print("ERROR: Device '%s' has no output channels." % dev_name,
              file=sys.stderr)
        raise SystemExit(1)

    play_channels = n_channels
    do_downmix = False
    if n_channels > dev_max_ch:
        if downmix:
            play_channels = min(2, dev_max_ch)
            do_downmix = True
        else:
            print("ERROR: Audio has %d channels but device '%s' supports only %d."
                  % (n_channels, dev_name, dev_max_ch), file=sys.stderr)
            print("       Use --downmix to fold down to the available outputs,",
                  file=sys.stderr)
            print("       or choose a device with enough output channels.",
                  file=sys.stderr)
            raise SystemExit(1)

    downmix_gain = 1.0
    if do_downmix:
        fold_peak = scan_downmix_peak(wav_path, play_channels)
        if fold_peak > 0.99:
            downmix_gain = 0.99 / fold_peak
        print("  Downmix: %d ch -> %d ch (per-output average%s)" %
              (n_channels, play_channels,
               ", peak-safe" if downmix_gain < 1.0 else ""))

    # Let PortAudio/ASIO choose the native callback granularity.  sounddevice
    # explicitly recommends blocksize=0 for the most robust callback behavior.
    buffer_blocks = HIGH_BUFFER_BLOCKS if latency == "high" else LOW_BUFFER_BLOCKS


    if debug:
        print("  Engine:   v%s callback+queue" % VERSION)
        print("  File:     %s" % wav_path)
        print("  Channels: %d%s" %
              (n_channels, " -> %d (downmix)" % play_channels if do_downmix else ""))
        print("  SR:       %d Hz" % sr)
        print("  Duration: %.3f s" % (n_samples / sr))
        print("  Device:   %s" % (str(device_id) if device_id is not None else "default"))
        print("  Dev name: %s" % dev_name)
        print("  Host API: %s" % api_name)
        print("  Dev ch:   %d" % dev_max_ch)
        print("  Latency:  %s" % latency)
        print("  Callback: host-optimal blocksize (PortAudio blocksize=0)")
        print("  Disk queue: %d frames x %d blocks (up to %.0f ms buffered)" %
              (IO_BLOCK_FRAMES, buffer_blocks,
               1000.0 * IO_BLOCK_FRAMES * buffer_blocks / sr))
        print("  sounddevice: %s" % getattr(sd, "__version__", "unknown"))
        try:
            pa_ver = sd.get_portaudio_version()
            print("  PortAudio: %s" % (pa_ver[1] if isinstance(pa_ver, tuple) and len(pa_ver) > 1 else str(pa_ver)))
        except Exception:
            pass
        if n_channels < dev_max_ch:
            print("  INFO: Audio uses %d of %d available output channels."
                  % (n_channels, dev_max_ch))

    check_kwargs = dict(channels=play_channels, samplerate=sr, dtype="float32")
    if device_id is not None:
        check_kwargs["device"] = device_id
    try:
        sd.check_output_settings(**check_kwargs)
    except Exception as e:
        print("ERROR: Device '%s' [%s] cannot play this file as-is."
              % (dev_name, api_name), file=sys.stderr)
        print("       Reason: %s" % e, file=sys.stderr)
        print("       File: %d Hz, %d channel(s)%s."
              % (sr, n_channels,
                 " -> %d channel(s) after downmix" % play_channels if do_downmix else ""),
              file=sys.stderr)
        try:
            print("       Device default sample rate: %d Hz."
                  % int(round(dev_info["default_samplerate"])), file=sys.stderr)
        except Exception:
            pass
        print("       Common causes: the interface is set to a different sample "
              "rate (ASIO does not resample — match it in the device control "
              "panel), or the device is already in use by another app.",
              file=sys.stderr)
        raise SystemExit(1)

    # One extra slot is reserved so the EOF sentinel can be queued even when
    # the data buffer is full.
    q = queue.Queue(maxsize=buffer_blocks + 1)
    finished = threading.Event()
    callback_error = {"message": ""}
    status_notes = []
    frames_played = [0]
    eof_token = object()
    current = {"block": None, "offset": 0}

    def prepare_block(block):
        if do_downmix:
            block = fold_down_block(block, play_channels)
            if downmix_gain < 1.0:
                block = block * np.float32(downmix_gain)
        return np.ascontiguousarray(block, dtype=np.float32)

    def callback(outdata, frames, time_info, status):
        # Real-time thread: only non-blocking queue access and array copies.
        # Disk I/O and downmix happen on the producer/main thread.
        if status:
            status_notes.append(str(status))
            if getattr(status, "output_underflow", False):
                callback_error["message"] = (
                    "ASIO output underflow. Try Latency=high, increase the "
                    "interface buffer size, or close other audio applications.")
                outdata.fill(0)
                raise sd.CallbackAbort

        outdata.fill(0)
        written = 0
        while written < frames:
            block = current["block"]
            if block is None:
                try:
                    item = q.get_nowait()
                except queue.Empty as e:
                    callback_error["message"] = (
                        "Playback buffer ran empty. Try Latency=high or increase "
                        "the ASIO buffer size in the interface control panel.")
                    raise sd.CallbackAbort from e

                if item is eof_token:
                    # CallbackStop is graceful: finished_callback fires only
                    # after all generated output buffers have actually played.
                    raise sd.CallbackStop
                current["block"] = item
                current["offset"] = 0
                block = item

            off = current["offset"]
            available = len(block) - off
            if available <= 0:
                current["block"] = None
                current["offset"] = 0
                continue

            take = min(available, frames - written)
            outdata[written:written + take] = block[off:off + take]
            written += take
            frames_played[0] += take
            off += take
            if off >= len(block):
                current["block"] = None
                current["offset"] = 0
            else:
                current["offset"] = off

    stream_kwargs = dict(
        samplerate=sr,
        blocksize=0,
        channels=play_channels,
        dtype="float32",
        latency=latency,
        callback=callback,
        finished_callback=finished.set,
    )
    if device_id is not None:
        stream_kwargs["device"] = device_id

    stream = None
    try:
        with sf.SoundFile(wav_path, mode="r") as snd:
            # Pre-fill a bounded disk queue before opening ASIO.
            eof_queued = False
            n_prefilled = 0
            for _ in range(buffer_blocks):
                block = snd.read(IO_BLOCK_FRAMES, dtype="float32", always_2d=True)
                if len(block) == 0:
                    q.put_nowait(eof_token)
                    eof_queued = True
                    break
                q.put_nowait(prepare_block(block))
                n_prefilled += 1
                if len(block) < IO_BLOCK_FRAMES:
                    q.put_nowait(eof_token)
                    eof_queued = True
                    break

            if n_prefilled == 0:
                print("ERROR: Audio file contains no readable frames.", file=sys.stderr)
                raise SystemExit(1)

            stream = sd.OutputStream(**stream_kwargs)
            stream.start()

            # Producer side: the bounded queue is paced by the audio callback.
            queue_seconds = IO_BLOCK_FRAMES * buffer_blocks / float(sr)
            q_timeout = max(5.0, queue_seconds * 4.0)
            while not eof_queued:
                block = snd.read(IO_BLOCK_FRAMES, dtype="float32", always_2d=True)
                if len(block) == 0:
                    q.put(eof_token, timeout=q_timeout)
                    eof_queued = True
                    break
                q.put(prepare_block(block), timeout=q_timeout)
                if len(block) < IO_BLOCK_FRAMES:
                    q.put(eof_token, timeout=q_timeout)
                    eof_queued = True

            # Once EOF is queued, at most the bounded queue remains to play.
            finish_timeout = max(5.0, queue_seconds * 4.0 + 2.0)
            if not finished.wait(timeout=finish_timeout):
                callback_error["message"] = (
                    "Audio callback did not finish within %.1f s after EOF. "
                    "The ASIO driver may be stalled." % finish_timeout)
                try:
                    stream.abort()
                except Exception:
                    pass

            if callback_error["message"]:
                raise RuntimeError(callback_error["message"])

            # CallbackStop makes the stream inactive only after all generated
            # output has played.  close() therefore avoids the active-stream
            # Pa_StopStream drain path that produced -9987 in v1.4.
            stream.close()
            stream = None

    except KeyboardInterrupt:
        if stream is not None:
            try:
                stream.abort()
                stream.close()
            except Exception:
                pass
        print("\nPlayback interrupted by user.")
        raise SystemExit(0)
    except queue.Full:
        if stream is not None:
            try:
                stream.abort()
                stream.close()
            except Exception:
                pass
        print("ERROR during playback: audio callback stopped consuming data. "
              "Try Latency=high or increase the ASIO buffer size.", file=sys.stderr)
        raise SystemExit(1)
    except Exception as e:
        if stream is not None:
            try:
                if getattr(stream, "active", False):
                    stream.abort()
                stream.close()
            except Exception:
                pass
        print("ERROR during playback: %s" % e, file=sys.stderr)
        raise SystemExit(1)

    if debug:
        print("  Frames:   %d / %d" % (frames_played[0], n_samples))
        if status_notes:
            print("  PortAudio status: %s" % "; ".join(status_notes))
        print("  Playback complete.")

    if status_file:
        try:
            with open(status_file, "w", encoding="utf-8") as f:
                f.write("ok")
        except Exception as e:
            print("ERROR: Playback succeeded, but status file could not be written: %s"
                  % e, file=sys.stderr)
            raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Multichannel audio playback engine for Praat AudioTools"
    )
    parser.add_argument("wav_file", nargs="?", help="Path to WAV file to play")
    parser.add_argument("--device", type=int, default=None,
                        help="Output device ID (use --list-devices to find IDs)")
    parser.add_argument("--latency", default="low", choices=["low", "high"],
                        help="Buffer latency: low (default, ASIO) or high (more stable)")
    parser.add_argument("--list-devices", action="store_true",
                        help="List all available output devices and exit")
    parser.add_argument("--list-devices-file", default=None,
                        help="Write device list to this file instead of stdout")
    parser.add_argument("--devices-tsv", default=None,
                        help="Write output devices as id<TAB>key<TAB>label for Praat")
    parser.add_argument("--downmix", action="store_true",
                        help="Fold channels down if the device has too few outputs")
    parser.add_argument("--status-file", default=None,
                        help="Path to write 'ok' on successful playback completion")
    parser.add_argument("--debug", action="store_true", help="Print debug information")
    args = parser.parse_args()

    missing = []
    for pkg in ["soundfile", "sounddevice", "numpy"]:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print("ERROR: Missing packages: " + ", ".join(missing), file=sys.stderr)
        print("Install with:  pip install " + " ".join(missing), file=sys.stderr)
        raise SystemExit(1)

    if args.list_devices:
        list_devices(out_file=args.list_devices_file)
        return
    if args.devices_tsv:
        list_devices_tsv(args.devices_tsv)
        return
    if not args.wav_file:
        parser.print_help()
        raise SystemExit(1)

    play_file(
        wav_path=args.wav_file,
        device_id=args.device,
        latency=args.latency,
        debug=args.debug,
        downmix=args.downmix,
        status_file=args.status_file,
    )


if __name__ == "__main__":
    main()
