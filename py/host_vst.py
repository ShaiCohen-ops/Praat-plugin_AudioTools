import sys
import os
from typing import Dict


def fail(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(code)


def check_dependencies() -> None:
    missing = []
    try:
        import pedalboard  # noqa: F401
        from pedalboard.io import AudioFile  # noqa: F401
    except ImportError:
        missing.append("pedalboard")
    if missing:
        fail("Missing Python packages: " + ", ".join(missing) + "\nInstall with: py -m pip install " + " ".join(missing))


def parse_param_string(param_string: str) -> Dict[str, float]:
    result: Dict[str, float] = {}
    if not param_string.strip():
        return result
    for item in param_string.split(","):
        item = item.strip()
        if not item:
            continue
        if "=" in item:
            key, value = item.split("=", 1)
        elif " " in item.strip():
            key, value = item.strip().split(None, 1)
        else:
            fail(f"Bad parameter assignment '{item}'. Use name=value or name value, separated by commas")
        key = key.strip()
        value = value.strip()
        try:
            result[key] = float(value)
        except ValueError:
            fail(f"Bad numeric value in parameter assignment '{item}'")
    return result


def main() -> None:
    if len(sys.argv) < 4 or len(sys.argv) > 8:
        print(
            "Usage: py host_vst.py input.wav output.wav plugin.vst3 [tail_seconds] [buffer_size] [param_assignments] [dump_params]",
            file=sys.stderr,
        )
        print("Example:", file=sys.stderr)
        print(
            '  py host_vst.py in.wav out.wav "C:\\Program Files\\Common Files\\VST3\\MyPlugin.vst3" 1.5 8192 "mix=0.5,output=0.8" 0',
            file=sys.stderr,
        )
        raise SystemExit(1)

    check_dependencies()

    from pedalboard import load_plugin
    from pedalboard.io import AudioFile
    import numpy as np

    in_wav = sys.argv[1]
    out_wav = sys.argv[2]
    plugin_path = sys.argv[3]
    tail_seconds = float(sys.argv[4]) if len(sys.argv) >= 5 else 1.0
    buffer_size = int(sys.argv[5]) if len(sys.argv) >= 6 else 8192
    param_string = sys.argv[6] if len(sys.argv) >= 7 else ""
    dump_params = bool(int(sys.argv[7])) if len(sys.argv) >= 8 else False

    if not os.path.isfile(in_wav):
        fail(f"Input file not found: {in_wav}")
    if not os.path.exists(plugin_path):
        fail(f"VST3 plugin not found: {plugin_path}")
    if not plugin_path.lower().endswith(".vst3"):
        fail("This script expects a .vst3 plugin path")

    print(f"Input:  {in_wav}")
    print(f"Output: {out_wav}")
    print(f"Plugin: {plugin_path}")
    print(f"Tail seconds: {tail_seconds}")
    print(f"Buffer size: {buffer_size}")

    plugin = load_plugin(plugin_path)
    print(f"Loaded plugin: {plugin}")

    available_params = list(plugin.parameters.keys()) if hasattr(plugin, "parameters") else []
    if dump_params:
        print("Available parameters:")
        print(f"  {'Name':<45} {'Min':>10} {'Max':>10} {'Default':>10} {'Current':>10}")
        print(f"  {'-'*45} {'-'*10} {'-'*10} {'-'*10} {'-'*10}")
        for name in available_params:
            def fmt(v):
                try:
                    return f"{float(v):>10.4g}"
                except (TypeError, ValueError):
                    return f"{str(v):>10}"
            try:
                param = plugin.parameters[name]
                # pedalboard may return a metadata object or a bare value
                mn = getattr(param, "min_value",     "?")
                mx = getattr(param, "max_value",     "?")
                df = getattr(param, "default_value", "?")
                try:
                    cur = getattr(plugin, name)
                except Exception:
                    cur = "?"
                print(f"  {name:<45}{fmt(mn)}{fmt(mx)}{fmt(df)}{fmt(cur)}")
            except Exception as e:
                print(f"  {name:<45}  (error: {e})")

    assignments = parse_param_string(param_string)
    for key, value in assignments.items():
        if key not in available_params:
            print(f"WARNING: parameter '{key}' was not found. Skipping.", file=sys.stderr)
            continue
        try:
            setattr(plugin, key, value)
            print(f"Set {key} = {value}")
        except Exception as exc:
            print(f"WARNING: could not set parameter '{key}' to {value}: {exc}", file=sys.stderr)

    with AudioFile(in_wav) as f:
        audio = f.read(f.frames)
        sr = f.samplerate
        num_channels = f.num_channels

    print(f"Sample rate: {sr}")
    print(f"Channels:    {num_channels}")
    print(f"Frames:      {audio.shape[-1]}")

    processed = plugin(audio, sr, buffer_size=buffer_size, reset=True)

    tail_seconds = max(0.0, tail_seconds)
    if tail_seconds > 0:
        tail_frames = int(round(tail_seconds * sr))
        silence = np.zeros((num_channels, tail_frames), dtype=np.float32)
        tail = plugin(silence, sr, buffer_size=buffer_size, reset=False)
        processed = np.concatenate([processed, tail], axis=1)

    with AudioFile(out_wav, "w", sr, processed.shape[0]) as f:
        f.write(processed)

    print(f"OK: wrote {out_wav}")


if __name__ == "__main__":
    main()
