#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Part of Praat AudioTools | Author: Shai Cohen, Bar-Ilan University | MIT License
"""
dce_engine.py — Distributed Corpus Ecology, Experimental Core
Version : 0.1.7.2 (Praat AudioTools) — Safe Scratch Cleanup
Scope   : conditions 0 (Independent), 1 (Centralized), 2 (Decentralized)
Planned : v0.2 Collective Regulator (3) + Macro-Trajectory Replay (4)
          v0.3 batch metrics (SSM / novelty / entropy / lagged correlation)

Pipeline (each stage reads/writes plain TSV, so Praat can draw every stage):
    analyze   source.wav            -> corpus.tsv        (grains + features)
    simulate  corpus.tsv            -> events.tsv, states.tsv   (NO audio)
    render    events.tsv + source   -> stereo WAV  (--render-mode legacy | sustain)
    run       source.wav            -> all of the above, for N conditions x M seeds
    demo                            -> synthetic percussion loop for testing

Design rules
  * One engine; the three architectures differ ONLY in where an agent's
    external input comes from:
        cond 0 : nothing (own bias + own fatigue + noise)
        cond 1 : one shared global trajectory G(t)           (scaled by `coupling`)
        cond 2 : memory-filtered activity of the other agents (K matrix * `coupling`)
    In cond 2 the coupling also acts on grain choice (K>0 attracts toward the
    other agent's last grain in feature space, K<0 repels).
  * Synchronous update: every agent reads the PREVIOUS tick's state.
  * Independent, seeded RNG streams per agent and per purpose (noise / firing /
    selection): changing the condition never reshuffles another agent's randomness.
  * Config is plain key=value text (Praat has no JSON parser).

Changelog
  0.1  initial: analyze / simulate / render / run, conditions 0-2
       default K = cyclic inhibition: a fully 'cooperate/compete' K (A<->B coop, A-C compete)
       collapsed to one dominant agent in testing; the ring keeps dominance rotating
  0.1.1 methodology fixes (no new features):
       - fully synchronous update: last_g/last_t are snapshotted at tick start, so
         agent order no longer matters (regression test: agent_order=2,1,0 gives identical events)
       - two coupling channels switchable for ablation: coupling_activity, coupling_selection
         (cond 2 with coupling_selection=0 is the clean counterpart of cond 1: both act on activity only)
       - rank normalisation now averages ties (scipy rankdata) — equal durations are equal
       - render: --norm fixed|rms|peak (fixed = identical gain across files, 32-bit float WAV,
         for measurement; rms = loudness-matched, for blind listening); --length gives equal duration
  0.1.2 analysis / robustness fixes (no new architecture):
       - analyze: no material is discarded. Segments > max_dur are split evenly (not truncated),
         segments < min_dur are merged into their neighbour; coverage is reported
       - stereo/multichannel sources: analysis + render use the highest-RMS channel
         (--channel auto|mix|0|1|...), so anti-phase channels no longer cancel
       - empty event log is a legitimate (silent) result: render writes silence of the requested length
       - rate_max is now in EVENTS PER SECOND (p = 1-exp(-rate*act*dt)); noise is scaled so the
         activity dynamics are approximately independent of dt (reference dt = 0.1 s)
       - event log is sorted by (tick, agent) -> byte-identical files regardless of agent_order
  0.1.3 - event count per tick is Poisson (inverse-CDF on ONE uniform per tick, so the underlying
         random numbers stay aligned across conditions): rate no longer capped at 1/dt, and the
         event rate is independent of dt. Events are placed uniformly INSIDE the tick window
         (config `subtick`=1; 0 = tick-aligned grid), so onsets are no longer locked to a 100 ms grid.
         Log column `p_fire` is renamed `lam` (expected events in that tick).
       - render: output directory is created on every path (incl. silent output)

  0.1.4  - event-triggered coupling: off/hybrid/fast_only, one-tick latency,
           event_strength and event_decay_s; event pulse and fast-input diagnostics.
  0.1.4.1 - reliability / experimental-validity patch, musical defaults unchanged:
           fast activity feedback respects coupling_activity; strict input checks
           for seed, matrix, and memory_tau; nonnegative Poisson counts; CLI
           selftest; activity saturation/selection-entropy diagnostics and peak warnings.
           Pulse centering is intentionally unchanged in 0.1.4.1.
  0.1.5  - reference-centered fast and slow feedback (opt-in): independently
           simulate uncoupled agents using identical seed and parameters,
           calculate post-burn-in mem/pulse baselines, and subtract them from
           the corresponding neighbor signals. Legacy mode reproduces 0.1.4.1.
           - optional rate normalization of fast event signals; continuous
             selection coupling gain independent of activity coupling.
           - per-agent control-drive statistics and selection entropy;
             TSV-only multi-seed/multi-coupling 'study' command.
           - new zero-coupling invariants (historical golden checksum added in v0.1.5.2).
           - renderer and agent count unchanged; no regulator or replay yet.

   0.1.7.1 - Final output fade for Persistent Processes only (default 1.0 s).
             Always fades the final stereo mix, not only voices clipped at the
             length boundary. Does not affect simulation or earlier render modes.
  0.1.7  - Persistent Sonic Processes (rendering only; event logs, simulation, legacy, v0.1.6
           sustain and v0.1.6.1 voices are unchanged):
           - render mode `process`: an agent decision updates a persistent sound process.
             Voice persistence: one voice per PHRASE; a phrase ends only when the agent falls
             silent for > 4x its own expected interval (from `lam`) and >= 0.3 s
             (articulation=phrases), or at source attacks (articulation=attacks).
             An attack-marked grain inside a phrase does not re-attack: it enters after its attack.
           - continuous transformation: the voice is a mixture of material streams whose
             weights glide with time constant morph_s/3, independent of decision density;
             a decision pointing within 0.6 s of where a stream is reading re-uses it.
             Linear mixture + block energy correction (+-6 dB); same-sound entries phase-aligned.
           - extension: during a phrase a stream loops a window ending ~12 dB below its peak
             (best of 6 correlation-aligned destinations, 80 ms energy-preserving jumps, decay
             slope flattened up to 12 dB); after the phrase it plays to its natural end.
             Transients are never looped. One stream without loop = the source, sample-exact.
           - same-material re-articulation of an agent = one resonator (old voice faded).
           - diagnostics: voices, decisions/voice, new material / reuse, loop jumps, max streams.
  0.1.6.1 - Continuous Voice Rendering (rendering only; event logs, simulation, legacy and
           v0.1.6 sustain output are unchanged - both are selftest goldens):
           - render mode `voices`: one persistent voice (source playhead) per agent. A grain
             that starts at a significant attack opens a new voice and the previous one rings
             on to its natural end (no voice stealing); a grain that starts mid-sound is a
             Voice Evolution: the playhead moves to the new material over evolution_ms
             (default 300 ms), entering at the 0-20 ms lag of maximum correlation with the
             material being left, with correlation-compensated constant-power gains.
             Decisions < 10 ms after the previous change are absorbed (logged, inaudible).
           - sustain option preserve_tails=1 (Independent Tail Preservation): no handoff,
             to measure the contribution of overlap alone.
           - diagnostics: attacks / evolutions / entries / absorbed, voice count and length,
             mean evolution correlation; per-event action, lag and rho in *_render.tsv.
           - selftest: v0.1.6 sustain golden, voices determinism and event-log invariance,
             sustained-tone continuity, no restart of a sounding voice, crossfade level.
  0.1.6  - Sustain & Release (rendering only; analysis grains, simulation, event logs,
           study and all historical goldens are unchanged):
           - analytical grain (corpus row, selection) is now separate from the rendered
             event (source interval actually played). Render mode legacy|sustain;
             legacy is the v0.1.5.5 renderer, sample-identical (selftest golden).
           - sustain analysis (numpy only, deterministic): each corpus boundary is tested
             as an attack by energy rise OR spectral change; each grain gets a natural end
             = first of next significant attack, envelope floor, max_tail_s, file end.
             Soft transient / sustained / resonant / uncertain class (diagnostic + fades).
             Written to corpus_sustain.tsv; corpus.tsv itself is untouched.
           - sustain renderer: source continuation instead of 600 ms cuts; 2 ms fade-in on
             real attacks, crossfade_ms equal-power entry mid-sustain; release_ms fade only
             where the source is still sounding (12 ms cap for transients), attack-protected;
             same-agent handoff crossfade when two events would replay the same source audio;
             tail_policy fixed (default, trim with release at the requested length) | extend.
           - diagnostics: *_render.tsv per event, *_render_stats.txt (max overlap, peak, RMS,
             duration, extended / natural / release / handoff / boundary counts, classes).
           - selftest: legacy render golden + synthetic percussion / sustained / resonant /
             speech-like tests + determinism and event-log invariance.
  0.1.5.5 - wrapper reliability and batch reporting only; sound engine untouched:
           - Praat automatically opens the network editor for Custom and Cancel exits quietly.
           - selftest executes a short study smoke test and checks generated TSV files.
           - study reports the number of agents with zero events; effective-grain
             means remain computed over active agents only.
  0.1.5.4 - compact Praat interface is the primary change; engine behavior preserved.
           Study now includes paired per-seed comparisons for agent-balanced
           activity variability, effective-grain count and drive variability.
           No density matching is claimed; condition 1 remains a global trajectory.
  0.1.5.3 - method calibration and factorial-study correction:
           - opt-in central_reference=mean_g makes the *post-burn-in average*
             central drive zero (it does NOT density-match or equalize drive variance).
           - study drops irrelevant factor combinations for conditions 0 and 1,
             uses labelled n/a cells, and constructs seed-paired comparisons
             from unique simulations rather than duplicated pseudoreplicates.
           - independent-reference cache reused across condition-2 study runs,
             20 seeds default, and Fisher-z analysis for agent correlations.
           - legacy / off / fast_only / uncoupled golden regression checks.
  0.1.5.2 - methodology/UI correction (synthesis untouched):
           - expose legacy historical SHA-256 comparison in selftest
           - independent reference simulation is quiet in interactive runs
           - summary uses consistent post-burn-in window for activity and drives
           - study now has memory/gain/reference/event-mode sweeps, separate
             fast/slow metrics, agent correlations, mean/95% t CI and seed-paired
             condition differences; condition-0 runs cached across couplings
           - CRN applies to noise and per-tick firing counts, not to later
             grain selection / subtick offsets if event counts diverge.

Design notes
  * Stereo sources: analysis and synthesis use ONE channel (highest RMS); events are then placed in a
    NEW stereo image (per-agent pan). The source's original inter-channel spatial relations are not kept.
  * Synchronous update: all agents read the previous tick's activity/memory/fatigue AND last-grain state.
  * `rate_max` = events/second at activity 1.
"""
import argparse
import csv
import os
import sys
import tempfile
import hashlib
import re
import shutil
from collections import defaultdict

import numpy as np
import soundfile as sf
from scipy.stats import poisson, t as student_t

AGENTS = ["A", "B", "C"]          # A rhythmic, B spectral, C textural
FEATS = ["rms_db", "centroid_hz", "flatness", "dur_s"]

# --------------------------------------------------------------------------
# Config (all values may be overridden by --config file or --set key=value)
# --------------------------------------------------------------------------
DEFAULTS = {
    # time
    "dt": 0.1,                      # tick length, seconds
    "duration": 60.0,               # seconds
    # the four user-facing parameters
    "coupling": 1.5,                # coupling strength (cond 1: global drive, cond 2: mutual)
    "coupling_activity": 1.0,       # 1/0: coupling channel acting on firing activity (cond 2)
    "coupling_selection": 1.0,       # 1/0: coupling channel acting on grain choice (cond 2)
    "selection_gain": 1.0,           # additional continuous selection coupling gain
    "feedback_reference": "legacy", # legacy | independent: mean-centered slow and fast drives
    "central_reference": "legacy",  # legacy | mean_g : opt-in mean-centered GLOBAL trajectory
    "pulse_rate_normalize": 0.0,     # normalize per-agent pulse deviations by max-rate ratio
    "event_mode": "off",              # off=legacy; hybrid=slow+fast; fast_only=no slow activity
    "event_strength": 1.0,             # independent fast reaction gain
    "event_decay_s": 0.25,             # exponential time scale for event impulses, seconds
    "subtick": 1.0,                 # 1: place events uniformly inside the tick; 0: tick-aligned grid
    "agent_order": "0,1,2",         # evaluation order — must not matter (regression test)
    "memory_tau": 2.0,              # feedback memory, seconds (EMA of others' activity)
    "temperature": 0.4,             # selection temperature (softmax)
    "pref": "0.8,0.5,0.3,0.1;0.5,0.9,0.6,0.4;0.4,0.2,0.2,0.9",     # agent preferences (rank-normalised features)
    "pref_weights": "1.5,0.5,0.3,1.0;0.5,1.5,1.0,0.3;0.5,0.5,0.5,1.5",
    # coupling matrix K[i,j] = influence of j on i  (+ cooperative, - competitive)
    "K": "0,0.3,-0.8;-0.8,0,0.3;0.3,-0.8,0",   # cyclic inhibition (A<-C, B<-A, C<-B) + weak excitation
    # centralized trajectory (normalised time;level) — the composer-prescribed form
    "trajectory": "0,0.2;0.35,0.85;0.7,0.3;1,0.9",
    # fixed internal constants (not part of the user-facing interface)
    "bias": "0.0,0.0,0.0",
    "rate_max": "7,3.5,1.7",         # max firing rate, EVENTS PER SECOND (at activity = 1)
    "act_gain": 6.0,
    "act_tau": 0.5,                 # s
    "fatigue_gain": 0.8,
    "fatigue_tau": 6.0,             # s
    "noise": 0.15,
    "repeat_penalty": 1.0,
    "social_window": 2.0,           # s: how long another agent's last grain still influences choice
    "pans": "-0.6,0,0.6",
}


def parse_vec(s):
    return np.array([float(x) for x in str(s).split(",")], dtype=float)


def parse_mat(s):
    return np.array([[float(x) for x in row.split(",")] for row in str(s).split(";")], dtype=float)


def load_config(path=None, sets=None):
    cfg = dict(DEFAULTS)
    if path:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip()
    for kv in sets or []:
        if "=" not in kv:
            raise ValueError("--set must have the form key=value")
        k, v = kv.split("=", 1)
        k = k.strip()
        if k not in DEFAULTS:
            raise ValueError("Unknown configuration key: %r" % k)
        cfg[k] = v.strip()
    for k in cfg:                   # numeric scalars
        if k in DEFAULTS and isinstance(DEFAULTS[k], float):
            cfg[k] = float(cfg[k])
    unknown = set(cfg) - set(DEFAULTS)
    if unknown:
        raise ValueError("Unknown configuration key(s): " + ", ".join(sorted(unknown)))
    return cfg


def validated_matrix(text, name="K", shape=(3, 3), zero_diagonal=False):
    """Finite, exact shape: reject (rather than silently rewrite) self-coupling."""
    try:
        matrix = parse_mat(text)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"{name}: expected {shape[0]}x{shape[1]} numeric matrix") from exc
    if matrix.shape != shape or not np.all(np.isfinite(matrix)):
        raise ValueError(f"{name}: expected finite {shape[0]}x{shape[1]} matrix")
    if zero_diagonal and np.any(np.abs(np.diag(matrix)) > 1e-12):
        raise ValueError(f"{name}: diagonal must be 0 (self-coupling is not supported)")
    return matrix


# --------------------------------------------------------------------------
# 1. Corpus analysis
# --------------------------------------------------------------------------
def load_mono(path, channel="auto"):
    """channel: 'auto' = highest-RMS channel (default), 'mix' = channel mean, or an integer index."""
    y, sr = sf.read(path, always_2d=True)
    if y.shape[1] == 1:
        return y[:, 0].astype(np.float64), sr
    if channel == "mix":
        return y.mean(axis=1).astype(np.float64), sr
    if channel == "auto":
        k = int(np.argmax(np.sqrt((y ** 2).mean(axis=0))))
    else:
        k = min(int(channel), y.shape[1] - 1)
    return y[:, k].astype(np.float64), sr


def analyze(wav_path, corpus_path, channel="auto", min_dur=0.03, max_dur=0.6):
    import librosa
    y, sr = load_mono(wav_path, channel)
    onsets = librosa.onset.onset_detect(y=y, sr=sr, backtrack=True, units="samples")
    bounds = sorted(set([0] + [int(o) for o in onsets] + [len(y)]))
    # 1. merge segments shorter than min_dur into their neighbour (drop the boundary)
    merged = [bounds[0]]
    for b in bounds[1:]:
        if (b - merged[-1]) / sr < min_dur and b != bounds[-1]:
            continue
        merged.append(b)
    if len(merged) > 2 and (merged[-1] - merged[-2]) / sr < min_dur:
        del merged[-2]
    # 2. split segments longer than max_dur evenly (nothing is truncated or skipped)
    edges = []
    for a, b in zip(merged[:-1], merged[1:]):
        k = int(np.ceil((b - a) / (max_dur * sr)))
        edges += [(int(x), int(z)) for x, z in zip(np.linspace(a, b, k + 1)[:-1], np.linspace(a, b, k + 1)[1:])]
    rows = []
    for a, b in edges:
        seg = y[a:b]
        rms = np.sqrt(np.mean(seg ** 2)) + 1e-9
        mag = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) + 1e-12
        freqs = np.fft.rfftfreq(len(seg), 1.0 / sr)
        centroid = float(np.sum(freqs * mag) / np.sum(mag))
        pw = mag ** 2
        flat = float(np.exp(np.mean(np.log(pw))) / np.mean(pw))
        rows.append([len(rows), a / sr, b / sr, 20 * np.log10(rms), centroid, flat, (b - a) / sr])
    if len(rows) < 4:
        sys.exit("analyze: fewer than 4 grains found — check the source file")
    os.makedirs(os.path.dirname(os.path.abspath(corpus_path)), exist_ok=True)
    with open(corpus_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["id", "start_s", "end_s"] + FEATS)
        for r in rows:
            w.writerow([r[0]] + [f"{x:.6f}" for x in r[1:]])
    cov = sum(r[6] for r in rows) / (len(y) / sr)
    print(f"analyze: {len(rows)} grains, coverage {100 * cov:.1f}% of {len(y) / sr:.2f}s -> {corpus_path}")
    return len(rows)


def load_corpus(corpus_path):
    with open(corpus_path, encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter="\t")
        rows = list(rd)
    se = np.array([[float(r["start_s"]), float(r["end_s"])] for r in rows])
    raw = np.array([[float(r[k]) for k in FEATS] for r in rows])
    raw[:, 1] = np.log(raw[:, 1])       # log centroid
    raw[:, 3] = np.log(raw[:, 3])       # log duration
    # rank-percentile normalisation -> [0,1], robust to outliers
    from scipy.stats import rankdata
    ranks = np.column_stack([rankdata(raw[:, k], method="average") - 1.0 for k in range(raw.shape[1])])
    F = ranks / max(len(rows) - 1, 1)
    return se, F


# --------------------------------------------------------------------------
# 2. Interaction simulator (no audio)
# --------------------------------------------------------------------------
def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def simulate(corpus_path, cfg, condition, seed, out_prefix, quiet=False, reference_cache=None):
    if not isinstance(seed, (int, np.integer)) or seed < 0:
        raise ValueError("Seed must be a non-negative integer")
    if condition not in (0, 1, 2):
        sys.exit("simulate: conditions 3 (Regulator) and 4 (Replay) arrive in v0.2")
    event_mode = str(cfg.get("event_mode", "off")).strip().lower()
    if event_mode not in ("off", "hybrid", "fast_only"):
        raise ValueError("event_mode must be off, hybrid or fast_only")
    event_strength = float(cfg.get("event_strength", 1.0))
    event_decay_s = float(cfg.get("event_decay_s", 0.25))
    if not (0.0 <= event_strength <= 20.0 and 0.01 <= event_decay_s <= 30.0):
        raise ValueError("event_strength must be 0..20 and event_decay_s 0.01..30")
    se, F = load_corpus(corpus_path)
    n_grains = len(F)
    nA = len(AGENTS)
    dt, dur = cfg["dt"], cfg["duration"]
    if not (np.isfinite(dt) and 0 < dt <= 1.0 and np.isfinite(dur) and dur >= dt):
        raise ValueError("dt must be (0,1] and duration must be >= dt")
    tau = cfg["memory_tau"]
    if not np.isfinite(tau) or tau < dt:
        raise ValueError(f"memory_tau must be >= dt ({dt:g} s), not {tau:g} s")
    if not quiet and condition == 2 and cfg["feedback_reference"] == "independent" and cfg["memory_tau"] > 0.3 * dur:
        print("  WARNING: memory_tau > 30% of output duration; reference includes a substantial transient")
    T = int(round(dur / dt))
    central_reference = str(cfg.get("central_reference", "legacy")).strip().lower()
    if central_reference not in ("legacy", "mean_g"):
        raise ValueError("central_reference must be legacy or mean_g")
    K = validated_matrix(cfg["K"], "K", zero_diagonal=True)
    pref = validated_matrix(cfg["pref"], "pref", shape=(nA, len(FEATS)))
    W = validated_matrix(cfg["pref_weights"], "pref_weights", shape=(nA, len(FEATS)))
    bias, rmax, pans = parse_vec(cfg["bias"]), parse_vec(cfg["rate_max"]), parse_vec(cfg["pans"])
    if any(v.shape != (nA,) or not np.all(np.isfinite(v)) for v in (bias, rmax, pans)):
        raise ValueError("bias/rate_max/pans must contain 3 finite values each")
    if np.any(rmax < 0):
        raise ValueError("rate_max cannot be negative")
    traj = parse_mat(cfg["trajectory"])
    if traj.ndim != 2 or traj.shape[1] != 2 or not np.all(np.isfinite(traj)) or np.any(np.diff(traj[:, 0]) < 0):
        raise ValueError("trajectory requires increasing t,level pairs")
    coupling, temp = cfg["coupling"], max(cfg["temperature"], 1e-3)
    # Mean over the analysis window, not the continuous trajectory or a
    # corpus-derived baseline. This is an experimental control only; legacy
    # remains bit-for-bit unchanged.
    central_g_mean = 0.5
    if condition == 1 and central_reference == "mean_g":
        burn = int(0.1 * T)
        tt = np.arange(T, dtype=float) * dt / dur
        central_g_mean = float(np.mean(np.interp(tt[burn:], traj[:, 0], traj[:, 1])))
    reference_mode = str(cfg["feedback_reference"]).lower()
    if reference_mode not in ("legacy", "independent"):
        raise ValueError("feedback_reference must be legacy or independent")
    selection_gain = float(cfg["selection_gain"])
    pulse_norm = float(cfg["pulse_rate_normalize"])
    if not (np.isfinite(selection_gain) and 0.0 <= selection_gain <= 10.0):
        raise ValueError("selection_gain must be finite and in [0,10]")
    if pulse_norm not in (0.0, 1.0):
        raise ValueError("pulse_rate_normalize must be 0 or 1")
    order = [int(x) for x in str(cfg["agent_order"]).split(",")]
    if sorted(order) != list(range(nA)):
        raise ValueError("agent_order must be a permutation of 0,1,2")
    noise_sd = cfg["noise"] * np.sqrt(0.1 / dt)              # keeps filtered noise variance ~ independent of dt
    ch_act, ch_sel = float(cfg["coupling_activity"]), float(cfg["coupling_selection"])
    mem_a = min(dt / max(cfg["memory_tau"], dt), 1.0)
    act_a = min(dt / max(cfg["act_tau"], dt), 1.0)
    fat_a = min(dt / max(cfg["fatigue_tau"], dt), 1.0)

    # separate seeded streams: [noise, fire, select] x agent
    kids = np.random.SeedSequence(seed).spawn(4 * nA)
    r_noise = [np.random.default_rng(kids[i]) for i in range(nA)]
    r_fire = [np.random.default_rng(kids[nA + i]) for i in range(nA)]
    r_sel = [np.random.default_rng(kids[2 * nA + i]) for i in range(nA)]
    r_off = [np.random.default_rng(kids[3 * nA + i]) for i in range(nA)]      # sub-tick onset offsets
    subtick = float(cfg["subtick"])

    act = np.full(nA, 0.5); mem = np.full(nA, 0.5); fat = np.zeros(nA)
    last_g = [-1] * nA; last_t = [-1e9] * nA
    use = np.zeros((nA, n_grains))
    events, states = [], []
    # Continuous-time exponential decay of short-lived event impulses.
    # Each tick reads only LAST tick's traces. No instantaneous cross-agent
    # coupling occurs inside the tick, including when n_ev > 1.
    pulse = np.zeros(nA, dtype=np.float64)
    pulse_decay = np.exp(-dt / event_decay_s)

    # Independent reference is measured from an actual uncoupled simulation with
    # the same seed/parameter settings, not guessed from an analytic fixed point.
    # Only used in condition 2: it changes no condition-0/1 behavior. The
    # recursion terminates because condition 0 never requests a reference.
    ref_mem = np.full(nA, 0.5)
    ref_pulse = np.zeros(nA)
    if condition == 2 and reference_mode == "independent" and ch_act != 0 and coupling != 0:
        # A cache is supplied by `study` only. Its lifetime is a single study
        # on a fixed corpus and common model configuration. The reference
        # depends on the seed, memory time and event decay (but not coupling,
        # mode, selection gain or reference centering).
        ref_key = (int(seed), float(tau), float(event_decay_s))
        ref_pair = reference_cache.get(ref_key) if reference_cache is not None else None
        if ref_pair is None:
            ref_prefix = out_prefix + "_independent_reference"
            _, st_ref_path = simulate(corpus_path, dict(cfg, feedback_reference="legacy"), 0, seed, ref_prefix, quiet=True)
            with open(st_ref_path, encoding="utf-8") as f:
                ref_rows = list(csv.DictReader(f, delimiter="\t"))
            burn = max(1, int(0.1 * len(ref_rows)))
            good = ref_rows[burn:] or ref_rows
            ref_mem = np.array([np.mean([float(r[f"mem_{a}"]) for r in good]) for a in AGENTS])
            ref_pulse = np.array([np.mean([float(r[f"pulse_{a}"]) for r in good]) for a in AGENTS])
            for ref_path in (ref_prefix + "_events.tsv", st_ref_path):
                os.remove(ref_path)
            if reference_cache is not None:
                reference_cache[ref_key] = (ref_mem.copy(), ref_pulse.copy())
        else:
            ref_mem, ref_pulse = ref_pair
        if not quiet:
            print("  independent feedback reference mem=" + np.array2string(ref_mem, precision=3) +
                  " pulse=" + np.array2string(ref_pulse, precision=3))
    pos_rates = rmax[rmax > 0]
    pulse_scale = np.where(rmax > 0, np.median(pos_rates) / np.maximum(rmax, 1e-8), 0.0) if pos_rates.size else np.ones(nA)
    pulse_scale = np.clip(pulse_scale, 0.0, 3.0) if pulse_norm else np.ones(nA)

    for t in range(T):
        time = t * dt
        G = float(np.interp(time / dur, traj[:, 0], traj[:, 1]))
        act_p, mem_p, fat_p = act.copy(), mem.copy(), fat.copy()       # synchronous snapshot
        lg_p, lt_p = list(last_g), list(last_t)                        # ... incl. last grain/time
        pulse_p = pulse.copy()
        next_counts = np.zeros(nA, dtype=np.int64)
        fast_inputs = np.zeros(nA, dtype=np.float64)
        slow_inputs = np.zeros(nA, dtype=np.float64)
        u_ext_values = np.zeros(nA, dtype=np.float64)
        for i in order:
            if condition == 1:
                if central_reference == "mean_g":
                    u_ext = coupling * (2 * (G - central_g_mean))
                else:
                    u_ext = coupling * (2 * G - 1)
            elif condition == 2:
                slow_neighbor = (2 * (mem_p - ref_mem) if reference_mode == "independent"
                                 else 2 * mem_p - 1)
                fast_neighbor = (pulse_p - ref_pulse if reference_mode == "independent"
                                 else pulse_p) * pulse_scale
                slow_drive = (ch_act * coupling * float(np.dot(K[i], slow_neighbor))
                              if ch_act != 0.0 else 0.0)
                fast_drive = (ch_act * event_strength * coupling * float(np.dot(K[i], fast_neighbor))
                              if ch_act != 0.0 and event_strength != 0.0 and event_mode != "off" else 0.0)
                fast_inputs[i] = fast_drive
                slow_inputs[i] = slow_drive
                u_ext = ((0.0 if event_mode == "fast_only" else slow_drive) + fast_drive)
            else:
                u_ext = 0.0
            u_ext_values[i] = u_ext
            u = bias[i] + u_ext - cfg["fatigue_gain"] * fat_p[i] + r_noise[i].normal(0, noise_sd)
            act[i] = act_p[i] + (sigmoid(cfg["act_gain"] * u) - act_p[i]) * act_a
            fat[i] = fat_p[i] + (act_p[i] - fat_p[i]) * fat_a
            mem[i] = mem_p[i] + (act_p[i] - mem_p[i]) * mem_a
            lam = rmax[i] * act[i] * dt                               # expected events this tick
            n_ev = max(0, int(poisson.ppf(r_fire[i].random(), lam)))          # ONE uniform per tick (aligned across conditions)
            next_counts[i] = n_ev
            if n_ev:
                offs = np.sort(r_off[i].random(n_ev)) * dt if subtick else np.zeros(n_ev)
                base = -(((F - pref[i]) ** 2) * W[i]).sum(axis=1)
                if condition == 2 and ch_sel and selection_gain:
                    for j in range(nA):
                        if j != i and lg_p[j] >= 0 and time - lt_p[j] <= cfg["social_window"]:
                            base -= ch_sel * selection_gain * coupling * K[i, j] * ((F - F[lg_p[j]]) ** 2).sum(axis=1)
                for off in offs:
                    z = (base - cfg["repeat_penalty"] * use[i]) / temp
                    p = np.exp(z - z.max()); p /= p.sum()
                    g = int(r_sel[i].choice(n_grains, p=p))
                    ent = float(-(p * np.log(p + 1e-12)).sum())
                    use[i] *= 0.9; use[i, g] += 1.0
                    last_g[i], last_t[i] = g, time + off
                    gain = 0.35 + 0.65 * act[i]
                    events.append([condition, seed, t, f"{time + off:.4f}", AGENTS[i], g, f"{gain:.4f}",
                                   f"{pans[i]:.3f}", f"{act[i]:.4f}", f"{mem[i]:.4f}", f"{fat[i]:.4f}",
                                   f"{bias[i]:.3f}", f"{u_ext:.4f}", f"{lam:.4f}", f"{ent:.4f}",
                                   f"{fast_inputs[i]:.4f}"])
        # One-tick delay: today's events become visible to neighbors next tick.
        # Saturating per-tick event impulse: one onset is already meaningful;
        # bursts grow the trace without making its range unbounded.
        pulse = np.minimum(1.0, pulse_p * pulse_decay + (1.0 - np.exp(-next_counts)))
        states.append([f"{time:.3f}", f"{G:.4f}"] + [f"{x:.4f}" for x in act] +
                      [f"{x:.4f}" for x in mem] + [f"{x:.4f}" for x in fat] +
                      [f"{x:.4f}" for x in pulse] + [f"{x:.4f}" for x in fast_inputs] +
                      [f"{x:.4f}" for x in slow_inputs] + [f"{x:.4f}" for x in u_ext_values])

    events.sort(key=lambda e: (e[2], float(e[3]), AGENTS.index(e[4])))   # canonical order: (tick, time, agent)
    ev_path, st_path = out_prefix + "_events.tsv", out_prefix + "_states.tsv"
    os.makedirs(os.path.dirname(os.path.abspath(ev_path)), exist_ok=True)
    with open(ev_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["condition", "seed", "tick", "time", "agent", "grain", "gain", "pan",
                    "act", "mem", "fat", "u_bias", "u_ext", "lam", "sel_entropy",
                    "fast_input"])
        w.writerows(events)
    with open(st_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["time", "G"] + [f"act_{a}" for a in AGENTS] + [f"mem_{a}" for a in AGENTS] +
                   [f"fat_{a}" for a in AGENTS] + [f"pulse_{a}" for a in AGENTS] +
                   [f"fast_{a}" for a in AGENTS] + [f"slow_{a}" for a in AGENTS] +
                   [f"drive_{a}" for a in AGENTS])
        w.writerows(states)
    if not quiet:
        summarize(events, states, dur, condition, seed)
    return ev_path, st_path


def summarize(events, states, dur, condition, seed):
    st = np.array([[float(x) for x in r] for r in states])
    act = st[int(0.1 * len(st)):, 2:5]                      # discard 10% burn-in transient
    counts = [sum(1 for e in events if e[4] == a) for a in AGENTS]
    c = np.corrcoef(act.T) if act.shape[0] >= 2 else np.full((3, 3), np.nan)
    saturation_low = np.mean(act < 0.1, axis=0)
    saturation_high = np.mean(act > 0.9, axis=0)
    sel_ent_per_agent = [float(np.mean([float(e[14]) for e in events if e[4] == a]))
                         if any(e[4] == a for e in events) else float("nan") for a in AGENTS]
    mean_sel_ent = float(np.nanmean(sel_ent_per_agent)) if np.isfinite(sel_ent_per_agent).any() else float("nan")
    drive_values = st[int(0.1 * len(st)):, -3:]
    drive_mean = np.mean(drive_values, axis=0)
    drive_std = np.std(drive_values, axis=0)
    # States layout: time,G,act(3),mem(3),fat(3),pulse(3),fast(3),slow(3),drive(3)
    slow_std = st[int(0.1 * len(st)):, 17:20].std(axis=0)
    fast_std = st[int(0.1 * len(st)):, 14:17].std(axis=0)
    print(f"  cond {condition} seed {seed}: events/s A={counts[0]/dur:.2f} B={counts[1]/dur:.2f} "
          f"C={counts[2]/dur:.2f} | act corr AB={c[0,1]:+.2f} AC={c[0,2]:+.2f} BC={c[1,2]:+.2f} "
          f"| act std A={act[:,0].std():.2f} B={act[:,1].std():.2f} C={act[:,2].std():.2f}")
    print("  saturation act<0.1 A/B/C=" + "/".join(f"{x:.1%}" for x in saturation_low) +
          " | act>0.9 A/B/C=" + "/".join(f"{x:.1%}" for x in saturation_high) +
          f" | agent-balanced mean entropy={mean_sel_ent:.3f} nats")
    print("  entropy A/B/C=" + "/".join(f"{x:.2f}" for x in sel_ent_per_agent) +
          " | drive mean A/B/C=" + "/".join(f"{x:+.2f}" for x in drive_mean) +
          " | drive std A/B/C=" + "/".join(f"{x:.2f}" for x in drive_std) +
          " | slow std A/B/C=" + "/".join(f"{x:.2f}" for x in slow_std) +
          " | fast std A/B/C=" + "/".join(f"{x:.2f}" for x in fast_std))
    if max(float(saturation_high.max()), float(saturation_low.max())) > 0.80:
        print("  WARNING: one or more agents spend >80% of observed time saturated; inspect coupling/network")


# --------------------------------------------------------------------------
# 3. Audio renderer (event log -> WAV)
# --------------------------------------------------------------------------
def render(events_path, corpus_path, source_wav, out_wav, norm="fixed", length_s=None,
           channel="auto", fixed_gain=0.5, rms_target_db=-30.0, fade_ms=4.0, tail_s=0.5,
           render_mode="legacy", sustain=None):
    # v0.1.6: dispatch only. The legacy body below is byte-for-byte the v0.1.5.5
    # renderer (sample-identical output is a selftest golden).
    if render_mode == "sustain":
        return render_sustain(events_path, corpus_path, source_wav, out_wav, norm=norm,
                              length_s=length_s, channel=channel, fixed_gain=fixed_gain,
                              rms_target_db=rms_target_db, tail_s=tail_s,
                              opts=sustain_options(**(sustain or {})))
    if render_mode == "process":
        return render_process(events_path, corpus_path, source_wav, out_wav, norm=norm,
                              length_s=length_s, channel=channel, fixed_gain=fixed_gain,
                              rms_target_db=rms_target_db, tail_s=tail_s,
                              opts=sustain_options(**(sustain or {})))
    if render_mode == "voices":
        return render_voices(events_path, corpus_path, source_wav, out_wav, norm=norm,
                             length_s=length_s, channel=channel, fixed_gain=fixed_gain,
                             rms_target_db=rms_target_db, tail_s=tail_s,
                             opts=sustain_options(**(sustain or {})))
    if render_mode != "legacy":
        raise ValueError("render_mode must be legacy, sustain, voices or process")
    y, sr = load_mono(source_wav, channel)
    se, _ = load_corpus(corpus_path)
    with open(events_path, encoding="utf-8") as f:
        evs = list(csv.DictReader(f, delimiter="\t"))
    if not evs:                                           # a silent system is a legitimate result
        if not length_s:
            length_s = 1.0
            print("  render: empty event log and no --length given — writing 1.0 s of silence")
        os.makedirs(os.path.dirname(os.path.abspath(out_wav)), exist_ok=True)
        sf.write(out_wav, np.zeros((int(length_s * sr), 2)), sr, subtype="FLOAT")
        print(f"  render[silent]: 0 events -> {out_wav}")
        return
    last = max(float(e["time"]) + (se[int(e["grain"])][1] - se[int(e["grain"])][0]) for e in evs)
    total = length_s if length_s else last + tail_s
    out = np.zeros((int((max(total, last) + 1.0) * sr), 2))          # working buffer (trimmed below)
    fade = int(fade_ms / 1000 * sr)
    for e in evs:
        a, b = (int(se[int(e["grain"])][0] * sr), int(se[int(e["grain"])][1] * sr))
        seg = y[a:b].copy()
        k = min(fade, len(seg) // 2)
        if k > 0:
            seg[:k] *= np.linspace(0, 1, k)
            seg[-k:] *= np.linspace(1, 0, k)
        th = (float(e["pan"]) + 1) * np.pi / 4
        s = int(float(e["time"]) * sr)
        out[s:s + len(seg), 0] += seg * float(e["gain"]) * np.cos(th)
        out[s:s + len(seg), 1] += seg * float(e["gain"]) * np.sin(th)
    out = out[:int(total * sr)]                           # equal length across conditions
    peak = np.abs(out).max()
    if norm == "peak" and peak > 0:
        out *= 10 ** (-1 / 20) / peak                     # -1 dBFS peak, per file
        sub = "PCM_24"
    elif norm == "rms":                                   # loudness-matched (blind listening)
        rms = np.sqrt(np.mean(out ** 2)) + 1e-12
        out *= 10 ** (rms_target_db / 20) / rms
        if np.abs(out).max() > 0.98:
            out *= 0.98 / np.abs(out).max()
            print("  render: rms target limited by peak — check loudness matching")
        sub = "PCM_24"
    else:                                                 # fixed: same gain for every file
        out *= fixed_gain
        sub = "FLOAT"                                     # 32-bit float: no clipping, true levels kept
    os.makedirs(os.path.dirname(os.path.abspath(out_wav)), exist_ok=True)
    sf.write(out_wav, out, sr, subtype=sub)
    final_peak = float(np.max(np.abs(out))) if out.size else 0.0
    print(f"  render[{norm}]: {len(evs)} events, pre-gain peak {peak:.3f}, output peak {final_peak:.3f} -> {out_wav}")
    if final_peak > 1.0:
        print(f"  WARNING: output peak {final_peak:.3f} exceeds 1.0; Praat Play/audio hardware may clip despite FLOAT WAV")


# --------------------------------------------------------------------------
# 3b. Sustain-Aware rendering (v0.1.6)
#
# Analytical grain  : corpus.tsv row, unchanged; drives features and selection.
# Rendered event    : [grain start, natural end] of the ORIGINAL source, where the
#                     natural end is found by searching forward from the grain end
#                     until the first of
#                       - a significant new attack (energy rise OR spectral change
#                         at a corpus boundary),
#                       - the envelope falling below a floor relative to the grain,
#                       - max_tail_s,
#                       - the end of the recording.
# Nothing is synthesised: a release envelope is applied only when the source is
# still sounding where the continuation has to stop.
# --------------------------------------------------------------------------
SUSTAIN_DEFAULTS = {
    "max_tail_s": 4.0,             # longest continuation beyond the grain end
    "release_ms": 120.0,           # artificial release when the source is still sounding
    "crossfade_ms": 25.0,          # mid-sustain entries and same-agent handoffs
    "sustain_sensitivity": 0.5,    # 0 = cut readily, 1 = continue readily
    "tail_policy": "fixed",        # fixed: trim at the requested length; extend: let tails finish
    "preserve_tails": 0,           # sustain only: 1 = no same-agent handoff (tails always ring out)
    "evolution_ms": 300.0,         # voices only: crossfade time of a Voice Evolution
    "morph_s": 1.0,                # process only: time for the voice to move to new material
    "articulation": "phrases",     # process only: phrases (agent falls silent) | attacks (source attacks)
    "final_fade_s": 1.0,           # process only: global end-of-file fade, 0 disables
}
_ENV_HOP_S = 0.005
_FAST_WIN_S = 0.010
_SLOW_WIN_S = 0.040
_ABS_FLOOR_DB = -75.0
CLASS_NAMES = ["transient", "sustained", "resonant", "uncertain"]


def sustain_options(**kw):
    o = dict(SUSTAIN_DEFAULTS)
    for k, v in kw.items():
        if k not in SUSTAIN_DEFAULTS:
            raise ValueError("Unknown sustain option: %r" % k)
        if v is not None:
            o[k] = v
    for k in ("max_tail_s", "release_ms", "crossfade_ms", "sustain_sensitivity", "evolution_ms"):
        o[k] = float(o[k])
        if not np.isfinite(o[k]):
            raise ValueError(k + " must be finite")
    if not 0.0 <= o["max_tail_s"] <= 30.0:
        raise ValueError("max_tail_s must be 0..30 s")
    if not 1.0 <= o["release_ms"] <= 2000.0:
        raise ValueError("release_ms must be 1..2000 ms")
    if not 1.0 <= o["crossfade_ms"] <= 500.0:
        raise ValueError("crossfade_ms must be 1..500 ms")
    if not 0.0 <= o["sustain_sensitivity"] <= 1.0:
        raise ValueError("sustain_sensitivity must be 0..1")
    o["final_fade_s"] = float(o["final_fade_s"])
    if not (np.isfinite(o["final_fade_s"]) and 0 <= o["final_fade_s"] <= 10.0):
        raise ValueError("final_fade_s must be 0..10 seconds")
    o["morph_s"] = float(o["morph_s"])
    if not (np.isfinite(o["morph_s"]) and 0.05 <= o["morph_s"] <= 10.0):
        raise ValueError("morph_s must be 0.05..10 s")
    o["articulation"] = str(o["articulation"]).strip().lower()
    if o["articulation"] not in ("phrases", "attacks"):
        raise ValueError("articulation must be phrases or attacks")
    if not 10.0 <= o["evolution_ms"] <= 3000.0:
        raise ValueError("evolution_ms must be 10..3000 ms")
    o["preserve_tails"] = int(o["preserve_tails"])
    if o["preserve_tails"] not in (0, 1):
        raise ValueError("preserve_tails must be 0 or 1")
    o["tail_policy"] = str(o["tail_policy"]).strip().lower()
    if o["tail_policy"] not in ("fixed", "extend"):
        raise ValueError("tail_policy must be fixed or extend")
    return o


def _env_db(y, sr, win_s, hop):
    """RMS envelope in dB, frames centred at k*hop (exact, O(N) via cumulative sum)."""
    n = len(y)
    c = np.concatenate([[0.0], np.cumsum(np.asarray(y, dtype=np.float64) ** 2)])
    centres = np.arange(0, n, hop)
    h = max(1, int(round(win_s * sr / 2)))
    lo = np.clip(centres - h, 0, n)
    hi = np.clip(centres + h, 0, n)
    ms = np.maximum(c[hi] - c[lo], 0.0) / np.maximum(hi - lo, 1)
    return 10.0 * np.log10(ms + 1e-20)


def _frames(x0, x1, hop, nframes):
    """Frame indices whose centres lie in [x0, x1)."""
    k0 = max(0, int(np.ceil(x0 / hop)))
    k1 = min(nframes, int(np.ceil(x1 / hop)))
    return k0, max(k0, k1)


def _spectral_distance(y, sr, tb, win_s=0.06):
    L = int(win_s * sr)
    if tb - L < 0 or tb + L > len(y) or L < 64:
        return 0.0
    nfft = 1 << int(np.ceil(np.log2(L)))
    w = np.hanning(L)
    spec = []
    for seg in (y[tb - L:tb], y[tb:tb + L]):
        m = np.abs(np.fft.rfft(seg * w, n=nfft))
        spec.append(np.log1p(m / (np.mean(m) + 1e-12)))
    p, q = spec
    den = np.linalg.norm(p) * np.linalg.norm(q)
    return float(1.0 - np.dot(p, q) / den) if den > 0 else 0.0


def _logistic(x):
    return 1.0 / (1.0 + np.exp(-np.clip(x, -60, 60)))


def sustain_analysis(y, sr, se, opts):
    """Per-grain rendering metadata. Deterministic, numpy-only, source-bounded.

    Candidate attacks are the corpus grain boundaries (i.e. the onsets that
    built the corpus, plus the even splits of long segments). A boundary is a
    significant attack when the energy rises sharply across it OR the spectrum
    changes at a comparable level. Split boundaries inside one sustained sound
    show neither, so continuation passes through them.
    """
    s = opts["sustain_sensitivity"]
    rise_thr = 4.0 + 8.0 * s            # dB      (8 dB at s = 0.5)
    spec_thr = 0.15 + 0.30 * s          # 1 - cos (0.30 at s = 0.5)
    floor_rel = -(30.0 + 30.0 * s)      # dB below the grain's own peak (-45 at 0.5)
    hop = max(1, int(round(_ENV_HOP_S * sr)))
    fast = _env_db(y, sr, _FAST_WIN_S, hop)
    slow = _env_db(y, sr, _SLOW_WIN_S, hop)
    nfr = len(slow)
    n = len(y)
    starts = (se[:, 0] * sr).astype(int)        # same int() rounding as the legacy renderer
    ends = (se[:, 1] * sr).astype(int)
    G = len(se)
    w = int(0.05 * sr)

    # --- 1. boundary significance ---
    rise = np.zeros(G)
    spec = np.zeros(G)
    sig = np.zeros(G)
    attack = np.zeros(G, dtype=bool)
    for j in range(G):
        tb = starts[j]
        if tb < w:                              # recording start: always an attack
            rise[j], sig[j], attack[j] = np.inf, np.inf, True
            continue
        k0, k1 = _frames(tb - w, tb, hop, nfr)
        m0, m1 = _frames(tb, tb + w, hop, nfr)
        if k1 <= k0 or m1 <= m0:
            continue
        pre, post = float(np.median(fast[k0:k1])), float(np.max(fast[m0:m1]))
        rise[j] = post - pre
        pre_mean = float(np.mean(fast[k0:k1]))
        # Spectral change counts only when real material follows (a sound decaying
        # into the noise floor also changes spectrum, but is not a new event).
        if max(pre_mean, post) > _ABS_FLOOR_DB + 5 and post >= pre_mean - 10.0:
            spec[j] = _spectral_distance(y, sr, tb)
        sig[j] = max(rise[j] / rise_thr, spec[j] / spec_thr)
        attack[j] = sig[j] >= 1.0

    # --- 2. natural end per grain ---
    attack_pos = np.sort(starts[attack])
    guard = int(0.003 * sr)
    max_tail = int(opts["max_tail_s"] * sr)
    out = {k: [] for k in ("ref_db", "nat_end", "reason", "end_rel_db", "release",
                           "t20_s", "slope_db_s", "resid_db", "cls", "p_tr", "p_sus", "p_res")}
    for g in range(G):
        a, b = starts[g], min(ends[g], n)
        ka, kb = _frames(a, max(b, a + 1), hop, nfr)
        ref = float(np.max(slow[ka:kb])) if kb > ka else float(slow[min(ka, nfr - 1)])
        floor_db = max(ref + floor_rel, _ABS_FLOOR_DB)
        # next significant attack at or after the grain end
        i = int(np.searchsorted(attack_pos, b - 1, side="left"))
        t_att = int(attack_pos[i]) if i < len(attack_pos) else None
        # first frame at/after the grain end below the floor
        kb0 = min(int(np.ceil(b / hop)), nfr)
        kl = min(nfr, int(np.ceil(min(n, b + max_tail) / hop)) + 1)
        below = np.nonzero(slow[kb0:kl] < floor_db)[0]
        t_floor = int((kb0 + below[0]) * hop) if below.size else None
        cands = [("max_tail", b + max_tail), ("file_end", n)]
        if t_floor is not None:
            cands.append(("floor", t_floor))
        if t_att is not None:
            cands.append(("attack", max(b, t_att - guard) if t_att > b else b))
        reason, end = min(cands, key=lambda c: (c[1], ["attack", "floor", "max_tail", "file_end"].index(c[0])))
        end = int(min(max(end, b), n))
        # Read levels only from frames whose window lies before the stop point,
        # so the following attack cannot leak into the measurement.
        lead = int(0.5 * _SLOW_WIN_S * sr)
        k_end = min(max(ka, int(max(a, end - lead) // hop)), nfr - 1)
        end_rel = float(slow[k_end] - ref)
        # Natural ending: the source has (nearly) died away at the stop point.
        release = not (reason == "floor" or end_rel <= floor_rel + 6.0 or slow[k_end] <= _ABS_FLOOR_DB + 6)
        # --- 3. soft classification (diagnostic + fade choice) ---
        kp0, kp1 = _frames(a, max(end - lead, a + 1), hop, nfr)
        env = slow[kp0:kp1]
        peak_sample = a
        if env.size:
            pk = int(np.argmax(env))
            peak_sample = int((kp0 + pk) * hop)
            after = env[pk:]
            d20 = np.nonzero(after < ref - 20.0)[0]
            t20 = (d20[0] if d20.size else len(after)) * hop / sr
            if len(after) >= 4:
                tt = np.arange(len(after)) * hop / sr
                A = np.vstack([tt, np.ones_like(tt)]).T
                coef, *_ = np.linalg.lstsq(A, after, rcond=None)
                slope = float(coef[0])
                resid = float(np.std(after - A @ coef))
            else:
                slope, resid = float("nan"), float("nan")
        else:
            t20, slope, resid = 0.0, float("nan"), float("nan")
        L = (end - a) / sr
        p_tr = float(_logistic((0.15 - t20) / 0.04))
        if np.isfinite(slope):
            p_res = float((1.0 if attack[g] else 0.7) * _logistic((t20 - 0.25) / 0.08) *
                          _logistic((-slope - 3.0) / 1.5))
            p_sus = float(_logistic((L - 0.5) / 0.15) * _logistic((6.0 - abs(slope)) / 1.5) *
                          _logistic((4.0 - resid) / 1.0))
        else:
            p_res = p_sus = 0.0
        probs = [p_tr, p_sus, p_res]
        cls = CLASS_NAMES[int(np.argmax(probs))] if max(probs) >= 0.5 else "uncertain"
        out.setdefault("peak", []).append(peak_sample)
        for k, v in (("ref_db", ref), ("nat_end", end), ("reason", reason), ("end_rel_db", end_rel),
                     ("release", release), ("t20_s", t20), ("slope_db_s", slope), ("resid_db", resid),
                     ("cls", cls), ("p_tr", p_tr), ("p_sus", p_sus), ("p_res", p_res)):
            out[k].append(v)
    out.update(start=starts, end=ends, attack_start=attack, rise_db=rise, spec_dist=spec, sig=sig)
    return out


def write_sustain_tsv(path, meta, sr):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["id", "class", "attack_start", "start_sig", "rise_db", "spec_dist",
                    "grain_end_s", "natural_end_s", "tail_s", "end_reason", "end_rel_db",
                    "needs_release", "t20_s", "slope_db_s", "p_transient", "p_sustained", "p_resonant"])
        for g in range(len(meta["start"])):
            sg = meta["sig"][g]
            w.writerow([g, meta["cls"][g], int(meta["attack_start"][g]),
                        "inf" if not np.isfinite(sg) else f"{sg:.3f}",
                        "inf" if not np.isfinite(meta["rise_db"][g]) else f"{meta['rise_db'][g]:.2f}",
                        f"{meta['spec_dist'][g]:.3f}", f"{meta['end'][g] / sr:.6f}",
                        f"{meta['nat_end'][g] / sr:.6f}",
                        f"{max(0, meta['nat_end'][g] - meta['end'][g]) / sr:.4f}",
                        meta["reason"][g], f"{meta['end_rel_db'][g]:.2f}", int(meta["release"][g]),
                        f"{meta['t20_s'][g]:.4f}",
                        "nan" if not np.isfinite(meta["slope_db_s"][g]) else f"{meta['slope_db_s'][g]:.2f}",
                        f"{meta['p_tr'][g]:.3f}", f"{meta['p_sus'][g]:.3f}", f"{meta['p_res'][g]:.3f}"])


def _ramp_in(n, shape):
    x = (np.arange(n) + 0.5) / n
    return np.sin(0.5 * np.pi * x) if shape == "power" else 0.5 - 0.5 * np.cos(np.pi * x)


def _ramp_out(n, shape):
    return _ramp_in(n, shape)[::-1]


def _normalize(out, norm, fixed_gain, rms_target_db):
    """Same three level modes as the legacy renderer (no compression)."""
    peak = np.abs(out).max() if out.size else 0.0
    if norm == "peak" and peak > 0:
        out *= 10 ** (-1 / 20) / peak
        return out, "PCM_24", peak
    if norm == "rms":
        rms = np.sqrt(np.mean(out ** 2)) + 1e-12
        out *= 10 ** (rms_target_db / 20) / rms
        if np.abs(out).max() > 0.98:
            out *= 0.98 / np.abs(out).max()
            print("  render: rms target limited by peak — check loudness matching")
        return out, "PCM_24", peak
    out *= fixed_gain
    return out, "FLOAT", peak


def _max_overlap(intervals):
    pts = sorted([(s, 1) for s, e in intervals if e > s] + [(e, -1) for s, e in intervals if e > s],
                 key=lambda p: (p[0], p[1]))
    cur = best = 0
    for _, d in pts:
        cur += d
        best = max(best, cur)
    return best


def _write_stats(path, stats):
    with open(path, "w", encoding="utf-8") as f:
        for k, v in stats.items():
            f.write(f"{k}={v}\n")


def render_paths(out_wav):
    stem = os.path.splitext(out_wav)[0]
    return stem + "_render.tsv", stem + "_render_stats.txt"


def render_sustain(events_path, corpus_path, source_wav, out_wav, norm="fixed", length_s=None,
                   channel="auto", fixed_gain=0.5, rms_target_db=-30.0, tail_s=0.5,
                   opts=None, meta=None):
    opts = sustain_options(**(opts or {}))
    y, sr = load_mono(source_wav, channel)
    se, _ = load_corpus(corpus_path)
    if meta is None:
        meta = sustain_analysis(y, sr, se, opts)
        write_sustain_tsv(os.path.splitext(corpus_path)[0] + "_sustain.tsv", meta, sr)
    with open(events_path, encoding="utf-8") as f:
        evs = list(csv.DictReader(f, delimiter="\t"))
    ms = lambda v: int(round(v * sr / 1000.0))
    fi_attack, fade_min, nat_fade = ms(2.0), ms(4.0), ms(10.0)
    xf_n, rel_n, rel_tr = ms(opts["crossfade_ms"]), ms(opts["release_ms"]), ms(12.0)

    # ---- 1. event plan: source interval, output position, fades ----
    plan = []
    for idx, e in enumerate(evs):
        g = int(e["grain"])
        a, b = int(se[g][0] * sr), int(se[g][1] * sr)          # identical to the legacy renderer
        end = max(int(meta["nat_end"][g]), b)
        L = end - a
        att = bool(meta["attack_start"][g])
        fi = min(fi_attack if att else xf_n, L // 4)
        protect = max(fi, min(int(0.05 * sr), (b - a) // 2))
        if meta["release"][g]:
            fo_target, ending = (rel_tr if meta["cls"][g] == "transient" else rel_n), "release"
        else:
            fo_target, ending = nat_fade, "natural"
        plan.append(dict(idx=idx, g=g, agent=e["agent"], s=int(float(e["time"]) * sr), a=a, b=b,
                         L=L, fi=fi, fi_shape="raised" if att else "power", protect=protect,
                         fo_target=fo_target, fo_shape="raised", ending=ending,
                         reason=meta["reason"][g], gain=float(e["gain"]), pan=float(e["pan"]),
                         cls=meta["cls"][g], att=att))

    # ---- 2. same-agent handoff: two copies of the SAME source audio must not
    # overlap (comb filtering); different material overlaps freely ----
    n_handoff = 0
    for ag in ([] if opts["preserve_tails"] else AGENTS):
        active = []
        for p in sorted((p for p in plan if p["agent"] == ag), key=lambda p: (p["s"], p["idx"])):
            for q in active:
                q_end = q["s"] + q["L"]
                src_overlap = q["a"] < p["a"] + p["L"] and p["a"] < q["a"] + q["L"]
                if q["s"] < p["s"] < q_end and src_overlap:
                    xf = min(xf_n, q_end - p["s"])
                    q["L"] = p["s"] - q["s"] + xf
                    q["fo_target"], q["fo_shape"], q["ending"], q["fixed_fo"] = xf, "power", "handoff", True
                    n_handoff += 1
            active = [q for q in active if q["s"] + q["L"] > p["s"]] + [p]

    # ---- 3. output-length policy ----
    nat_last = max((p["s"] + p["L"] for p in plan), default=0)
    if opts["tail_policy"] == "extend":
        total_n = max(int(length_s * sr) if length_s else 0, nat_last)
    else:
        total_n = int(length_s * sr) if length_s else nat_last + int(tail_s * sr)
    n_boundary = 0
    for p in plan:
        if p["s"] + p["L"] > total_n:
            p["L"] = max(0, total_n - p["s"])
            p["fo_target"] = rel_tr if p["cls"] == "transient" else rel_n
            p["fo_shape"], p["ending"], p["fixed_fo"] = "raised", "boundary", False
            n_boundary += 1

    # ---- 4. final fade lengths, constrained to the available audio ----
    for p in plan:
        L = p["L"]
        p["fi"] = min(p["fi"], L // 4)
        if p.get("fixed_fo"):
            fo = min(p["fo_target"], L)
        else:
            fo = min(p["fo_target"], max(0, L - p["protect"]))
            fo = max(fo, min(fade_min, L // 2))
        p["fo"] = int(max(0, fo))

    # ---- 5. mix (gain and constant-power pan exactly as legacy) ----
    if not plan:
        os.makedirs(os.path.dirname(os.path.abspath(out_wav)), exist_ok=True)
        sf.write(out_wav, np.zeros((max(total_n, int(sr)), 2)), sr, subtype="FLOAT")
        print(f"  render[sustain,silent]: 0 events -> {out_wav}")
        return
    out = np.zeros((total_n, 2))
    for p in plan:
        L = p["L"]
        if L <= 0:
            continue
        env = np.ones(L)
        if p["fi"] > 0:
            env[:p["fi"]] *= _ramp_in(p["fi"], p["fi_shape"])
        if p["fo"] > 0:
            env[L - p["fo"]:] *= _ramp_out(p["fo"], p["fo_shape"])
        seg = y[p["a"]:p["a"] + L] * env
        th = (p["pan"] + 1) * np.pi / 4
        s = p["s"]
        out[s:s + L, 0] += seg * p["gain"] * np.cos(th)
        out[s:s + L, 1] += seg * p["gain"] * np.sin(th)
    out, sub, pre_peak = _normalize(out, norm, fixed_gain, rms_target_db)
    os.makedirs(os.path.dirname(os.path.abspath(out_wav)), exist_ok=True)
    sf.write(out_wav, out, sr, subtype=sub)

    # ---- 6. diagnostics ----
    final_peak = float(np.max(np.abs(out)))
    rms_db = 20 * np.log10(np.sqrt(np.mean(out ** 2)) + 1e-12)
    tails = np.array([max(0, p["a"] + p["L"] - p["b"]) / sr for p in plan])
    cnt = lambda key, val: sum(1 for p in plan if p[key] == val)
    stats = dict(mode="sustain", preserve_tails=opts["preserve_tails"], events=len(plan), duration_s=f"{total_n / sr:.3f}",
                 max_overlap=_max_overlap([(p["s"], p["s"] + p["L"]) for p in plan]),
                 extended=int(np.sum(tails > 0.001)), natural=cnt("ending", "natural"),
                 release=cnt("ending", "release"), handoff=cnt("ending", "handoff"),
                 boundary=cnt("ending", "boundary"),
                 transient=cnt("cls", "transient"), sustained=cnt("cls", "sustained"),
                 resonant=cnt("cls", "resonant"), uncertain=cnt("cls", "uncertain"),
                 tail_mean_s=f"{tails.mean():.3f}", tail_max_s=f"{tails.max():.3f}",
                 pre_gain_peak=f"{pre_peak:.4f}", peak=f"{final_peak:.4f}", rms_dbfs=f"{rms_db:.2f}",
                 policy=opts["tail_policy"], max_tail_s=opts["max_tail_s"], release_ms=opts["release_ms"],
                 crossfade_ms=opts["crossfade_ms"], sustain_sensitivity=opts["sustain_sensitivity"])
    tsv_path, stats_path = render_paths(out_wav)
    with open(tsv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["event", "time", "agent", "grain", "class", "attack_start", "grain_dur_s",
                    "tail_s", "dur_s", "fade_in_ms", "fade_out_ms", "end_reason", "ending"])
        for p in plan:
            w.writerow([p["idx"], f"{p['s'] / sr:.4f}", p["agent"], p["g"], p["cls"], int(p["att"]),
                        f"{(p['b'] - p['a']) / sr:.4f}", f"{max(0, p['a'] + p['L'] - p['b']) / sr:.4f}",
                        f"{p['L'] / sr:.4f}", f"{1000 * p['fi'] / sr:.2f}", f"{1000 * p['fo'] / sr:.2f}",
                        p["reason"], p["ending"]])
    _write_stats(stats_path, stats)
    print(f"  render[sustain,{norm}]: {len(plan)} events, pre-gain peak {pre_peak:.3f}, "
          f"output peak {final_peak:.3f} -> {out_wav}")
    print(f"  sustain: extended {stats['extended']}/{len(plan)} | natural {stats['natural']} "
          f"release {stats['release']} handoff {stats['handoff']} boundary {stats['boundary']} | "
          f"tail mean {stats['tail_mean_s']} s max {stats['tail_max_s']} s | max overlap {stats['max_overlap']} "
          f"| rms {stats['rms_dbfs']} dBFS | {stats['duration_s']} s")
    print(f"  classes: transient {stats['transient']} sustained {stats['sustained']} "
          f"resonant {stats['resonant']} uncertain {stats['uncertain']}")
    if final_peak > 1.0:
        print(f"  WARNING: output peak {final_peak:.3f} exceeds 1.0; Praat Play/audio hardware may clip despite FLOAT WAV")
    return stats


# --------------------------------------------------------------------------
# 3c. Continuous Voices rendering (v0.1.6.1)
#
# Each agent owns ONE persistent voice: a playhead into the source. The event
# log is read as a stream of decisions, not of attacks:
#   * New Attack : the grain begins at a significant source attack (or the
#                  voice is silent). A new voice starts; the previous voice is
#                  NOT stolen - it rings on to its own natural end.
#   * Evolution  : the grain begins mid-sound and the voice is still sounding.
#                  The playhead moves to the new material through an
#                  evolution_ms crossfade. The entry point is shifted (0..20 ms)
#                  to the lag of maximum correlation with the material being
#                  left (WSOLA-style), and the crossfade gains are compensated
#                  for the measured correlation, so neither phase cancellation
#                  nor a level bump occurs at the join.
#   * Absorbed   : a decision arriving within 10 ms of the previous change of
#                  the same voice; it is logged but moves nothing.
# --------------------------------------------------------------------------
_ALIGN_MAX_S = 0.020
_ALIGN_WIN_S = 0.040
_MIN_XF_S = 0.010


def _xfade_pair(n, rho):
    """Fade-out / fade-in gains whose sum keeps constant power for two signals
    with correlation rho in [0, 1]: rho = 1 gives a raised cosine (amplitude-
    complementary), rho = 0 gives equal power."""
    f = 0.5 - 0.5 * np.cos(np.pi * (np.arange(n) + 0.5) / n)
    r = float(np.clip(rho, 0.0, 1.0))
    norm = np.sqrt((1 - f) ** 2 + f ** 2 + 2 * r * f * (1 - f))
    return (1 - f) / norm, f / norm


def _energy_correction(u, v, g1, g2, fo, fi, sr, block_s=0.005, max_db=6.0):
    """Block-wise gain correction (5 ms blocks, linearly interpolated) that makes
    the crossfade's short-term energy follow the power interpolation of the two
    signals it joins. This removes the dips caused by drifting phase (beating
    decays) that one global correlation cannot capture. Limited to +-max_db:
    a full anti-phase cancellation is not 'repaired' by unbounded gain."""
    n = min(len(u), len(v), len(fo), len(fi))
    if n < 4:
        return np.ones(n)
    b = max(4, int(block_s * sr))
    f = 1.0 - fo[:n] / np.maximum(fo[:n] + fi[:n], 1e-12)          # 0 -> 1 progress
    mix = fo[:n] * g1 * u[:n] + fi[:n] * g2 * v[:n]
    centres, corr = [], []
    for i in range(0, n, b):
        j = min(n, i + b)
        e1 = np.mean((g1 * u[i:j]) ** 2)
        e2 = np.mean((g2 * v[i:j]) ** 2)
        fm = float(np.mean(f[i:j]))
        want = (1 - fm) * e1 + fm * e2
        have = np.mean(mix[i:j] ** 2)
        c = np.sqrt(want / have) if have > 1e-20 and want > 1e-20 else 1.0
        corr.append(float(np.clip(c, 10 ** (-max_db / 20), 10 ** (max_db / 20))))
        centres.append(0.5 * (i + j - 1))
    return np.interp(np.arange(n), centres, corr)


def _best_lag(y, q, a, W, Lmax, limit):
    """Lag in [0, Lmax] of the window y[a+lag : a+lag+W] that best continues
    y[q : q+W]; returns (lag, correlation). Deterministic, exact."""
    W = int(min(W, len(y) - q, limit - a - Lmax))
    if W < 32:
        return 0, 0.0
    u = y[q:q + W]
    nu = np.linalg.norm(u)
    seg = y[a:a + Lmax + W]
    if nu < 1e-9 or len(seg) < W:
        return 0, 0.0
    win = np.lib.stride_tricks.sliding_window_view(seg, W)[:Lmax + 1]
    dots = win @ u
    norms = np.linalg.norm(win, axis=1) * nu
    corr = np.where(norms > 1e-12, dots / np.maximum(norms, 1e-12), 0.0)
    k = int(np.argmax(corr))
    return k, float(corr[k])


def render_voices(events_path, corpus_path, source_wav, out_wav, norm="fixed", length_s=None,
                  channel="auto", fixed_gain=0.5, rms_target_db=-30.0, tail_s=0.5, opts=None, meta=None):
    opts = sustain_options(**(opts or {}))
    y, sr = load_mono(source_wav, channel)
    se, _ = load_corpus(corpus_path)
    if meta is None:
        meta = sustain_analysis(y, sr, se, opts)
        write_sustain_tsv(os.path.splitext(corpus_path)[0] + "_sustain.tsv", meta, sr)
    with open(events_path, encoding="utf-8") as f:
        evs = list(csv.DictReader(f, delimiter="\t"))
    ms = lambda v: int(round(v * sr / 1000.0))
    fi_attack, nat_fade, fade_min = ms(2.0), ms(10.0), ms(4.0)
    xf_entry, rel_n, rel_tr, evo_n = ms(opts["crossfade_ms"]), ms(opts["release_ms"]), ms(12.0), ms(opts["evolution_ms"])
    min_xf, Lmax, Wal = int(_MIN_XF_S * sr), int(_ALIGN_MAX_S * sr), int(_ALIGN_WIN_S * sr)
    n = len(y)

    segs, log = [], []          # a segment = one stretch of one voice playing one source region

    def natural_out_end(sg):
        return sg["s"] + max(0, meta["nat_end"][sg["g"]] - sg["p"])

    for ag in AGENTS:
        agent_ev = sorted([(int(float(e["time"]) * sr), i, e) for i, e in enumerate(evs) if e["agent"] == ag])
        cur, last_change, voice_id = None, -10 ** 12, -1
        ringing = []                    # earlier voices of this agent still sounding (not stolen)
        for k, (t, idx, e) in enumerate(agent_ev):
            g = int(e["grain"])
            a = int(se[g][0] * sr)
            gain, pan = float(e["gain"]), float(e["pan"])
            att = bool(meta["attack_start"][g])
            alive = cur is not None and t < natural_out_end(cur)
            t_next = agent_ev[k + 1][0] if k + 1 < len(agent_ev) else None
            if alive and not att and t - last_change < min_xf:
                log.append(dict(idx=idx, t=t, agent=ag, g=g, action="absorbed", xf=0, lag=0, rho=0.0, seg=None))
                continue
            if att or not alive:
                # New Attack / entry: earlier voices ring on untouched (no voice stealing) -
                # EXCEPT a voice replaying the same source audio: re-exciting the same material
                # is one resonator, and two time-shifted copies of one recording comb-filter.
                end_new = meta["nat_end"][g]
                ringing = [v for v in ringing if v["end"] is None and t < natural_out_end(v)]
                if cur is not None and cur["end"] is None and t < natural_out_end(cur) and cur not in ringing:
                    ringing.append(cur)
                for v in ringing:
                    q_now = v["p"] + (t - v["s"])
                    v_end = meta["nat_end"][v["g"]]
                    if q_now < end_new and a < v_end:          # source intervals still overlap
                        v["end"] = t + max(1, min(xf_entry, natural_out_end(v) - t))
                        v["forced"] = "retrigger"
                ringing = [v for v in ringing if v["end"] is None]
                voice_id += 1
                action = "attack" if att else "entry"
                cur = dict(s=t, p=a, g=g, gain=gain, pan=pan, fi=fi_attack if att else xf_entry,
                           fi_shape="raised" if att else "power", fi_gain=None, fo=None, fo_gain=None,
                           end=None, voice=f"{ag}{voice_id}", cls=meta["cls"][g], att=att)
                segs.append(cur)
                log.append(dict(idx=idx, t=t, agent=ag, g=g, action=action, xf=0, lag=0, rho=0.0, seg=cur))
                last_change = t
                continue
            # Evolution: move the playhead of the sounding voice to the new material.
            q = cur["p"] + (t - cur["s"])                       # source position being played now
            room_old = natural_out_end(cur) - t                 # old material still available
            room_new = meta["nat_end"][g] - a - Lmax
            xf = min(evo_n, room_old, max(room_new, 0))
            if t_next is not None:
                xf = min(xf, t_next - t)
            if xf < min_xf:
                xf = min(min_xf, max(room_old, 0))
            lag, rho = _best_lag(y, q, a, min(Wal, max(xf, 32)), Lmax, meta["nat_end"][g])
            fo_gain, fi_gain = _xfade_pair(max(1, xf), rho)
            if xf >= 4 and q + xf <= n and a + lag + xf <= n:
                c = _energy_correction(y[q:q + xf], y[a + lag:a + lag + xf], cur["gain"], gain,
                                       fo_gain, fi_gain, sr)
                fo_gain, fi_gain = fo_gain * c, fi_gain * c
            cur["end"] = t + xf
            cur["fo"], cur["fo_gain"] = xf, fo_gain
            nxt = dict(s=t, p=a + lag, g=g, gain=gain, pan=pan, fi=xf, fi_shape="corr", fi_gain=fi_gain,
                       fo=None, fo_gain=None, end=None, voice=cur["voice"], cls=meta["cls"][g], att=False)
            segs.append(nxt)
            log.append(dict(idx=idx, t=t, agent=ag, g=g, action="evolution", xf=xf, lag=lag, rho=rho, seg=nxt))
            cur, last_change = nxt, t

    # natural endings (segments not replaced by an evolution)
    for sg in segs:
        if sg["end"] is None:
            sg["end"] = natural_out_end(sg)
            sg["ending"] = "release" if meta["release"][sg["g"]] else "natural"
        elif sg.get("forced") == "retrigger":
            sg["ending"] = "retrigger"
            sg["fo"], sg["fo_gain"] = sg["end"] - sg["s"], None     # fade over the whole remaining overlap
        else:
            sg["ending"] = "evolution"
    nat_last = max((sg["end"] for sg in segs), default=0)
    if opts["tail_policy"] == "extend":
        total_n = max(int(length_s * sr) if length_s else 0, nat_last)
    else:
        total_n = int(length_s * sr) if length_s else nat_last + int(tail_s * sr)
    for sg in segs:
        if sg["end"] > total_n:
            sg["end"], sg["ending"], sg["fo"], sg["fo_gain"] = total_n, "boundary", None, None
    # final fade lengths
    for sg in segs:
        L = max(0, sg["end"] - sg["s"])
        sg["L"] = L
        if sg["fi_gain"] is not None:
            sg["fi"] = min(sg["fi"], L)
            sg["fi_gain"] = sg["fi_gain"][:sg["fi"]]
        else:
            sg["fi"] = min(sg["fi"], L // 4)
        if sg["ending"] == "retrigger":
            sg["fo"] = int(min(xf_entry, L))
        elif sg["fo_gain"] is None:
            tgt = nat_fade if sg["ending"] == "natural" else (rel_tr if sg["cls"] == "transient" else rel_n)
            fo = min(tgt, max(0, L - sg["fi"]))
            sg["fo"] = int(max(fo, min(fade_min, L // 2)))
        else:
            sg["fo"] = min(sg["fo"], L)
            sg["fo_gain"] = sg["fo_gain"][len(sg["fo_gain"]) - sg["fo"]:]

    # mix
    out = np.zeros((max(total_n, 1), 2))
    for sg in segs:
        L = sg["L"]
        if L <= 0:
            continue
        L = min(L, n - sg["p"])                                   # never read past the recording
        env = np.ones(L)
        fi = min(sg["fi"], L)
        if fi > 0:
            env[:fi] *= sg["fi_gain"][:fi] if sg["fi_gain"] is not None else _ramp_in(fi, sg["fi_shape"])
        fo = min(sg["fo"], L)
        if fo > 0:
            env[L - fo:] *= (sg["fo_gain"][len(sg["fo_gain"]) - fo:] if sg["fo_gain"] is not None
                             else _ramp_out(fo, "power" if sg["ending"] == "retrigger" else "raised"))
        seg = y[sg["p"]:sg["p"] + L] * env
        th = (sg["pan"] + 1) * np.pi / 4
        s0 = sg["s"]
        out[s0:s0 + L, 0] += seg * sg["gain"] * np.cos(th)
        out[s0:s0 + L, 1] += seg * sg["gain"] * np.sin(th)
    out, sub, pre_peak = _normalize(out, norm, fixed_gain, rms_target_db)
    os.makedirs(os.path.dirname(os.path.abspath(out_wav)), exist_ok=True)
    sf.write(out_wav, out, sr, subtype=sub)

    # diagnostics
    final_peak = float(np.max(np.abs(out)))
    rms_db = 20 * np.log10(np.sqrt(np.mean(out ** 2)) + 1e-12)
    voices = {}
    for sg in segs:
        v = voices.setdefault(sg["voice"], [sg["s"], sg["s"] + sg["L"]])
        v[0], v[1] = min(v[0], sg["s"]), max(v[1], sg["s"] + sg["L"])
    vdur = np.array([(b - a) / sr for a, b in voices.values()]) if voices else np.zeros(1)
    evo = [r for r in log if r["action"] == "evolution"]
    cnt = lambda act: sum(1 for r in log if r["action"] == act)
    stats = dict(mode="voices", events=len(log), attacks=cnt("attack"), evolutions=cnt("evolution"),
                 entries=cnt("entry"), absorbed=cnt("absorbed"), voices=len(voices),
                 retrigger=sum(1 for sg in segs if sg["ending"] == "retrigger"),
                 voice_mean_s=f"{vdur.mean():.3f}", voice_max_s=f"{vdur.max():.3f}",
                 evolution_rho_mean=f"{np.mean([r['rho'] for r in evo]) if evo else 0:.3f}",
                 duration_s=f"{total_n / sr:.3f}",
                 max_overlap=_max_overlap([(sg["s"], sg["s"] + sg["L"]) for sg in segs]),
                 release=sum(1 for sg in segs if sg["ending"] in ("release", "boundary")),
                 pre_gain_peak=f"{pre_peak:.4f}", peak=f"{final_peak:.4f}", rms_dbfs=f"{rms_db:.2f}",
                 policy=opts["tail_policy"], evolution_ms=opts["evolution_ms"], max_tail_s=opts["max_tail_s"],
                 release_ms=opts["release_ms"], crossfade_ms=opts["crossfade_ms"],
                 sustain_sensitivity=opts["sustain_sensitivity"])
    tsv_path, stats_path = render_paths(out_wav)
    with open(tsv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["event", "time", "agent", "grain", "action", "voice", "class", "dur_s",
                    "xfade_ms", "lag_ms", "rho", "src_s", "ending"])
        for r in sorted(log, key=lambda r: r["idx"]):
            sg = r["seg"]
            w.writerow([r["idx"], f"{r['t'] / sr:.4f}", r["agent"], r["g"], r["action"],
                        sg["voice"] if sg else "", meta["cls"][r["g"]],
                        f"{sg['L'] / sr:.4f}" if sg else "0.0000", f"{1000 * r['xf'] / sr:.2f}",
                        f"{1000 * r['lag'] / sr:.2f}", f"{r['rho']:.3f}",
                        f"{sg['p'] / sr:.6f}" if sg else "", sg["ending"] if sg else "absorbed"])
    _write_stats(stats_path, stats)
    print(f"  render[voices,{norm}]: {len(log)} events, pre-gain peak {pre_peak:.3f}, "
          f"output peak {final_peak:.3f} -> {out_wav}")
    print(f"  voices: attacks {stats['attacks']} evolutions {stats['evolutions']} entries {stats['entries']} "
          f"absorbed {stats['absorbed']} retrigger {stats['retrigger']} | {stats['voices']} voices, mean {stats['voice_mean_s']} s "
          f"max {stats['voice_max_s']} s | evolution rho {stats['evolution_rho_mean']} | "
          f"max overlap {stats['max_overlap']} | rms {stats['rms_dbfs']} dBFS | {stats['duration_s']} s")
    if final_peak > 1.0:
        print(f"  WARNING: output peak {final_peak:.3f} exceeds 1.0; Praat Play/audio hardware may clip despite FLOAT WAV")
    return stats


# --------------------------------------------------------------------------
# 3d. Persistent Sonic Processes (v0.1.7)
#
# Agent decision -> update of a persistent sound process (not a new sound).
#   * Voice persistence  : an agent's voice lasts a whole PHRASE. A phrase ends only
#     when the agent falls silent for much longer than its own current firing rate
#     predicts (gap > 4 x expected interval from the event's `lam`, and >= 0.3 s),
#     or - with articulation=attacks - when it selects a grain that starts at a
#     source attack. Selecting an attack-marked grain inside a phrase does NOT re-attack:
#     the new material enters after its own attack.
#   * Continuous transformation : the voice is a weighted mixture of "material
#     streams". A decision only changes which stream the mixture is moving towards;
#     the weights follow a one-pole glide whose time constant is morph_s / 3 and is
#     independent of how often decisions arrive. A decision whose material overlaps
#     a stream already in the mixture re-uses that stream (no copy, no comb filter).
#   * Extension beyond the segment : while the phrase lasts, a stream that reaches
#     the natural end of its material loops a window at that end (correlation-aligned,
#     energy-preserving jumps), so sustained material can last as long as the phrase.
#     When the phrase ends, looping stops and every stream plays to its natural end.
#   With one stream and no loop, the voice output IS the source, sample for sample.
# --------------------------------------------------------------------------
_BLOCK_S = 0.010
_PHRASE_FACTOR = 4.0
_PHRASE_MIN_GAP_S = 0.30
_LOOP_LEN_S = 0.75
_LOOP_MIN_S = 0.15
_JUMP_XF_S = 0.080
_JUMP_CANDIDATES = 6
_ATTACK_SKIP_S = 0.020
_W_EPS = 1e-3
_REUSE_S = 0.6


def _stream(y, sr, p0, n_out, region, loop_until, rng, xj_max, allow_loop=True, nat_end=None, slope_db_s=0.0):
    """Render one material stream: continuous reading from p0; while out offset <
    loop_until it loops `region` (crossfaded, correlation-aligned jumps); after that
    it plays on to the material's natural end and stops. Returns (signal, n_jumps, natural_len)."""
    out = np.zeros(n_out)
    r0, r1 = region
    nat_end = r1 if nat_end is None else max(nat_end, r1)
    loopable = allow_loop and (r1 - r0) >= int(_LOOP_MIN_S * sr)
    xj = int(min(xj_max, (r1 - r0) // 4)) if loopable else 0
    pieces = []                                   # (out_start, src_start, length, rho)
    o, p, rho, jumps = 0, int(p0), 1.0, 0
    while o < n_out and p < nat_end:
        if not loopable or o >= loop_until:
            L = min(n_out - o, nat_end - p)
            pieces.append((o, p, L, rho))
            o += L
            break
        run = (r1 - xj) - p                       # play until one crossfade before the end
        if run <= 0:
            run = 1
        if o + run >= loop_until or o + run >= n_out:
            # no further jump needed before looping stops / the stream is no longer heard
            L = min(n_out - o, nat_end - p)
            pieces.append((o, p, L, rho))
            o += L
            break
        pieces.append((o, p, run + xj, rho))
        span = max(1, int(0.3 * (r1 - r0)) - 2 * xj)
        best = None
        for dest in r0 + rng.integers(0, span, size=_JUMP_CANDIDATES):     # deterministic candidates
            lag, rh = _best_lag(y, p + run, int(dest), min(int(_ALIGN_WIN_S * sr), xj), int(_ALIGN_MAX_S * sr), r1)
            if best is None or rh > best[1]:
                best = (int(dest) + lag, rh)
        o, p, rho, jumps = o + run, best[0], best[1], jumps + 1
    natural_len = 0
    for k, (os_, ps, L, rh) in enumerate(pieces):
        L = int(min(L, n_out - os_, len(y) - ps))
        if L <= 0:
            continue
        seg = y[ps:ps + L].copy()
        if k > 0 and slope_db_s < 0:
            # Held decay: flatten the measured decay slope inside the loop so the window
            # holds the level of its end point instead of repeating a decay sawtooth.
            pos = np.arange(ps, ps + L)
            db = np.clip(slope_db_s * np.maximum(r1 - pos, 0) / sr, -12.0, 0.0)
            seg *= 10 ** (db / 20.0)
        if k > 0 and xj > 0:                      # fade-in of a jump destination
            fo, fi = _xfade_pair(xj, rh)
            prev = pieces[k - 1]
            u = y[prev[1] + prev[2] - xj: prev[1] + prev[2]]
            c = _energy_correction(u, y[ps:ps + xj], 1.0, 1.0, fo, fi, sr) if len(u) == xj and L >= xj else np.ones(xj)
            m = min(xj, L)
            seg[:m] *= (fi * c)[:m]
        if k + 1 < len(pieces) and xj > 0:        # fade-out into the next jump
            nxt = pieces[k + 1]
            fo, fi = _xfade_pair(xj, nxt[3])
            v = y[nxt[1]:nxt[1] + xj]
            c = _energy_correction(y[ps + L - xj:ps + L], v, 1.0, 1.0, fo, fi, sr) if len(v) == xj and L >= xj else np.ones(xj)
            m = min(xj, L)
            seg[L - m:] *= (fo * c)[xj - m:]
        out[os_:os_ + L] += seg
        natural_len = max(natural_len, os_ + L)
    return out, jumps, natural_len


def render_process(events_path, corpus_path, source_wav, out_wav, norm="fixed", length_s=None,
                   channel="auto", fixed_gain=0.5, rms_target_db=-30.0, tail_s=0.5, opts=None, meta=None):
    opts = sustain_options(**(opts or {}))
    y, sr = load_mono(source_wav, channel)
    se, _ = load_corpus(corpus_path)
    if meta is None:
        meta = sustain_analysis(y, sr, se, opts)
        write_sustain_tsv(os.path.splitext(corpus_path)[0] + "_sustain.tsv", meta, sr)
    with open(events_path, encoding="utf-8") as f:
        evs = list(csv.DictReader(f, delimiter="\t"))
    n = len(y)
    B = max(1, int(round(_BLOCK_S * sr)))
    ms = lambda v: int(round(v * sr / 1000.0))
    fi_attack, xf_entry, rel_n, nat_fade = ms(2.0), ms(opts["crossfade_ms"]), ms(opts["release_ms"]), ms(10.0)
    a_w = 1.0 - np.exp(-_BLOCK_S / (opts["morph_s"] / 3.0))       # weight glide per block
    a_g = 1.0 - np.exp(-_BLOCK_S / 0.10)                          # gain glide per block (0.1 s)
    seed = int(evs[0]["seed"]) if evs else 0
    dt_tick = 0.1

    # ---- 1. phrases per agent ----
    phrases = []
    for ai, ag in enumerate(AGENTS):
        ev = sorted([(int(float(e["time"]) * sr), i, e) for i, e in enumerate(evs) if e["agent"] == ag])
        cur = None
        for k, (t, idx, e) in enumerate(ev):
            g = int(e["grain"])
            new = cur is None
            if not new:
                lam = max(float(ev[k - 1][2]["lam"]), 1e-6)
                expected = dt_tick / lam                                   # mean interval at that activity
                gap = (t - ev[k - 1][0]) / sr
                if gap > max(_PHRASE_MIN_GAP_S, _PHRASE_FACTOR * expected):
                    new = True
                if opts["articulation"] == "attacks" and meta["attack_start"][g]:
                    new = True
            if new:
                cur = dict(agent=ag, ai=ai, pan=float(e["pan"]), decisions=[], id=f"{ag}{len([p for p in phrases if p['agent'] == ag])}")
                phrases.append(cur)
            cur["decisions"].append((t, idx, g, float(e["gain"])))

    # ---- 2. per phrase: streams, weights, gain, render ----
    nat_last = 0
    rendered, log, stats_acc = [], [], dict(streams=0, reuse=0, jumps=0, max_streams=0)
    for ph in phrases:
        dec = ph["decisions"]
        t0 = dec[0][0]
        t_last = dec[-1][0]
        rng = np.random.default_rng([seed, ph["ai"], len(rendered)])
        streams = []                                   # dict(g, p0, region, created)
        timeline = []                                  # (t, stream index, gain) per decision
        for j, (t, idx, g, gain) in enumerate(dec):
            a = int(se[g][0] * sr)
            end = max(int(meta["nat_end"][g]), int(se[g][1] * sr))
            hit, cur_q = None, None
            for si, st in enumerate(streams):
                # reuse only when the decision points (within 0.6 s) at where this stream is
                # reading NOW; an earlier or later part of the same sound is new material.
                q = st["p0"] + (t - st["created"])
                if q >= st["region"][1]:
                    q = (st["region"][0] + st["region"][1]) // 2       # looping: inside the window
                if si == timeline[-1][1] if timeline else False:
                    cur_q = (si, q)
                if abs(q - a) <= int(_REUSE_S * sr) and q < end:
                    hit = si
                    break
            if hit is None:
                if j == 0:
                    p0 = a                                         # articulation keeps its attack
                else:
                    skip = meta["peak"][g] + int(_ATTACK_SKIP_S * sr) if meta["attack_start"][g] else a
                    p0 = a if skip >= end - int(_LOOP_MIN_S * sr) else skip
                    if cur_q is not None:
                        # same-sound transitions enter in phase with the stream being left
                        cs = streams[cur_q[0]]
                        if p0 < cs["end"] and end > cs["p0"]:
                            lag, _ = _best_lag(y, cur_q[1], p0, int(_ALIGN_WIN_S * sr), int(_ALIGN_MAX_S * sr), end)
                            p0 += lag
                # loop window: the stretch ending about 12 dB below the material's peak
                # (the sustain of a tone, the body of a resonance), not its dying end.
                l1 = min(end, meta["peak"][g] + int(0.6 * meta["t20_s"][g] * sr))   # about -12 dB
                l1 = min(end, max(l1, p0 + int(_LOOP_MIN_S * sr)))
                r0 = max(p0, l1 - int(_LOOP_LEN_S * sr))
                sl = meta["slope_db_s"][g]
                streams.append(dict(g=g, p0=p0, region=(r0, l1), end=end, created=t, cls=meta["cls"][g],
                                    slope=float(sl) if np.isfinite(sl) and sl < 0 else 0.0))
                hit = len(streams) - 1
                role = "articulation" if j == 0 else "new_material"
                stats_acc["streams"] += 1
            else:
                role = "reuse"
                stats_acc["reuse"] += 1
            timeline.append((t, hit, gain))
            log.append(dict(idx=idx, t=t, agent=ph["agent"], g=g, role=role, voice=ph["id"], stream=hit))
        # voice end after the phrase: every stream plays to its natural end, no looping
        nat_end_out = []
        for st in streams:
            q_last = st["p0"] + (t_last - st["created"])
            if q_last >= st["region"][1]:                # was looping: at most a loop window, then the tail
                remaining = st["end"] - st["region"][0]
            else:
                remaining = st["end"] - max(q_last, st["p0"])
            nat_end_out.append(t_last + max(0, remaining))
        v_end = max(nat_end_out + [t_last + 1])
        nb = int(np.ceil((v_end - t0) / B)) + 1
        # block-wise weights and gain (independent of decision density)
        W = np.zeros((len(streams), nb))
        G = np.zeros(nb)
        w = np.zeros(len(streams))
        w[timeline[0][1]] = 1.0
        gcur, k = timeline[0][2], 0
        target, gtarget = timeline[0][1], timeline[0][2]
        for b in range(nb):
            tb = t0 + b * B
            while k < len(timeline) and timeline[k][0] <= tb:
                target, gtarget = timeline[k][1], timeline[k][2]
                k += 1
            onehot = np.zeros(len(streams))
            onehot[target] = 1.0
            w += (onehot - w) * a_w
            w[w < _W_EPS] = 0.0
            gcur += (gtarget - gcur) * a_g
            W[:, b], G[b] = w, gcur
        stats_acc["max_streams"] = max(stats_acc["max_streams"], int(np.max(np.sum(W > 0, axis=0))))
        n_out = nb * B
        voice = np.zeros(n_out)
        xs = np.arange(n_out)
        bc = np.arange(nb) * B
        sw = np.maximum(W.sum(axis=0), 1e-12)
        Wn = W / sw                                         # linear mixture weights, sum 1
        want = np.zeros(nb)                                 # power interpolation of the streams
        for si, st in enumerate(streams):
            off = st["created"] - t0
            if off >= n_out:
                continue
            active = np.nonzero(W[si] > 0)[0]
            if active.size == 0:
                continue
            length = min(n_out - off, (active[-1] + 1) * B - off + B)
            if length <= 0:
                continue
            sig, jumps, nlen = _stream(y, sr, st["p0"], length, st["region"], t_last - st["created"],
                                       rng, int(_JUMP_XF_S * sr), allow_loop=st["cls"] != "transient",
                                       nat_end=st["end"], slope_db_s=st["slope"])
            stats_acc["jumps"] += jumps
            if 0 < nlen < length:                       # natural end of the material: fade
                fo = min(rel_n if meta["release"][st["g"]] else nat_fade, nlen // 2)
                if fo > 0:
                    sig[nlen - fo:nlen] *= _ramp_out(fo, "raised")
            wcurve = np.interp(xs[off:off + length], bc, Wn[si])
            voice[off:off + length] += sig * wcurve
            full = np.zeros(n_out)
            full[off:off + length] = sig
            e_blk = np.mean(full[:nb * B].reshape(nb, B) ** 2, axis=1)
            want += Wn[si] * e_blk
        # Energy-preserving mixture: correlated streams (same sound) add in amplitude,
        # unrelated ones in power; a block-wise correction (+-6 dB) keeps the voice at the
        # power interpolation of its streams either way.
        have = np.mean(voice[:nb * B].reshape(nb, B) ** 2, axis=1)
        corr = np.where((have > 1e-20) & (want > 1e-20), np.sqrt(want / np.maximum(have, 1e-20)), 1.0)
        corr = np.clip(corr, 0.5, 2.0)
        voice *= np.interp(xs, bc + B // 2, corr)
        voice *= np.interp(xs, bc, G)
        # phrase entry
        g0 = dec[0][2]
        fi = min(fi_attack if meta["attack_start"][g0] else xf_entry, n_out // 4)
        if fi > 0:
            voice[:fi] *= _ramp_in(fi, "raised" if meta["attack_start"][g0] else "power")
        nz = np.nonzero(np.abs(voice) > 0)[0]
        v_len = int(nz[-1] + 1) if nz.size else 0
        ph.update(t0=t0, voice=voice[:v_len], first=dec[0][2], streams=streams)
        rendered.append(ph)
        nat_last = max(nat_last, t0 + v_len)

    # ---- 3. same-material re-articulation of one agent = one resonator ----
    n_retrig = 0
    for ag in AGENTS:
        own = sorted([p for p in rendered if p["agent"] == ag], key=lambda p: p["t0"])
        for i in range(1, len(own)):
            new = own[i]
            a_new = int(se[new["first"]][0] * sr)
            e_new = int(meta["nat_end"][new["first"]])
            for old in own[:i]:
                if old["t0"] + len(old["voice"]) <= new["t0"]:
                    continue
                if any(a_new < st["end"] and st["p0"] < e_new for st in old["streams"]):
                    cut = new["t0"] - old["t0"]
                    xf = min(xf_entry, len(old["voice"]) - cut)
                    if xf > 0:
                        old["voice"][cut:cut + xf] *= _ramp_out(xf, "power")
                    old["voice"] = old["voice"][:cut + max(xf, 0)]
                    n_retrig += 1

    # ---- 4. output length policy and mix ----
    if opts["tail_policy"] == "extend":
        total_n = max(int(length_s * sr) if length_s else 0, nat_last)
    else:
        total_n = int(length_s * sr) if length_s else nat_last + int(tail_s * sr)
    out = np.zeros((max(total_n, 1), 2))
    n_boundary = 0
    for ph in rendered:
        v = ph["voice"]
        s0 = ph["t0"]
        if s0 >= total_n or len(v) == 0:
            continue
        if s0 + len(v) > total_n:
            v = v[:total_n - s0].copy()
            fo = min(rel_n, len(v) // 2)
            if fo > 0:
                v[len(v) - fo:] *= _ramp_out(fo, "raised")
            n_boundary += 1
        th = (ph["pan"] + 1) * np.pi / 4
        out[s0:s0 + len(v), 0] += v * np.cos(th)
        out[s0:s0 + len(v), 1] += v * np.sin(th)
        ph["out_len"] = len(v)
    # The per-voice release above applies ONLY to voices truncated at the output
    # boundary. A voice ending exactly at its natural end, or a fixed-duration
    # output containing a sustained mix, otherwise has no guaranteed musical
    # fade. Fade the finished stereo mix regardless of why the render stops.
    # This is post-render only: it cannot alter decisions or interactions.
    fade_n = min(len(out), int(round(opts["final_fade_s"] * sr)))
    if fade_n >= 2:
        out[-fade_n:] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fade_n)))[:, None]
    elif fade_n == 1:
        out[-1, :] = 0.0
    out, sub, pre_peak = _normalize(out, norm, fixed_gain, rms_target_db)
    os.makedirs(os.path.dirname(os.path.abspath(out_wav)), exist_ok=True)
    sf.write(out_wav, out, sr, subtype=sub)

    # ---- 5. diagnostics ----
    final_peak = float(np.max(np.abs(out)))
    rms_db = 20 * np.log10(np.sqrt(np.mean(out ** 2)) + 1e-12)
    vl = np.array([ph.get("out_len", 0) / sr for ph in rendered]) if rendered else np.zeros(1)
    dpv = np.array([len(ph["decisions"]) for ph in rendered]) if rendered else np.zeros(1)
    stats = dict(mode="process", events=len(log), voices=len(rendered),
                 articulations=sum(1 for r in log if r["role"] == "articulation"),
                 new_material=sum(1 for r in log if r["role"] == "new_material"),
                 reuse=stats_acc["reuse"], loop_jumps=stats_acc["jumps"], retrigger=n_retrig, boundary=n_boundary,
                 max_streams=stats_acc["max_streams"], decisions_per_voice=f"{dpv.mean():.2f}",
                 voice_mean_s=f"{vl.mean():.3f}", voice_max_s=f"{vl.max():.3f}",
                 duration_s=f"{total_n / sr:.3f}",
                 max_overlap=_max_overlap([(ph["t0"], ph["t0"] + ph.get("out_len", 0)) for ph in rendered]),
                 pre_gain_peak=f"{pre_peak:.4f}", peak=f"{final_peak:.4f}", rms_dbfs=f"{rms_db:.2f}",
                                   policy=opts["tail_policy"], morph_s=opts["morph_s"], articulation=opts["articulation"],
                  final_fade_s=f"{fade_n / sr:.4f}",
                 max_tail_s=opts["max_tail_s"], release_ms=opts["release_ms"], crossfade_ms=opts["crossfade_ms"],
                 sustain_sensitivity=opts["sustain_sensitivity"])
    # per-decision log; dur_s = time until the next decision of the same voice (or the voice's end)
    nxt = {}
    by_voice = {}
    for r in log:
        by_voice.setdefault(r["voice"], []).append(r)
    for ph in rendered:
        rows = sorted(by_voice.get(ph["id"], []), key=lambda r: r["t"])
        end = ph["t0"] + ph.get("out_len", 0)
        for i, r in enumerate(rows):
            nxt[r["idx"]] = (rows[i + 1]["t"] if i + 1 < len(rows) else end) - r["t"]
    tsv_path, stats_path = render_paths(out_wav)
    with open(tsv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["event", "time", "agent", "grain", "role", "voice", "stream", "class", "dur_s"])
        for r in sorted(log, key=lambda r: r["idx"]):
            w.writerow([r["idx"], f"{r['t'] / sr:.4f}", r["agent"], r["g"], r["role"], r["voice"], r["stream"],
                        meta["cls"][r["g"]], f"{max(0, nxt.get(r['idx'], 0)) / sr:.4f}"])
    _write_stats(stats_path, stats)
    print(f"  render[process,{norm}]: {len(log)} decisions, pre-gain peak {pre_peak:.3f}, "
          f"output peak {final_peak:.3f} -> {out_wav}")
    print(f"  process: {stats['voices']} voices ({stats['decisions_per_voice']} decisions/voice, mean "
          f"{stats['voice_mean_s']} s, max {stats['voice_max_s']} s) | new material {stats['new_material']} "
          f"reuse {stats['reuse']} | loop jumps {stats['loop_jumps']} | retrigger {n_retrig} | "
          f"max overlap {stats['max_overlap']} | rms {stats['rms_dbfs']} dBFS | {stats['duration_s']} s")
    if final_peak > 1.0:
        print(f"  WARNING: output peak {final_peak:.3f} exceeds 1.0; Praat Play/audio hardware may clip despite FLOAT WAV")
    return stats


def legacy_diagnostics(events_path, corpus_path, out_wav):
    """Same diagnostics file for a legacy render, computed AFTER rendering from the
    written audio, so the legacy synthesis path itself is untouched."""
    se, _ = load_corpus(corpus_path)
    out, sr = sf.read(out_wav, always_2d=True)
    with open(events_path, encoding="utf-8") as f:
        evs = list(csv.DictReader(f, delimiter="\t"))
    iv = [(int(float(e["time"]) * sr), int(float(e["time"]) * sr) +
           int(se[int(e["grain"])][1] * sr) - int(se[int(e["grain"])][0] * sr)) for e in evs]
    total = len(out)
    iv = [(s, min(e, total)) for s, e in iv]
    stats = dict(mode="legacy", events=len(evs), duration_s=f"{total / sr:.3f}",
                 max_overlap=_max_overlap(iv), extended=0, natural=0, release=0, handoff=0, boundary=0,
                 peak=f"{float(np.max(np.abs(out))) if out.size else 0.0:.4f}",
                 rms_dbfs=f"{20 * np.log10(np.sqrt(np.mean(out ** 2)) + 1e-12) if out.size else -240:.2f}")
    _write_stats(render_paths(out_wav)[1], stats)
    print(f"  legacy: max overlap {stats['max_overlap']} | rms {stats['rms_dbfs']} dBFS | {stats['duration_s']} s")
    return stats


# --------------------------------------------------------------------------
# 4. Demo source (synthetic percussion loop, for testing without a recording)
# --------------------------------------------------------------------------
def make_demo(path, sr=44100, bpm=120, bars=4, seed=7):
    rng = np.random.default_rng(seed)
    step = 60.0 / bpm / 4
    n = int(bars * 16 * step * sr) + sr
    y = np.zeros(n)

    def add(t, x):
        s = int(t * sr); e = min(n, s + len(x))
        if e > s:
            y[s:e] += x[:e - s]

    def env(d, p=4.0):
        t = np.arange(int(d * sr)) / sr
        return np.exp(-p * t / d)

    def noise(d):
        return rng.standard_normal(int(d * sr))

    for b in range(bars):
        for k in range(16):
            t = (b * 16 + k) * step
            if k in (0, 6, 8, 14):                                          # kick
                d = 0.25; tt = np.arange(int(d * sr)) / sr
                add(t, np.sin(2 * np.pi * np.cumsum(45 + 90 * np.exp(-tt * 25)) / sr) * env(d, 5) * 0.9)
            if k in (4, 12):                                                # snare
                d = 0.18 + 0.04 * rng.random(); tt = np.arange(int(d * sr)) / sr
                add(t, (np.diff(noise(d), prepend=0) * 0.6 + np.sin(2 * np.pi * 190 * tt) * 0.5) * env(d, 5) * 0.5)
            if k % 2 == 0:                                                  # hats
                d = 0.2 if k == 10 else 0.04
                add(t, np.diff(noise(d), prepend=0) * env(d, 6) * (0.25 + 0.15 * rng.random()))
            if k == 10 and b % 2 == 1:                                      # tom
                d = 0.35; tt = np.arange(int(d * sr)) / sr
                f0 = 140 + 60 * rng.random()
                add(t, np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.4 * np.exp(-tt * 20))) / sr) * env(d, 4) * 0.6)
    add(0.0, np.diff(noise(0.9), prepend=0) * env(0.9, 4) * 0.25)           # crash
    y /= np.abs(y).max() / 0.9
    sf.write(path, y, sr, subtype="PCM_16")
    print(f"demo: {path}")


# --------------------------------------------------------------------------
# Synthetic rendering fixtures (numpy only, deterministic) for selftest
# --------------------------------------------------------------------------
def _fx_bounds(onsets, total, max_dur=0.6):
    """Grain boundaries exactly as analyze() builds them: onsets, then even splits."""
    b = sorted(set([0.0] + [float(o) for o in onsets] + [float(total)]))
    rows = []
    for a, z in zip(b[:-1], b[1:]):
        k = int(np.ceil((z - a) / max_dur - 1e-9))
        e = np.linspace(a, z, k + 1)
        rows += list(zip(e[:-1], e[1:]))
    return rows


def _fx_percussion(sr=22050):
    rng = np.random.default_rng(20261115)
    T = 6.0
    y = np.zeros(int(T * sr))
    on = []
    for i in range(22):
        t0 = 0.1 + 0.25 * i
        s = int(t0 * sr)
        on.append(t0)
        n = int(0.2 * sr)
        tt = np.arange(n) / sr
        if i % 2 == 0:
            x = np.sin(2 * np.pi * np.cumsum(50 + 120 * np.exp(-tt * 30)) / sr) * np.exp(-tt / 0.05)
        else:
            x = np.diff(rng.standard_normal(n + 1)) * np.exp(-tt / 0.02) * 0.4
        y[s:s + n] += x[:len(y) - s]
    return 0.8 * y / np.abs(y).max(), sr, on, T


def _fx_sustained(sr=22050):
    T = 6.0
    t = np.arange(int(T * sr)) / sr
    env = np.clip((t - 0.2) / 0.03, 0, 1) * np.clip((5.2 - t) / 0.08, 0, 1)
    x = sum(np.sin(2 * np.pi * 220 * k * t + 0.3 * k) / k for k in range(1, 9))
    x *= 1 + 0.05 * np.sin(2 * np.pi * 5.5 * t)
    return 0.5 * env * x / np.abs(x).max(), sr, [0.2], T


def _fx_resonant(sr=22050):
    T = 9.0
    t = np.arange(int(T * sr)) / sr
    y = np.zeros_like(t)
    on = [0.1, 3.1, 6.1]
    for j, t0 in enumerate(on):
        tt = t - t0
        m = tt >= 0
        x = sum(a * np.sin(2 * np.pi * f * (1 + 0.03 * j) * tt[m]) * np.exp(-tt[m] / tau)
                for f, a, tau in [(311, 1, 1.2), (867, .6, .8), (1460, .4, .5), (2210, .25, .35)])
        y[m] += x * (1 - np.exp(-tt[m] / 0.002))
    return 0.8 * y / np.abs(y).max(), sr, on, T


def _fx_speechlike(sr=22050):
    """Vowel / fricative / vowel / vowel / pause / plosive + vowel ... (formant-like spectra)."""
    rng = np.random.default_rng(7)
    parts = [("v", .32, 140, (700, 1200)), ("f", .12, 0, None), ("v", .28, 125, (300, 2300)),
             ("v", .30, 110, (600, 900)), ("s", .15, 0, None), ("p", .03, 0, None),
             ("v", .35, 130, (500, 1700)), ("f", .10, 0, None), ("v", .40, 120, (350, 2000)),
             ("s", .30, 0, None)]
    ys, on, t0 = [np.zeros(int(0.05 * sr))], [], 0.05
    for kind, d, f0, fm in parts:
        n = int(d * sr)
        tt = np.arange(n) / sr
        if kind == "v":
            x = sum(np.sin(2 * np.pi * f0 * k * tt) * (np.exp(-((f0 * k - fm[0]) / 150) ** 2) +
                    0.7 * np.exp(-((f0 * k - fm[1]) / 200) ** 2) + 0.05) for k in range(1, int(4000 / f0)))
            x *= np.clip(tt / 0.02, 0, 1) * np.clip((d - tt) / 0.03, 0, 1)
            x = 0.5 * x / np.abs(x).max()
        elif kind == "f":
            x = np.diff(np.diff(rng.standard_normal(n + 2))) * 0.12 * np.clip(tt / 0.01, 0, 1) * np.clip((d - tt) / 0.02, 0, 1)
        elif kind == "p":
            x = rng.standard_normal(n) * np.exp(-tt / 0.006) * 0.5
        else:
            x = np.zeros(n)
        if kind != "s":
            on.append(t0)
        ys.append(x)
        t0 += d
    y = np.concatenate(ys)
    return y, sr, on, len(y) / sr


def _fx_write_corpus(y, sr, rows, path):
    """Corpus TSV with the same features analyze() computes, from given boundaries."""
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["id", "start_s", "end_s"] + FEATS)
        for i, (a_s, b_s) in enumerate(rows):
            seg = y[int(a_s * sr):int(b_s * sr)]
            rms = np.sqrt(np.mean(seg ** 2)) + 1e-9
            mag = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) + 1e-12
            freqs = np.fft.rfftfreq(len(seg), 1.0 / sr)
            pw = mag ** 2
            w.writerow([i] + [f"{x:.6f}" for x in (a_s, b_s, 20 * np.log10(rms), float(np.sum(freqs * mag) / np.sum(mag)),
                                                   float(np.exp(np.mean(np.log(pw))) / np.mean(pw)), b_s - a_s)])


def _fx_golden_source(path, sr=22050):
    """Source for the 18-grain selftest corpus (grain n at n*0.09 s)."""
    t = np.arange(int(1.8 * sr)) / sr
    y = np.zeros_like(t)
    for n in range(18):
        tt = t - n * 0.09
        m = tt >= 0
        y[m] += 0.3 * np.sin(2 * np.pi * (180 + 120 * n) * tt[m]) * np.exp(-tt[m] / 0.05)
    sf.write(path, y, sr, subtype="FLOAT")


def _wav_digest(path):
    data, _ = sf.read(path, dtype="float32", always_2d=True)
    return hashlib.sha256(np.ascontiguousarray(data).tobytes()).hexdigest()


# --------------------------------------------------------------------------
# Built-in deterministic regression tests (no librosa or source audio required)
# --------------------------------------------------------------------------
def selftest():
    """Check selection, ordering, the no-coupling invariant, and input validation."""
    with tempfile.TemporaryDirectory(prefix="dce_selftest_") as tmp:
        corpus = os.path.join(tmp, "corpus.tsv")
        with open(corpus, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f, delimiter="\t")
            w.writerow(["id", "start_s", "end_s"] + FEATS)
            for n in range(18):
                w.writerow([n, n * .09, n * .09 + .09, -35 + n % 7,
                            180 + 120 * n, 0.02 + .015 * (n % 5), .09])
        cfg = load_config(sets=["duration=9.0", "coupling=4.0", "memory_tau=0.3",
                                "temperature=0.12", "event_mode=hybrid"])

        def run_one(cond, label, config):
            prefix = os.path.join(tmp, label)
            ev, st = simulate(corpus, config, cond, 1, prefix)
            # Condition ID is metadata; compare event content with that ID removed.
            with open(ev, newline="", encoding="utf-8") as f:
                event_rows = list(csv.reader(f, delimiter="\t"))
            # Floats -0.0000 and +0.0000 are the same mathematical value.
            # Normalize numeric columns for cross-condition invariants; the
            # event log itself remains byte-stable under agent-order changes.
            events_content = [tuple(v if j == 3 else float(v) for j, v in enumerate(r[1:])) for r in event_rows[1:]]
            with open(st, newline="", encoding="utf-8") as sfh:
                state_rows = list(csv.reader(sfh, delimiter="\t"))
            states_content = [tuple(float(x) for x in r) for r in state_rows[1:]]
            return (events_content, states_content)

        # Scratch cleanup: nested leftovers are removed; dangerous paths rejected.
        scratch = os.path.join(tmp, "temp_DCE_123456")
        os.makedirs(os.path.join(scratch, "nested"))
        with open(os.path.join(scratch, "nested", "leftover.txt"), "w", encoding="utf-8") as f:
            f.write("test")
        clean_run_folder(scratch, tmp)
        assert not os.path.exists(scratch), "successful cleanup left a run folder"
        for bad_folder, bad_root in ((tmp, tmp),
                                     (os.path.join(tmp, "important"), tmp),
                                     (os.path.join(tmp, "nested", "temp_DCE_123456"), tmp)):
            try:
                clean_run_folder(bad_folder, bad_root)
            except ValueError:
                pass
            else:
                raise AssertionError("cleanup accepted an unsafe path")

        # Historical golden file: v0.1.4.1 (original engine, not this implementation)
        # Same 18-grain synthetic fixture, cfg above, condition 2, seed 1.
        # Hash the raw TSV including CRLF and header, to catch even small changes.
        golden_cfg = dict(cfg, feedback_reference="legacy", selection_gain=1.0,
                          pulse_rate_normalize=0.0)
        golden_path, _ = simulate(corpus, golden_cfg, 2, 1, os.path.join(tmp, "golden"), quiet=True)
        golden_actual = hashlib.sha256(open(golden_path, "rb").read()).hexdigest()
        golden_expected = "1e6775d40a6f4e04bd8e5197ad2c491fad7f86ede9586c3e76a0ab770fd2d0b2"
        assert golden_actual == golden_expected, (
            "v0.1.4.1 golden events SHA-256 mismatch: " + golden_actual)
        # These hashes were generated by running the original archived 0.1.4.1
        # implementation on exactly this fixture (TSV includes condition ID).
        extra_goldens = [
            (2, "off", "036c9dc9016adf02ac8aacf3d2acfb8ee9ac25261e023550623bcb7b1269ebd2"),
            (2, "fast_only", "120e1b37d35d88d248854a67c449f891017e1d91338a6ad54b6f97d3f6cfe60c"),
            (0, "hybrid", "b97bda31c0d0d0dad268ff3a4488478d779feba8c87b380505ee61817183a3f9"),
        ]
        for cond, mode, expected in extra_goldens:
            ev_path, _ = simulate(corpus, dict(golden_cfg, event_mode=mode), cond, 1,
                                  os.path.join(tmp, f"historic_{cond}_{mode}"), quiet=True)
            actual = hashlib.sha256(open(ev_path, "rb").read()).hexdigest()
            assert actual == expected, f"historical v0.1.4.1 {cond}/{mode} checksum mismatch: {actual}"

        baseline = run_one(2, "hybrid", cfg)
        assert baseline == run_one(2, "repeat", cfg), "fixed seed not reproducible"
        reverse = dict(cfg, agent_order="2,1,0")
        assert baseline == run_one(2, "reverse", reverse), "agent order changed outcome"
        # This was the v0.1.4 bug: fast event coupling ignored coupling_activity.
        disabled = dict(cfg, coupling_activity=0.0, coupling_selection=0.0)
        unlinked = run_one(0, "independent", disabled)
        assert unlinked == run_one(2, "hybrid_unlinked", disabled), "fast coupling bypasses activity switch"
        assert unlinked == run_one(2, "coupling_zero", dict(cfg, coupling=0.0)), "coupling=0 must equal independent"
        assert unlinked == run_one(1, "central_zero", dict(cfg, coupling=0.0)), "central coupling=0 must equal independent"
        assert unlinked == run_one(2, "matrix_zero", dict(cfg, K="0,0,0;0,0,0;0,0,0")), "K=0 must equal independent"
        center_cfg = dict(cfg, feedback_reference="independent")
        assert unlinked == run_one(2, "center_matrix_zero", dict(center_cfg, K="0,0,0;0,0,0;0,0,0")), "centered K=0 must equal independent"
        # Opt-in central drive must be zero-mean over the defined post-burn-in
        # sample window, while the legacy central signal keeps its old bias.
        cent_cfg = dict(cfg, central_reference="mean_g")
        _, cent_states = run_one(1, "central_mean_g", cent_cfg)
        cent_drive = np.asarray(cent_states)[int(0.1*len(cent_states)):, -3:]
        assert np.max(np.abs(cent_drive.mean(axis=0))) < 1e-4, "centered global drive must average to zero"
        disabled_fast = dict(disabled, event_mode="fast_only")
        assert unlinked == run_one(2, "fast_unlinked", disabled_fast), "fast_only bypasses activity switch"
        # Musical backward compatibility: event_strength=0 leaves the Off path identical.
        off = dict(cfg, event_mode="off")
        zero = dict(cfg, event_strength=0.0)
        assert run_one(2, "off", off) == run_one(2, "zero_fast", zero), "zero event_strength changed legacy path"
        assert run_one(2, "baseline_repeat", dict(cfg, feedback_reference="independent")) == run_one(2, "baseline_repeat2", dict(cfg, feedback_reference="independent")), "independent reference must be reproducible"
        assert run_one(2, "selection_gain_zero", dict(cfg, selection_gain=0.0, coupling_activity=0.0)) == unlinked, "selection_gain=0 must deactivate grain-choice coupling"
        for bad, value, msg in [("memory_tau", "0.01", "memory_tau"),
                                ("K", "1,2;3,4", "K"),
                                ("K", "1,2,3;4,5,6;7,8,9", "K")]:
            try:
                run_one(2, "bad_" + bad, load_config(sets=[f"{bad}={value}"]))
            except ValueError as exc:
                assert msg in str(exc)
            else:
                raise AssertionError("validation did not reject " + bad)
        assert max(0, int(poisson.ppf(0.0, 0.5))) == 0, "Poisson zero-quantile must not generate negative events"
        try:
            simulate(corpus, cfg, 2, -1, os.path.join(tmp, "bad_seed"))
        except ValueError:
            pass
        else:
            raise AssertionError("negative seed not rejected")
        try:
            load_config(sets=["couplng=4"])
        except ValueError:
            pass
        else:
            raise AssertionError("unknown config key not rejected")

        # Study smoke test: this exercises the factor grid, CI / paired analysis,
        # and TSV file creation without requiring a source-audio analysis.
        smoke_path = os.path.join(tmp, "study.tsv")
        run_study(corpus, dict(cfg, duration=3.0), [0, 1, 2], [1, 2],
                  [0.0, 4.0], smoke_path)
        for suffix in ["study.tsv", "study_runs.tsv", "study_summary.tsv",
                       "study_runs_summary.tsv", "study_paired.tsv",
                       "study_paired_summary.tsv"]:
            output = os.path.join(tmp, suffix)
            assert os.path.isfile(output) and os.path.getsize(output) > 0, suffix + " not written"
        with open(os.path.join(tmp, "study_runs.tsv"), encoding="utf-8") as f:
            smoke_rows = list(csv.DictReader(f, delimiter="\t"))
        assert smoke_rows and "n_silent_agents" in smoke_rows[0], "study must report silent agents"
        assert all(0 <= int(r["n_silent_agents"]) <= len(AGENTS) for r in smoke_rows), "invalid silent-agent count"

        # Silent agents are an explicit diagnostic, not silently excluded.
        silent_path = os.path.join(tmp, "study_silent.tsv")
        run_study(corpus, dict(cfg, duration=3.0, rate_max="0,0,0"),
                  [0], [1], [0.0], silent_path)
        with open(os.path.join(tmp, "study_silent_runs.tsv"), encoding="utf-8") as f:
            silent_rows = list(csv.DictReader(f, delimiter="\t"))
        assert len(silent_rows) == 1 and int(silent_rows[0]["n_silent_agents"]) == 3, \
            "silent-agent counting did not identify three inactive agents"

        # ================= v0.1.6 rendering tests =================
        # E. Legacy render golden: sample-identical to the v0.1.5.5 renderer.
        # References were produced by the archived v0.1.5.5 engine on this exact
        # fixture (golden event log above + synthetic source), digest of float32 samples.
        src = os.path.join(tmp, "golden_src.wav")
        _fx_golden_source(src)
        ev_hash_before = hashlib.sha256(open(golden_path, "rb").read()).hexdigest()
        legacy_refs = {"fixed": "fa5b1072766929ada3314ec376608264920ebd0ba268a9869a5a57a2a8eac3e5",
                       "rms": "b2177931c5536a0356924ec2f0c064dc0d6d0a714b1e40813b2ac279ef784f5a",
                       "peak": "33eacd3234138654b650eaa42efeafdda7e24ca34d1e5d04990e86107e1c92f8"}
        for norm, ref in legacy_refs.items():
            o = os.path.join(tmp, f"legacy_{norm}.wav")
            render(golden_path, corpus, src, o, norm=norm, length_s=9.6)
            assert _wav_digest(o) == ref, f"legacy {norm} render differs from v0.1.5.5: {_wav_digest(o)}"
        # v0.1.6 Sustain-Aware output is frozen as well (digest from the v0.1.6 engine).
        sus_ref = os.path.join(tmp, "sus_ref.wav")
        render(golden_path, corpus, src, sus_ref, norm="fixed", length_s=9.6, render_mode="sustain")
        assert _wav_digest(sus_ref) == "902e73dfec6a478bf63aeb24094e6f7fb7b20a082c9d302593a8ed61a680a1aa", \
            "sustain render differs from v0.1.6: " + _wav_digest(sus_ref)
        vo_a, vo_b = os.path.join(tmp, "vo_a.wav"), os.path.join(tmp, "vo_b.wav")
        render(golden_path, corpus, src, vo_a, length_s=9.6, render_mode="voices")
        render(golden_path, corpus, src, vo_b, length_s=9.6, render_mode="voices")
        assert _wav_digest(vo_a) == _wav_digest(vo_b), "voices render is not deterministic"
        sus_a, sus_b = os.path.join(tmp, "sus_a.wav"), os.path.join(tmp, "sus_b.wav")
        render(golden_path, corpus, src, sus_a, length_s=9.6, render_mode="sustain")
        render(golden_path, corpus, src, sus_b, length_s=9.6, render_mode="sustain")
        assert _wav_digest(sus_a) == _wav_digest(sus_b), "sustain render is not deterministic"
        assert hashlib.sha256(open(golden_path, "rb").read()).hexdigest() == ev_hash_before, \
            "rendering modified the event log"
        assert len(sf.read(sus_a)[0]) == int(9.6 * sf.info(sus_a).samplerate), "fixed policy length"
        ext = os.path.join(tmp, "sus_ext.wav")
        render(golden_path, corpus, src, ext, length_s=9.6, render_mode="sustain", sustain={"tail_policy": "extend"})
        assert len(sf.read(ext)[0]) >= len(sf.read(sus_a)[0]), "extend policy shorter than fixed"
        for bad in ({"max_tail_s": -1}, {"release_ms": 0}, {"final_fade_s": -1},
                    {"final_fade_s": 11}, {"sustain_sensitivity": 2}, {"tail_policy": "x"},
                    {"evolution_ms": 5}, {"preserve_tails": 2}):
            try:
                sustain_options(**bad)
            except ValueError:
                pass
            else:
                raise AssertionError("sustain option not rejected: %r" % bad)
        try:
            render(golden_path, corpus, src, ext, render_mode="smooth")
        except ValueError:
            pass
        else:
            raise AssertionError("unknown render mode not rejected")

        # A-D. Synthetic source types: analysis + a full simulate/render pass each.
        def fixture_run(name, make):
            y, sr, on, T = make()
            rows = _fx_bounds(on, T)
            path = os.path.join(tmp, name)
            sf.write(path + ".wav", y, sr, subtype="FLOAT")
            _fx_write_corpus(y, sr, rows, path + "_corpus.tsv")
            se = np.array(rows)
            meta = sustain_analysis(y, sr, se, sustain_options())
            ev, _ = simulate(path + "_corpus.tsv", dict(cfg, duration=T), 2, 1, path, quiet=True)
            stats = render(ev, path + "_corpus.tsv", path + ".wav", path + "_sus.wav",
                           length_s=T, render_mode="sustain")
            with open(render_paths(path + "_sus.wav")[0], encoding="utf-8") as f:
                plan = list(csv.DictReader(f, delimiter="\t"))
            return y, sr, on, rows, meta, stats, plan

        def starts_at(rows, t):
            return [g for g, (a_s, _) in enumerate(rows) if abs(a_s - t) < 1e-9]

        # A. percussion: every hit is an attack, no extension, attacks kept (<=2 ms fade-in)
        y, sr, on, rows, meta, stats, plan = fixture_run("percussion", _fx_percussion)
        hits = [g for t in on for g in starts_at(rows, t)]
        assert all(meta["attack_start"][g] for g in hits), "A: percussion hit not detected as attack"
        assert all(meta["nat_end"][g] - meta["end"][g] <= int(0.001 * sr) for g in hits[:-1]), "A: percussion smeared"
        att_ev = [p for p in plan if p["attack_start"] == "1"]
        assert att_ev and all(float(p["fade_in_ms"]) <= 2.0 + 1000.0 / sr for p in att_ev), "A: attack fade-in too long"
        assert all(float(p["fade_out_ms"]) <= 12.0 + 1000.0 / sr for p in plan if p["class"] == "transient"), "A: transient release"

        # B. sustained tone: split boundaries are not attacks, continuation is not cut at 0.6 s
        y, sr, on, rows, meta, stats, plan = fixture_run("sustained", _fx_sustained)
        inner = [g for g, (a_s, _) in enumerate(rows) if 0.25 < a_s < 5.1]
        assert inner and not any(meta["attack_start"][g] for g in inner), "B: split boundary treated as attack"
        for g, (a_s, b_s) in enumerate(rows):
            if 0.15 < a_s < 4.2:
                want = min(b_s + SUSTAIN_DEFAULTS["max_tail_s"], 5.15)
                assert meta["nat_end"][g] / sr >= want - 0.01, f"B: grain {g} cut at {meta['nat_end'][g] / sr:.3f}"
        assert sum(meta["cls"][g] == "sustained" for g in inner) >= len(inner) // 2, "B: tone not classified sustained"
        assert int(stats["extended"]) > 0, "B: no rendered event was extended"

        # C. resonant decay: tails continue, never across the next strike
        y, sr, on, rows, meta, stats, plan = fixture_run("resonant", _fx_resonant)
        strikes = [starts_at(rows, t)[0] for t in on]
        assert all(meta["attack_start"][g] for g in strikes), "C: strike not detected"
        assert all(meta["cls"][g] == "resonant" for g in strikes), "C: strike not classified resonant"
        for g in range(len(rows)):
            nxt = [int(t * sr) for t in on if int(t * sr) > meta["start"][g]]
            if nxt:
                assert meta["nat_end"][g] <= nxt[0], f"C: grain {g} tail crosses the next strike"
        assert meta["nat_end"][strikes[0]] >= int((on[1] - 0.01) * sr), "C: first decay truncated early"
        assert float(stats["peak"]) <= 1.0, "C: overlapping resonances exceed full scale"

        # D. speech-like: each phone onset is an attack; no tail absorbs the next phone
        y, sr, on, rows, meta, stats, plan = fixture_run("speechlike", _fx_speechlike)
        phones = [g for t in on for g in starts_at(rows, t)]
        assert all(meta["attack_start"][g] for g in phones), "D: phone onset not detected"
        for g in range(len(rows)):
            nxt = [int(t * sr) for t in on if int(t * sr) > meta["start"][g]]
            if nxt:
                assert meta["nat_end"][g] <= nxt[0], f"D: grain {g} absorbs the following phone"
        # F. Continuous Voices on the sustained tone and the resonant strikes
        def voices_run(name, make):
            y, sr, on, T = make()
            rows = _fx_bounds(on, T)
            path = os.path.join(tmp, "v_" + name)
            sf.write(path + ".wav", y, sr, subtype="FLOAT")
            _fx_write_corpus(y, sr, rows, path + "_corpus.tsv")
            ev, _ = simulate(path + "_corpus.tsv", dict(cfg, duration=T), 2, 1, path, quiet=True)
            h0 = hashlib.sha256(open(ev, "rb").read()).hexdigest()
            st = render(ev, path + "_corpus.tsv", path + ".wav", path + "_vo.wav", length_s=T, render_mode="voices")
            assert hashlib.sha256(open(ev, "rb").read()).hexdigest() == h0, "voices render modified the event log"
            with open(render_paths(path + "_vo.wav")[0], encoding="utf-8") as f:
                log = list(csv.DictReader(f, delimiter="\t"))
            out, _ = sf.read(path + "_vo.wav", always_2d=True)
            return y, sr, on, rows, st, log, out
        y, sr, on, rows, st, log, out = voices_run("sustained", _fx_sustained)
        assert int(st["evolutions"]) > int(st["attacks"]), "F: sustained tone not rendered as evolution"
        assert all(r["action"] != "attack" for r in log if 0.25 < float(rows[int(r["grain"])][0]) < 5.1), \
            "F: a mid-tone grain restarted the voice"
        assert float(st["voice_max_s"]) >= 2.0, "F: no continuous voice on a sustained tone"
        # crossfade level: no dip deeper than 3 dB inside the tone (10 ms RMS of the mix)
        m = out.mean(axis=1)
        hop = int(0.01 * sr)
        e = 10 * np.log10(np.array([np.mean(m[i:i + hop] ** 2) for i in range(0, len(m) - hop, hop)]) + 1e-20)
        voiced = e > np.max(e) - 30
        idx = np.nonzero(voiced)[0]
        inner = e[idx[5]:idx[-5]]
        steps = np.diff(inner)
        assert np.min(steps) > -6.0, f"F: abrupt level drop {np.min(steps):.1f} dB inside the voice"
        y, sr, on, rows, st, log, out = voices_run("resonant", _fx_resonant)
        strikes = [g for t in on for g, (a_s, _) in enumerate(rows) if abs(a_s - t) < 1e-9]
        assert all(r["action"] == "attack" for r in log if int(r["grain"]) in strikes), "F: strike not a new attack"
        assert float(st["peak"]) <= 1.0, "F: voices exceed full scale on resonant strikes"
        # G. Persistent Sonic Processes
        y, sr, on, T = _fx_sustained()
        rows = _fx_bounds(on, T)
        path = os.path.join(tmp, "p_sustained")
        sf.write(path + ".wav", y, sr, subtype="FLOAT")
        _fx_write_corpus(y, sr, rows, path + "_corpus.tsv")
        ev, _ = simulate(path + "_corpus.tsv", dict(cfg, duration=T), 2, 1, path, quiet=True)
        h0 = hashlib.sha256(open(ev, "rb").read()).hexdigest()
        st = render(ev, path + "_corpus.tsv", path + ".wav", path + "_p1.wav", length_s=T, render_mode="process")
        render(ev, path + "_corpus.tsv", path + ".wav", path + "_p2.wav", length_s=T, render_mode="process")
        assert _wav_digest(path + "_p1.wav") == _wav_digest(path + "_p2.wav"), "G: process render not deterministic"
        assert hashlib.sha256(open(ev, "rb").read()).hexdigest() == h0, "G: process render modified the event log"
        # v0.1.7.1: the final fade must reach digital zero, preserve length,
        # and leave all samples before the final one-second window unchanged.
        raw_path = path + "_no_final_fade.wav"
        render(ev, path + "_corpus.tsv", path + ".wav", raw_path,
               length_s=T, render_mode="process", sustain={"final_fade_s": 0.0})
        faded, _ = sf.read(path + "_p1.wav", always_2d=True)
        raw, _ = sf.read(raw_path, always_2d=True)
        fade_start = len(faded) - int(round(sr * SUSTAIN_DEFAULTS["final_fade_s"]))
        assert faded.shape == raw.shape, "G: final fade changed output length"
        assert np.array_equal(faded[:fade_start], raw[:fade_start]), "G: fade changed the musical body"
        assert np.max(np.abs(faded[-1])) == 0.0, "G: final mix does not end at zero"
        assert not np.array_equal(faded[fade_start:], raw[fade_start:]), "G: final fade had no effect"
        with open(render_paths(path + "_p1.wav")[0], encoding="utf-8") as f:
            plog = list(csv.DictReader(f, delimiter="\t"))
        assert sum(r["role"] == "articulation" for r in plog) == int(st["voices"]), "G: articulation inside a phrase"
        assert float(st["decisions_per_voice"]) >= 4.0, "G: decisions are still mostly separate sounds"
        assert float(st["voice_max_s"]) >= 3.0, "G: no long persistent voice on a sustained tone"
        # decision density does not shorten or alter a transition: extra decisions that point
        # at the material already playing leave the audio sample-identical.
        a_mid = [g for g, (a_s, _) in enumerate(rows) if 1.3 < a_s < 2.0][0]
        a_late = [g for g, (a_s, _) in enumerate(rows) if 3.0 < a_s < 3.7][0]
        def write_ev(p, times):
            with open(p, "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f, delimiter="\t")
                w.writerow(["condition", "seed", "time", "agent", "grain", "gain", "pan", "lam"])
                for t_, g_ in times:
                    w.writerow([2, 1, f"{t_:.4f}", "A", g_, "0.8000", "-0.600", "0.5000"])
        sparse = [(0.5, a_mid), (1.5, a_late)]
        dense = sparse + [(1.5 + 0.05 * k, a_late) for k in range(1, 8)]
        write_ev(path + "_sparse.tsv", sparse)
        write_ev(path + "_dense.tsv", sorted(dense))
        render(path + "_sparse.tsv", path + "_corpus.tsv", path + ".wav", path + "_sp.wav", length_s=T, render_mode="process")
        render(path + "_dense.tsv", path + "_corpus.tsv", path + ".wav", path + "_de.wav", length_s=T, render_mode="process")
        assert np.array_equal(sf.read(path + "_sp.wav")[0], sf.read(path + "_de.wav")[0]), \
            "G: decision density changed the transformation"
        # articulation=attacks keeps percussion as separate strokes
        y, sr, on, T = _fx_percussion()
        rows = _fx_bounds(on, T)
        path = os.path.join(tmp, "p_perc")
        sf.write(path + ".wav", y, sr, subtype="FLOAT")
        _fx_write_corpus(y, sr, rows, path + "_corpus.tsv")
        ev, _ = simulate(path + "_corpus.tsv", dict(cfg, duration=T), 2, 1, path, quiet=True)
        st = render(ev, path + "_corpus.tsv", path + ".wav", path + "_pa.wav", length_s=T,
                    render_mode="process", sustain={"articulation": "attacks"})
        assert int(st["voices"]) >= 0.8 * int(st["events"]), "G: attacks articulation merged percussion strokes"
    print("SELFTEST PASS: four historical v0.1.4.1 SHA-256 references, central centering, order, ablation, validation, study smoke, silent agents")
    print("SELFTEST PASS (v0.1.6): legacy render identical to v0.1.5.5 (fixed/rms/peak), sustain determinism, "
          "event-log invariance, tail policies, option validation, A percussion, B sustained, C resonant, D speech-like")
    print("SELFTEST PASS (v0.1.6.1): v0.1.6 sustain golden, Continuous Voices determinism, event-log invariance, "
          "sustained continuity, no mid-sound restarts, crossfade level, resonant attacks")
    print("SELFTEST PASS (v0.1.7.1): final fade reaches zero, only affects end of process mix; "
          "process determinism, event-log invariance, one articulation per voice, "
          "persistent voices, decision-density independence, attacks articulation")


# --------------------------------------------------------------------------
# Multi-seed study: raw agent runs, per-run metrics, t-CI aggregation,
# paired differences (seed-matched). No audio render or density adjustment.
# All comparisons are observational, not automatically density-matched.
# --------------------------------------------------------------------------
def _ci95(values):
    x = np.asarray(values, dtype=float)
    x = x[np.isfinite(x)]
    n = len(x)
    if not n:
        return (0, np.nan, np.nan, np.nan)
    mu = float(x.mean())
    if n < 2:
        return (n, mu, np.nan, np.nan)  # no confidence interval for n=1
    half = float(student_t.ppf(.975, n - 1) * x.std(ddof=1) / np.sqrt(n))
    return (n, mu, mu - half, mu + half)


def _write_tsv(path, fieldnames, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        w.writeheader()
        w.writerows(rows)


def run_study(corpus, cfg, conditions, seeds, couplings, out_tsv,
              memories=None, selection_gains=None, references=None, event_modes=None,
              central_references=None):
    """Factor-aware, non-duplicating experiment grid. Distinct rows are runs,
    not condition labels copied across irrelevant factor combinations.

    Paired contrasts use the same seed; they do NOT density-match and cannot
    establish musical-form effects. Correlations should be pooled on Fisher z.
    """
    import itertools
    conditions = list(dict.fromkeys(conditions))
    seeds = list(dict.fromkeys(int(x) for x in seeds))
    couplings = list(dict.fromkeys(float(x) for x in couplings))
    memories = list(dict.fromkeys(float(x) for x in (memories or [cfg["memory_tau"]])))
    selection_gains = list(dict.fromkeys(float(x) for x in (selection_gains or [cfg["selection_gain"]])))
    references = list(dict.fromkeys(references or [cfg["feedback_reference"]]))
    event_modes = list(dict.fromkeys(event_modes or [cfg["event_mode"]]))
    central_references = list(dict.fromkeys(central_references or [cfg["central_reference"]]))
    if not seeds or not conditions or any(c not in (0,1,2) for c in conditions):
        raise ValueError("study requires valid conditions (0,1,2) and at least one seed")
    if any(x < 0 for x in seeds):
        raise ValueError("study seeds must be nonnegative")
    if not couplings:
        raise ValueError("study requires at least one coupling")
    if any(x not in ("legacy", "mean_g") for x in central_references):
        raise ValueError("central references must be legacy or mean_g")
    stem = os.path.splitext(out_tsv)[0]
    os.makedirs(os.path.dirname(os.path.abspath(out_tsv)), exist_ok=True)
    NA = "n/a"
    fields = ["condition", "seed", "coupling", "memory_s", "selection_gain", "reference",
              "event_mode", "central_reference"]
    per_agent, per_run = [], []
    indexed = {0:{}, 1:{}, 2:{}}
    ref_cache = {}
    schedules = []
    if 0 in conditions:
        for seed in seeds:
            schedules.append((0,seed,NA,NA,NA,NA,NA,NA))
    if 1 in conditions:
        for seed,cpl,cr in itertools.product(seeds,couplings,central_references):
            if cpl == 0.0 and cr != central_references[0]:
                continue  # central reference is irrelevant when drive is zero
            schedules.append((1,seed,cpl,NA,NA,NA,NA,cr if cpl else NA))
    if 2 in conditions:
        for seed,cpl,mem,sg,ref,mode in itertools.product(
                seeds,couplings,memories,selection_gains,references,event_modes):
            if cpl == 0.0:
                if (mem,sg,ref,mode) != (memories[0],selection_gains[0],references[0],event_modes[0]):
                    continue  # no external interaction is possible at coupling=0
                schedules.append((2,seed,cpl,NA,NA,NA,NA,NA))
            else:
                schedules.append((2,seed,cpl,mem,sg,ref,mode,NA))

    with tempfile.TemporaryDirectory(prefix="dce_study_") as td:
        for j, values in enumerate(schedules):
            metadata = dict(zip(fields, values))
            cond,seed,cpl,mem,sg,ref,mode,cent = values
            cc = dict(cfg)
            if cond in (1,2): cc["coupling"] = cpl
            if cond == 1 and cpl: cc["central_reference"] = cent
            if cond == 2 and cpl:
                cc.update(memory_tau=mem, selection_gain=sg,
                          feedback_reference=ref, event_mode=mode)
            ep, sp = simulate(corpus, cc, cond, seed,
                              os.path.join(td, f"run_{j:06d}"), quiet=True,
                              reference_cache=ref_cache)
            with open(ep, encoding="utf-8") as f:
                ev = list(csv.DictReader(f, delimiter="\t"))
            with open(sp, encoding="utf-8") as f:
                st = list(csv.DictReader(f, delimiter="\t"))
            post = st[int(0.1 * len(st)):] or st
            act = np.column_stack([[float(row[f"act_{a}"]) for row in post] for a in AGENTS])
            with np.errstate(invalid="ignore", divide="ignore"):
                corr = np.corrcoef(act.T) if len(act) >= 2 else np.full((3,3),np.nan)
            def fisher(r):
                return float(np.arctanh(np.clip(r, -0.999999, 0.999999))) if np.isfinite(r) else np.nan
            run = dict(metadata, total_events_per_s=len(ev) / cfg["duration"],
                       corr_AB=float(corr[0,1]), corr_AC=float(corr[0,2]), corr_BC=float(corr[1,2]),
                       fisher_z_AB=fisher(corr[0,1]), fisher_z_AC=fisher(corr[0,2]),
                       fisher_z_BC=fisher(corr[1,2]))
            # Attach agent-balanced metrics to the run BEFORE paired comparison.
            # This prevents frequently firing agent A from dominating the estimate.
            act_std_agent = []
            grains_agent = []
            drive_std_agent = []
            saturation_agent = []
            for aa in AGENTS:
                aact = np.asarray([float(row[f"act_{aa}"]) for row in post])
                adrive = np.asarray([float(row[f"drive_{aa}"]) for row in post])
                ae = [e for e in ev if e["agent"] == aa]
                aentropy = float(np.mean([float(e["sel_entropy"]) for e in ae])) if ae else np.nan
                act_std_agent.append(float(aact.std()))
                drive_std_agent.append(float(adrive.std()))
                saturation_agent.append(float(np.mean((aact < .1) | (aact > .9))))
                grains_agent.append(float(np.exp(aentropy)) if np.isfinite(aentropy) else np.nan)
            # No-event agents are counted explicitly; mean effective-grain
            # statistics below retain their original active-agent-only meaning.
            run.update(n_silent_agents=sum(not np.isfinite(x) for x in grains_agent),
                       mean_agent_act_std=float(np.mean(act_std_agent)),
                       mean_agent_drive_std=float(np.mean(drive_std_agent)),
                       mean_agent_saturation=float(np.mean(saturation_agent)),
                       mean_agent_effective_grains=(float(np.mean([x for x in grains_agent if np.isfinite(x)]))
                                                    if any(np.isfinite(x) for x in grains_agent) else np.nan))
            per_run.append(run)
            if cond == 0: indexed[0][seed] = run
            elif cond == 1: indexed[1][(seed,cpl,cent)] = run
            else: indexed[2][(seed,cpl,mem,sg,ref,mode)] = run
            for a in AGENTS:
                ae = [e for e in ev if e["agent"] == a]
                activity = np.asarray([float(row[f"act_{a}"]) for row in post])
                def v(name):
                    return np.asarray([float(row[f"{name}_{a}"]) for row in post])
                entropy = float(np.mean([float(e["sel_entropy"]) for e in ae])) if ae else np.nan
                per_agent.append(dict(metadata, agent=a, events_per_s=len(ae)/cfg["duration"],
                    act_mean=float(activity.mean()), act_std=float(activity.std()),
                    sat_low=float(np.mean(activity < .1)), sat_high=float(np.mean(activity > .9)),
                    entropy_nats=entropy,
                    effective_grains=float(np.exp(entropy)) if np.isfinite(entropy) else np.nan,
                    drive_mean=float(v("drive").mean()), drive_std=float(v("drive").std()),
                    slow_mean=float(v("slow").mean()), slow_std=float(v("slow").std()),
                    fast_mean=float(v("fast").mean()), fast_std=float(v("fast").std())))
    agent_metrics=["events_per_s","act_mean","act_std","sat_low","sat_high",
                   "entropy_nats","effective_grains","drive_mean","drive_std",
                   "slow_mean","slow_std","fast_mean","fast_std"]
    run_metrics=["total_events_per_s", "n_silent_agents", "corr_AB","corr_AC","corr_BC",
                 "fisher_z_AB","fisher_z_AC","fisher_z_BC",
                 "mean_agent_act_std", "mean_agent_effective_grains",
                 "mean_agent_drive_std", "mean_agent_saturation"]
    # Paired seed differences; exploratory secondary metrics, no multiplicity correction.
    # Pre-specified primary metric for the exploratory study: mean_agent_act_std.
    inferential_metrics=["mean_agent_act_std", "total_events_per_s",
                         "mean_agent_effective_grains", "mean_agent_drive_std",
                         "mean_agent_saturation", "fisher_z_AB","fisher_z_AC","fisher_z_BC"]
    _write_tsv(out_tsv,fields+["agent"]+agent_metrics,per_agent)
    _write_tsv(stem+"_runs.tsv",fields+run_metrics,per_run)
    def aggregate(rows, group_fields, metric_fields, outfile):
        grouped=defaultdict(list)
        for row in rows:
            grouped[tuple(row[k] for k in group_fields)].append(row)
        out=[]
        for key,gr in sorted(grouped.items(),key=lambda x:str(x[0])):
            for metric in metric_fields:
                n,mean,lo,hi=_ci95([r[metric] for r in gr])
                item=dict(zip(group_fields,key),metric=metric,n_seeds=n,
                          mean=mean,ci95_low=lo,ci95_high=hi,
                          r_from_fisher_z=float(np.tanh(mean)) if metric.startswith("fisher_z_") and np.isfinite(mean) else "")
                out.append(item)
        _write_tsv(outfile,group_fields+["metric","n_seeds","mean","ci95_low","ci95_high","r_from_fisher_z"],out)
    grouping=[x for x in fields if x!="seed"]
    aggregate(per_agent,grouping+["agent"],agent_metrics,stem+"_summary.tsv")
    aggregate(per_run,grouping,inferential_metrics,stem+"_runs_summary.tsv")

    # Contrast each unique condition-2 run with the matching independent
    # baseline, and separately with each centralized control for its coupling.
    # A centralized run is paired with condition 0 exactly once per seed/coupling
    # (not once for every condition-2 setting). Pair labels remain explicit.
    pairs=[]
    def add_pair(lhs,rhs,meta,name):
        for metric in inferential_metrics:
            pairs.append(dict(meta,pair=name,metric=metric,
                              difference=float(lhs[metric]-rhs[metric])))
    for (seed,cpl,cent),r1 in indexed[1].items():
        if seed in indexed[0]:
            add_pair(r1,indexed[0][seed],{k:r1[k] for k in fields if k!="condition"},"1-0")
    for (seed,cpl,mem,sg,ref,mode),r2 in indexed[2].items():
        if seed in indexed[0]:
            add_pair(r2,indexed[0][seed],{k:r2[k] for k in fields if k!="condition"},"2-0")
        for cent in ([NA] if cpl == 0.0 else central_references):
            if (seed,cpl,cent) in indexed[1]:
                meta={k:r2[k] for k in fields if k!="condition"}
                meta["central_reference"]=cent
                add_pair(r2,indexed[1][(seed,cpl,cent)],meta,"2-1")
    pair_fields=[k for k in fields if k!="condition"]
    _write_tsv(stem+"_paired.tsv",pair_fields+["pair","metric","difference"],pairs)
    pg=[k for k in pair_fields if k!="seed"]+["pair","metric"]
    groups=defaultdict(list)
    for row in pairs:
        groups[tuple(row[k] for k in pg)].append(row["difference"])
    summary=[]
    for key,values in sorted(groups.items(),key=lambda x:str(x[0])):
        n,mu,lo,hi=_ci95(values)
        summary.append(dict(zip(pg,key),n_seeds=n,mean_difference=mu,ci95_low=lo,ci95_high=hi))
    _write_tsv(stem+"_paired_summary.tsv",pg+["n_seeds","mean_difference","ci95_low","ci95_high"],summary)
    print(f"STUDY PASS: {len(per_run)} distinct runs; {len(pairs)} paired metric contrasts")
    print("CI: 95% Student t across seeds, descriptive only; no density/drive matching or multi-test correction")
    print("Correlations: use fisher_z_* for CI/contrasts; r_from_fisher_z is back-transformed mean")


# --------------------------------------------------------------------------
# Safe scratch-folder cleanup. Called by the Praat wrapper ONLY after successful
# import and visualization, and ONLY when Keep_intermediate_files is disabled.
# The engine never removes failed runs or user-selected retention folders.
# --------------------------------------------------------------------------
def clean_run_folder(folder, temp_root):
    """Delete exactly one DSE-created scratch directory under Praat's temp root.

    Strict basename and immediate-parent checks defend against an accidental
    or malformed recursive deletion. This action is deliberately explicit.
    """
    folder = os.path.abspath(os.path.normpath(folder))
    temp_root = os.path.abspath(os.path.normpath(temp_root))
    label = os.path.basename(folder)
    if not re.fullmatch(r"temp_DCE_[0-9]{6}", label):
        raise ValueError("Cleanup refused: not a DSE scratch folder: " + label)
    if os.path.normcase(os.path.realpath(os.path.dirname(folder))) != os.path.normcase(os.path.realpath(temp_root)):
        raise ValueError("Cleanup refused: folder is not directly inside Praat's temporary directory")
    if os.path.islink(folder):
        raise ValueError("Cleanup refused: scratch folder is a symbolic link")
    if not os.path.exists(folder):
        print("cleanup: scratch folder already absent")
        return
    if not os.path.isdir(folder):
        raise ValueError("Cleanup refused: scratch path is not a directory")
    shutil.rmtree(folder)
    print("cleanup: removed scratch directory " + folder)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def render_args(p):
    """Rendering-only options: they never reach the simulation config, so the
    event log (agent decisions) is independent of the rendering mode."""
    p.add_argument("--render-mode", choices=["legacy", "sustain", "voices", "process"], default="legacy")
    p.add_argument("--max-tail", type=float, default=SUSTAIN_DEFAULTS["max_tail_s"], help="s")
    p.add_argument("--release-ms", type=float, default=SUSTAIN_DEFAULTS["release_ms"])
    p.add_argument("--crossfade-ms", type=float, default=SUSTAIN_DEFAULTS["crossfade_ms"])
    p.add_argument("--sustain-sensitivity", type=float, default=SUSTAIN_DEFAULTS["sustain_sensitivity"])
    p.add_argument("--tail-policy", choices=["fixed", "extend"], default=SUSTAIN_DEFAULTS["tail_policy"])
    p.add_argument("--preserve-tails", type=int, choices=[0, 1], default=SUSTAIN_DEFAULTS["preserve_tails"],
                   help="sustain only: 1 = no same-agent handoff")
    p.add_argument("--evolution-ms", type=float, default=SUSTAIN_DEFAULTS["evolution_ms"],
                   help="voices only: Voice Evolution crossfade")
    p.add_argument("--final-fade-s", type=float, default=SUSTAIN_DEFAULTS["final_fade_s"],
                   help="process only: fade the final stereo mix over this many seconds (0 disables)")
    p.add_argument("--morph-s", type=float, default=SUSTAIN_DEFAULTS["morph_s"],
                   help="process only: time for a voice to move to new material")
    p.add_argument("--articulation", choices=["phrases", "attacks"], default=SUSTAIN_DEFAULTS["articulation"],
                   help="process only: when a new voice is articulated")


def sustain_from_args(a):
    return sustain_options(max_tail_s=a.max_tail, release_ms=a.release_ms, crossfade_ms=a.crossfade_ms,
                           sustain_sensitivity=a.sustain_sensitivity, tail_policy=a.tail_policy,
                           preserve_tails=a.preserve_tails, evolution_ms=a.evolution_ms,
                           morph_s=a.morph_s, articulation=a.articulation,
                           final_fade_s=a.final_fade_s)


def main():
    ap = argparse.ArgumentParser(description="Distributed Sound Ecology v0.1.7.2")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--config", help="key=value file")
        p.add_argument("--set", action="append", default=[], metavar="key=value")

    p = sub.add_parser("cleanup", help="remove one completed temporary DSE run safely")
    p.add_argument("--folder", required=True)
    p.add_argument("--temp-root", required=True)
    p = sub.add_parser("selftest", help="deterministic regression checks (no audio needed)")
    p = sub.add_parser("study", help="batch coupling/seed study from an existing corpus TSV (no audio)")
    p.add_argument("corpus"); common(p)
    p.add_argument("--conditions", type=int, nargs="+", default=[0, 1, 2])
    p.add_argument("--seeds", type=int, nargs="+", default=list(range(1, 21)))
    p.add_argument("--couplings", type=float, nargs="+", default=[0, 1, 2, 4, 8])
    p.add_argument("--memories", type=float, nargs="+", default=None,
                   help="memory_tau values; default: config's memory_tau")
    p.add_argument("--selection-gains", type=float, nargs="+", default=None)
    p.add_argument("--references", choices=["legacy", "independent"], nargs="+", default=None)
    p.add_argument("--event-modes", choices=["off", "hybrid", "fast_only"], nargs="+", default=None)
    p.add_argument("--central-references", choices=["legacy", "mean_g"], nargs="+", default=None)
    p.add_argument("-o", default="study_results.tsv")
    p = sub.add_parser("demo");     p.add_argument("-o", default="demo_perc_loop.wav")
    p = sub.add_parser("analyze");  p.add_argument("source"); p.add_argument("-o", default="corpus.tsv")
    p.add_argument("--channel", default="auto", help="auto (highest RMS) | mix | 0 | 1 | ...")
    p = sub.add_parser("simulate"); p.add_argument("corpus"); common(p)
    p.add_argument("--condition", type=int, default=2); p.add_argument("--seed", type=int, default=1)
    p.add_argument("-o", default="run")
    p = sub.add_parser("render")
    p.add_argument("events"); p.add_argument("--source", required=True)
    p.add_argument("--corpus", required=True); p.add_argument("-o", default="out.wav")
    p.add_argument("--norm", choices=["fixed", "rms", "peak"], default="fixed")
    p.add_argument("--length", type=float, default=None)
    p.add_argument("--channel", default="auto")
    render_args(p)
    p = sub.add_parser("run");      p.add_argument("source"); common(p)
    p.add_argument("--conditions", type=int, nargs="+", default=[0, 1, 2])
    p.add_argument("--seeds", type=int, nargs="+", default=[1])
    p.add_argument("--no-render", action="store_true")
    p.add_argument("--channel", default="auto")
    p.add_argument("--norm", choices=["fixed", "rms", "peak"], default="fixed")
    render_args(p)
    p.add_argument("-o", default="dce_out")

    a = ap.parse_args()
    if a.cmd == "cleanup":
        clean_run_folder(a.folder, a.temp_root)
    elif a.cmd == "selftest":
        selftest()
    elif a.cmd == "study":
        run_study(a.corpus, load_config(a.config, a.set), a.conditions, a.seeds, a.couplings, a.o,
                  a.memories, a.selection_gains, a.references, a.event_modes, a.central_references)
    elif a.cmd == "demo":
        make_demo(a.o)
    elif a.cmd == "analyze":
        analyze(a.source, a.o, a.channel)
    elif a.cmd == "simulate":
        simulate(a.corpus, load_config(a.config, a.set), a.condition, a.seed, a.o)
    elif a.cmd == "render":
        opts = sustain_from_args(a)
        render(a.events, a.corpus, a.source, a.o, norm=a.norm, length_s=a.length, channel=a.channel,
               render_mode=a.render_mode, sustain=opts)
        if a.render_mode == "legacy":
            legacy_diagnostics(a.events, a.corpus, a.o)
    elif a.cmd == "run":
        cfg = load_config(a.config, a.set)
        opts = sustain_from_args(a)                 # validate before any work
        corpus = os.path.join(a.o, "corpus.tsv")
        analyze(a.source, corpus, a.channel)
        meta = None
        if a.render_mode in ("sustain", "voices", "process") and not a.no_render:
            y_src, sr_src = load_mono(a.source, a.channel)
            meta = sustain_analysis(y_src, sr_src, load_corpus(corpus)[0], opts)
            write_sustain_tsv(os.path.join(a.o, "corpus_sustain.tsv"), meta, sr_src)
            print(f"sustain analysis: {int(np.sum(meta['attack_start']))}/{len(meta['start'])} grain starts are "
                  f"significant attacks; sensitivity {opts['sustain_sensitivity']:.2f}")
        for c in a.conditions:
            for s in a.seeds:
                prefix = os.path.join(a.o, f"c{c}_s{s}")
                ev, _ = simulate(corpus, cfg, c, s, prefix)
                if not a.no_render:
                    if a.render_mode == "sustain":
                        render_sustain(ev, corpus, a.source, prefix + ".wav", norm=a.norm,
                                       length_s=cfg["duration"] + 0.6, channel=a.channel,
                                       opts=opts, meta=meta)
                    elif a.render_mode == "process":
                        render_process(ev, corpus, a.source, prefix + ".wav", norm=a.norm,
                                       length_s=cfg["duration"] + 0.6, channel=a.channel,
                                       opts=opts, meta=meta)
                    elif a.render_mode == "voices":
                        render_voices(ev, corpus, a.source, prefix + ".wav", norm=a.norm,
                                      length_s=cfg["duration"] + 0.6, channel=a.channel,
                                      opts=opts, meta=meta)
                    else:
                        render(ev, corpus, a.source, prefix + ".wav", norm=a.norm,
                               length_s=cfg["duration"] + 0.6, channel=a.channel)
                        legacy_diagnostics(ev, corpus, prefix + ".wav")


if __name__ == "__main__":
    main()
