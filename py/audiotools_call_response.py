#!/usr/bin/env python3
# ============================================================
# Praat AudioTools Plugin
# Script:      audiotools_call_response.py
# Author:      Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version:     0.4.12 (2026) - Performer display (from v0.4.11)
# License:     MIT License
# Repository:  https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Capture + decision engine for AudioTools Intelligent Musical Call &
#   Response.  Two ways of running:
#
#   v0.2.0 CONTINUOUS ENGINE  (command: serve)
#     Started ONCE per performance (Praat -> blocking "launch" -> detached
#     "serve" process) and alive for the whole session:
#       input callback -> in_q -> DETECT+ANALYSE thread -> render_q
#         -> RENDER thread (headless "praat --run AudioTools_CallResponse.praat"
#            in render mode = the six AudioTools scripts, unmodified)
#         -> play_q -> PLAY thread -> output callback
#     The microphone stream stays open during analysis, rendering and
#     playback.  Python plays ONLY the WAV rendered by Praat (or, exactly as
#     in v0.1.3, the untransformed phrase when nothing qualifies or every
#     render fails - always logged).
#
#   v0.1.3 TURN-TAKING  (commands: listen / analyze, one process per turn)
#     Unchanged: opens the mic, records one phrase, analyses it, writes the
#     phrase WAV + decision file, exits; Praat renders and plays.
#
#   Both paths share the same feature extraction, scoring, eligibility
#   gates, parameter mapping and phrase detector.
#
# Changelog v0.4.12 - Performer display (from v0.4.11):
#   Engine unchanged except: det_event_age is reported with 0.1 s
#   resolution (the Praat display holds PHRASE CAPTURED for 2 s).
#
# Changelog v0.4.11 - Reliable phrase ends (from v0.4.10):
#   FIX (regression in v0.4.10): the stable noise floor learned a rise of
#     the room / microphone noise only after 4 s.  When the noise rose
#     6-8 dB just after calibration (Windows gain control, mic
#     "enhancements") and the performer began within those 4 s, the noise
#     stayed above the END threshold and no phrase ever ended (only the
#     12 s splits).  Now a FLAT input above the floor (< 2 dB variation
#     over 0.3 s) is learned within 0.3 s, as in v0.4.9; a crescendo is not
#     flat, so it stays protected.
#   FIX (also in v0.4.9 and earlier): calibration on digital silence set the
#     floor to -200 dBFS, so microphone noise counted as playing for the
#     rest of the session.  Calibration now ignores frames below -100 dBFS,
#     waits for 0.5 s of real input (3 s at most, else -80), and the floor
#     never goes below -90 dBFS.
#   NEW release of a stuck phrase: if the last 1.5 s of a phrase are flat
#     (< 3 dB), noise-like (spectral flatness > 0.25) and >= 10 dB below
#     the phrase peak, that is background, not playing: the phrase ends
#     where it began (ended_by "background") and the floor learns it.  A
#     phrase that is ONLY flat noise is discarded (no answer).
#   CHANGED steady background at Max_phrase_s: only flat AND noise-like
#     (a held tone is never turned into background; the "flat twice in a
#     row" rule of v0.4.10 is gone).
#   Display: the last detector event for 3 s - phrase end (silence) /
#     split at Max_phrase_s (continues) / background learned / noise or
#     too short, ignored.
#
# Changelog v0.4.10 - Phrase detection (from v0.4.9):
#   FIX crescendos were never detected: in LISTENING the noise floor rose
#     3 % per 10 ms with any input below the threshold, so a gradual entry
#     (2-3 s fade-in, even when it then held a loud tone) pulled the
#     threshold up with it.  The floor now learns only from input within
#     3 dB of it (slowly), falls quickly, and learns a change of room noise
#     only after 4 s of higher quiet input without a phrase.
#   NEW gradual entries: every phrase is captured from where its rise
#     began (walking back while above floor + 3 dB, up to 2 s) - the soft
#     opening of a gesture belongs to it.  (A "soft rise" trigger below the
#     threshold was tried and left out: a step in room noise looks the
#     same.  Very quiet playing = lower Sensitivity_dB.)
#   FIX long phrases: at Max_phrase_s the phrase was cut wherever it was
#     and the next one began after a fresh onset (part of the sound fell
#     between them).  Now it is cut at its quietest point in the last 30 %
#     and the rest continues directly as the next phrase.  A phrase that
#     reaches the limit completely flat (< 4 dB between quiet and loud) and
#     noise-like (a fan switched on) - or flat twice in a row - is steady
#     background: the floor learns it and the chain stops (otherwise steady
#     noise could chain phrases forever).  A held tone is not affected.
#   Display: the level meter is the detector's own frame level (max of the
#     last 100 ms), and the status carries det_state, floor / start / end
#     thresholds and the accumulated quiet (Praat: DETECTOR line, threshold
#     marks on the meter, READY no longer shown during a phrase).
#   The decision layer, memory and engines are unchanged.
#
# Changelog v0.4.9 - Influence memory fixes (from v0.4.8):
#   FIX coherence gate: it used the map's vectorised similarity, which (a)
#     did not switch PITCH mode to hybrid for an unpitched phrase and (b)
#     has no contour stage - a noise phrase vs a percussive one read 0.49
#     at the gate but 0.20 in retrieval, so an unrelated earlier phrase
#     kept influence.  The gate now calls SonicMemory.similarity itself
#     (same mode, same unpitched rule, contour stage, memory-wide scales).
#   FIX map similarity: PITCH mode falls back to hybrid weights for an
#     unpitched query, as retrieval does.
#   FIX influence arcs: their thickness was the earlier phrase's WEIGHT in
#     the model; it is now its actual SHARE of the chosen sound's score
#     (w_k * similarity(phrase_k, chosen) / total).  The debug log lists the
#     shares, trend included.
#   FIX timing: the history and the 45 s half-life use the time the phrase
#     ENDED (as played), not the time the engine analysed it - a backlog
#     no longer ages the history.
#
# Changelog v0.4.8 - Phrase-level influence memory (from v0.4.7):
#   The answer now responds to the recent HISTORY of gestures, not only to
#   the last phrase.  Retrieval scores every stored sound against the last
#   phrase AND the previous ones, each with a weight that fades with its
#   position (Influence_decay ^ k) and with time (half-life 45 s, so after
#   a long pause the history is forgotten):
#       influence(sound) = sum_k w_k * similarity(phrase_k, sound) / sum_k w_k
#   The last phrase always has weight 1.  Influence_depth 1 = exactly the
#   v0.4.7 behaviour.  Optional Trend_weight: a further query extrapolated
#   from the previous phrase to the last one (descriptor groups: last +
#   (last - previous); contours, voicing from the last) - it looks for
#   where the gesture is heading.  Minimum similarity, ranking, candidate
#   draw, contrast mode and Recall + Transform use the influence score;
#   the duplicate guard (re-captured playback) still uses the last phrase.
#   Coherence gating: an earlier phrase counts only as far as it resembles
#   the last one (similarity < 0.30: not at all - a new idea starts a new
#   history; > 0.60: fully).  Without it a sudden change of gesture was
#   answered with material pulled from the previous idea.
#   Map: the earlier phrases' share in a recall is drawn as pale lilac
#   arcs (thicker = larger share).  Display: MATCH shows "(n phrases)".
#   Defaults: depth 3, decay 0.5, trend 0 (off).  New arguments
#   --influence-depth, --influence-decay, --trend-weight.
#
# Changelog v0.4.7 - Loudness balance between the six answers (from v0.4.6):
#   Level matching (Level_matching on) is now a perceptual, burst-aware
#   STATIC gain per sound - no compression, the sound's own dynamics are
#   untouched.  Measured on emulations of the six outputs:
#   FIX stereo measurement: the RMS was taken of (L + R) / 2, so
#     decorrelated stereo (Paulstretch, Markov, 8-Channel Speed Deviations:
#     L/R correlation ~0) read up to 3 dB low and was raised +2.4..+5.8 dB
#     above its target.  Now: K-weighted (BS.1770 pre-filter) loudness of
#     the 400 ms blocks within 20 dB of the loudest, measured AS PLAYED:
#     real stereo = the two channel powers summed (BS.1770), mono and
#     dual-mono = the mono power that equal-power panning preserves.  So
#     mono, dual-mono and decorrelated stereo answers end up equally loud
#     after placement, and L and R can no longer cancel in the reading.
#   NEW burst constraint: the loudest 100 ms of a sound may be at most
#     6 dB above the role's target.  The emulated Groove Creator / MDS
#     outputs have 100 ms bursts +8..9 dB over their average (Speed
#     Deviations +6, sustained answers +1..3): they now play 2-3 dB lower
#     instead of hitting the listener with their transients.
#   FIX peak after spatialisation: the equal-power balance of a STEREO
#     source can raise one channel by up to +3 dB after level matching
#     (measured 0.90 -> 1.15).  Each voice is now scaled so its peak stays
#     <= 0.9 after placement; the mix limiter only handles overlaps.
#   Debug log: per voice the integrated and burst loudness and what limited
#     the gain (target / burst / peak / boost); summary: peak-trimmed voices.
#   Not changed: no fixed per-transformation trims (Speed Deviations already
#     lands on target on average - a trim would make it quieter than the
#     others); the standalone AudioTools scripts are untouched.
#
# Changelog v0.4.6 - Memory map (from v0.4.5):
#   NEW memory map (an arc diagram in the spirit of the OMax / DYCI2
#     memory views).  The engine writes graph.tsv to the session whenever
#     the memory or the sounding voices change (at most 4 per second); the
#     Praat Demo window draws it.  Musical behaviour is unchanged.
#     - one horizontal line = the memory: Corpus C (preloaded) on the left,
#       the performance (live phrases A, processed answers B) in time order
#       on the right.  Live phrases that are not stored (A off) still appear
#       as light points, so corpus-only answers are visible.
#     - upper arcs: similarity links (each sound's 3 nearest sounds above
#       Minimum_similarity; colour = gesture class, paler = weaker).  The
#       map uses the weighted group distance of the similarity mode; the
#       second-stage contour comparison that refines a RECALL is not drawn.
#     - lower arcs: what happened (the last 40 actions): recall (purple),
#       recall + transform (magenta), transformation phrase -> result
#       (teal); thicker = closer match, paler = older.
#     - points: sounds (A blue, B orange, C grey); a red ring marks a sound
#       that is sounding now; a red tick marks the latest phrase.
#     Links are computed vectorised: one row per new sound, one matrix for
#     Corpus C at start-up (300 sounds: well under a second).
#
# Changelog v0.4.5 - Whole answers (from v0.4.4):
#   Answers and memory sounds are no longer cut before their natural end.
#   FIX layers: a memory layer was a RANDOM excerpt (60-100 % of the sound,
#     random start) - so layers, often earlier processed answers, entered
#     mid-sound and stopped before their end.  New --layer-shape:
#     whole (default) = the complete stored sound; excerpt = from an onset
#     in the first 40 % of the sound to its natural END (never a random
#     start or an early stop).
#   FIX Corpus B: a processed answer was stored as its first Max_item_s
#     (15 s) by a raw slice - a recalled / layered answer stopped abruptly.
#     B now keeps the whole answer up to Max_response_s + 1.5 s.  Max_item_s
#     applies to live phrases (A) and Corpus C segmentation only.
#   FIX playback cap: Max_response_s + 1.5 s grace, so a natural tail
#     slightly longer than planned (e.g. Paulstretch) is kept.  A sound that
#     is still longer is cut at its QUIETEST point near the limit (never
#     inside the first 85 % of it) and faded (>= 0.5 s).  The same
#     quiet-point cut + fade is used for Corpus A storage.
#   Log: every voice records its shape - whole / excerpt a-b of c s /
#     trimmed from x to y s; summary counts trimmed voices and excerpts.
#   Unchanged and still intended: Paulstretch on a phrase longer than
#     ~10 s stretches its most stable 10 s window (planned, not a cut).
#
# Changelog v0.4.4 - Engine arguments via file (from v0.4.3):
#   FIX: "launch --args-file FILE" reads the engine arguments from a file
#     (one per line, closed by "#end"; Praat writes it as Latin-1, UTF-8 or
#     UTF-16 - all detected).  The Praat script no longer passes ~130
#     arguments on one command line, which runSubprocess cut off at about
#     1 KB on Windows (arguments lost / emptied from there on: the
#     "--w-preloaded" start-up error, or silently dropped last options).
#     "launch" with plain arguments still works as before.
#
# Changelog v0.4.3 - Windows path fix (from v0.4.2):
#   The engine is unchanged.  The Praat script now normalises user-typed
#   paths (Corpus_C_folder, praatExe$): a trailing backslash escaped the
#   closing quote of the argument on Windows and merged the next ones
#   ("argument --w-preloaded: invalid float value: ''").
#
# Changelog v0.4.2 - Performance presets (from v0.4.1):
#   The engine is unchanged.  The Praat form gained a first field (Preset),
#   so RENDER_FORM_ARGS gains a first value ("Custom (form and dialogs)");
#   presets are resolved in Praat and reach the engine as ordinary
#   arguments.
#
# Changelog v0.4.1 - Corpus-only recall + adaptive level (from v0.4.0):
#   Analysis, classifier, the six transformations, retrieval, mixer,
#   spatialisation and session safety are unchanged.  Corpus C files are
#   still only read.
#   NEW response mode corpus_only ("Corpus only - unprocessed recall"):
#     every answer is a stored sound played as it is (only envelope,
#     level and placement - no transformation).  Without a qualified match
#     the engine stays SILENT and keeps listening: no Transform fallback
#     and no passthrough of the phrase.  No memory layers and no
#     background texture in this mode (the texture is granulated).
#   NEW Follow live input (off by default): the K-weighted loudness of
#     every phrase (BS.1770 pre-filter, active 100 ms blocks) is tracked
#     RELATIVE to the session median (EMA, alpha 0.4 per phrase); the
#     difference, clamped to +-follow range (9 dB), shifts all role
#     targets alike, so response / layer / background keep their ratios.
#     Relative, so no microphone / speaker calibration is needed.  Phrases
#     recorded while the expected speaker leakage is within 15 dB of the
#     phrase are not counted (no feedback loop).  Applied from the 3rd
#     counted phrase, at voice creation only (never inside a sound).
#   NEW Corpus C balance (dB, -12..+12): extra gain for sounds taken from
#     the preloaded corpus (recalls, layers, background built from C).
#   NOTE: with level matching on, the +12 dB boost cap and the peak
#     ceiling still apply after both offsets.
#   Status: level_offset; summary: silent answers, follow offset.
#
# Changelog v0.4.0 - Polyphonic spatial playback (from v0.3.2):
#   The analysis, classifier, six transformations and their parameters,
#   Sonic Memory (corpora, retrieval, decisions) and the v0.3.1 / v0.3.2
#   session-safety rules are unchanged.  New is the PLAYBACK architecture:
#   POLYPHONY: answers no longer wait for each other.  Every answer is a
#     voice in a mixer (default max 4 voices): new gestures are answered
#     while earlier answers still sound.  Roles: response (foreground),
#     layer (a related or independent sound from memory entering 0.6-3.5 s
#     later, on the phrase's pulse if it is rhythmic, quieter, elsewhere in
#     space; probability = Polyphonic_density) and background.  Priority:
#     response > layer > background; a full mixer fades out (0.25 s) the
#     oldest background, then the oldest layer.  Polyphony off = the v0.3
#     one-answer-at-a-time order.
#   BACKGROUND: once there is material, a quiet (-33 dBFS) evolving texture
#     made from the performance's own sounds (memory + latest answers;
#     aligned overlapping grains, slow movement, gentle low-pass) keeps the
#     space from falling silent.  It recedes -9 dB while the performer
#     plays or two answers sound (-4.5 dB under one), returns over ~1.5 s,
#     crossfades into a new texture every 20-30 s.  Before the first sound
#     exists it stays silent (no synthetic noise); with a Corpus C folder it
#     starts at once.  It PAUSES while the microphone hears the speakers
#     strongly (leakage above -20 dB).
#   SPACE: equal-power panning of mono sources, preserved stereo sources
#     (mid/side width + equal-power balance), positions chosen away from
#     sounding voices, answers alternating sides, slow movement (two
#     incommensurate sines).  No decorrelation, no phase tricks (mono-safe),
#     |pan| <= 0.85.  Stereo_width, Spatial_movement, Pan_variation.
#   ENVELOPES: raised-cosine fade-in (30 ms, <= 15 % of the sound; 1 ms
#     anti-click ramp for transient starts - attacks are kept) and fade-out
#     (400 ms, <= 30 %; >= 0.5 s for an answer cut by Max_response_s);
#     smooth gain ramps for ducking and voice stealing; the whole mix fades
#     out (150 ms) before the engine stops.
#   LEVEL: optional level matching per role (-18 / -24 / -33 dBFS active
#     RMS), a peak limiter (ceiling -0.5 dBFS) on the sum.
#   LEAKAGE: the guard follows the LOUDER output channel; the phrase check
#     also fits the two channels separately (a voice panned to the speaker
#     the microphone hears best) and tolerates +-3 ms of clock drift; the
#     leak estimate decays only with evidence that the path is gone; extra
#     4 dB guard margin while only the background sounds.
#   UI: one new form field, Playback_settings (dialog: polyphony, max
#     voices, density, background + level, width, movement, pan variation,
#     fade-in/out, transients, level matching).  Display: VOICES line.
#
# Changelog v0.3.2 - Status-file robustness (from v0.3.1):
#   Musical behaviour, memory, retrieval, the six transformations and the
#   v0.3.1 session-safety rules are unchanged.
#   FIX (Windows error 13): Praat no longer stops when a read of status.txt
#     collides with the engine replacing it.  Status reads are guarded; a
#     failed or incomplete read (no end=1) is skipped and the last complete
#     status is kept.  Heartbeat and stop-request writes are guarded too.
#   FIX: "the engine process never ran" is reported only if NO complete
#     status was ever read.  An engine that did run but whose status stays
#     unreadable for 30 s is stopped with its own message.
#   FIX: the engine retries a status update that hits a locked file, logs
#     the first failure of a streak (with its cause) and the recovery,
#     counts failures (summary: status_write_failures) and retries the
#     FINAL status for up to 5 s.  No half-written .tmp file is left.
#   Cleanup after an unexpected Praat stop: unchanged v0.3.1 path - the
#     engine notices the missing heartbeat after 20 s and removes its own
#     session (only its own: PID + start time).
#
# Changelog v0.3.1 - Cleanup & Session Safety (from v0.3.0):
#   Only session lifecycle / deletion changed; musical behaviour, retrieval
#   and the six transformations are identical to v0.3.0.
#   FIX: cleanup no longer deletes a session whose engine is still running.
#     It waits for the engine (PID + process start time), and if the
#     engine is still alive it deletes NOTHING and reports CLEANUP
#     INCOMPLETE; the engine then removes its own session when it exits.
#   FIX: crash recovery never removes a session whose engine is alive,
#     however long it has been quiet; a reused PID (same number, different
#     start time) counts as dead.
#   FIX: the Praat script no longer force-deletes files of a session folder
#     that Python's cleanup left in place; it shows CLEANUP INCOMPLETE.
#   Python cleanup commands return a non-zero exit code when something was
#     not removed (except with --report, used by the Praat script).
#
# Changelog v0.3.0 (Sonic Memory Upgrade from v0.2.0):
#   NEW three in-RAM corpora: A live phrases, B Praat-rendered responses
#     (analysed from their OWN audio, provenance root/parent/method/
#     generation, generation limit, near-identical results not stored),
#     C a read-only preloaded folder (energy-aware segmentation, re-indexed
#     at every start, audio re-read on demand when the RAM budget is full).
#   NEW retrieval: z-normalised distance per feature group (timbre, pitch
#     gesture, rhythm, envelope, duration) + a second-stage pitch/envelope
#     contour comparison; modes hybrid | timbre | pitch | rhythm | envelope |
#     contrast; minimum similarity, ranked candidates, controlled randomness,
#     cooldown, self / recent / same-family exclusion, novelty preference.
#   NEW decision layer: Transform (v0.2 behaviour) | Recall | Recall +
#     Transform | Hybrid (weighted), always falling back to Transform when no
#     qualified match exists.  Optional quiet layered response (off).
#   NEW "brain" worker thread: analysis moved out of the detector thread,
#     the detector never searches memory.
#   NEW zero-temporary-file lifecycle: the engine deletes everything it
#     created (WAVs, job files, logs, stderr) before reporting its final
#     status; "cleanup" waits for the engine process, deletes the session
#     with bounded retries and reports what could not be removed;
#     "cleanup-stale" removes only ABANDONED sessions (dead owner, no
#     recent activity) and orphan probe files.  No index or cache on disk.
#   PRESERVED: continuous listening, phrase detection, leakage handling,
#     v0.2 features/scoring/parameter mapping, the six transformations
#     rendered by the unchanged AudioTools scripts, MDS visualisation flag,
#     MAX MC behaviour of 8-Channel Speed Deviations, all v0.1.3 commands.
#
# Changelog v0.2.0:
#   PRESERVED from v0.1.3 (byte-identical code): feature extraction, the six
#     score functions, eligibility gates, safeguards, tie-break, confidence
#     thresholds, parameter mapping (incl. 8-Channel Speed Deviations MAX MC
#     deviation cap), PhraseDetector thresholds/hysteresis, listen / analyze /
#     probe / cleanup commands, decision-file protocol, self-test cases.
#   NEW continuous capture: "serve" command - persistent engine with
#     callback capture, bounded queues (pending phrases / pending responses,
#     overflow policy drop_oldest | drop_newest, every drop logged), one
#     render at a time, one playback at a time, separate input/output devices,
#     status file for the Praat display, stop request + Praat heartbeat,
#     per-job timestamps (onset, end, analysed, render start/end, play
#     start/end) in the optional debug log.
#   NEW leakage handling: speaker->mic leakage ESTIMATE (least-squares fit of
#     the played signal to the captured input, best lag in 0-500 ms), warning
#     above -20 dB, optional guard that (a) lifts the onset/offset thresholds
#     by the expected leakage level only while an answer is playing and
#     (b) discards a finished phrase only when >= 75 % of its energy is
#     explained by the playback.  This is NOT echo cancellation: the recorded
#     audio is never modified, and a performer playing over the answer still
#     triggers phrases.
#   ARCHITECTURE: PhraseDetector gains rearm() (continue listening after a
#     phrase) and an optional leakage hook (default None = v0.1.3 behaviour).
#     MAX_RESPONSE_S is now configurable (--max-response, default 20 s).
#   COMPATIBILITY: "devices" now lists output devices too.  The v0.1.3
#     commands accept the new optional --max-response argument.
#
# Commands:
#   launch        <serve arguments>        start "serve" detached, return at once
#   launch        --args-file FILE         the same, arguments read from FILE (v0.4.4)
#   serve         --session DIR --script PRAAT_SCRIPT ...   continuous engine
#   probe         --out FILE [--live]      dependency check, writes FILE
#   devices       --out FILE               list audio input + output devices
#   listen        --session DIR --cycle N  [capture options]   (v0.1.3)
#   analyze       --session DIR --cycle N --input WAV         (v0.1.3)
#   cleanup       --session DIR            wait for the engine, remove the session
#   cleanup-stale --base DIR               remove abandoned sessions / probe files
#   self-test     [--write-dir DIR]        six-category + v0.2.0 + v0.3.0 tests
#
# Requirements:
#   Python >= 3.9, numpy, scipy, soundfile        (all commands)
#   sounddevice (PortAudio)                       (serve, listen, devices)
#   a Praat executable for headless rendering     (serve; found from the
#     Praat script's praatExe$ setting, PRAAT_EXE, PATH or standard folders)
#   pip install numpy scipy soundfile sounddevice
#   librosa is deliberately NOT used: its import time (1-3 s) would be
#   paid inside the musician's waiting time.
#
# Protocol (decision / job / status files: UTF-8, "\n" line endings, one
# key=value per line, values never contain newlines, written to *.tmp and
# renamed; the last line is end=1):
#   status=ok|timeout|silent_input|error   message=...
#   wav=<phrase wav>  sr=  channels=  duration=
#   mode=auto|manual  selected=<id>|passthrough  selected_score=
#   ranking=<id,id,...>  (eligible candidates above threshold, best first)
#   score_<id>=  eligible_<id>=0|1  reason_<id>=
#   p_<id>_<name>=<value>  for every candidate (named, not positional;
#                          the Praat dispatcher owns argument order)
#   seed=  t_phrase_end_epoch=  t_written_epoch=  t_detect_delay=
#   t_features=  t_select=  t_py_runtime=
#   render jobs add: out= result= plugin_root= max_response= job_id=
#
# Notes:
#   - Thresholds and score centres are POC heuristics tuned on synthetic
#     signals, not universal acoustic constants.
# ============================================================

import argparse
import collections
import math
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
import zlib

T_PROCESS_START = time.perf_counter()
VERSION = "0.4.12"

TRANSFORM_IDS = ["paulstretch", "markov", "mds", "spiral", "speeddev", "groove"]
TRANSFORM_NAMES = {
    "paulstretch": "Paulstretch (stable harmonic)",
    "markov": "Markov Soundscape Weaver (noisy / aperiodic)",
    "mds": "MDS Space Navigator (discrete attacks)",
    "spiral": "Spiral Pitch Dance (continuous glissando)",
    "speeddev": "8-Channel Speed Deviations (MAX MC; envelope-driven speed spread)",
    "groove": "Percussive Audio Groove Creator (variable density)",
}
# Deterministic tie-break: more specific categories first.
TIE_PRIORITY = ["spiral", "groove", "mds", "paulstretch", "markov", "speeddev"]
CONFIDENCE_THRESHOLD = {
    "paulstretch": 0.50, "markov": 0.50, "mds": 0.50,
    "spiral": 0.50, "speeddev": 0.45, "groove": 0.50,
}
AMBIGUITY_MARGIN = 0.08
MAX_RESPONSE_S = 20.0          # hard cap for stretched / generated answers
                               # (v0.2.0: overridden by --max-response)
SESSION_PREFIX = "AudioTools_CR_"


# ============================================================
# small helpers
# ============================================================
def sig(x, centre, width):
    """Logistic ramp 0..1 centred on `centre`."""
    z = (x - centre) / max(width, 1e-9)
    if z > 40:
        return 1.0
    if z < -40:
        return 0.0
    return 1.0 / (1.0 + math.exp(-z))


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def fnum(x, nd=4):
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return "nan"
    return ("%." + str(nd) + "f") % x


def clean_value(v):
    s = str(v)
    return s.replace("\r", " ").replace("\n", " ")


def write_kv_atomic(path, pairs):
    """Write key=value lines to path.tmp, then rename onto path."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        for k, v in pairs:
            fh.write("%s=%s\n" % (k, clean_value(v)))
        fh.write("end=1\n")
    os.replace(tmp, path)


def write_kv_retry(path, pairs, tries=50):
    """v0.3.2: write_kv_atomic that survives a reader holding the file
    (Windows sharing violation): bounded retries, never raises."""
    for _ in range(tries):
        try:
            write_kv_atomic(path, pairs)
            return True
        except OSError:
            time.sleep(0.02)
    try:
        os.remove(path + ".tmp")
    except OSError:
        pass
    return False


def write_text_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(tmp, path)


def import_dsp():
    import numpy as np                      # noqa: F401
    import scipy.signal                     # noqa: F401
    import scipy.fft                        # noqa: F401
    import soundfile                        # noqa: F401
    return np


# ============================================================
# DSP building blocks (numpy / scipy only)
# ============================================================
def to_mono(x):
    import numpy as np
    if x.ndim == 1:
        return x.astype(np.float64)
    return x.mean(axis=1).astype(np.float64)


def frame_signal(x, frame, hop):
    import numpy as np
    if len(x) < frame:
        x = np.pad(x, (0, frame - len(x)))
    n = 1 + (len(x) - frame) // hop
    idx = np.arange(frame)[None, :] + hop * np.arange(n)[:, None]
    return x[idx]


def rms_envelope_db(x, sr, hop_s=0.01, win_s=0.02):
    import numpy as np
    hop = max(1, int(round(hop_s * sr)))
    win = max(hop, int(round(win_s * sr)))
    pad = np.pad(x, (win // 2, win // 2))
    fr = frame_signal(pad, win, hop)
    r = np.sqrt(np.mean(fr ** 2, axis=1) + 1e-20)
    return 20 * np.log10(r + 1e-12)


def stft_mag(x, sr, n_fft=1024, hop=None):
    import numpy as np
    if hop is None:
        hop = int(round(0.01 * sr))
    pad = np.pad(x, (n_fft // 2, n_fft // 2))
    fr = frame_signal(pad, n_fft, hop) * np.hanning(n_fft)[None, :]
    return np.abs(np.fft.rfft(fr, axis=1)), np.fft.rfftfreq(n_fft, 1.0 / sr)


def mel_filterbank(sr, n_fft, n_mels=26, fmin=60.0, fmax=None):
    import numpy as np
    fmax = fmax or sr / 2
    def hz2mel(f):
        return 2595 * np.log10(1 + f / 700.0)
    def mel2hz(m):
        return 700 * (10 ** (m / 2595.0) - 1)
    mels = np.linspace(hz2mel(fmin), hz2mel(fmax), n_mels + 2)
    hz = mel2hz(mels)
    bins = np.fft.rfftfreq(n_fft, 1.0 / sr)
    fb = np.zeros((n_mels, len(bins)))
    for m in range(1, n_mels + 1):
        lo, ce, hi = hz[m - 1], hz[m], hz[m + 1]
        up = (bins - lo) / max(ce - lo, 1e-9)
        dn = (hi - bins) / max(hi - ce, 1e-9)
        fb[m - 1] = np.clip(np.minimum(up, dn), 0, None)
    return fb


def mfcc_from_mag(mag, fb, n_coef=12):
    import numpy as np
    import scipy.fft
    mel = np.log(np.maximum(mag ** 2 @ fb.T, 1e-12))
    return scipy.fft.dct(mel, type=2, norm="ortho", axis=1)[:, 1:n_coef + 1]


def yin_pitch(x, sr, fmin=50.0, fmax=1200.0, hop_s=0.01):
    """YIN (CMNDF) on a 16 kHz copy. Returns times, f0 (nan = unvoiced),
    aperiodicity (0 = perfectly periodic, 1 = noise)."""
    import numpy as np
    import scipy.signal
    target = 16000
    g = math.gcd(int(sr), target)
    y = scipy.signal.resample_poly(x, target // g, int(sr) // g) if sr != target else x
    W = 1024
    tau_max = int(target / fmin)              # 320
    tau_min = max(2, int(target / fmax))      # 13
    L = W - tau_max
    hop = int(round(hop_s * target))
    pad = np.pad(y, (W // 2, W // 2))
    fr = frame_signal(pad, W, hop)
    n = fr.shape[0]
    N = 2048
    A = np.fft.rfft(fr[:, :L], N, axis=1)
    B = np.fft.rfft(fr, N, axis=1)
    r = np.fft.irfft(np.conj(A) * B, N, axis=1)[:, :tau_max + 1]
    sq = fr ** 2
    cs = np.concatenate([np.zeros((n, 1)), np.cumsum(sq, axis=1)], axis=1)
    taus = np.arange(tau_max + 1)
    e0 = cs[:, L][:, None]
    et = cs[:, taus + L] - cs[:, taus]
    d = np.maximum(e0 + et - 2 * r, 0)
    d[:, 0] = 0
    cum = np.cumsum(d[:, 1:], axis=1)
    cmndf = np.ones_like(d)
    cmndf[:, 1:] = d[:, 1:] * taus[1:][None, :] / np.maximum(cum, 1e-12)
    f0 = np.full(n, np.nan)
    aper = np.ones(n)
    thr = 0.15
    for i in range(n):
        c = cmndf[i]
        seg = c[tau_min:tau_max]
        below = np.where(seg < thr)[0]
        if len(below):
            t = below[0] + tau_min
            while t + 1 < tau_max and c[t + 1] < c[t]:
                t += 1
        else:
            t = int(np.argmin(seg)) + tau_min
        aper[i] = float(clamp(c[t], 0.0, 1.0))
        # voicing gate = the standard YIN threshold; measured on the
        # self-test material: tones <= 0.05, inharmonic cluster ~0.20
        if c[t] < thr:
            if 1 <= t < tau_max:
                a, b, cc = c[t - 1], c[t], c[t + 1]
                den = a - 2 * b + cc
                tt = t + (0.5 * (a - cc) / den if abs(den) > 1e-12 else 0.0)
            else:
                tt = t
            f0[i] = target / tt
    times = np.arange(n) * hop / target
    return times, f0, aper


def praat_intensity(x, sr, min_pitch):
    """Approximation of Praat Sound: To Intensity (subtract mean = yes):
    squared signal under a Kaiser-20 window of physical length
    6.4/min_pitch (effective 3.2/min_pitch), step 0.8/min_pitch.
    Checked against Praat 7.0 To TextGrid (silences) on 26 signals x 8
    settings: exact segment count in 84%, otherwise off by one (dense
    material near the threshold)."""
    import numpy as np
    win = max(4, int(round(6.4 / min_pitch * sr)))
    hop = max(1, int(round(0.8 / min_pitch * sr)))
    w = np.kaiser(win, 20)
    w = w / w.sum()
    x = x - x.mean()
    n = 1 + max(0, (len(x) - win)) // hop
    if len(x) < win:
        return np.array([len(x) / 2 / sr]), np.array([-300.0])
    fr = frame_signal(x, win, hop)
    p = (fr ** 2) @ w
    db = 10 * np.log10(p / 4e-10 + 1e-30)
    t = (np.arange(n) * hop + win / 2) / sr
    return t, db


def praat_silences(t, db, dur, thr_db, min_silent, min_sounding):
    """Emulation of Intensity: To TextGrid (silences). Returns list of
    sounding intervals (start, end)."""
    import numpy as np
    mx = float(np.max(db))
    sounding = db >= mx - thr_db
    # frame boundaries halfway between frame centres
    edges = np.concatenate([[0.0], (t[1:] + t[:-1]) / 2, [dur]])
    ivs = []
    cur = bool(sounding[0])
    start = 0.0
    for i in range(1, len(sounding)):
        if bool(sounding[i]) != cur:
            ivs.append([start, edges[i], cur])
            start = edges[i]
            cur = bool(sounding[i])
    ivs.append([start, dur, cur])

    def merge(ivs):
        out = []
        for iv in ivs:
            if out and out[-1][2] == iv[2]:
                out[-1][1] = iv[1]
            else:
                out.append(list(iv))
        return out
    # 1. short silences become sounding
    for iv in ivs:
        if not iv[2] and iv[1] - iv[0] < min_silent:
            iv[2] = True
    ivs = merge(ivs)
    # 2. short soundings become silent
    for iv in ivs:
        if iv[2] and iv[1] - iv[0] < min_sounding:
            iv[2] = False
    ivs = merge(ivs)
    return [(a, b) for a, b, s in ivs if s]


def groove_event_emulation(x, sr, onset_thr_db=-20.0, min_silence=0.05, max_segment=0.15):
    """Mirror of the onset detector + 3-band classifier inside
    'Percussive Audio Groove Creator.praat' (v0.5.1), so eligibility is
    judged with the script's own rules. Returns (events, counts)."""
    import numpy as np
    dur = len(x) / sr
    t, db = praat_intensity(x, sr, 70.0)
    thr = float(np.max(db)) + onset_thr_db
    nyq = sr / 2
    events = []
    last = -1.0
    for f in range(2, len(db) - 2):
        tm = t[f]
        if not (0.02 < tm < dur - 0.05):
            continue
        if tm - last <= min_silence:
            continue
        c = db[f]
        if c > db[f - 1] and c > db[f - 2] and c > db[f + 1] and c > thr:
            a = int(max(0, tm - 0.005) * sr)
            b = int(min(dur, tm + max_segment) * sr)
            seg = x[a:b]
            if len(seg) / sr <= 0.015:
                continue
            nfft = 1 << int(math.ceil(math.log2(len(seg))))
            P = np.abs(np.fft.rfft(seg, nfft)) ** 2
            fq = np.fft.rfftfreq(nfft, 1.0 / sr)
            def band(lo, hi):
                hi = min(hi, nyq)
                if hi <= lo:
                    return 0.0
                return float(P[(fq >= lo) & (fq < hi)].sum())
            lo_e, mi_e, hi_e = band(20, 250), band(250, 4000), band(4000, 18000)
            tot = lo_e + mi_e + hi_e
            typ = 0
            if tot > 0:
                if lo_e / tot > 0.55:
                    typ = 1
                elif hi_e / tot > 0.35:
                    typ = 2
                elif mi_e / tot > 0.4:
                    typ = 3
            if typ:
                events.append((tm, typ))
                last = tm
    counts = [sum(1 for e in events if e[1] == k) for k in (1, 2, 3)]
    return events, counts


def onset_detect(mag, hop_s):
    """Spectral-flux onsets with an adaptive median threshold."""
    import numpy as np
    import scipy.signal
    lm = np.log1p(100 * mag / (mag.max() + 1e-12))
    flux = np.maximum(np.diff(lm, axis=0), 0).sum(axis=1)
    flux = np.concatenate([[0.0], flux])
    if flux.max() <= 0:
        return np.array([], dtype=int), flux
    nov = flux / flux.max()
    k = max(3, int(round(0.25 / hop_s)) | 1)
    med = scipy.signal.medfilt(nov, k)
    thr = med + 0.12 + 0.5 * np.std(nov)
    peaks, _ = scipy.signal.find_peaks(nov, height=thr,
                                       distance=max(1, int(round(0.05 / hop_s))))
    return peaks, nov


# ============================================================
# feature extraction
# ============================================================
def extract_features(audio, sr):
    import numpy as np
    import scipy.signal
    x = to_mono(audio)
    dur = len(x) / sr
    F = {"duration": dur, "sr": sr}
    hop_s = 0.01

    # ---- energy envelope ----
    env = rms_envelope_db(x, sr, hop_s)
    peak_db = float(env.max())
    floor_db = float(max(np.percentile(env, 5), peak_db - 60))
    active = env > max(floor_db + 6, peak_db - 40)
    F["active_ratio"] = float(active.mean())
    smooth = np.convolve(env, np.ones(5) / 5, mode="same")
    act_vals = smooth[active] if active.any() else smooth
    F["env_dyn_range_db"] = float(np.percentile(act_vals, 95) - np.percentile(smooth, 10))
    pk, _ = scipy.signal.find_peaks(smooth, prominence=6, distance=int(0.1 / hop_s))
    pk = [p for p in pk if smooth[p] > peak_db - 30]
    F["env_peaks"] = len(pk)
    F["env_peak_rate"] = len(pk) / max(dur, 1e-6)
    d1 = np.diff(smooth[active]) if active.sum() > 3 else np.array([0.0])
    F["env_complexity"] = float(np.std(d1))
    if active.sum() > 3:
        ta = np.arange(len(env))[active] * hop_s
        F["energy_slope_db_s"] = float(np.polyfit(ta, smooth[active], 1)[0])
    else:
        F["energy_slope_db_s"] = 0.0

    # ---- silent gaps inside the phrase (between first and last activity) ----
    gaps = []
    if active.any():
        ia = np.where(active)[0]
        inner = active[ia[0]:ia[-1] + 1]
        run = 0
        for v in inner:
            if not v:
                run += 1
            else:
                if run * hop_s >= 0.08:
                    gaps.append(run * hop_s)
                run = 0
        F["silence_ratio"] = float(1 - inner.mean())
    else:
        F["silence_ratio"] = 1.0
    F["silent_gaps_n"] = len(gaps)
    F["gap_median"] = float(np.median(gaps)) if gaps else 0.0

    # ---- pitch / periodicity ----
    pt, f0, aper = yin_pitch(x, sr, hop_s=hop_s)
    n = min(len(f0), len(active))
    f0, aper, act_p = f0[:n], aper[:n], active[:n]
    voiced = (~np.isnan(f0)) & act_p
    F["voiced_ratio"] = float(voiced.sum() / max(act_p.sum(), 1))
    per = 1 - aper[act_p] if act_p.any() else np.array([0.0])
    pmed = float(clamp(np.median(per), 1e-4, 0.9999))
    F["periodicity"] = pmed
    F["hnr_db"] = float(10 * math.log10(pmed / (1 - pmed)))
    if voiced.sum() >= 5:
        st = 12 * np.log2(f0[voiced] / 100.0)
        tv = np.arange(n)[voiced] * hop_s
        st_s = scipy.signal.medfilt(st, 5) if len(st) >= 5 else st
        F["f0_median"] = float(100 * 2 ** (np.median(st_s) / 12))
        F["f0_p5"] = float(100 * 2 ** (np.percentile(st_s, 5) / 12))
        F["f0_p95"] = float(100 * 2 ** (np.percentile(st_s, 95) / 12))
        F["pitch_range_st"] = float(np.percentile(st_s, 95) - np.percentile(st_s, 5))
        slope = float(np.polyfit(tv, st_s, 1)[0]) if len(tv) > 2 else 0.0
        F["pitch_slope_st_s"] = slope
        F["f0_std_st"] = float(np.std(st_s - np.polyval(np.polyfit(tv, st_s, 1), tv))
                               if len(tv) > 2 else 0.0) if F["pitch_range_st"] < 2 else float(np.std(st_s))
        q = max(1, len(st_s) // 10)
        F["pitch_net_change_st"] = float(np.median(st_s[-q:]) - np.median(st_s[:q]))
        ds = np.diff(st_s)
        jumps = np.abs(ds) > 2.0
        moving = ds[~jumps]
        sgn = np.sign(F["pitch_net_change_st"]) or 1.0
        F["pitch_monotonicity"] = float(np.sum(np.maximum(moving * sgn, 0)) /
                                        max(np.sum(np.abs(moving)), 1e-9))
        # continuity: longest voiced run (allow 30 ms holes) / voiced frames
        runs, cur, hole = [], 0, 0
        for v in voiced:
            if v:
                cur += 1 + hole if cur else 1
                hole = 0
            else:
                hole += 1
                if hole > 3:
                    if cur:
                        runs.append(cur)
                    cur, hole = 0, 0
        if cur:
            runs.append(cur)
        F["pitch_continuity"] = float(max(runs) / max(voiced.sum(), 1)) if runs else 0.0
        F["voiced_runs"] = len(runs)
        F["pitch_breaks_per_s"] = float((int(jumps.sum()) + max(len(runs) - 1, 0)) / max(dur, 1e-6))
        F["pitch_rate_st_s"] = float(np.mean(np.abs(moving)) / hop_s) if len(moving) else 0.0
    else:
        for k in ("f0_median", "f0_p5", "f0_p95"):
            F[k] = float("nan")
        for k in ("pitch_range_st", "pitch_slope_st_s", "f0_std_st", "pitch_net_change_st",
                  "pitch_monotonicity", "pitch_continuity", "pitch_breaks_per_s",
                  "pitch_rate_st_s"):
            F[k] = 0.0
        F["voiced_runs"] = 0
    F["voiced_frames"] = int(voiced.sum())

    # ---- spectrum ----
    hop = int(round(hop_s * sr))
    mag, fq = stft_mag(x, sr, 1024, hop)
    m = min(len(mag), len(active))
    mag, act_s = mag[:m], active[:m]
    P = mag ** 2
    band = (fq >= 50) & (fq <= min(16000, sr / 2))
    Pb = P[:, band] + 1e-20
    cen = (P[:, band] @ fq[band]) / np.maximum(P[:, band].sum(axis=1), 1e-20)
    flat = np.exp(np.mean(np.log(Pb), axis=1)) / np.mean(Pb, axis=1)
    sel = act_s if act_s.sum() > 3 else np.ones(m, bool)
    F["centroid_mean"] = float(np.mean(cen[sel]))
    F["centroid_cv"] = float(np.std(np.log(cen[sel] + 1)) )
    F["flatness"] = float(np.median(flat[sel]))
    lm = np.log1p(100 * mag / (mag.max() + 1e-12))
    fl = np.concatenate([[0.0], np.sqrt((np.maximum(np.diff(lm, axis=0), 0) ** 2).sum(axis=1))])
    flv = fl[sel]
    F["flux_mean"] = float(np.mean(flv))
    F["flux_cv"] = float(np.std(flv) / max(np.mean(flv), 1e-9))
    F["spectral_abruptness"] = float(np.percentile(flv, 95) / max(np.median(flv), 1e-9))
    fb = mel_filterbank(sr, 1024)
    mf = mfcc_from_mag(mag, fb)
    F["mfcc_frame_var"] = float(np.mean(np.std(mf[sel], axis=0)))
    seg_len = max(1, int(round(0.25 / hop_s)))
    blocks = [mf[i:i + seg_len][sel[i:i + seg_len]] for i in range(0, m, seg_len)]
    blocks = [b.mean(axis=0) for b in blocks if len(b) >= 3]
    F["spectral_variability"] = float(np.mean(np.std(np.array(blocks), axis=0))) if len(blocks) > 1 else 0.0

    # ---- onsets / temporal ----
    pk_on, nov = onset_detect(mag, hop_s)
    pk_on = np.array([p for p in pk_on if p < len(active) and
                      (active[max(0, p - 1):p + 4].any())], dtype=int)
    on_t = pk_on * hop_s
    F["onsets_n"] = int(len(on_t))
    act_dur = max(float(active.sum()) * hop_s, 0.1)
    F["onset_rate"] = float(len(on_t) / max(dur, 1e-6))
    if len(on_t) >= 2:
        ioi = np.diff(on_t)
        F["ioi_median"] = float(np.median(ioi))
        F["ioi_cv"] = float(np.std(ioi) / max(np.mean(ioi), 1e-9))
        F["ioi_min"] = float(np.min(ioi))
    else:
        F["ioi_median"] = 0.0
        F["ioi_cv"] = 0.0
        F["ioi_min"] = 0.0
    if dur >= 1.5 and len(on_t) >= 3:
        cs, wl = [], 1.0
        for s0 in np.arange(0, dur - wl + 1e-9, 0.25):
            cs.append(np.sum((on_t >= s0) & (on_t < s0 + wl)))
        cs = np.array(cs, float)
        F["density_cv"] = float(np.std(cs) / max(np.mean(cs), 1e-9))
        half = dur / 2
        r1 = np.sum(on_t < half) / half
        r2 = np.sum(on_t >= half) / half
        F["density_trend"] = float((r2 - r1) / max((r1 + r2) / 2, 1e-9))
    else:
        F["density_cv"] = 0.0
        F["density_trend"] = 0.0
    # attack sharpness and decay per onset -> transient / impulsive character
    rises, imp = [], []
    for p in pk_on:
        a = max(0, p - 3)
        top = min(len(smooth) - 1, p + 4)
        pkv = float(np.max(env[p:top + 1])) if top >= p else float(env[p])
        rise = pkv - float(env[a])
        later = min(len(env) - 1, p + 15)
        decay = pkv - float(np.mean(env[min(later, len(env) - 1):min(later + 3, len(env))]))
        rises.append(rise)
        imp.append(sig(rise, 10, 3) * sig(decay, 12, 4))
    F["transient_strength_db"] = float(np.median(rises)) if rises else 0.0
    impulsive = float(np.mean(imp)) if imp else 0.0
    F["impulsive"] = impulsive
    F["perc_char"] = float(impulsive * (1 - 0.65 * sig(F["hnr_db"], 6, 3)))

    # ---- Praat-emulated segmentation (MDS Space Navigator) ----
    t_i, db_i = praat_intensity(x, sr, 100.0)
    mds_cfg = None
    for thr in (25.0, 20.0, 30.0, 35.0):
        for msil in (0.1, 0.06):
            segs = praat_silences(t_i, db_i, dur, thr, msil, 0.1)
            if len(segs) >= 3:
                mds_cfg = (thr, msil, segs)
                break
        if mds_cfg:
            break
    if mds_cfg is None:
        segs = praat_silences(t_i, db_i, dur, 25.0, 0.1, 0.1)
        mds_cfg = (25.0, 0.1, segs)
    thr, msil, segs = mds_cfg
    F["mds_thr_db"] = thr
    F["mds_min_silent"] = msil
    F["mds_segments"] = len(segs)
    F["mds_seg_median_dur"] = float(np.median([b - a for a, b in segs])) if segs else 0.0
    if len(segs) >= 2:
        gaps_m = [segs[i + 1][0] - segs[i][1] for i in range(len(segs) - 1)]
        F["mds_gap_median"] = float(np.median(gaps_m))
    else:
        F["mds_gap_median"] = 0.0
    if len(segs) >= 2:
        means, within = [], []
        for a, b in segs:
            ia, ib = int(a / hop_s), int(b / hop_s)
            blk = mf[ia:max(ib, ia + 1)]
            if len(blk):
                means.append(blk.mean(axis=0))
                within.append(np.mean(np.std(blk, axis=0)) if len(blk) > 1 else 0.0)
        means = np.array(means)
        if len(means) >= 2:
            dd = [np.linalg.norm(means[i] - means[j]) for i in range(len(means))
                  for j in range(i + 1, len(means))]
            F["mds_timbre_spread"] = float(np.mean(dd) / max(np.mean(within) + 1.0, 1e-9))
        else:
            F["mds_timbre_spread"] = 0.0
    else:
        F["mds_timbre_spread"] = 0.0

    # ---- Praat-emulated percussive events (Groove Creator) ----
    gcfg = None
    for othr in (-20.0, -25.0, -30.0):
        ev, cnt = groove_event_emulation(x, sr, othr, 0.05, 0.15)
        if len(ev) >= 3:
            gcfg = (othr, ev, cnt)
            break
    if gcfg is None:
        ev, cnt = groove_event_emulation(x, sr, -20.0, 0.05, 0.15)
        gcfg = (-20.0, ev, cnt)
    F["groove_onset_thr_db"] = gcfg[0]
    F["groove_events"] = len(gcfg[1])
    F["groove_bass"], F["groove_hh"], F["groove_snare"] = gcfg[2]
    F["groove_types"] = sum(1 for c in gcfg[2] if c > 0)

    # ---- Markov grain bookkeeping (script rule: nGrains >= 2k, dur >= 4 grains) ----
    F["markov_grains_80ms"] = int(math.floor((dur - 0.08) / 0.04) + 1) if dur > 0.08 else 0

    # keep arrays for parameter mapping (not reported)
    F["_per"] = 1 - aper
    F["_active"] = active
    F["_hop"] = hop_s
    # v0.3.0 sonic memory: raw material for the retrieval descriptor (private
    # keys; the six-transformation classifier never reads them)
    F["_f0"] = f0
    F["_env"] = smooth
    F["_mfcc_mean"] = mf[sel].mean(axis=0) if sel.any() else mf.mean(axis=0)
    return F


# ============================================================
# transformation scoring: eligibility + score + params
# ============================================================
def nz(v, default=0.0):
    return default if v is None or (isinstance(v, float) and math.isnan(v)) else v


def raw_scores(F):
    """Component scores (0..1) per transformation, before safeguards."""
    S, C = {}, {}
    # 1 Paulstretch - stable harmonic, sustained
    c = {
        "harmonic": sig(F["hnr_db"], 6, 3),
        "voiced": sig(F["voiced_ratio"], 0.6, 0.1),
        "pitch_stable": 1 - sig(F["f0_std_st"], 1.0, 0.4),
        "low_density": 1 - sig(F["onset_rate"], 2.0, 0.7),
        "sustained": 1 - sig(F["silence_ratio"], 0.25, 0.08),
        "no_glissando": 1 - sig(F["pitch_range_st"], 4, 1.2),
        "stable_envelope": 1 - sig(F["env_peak_rate"], 1.0, 0.35),
        "flat_dynamics": 1 - sig(F["env_dyn_range_db"], 9, 2.5),
    }
    w = {"harmonic": 1.2, "voiced": 1.0, "pitch_stable": 1.2, "low_density": 1.0,
         "sustained": 1.0, "no_glissando": 1.0, "stable_envelope": 0.8,
         "flat_dynamics": 1.0}
    S["paulstretch"], C["paulstretch"] = wmean(c, w), c
    # 2 Markov - noisy, aperiodic, timbrally varying, continuous
    c = {
        "flat_spectrum": sig(F["flatness"], 0.2, 0.06),
        "aperiodic": 1 - sig(F["hnr_db"], 3, 2.5),
        "unvoiced": 1 - sig(F["voiced_ratio"], 0.4, 0.12),
        "timbral_variation": sig(F["spectral_variability"], 1.0, 0.5),
        "continuous": 1 - sig(F["silence_ratio"], 0.3, 0.08),
    }
    w = {"flat_spectrum": 1.3, "aperiodic": 1.0, "unvoiced": 0.8,
         "timbral_variation": 0.8, "continuous": 1.0}
    S["markov"], C["markov"] = wmean(c, w), c
    # 3 MDS - discrete separable segments with distinct timbres
    c = {
        "segments": sig(F["mds_segments"], 3.5, 0.8),
        "separated": sig(F["silence_ratio"], 0.15, 0.06),
        "onset_density": sig(F["onset_rate"], 1.2, 0.5),
        "timbre_diff": sig(F["mds_timbre_spread"], 0.6, 0.25),
    }
    w = {"segments": 1.2, "separated": 1.0, "onset_density": 0.8, "timbre_diff": 0.8}
    S["mds"], C["mds"] = wmean(c, w), c
    # 4 Spiral - continuous voiced glissando
    c = {
        "pitch_range": sig(F["pitch_range_st"], 4, 1.2),
        "monotonic": sig(F["pitch_monotonicity"], 0.6, 0.1),
        "continuous": sig(F["pitch_continuity"], 0.6, 0.1),
        "voiced": sig(F["voiced_ratio"], 0.6, 0.1),
        "trend": sig(abs(F["pitch_net_change_st"]), 3, 1),
        "unfragmented": 1 - sig(F["pitch_breaks_per_s"], 1.0, 0.4),
    }
    w = {"pitch_range": 1.2, "monotonic": 1.0, "continuous": 1.0, "voiced": 0.8,
         "trend": 1.0, "unfragmented": 0.8}
    S["spiral"], C["spiral"] = wmean(c, w), c
    # 5 MC varispeed - complex dynamic envelope determines spread across 8 constant speeds
    c = {
        "dynamic_range": sig(F["env_dyn_range_db"], 10, 3),
        "env_peaks": sig(F["env_peaks"], 3, 1),
        "fluctuation_rate": sig(F["env_peak_rate"], 0.8, 0.3),
        "env_complexity": sig(F["env_complexity"], 0.3, 0.12),
    }
    w = {"dynamic_range": 1.0, "env_peaks": 1.0, "fluctuation_rate": 0.8, "env_complexity": 1.0}
    S["speeddev"], C["speeddev"] = wmean(c, w), c
    # 6 Groove - percussive events with changing density
    c = {
        "percussive": sig(F["perc_char"], 0.45, 0.1),
        "events": sig(F["groove_events"], 4, 1.2),
        "onset_rate": sig(F["onset_rate"], 2.0, 0.8),
        "density_change": sig(max(F["density_cv"], abs(F["density_trend"])), 0.25, 0.08),
        "transients": sig(F["transient_strength_db"], 10, 3),
        "drum_classes": sig(F["groove_types"], 1.5, 0.3),
    }
    w = {"percussive": 1.3, "events": 1.0, "onset_rate": 0.8, "density_change": 0.8,
         "transients": 0.8, "drum_classes": 0.6}
    S["groove"], C["groove"] = wmean(c, w), c
    return S, C


def wmean(c, w):
    return sum(c[k] * w[k] for k in c) / sum(w[k] for k in c)


def eligibility(F):
    """Hard gates per transformation, mirroring each script's input needs.
    Returns {id: (ok, reason)}."""
    E = {}
    def gate(conds):
        bad = [msg for ok, msg in conds if not ok]
        return (len(bad) == 0, "; ".join(bad) if bad else "ok")
    E["paulstretch"] = gate([
        (F["duration"] >= 0.4, "phrase shorter than 0.4 s"),
        (F["voiced_ratio"] >= 0.35, "voiced ratio %.2f < 0.35" % F["voiced_ratio"]),
        (F["hnr_db"] >= 2.0, "harmonicity %.1f dB < 2" % F["hnr_db"]),
    ])
    E["markov"] = gate([
        (F["markov_grains_80ms"] >= 8, "fewer than 8 grains of 80 ms (script needs 2 x states)"),
        (F["flatness"] >= 0.05 or F["hnr_db"] < 6,
         "spectrum neither flat (%.2f) nor aperiodic (%.1f dB)" % (F["flatness"], F["hnr_db"])),
    ])
    E["mds"] = gate([
        (F["mds_segments"] >= 3,
         "Praat silence segmentation finds %d segment(s) < 3" % F["mds_segments"]),
        (F["mds_seg_median_dur"] >= 0.1, "segments too short for MFCC analysis"),
    ])
    E["spiral"] = gate([
        (F["voiced_frames"] >= 20, "no valid pitch trajectory (%d voiced frames)" % F["voiced_frames"]),
        (F["voiced_ratio"] >= 0.4, "voiced ratio %.2f < 0.4" % F["voiced_ratio"]),
        (F["pitch_range_st"] >= 2.0, "pitch range %.1f st < 2" % F["pitch_range_st"]),
        (F["pitch_continuity"] >= 0.4, "pitch contour fragmented (continuity %.2f)" % F["pitch_continuity"]),
    ])
    E["speeddev"] = gate([
        (F["env_peaks"] >= 2, "fewer than 2 dynamic peaks"),
        (F["env_dyn_range_db"] >= 6, "dynamic range %.1f dB < 6" % F["env_dyn_range_db"]),
    ])
    E["groove"] = gate([
        (F["groove_events"] >= 3,
         "Groove Creator detector finds %d classified event(s) < 3" % F["groove_events"]),
        (F["perc_char"] >= 0.25, "not percussive enough (%.2f < 0.25)" % F["perc_char"]),
    ])
    return E


def score_all(F):
    """Raw scores -> cross-category safeguards -> eligibility mask."""
    S, C = raw_scores(F)
    notes = []
    # glissando must not read as stable harmonic material
    g = sig(F["pitch_range_st"], 5, 1.5) * sig(F["pitch_monotonicity"], 0.6, 0.1)
    if g > 0.05:
        S["paulstretch"] *= (1 - 0.5 * g)
        notes.append("paulstretch x%.2f (glissando safeguard)" % (1 - 0.5 * g))
    # noisy percussion must not read as a continuous noise texture
    pc = F["perc_char"]
    S["markov"] *= (1 - 0.6 * pc)
    if pc > 0.05:
        notes.append("markov x%.2f (percussive safeguard)" % (1 - 0.6 * pc))
    # tonal attack sequences belong to MDS more than to the drum classifier
    S["mds"] *= (1 - 0.5 * pc)
    if pc > 0.05:
        notes.append("mds x%.2f (percussive events prefer Groove)" % (1 - 0.5 * pc))
    # The envelope-driven MC speed spread yields to strongly supported,
    # more input-specific and ELIGIBLE categories.
    E = eligibility(F)
    others = [v for k, v in S.items() if k != "speeddev" and E[k][0]]
    other = max(others) if others else 0.0
    dom = 1 - 0.45 * sig(other, 0.6, 0.08)
    S["speeddev"] *= dom
    if dom < 0.98:
        notes.append("speeddev x%.2f (an eligible specific category scores %.2f)" % (dom, other))
    return S, C, E, notes


def decide(F, forced=None):
    S, C, E, notes = score_all(F)
    ranking = [k for k in TRANSFORM_IDS if E[k][0] and S[k] >= CONFIDENCE_THRESHOLD[k]]
    ranking.sort(key=lambda k: (-round(S[k], 6), TIE_PRIORITY.index(k)))
    info = {"scores": S, "components": C, "elig": E, "notes": notes, "ranking": ranking}
    if forced and forced in TRANSFORM_IDS:
        info["mode"] = "manual"
        info["selected"] = forced
        if not E[forced][0]:
            info["warning"] = "manual choice is INELIGIBLE: " + E[forced][1]
    else:
        info["mode"] = "auto"
        info["selected"] = ranking[0] if ranking else "passthrough"
    if len(ranking) >= 2 and S[ranking[0]] - S[ranking[1]] < AMBIGUITY_MARGIN:
        info["ambiguous"] = "%s %.3f vs %s %.3f" % (ranking[0], S[ranking[0]],
                                                    ranking[1], S[ranking[1]])
    return info


# ---------------- parameter mapping ----------------
def params_all(F, audio, sr, nch, seed):
    P = {}
    dur = F["duration"]
    # 1 Paulstretch: stability -> stretch, response length capped
    stab = 0.5 * (sig(F["hnr_db"], 6, 3) + (1 - sig(F["f0_std_st"], 1.0, 0.4)))
    stretch = 2.0 + 4.0 * stab
    crop = (0.0, dur)
    if dur * stretch > MAX_RESPONSE_S:
        stretch = max(2.0, MAX_RESPONSE_S / dur)
        if dur * stretch > MAX_RESPONSE_S + 1e-6:
            crop = most_stable_window(F, MAX_RESPONSE_S / stretch)
    f0m = nz(F["f0_median"], 200.0)
    P["paulstretch"] = {
        "stretch": round(stretch, 3),
        "window": 0.35 if f0m < 110 else 0.25,
        "overlap": 75,
        "stereo": 1,
        "phase_offset": 0.3,
        "crop_start": round(crop[0], 4),
        "crop_end": round(crop[1], 4),
        "expected_out_s": round((crop[1] - crop[0]) * stretch, 2),
    }
    # 2 Markov: spectral variability -> states, flux changes -> grain
    g_ms = clamp(110 - 30 * sig(F["flux_cv"], 1.0, 0.4), 50, 140)
    k = int(round(4 + 4 * sig(F["spectral_variability"], 1.0, 0.5)))
    n_gr = math.floor((dur - g_ms / 1000) / (g_ms / 1000 * 0.5)) + 1 if dur > g_ms / 1000 else 0
    while k > 2 and n_gr < 2 * k:
        k -= 1
    if dur < 4 * g_ms / 1000:
        g_ms = clamp(dur / 4 * 1000 * 0.95, 20, 140)
    P["markov"] = {
        "grain_ms": round(g_ms, 1),
        "analysis_overlap": 0.5,
        "states": k,
        "randomness": round(clamp(0.1 + 0.3 * sig(F["centroid_cv"], 0.2, 0.08), 0.1, 0.4), 3),
        "out_dur": round(clamp(1.25 * dur, 4.0, MAX_RESPONSE_S), 2),
        "synth_overlap": 0.5,
        "varispeed": 0.0,
        "jitter": 0.1,
        "density_var": round(clamp(0.25 * F["density_cv"], 0.0, 0.3), 3),
        "decorrelation": 0.3 if nch >= 1 else -1,
        "seed": seed,
        "grains_available": n_gr,
    }
    # 3 MDS: segmentation emulated in Python with the script's own rules
    segd = F["mds_seg_median_dur"] or 0.2
    gap = F["mds_gap_median"] or 0.1
    P["mds"] = {
        "silence_threshold_db": F["mds_thr_db"],
        "min_silent": F["mds_min_silent"],
        "min_sounding": 0.1,
        "max_formant": 5500,
        "n_formants": 5,
        "n_mfcc": 12,
        "between": round(clamp(0.5 * gap, 0.03, 0.2), 3),
        "expected_segments": F["mds_segments"],
        "segment_median_s": round(segd, 3),
    }
    # 4 Spiral: range -> semitones, movement rate -> acceleration, length -> spirals
    fl = nz(F["f0_p5"], 80.0)
    fh = nz(F["f0_p95"], 600.0)
    floor_p = clamp(0.7 * fl, 50.0, 400.0)
    ceil_p = clamp(1.5 * fh, floor_p * 2, min(1200.0, 0.45 * sr - 1))
    P["spiral"] = {
        "spirals": int(clamp(round(1 + dur / 3.0), 1, 3)),
        "semitones": round(clamp(F["pitch_range_st"], 3.0, 12.0), 2),
        "acceleration": round(clamp(1 + F["pitch_rate_st_s"] / 30.0, 1.0, 2.0), 3),
        "time_step": 0.005,
        "floor": round(floor_p, 1),
        "ceiling": round(ceil_p, 1),
    }
    # 5 MAX MC Deviate (v0.7): envelope controls speed deviation *between* channels.
    # Each channel runs at one constant playback speed. Pitch and D/s duration
    # change together; there is NO intra-channel time-varying acceleration.
    # Envelope variation is used as a musical gesture -> spatial/rate spread:
    # subtle fluctuations = subtle varispeed dispersion; intricate swells
    # = larger differences across eight static playback rates.
    dyn = sig(F["env_dyn_range_db"], 12.0, 4.0)
    complexity = sig(F["env_complexity"], 0.45, 0.20)
    peaks = sig(F["env_peaks"], 4.0, 1.25)
    spread = clamp(0.06 + 0.12 * dyn + 0.12 * complexity + 0.10 * peaks,
                   0.06, 0.40)
    # For d in [0,0.95], speed factors are uniform in [1-d,1+d].
    # All output durations obey D/(1+d) <= duration <= D/(1-d).
    # Use the slowest possible channel for an actual hard output cap.
    deviation_cap = max(0.0, 1.0 - dur / MAX_RESPONSE_S)
    spread = min(spread, deviation_cap, 0.40)
    P["speeddev"] = {
        "preset": "MAX MC Deviate (fresh random every run)",
        "deviation": round(spread, 4),
        "min_speed": round(1.0 - spread, 4),
        "max_speed": round(1.0 + spread, 4),
        "min_channel_duration_s": round(dur / (1.0 + spread), 3),
        "max_channel_duration_s": round(dur / max(1.0 - spread, 1e-6), 3),
        "engine": "MC-style varispeed (pitch follows speed)",
        "output": "MC stereo mix (odd L / even R)",
        "random_seed": 0,  # Preset overrides seed and draws fresh factors every time
    }
    # 6 Groove: IOIs -> tempo (with documented fallback), density -> groove
    tempo, reliable = estimate_tempo(F)
    beat = 60.0 / tempo
    bars = min((1, 2, 4), key=lambda b: abs(b * 4 * beat - dur))
    dt, dcv = F["density_trend"], F["density_cv"]
    if F["onset_rate"] < 1.0:
        pattern = "Sparse Minimal"
    elif dt > 0.5:
        pattern = "Double-time Feel"
    elif dt < -0.5:
        pattern = "Half-time Feel"
    elif dcv > 0.6:
        pattern = "Breakbeat"
    elif F["ioi_cv"] > 0.5:
        pattern = "Syncopated Funk"
    else:
        pattern = "Standard 4/4"
    P["groove"] = {
        "bars": bars,
        "pattern": pattern,
        "tempo": round(tempo, 2),
        "tempo_reliable": int(reliable),
        "onset_thr_db": F["groove_onset_thr_db"],
        "min_silence": round(clamp(0.5 * F["ioi_min"], 0.03, 0.08) if F["ioi_min"] > 0 else 0.05, 3),
        "max_segment": 0.15,
        "density": round(clamp(0.35 + 0.08 * F["onset_rate"], 0.3, 0.9), 3),
        "clip_max": 0.12,
        "attack": 0.002,
        "release": 0.05,
        "shape": 1.2,
        "stereo": 1,
    }
    return P


def estimate_tempo(F):
    """Median IOI folded into 80-160 BPM. Unreliable -> 100 BPM fallback."""
    if F["onsets_n"] >= 4 and F["ioi_median"] > 0 and F["ioi_cv"] <= 0.6:
        bpm = 60.0 / F["ioi_median"]
        while bpm < 80:
            bpm *= 2
        while bpm >= 160:
            bpm /= 2
        return bpm, True
    return 100.0, False


def most_stable_window(F, length):
    import numpy as np
    per = F["_per"]
    act = F["_active"][:len(per)]
    hop = F["_hop"]
    w = max(1, int(round(length / hop)))
    score = per[:len(act)] * act
    if len(score) <= w:
        return (0.0, F["duration"])
    cs = np.concatenate([[0], np.cumsum(score)])
    best = int(np.argmax(cs[w:] - cs[:-w]))
    return (best * hop, min(F["duration"], best * hop + length))


def audio_seed(audio):
    import numpy as np
    b = np.ascontiguousarray(audio, dtype=np.float32).tobytes()
    return 1 + (zlib.crc32(b) % 2000000000)


# ============================================================
# phrase detection (pure state machine, testable without hardware)
# ============================================================
class PhraseDetector:
    """IDLE -> (calibrate) -> LISTENING -> PHRASE -> done.
    Feed blocks of exactly `hop` frames.  Hysteresis: onset needs
    `on_frames` consecutive frames above floor + sensitivity; the phrase
    stays alive while frames exceed (onset threshold - hysteresis);
    `end_silence` of continuous quiet ends it; phrases shorter than
    `min_phrase` are discarded as false triggers.
    v0.4.10:
    - STABLE noise floor: it learns only from input within 3 dB of it
      (slowly, time constant ~2.5 s) and falls quickly; input that stays
      higher for 4 s without a phrase is taken as a change of room noise
      and learned (~1 s).  Before, the floor rose 3 %% per 10 ms with ANY
      input below the threshold, so a crescendo pulled the threshold up
      with it and was never detected.
    - GRADUAL ENTRY: a phrase is captured from where its rise began
      (walking back while above floor + 3 dB, up to 2 s), not only 0.25 s
      before the threshold was crossed.
    - LONG PHRASE: at max_phrase the phrase is cut at its quietest point in
      the last 30 %% (the latest frame within 3 dB of the quietest) and the
      rest CONTINUES as the next phrase (rearm) - no sample is lost.  A
      phrase that reaches max_phrase completely FLAT (< 4 dB between its
      5th and 95th percentile level) AND noise-like (spectral flatness >
      0.25: a fan, air conditioning) is steady background: the floor
      learns its level and nothing is carried.  A held tone continues.
    v0.4.11: calibration ignores digital silence (floor >= -90 dBFS); flat
      input above the floor is learned within 0.3 s (a rise of the mic
      noise after calibration no longer blocks every phrase end); a phrase
      whose last 1.5 s are flat noise-like background ends where that
      background began (or is discarded when it is nothing else)."""
    FLOOR_NEAR_DB = 3.0
    FLOOR_RISE = 0.004
    FLOOR_FALL = 0.2
    FLOOR_DRIFT_S = 4.0
    FLOOR_DRIFT = 0.01
    PRE_MAX_S = 2.0
    STEADY_DB = 4.0
    CALIB_MIN_DB = -100.0        # v0.4.11: calibration ignores digital silence
    CALIB_TIMEOUT_S = 3.0
    FLOOR_MIN_DB = -90.0
    FLAT_LEARN_S = 0.3           # v0.4.11: flat input above the floor learned after 0.3 s
    FLAT_LEARN_DB = 2.0
    FLAT_LEARN_RATE = 0.03
    RELEASE_S = 1.5              # v0.4.11: flat noise-like tail -> the phrase is over
    RELEASE_FLAT_DB = 3.0
    RELEASE_BELOW_PEAK_DB = 10.0

    def __init__(self, sr, channels, sensitivity_db=9.0, min_phrase=0.5,
                 end_silence=0.6, max_phrase=12.0, preroll=0.25, hop_s=0.01,
                 calib_s=0.5, hysteresis_db=4.0, abs_min_db=-65.0):
        import numpy as np
        self.np = np
        self.sr, self.ch = sr, channels
        self.hop = int(round(hop_s * sr))
        self.hop_s = self.hop / sr
        self.sens, self.hyst, self.abs_min = sensitivity_db, hysteresis_db, abs_min_db
        self.min_phrase, self.end_silence, self.max_phrase = min_phrase, end_silence, max_phrase
        self.pre_n = max(1, int(round(preroll / self.hop_s)))
        self.calib_n = max(1, int(round(calib_s / self.hop_s)))
        self.on_frames = 3
        self.state = "CALIBRATING"
        self.calib = []
        self.floor = None
        self.pre, self.pre_db = [], []
        self.buf, self.buf_db = [], []
        self.above = 0
        self.frames_in = 0
        self.silent_run = 0
        self.last_active = 0
        self.start_active = 0
        self.false_triggers = 0
        self.gradual_entries = 0     # phrases captured from further back than the pre-roll
        self.steady_learned = 0      # flat max_phrase phrases learned as background
        self.continued = False       # this phrase continues a flat max_phrase phrase
        self.next_continued = False
        self.pending_cont = False
        self.pending_frames = 0
        self.digital_silence = True
        self.ended_by = ""
        self.peak_db = -200.0
        self.last_db = -200.0
        self.quiet_above = 0
        self.carry = None
        self.cut_end = None
        self.calib_frames = 0
        self.last_discard = ""
        self.background_releases = 0
        self.pre_max = int(round(self.PRE_MAX_S / self.hop_s)) + self.pre_n + self.on_frames
        # v0.2.0: optional callable returning the expected speaker->mic
        # leakage level in dBFS (or None).  None = no leakage lifting.
        self.leak_level = None

    def thresholds(self):
        on = max(self.floor + self.sens, self.abs_min)
        off = on - self.hyst
        if self.leak_level is not None:
            lv = self.leak_level()
            if lv is not None:
                on = max(on, lv + 6.0)
                off = max(off, lv + 3.0)
        return on, off

    # ---- helpers ----
    def _pre_push(self, block, db):
        self.pre.append(block)
        self.pre_db.append(db)
        if len(self.pre) > self.pre_max:
            del self.pre[:len(self.pre) - self.pre_max]
            del self.pre_db[:len(self.pre_db) - self.pre_max]

    def _floor_update(self, db):
        if db < self.floor:
            self.floor += self.FLOOR_FALL * (db - self.floor)
            self.quiet_above = 0
        elif db < self.floor + self.FLOOR_NEAR_DB:
            self.floor += self.FLOOR_RISE * (db - self.floor)
            self.quiet_above = 0
        else:
            self.quiet_above += 1
            k = int(round(self.FLAT_LEARN_S / self.hop_s))
            if self.quiet_above >= k and len(self.pre_db) >= k:
                recent = self.pre_db[-k:] + [db]
                if max(recent) - min(recent) < self.FLAT_LEARN_DB:
                    # v0.4.11: steady input above the floor = the room / mic changed
                    self.floor += self.FLAT_LEARN_RATE * (db - self.floor)
                    return
            if self.quiet_above * self.hop_s >= self.FLOOR_DRIFT_S:
                self.floor += self.FLOOR_DRIFT * (db - self.floor)
        self.floor = max(self.floor, self.FLOOR_MIN_DB)

    def _entry_start(self):
        """(start, rise) indices in pre: rise = first frame of the rise
        (walking back while above floor + 3 dB, at most PRE_MAX_S), start =
        rise minus the pre-roll."""
        n = len(self.pre_db)
        rise = n - self.above
        thr = self.floor + self.FLOOR_NEAR_DB
        while rise > 0 and self.pre_db[rise - 1] > thr:
            rise -= 1
        return max(0, rise - self.pre_n), rise

    def _noise_like(self, i0=None, i1=None, n_frames=12, n_fft=2048):
        """spectral flatness (geometric / arithmetic mean power, 100 Hz-8 kHz)
        of frames spread over the phrase: > 0.25 = noise-like (a fan, air
        conditioning), a held tone or chord is far below."""
        np = self.np
        a = self.buf[self.start_active if i0 is None else i0:i1]
        if not a:
            return False
        x = np.concatenate(a, axis=0)
        x = x.mean(axis=1) if x.ndim == 2 else x
        if len(x) < n_fft:
            return False
        fq = np.fft.rfftfreq(n_fft, 1.0 / self.sr)
        band = (fq >= 100) & (fq <= min(8000, self.sr / 2))
        vals = []
        for st in np.linspace(0, len(x) - n_fft, n_frames).astype(int):
            pw = np.abs(np.fft.rfft(x[st:st + n_fft] * np.hanning(n_fft))) ** 2
            pb = pw[band] + 1e-20
            vals.append(np.exp(np.mean(np.log(pb))) / np.mean(pb))
        return float(np.median(vals)) > 0.25

    def _release_check(self):
        """v0.4.11: is the end of this 'phrase' only background?  The last
        RELEASE_S flat (< RELEASE_FLAT_DB between 10th and 90th percentile)
        and noise-like, and either >= RELEASE_BELOW_PEAK_DB under the phrase
        peak (a tail of background after the playing: end the phrase where
        it began) or the whole phrase flat noise (discard it)."""
        np = self.np
        w = int(round(self.RELEASE_S / self.hop_s))
        n = len(self.buf_db)
        if n - self.start_active < w:
            return None
        win = np.array(self.buf_db[n - w:])
        p10, p50, p90 = np.percentile(win, [10, 50, 90])
        if p90 - p10 >= self.RELEASE_FLAT_DB:
            return None
        whole = np.array(self.buf_db[self.start_active:])
        only_noise = np.percentile(whole, 95) - np.percentile(whole, 5) < self.STEADY_DB
        tail = p50 < self.peak_db - self.RELEASE_BELOW_PEAK_DB
        if not (only_noise or tail) or not self._noise_like(n - w, n):
            return None
        self.floor = max(float(p50) - 1.0, self.FLOOR_MIN_DB)
        self.background_releases += 1
        if only_noise:
            self.false_triggers += 1
            self.last_discard = "noise"
            self.state = "LISTENING"
            self.pre, self.pre_db = self.buf[-self.pre_n:], self.buf_db[-self.pre_n:]
            self.buf, self.buf_db = [], []
            self.above = 0
            return "discarded"
        end = n - w                                  # the background began here
        self.last_active = min(self.last_active, end - 1)
        if (self.last_active - self.start_active + 1) * self.hop_s < self.min_phrase:
            self.false_triggers += 1
            self.last_discard = "short"
            self.state = "LISTENING"
            self.pre, self.pre_db = self.buf[-self.pre_n:], self.buf_db[-self.pre_n:]
            self.buf, self.buf_db = [], []
            self.above = 0
            return "discarded"
        self.ended_by = "background"
        self.state = "DONE"
        return "end"

    def _quiet_cut(self):
        """cut index for a phrase at max_phrase: after the latest frame within
        3 dB of the quietest one in the last 30 % of the phrase."""
        a = self.start_active
        n = len(self.buf_db)
        lo = a + int(0.7 * (n - a))
        seg = self.buf_db[lo:n]
        if len(seg) < 2:
            return n
        m = min(seg)
        k = max(i for i, v in enumerate(seg) if v <= m + 3.0)
        return min(n, lo + k + 1)

    def rearm(self):
        """v0.2.0: continue listening after an 'end' without recalibrating.
        The noise floor is kept and the quiet tail after the phrase becomes
        the pre-roll of the next one.  v0.4.10: after a max_phrase cut, the
        rest of the sound continues as the next phrase (state PHRASE)."""
        self.continued = False
        # a flat max_phrase phrase whose cut left nothing to carry: if the next
        # phrase starts within 0.5 s it still counts as its continuation
        self.pending_cont = self.next_continued and self.ended_by == "max_duration"
        self.pending_frames = 0
        if self.carry is not None and len(self.carry[0]):
            self.continued = self.next_continued       # a flat phrase continues
            self.buf, self.buf_db = list(self.carry[0]), list(self.carry[1])
            self.carry, self.cut_end = None, None
            self.start_active = 0
            self.last_active = len(self.buf) - 1
            self.silent_run = 0
            self.above = 0
            self.ended_by = ""
            self.peak_db = max(self.buf_db)
            self.state = "PHRASE"
            return
        k = self.last_active + 1
        keep = self.pre_n + self.on_frames
        self.pre = list(self.buf[k:][-keep:])
        self.pre_db = list(self.buf_db[k:][-keep:])
        self.buf, self.buf_db = [], []
        self.carry, self.cut_end = None, None
        self.above = 0
        self.silent_run = 0
        self.ended_by = ""
        self.peak_db = -200.0
        self.state = "LISTENING"

    def feed(self, block):
        np = self.np
        self.frames_in += 1
        mono = block.mean(axis=1) if block.ndim == 2 else block
        e = float(np.sqrt(np.mean(mono.astype(np.float64) ** 2) + 1e-20))
        db = 20 * math.log10(e + 1e-12)
        self.last_db = db
        if e > 1e-7:
            self.digital_silence = False
        if self.state == "CALIBRATING":
            self.calib_frames += 1
            if db > self.CALIB_MIN_DB:              # v0.4.11: not digital silence
                self.calib.append(db)
            self._pre_push(block, db)
            if len(self.calib) >= self.calib_n or \
                    self.calib_frames * self.hop_s >= self.CALIB_TIMEOUT_S:
                fl = float(np.percentile(self.calib, 30)) if self.calib else -80.0
                self.floor = max(fl, self.FLOOR_MIN_DB)
                self.state = "LISTENING"
            return None
        if self.state == "LISTENING":
            self.pending_frames += 1
            on, _ = self.thresholds()
            if db > on:
                self.above += 1
                self._pre_push(block, db)
                if self.above >= self.on_frames:
                    start, rise = self._entry_start()
                    self.buf, self.buf_db = self.pre[start:], self.pre_db[start:]
                    self.pre, self.pre_db = [], []
                    self.start_active = rise - start
                    self.last_active = len(self.buf) - 1
                    self.silent_run = 0
                    self.peak_db = max(self.buf_db)
                    self.quiet_above = 0
                    if self.start_active > self.pre_n + self.on_frames:
                        self.gradual_entries += 1
                    self.continued = self.pending_cont and \
                        self.pending_frames * self.hop_s <= 0.5
                    self.pending_cont = False
                    self.state = "PHRASE"
                    return "onset"
            else:
                self.above = 0
                self._floor_update(db)
                self._pre_push(block, db)
            return None
        if self.state == "PHRASE":
            self.buf.append(block)
            self.buf_db.append(db)
            _, off = self.thresholds()
            if db > off:
                self.last_active = len(self.buf) - 1
                self.silent_run = 0
                self.peak_db = max(self.peak_db, db)
            else:
                self.silent_run += 1
            active_len = (self.last_active - self.start_active + 1) * self.hop_s
            total_len = (len(self.buf) - self.start_active) * self.hop_s
            if len(self.buf) % 10 == 0 and self.silent_run * self.hop_s < self.end_silence:
                rel = self._release_check()
                if rel:
                    return rel
            if self.silent_run * self.hop_s >= self.end_silence:
                if active_len < self.min_phrase:
                    self.last_discard = "short"
                    self.false_triggers += 1
                    self.state = "LISTENING"
                    self.pre, self.pre_db = self.buf[-self.pre_n:], self.buf_db[-self.pre_n:]
                    self.buf, self.buf_db = [], []
                    self.above = 0
                    return "discarded"
                self.ended_by = "silence"
                self.state = "DONE"
                return "end"
            if total_len >= self.max_phrase:
                cut = self._quiet_cut()
                lv = np.array(self.buf_db[self.start_active:])
                p5, p50, p95 = np.percentile(lv, [5, 50, 95])
                flat = p95 - p5 < self.STEADY_DB
                if flat and self._noise_like():
                    # steady NOISE background (a fan): learn it, carry nothing;
                    # v0.4.11: a held tone is never turned into background
                    self.floor = float(p50) - 1.0
                    self.carry = None
                    self.ended_by = "max_duration_steady"
                    self.steady_learned += 1
                else:
                    self.carry = (self.buf[cut:], self.buf_db[cut:]) if cut < len(self.buf) else None
                    self.ended_by = "max_duration"
                self.next_continued = flat
                self.cut_end = cut
                self.last_active = cut - 1
                self.state = "DONE"
                return "end"
        return None

    def phrase_end_index(self, tail_s=0.15):
        """v0.4.10: where the phrase audio ends in buf (the quiet cut of a
        max_phrase phrase, else the last active frame + tail_s)."""
        if self.cut_end is not None:
            return self.cut_end
        tail = int(round(tail_s / self.hop_s))
        return min(len(self.buf), self.last_active + 1 + tail)

    def phrase_audio(self, tail_s=0.15):
        np = self.np
        return np.concatenate(self.buf[:self.phrase_end_index(tail_s)], axis=0)

    def silence_frames_after_last_active(self):
        return len(self.buf) - 1 - self.last_active


# ============================================================
# reports
# ============================================================
REPORT_KEYS = [
    ("duration", "s"), ("active_ratio", ""), ("hnr_db", "dB"), ("periodicity", ""),
    ("voiced_ratio", ""), ("f0_median", "Hz"), ("f0_std_st", "st"),
    ("pitch_range_st", "st"), ("pitch_slope_st_s", "st/s"), ("pitch_net_change_st", "st"),
    ("pitch_monotonicity", ""), ("pitch_continuity", ""), ("pitch_breaks_per_s", "/s"),
    ("centroid_mean", "Hz"), ("centroid_cv", ""), ("flatness", ""), ("flux_mean", ""),
    ("flux_cv", ""), ("spectral_variability", ""), ("spectral_abruptness", ""),
    ("env_dyn_range_db", "dB"), ("env_peaks", ""), ("env_peak_rate", "/s"),
    ("env_complexity", "dB/fr"), ("energy_slope_db_s", "dB/s"),
    ("onsets_n", ""), ("onset_rate", "/s"), ("ioi_median", "s"), ("ioi_cv", ""),
    ("density_cv", ""), ("density_trend", ""), ("transient_strength_db", "dB"),
    ("impulsive", ""), ("perc_char", ""), ("silence_ratio", ""), ("silent_gaps_n", ""),
    ("mds_segments", ""), ("mds_timbre_spread", ""), ("groove_events", ""),
    ("groove_types", ""), ("markov_grains_80ms", ""),
]


def morphology_line(F):
    e = "rising" if F["energy_slope_db_s"] > 2 else "falling" if F["energy_slope_db_s"] < -2 else "level"
    d = ("accelerating" if F["density_trend"] > 0.3 else
         "decelerating" if F["density_trend"] < -0.3 else "steady")
    p = ("rising" if F["pitch_net_change_st"] > 2 else
         "falling" if F["pitch_net_change_st"] < -2 else "stable") if F["voiced_frames"] >= 20 else "unpitched"
    s = "abrupt" if F["spectral_abruptness"] > 4 else "gradual"
    return "energy %s | density %s | pitch %s | spectral change %s" % (e, d, p, s)


def build_report(F, info, P, header=""):
    L = []
    if header:
        L.append(header)
    L.append("-- Features --")
    row = []
    for k, u in REPORT_KEYS:
        v = F.get(k)
        s = ("%d" % v) if isinstance(v, int) else fnum(v, 3)
        row.append("%s %s%s" % (k, s, (" " + u) if u else ""))
        if len(row) == 3:
            L.append("  " + "   ".join(row))
            row = []
    if row:
        L.append("  " + "   ".join(row))
    L.append("  morphology: " + morphology_line(F))
    L.append("-- Scores (threshold) / eligibility --")
    for k in TRANSFORM_IDS:
        ok, why = info["elig"][k]
        comp = " ".join("%s=%.2f" % (a, b) for a, b in info["components"][k].items())
        L.append("  %-11s %.3f (%.2f)  %s" % (k, info["scores"][k], CONFIDENCE_THRESHOLD[k],
                                              "eligible" if ok else "REJECTED: " + why))
        L.append("      " + comp)
    for n in info["notes"]:
        L.append("  safeguard: " + n)
    below = [k for k in TRANSFORM_IDS if info["elig"][k][0] and k not in info["ranking"]]
    for k in below:
        L.append("  rejected %s: score below confidence threshold" % k)
    L.append("-- Decision --")
    L.append("  mode %s -> %s" % (info["mode"], info["selected"]))
    if info["selected"] == "passthrough":
        L.append("  no candidate reached its threshold: the phrase is returned untransformed")
    if "ambiguous" in info:
        L.append("  AMBIGUOUS: " + info["ambiguous"])
    if "warning" in info:
        L.append("  WARNING: " + info["warning"])
    if info["selected"] in P:
        L.append("  params: " + " ".join("%s=%s" % kv for kv in P[info["selected"]].items()))
    return "\n".join(L) + "\n"


def decision_pairs(F, info, P, extra):
    pairs = list(extra)
    pairs += [("mode", info["mode"]), ("selected", info["selected"]),
              ("selected_score", fnum(info["scores"].get(info["selected"], 0.0), 4)),
              ("ranking", ",".join(info["ranking"]))]
    if "ambiguous" in info:
        pairs.append(("ambiguous", info["ambiguous"]))
    if "warning" in info:
        pairs.append(("warning", info["warning"]))
    for k in TRANSFORM_IDS:
        pairs.append(("score_" + k, fnum(info["scores"][k], 4)))
        pairs.append(("eligible_" + k, 1 if info["elig"][k][0] else 0))
        pairs.append(("reason_" + k, info["elig"][k][1]))
        for name, v in P[k].items():
            pairs.append(("p_%s_%s" % (k, name), v))
    pairs.append(("morphology", morphology_line(F)))
    return pairs


def analyse_and_write(audio, sr, args, extra, t_end_epoch=None, detect_delay=None):
    t0 = time.perf_counter()
    F = extract_features(audio, sr)
    t1 = time.perf_counter()
    forced = None if args.force in ("", "auto") else args.force
    info = decide(F, forced)
    nch = 1 if audio.ndim == 1 else audio.shape[1]
    seed = audio_seed(audio)
    P = params_all(F, audio, sr, nch, seed)
    t2 = time.perf_counter()
    rep = build_report(F, info, P, "Cycle %s - %s, %.2f s, %d Hz, %d ch" %
                       (args.cycle, extra[0][1] if extra else "", F["duration"], sr, nch))
    rep += "-- Timing --\n  features %.3f s   selection %.3f s\n" % (t1 - t0, t2 - t1)
    if detect_delay is not None:
        rep += "  phrase-end detection delay %.3f s\n" % detect_delay
    sess = args.session
    rep_path = os.path.join(sess, "report_%03d.txt" % int(args.cycle))
    write_text_atomic(rep_path, rep)
    pairs = [("status", "ok"), ("message", "ok")] + list(extra) + [
        ("duration", fnum(F["duration"], 4)), ("sr", sr), ("channels", nch),
        ("seed", seed), ("report", rep_path),
        ("t_features", fnum(t1 - t0, 4)), ("t_select", fnum(t2 - t1, 4)),
    ]
    if t_end_epoch is not None:
        pairs.append(("t_phrase_end_epoch", "%.4f" % t_end_epoch))
    if detect_delay is not None:
        pairs.append(("t_detect_delay", fnum(detect_delay, 4)))
    pairs = decision_pairs(F, info, P, pairs)
    pairs.append(("t_written_epoch", "%.4f" % time.time()))
    pairs.append(("t_py_runtime", fnum(time.perf_counter() - T_PROCESS_START, 4)))
    write_kv_atomic(decision_path(args), pairs)
    return F, info, P


def decision_path(args):
    return os.path.join(args.session, "decision_%03d.txt" % int(args.cycle))


def write_status(args, status, message, extra=()):
    pairs = [("status", status), ("message", message)] + list(extra)
    pairs.append(("t_py_runtime", fnum(time.perf_counter() - T_PROCESS_START, 4)))
    write_kv_atomic(decision_path(args), pairs)


# ============================================================
# commands
# ============================================================
def cmd_probe(args):
    found, missing = [], []
    mods = ["numpy", "scipy", "soundfile"] + (["sounddevice"] if args.live else [])
    for m in mods:
        try:
            __import__(m)
            found.append(m)
        except Exception as ex:                          # noqa: BLE001
            missing.append("%s (%s)" % (m, str(ex).split("\n")[0][:80]))
    pairs = [("status", "ok" if not missing else "missing"),
             ("python", sys.executable), ("version", sys.version.split()[0]),
             ("engine_version", VERSION),
             ("found", " ".join(found)), ("missing", "; ".join(missing))]
    write_kv_atomic(args.out, pairs)
    return 0


def cmd_devices(args):
    try:
        import sounddevice as sd
        lines, olines = [], []
        dflt = sd.default.device if sd.default.device else (None, None)
        default_in, default_out = dflt[0], dflt[1]
        for i, d in enumerate(sd.query_devices()):
            if d["max_input_channels"] > 0:
                lines.append("%s%3d  %-40s in:%d  %d Hz" % (
                    "*" if i == default_in else " ", i, d["name"][:40],
                    d["max_input_channels"], int(d["default_samplerate"])))
            if d.get("max_output_channels", 0) > 0:
                olines.append("%s%3d  %-40s out:%d  %d Hz" % (
                    "*" if i == default_out else " ", i, d["name"][:40],
                    d["max_output_channels"], int(d["default_samplerate"])))
        text = "Audio input devices (* = default):\n" + "\n".join(lines) + "\n"
        text += "\nAudio output devices (* = default):\n" + "\n".join(olines) + "\n"
        text += ("\nEnter the index or part of the name in the Input_device / "
                 "Output_device fields, or 'default'.\n"
                 "Use headphones or a separate output so the answers do not reach "
                 "the microphone.\n")
        status = "ok"
    except Exception as ex:                              # noqa: BLE001
        text = "Could not query audio devices: %s\n" % ex
        status = "error"
    write_text_atomic(args.out, text)
    return 0 if status == "ok" else 1


def resolve_device(sd, spec, kind="input"):
    spec = (spec or "").strip()
    if spec == "" or spec.lower() in ("default", "none"):
        return None
    if spec.lstrip("-").isdigit():
        return int(spec)
    key = "max_input_channels" if kind == "input" else "max_output_channels"
    hits = [i for i, d in enumerate(sd.query_devices())
            if d.get(key, 0) > 0 and spec.lower() in d["name"].lower()]
    if not hits:
        raise RuntimeError("no %s device matches '%s' (run 'List audio devices')" % (kind, spec))
    return hits[0]


def cmd_listen(args):
    global MAX_RESPONSE_S
    MAX_RESPONSE_S = float(getattr(args, "max_response", MAX_RESPONSE_S))
    try:
        np = import_dsp()
        import soundfile as sf
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "missing Python package: %s" % ex)
        return 1
    try:
        import sounddevice as sd
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "sounddevice/PortAudio unavailable: %s" % ex)
        return 1
    import queue
    q = queue.Queue()
    det = PhraseDetector(int(args.sr), int(args.channels), args.sensitivity,
                         args.min_phrase, args.end_silence, args.max_phrase,
                         args.preroll)
    overflow = [0]

    def cb(indata, frames, tinfo, status):
        if status:
            overflow[0] += 1
        q.put((indata.copy(), time.time()))

    try:
        dev = resolve_device(sd, args.device)
        stream = sd.InputStream(samplerate=int(args.sr), channels=int(args.channels),
                                dtype="float32", blocksize=det.hop, device=dev,
                                callback=cb)
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "cannot open audio input: %s" % ex)
        return 1
    t_open = time.time()
    t_onset = None
    pending = np.zeros((0, int(args.channels)), dtype=np.float32)
    result = None
    t_end_epoch = None
    t_last_block = t_open
    try:
        with stream:
            while True:
                try:
                    block, tb = q.get(timeout=0.5)
                except queue.Empty:
                    if time.time() - t_open > 5 and det.frames_in == 0:
                        write_status(args, "error", "audio input delivers no data")
                        return 1
                    continue
                t_last_block = tb
                pending = np.concatenate([pending, block], axis=0)
                while len(pending) >= det.hop:
                    ev = det.feed(pending[:det.hop])
                    pending = pending[det.hop:]
                    if ev == "onset":
                        t_onset = tb
                    elif ev == "end":
                        result = det.phrase_audio()
                        t_end_epoch = tb - det.silence_frames_after_last_active() * det.hop_s
                        break
                if result is not None:
                    break
                waited = tb - t_open
                if det.state in ("CALIBRATING", "LISTENING") and waited > args.timeout:
                    if det.digital_silence:
                        write_status(args, "silent_input",
                                     "input was digital silence for %.0f s - check the "
                                     "microphone permission / device" % waited)
                    else:
                        write_status(args, "timeout",
                                     "no phrase within %.0f s (noise floor %.1f dBFS, "
                                     "false triggers %d)" % (waited, det.floor or -200,
                                                             det.false_triggers))
                    return 0
    except KeyboardInterrupt:
        write_status(args, "error", "capture interrupted by the user")
        return 1
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "capture failed: %s" % ex)
        return 1
    t_final = time.time()
    detect_delay = t_final - t_end_epoch
    wav = os.path.join(args.session, "q_%03d.wav" % int(args.cycle))
    audio = result if int(args.channels) > 1 else result[:, 0]
    sf.write(wav, audio, int(args.sr), subtype="FLOAT")
    extra = [("source", "live microphone"), ("wav", wav),
             ("ended_by", det.ended_by), ("false_triggers", det.false_triggers),
             ("noise_floor_dbfs", fnum(det.floor, 1)),
             ("onset_threshold_dbfs", fnum(det.thresholds()[0], 1)),
             ("input_overflows", overflow[0])]
    try:
        analyse_and_write(audio.astype(np.float64), int(args.sr), args, extra,
                          t_end_epoch, detect_delay)
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "analysis failed: %s" % ex, [("wav", wav)])
        return 1
    return 0


def cmd_analyze(args):
    global MAX_RESPONSE_S
    MAX_RESPONSE_S = float(getattr(args, "max_response", MAX_RESPONSE_S))
    try:
        np = import_dsp()
        import soundfile as sf
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "missing Python package: %s" % ex)
        return 1
    try:
        audio, sr = sf.read(args.input, dtype="float64", always_2d=False)
    except Exception as ex:                              # noqa: BLE001
        write_status(args, "error", "cannot read %s: %s" % (args.input, ex))
        return 1
    if audio.ndim == 2 and audio.shape[1] == 1:
        audio = audio[:, 0]
    dur = len(audio) / sr
    if dur < 0.25:
        write_status(args, "error", "phrase too short (%.3f s < 0.25 s)" % dur)
        return 1
    if float(np.max(np.abs(audio))) < 1e-6:
        write_status(args, "silent_input", "the selected Sound is silent")
        return 0
    try:
        analyse_and_write(audio, int(sr), args, [("source", "selected Sound"),
                                                 ("wav", args.input)])
    except Exception as ex:                              # noqa: BLE001
        import traceback
        write_status(args, "error", "analysis failed: %s | %s" %
                     (ex, traceback.format_exc().replace("\n", " | ")[-400:]))
        return 1
    return 0


def safe_session_dir(path):
    base = os.path.basename(os.path.normpath(path))
    return base.startswith(SESSION_PREFIX) and os.path.isdir(path)


def cmd_cleanup(args):
    """The ONLY way a session folder is removed after a normal run.
    v0.3.1: the folder is deleted only after the engine of THIS session
    (pid + start time from launch.txt) has really exited.  If it is still
    running after --wait seconds, NOTHING is deleted: the result is
    INCOMPLETE and a cleanup.pending marker asks the engine to remove the
    folder itself when it exits.  Exit code: 0 = folder gone, 1 = not
    removed, 2 = refused (not a session folder).  With --report one result
    line is printed and the exit code is always 0 (Praat reads the line with
    runSubprocess$, which would stop the script on a non-zero code)."""
    sess = args.session
    say = print if args.report else (lambda *a, **k: None)

    def done(rc, line):
        say(line)
        sys.stdout.flush()
        return 0 if args.report else rc
    if not os.path.exists(sess):
        return done(0, "CLEANUP OK files=0")
    if not safe_session_dir(sess):
        return done(2, "CLEANUP INCOMPLETE: refused (not a session folder): %s" % sess)
    info = read_kv(os.path.join(sess, "launch.txt"))
    t0 = time.time()
    while owner_alive(info) and time.time() - t0 < args.wait:
        time.sleep(0.1)
    if owner_alive(info):
        try:
            write_text_atomic(os.path.join(sess, "cleanup.pending"), "remove on exit\n")
        except OSError:
            pass
        t1 = time.time()                 # the engine may be exiting right now
        while owner_alive(info) and time.time() - t1 < 3.0:
            time.sleep(0.1)
        if owner_alive(info):
            return done(1, "CLEANUP INCOMPLETE: engine still running (pid %s) - nothing deleted; "
                           "it removes %s when it exits" % (info.get("pid"), sess))
    n = sum(len(f) for _, _, f in os.walk(sess))
    left = remove_tree(sess)
    if left:
        return done(1, "CLEANUP INCOMPLETE: %s" % "; ".join(left[:8]))
    return done(0, "CLEANUP OK files=%d" % n)


def read_kv(path):
    out = {}
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "=" in line:
                    k, v = line.rstrip("\r\n").split("=", 1)
                    out[k] = v
    except OSError:
        pass
    return out


def session_activity(path):
    newest = 0.0
    for dirpath, _, names in os.walk(path):
        for n in names:
            try:
                newest = max(newest, os.path.getmtime(os.path.join(dirpath, n)))
            except OSError:
                pass
    try:
        newest = max(newest, os.path.getmtime(path))
    except OSError:
        pass
    return newest


STALE_ENGINE_S = 600        # dead engine + no activity for 10 min -> abandoned
STALE_NO_ENGINE_S = 12 * 3600   # session without an engine record (turn-taking,
                                # selected Sounds, device list) -> 12 h


def cmd_cleanup_stale(args):
    """Crash recovery at launch: remove ABANDONED sessions only.
    v0.3.1: a session whose engine (pid + start time) is alive is NEVER
    removed, however long it has been quiet.  A session is abandoned when
    its engine is gone (or a reused PID) and nothing in it changed for
    10 min; a session without an engine record after 12 h.  Orphan probe
    files go after 2 min.  Exit code 1 if an abandoned session could not be
    removed completely (0 with --report, which prints a summary line)."""
    now = time.time()
    removed, kept, failed = 0, 0, 0
    try:
        names = os.listdir(args.base)
    except OSError:
        names = []
    for name in names:
        p = os.path.join(args.base, name)
        try:
            if name.startswith(SESSION_PREFIX + "probe_") and os.path.isfile(p):
                if now - os.path.getmtime(p) > 120:
                    os.remove(p)
                    removed += 1
                continue
            if not (name.startswith(SESSION_PREFIX) and os.path.isdir(p)):
                continue
            info = read_kv(os.path.join(p, "launch.txt"))
            if info.get("pid"):
                if owner_alive(info):
                    kept += 1                       # active: never touched
                    continue
                limit = STALE_ENGINE_S
            else:
                limit = STALE_NO_ENGINE_S
            if now - session_activity(p) < limit:
                kept += 1
                continue
            if remove_tree(p, 8, 0.25):
                failed += 1
            else:
                removed += 1
        except OSError:
            failed += 1
    if args.report:
        print("STALE removed=%d kept=%d failed=%d" % (removed, kept, failed))
        return 0
    return 1 if failed else 0


# ============================================================
# self-test: six synthetic gestures + phrase-detector stream test
# ============================================================
def synth_cases(sr=44100):
    import numpy as np
    rng = np.random.default_rng(7)
    def harm(f, n=8, roll=0.7):
        return sum((roll ** k) * np.sin(2 * np.pi * (k + 1) * f) for k in range(n))
    cases = {}
    # 1 stable harmonic tone with gentle vibrato
    d = 3.0
    t = np.arange(int(d * sr)) / sr
    ph = np.cumsum(220 * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))) / sr
    env = np.minimum(1, t / 0.15) * np.minimum(1, (d - t) / 0.3)
    cases["paulstretch"] = 0.3 * env * harm(ph) / 2.5
    # 2 broadband noise with a slowly wandering band (timbral variation)
    import scipy.signal as ss
    n = rng.standard_normal(int(d * sr))
    out = np.zeros_like(n)
    blk = int(0.25 * sr)
    for i in range(0, len(n), blk):
        fc = 500 + 5000 * rng.random()
        b, a = ss.butter(2, [fc / (sr / 2) * 0.5, min(0.95, fc / (sr / 2) * 2.5)], "band")
        out[i:i + blk] = ss.lfilter(b, a, n[i:i + blk])
    out = 0.6 * out + 0.4 * n
    cases["markov"] = 0.25 * out / np.max(np.abs(out)) * np.minimum(1, t / 0.1) * np.minimum(1, (d - t) / 0.2)
    # 3 tonal plucks, different pitches and timbres, separated by silence
    x = np.zeros(int(3.6 * sr))
    pos = 0.05
    for i, (f, roll) in enumerate([(196, 0.5), (523, 0.8), (330, 0.3), (784, 0.7),
                                   (262, 0.9), (440, 0.4)]):
        L = int(0.32 * sr)
        tt = np.arange(L) / sr
        note = harm(f * tt, 10, roll) * np.exp(-tt * 9) * np.minimum(1, tt / 0.004)
        a = int(pos * sr)
        x[a:a + L] += 0.35 * note / np.max(np.abs(note))
        pos += 0.58
    cases["mds"] = x
    # 4 continuous glissando 200 -> 650 Hz
    d = 3.0
    t = np.arange(int(d * sr)) / sr
    f = 200 * (650 / 200) ** (t / d)
    ph = np.cumsum(f) / sr
    cases["spiral"] = 0.3 * np.minimum(1, t / 0.1) * np.minimum(1, (d - t) / 0.2) * harm(ph, 6, 0.6) / 2.2
    # 5 inharmonic sustained cluster with irregular swells: the envelope
    # controls the BETWEEN-channel speed spread, not time-varying speed.
    d = 4.0
    t = np.arange(int(d * sr)) / sr
    parts = [173 * r for r in (1.0, 1.618, 2.414, 3.303, 4.732, 6.171)]
    tone = sum(np.sin(2 * np.pi * p * t + k) / (k + 1) for k, p in enumerate(parts))
    sw = np.zeros_like(t)
    for c, w, a in [(0.3, 0.15, 1.0), (0.9, 0.1, 0.5), (1.4, 0.25, 0.9), (2.1, 0.08, 0.6),
                    (2.6, 0.2, 1.0), (3.2, 0.12, 0.4), (3.6, 0.15, 0.8)]:
        sw += a * np.exp(-0.5 * ((t - c) / w) ** 2)
    cases["speeddev"] = 0.3 * tone / np.max(np.abs(tone)) * (0.03 + sw / sw.max())
    # 6 drum-like sequence, accelerating
    d = 4.0
    x = np.zeros(int(d * sr))
    times = list(np.cumsum([0.05] + [0.5] * 3 + [0.3] * 4 + [0.18] * 7 + [0.12] * 6))
    kinds = ["k", "h", "s", "h", "k", "h", "s", "h", "k", "h", "s", "h", "k", "h", "s",
             "h", "k", "h", "s", "h", "k", "s"]
    for tm, kd in zip(times, kinds):
        if tm > d - 0.2:
            break
        L = int(0.2 * sr)
        tt = np.arange(L) / sr
        if kd == "k":
            s = np.sin(2 * np.pi * np.cumsum(120 * np.exp(-tt * 25) + 45) / sr) * np.exp(-tt * 18)
        elif kd == "s":
            nn = rng.standard_normal(L)
            b, a = ss.butter(2, [800 / (sr / 2), 3500 / (sr / 2)], "band")
            s = 0.7 * ss.lfilter(b, a, nn) * np.exp(-tt * 22) + 0.4 * np.sin(2 * np.pi * 190 * tt) * np.exp(-tt * 30)
        else:
            nn = rng.standard_normal(L)
            b, a = ss.butter(4, 6000 / (sr / 2), "high")
            s = ss.lfilter(b, a, nn) * np.exp(-tt * 60)
        s = s / np.max(np.abs(s))
        a0 = int(tm * sr)
        x[a0:a0 + L] += 0.4 * s[:max(0, min(L, len(x) - a0))]
    cases["groove"] = x
    return cases


def detector_stream_test(sr=44100):
    """Feed the PhraseDetector a synthetic stream: room noise, a click
    (false trigger), a phrase with an internal 0.3 s pause, then silence."""
    import numpy as np
    rng = np.random.default_rng(3)
    hop = int(0.01 * sr)
    noise = lambda s: 0.002 * rng.standard_normal(int(s * sr))
    t = np.arange(int(1.2 * sr)) / sr
    tone = 0.2 * np.sin(2 * np.pi * 330 * t)
    burst = 0.15 * rng.standard_normal(int(0.15 * sr))   # 150 ms knock: onset, too short
    click = np.zeros(int(0.05 * sr))
    click[:int(0.01 * sr)] = 0.3                         # 10 ms click: never an onset
    stream = np.concatenate([noise(1.0), click + noise(0.05), noise(0.8),
                             burst + noise(0.15), noise(1.0),
                             tone[:int(0.8 * sr)] + noise(0.8), noise(0.3),
                             tone[:int(0.7 * sr)] + noise(0.7), noise(1.5)])
    det = PhraseDetector(sr, 1, 9.0, 0.5, 0.6, 12.0, 0.25)
    events = []
    for i in range(0, len(stream) - hop, hop):
        ev = det.feed(stream[i:i + hop])
        if ev:
            events.append((ev, round(i / sr, 2)))
        if ev == "end":
            break
    ph = det.phrase_audio()
    # expected: click ignored, knock = onset + discarded, phrase with its
    # internal 0.3 s pause kept whole (0.25 pre-roll + 1.8 s + 0.15 tail)
    ok = ([e[0] for e in events] == ["onset", "discarded", "onset", "end"]
          and det.false_triggers == 1 and 2.0 < len(ph) / sr < 2.4)
    return ok, events, len(ph) / sr, det


def cmd_self_test(args):
    np = import_dsp()
    import soundfile as sf
    sr = 44100
    cases = synth_cases(sr)
    failures = 0
    print("=" * 72)
    print("AudioTools Call & Response %s - self-test (synthetic, in memory)" % VERSION)
    print("=" * 72)

    class A:
        force = "auto"
    for expected, audio in cases.items():
        t0 = time.perf_counter()
        F = extract_features(audio, sr)
        t1 = time.perf_counter()
        info = decide(F)
        P = params_all(F, audio, sr, 1, audio_seed(audio))
        t2 = time.perf_counter()
        got = info["selected"]
        status = "OK " if got == expected else "FAIL"
        if got != expected:
            failures += 1
        print("\n[%s] case '%s' -> selected '%s'   (features %.2f s, select %.3f s)" %
              (status, expected, got, t1 - t0, t2 - t1))
        print(build_report(F, info, P).rstrip())
        if args.write_dir:
            os.makedirs(args.write_dir, exist_ok=True)
            sf.write(os.path.join(args.write_dir, "selftest_%s.wav" % expected),
                     audio.astype(np.float32), sr, subtype="FLOAT")
    ok, events, plen, det = detector_stream_test(sr)
    print("\n[%s] phrase detector stream test: events %s, phrase %.2f s, floor %.1f dBFS" %
          ("OK " if ok else "FAIL", events, plen, det.floor))
    if not ok:
        failures += 1
    print("\n" + "-" * 72 + "\nv0.2.0 continuous-engine unit tests (no audio hardware)")
    for name, fn in V020_TESTS:
        try:
            ok, detail = fn(sr)
        except Exception as ex:                              # noqa: BLE001
            ok, detail = False, "exception: %s" % ex
        print("[%s] %s: %s" % ("OK " if ok else "FAIL", name, detail))
        if not ok:
            failures += 1
    print("\n" + "-" * 72 + "\nv0.3.0 sonic-memory unit tests (in RAM; temporary test folders removed)")
    for name, fn in V030_TESTS:
        try:
            ok, detail = fn(sr)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            ok, detail = False, "exception: %s %s" % (ex, traceback.format_exc()[-300:])
        print("[%s] %s: %s" % ("OK " if ok else "FAIL", name, detail))
        if not ok:
            failures += 1
    print("\n" + "-" * 72 + "\nv0.4.0 polyphonic spatial playback tests (offline mixer, no device)")
    for name, fn in V040_TESTS:
        try:
            ok, detail = fn(sr)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            ok, detail = False, "exception: %s %s" % (ex, traceback.format_exc()[-400:])
        print("[%s] %s: %s" % ("OK " if ok else "FAIL", name, detail))
        if not ok:
            failures += 1
    print("\n" + "-" * 72 + "\nv0.4.1 corpus-only recall + adaptive level tests")
    for name, fn in V041_TESTS:
        try:
            ok, detail = fn(sr)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            ok, detail = False, "exception: %s %s" % (ex, traceback.format_exc()[-400:])
        print("[%s] %s: %s" % ("OK " if ok else "FAIL", name, detail))
        if not ok:
            failures += 1
    print("\n%d failure(s)" % failures)
    return 1 if failures else 0


# ---------------- v0.2.0 unit tests ----------------
def _t_queue(sr):
    dropped = []
    class J:
        def __init__(self, i):
            self.tag, self.selected = "%04d" % i, "x"
    q = BoundedJobQueue("t", 3, "drop_oldest", lambda j, why: dropped.append(j.tag))
    for i in range(1, 6):
        q.put(J(i))
    order = [q.get(0).tag for _ in range(3)]
    ok1 = order == ["0003", "0004", "0005"] and dropped == ["0001", "0002"]
    dropped2 = []
    q2 = BoundedJobQueue("t", 2, "drop_newest", lambda j, why: dropped2.append(j.tag))
    for i in range(1, 5):
        q2.put(J(i))
    order2 = [q2.get(0).tag for _ in range(2)]
    ok2 = order2 == ["0001", "0002"] and dropped2 == ["0003", "0004"] and q2.get(0) is None
    return ok1 and ok2, ("drop_oldest kept %s dropped %s | drop_newest kept %s dropped %s"
                         % (order, dropped, order2, dropped2))


def _t_leak(sr):
    import numpy as np
    rng = np.random.default_rng(5)
    n = int(1.5 * sr)
    t = np.arange(n) / sr
    out = 0.3 * np.sin(2 * np.pi * 220 * t * (1 + 0.3 * t)) * (1 + 0.5 * rng.standard_normal(n))
    lag = int(0.035 * sr)
    L = int(1.0 * sr)
    mx = int(LEAK_MAX_LAG_S * sr)
    x = out[-(L + mx):]
    y_leak = 0.2 * out[-L - lag:-lag] + 0.002 * rng.standard_normal(L)       # -14 dB, 35 ms
    a, rho, lg = leak_fit(x, y_leak, mx)
    ok1 = abs(20 * math.log10(abs(a)) + 13.98) < 0.5 and abs(lg - lag) <= 1 and rho > 0.95
    player = 0.2 * np.sin(2 * np.pi * 330 * t[:L]) * np.exp(-t[:L])
    a2, rho2, _ = leak_fit(x, player + 0.002 * rng.standard_normal(L), mx)
    ok2 = rho2 * rho2 < 0.1
    mix = 0.05 * out[-L - lag:-lag] + player                          # performer over leak
    a3, rho3, lg3 = leak_fit(x, mix, mx)
    ok3 = rho3 * rho3 < LEAK_DISCARD_RHO2                             # performer kept
    return ok1 and ok2 and ok3, (
        "pure leak %.2f dB @ %.1f ms rho %.3f | independent player rho^2 %.3f | "
        "player over leak rho^2 %.2f (kept, < %.2f)" % (
            20 * math.log10(abs(a)), 1000 * lg / sr, rho, rho2 * rho2, rho3 * rho3,
            LEAK_DISCARD_RHO2))


def _t_ring(sr):
    import numpy as np
    r = Ring(sr, 2.0)
    blk = int(0.01 * sr)
    t0 = 1000.0
    for i in range(300):                    # 3 s of a ramp, ring keeps 2 s
        v = (np.arange(blk) + i * blk).astype(np.float32)
        r.append(v, t0 + (i + 1) * 0.01)
    seg = r.segment(t0 + 2.0, 0.5)          # samples [1.5 s, 2.0 s)
    exp = np.arange(int(1.5 * sr), int(2.0 * sr)).astype(np.float32)
    old = r.segment(t0 + 0.5, 0.2)          # older than history -> zeros
    return bool(np.array_equal(seg, exp) and not old.any()), "aligned segment, expired history = zeros"


def _t_rearm(sr):
    """Three phrases back to back in ONE stream: v0.2.0 continuous detection
    must find all three without recalibrating."""
    import numpy as np
    rng = np.random.default_rng(9)
    hop = int(0.01 * sr)
    nz_ = lambda s: 0.002 * rng.standard_normal(int(s * sr))
    def tone(f, s):
        tt = np.arange(int(s * sr)) / sr
        return 0.2 * np.sin(2 * np.pi * f * tt)
    stream = np.concatenate([nz_(1.0), tone(220, 1.0) + nz_(1.0), nz_(0.8),
                             tone(330, 0.7) + nz_(0.7), nz_(0.9), tone(440, 1.2) + nz_(1.2), nz_(1.0)])
    det = PhraseDetector(sr, 1, 9.0, 0.5, 0.6, 12.0, 0.25)
    lens = []
    for i in range(0, len(stream) - hop, hop):
        if det.feed(stream[i:i + hop]) == "end":
            lens.append(round(len(det.phrase_audio()) / sr, 2))
            det.rearm()
    ok = len(lens) == 3 and abs(lens[0] - 1.4) < 0.1 and abs(lens[1] - 1.1) < 0.1 and abs(lens[2] - 1.6) < 0.1
    return ok, "phrase lengths %s s (tone + 0.25 pre-roll + 0.15 tail)" % lens


def _t_guard(sr):
    """Leakage hook: lifts thresholds only while the hook reports a level;
    None restores the exact v0.1.3 thresholds."""
    det = PhraseDetector(sr, 1)
    det.floor = -60.0
    base = det.thresholds()
    det.leak_level = lambda: -30.0
    lifted = det.thresholds()
    det.leak_level = lambda: None
    back = det.thresholds()
    ok = base == (-51.0, -55.0) and lifted == (-24.0, -27.0) and back == base
    return ok, "v0.1.3 %s | playing with leak at -30 dBFS %s | idle %s" % (base, lifted, back)


def _t_path(sr):
    """PHAT path validation: real leakage under a performer is found at the
    right delay; a same-pitch performer against a phase-randomised
    (Paulstretch-like) answer with NO leakage is not a path."""
    import numpy as np
    rng = np.random.default_rng(3)
    L, mx = int(1.0 * sr), int(LEAK_MAX_LAG_S * sr)
    n = L + mx
    t = np.arange(n) / sr
    def harm(f, ph):
        return sum((0.7 ** i) * np.sin(2 * np.pi * (i + 1) * f * t + ph[i]) for i in range(8)) / 2.5
    perf = 0.3 * harm(220, np.zeros(8))
    base = harm(220, np.zeros(8)) + 0.01 * rng.standard_normal(n)
    X = np.fft.rfft(base)
    ans = 0.3 * np.fft.irfft(np.abs(X) * np.exp(1j * rng.uniform(0, 2 * np.pi, len(X))), n)
    lag = int(0.04 * sr)
    nz_ = 0.002 * rng.standard_normal(n)
    r0 = leak_path(ans, (perf + nz_)[-L:], mx, sr)
    res1 = []
    for trial in range(6):              # same pitch, random answer phases, both noisy
        same = 0.3 * harm(220, rng.uniform(0, 2 * np.pi, 8)) + 0.002 * rng.standard_normal(n)
        res1.append(leak_path(same, (perf + nz_)[-L:], mx, sr))
    y = 0.1 * np.concatenate([np.zeros(lag), ans])[:n] + perf + nz_
    r2 = leak_path(ans, y[-L:], mx, sr)
    y3 = 0.1 * np.concatenate([np.zeros(lag), ans])[:n] + nz_
    r3 = leak_path(ans, y3[-L:], mx, sr)
    g3 = 20 * math.log10(abs(r3["a"]) + 1e-12)
    ok = (not r0["plausible"] and not any(r["plausible"] for r in res1) and r2["plausible"]
          and abs(r2["lag"] - lag) <= 1 and r3["plausible"] and abs(g3 + 20) < 0.5
          and abs(r3["rho"]) >= LEAK_GAIN_RHO and abs(r2["rho"]) < LEAK_GAIN_RHO)
    return ok, ("no leak: paul answer %s (z %.1f) | same pitch x6: %d path(s), max dominance %.2f"
                " | -20 dB leak under performer: path at %.1f ms, gain frozen (rho %.2f)"
                " | -20 dB leak alone: %.2f dB (rho %.2f)" % (
                    "path" if r0["plausible"] else "no path", r0["z"],
                    sum(r["plausible"] for r in res1), max(r["dom"] for r in res1),
                    1000 * r2["lag"] / sr, r2["rho"], g3, r3["rho"]))


V020_TESTS = [("bounded queues + overflow policies", _t_queue),
              ("leakage least-squares estimate", _t_leak),
              ("leakage path validation (PHAT)", _t_path),
              ("wall-clock ring alignment", _t_ring),
              ("continuous re-arming detector", _t_rearm),
              ("leakage guard thresholds", _t_guard)]


# ---------------- v0.3.0 sonic-memory unit tests ----------------
def _mem_cfg(**kw):
    c = {"enabled": True, "response_mode": "hybrid", "use_A": True, "use_B": True,
         "use_C": True, "sim_mode": "hybrid", "min_similarity": 0.3, "w_live": 40.0,
         "w_processed": 30.0, "w_preloaded": 30.0, "p_transform": 40.0, "p_recall": 30.0,
         "p_recall_transform": 30.0, "max_generation": 2, "max_live": 100,
         "max_processed": 100, "max_ram_min": 30.0, "max_item_s": 15.0, "candidates": 5,
         "evolving": False, "cooldown": 4, "same_family_exclusion": False,
         "c_max_items": 300, "c_max_files": 200, "c_max_per_file": 20, "c_min_item_s": 0.5}
    c.update(kw)
    return c


_MEM_CACHE = {}


def _mem_items(sr):
    """The six synthetic gestures analysed once (features + descriptor)."""
    if "items" not in _MEM_CACHE:
        out = {}
        for name, audio in synth_cases(sr).items():
            F, info, desc = analyse_item(audio, sr)
            out[name] = (audio, F, info, desc)
        _MEM_CACHE["items"] = out
    return _MEM_CACHE["items"]


def _mem_fill(sr, corpus="A", **kw):
    import numpy as np
    mem = SonicMemory(_mem_cfg(**kw), 1234)
    for name, (audio, F, info, desc) in _mem_items(sr).items():
        iid = mem.new_id(corpus)
        mem.add(CorpusItem(iid, corpus, audio.astype(np.float32)[:, None], sr, F, desc, info,
                           time.time(), {"root": iid, "parent": None, "method": None,
                                         "generation": 0, "source": name}))
    return mem


def _variant(audio, sr):
    """Same gesture, slightly different take: 30 ms later, -1.5 dB, a little noise."""
    import numpy as np
    rng = np.random.default_rng(3)
    a = np.concatenate([np.zeros(int(0.03 * sr)), audio])[:len(audio)] * 0.84
    return a + 0.002 * rng.standard_normal(len(a))


def _t_mem_insert(sr):
    mem = _mem_fill(sr)
    c = mem.counts()
    ok = c == {"A": 6, "B": 0, "C": 0} and all(it.desc is not None for it in mem.items["A"])
    return ok, "counts %s, RAM %.1f s" % (c, mem.ram_seconds())


def _t_mem_rank(sr):
    mem = _mem_fill(sr)
    hits = []
    for name, (audio, F, info, desc) in _mem_items(sr).items():
        Fq, iq, dq = analyse_item(_variant(audio, sr), sr)
        best = mem.similarity(dq, mem.items["A"], "hybrid")[0]
        hits.append((name, best[0].p["source"], round(best[1], 2)))
    ok = all(a == b for a, b, _ in hits)
    return ok, "variant -> nearest: " + ", ".join("%s->%s %.2f" % h for h in hits)


def _t_mem_nopitch(sr):
    import numpy as np
    mem = _mem_fill(sr)
    rng = np.random.default_rng(5)
    noise = 0.2 * rng.standard_normal(int(2.0 * sr))
    F, info, d = analyse_item(noise, sr)
    res = mem.similarity(d, mem.items["A"], "pitch")
    res2 = mem.similarity(d, mem.items["A"], "hybrid")
    finite = all(np.isfinite(r[1]) for r in res + res2)
    return finite and not d["voiced"], "unpitched query: %d finite similarities, best %s %.2f" % (
        len(res2), res2[0][0].p["source"], res2[0][1])


def _t_mem_self(sr):
    mem = _mem_fill(sr)
    q = mem.items["A"][0]
    excluded = {q.id, mem.items["A"][1].id}
    seen = set()
    for _ in range(30):
        ch, top, why = mem.retrieve(q.desc, exclude_ids=excluded)
        seen |= {r["item"].id for r in top}
    ok = not (seen & excluded) and len(seen) > 0
    # an identical copy (sim >= 0.97) is never "recalled"
    mem.add(CorpusItem("A9999", "A", q.audio, q.sr, q.F, q.desc, q.info, time.time(),
                       {"root": "A9999", "generation": 0}))
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    ok = ok and all(r["item"].id != "A9999" for r in top)
    return ok, "excluded ids never ranked; identical copy refused"


def _t_mem_generation(sr):
    mem = _mem_fill(sr)
    for it in mem.items["A"]:
        it.p["generation"] = 2
    q = mem.items["A"][0]
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    rt2 = pick_recall_transform(ch, top, None, 2)
    for it in mem.items["A"]:
        it.p["generation"] = 1
    rt1 = pick_recall_transform(ch, top, None, 2)
    ok = rt2 is None and (rt1 is not None or not top)
    return ok, "generation-2 sources refused for Recall+Transform (max 2); generation 1 allowed"


def _t_mem_cooldown(sr):
    mem = _mem_fill(sr, cooldown=3)
    q = mem.items["A"][0]
    picks = []
    for _ in range(9):
        ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
        if ch is None:
            picks.append(None)
            continue
        mem.mark_recalled(ch["item"])
        picks.append(ch["item"].id)
    rep = any(picks[i] is not None and picks[i] in picks[max(0, i - 3):i]
              for i in range(len(picks)))
    return not rep, "picks %s (no repeat within 3)" % picks


def _t_mem_empty(sr):
    mem = SonicMemory(_mem_cfg(), 1)
    d = _mem_items(sr)["paulstretch"][3]
    ch, top, why = mem.retrieve(d)
    a1 = mem.choose_action(ch, None)
    mem2 = SonicMemory(_mem_cfg(response_mode="recall"), 1)
    a2 = mem2.choose_action(None, None)
    mem3 = SonicMemory(_mem_cfg(response_mode="recall_transform"), 1)
    a3 = mem3.choose_action(None, None)
    ok = ch is None and a1[0] == a2[0] == a3[0] == "transform"
    return ok, "empty memory -> %s; Recall without match -> %s; R+T -> %s" % (a1[0], a2[0], a3[0])


def _t_mem_contrast(sr):
    mem = _mem_fill(sr, sim_mode="contrast", min_similarity=0.2, candidates=1)
    q = mem.items["A"][0]
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    ranked = mem.similarity(q.desc, [it for it in mem.items["A"] if it.id != q.id], "hybrid")
    ok = ch is not None and ch["item"] is ranked[-1][0]
    return ok, "contrast picks the least similar (%s, sim %.2f)" % (
        ch["item"].p["source"] if ch else "-", ch["sim"] if ch else 0)


def _t_mem_weights(sr):
    mem = SonicMemory(_mem_cfg(evolving=True, w_processed=0.0, use_C=False), 1)
    ok = True
    for p in (0.0, 0.3, 0.6, 1.0):
        w = mem.corpus_weights(p)
        ok = ok and w["B"] == 0 and w["C"] == 0 and w["A"] > 0
    mem2 = _mem_fill(sr, corpus="C", use_C=False)
    q = mem2.items["C"][0]
    ch, top, why = mem2.retrieve(q.desc)
    ok = ok and ch is None
    return ok, "manual 0 / disabled corpora stay 0 at every stage of the evolving curve"


def _t_mem_evict(sr):
    mem = _mem_fill(sr, max_live=3)
    ids = [it.id for it in mem.items["A"]]
    mem2 = _mem_fill(sr, max_ram_min=0.1)            # 6 s budget, 6 x ~3 s audio
    ok = ids == ["A0004", "A0005", "A0006"] and mem.evicted == 3 and \
        mem2.ram_seconds() <= 6.0 + 1e-6
    return ok, "count limit keeps %s; RAM limit %.1f s <= 6 s (%d evicted)" % (
        ids, mem2.ram_seconds(), mem2.evicted)


def _t_mem_corpus_c(sr):
    """Corpus C indexing is READ-ONLY: files hashed before and after, no new
    files anywhere in the folder; segments avoid silence and tiny bits."""
    import hashlib
    import tempfile
    import numpy as np
    import soundfile as sf
    items = _mem_items(sr)
    with tempfile.TemporaryDirectory(prefix="AudioTools_CR_selftest_") as tmp:
        sil = np.zeros(int(1.0 * sr))
        long_ = np.concatenate([sil, items["paulstretch"][0], sil, items["markov"][0], sil,
                                0.0005 * np.ones(int(0.05 * sr)), sil])
        sf.write(os.path.join(tmp, "take1.wav"), long_, sr, subtype="PCM_16")
        sf.write(os.path.join(tmp, "take2.flac"), items["spiral"][0], sr)
        open(os.path.join(tmp, "notes.txt"), "w").write("not audio")

        def snap():
            out = {}
            for n in sorted(os.listdir(tmp)):
                with open(os.path.join(tmp, n), "rb") as fh:
                    out[n] = (hashlib.sha256(fh.read()).hexdigest(),
                              os.path.getmtime(os.path.join(tmp, n)))
            return out
        before = snap()
        mem = SonicMemory(_mem_cfg(), 1)
        n, notes = index_preloaded(tmp, mem, _mem_cfg())
        after = snap()
        durs = [round(it.duration, 2) for it in mem.items["C"]]
        a = mem.items["C"][0]
        a.audio = None                                 # on-demand path
        reread = a.get_audio()
    ok = before == after and n >= 3 and min(durs) >= 0.5 and len(reread) > 0
    return ok, "%d segments %s, folder unchanged (%d files hashed)" % (n, durs, len(before))


def _t_mem_cleanup(sr):
    """v0.3.1 session safety (all in a temporary base folder):
    cleanup refuses while the engine lives and deletes after it exits;
    cleanup-stale keeps a quiet-but-alive session, removes a dead one and
    one whose PID was reused; a foreign folder is refused."""
    import tempfile
    import io
    import contextlib

    class NS:
        pass
    notes, ok = [], True
    with tempfile.TemporaryDirectory(prefix="atcr_base_") as base:
        def mk(name, info, age):
            d = os.path.join(base, name)
            os.makedirs(os.path.join(d, "sub"))
            open(os.path.join(d, "sub", "x.wav"), "wb").write(b"0" * 100)
            if info:
                write_kv_atomic(os.path.join(d, "launch.txt"), info)
            old = time.time() - age
            for dp, dn, ns in os.walk(d):
                for n_ in ns:
                    os.utime(os.path.join(dp, n_), (old, old))
                os.utime(dp, (old, old))
            return d
        owner = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        try:
            tok = proc_start_token(owner.pid)
            live = mk(SESSION_PREFIX + "live", [("pid", owner.pid), ("start", tok)], 0)
            quiet = mk(SESSION_PREFIX + "quiet", [("pid", owner.pid), ("start", tok)], 7200)
            reused = mk(SESSION_PREFIX + "reused", [("pid", owner.pid), ("start", "x0")], 7200)
            dead = mk(SESSION_PREFIX + "dead", [("pid", 999999), ("start", "x1")], 7200)
            other = mk("MyCorpus", None, 7200)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                c = NS()
                c.session, c.wait, c.report = live, 0.0, False
                rc_live = cmd_cleanup(c)
                c.session, c.report = other, True
                cmd_cleanup(c)
                a = NS()
                a.base, a.report = base, True
                cmd_cleanup_stale(a)
            ok &= rc_live == 1 and os.path.isdir(live) and os.path.exists(
                os.path.join(live, "sub", "x.wav"))
            notes.append("live engine: cleanup rc %d, nothing deleted" % rc_live)
            ok &= os.path.isdir(quiet) and not os.path.exists(reused) and not os.path.exists(dead)
            ok &= os.path.isdir(other)
            notes.append("stale: quiet-but-alive kept, reused-PID and dead removed, "
                         "foreign refused")
        finally:
            owner.kill()
            owner.wait()
        c = NS()
        c.session, c.wait, c.report = live, 5.0, False
        rc_after = cmd_cleanup(c)
        ok &= rc_after == 0 and not os.path.exists(live)
        notes.append("after the engine exited: rc %d, folder removed" % rc_after)
        notes.append(buf.getvalue().strip().replace("\n", " | "))
    return ok, "; ".join(notes)


V030_TESTS = [("memory insertion", _t_mem_insert), ("similarity ranking", _t_mem_rank),
              ("missing pitch", _t_mem_nopitch), ("self / identity exclusion", _t_mem_self),
              ("generation limit", _t_mem_generation), ("cooldown", _t_mem_cooldown),
              ("empty-memory fallback", _t_mem_empty), ("contrast mode", _t_mem_contrast),
              ("weights never override 0", _t_mem_weights), ("eviction", _t_mem_evict),
              ("Corpus C read-only indexing", _t_mem_corpus_c),
              ("session cleanup safety", _t_mem_cleanup)]


# ---------------- v0.4.0 playback unit tests (offline, no device) ----------------
def _tone(sr, f, dur, amp=0.5):
    import numpy as np
    t = np.arange(int(dur * sr)) / sr
    return (amp * np.sin(2 * np.pi * f * t)).astype(np.float32)


def _t_pb_stereo(sr):
    import numpy as np
    import random
    rng = random.Random(1)
    m = _tone(sr, 440, 1.0)
    out = spatialize(m[:, None], sr, -0.6, 0.0, 1.0, rng)
    eL, eR, eM = float(np.sum(out[:, 0] ** 2)), float(np.sum(out[:, 1] ** 2)), float(np.sum(m ** 2))
    th = (-0.6 + 1) * math.pi / 4
    want = 20 * math.log10(math.cos(th) / math.sin(th))
    got = 10 * math.log10(eL / eR)
    c = float(np.corrcoef(out[:, 0], out[:, 1])[0, 1])
    power = (eL + eR) / eM
    fold = [10 * math.log10(float(np.sum((spatialize(m[:, None], sr, p, 0, 1.0, rng).sum(axis=1)
                                            / math.sqrt(2)) ** 2)) / eM) for p in (-1, -0.5, 0, 0.5, 1)]
    alloc = SpaceAllocator(random.Random(2), 1.0, 0.5)
    vs = []
    for role in ("fg", "fg", "sec", "bg"):
        vs.append(Voice(np.zeros((10, 2), np.float32), role, role, alloc.place(role, vs)))
    gaps = min(abs(a.center - b.center) for i, a in enumerate(vs) for b in vs[i + 1:])
    ok = abs(got - want) < 0.1 and abs(power - 1) < 0.01 and c > 0.999 and \
        max(fold) - min(fold) <= 3.05 and gaps >= 0.2
    return ok, ("L/R %.2f dB (equal-power %.2f), power %.3f, L-R correlation %.3f (no "
                "decorrelation), mono fold-down spread %.2f dB, 4 voices min spacing %.2f" %
                (got, want, power, c, max(fold) - min(fold), gaps))


def _t_pb_stereo_keep(sr):
    import numpy as np
    import random
    a = np.stack([_tone(sr, 330, 1.0), _tone(sr, 550, 1.0, 0.3)], axis=1)
    out = spatialize(a, sr, 0.0, 0.0, 1.0, random.Random(1))
    err = float(np.max(np.abs(out - a)))
    out2 = spatialize(a, sr, 0.0, 0.0, 0.0, random.Random(1))
    narrow = float(np.max(np.abs(out2[:, 0] - out2[:, 1])))
    return err < 1e-5 and narrow < 1e-5, ("stereo source at width 1 unchanged (max error %.1e); "
                                         "width 0 folds it to the centre" % err)


def _t_pb_envelope(sr):
    import numpy as np
    tone = np.full((int(1.0 * sr), 1), 0.5, np.float32)            # abrupt DC block
    b, fi, fo = shape_envelope(tone, sr, 0.03, 0.4, False)         # musical fade-in
    jump = float(np.max(np.abs(np.diff(b[:, 0]))))
    ends = (abs(float(b[0, 0])), abs(float(b[-1, 0])))
    bt, fit, _ = shape_envelope(tone, sr, 0.03, 0.4, True)         # treated as a transient
    jt = float(np.max(np.abs(np.diff(bt[:, 0]))))
    ramp_max = 0.5 * math.pi / (2 * int(fit * sr)) * 1.05            # smooth 1 ms ramp, no step
    # percussive: decaying click must keep its attack
    t = np.arange(int(0.5 * sr)) / sr
    hit = (np.exp(-t * 40) * np.sin(2 * np.pi * 1200 * t)).astype(np.float32)[:, None]
    hb, hfi, _ = shape_envelope(hit, sr, 0.03, 0.4, True)
    keep = float(np.max(np.abs(hb[:int(0.01 * sr)]))) / float(np.max(np.abs(hit[:int(0.01 * sr)])))
    short = shape_envelope(np.ones((int(0.2 * sr), 1), np.float32) * 0.3, sr, 0.03, 0.4, True)
    tb, _, tfo = shape_envelope(np.ones((sr * 2, 1), np.float32) * 0.3, sr, 0.03, 0.4, True,
                                truncated=True)
    ok = ends[0] < 1e-3 and ends[1] < 1e-3 and jump < 0.01 and jt <= ramp_max and \
        keep > 0.9 and hfi <= 0.0011 and short[2] <= 0.061 and tfo >= 0.5
    return ok, ("ends %.1e/%.1e, largest step %.4f (30 ms fade) / %.4f (1 ms anti-click ramp); "
                "percussive attack kept %.0f %% (fade-in %.0f ms); 0.2 s sound fade-out %.0f ms;"
                " truncated fade-out %.2f s" % (ends[0], ends[1], jump, jt, 100 * keep,
                                                1000 * hfi, 1000 * short[2], tfo))


def _t_pb_overlap(sr):
    import numpy as np
    mx = Mixer(sr)
    bufs = [np.full((sr, 2), 0.1, np.float32) for _ in range(3)]
    for k, b in enumerate(bufs):
        mx.add(Voice(b, "fg", "v%d" % k, 0.0, wait=int(0.3 * k * sr)))
    blocks, act = [], []
    for _ in range(int(2.0 * sr / 441)):
        blocks.append(mx.render(441).copy())
        act.append(sum(1 for v in mx.voices if not v.done and v.wait == 0 and v.pos > 0))
    y = np.concatenate(blocks)
    at = {t: float(y[int(t * sr), 0]) for t in (0.1, 0.45, 0.75, 1.15, 1.45)}
    ok = abs(at[0.1] - 0.1) < 1e-6 and abs(at[0.45] - 0.2) < 1e-6 and \
        abs(at[0.75] - 0.3) < 1e-6 and abs(at[1.15] - 0.2) < 1e-6 and max(act) == 3
    return ok, "3 voices entering 0.3 s apart: mix level %s, max simultaneous %d" % (
        " ".join("%.1f" % v for v in at.values()), mx.max_active)


def _t_pb_steal(sr):
    import numpy as np
    import types

    class FakeEngine:
        pass
    e = FakeEngine()
    e.pcfg = {"polyphony": True, "max_voices": 3}
    e.mixer = Mixer(sr)
    e.stop_ev = threading.Event()
    e.c = collections.Counter()
    e.log = lambda *a, **k: None
    alloc = types.MethodType(Engine._allocate, e)
    mk = (lambda role: Voice(np.zeros((sr, 2), np.float32), role, role, 0.0))
    bg, sec, fg1 = mk("bg"), mk("sec"), mk("fg")
    for v in (bg, sec, fg1):
        alloc(v, False)
    r1 = alloc(mk("fg"), False)                # steals the background
    r2 = alloc(mk("sec"), False)               # no background left: refused
    r3 = alloc(mk("fg"), False)                # steals the secondary voice
    ok = r1 and not r2 and r3 and bg.kill and sec.kill and not fg1.kill
    return ok, "fg steals bg first, then sec; sec may not steal fg (stolen %d)" % e.c["voices_stolen"]


def _t_pb_clip(sr):
    import numpy as np
    mx = Mixer(sr)
    for k in range(6):
        mx.add(Voice(np.stack([_tone(sr, 200 + 37 * k, 1.0, 0.99)] * 2, axis=1), "fg", "v", 0.0))
    ys = [mx.render(441).copy() for _ in range(80)]
    pk = max(float(np.max(np.abs(y))) for y in ys)
    ok = pk <= LIMIT_CEILING + 1e-6 and all(np.isfinite(y).all() for y in ys)
    return ok, "6 full-scale voices: output peak %.3f (ceiling %.2f), limiter %.1f dB" % (
        pk, LIMIT_CEILING, mx.max_reduction_db)


def _t_pb_shutdown(sr):
    import numpy as np
    mx = Mixer(sr)
    mx.add(Voice(np.stack([_tone(sr, 300, 3.0, 0.8)] * 2, axis=1), "fg", "v", 0.0))
    pre = [mx.render(441).copy() for _ in range(20)]
    mx.fade_all(STOP_FADE_S)
    post = [mx.render(441).copy() for _ in range(int(0.3 * sr / 441))]
    y = np.concatenate(pre + post)[:, 0]
    jump = float(np.max(np.abs(np.diff(y))))
    tail = float(np.max(np.abs(post[-1])))
    natural = 2 * math.pi * 300 / sr * 0.8
    ok = tail < 1e-6 and jump <= natural * 1.05
    return ok, "stop fade %.0f ms: last block %.1e, largest step %.4f (tone itself %.4f)" % (
        1000 * STOP_FADE_S, tail, jump, natural)


def _t_pb_background(sr):
    import numpy as np
    import random
    src = (_tone(sr, 220, 2.5, 0.4) * (1 + 0.3 * np.sin(np.arange(int(2.5 * sr)) / sr * 3))).astype(
        np.float32)
    tex = build_texture([(src, sr)], sr, 24.0, 1.0, 0.3, random.Random(3))
    k = int(0.1 * sr)
    mid = tex[int(3.2 * sr):int(20.8 * sr)].mean(axis=1)
    nf = len(mid) // k
    r = 20 * np.log10(np.sqrt(np.mean(mid[:nf * k].reshape(nf, k) ** 2, axis=1)) + 1e-12)
    dist = float(np.max(np.abs(tex[:, 0] - tex[:, 1])))
    ends = float(np.max(np.abs(tex[:50]))), float(np.max(np.abs(tex[-50:])))
    mx = Mixer(sr)
    v = Voice(tex, "bg", "bg", 0.0, gain=1.0, rate=0.5)
    mx.add(v)
    mx.render(441)
    v.target = 0.35                              # performer plays: recede
    gs = []
    for _ in range(int(1.5 * sr / 441)):
        mx.render(441)
        gs.append(v.gain)
    steps = float(np.max(np.abs(np.diff(gs))))
    ok = len(tex) == int(24.0 * sr) and float(r.max() - r.min()) < 12 and dist > 1e-3 and \
        max(ends) < 1e-3 and abs(gs[-1] - 0.35) < 1e-6 and steps <= 0.5 * 441 / sr + 1e-9
    return ok, ("24 s texture: no gaps (100 ms level range %.1f dB), stereo, faded ends; "
                "recedes to -9 dB in %.1f s in steps <= %.4f" %
                (float(r.max() - r.min()), (gs.index(0.35) + 1) * 441 / sr if 0.35 in gs else -1,
                 steps))


def _t_pb_leak_stereo(sr):
    import numpy as np
    rng = np.random.default_rng(4)
    L = rng.standard_normal(sr).astype(np.float32)
    R = rng.standard_normal(sr).astype(np.float32)
    mx, lag = 2000, 800
    xl, xr = L[:int(0.5 * sr) + mx], R[:int(0.5 * sr) + mx]
    y = 0.3 * xl[mx - lag:mx - lag + int(0.5 * sr)] + 0.02 * xr[mx - lag:mx - lag + int(0.5 * sr)]
    a, rho, lg = leak_fit((xl + xr) / 2, y, mx)
    r2 = leak_fit_stereo(xl, xr, y, mx, lg)
    ok = lg == lag and r2 > 0.99 and r2 > rho * rho + 0.2
    return ok, ("voice panned left leaking: mono fit explains %.0f %%, two-channel fit %.0f %% "
                "(lag %d)" % (100 * rho * rho, 100 * r2, lg))


V040_TESTS = [("stereo placement / mono compatibility", _t_pb_stereo),
              ("stereo source preserved", _t_pb_stereo_keep),
              ("envelope continuity", _t_pb_envelope),
              ("polyphonic overlap", _t_pb_overlap), ("voice stealing", _t_pb_steal),
              ("clipping prevention", _t_pb_clip), ("safe shutdown fade", _t_pb_shutdown),
              ("background texture + receding", _t_pb_background),
              ("stereo leakage fit", _t_pb_leak_stereo)]


# ---------------- v0.4.1 unit tests ----------------
def _t_corpus_only(sr):
    mem0 = SonicMemory(_mem_cfg(response_mode="corpus_only"), 1)
    a0 = mem0.choose_action(None, None)
    mem = _mem_fill(sr, corpus="C", response_mode="corpus_only", use_A=False, use_B=False)
    q = mem.items["C"][0]
    ch, top, why = mem.retrieve(q.desc, exclude_ids={q.id})
    rt = pick_recall_transform(ch, top, None, 2)
    acts = set(mem.choose_action(ch, rt)[0] for _ in range(50))
    strict = _mem_fill(sr, corpus="C", response_mode="corpus_only", min_similarity=0.999)
    ch2, _, _ = strict.retrieve(q.desc, exclude_ids={q.id})
    a2 = strict.choose_action(ch2, None)
    ok = a0[0] == "silence" and ch is not None and acts == {"recall"} and \
        ch2 is None and a2[0] == "silence"
    return ok, ("empty memory -> %s; with a match (and a R+T candidate) 50 draws -> %s; "
                "no match above 0.999 -> %s" % (a0[0], sorted(acts), a2[0]))


def _t_kweight(sr):
    import numpy as np
    t = np.arange(int(3.0 * sr)) / sr
    l1k = active_loudness_db(0.1 * np.sin(2 * np.pi * 997 * t), sr)
    l1k48 = active_loudness_db(0.1 * np.sin(2 * np.pi * 997 * np.arange(3 * 48000) / 48000), 48000)
    l40 = active_loudness_db(0.1 * np.sin(2 * np.pi * 40 * t), sr)
    l4k = active_loudness_db(0.1 * np.sin(2 * np.pi * 4000 * t), sr)
    st = np.stack([0.1 * np.sin(2 * np.pi * 997 * t)] * 2, axis=1)
    lst = active_loudness_db(st, sr)
    gap = np.concatenate([0.1 * np.sin(2 * np.pi * 997 * t[:sr]), np.zeros(2 * sr)])
    lgap = active_loudness_db(gap, sr)
    ok = abs(l1k + 23.01) < 0.3 and abs(l1k48 + 23.01) < 0.3 and l40 < l1k - 2.0 and \
        l4k > l1k + 2.0 and abs(lst - l1k - 3.01) < 0.05 and abs(lgap - l1k) < 0.3
    return ok, ("997 Hz at -20 dBFS: %.2f (44.1k) / %.2f (48k) [BS.1770: -23.01]; 40 Hz %.2f, "
                "4 kHz %.2f; stereo +%.2f; silence gated %.2f" % (
                    l1k, l1k48, l40, l4k, lst - l1k, lgap))


def _t_follow(sr):
    f = LevelFollower(9.0)
    seq = []
    for db in (-30, -30, -30, -30, -30):
        seq.append(f.update(db))
    steady = seq[-1]
    for db in (-36, -36, -36):
        f.update(db)
    softer = f.offset
    f.update(-10.0, excluded=True)
    after_excl = f.offset
    for _ in range(3):
        f.update(-80.0)
    clamped = f.offset
    early = LevelFollower(9.0)
    e = [early.update(d) for d in (-20.0, -40.0)]
    ok = steady == 0.0 and -6.0 < softer < -2.0 and after_excl == softer and \
        clamped == -9.0 and e == [0.0, 0.0] and f.excluded == 1
    return ok, ("steady %.1f; 6 dB softer x3 -> %+.1f dB; leaked phrase ignored (%+.1f); "
                "40 dB softer -> clamped %+.1f; no offset before 3 phrases" % (
                    steady, softer, after_excl, clamped))


def _t_voice_level(sr):
    """Offsets reach the voice: same tone, follow -6 dB and Corpus C +3 dB."""
    import numpy as np
    import random
    import types

    class FakeArgs:
        max_response = 20.0

    class FakeEngine:
        pass

    def make(off, corpus_db, corpus):
        e = FakeEngine()
        e.np, e.sr, e.a = np, sr, FakeArgs()
        e.pcfg = {"fade_in": 0.03, "fade_out": 0.4, "transients": True, "level_match": True,
                  "movement": 0.0, "width": 1.0, "corpus_c_db": corpus_db}
        e.follower = LevelFollower(9.0)
        e.follower.offset = off
        e.prng = random.Random(1)
        e.mixer = Mixer(sr)
        e.space = SpaceAllocator(e.prng, 1.0, 0.0)
        e._level_offset = types.MethodType(Engine._level_offset, e)
        mk = types.MethodType(Engine._make_voice, e)
        v, _ = mk(_tone(sr, 330, 2.0, 0.2), sr, "fg", "t", corpus=corpus)
        return 20 * math.log10(active_rms(v.buf))
    base = make(0.0, 0.0, None)
    soft = make(-6.0, 0.0, None)
    c_up = make(0.0, 3.0, "C")
    c_ign = make(0.0, 3.0, "A")
    ok = abs(soft - base + 6.0) < 0.1 and abs(c_up - base - 3.0) < 0.1 and abs(c_ign - base) < 0.01
    return ok, ("follow -6 dB -> %+.2f dB; Corpus C +3 dB -> %+.2f dB; non-C sound %+.2f dB" % (
        soft - base, c_up - base, c_ign - base))


def _t_args_file(sr):
    """v0.4.4: the argument file as Praat writes it, in every encoding Praat
    may choose, with a non-Latin path and an incomplete file."""
    import tempfile
    args = ["--session", "C:/Temp/AudioTools_CR_1", "--corpus-c",
            "C:/Users/user/\u05e7\u05d5\u05e8\u05e4\u05d5\u05e1 C/sounds", "--w-preloaded", "100.000",
            "--sensitivity", "9.000"]
    body = "# AudioTools Call & Response engine arguments\n" + "\n".join(args) + "\n#end\n"
    out = []
    with tempfile.TemporaryDirectory(prefix="atcr_args_") as d:
        p = os.path.join(d, "a.txt")
        for enc, bom, nl in (("utf-16-le", b"\xff\xfe", "\n"), ("utf-8", b"", "\r\n"),
                             ("utf-8", b"\xef\xbb\xbf", "\n")):
            with open(p, "wb") as fh:
                fh.write(bom + body.replace("\n", nl).encode(enc))
            out.append(read_args_file(p) == args)
        latin = list(args)
        latin[3] = "C:/Users/Ren\u00e9/sounds"
        with open(p, "wb") as fh:
            fh.write(("\n".join(latin) + "\n#end\n").encode("latin-1"))
        out.append(read_args_file(p) == latin)
        with open(p, "w") as fh:
            fh.write("\n".join(args[:3]) + "\n")            # cut off: no #end
        try:
            read_args_file(p)
            out.append(False)
        except ValueError:
            out.append(True)
    # and the parsed values arrive intact
    ok = all(out)
    return ok, "UTF-16 / UTF-8 CRLF / UTF-8 BOM / Latin-1 read exactly; incomplete file refused (%s)" % out


def _t_trim_quiet(sr):
    """v0.4.5: fits -> untouched; too long -> cut at the quiet point near
    the limit, faded, never early; no quiet point -> cut near the limit."""
    import numpy as np
    t = np.arange(int(25 * sr)) / sr
    x = (0.3 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)
    x[int(20.4 * sr):int(20.6 * sr)] *= 0.001             # a near-silence at 20.4-20.6 s
    a1, c1 = trim_quiet(x[:int(21 * sr)], sr, 21.5)
    a2, c2 = trim_quiet(x, sr, 21.5)
    y = (0.3 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)
    a3, c3 = trim_quiet(np.stack([y, y], axis=1), sr, 21.5)
    end2 = len(a2) / sr
    ok = (not c1 and len(a1) == int(21 * sr) and c2 and 20.4 <= end2 <= 20.62
          and abs(float(a2[-1])) < 1e-3 and c3 and 0.85 * 21.5 <= len(a3) / sr <= 21.5
          and float(np.max(np.abs(a3[-5:]))) < 1e-3 and len(a3) / sr >= 21.0)
    return ok, ("21 s under a 21.5 s limit untouched; 25 s cut at the quiet point %.2f s; "
                "no quiet point: cut at %.2f s (close to the limit), faded" % (
                    end2, len(a3) / sr))


def _t_whole_answers(sr):
    """v0.4.5 end to end on Engine methods (no device): an answer slightly
    over Max_response_s plays whole, Corpus B keeps a 19 s answer whole,
    a layer is the whole sound or an onset -> natural-end excerpt."""
    import numpy as np
    import random
    import types

    class A_:
        max_response = 20.0

    class E:
        pass
    e = E()
    e.np, e.sr, e.a = np, sr, A_()
    e.c = collections.Counter()
    e.log = lambda *a, **k: None
    e.pcfg = {"fade_in": 0.03, "fade_out": 0.4, "transients": True, "level_match": False,
              "movement": 0.0, "width": 1.0, "corpus_c_db": 0.0, "polyphony": True,
              "max_voices": 4, "density": 1.0, "layer_shape": "whole"}
    e.follower = None
    e.graph = None
    e.prng = random.Random(3)
    e.mixer = Mixer(sr)
    e.space = SpaceAllocator(e.prng, 1.0, 0.0)
    for nm in ("_level_offset", "_make_voice", "_insert_processed", "_plan_secondary"):
        setattr(e, nm, types.MethodType(getattr(Engine, nm), e))
    v1, t1 = e._make_voice(_tone(sr, 330, 21.0, 0.3), sr, "fg", "x")
    v2, t2 = e._make_voice(_tone(sr, 330, 30.0, 0.3), sr, "fg", "x")
    e.mcfg = _mem_cfg(max_item_s=15.0, layered=True, max_generation=2)
    e.memory = SonicMemory(e.mcfg, 1)
    e.layer_history = collections.deque(maxlen=4)
    t = np.arange(int(19 * sr)) / sr
    ans = (0.3 * np.sin(2 * np.pi * 300 * t) * (1 + 0.5 * np.sin(2 * np.pi * 0.3 * t)))
    e._insert_processed({"tag": "0001", "answer": ans.astype(np.float32)[:, None], "sr": sr,
                         "used": "paulstretch", "source_id": "A0001", "gen_out": 1})
    b = e.memory.items["B"]
    b_len = b[0].duration if b else 0.0
    b_audio = len(b[0].audio) / sr if b else 0.0
    # layers from a memory of the six gestures (groove has clear onsets)
    mem = _mem_fill(sr, layered=True)
    e.memory = mem
    F = _mem_items(sr)["paulstretch"][1]
    lens = {}
    for shape in ("whole", "excerpt"):
        e.pcfg["layer_shape"] = shape
        out = []
        for k in range(12):
            e.layer_history.clear()
            for it in mem.all_items():
                it.recalls = 0
            j = Job(k + 1, np.zeros((sr, 1), np.float32), sr, {"end": 0})
            j.phrase_id = j.source_id = "none"
            e._plan_secondary(j, F, None, [])
            if j.secondary is not None:
                src = [it for it in mem.all_items() if it.id == j.secondary["name"].split()[-1]][0]
                full = len(src.get_audio())
                got = len(j.secondary["audio"])
                tail_same = bool(np.array_equal(j.secondary["audio"][-50:], src.get_audio()[-50:]))
                out.append((got == full, tail_same, got / full))
        lens[shape] = out
    whole_ok = lens["whole"] and all(w for w, _, _ in lens["whole"])
    exc_ok = lens["excerpt"] and all(tail for _, tail, _ in lens["excerpt"]) and \
        all(r >= 0.6 - 1e-9 for _, _, r in lens["excerpt"])
    n_exc = sum(1 for w, _, _ in lens["excerpt"] if not w)
    ok = (not t1 and abs(v1.n / sr - 21.0) < 0.01 and t2 and 21.0 <= v2.n / sr <= 21.5
          and abs(b_len - 19.0) < 0.05 and abs(b_audio - 19.0) < 0.05 and whole_ok and exc_ok)
    return ok, ("21 s answer plays %.1f s (%s); 30 s -> %.1f s (%s); Corpus B keeps %.1f s of a "
                "19 s answer (Max_item_s 15); layers whole: %d/%d complete; excerpt: %d/%d end "
                "at the natural end (%d started at an onset)" % (
                    v1.n / sr, v1.shape, v2.n / sr, v2.shape, b_audio,
                    sum(1 for w, _, _ in lens["whole"] if w), len(lens["whole"]),
                    sum(1 for _, tl, _ in lens["excerpt"] if tl), len(lens["excerpt"]), n_exc))


def _t_graph_sim(sr):
    """v0.4.6: the vectorised map similarity equals SonicMemory.similarity
    in modes without the contour stage (timbre, rhythm)."""
    import numpy as np
    mem = _mem_fill(sr)
    its = mem.items["A"]
    sc = mem._scales(its, its[0].desc)
    err = 0.0
    for mode in ("timbre", "rhythm"):
        S = graph_similarity([it.desc for it in its], [it.desc for it in its], sc, mode)
        for i, it in enumerate(its):
            for p, s, _ in mem.similarity(it.desc, its, mode, scales=sc):
                err = max(err, abs(S[i, its.index(p)] - s))
    return err < 1e-9, "max difference to the retrieval similarity %.1e (timbre, rhythm)" % err


def _t_graph_map(sr):
    """v0.4.6: a map with C, A, B, a ghost phrase and all action kinds;
    rows are well-formed, every arc's ends are on the line, Corpus C on the
    left, the sounding item flagged, links of 300 C sounds fast."""
    import numpy as np
    mem = _mem_fill(sr, corpus="C")
    a_mem = _mem_fill(sr)
    for it in a_mem.items["A"][:3]:
        it.t = time.time()
        mem.items["A"].append(it)
    g = MemoryGraph(mem, "hybrid", 0.3)
    g.link(mem.items["C"], pool=mem.items["C"])
    g.link(mem.items["A"])
    a0 = mem.items["A"][0].id
    g.phrase(a0, mem.items["A"][0].t, "paulstretch")
    g.phrase("A0099", time.time() + 1, "groove")          # not stored: ghost
    g.action(a0, mem.items["C"][2].id, "recall", 0.8)
    g.action("A0099", mem.items["C"][5].id, "recall_transform", 0.6)
    b = CorpusItem("B0001", "B", np.zeros((sr, 1), np.float32), sr, mem.items["C"][5].F,
                   mem.items["C"][5].desc, mem.items["C"][5].info, time.time() + 2,
                   {"root": "x", "parent": mem.items["C"][5].id, "generation": 1})
    mem.items["B"].append(b)
    g.link([b])
    g.action(mem.items["C"][5].id, "B0001", "transform")
    rows, nodes = g.build()
    text = graph_tsv(rows, nodes, sounding={"B0001"})
    lines = text.strip().split("\n")
    cols = [l.split("\t") for l in lines[1:]]
    ok = all(len(c) == 9 for c in cols) and lines[0].startswith("kind\t")
    xs = dict((c[8], float(c[1])) for c in cols if c[0] == "node")
    kinds = collections.Counter(c[0] for c in cols)
    acts = [c[8] for c in cols if c[0] == "edge" and c[3] == "-1"]
    ok &= set(acts) == {"recall", "recall_transform", "transform"}
    ok &= max(x for k, x in xs.items() if k.startswith("C")) < min(
        x for k, x in xs.items() if not k.startswith("C"))
    ok &= "A0099" in xs and [c for c in cols if c[0] == "node" and c[8] == "B0001"][0][3] == "1"
    ends = all(float(c[1]) in xs.values() and float(c[2]) in xs.values()
               for c in cols if c[0] == "edge")
    # speed: 300 corpus sounds
    big = SonicMemory(_mem_cfg(), 1)
    rng = np.random.default_rng(1)
    src = list(_mem_items(sr).values())
    for i in range(300):
        au, F, info, d = src[i % 6]
        d2 = dict(d, groups={k: v + rng.normal(0, 0.3, v.shape) for k, v in d["groups"].items()})
        big.items["C"].append(CorpusItem("C%04d" % i, "C", None, sr, F, d2, info, 0,
                                         {"root": "x", "generation": 0}))
    t0 = time.perf_counter()
    gb = MemoryGraph(big, "hybrid", 0.45)
    gb.link(big.items["C"], pool=big.items["C"])
    rb, nb_ = gb.build()
    dt = time.perf_counter() - t0
    ok &= ends and dt < 2.0
    return ok, ("rows %s, actions %s, ghost phrase shown, C left of the performance, sounding "
                "flag set; 300 corpus sounds linked + laid out in %.2f s (%d arcs)" % (
                    dict(kinds), sorted(set(acts)), dt, sum(1 for r in rb if r[0] == "edge")))


def _t_level_stereo(sr):
    """v0.4.7: mono, dual-mono and decorrelated stereo sources, level-matched
    and placed, play equally loud (acoustic total of both channels).  The
    v0.4.6 rule made the decorrelated one +6 dB louder."""
    import numpy as np
    import random
    rng = np.random.default_rng(2)
    n = 3 * sr
    mono = (0.1 * rng.standard_normal(n)).astype(np.float32)
    srcs = {"mono": mono[:, None], "dual-mono": np.stack([mono, mono], axis=1),
            "decorrelated": np.stack([mono, (0.1 * rng.standard_normal(n)).astype(np.float32)], 1)}
    out, old = {}, {}
    for k, a in srcs.items():
        for ver, dst in (("new", out), ("old", old)):
            b, _ = level_match(a, -18.0, sr=sr) if ver == "new" else level_match(a, -18.0)
            st = spatialize(b, sr, 0.3, 0.0, 1.0, random.Random(1))
            dst[k] = loudness_profile(st, sr, "sum")[0]
    spread = max(out.values()) - min(out.values())
    ok = spread < 0.3 and old["decorrelated"] - old["mono"] > 5.0
    return ok, ("played loudness: %s (spread %.2f dB); v0.4.6: decorrelated %+.1f dB vs mono" % (
        ", ".join("%s %.2f" % kv for kv in out.items()), spread, old["decorrelated"] - old["mono"]))


def _t_level_burst(sr):
    """v0.4.7: sustained sounds reach the target; a percussive sequence is
    held by its loudest 100 ms (<= target + 6 dB); decorrelated stereo no
    longer overshoots; a stereo voice panned hard stays <= 0.9 after
    placement."""
    import numpy as np
    import random
    import types
    cases = synth_cases(sr)
    tgt = -18.0
    res = {}
    rng = np.random.default_rng(5)
    stereo_noise = np.stack([0.05 * rng.standard_normal(3 * sr),
                             0.05 * rng.standard_normal(3 * sr)], axis=1).astype(np.float32)
    for name, a in (("tone", cases["paulstretch"]), ("drums", cases["groove"]),
                    ("stereo noise", stereo_noise)):
        info = {}
        b, g = level_match(np.asarray(a, np.float32), tgt, sr=sr, info=info)
        i2, b2 = voice_loudness(b, sr)
        res[name] = (i2, b2, info["limited_by"])
    old_b, _ = level_match(stereo_noise, tgt)
    old_i, _ = voice_loudness(old_b, sr)

    class A_:
        max_response = 20.0

    class E:
        pass
    e = E()
    e.np, e.sr, e.a, e.c = np, sr, A_(), collections.Counter()
    e.pcfg = {"fade_in": 0.03, "fade_out": 0.4, "transients": True, "level_match": True,
              "movement": 0.0, "width": 1.0, "corpus_c_db": 0.0}
    e.follower, e.graph = None, None
    e.prng = random.Random(1)
    e.mixer = Mixer(sr)

    class Left:
        def place(self, role, others):
            return -0.95
    e.space = Left()
    e._level_offset = types.MethodType(Engine._level_offset, e)
    v, _ = types.MethodType(Engine._make_voice, e)(
        np.stack([cases["groove"], 0.2 * cases["groove"]], axis=1).astype(np.float32), sr, "fg", "x")
    vpk = float(np.max(np.abs(v.buf)))
    ok = (abs(res["tone"][0] - tgt) < 0.3 and res["drums"][1] <= tgt + BURST_HEADROOM_DB + 0.05
          and res["drums"][2] in ("burst", "peak") and abs(res["stereo noise"][0] - tgt) < 0.3
          and old_i > tgt + 2.0 and vpk <= VOICE_PEAK_CEILING + 1e-6)
    return ok, ("tone -> %.1f dB (%s); drums -> %.1f dB, burst %.1f dB (%s); decorrelated stereo -> "
                "%.1f dB (old rule %.1f); hard-panned stereo voice peak %.2f" % (
                    res["tone"][0], res["tone"][2], res["drums"][0], res["drums"][1],
                    res["drums"][2], res["stereo noise"][0], old_i, vpk))


def _blend_desc(a, b, wa):
    import numpy as np
    g = {k: wa * np.asarray(a["groups"][k], float) + (1 - wa) * np.asarray(b["groups"][k], float)
         for k in a["groups"]}
    return {"groups": g, "pitch_contour": a["pitch_contour"], "env_contour": a["env_contour"],
            "voiced": a["voiced"]}


def _t_influence(sr):
    """v0.4.8: (1) no influences = v0.4.7 ranking; (2) an ambiguous last
    phrase is pulled towards the gesture of the earlier phrases; (3) old
    history fades (half-life) and depth 1 ignores it; (4) the trend query
    is last + (last - previous)."""
    import numpy as np
    mem = _mem_fill(sr, min_similarity=0.0, candidates=6)
    its = _mem_items(sr)
    P, Sp = its["paulstretch"][3], its["spiral"][3]
    q = _blend_desc(P, Sp, 0.62)
    _, top0, _ = mem.retrieve(q)
    base = [(r["item"].p["source"], round(r["sim"], 9)) for r in top0]
    ranked = mem.similarity(q, [r["item"] for r in top0], "hybrid")
    same = base == [(it.p["source"], round(s, 9)) for it, s, _ in ranked]
    now = 1000.0
    hist = [("A0901", Sp, now - 20), ("A0902", Sp, now - 10)]
    infl = influence_queries(hist, now, 3, 0.5, 0.0, q)
    _, top1, _ = mem.retrieve(q, influences=infl)
    first0, first1 = top0[0]["item"].p["source"], top1[0]["item"].p["source"]
    old = influence_queries([("A0901", Sp, now - 600)], now, 3, 0.5, 0.0, q)
    d1 = influence_queries(hist, now, 1, 0.5, 0.0, q)
    tr = influence_queries(hist, now, 3, 0.5, 0.5, q)
    tq = [d for d, w, lab, pid in tr if lab == "trend"][0]
    exp_t = 2 * np.asarray(q["groups"]["timbre"]) - np.asarray(Sp["groups"]["timbre"])
    gated = influence_queries(hist, now, 3, 0.5, 0.5, q, gate=lambda d: influence_gate(0.2))
    half = influence_queries(hist, now, 3, 0.5, 0.0, q, gate=lambda d: influence_gate(0.45))
    ok = (same and first0 == "paulstretch" and first1 == "spiral" and old == [] and d1 == []
          and gated == [] and abs(half[0][1] - 0.5 * infl[0][1]) < 1e-9
          and np.allclose(tq["groups"]["timbre"], exp_t)
          and [lab for _, _, lab, _ in tr] == ["-1", "-2", "trend"])
    return ok, ("no influence: same ranking as v0.4.7 (top %s); after two Spiral phrases the "
                "same ambiguous phrase recalls %s (weights %s); 10-min-old history and depth 1 "
                "ignored; trend = last + (last - previous); unrelated history (sim 0.20) gated out, "
                "sim 0.45 counts half" % (
                    first0, first1, ", ".join("%s %.2f" % (lab, w) for _, w, lab, _ in infl)))


def _t_influence_fixes(sr):
    """v0.4.9: the gate sees the retrieval similarity (pitch mode, unpitched
    query); the map's pitch mode falls back to hybrid for unpitched queries;
    the score parts of a candidate add up to its influence score."""
    import numpy as np
    its = _mem_items(sr)
    mem = _mem_fill(sr, sim_mode="pitch", min_similarity=0.0)
    q, h = its["markov"][3], its["groove"][3]
    sc = mem._scales(mem.all_items(), q)
    real = mem.similarity(q, [_DescOnly(h)], "pitch", scales=sc)[0][1]
    gmap = float(graph_similarity([q], [h], sc, "pitch")[0, 0])
    ghyb = float(graph_similarity([q], [h], sc, "hybrid")[0, 0])
    infl = [(its["spiral"][3], 0.5, "-1", "x"), (its["paulstretch"][3], 0.25, "-2", "y")]
    cand, top, _ = mem.retrieve(its["spiral"][3], influences=infl)
    r = top[0]
    tot = 1.0 + 0.5 + 0.25
    ok = (abs(gmap - ghyb) < 1e-12 and q["voiced"] is False and len(r["parts"]) == 3
          and abs(sum(r["parts"]) / tot - r["sim"]) < 1e-9)
    return ok, ("unpitched phrase, pitch mode: gate now uses %.2f (= retrieval; the map's old "
                "pitch-only value was higher), map falls back to hybrid %.2f; score parts %s add "
                "up to the influence score %.3f" % (real, gmap, [round(p, 3) for p in r["parts"]],
                                                    r["sim"]))


def _det_run(sr, sig, **kw):
    det = PhraseDetector(sr, 1, 9.0, 0.5, 0.6, kw.get("max_phrase", 12.0), 0.25)
    hop = det.hop
    ev, phrases = [], []
    for i in range(0, len(sig) - hop, hop):
        e = det.feed(sig[i:i + hop])
        if e:
            ev.append((e, round(i / sr, 2)))
        if e == "end":
            phrases.append((round((i + hop) / sr, 2), len(det.phrase_audio()) / sr, det.ended_by))
            det.rearm()
    return det, ev, phrases


def _t_det_crescendo(sr):
    """v0.4.10: 2 s and 3 s crescendos from near-silence are detected and
    captured from (close to) their start; an abrupt entry still works."""
    import numpy as np
    rng = np.random.default_rng(1)
    noise = lambda s: 0.002 * rng.standard_normal(int(s * sr))
    out = []
    ok = True
    for ramp in (2.0, 3.0):
        t = np.arange(int(ramp * sr)) / sr
        tone = 0.2 * np.sin(2 * np.pi * 330 * t) * (t / ramp) ** 2
        hold = 0.2 * np.sin(2 * np.pi * 330 * np.arange(sr) / sr)
        sig = np.concatenate([noise(1.0), tone + noise(ramp), hold + noise(1.0), noise(1.5)])
        det, ev, ph = _det_run(sr, sig)
        on_t = [t_ for e, t_ in ev if e == "onset"]
        dur = ph[0][1] if ph else 0.0
        # the sounding part is ramp + 1 s; quieter than floor + 3 dB at the very start
        ok &= len(on_t) == 1 and dur >= ramp * 0.75 + 1.0
        out.append("%.0f s fade-in: onset at %.2f s, phrase %.2f s" % (ramp, on_t[0] if on_t else -1, dur))
    t = np.arange(int(1.5 * sr)) / sr
    det, ev, ph = _det_run(sr, np.concatenate([noise(1.0), 0.2 * np.sin(2 * np.pi * 330 * t), noise(1.5)]))
    ok &= [e for e, _ in ev] == ["onset", "end"]
    return ok, "; ".join(out) + "; abrupt entry: %s" % [e for e, _ in ev]


def _t_det_long(sr):
    """v0.4.10: a 14 s phrase is cut at its quiet dip near 12 s and the rest
    continues as the next phrase - the two phrases together hold the whole
    sound; without a dip the cut falls near the limit, again without loss."""
    import numpy as np
    rng = np.random.default_rng(2)
    noise = lambda s: 0.002 * rng.standard_normal(int(s * sr))
    t = np.arange(int(14 * sr)) / sr
    tone = 0.2 * np.sin(2 * np.pi * 220 * t)
    dip = tone.copy()
    dip[int(10.5 * sr):int(10.58 * sr)] *= 0.08                # 80 ms quiet moment at 10.5 s
    res = []
    ok = True
    for name, x in (("with a dip", dip), ("steady", tone)):
        det, ev, ph = _det_run(sr, np.concatenate([noise(1.0), x, noise(1.5)]))
        total = sum(p[1] for p in ph)
        cut = ph[0][0] if ph else -1
        ok &= len(ph) == 2 and ph[0][2] == "max_duration" and 14.0 <= total <= 14.6
        res.append("%s: cut at %.2f s, phrases %s s, together %.2f s" % (
            name, ph[0][1] if ph else -1, [round(p[1], 2) for p in ph], total))
        if name == "with a dip":
            ok &= abs(ph[0][1] - (10.58 + 0.25 - 0.0)) < 0.25
    return ok, "; ".join(res)


def _t_det_room(sr):
    """v0.4.10: when the room noise rises 8 dB and stays, the floor learns it
    within seconds and false phrases stop (at most one)."""
    import numpy as np
    rng = np.random.default_rng(3)
    sig = np.concatenate([0.002 * rng.standard_normal(3 * sr), 0.005 * rng.standard_normal(14 * sr)])
    det, ev, ph = _det_run(sr, sig)
    onsets = sum(1 for e, _ in ev if e == "onset")
    floor_new = 20 * math.log10(0.005)
    ok = onsets == 0 and abs(det.floor - floor_new) < 3.0
    # a fan much louder than the threshold: one phrase, learned as background,
    # no endless chain of continuation phrases
    sig2 = np.concatenate([0.002 * rng.standard_normal(2 * sr), 0.02 * rng.standard_normal(40 * sr)])
    det2, ev2, ph2 = _det_run(sr, sig2)
    ok &= len(ph2) == 0 and det2.state == "LISTENING" and \
        sum(1 for e, _ in ev2 if e == "discarded") == 1
    t3 = np.arange(int(30 * sr)) / sr
    det3, ev3, ph3 = _det_run(sr, np.concatenate([0.002 * rng.standard_normal(sr),
                                                  0.2 * np.sin(2 * np.pi * 220 * t3)]))
    kinds3 = [p[2] for p in ph3]
    ok &= kinds3[:2] == ["max_duration", "max_duration"] and \
        "max_duration_steady" not in kinds3
    return ok, ("room noise +8 dB: %d onsets, floor learned %.1f dBFS (noise %.1f); a fan 20 dB "
                "above: %d answered phrase(s), discarded as noise after %.1f s; a 30 s held "
                "tone: %s" % (onsets, det.floor, floor_new, len(ph2),
                              [t_ for e, t_ in ev2 if e == "discarded"][0] - 2.0 if
                              any(e == "discarded" for e, _ in ev2) else -1, kinds3))


def _t_det_release(sr):
    """v0.4.11: phrases end reliably when (a) the first 0.5 s were digital
    silence (then mic noise), (b) calibration ran on a much quieter input,
    (c) the mic noise rose 4-8 dB just after calibration - each with 5
    played phrases.  (Playing from the very first moment, before any real
    input was heard, makes calibration measure the playing: that first
    phrase can be lost; the detector recovers by itself.)"""
    import numpy as np
    rng = np.random.default_rng(7)

    def perf(noise, n=5, lead=()):
        parts = list(lead)
        for k in range(n):
            parts += [0.1 * np.sin(2 * np.pi * (330 + 40 * k) * np.arange(int(1.5 * sr)) / sr)
                      + noise * rng.standard_normal(int(1.5 * sr)),
                      noise * rng.standard_normal(int(2.5 * sr))]
        return np.concatenate(parts)
    mic = 0.0014
    cases = {
        "digital silence first": perf(mic, lead=[np.zeros(int(0.5 * sr)),
                                                 mic * rng.standard_normal(int(1.0 * sr))]),
        "calibrated at -85": perf(mic, lead=[0.00008 * rng.standard_normal(int(0.6 * sr))]),
    }
    for rise in (4, 6, 8):
        lo = 0.0007
        hi = lo * 10 ** (rise / 20)
        cases["noise +%d dB after calibration" % rise] = perf(
            hi, lead=[lo * rng.standard_normal(int(0.8 * sr)), hi * rng.standard_normal(int(1.2 * sr))])
    res, ok = [], True
    for name, sig in cases.items():
        det, ev, ph = _det_run(sr, sig)
        n_sil = sum(1 for p in ph if p[2] in ("silence", "background"))
        ok &= n_sil == 5 and not any(p[2].startswith("max") for p in ph)
        res.append("%s: %d/5" % (name, n_sil))
    return ok, "phrases ended: " + ", ".join(res)


V041_TESTS = [("engine arguments via file (v0.4.4)", _t_args_file),
              ("phrase ends: calibration / noise changes (v0.4.11)", _t_det_release),
              ("phrase detection: crescendo entries (v0.4.10)", _t_det_crescendo),
              ("phrase detection: long phrase cut without loss (v0.4.10)", _t_det_long),
              ("phrase detection: change of room noise (v0.4.10)", _t_det_room),
              ("influence fixes: gate similarity, shares (v0.4.9)", _t_influence_fixes),
              ("phrase-level influence memory (v0.4.8)", _t_influence),
              ("stereo loudness measurement (v0.4.7)", _t_level_stereo),
              ("burst-aware level + peak after placement (v0.4.7)", _t_level_burst),
              ("memory map similarity = retrieval similarity (v0.4.6)", _t_graph_sim),
              ("memory map rows and layout (v0.4.6)", _t_graph_map),
              ("quiet-point trim (v0.4.5)", _t_trim_quiet),
              ("whole answers, Corpus B, layer shapes (v0.4.5)", _t_whole_answers),
              ("corpus only: recall or silence, never transform", _t_corpus_only),
              ("K-weighted loudness (BS.1770 reference)", _t_kweight),
              ("relative level follower", _t_follow),
              ("level offsets applied to voices", _t_voice_level)]


# ============================================================
# v0.3.0 SONIC MEMORY
#   Three in-RAM corpora (A live phrases, B processed responses, C preloaded
#   reference), a normalised nearest-neighbour retrieval layer with a
#   second-stage contour comparison, and the Transform / Recall /
#   Recall + Transform decision layer.  The v0.2 classifier is not changed:
#   it is consulted for the live phrase and, for Recall + Transform, for the
#   RETRIEVED audio.  Nothing here touches the disk except reading the
#   user's Corpus C files (read-only).
# ============================================================
CORPUS_NAMES = {"A": "Live", "B": "Processed", "C": "Preloaded"}
SIM_MODES = {
    # group weights; "_contour" = share of the second-stage contour distance
    "hybrid": {"timbre": 0.35, "pitch": 0.20, "rhythm": 0.20, "envelope": 0.20,
               "duration": 0.05, "_contour": 0.25, "_contours": ("pitch", "env")},
    "timbre": {"timbre": 1.0, "_contour": 0.0, "_contours": ()},
    "pitch": {"pitch": 1.0, "_contour": 0.40, "_contours": ("pitch",)},
    "rhythm": {"rhythm": 0.85, "duration": 0.15, "_contour": 0.0, "_contours": ()},
    "envelope": {"envelope": 1.0, "_contour": 0.40, "_contours": ("env",)},
}
SIM_MODES["contrast"] = SIM_MODES["hybrid"]
# Prior spreads per descriptor dimension: blended with the corpus spread so
# that z-scores are meaningful even with only a few items in memory.
GROUP_PRIOR = {
    "timbre": [8.0] + [3.0] * 11 + [0.35, 0.5, 0.5, 6.0],
    "pitch": [0.25, 0.8, 4.0, 3.0, 4.0, 0.2, 0.2],
    "rhythm": [1.0, 0.4, 0.3, 0.5, 4.0, 0.25, 0.15, 0.5],
    "envelope": [5.0, 0.6, 0.25, 5.0, 0.15],
    "duration": [0.5],
}
SIM_SCALE = 0.8                  # similarity = exp(-SIM_SCALE * distance)
IDENTITY_SIM = 0.97              # a Praat result this close to its source is not stored
DUPLICATE_SIM = 0.995            # a stored sound this close to the phrase is the same
                                 #   recording (e.g. re-captured playback): never recalled
CONTOUR_BINS = 32


def _contour(values, valid, bins=CONTOUR_BINS):
    import numpy as np
    out = np.full(bins, np.nan)
    n = len(values)
    if n == 0:
        return out
    edges = np.linspace(0, n, bins + 1).astype(int)
    for b in range(bins):
        seg = values[edges[b]:max(edges[b + 1], edges[b] + 1)]
        ok = valid[edges[b]:max(edges[b + 1], edges[b] + 1)]
        if ok.any():
            out[b] = float(np.mean(seg[ok]))
    return out


def memory_descriptor(F):
    """Retrieval descriptor from the v0.2 feature set (+ private arrays).
    Groups of raw values (NaN = not measurable, e.g. pitch of noise) and two
    32-point contours: pitch in semitones around the phrase median, and the
    envelope in dB below its peak."""
    import numpy as np
    voiced = F.get("voiced_frames", 0) >= 20
    nan = float("nan")
    cen = max(F["centroid_mean"], 20.0)
    timbre = list(np.asarray(F.get("_mfcc_mean", np.zeros(12)), float)[:12])
    timbre += [math.log(cen), math.log10(F["flatness"] + 1e-4),
               F["spectral_variability"], clamp(F["hnr_db"], -10.0, 35.0)]
    if voiced:
        pitch = [F["voiced_ratio"], math.log2(max(nz(F["f0_median"], 100.0), 20.0)),
                 F["pitch_range_st"], F["pitch_slope_st_s"], F["pitch_net_change_st"],
                 F["pitch_monotonicity"], F["pitch_continuity"]]
    else:
        pitch = [F["voiced_ratio"]] + [nan] * 6
    rhythm = [F["onset_rate"], F["ioi_cv"], F["density_cv"], F["density_trend"],
              F["transient_strength_db"], F["perc_char"], F["silence_ratio"],
              math.log(F["ioi_median"]) if F["ioi_median"] > 0 else nan]
    envelope = [F["env_dyn_range_db"], F["env_peak_rate"], F["env_complexity"],
                F["energy_slope_db_s"], F["active_ratio"]]
    duration = [math.log(max(F["duration"], 0.05))]
    f0 = np.asarray(F.get("_f0", np.array([])), float)
    pc = np.full(CONTOUR_BINS, np.nan)
    if voiced and len(f0):
        ok = ~np.isnan(f0)
        st = np.where(ok, 12 * np.log2(np.where(ok, f0, 100.0) / 100.0), 0.0)
        med = float(np.median(st[ok])) if ok.any() else 0.0
        pc = _contour(st - med, ok)
    env = np.asarray(F.get("_env", np.array([])), float)
    ec = np.full(CONTOUR_BINS, np.nan)
    if len(env):
        rel = np.maximum(env - env.max(), -40.0)
        ec = _contour(rel, np.ones(len(rel), bool))
    g = {k: np.asarray(v, float) for k, v in (("timbre", timbre), ("pitch", pitch),
                                             ("rhythm", rhythm), ("envelope", envelope),
                                             ("duration", duration))}
    return {"groups": g, "pitch_contour": pc, "env_contour": ec, "voiced": voiced}


INFLUENCE_HALF_LIFE_S = 45.0   # v0.4.8: an earlier phrase's influence halves every 45 s


class _DescOnly:
    """v0.4.9: a bare descriptor holder, so SonicMemory.similarity can
    compare two phrases that are not memory items."""
    __slots__ = ("desc",)

    def __init__(self, desc):
        self.desc = desc
INFLUENCE_GATE = (0.30, 0.60)  # v0.4.8: similarity to the last phrase -> 0 .. full influence


def influence_gate(sim):
    """v0.4.8 coherence gating: an earlier phrase influences only as far as
    it resembles the last one.  Below 0.30 nothing (a new idea starts a new
    history), above 0.60 fully, linear in between."""
    lo, hi = INFLUENCE_GATE
    return clamp((sim - lo) / (hi - lo), 0.0, 1.0)


def trend_descriptor(last, prev, amount=1.0):
    """v0.4.8: a descriptor extrapolated from `prev` to `last`:
    groups = last + amount * (last - prev) (a NaN in either stays NaN, i.e.
    'not measurable'); contours and voicing are those of `last`."""
    import numpy as np
    g = {}
    for k, v in last["groups"].items():
        d = np.asarray(v, float) - np.asarray(prev["groups"][k], float)
        g[k] = np.asarray(v, float) + amount * d
    return {"groups": g, "pitch_contour": last["pitch_contour"],
            "env_contour": last["env_contour"], "voiced": last["voiced"]}


def influence_queries(history, now, depth, decay, trend_weight, last_desc, gate=None):
    """v0.4.8: the weighted extra queries for retrieval.  history = list of
    (phrase id, desc, time) of the PREVIOUS phrases, newest last.  Returns
    [(desc, weight, label, phrase id)]: earlier phrases k = 1..depth-1 with
    weight decay^k * 0.5^(age / half-life), plus the trend query.
    gate(desc) -> 0..1 (coherence with the last phrase) multiplies each
    earlier phrase's weight; the trend uses the previous phrase's gate."""
    out = []
    prev = list(history)[::-1][:max(0, int(depth) - 1)]
    gates = [1.0 if gate is None else gate(d) for pid, d, t in prev]
    for k, (pid, d, t) in enumerate(prev, 1):
        w = (decay ** k) * 0.5 ** (max(0.0, now - t) / INFLUENCE_HALF_LIFE_S) * gates[k - 1]
        if w >= 0.02:
            out.append((d, w, "-%d" % k, pid))
    if trend_weight > 0 and prev:
        pid, d, t = prev[0]
        w = trend_weight * 0.5 ** (max(0.0, now - t) / INFLUENCE_HALF_LIFE_S) * gates[0]
        if w >= 0.02:
            out.append((trend_descriptor(last_desc, d), w, "trend", None))
    return out


class CorpusItem:
    """One sound in memory.  audio may be None for a Corpus C segment kept
    on demand: get_audio() re-reads it from the ORIGINAL file (read-only)."""

    def __init__(self, iid, corpus, audio, sr, F, desc, info, t, provenance):
        self.id = iid
        self.corpus = corpus
        self.audio = audio
        self.sr = sr
        self.duration = F["duration"]
        self.F = F
        self.desc = desc
        self.info = info                       # v0.2 decision for THIS audio
        self.t = t
        self.p = dict(provenance)              # root, parent, method, generation, source
        self.gesture = info["selected"]
        self.recalls = 0
        self.src = None                        # (path, start, stop) for C on demand

    @property
    def generation(self):
        return self.p.get("generation", 0)

    @property
    def root(self):
        return self.p.get("root", self.id)

    def get_audio(self):
        if self.audio is not None:
            return self.audio
        import soundfile as sf
        path, start, stop = self.src
        a, sr = sf.read(path, start=start, stop=stop, dtype="float32", always_2d=True)
        return a

    def ram_seconds(self):
        return 0.0 if self.audio is None else len(self.audio) / float(self.sr)


class SonicMemory:
    """Owns the three corpora.  Used from ONE thread only (the engine's brain
    worker), so it needs no locks; the status writer reads plain counters."""

    def __init__(self, cfg, seed, log=None):
        import random
        self.cfg = cfg
        self.rng = random.Random(seed)
        self.seed = seed
        self.items = {"A": [], "B": [], "C": []}
        self.next = {"A": 1, "B": 1, "C": 1}
        self.recall_history = collections.deque(maxlen=max(0, int(cfg.get("cooldown", 4))))
        self.log = log or (lambda *a, **k: None)
        self.t0 = time.time()
        self.evicted = 0

    # ---------------- bookkeeping ----------------
    def counts(self):
        return {k: len(v) for k, v in self.items.items()}

    def ram_seconds(self):
        return sum(it.ram_seconds() for v in self.items.values() for it in v)

    def all_items(self):
        return self.items["A"] + self.items["B"] + self.items["C"]

    def find(self, iid):
        for v in self.items.values():
            for it in v:
                if it.id == iid:
                    return it
        return None

    def new_id(self, corpus):
        i = self.next[corpus]
        self.next[corpus] += 1
        return "%s%04d" % (corpus, i)

    def add(self, item):
        self.items[item.corpus].append(item)
        self.enforce_limits()
        return item

    def enforce_limits(self):
        c = self.cfg
        while len(self.items["A"]) > c["max_live"]:
            self._evict(self.items["A"][0], "live corpus limit")
        while len(self.items["B"]) > c["max_processed"]:
            self._evict(self.items["B"][0], "processed corpus limit")
        budget = 60.0 * c["max_ram_min"]
        while self.ram_seconds() > budget:
            loaded_c = [it for it in self.items["C"] if it.audio is not None and it.src]
            if loaded_c:                                  # C audio is re-loadable
                loaded_c[0].audio = None
                continue
            ab = self.items["A"] + self.items["B"]
            if not ab:
                break
            self._evict(min(ab, key=lambda it: it.t), "audio memory limit")

    def _evict(self, item, why):
        self.items[item.corpus].remove(item)
        item.audio = None
        self.evicted += 1
        self.log("memory: evicted %s (%s)" % (item.id, why))

    def clear(self):
        for v in self.items.values():
            for it in v:
                it.audio = None
                it.F = None
            v.clear()

    # ---------------- weights ----------------
    def corpus_weights(self, progress):
        """Manual weights, optionally shaped by the evolving-memory curve.
        The curve only MULTIPLIES: a corpus switched off or weighted 0 by the
        performer can never be brought back by the adaptive strategy."""
        c = self.cfg
        w = {"A": c["w_live"] if c["use_A"] else 0.0,
             "B": c["w_processed"] if c["use_B"] else 0.0,
             "C": c["w_preloaded"] if c["use_C"] else 0.0}
        if c.get("evolving"):
            p = clamp(progress, 0.0, 1.0)
            shape = {"C": 0.15 + (1 - p) ** 2, "A": 0.15 + 4 * p * (1 - p), "B": 0.15 + p ** 2}
            w = {k: w[k] * shape[k] for k in w}
        return w

    # ---------------- similarity ----------------
    def _scales(self, pool, qdesc):
        import numpy as np
        sc = {}
        for gname, prior in GROUP_PRIOR.items():
            rows = [it.desc["groups"][gname] for it in pool] + [qdesc["groups"][gname]]
            M = np.vstack(rows)
            with np.errstate(all="ignore"):
                sd = np.nanstd(M, axis=0) if len(rows) > 2 else np.zeros(M.shape[1])
            sd = np.where(np.isnan(sd), 0.0, sd)
            sc[gname] = np.sqrt(sd ** 2 + np.asarray(prior, float) ** 2)
        return sc

    @staticmethod
    def group_distance(a, b, scale):
        import numpy as np
        d = (a - b) / scale
        ok = ~np.isnan(d)
        if not ok.any():
            return None
        return float(np.sqrt(np.mean(d[ok] ** 2)))

    @staticmethod
    def contour_distance(qd, it, which):
        import numpy as np
        out = []
        if "pitch" in which:
            a, b = qd["pitch_contour"], it.desc["pitch_contour"]
            ok = ~np.isnan(a) & ~np.isnan(b)
            if ok.sum() >= 8:
                out.append(float(np.mean(np.abs(a[ok] - b[ok]))) / 3.0)
        if "env" in which:
            a, b = qd["env_contour"], it.desc["env_contour"]
            ok = ~np.isnan(a) & ~np.isnan(b)
            if ok.sum() >= 8:
                out.append(float(np.mean(np.abs(a[ok] - b[ok]))) / 6.0)
        return (sum(out) / len(out)) if out else None

    def similarity(self, qdesc, items, mode, scales=None):
        """[(item, sim, distance)] for every item, best first."""
        import math as _m
        if mode == "pitch" and not qdesc["voiced"]:
            # an unpitched phrase has no pitch gesture to compare: in PITCH
            # mode two noises would look identical (only the voiced ratio
            # is measurable), so such a query is ranked with HYBRID weights
            mode = "hybrid"
        W = SIM_MODES.get(mode, SIM_MODES["hybrid"])
        scales = scales or self._scales(items, qdesc)
        res = []
        for it in items:
            num = den = 0.0
            for gname, w in W.items():
                if gname.startswith("_") or w <= 0:
                    continue
                d = self.group_distance(qdesc["groups"][gname], it.desc["groups"][gname],
                                        scales[gname])
                if d is None:
                    continue
                if gname == "pitch" and (qdesc["voiced"] != it.desc["voiced"]):
                    d += 0.5                          # pitched vs unpitched
                num += w * d
                den += w
            dist = num / den if den > 0 else 3.0
            res.append([it, dist])
        res.sort(key=lambda r: r[1])
        wc = W.get("_contour", 0.0)
        if wc > 0:                                    # second stage, bounded
            for r in res[:max(15, 3 * self.cfg.get("candidates", 5))]:
                dc = self.contour_distance(qdesc, r[0], W["_contours"])
                if dc is not None:
                    r[1] = (1 - wc) * r[1] + wc * dc
            res.sort(key=lambda r: r[1])
        return [(it, _m.exp(-SIM_SCALE * d), d) for it, d in res]

    # ---------------- retrieval ----------------
    def retrieve(self, qdesc, exclude_ids=(), exclude_roots=(), progress=0.0, k=None,
                 influences=()):
        """Ranked qualified candidates and a weighted-random choice.
        Returns (choice or None, ranked list of dicts, reason).
        v0.4.8 influences = [(desc, weight, ...)]: extra weighted queries
        (earlier phrases, trend).  A sound's similarity becomes the weighted
        mean over the last phrase (weight 1) and these; the duplicate guard
        keeps using the last phrase alone.  No influences = v0.4.7."""
        c = self.cfg
        k = k or c.get("candidates", 5)
        mode = c.get("sim_mode", "hybrid")
        weights = self.corpus_weights(progress)
        pool = [it for corp in ("A", "B", "C") if weights[corp] > 0 for it in self.items[corp]]
        if not pool:
            return None, [], "memory empty or all corpora disabled"
        recent = set(self.recall_history)
        last = self.recall_history[-1] if self.recall_history else None
        last_root = None
        if last and c.get("same_family_exclusion"):
            li = self.find(last)
            last_root = li.root if li else None
        pool = [it for it in pool if it.id not in exclude_ids and it.root not in exclude_roots
                and it.id not in recent and (last_root is None or it.root != last_root)
                and it.duration >= 0.3]
        if not pool:
            return None, [], "every stored sound is excluded (self / recent / cooldown)"
        ranked = self.similarity(qdesc, pool, mode)
        latest = dict((it.id, s) for it, s, _ in ranked)
        parts = dict((it.id, [s]) for it, s, _ in ranked)     # v0.4.9: score parts
        if influences:
            acc = dict((it.id, s) for it, s, _ in ranked)
            wsum = 1.0
            for inf in influences:
                d, w = inf[0], inf[1]
                for it, s, _ in self.similarity(d, pool, mode):
                    acc[it.id] += w * s
                    parts[it.id].append(w * s)
                wsum += w
            ranked = sorted([(it, acc[it.id] / wsum, dist) for it, _, dist in ranked],
                            key=lambda r: -r[1])
        minsim = c.get("min_similarity", 0.5)
        qual = []
        for it, sim, dist in ranked:
            if mode == "contrast":
                score = 1.0 - sim
                if score < minsim:
                    continue
            else:
                if sim < minsim or latest[it.id] >= DUPLICATE_SIM:
                    continue
                score = sim
            novelty = 1.0 / (1.0 + it.recalls)
            qual.append({"item": it, "sim": sim, "match": score, "sim_last": latest[it.id],
                         "parts": parts[it.id],
                         "score": score * (1.0 + 0.15 * novelty), "dist": dist})
        if not qual:
            best = ranked[0][1] if ranked else 0.0
            return None, [], ("no stored sound reaches the minimum similarity %.2f "
                              "(best %.2f)" % (minsim, best))
        qual.sort(key=lambda r: -r["score"])
        top = qual[:k]
        best = top[0]["score"]
        probs = [weights[r["item"].corpus] * math.exp((r["score"] - best) / 0.05) for r in top]
        tot = sum(probs)
        if tot <= 0:
            return None, top, "all qualified candidates come from corpora weighted 0"
        x = self.rng.random() * tot
        for r, pr in zip(top, probs):
            x -= pr
            if x <= 0:
                return r, top, "ok"
        return top[-1], top, "ok"

    def mark_recalled(self, item):
        item.recalls += 1
        self.recall_history.append(item.id)

    # ---------------- decision ----------------
    def choose_action(self, candidate, rt_candidate):
        """TRANSFORM / RECALL / RECALL_TRANSFORM, never forcing a poor match:
        recall actions are only possible with a qualified candidate."""
        c = self.cfg
        mode = c.get("response_mode", "hybrid")
        if mode == "transform" or not c.get("enabled", True):
            return "transform", "response mode Transform"
        if mode == "corpus_only":
            # v0.4.1: never a transformation, never the phrase itself
            return ("recall", "corpus only") if candidate else \
                   ("silence", "corpus only: no qualified match -> silence")
        if mode == "recall":
            return ("recall", "response mode Recall") if candidate else \
                   ("transform", "Recall: no qualified match -> transform fallback")
        if mode == "recall_transform":
            return ("recall_transform", "response mode Recall + Transform") if rt_candidate \
                else ("transform", "Recall + Transform not possible -> transform fallback")
        opts = [("transform", c.get("p_transform", 40.0))]
        if candidate:
            opts.append(("recall", c.get("p_recall", 30.0)))
        if rt_candidate:
            opts.append(("recall_transform", c.get("p_recall_transform", 30.0)))
        tot = sum(max(0.0, w) for _, w in opts)
        if tot <= 0:
            return "transform", "all action weights 0 -> transform"
        x = self.rng.random() * tot
        for a, w in opts:
            x -= max(0.0, w)
            if x <= 0:
                return a, "hybrid draw"
        return opts[-1][0], "hybrid draw"


def pick_recall_transform(cand, top, forced, max_generation):
    """Recall + Transform candidate: the RETRIEVED audio must itself qualify
    for a transformation (v0.2 classifier on that audio) and its result must
    stay within the generation limit.  The weighted choice is tried first."""
    for r in ([cand] if cand else []) + [r for r in top if r is not cand]:
        it = r["item"]
        if it.generation + 1 > max_generation or it.duration < 0.4:
            continue
        dec = decide(it.F, forced) if forced else it.info
        if dec["selected"] != "passthrough":
            return dict(r, decision=dec)
    return None


def analyse_item(audio, sr, forced=None):
    """v0.2 features + v0.2 decision + v0.3 descriptor for any audio."""
    F = extract_features(audio, sr)
    info = decide(F, forced)
    return F, info, memory_descriptor(F)


def energy_segments(env_db, hop_s, min_len, max_len):
    """Musically usable regions of a long recording: energy-aware activity
    (peak - 35 dB, and 10 dB above the file's floor unless that is within
    20 dB of the peak), gaps under 0.25 s
    bridged, overlong regions split at their quietest point, short ones
    dropped.  Returns [(start_s, end_s)]."""
    import numpy as np
    if len(env_db) == 0:
        return []
    floor = float(np.percentile(env_db, 10))
    peak = float(env_db.max())
    # 10 dB over the floor - but a file that sounds all the way through has
    # no silent floor, so the threshold never rises above peak - 20 dB
    thr = max(peak - 35.0, min(floor + 10.0, peak - 20.0))
    act = env_db > thr
    segs, start = [], None
    for i, v in enumerate(act):
        if v and start is None:
            start = i
        elif not v and start is not None:
            segs.append([start, i])
            start = None
    if start is not None:
        segs.append([start, len(act)])
    merged = []
    gap = int(0.25 / hop_s)
    for s0, s1 in segs:
        if merged and s0 - merged[-1][1] <= gap:
            merged[-1][1] = s1
        else:
            merged.append([s0, s1])
    out = []
    mx, mn = int(max_len / hop_s), int(min_len / hop_s)
    for s0, s1 in merged:
        while s1 - s0 > mx:
            lo, hi = s0 + mx // 2, s0 + mx
            cut = lo + int(np.argmin(env_db[lo:hi])) if hi > lo else s0 + mx
            out.append((s0, cut))
            s0 = cut
        out.append((s0, s1))
    pad = int(0.05 / hop_s)
    return [(max(0, a - pad) * hop_s, min(len(env_db), b + pad) * hop_s)
            for a, b in out if b - a >= mn]


AUDIO_EXTS = (".wav", ".wave", ".aif", ".aiff", ".aifc", ".flac", ".ogg", ".oga",
              ".mp3", ".w64", ".caf", ".rf64", ".au", ".snd")


def index_preloaded(folder, memory, cfg, progress=None, log=None):
    """Corpus C: read the performer's folder READ-ONLY, segment, analyse,
    index in RAM.  Nothing is written anywhere.  Returns (n_items, notes)."""
    import numpy as np
    import soundfile as sf
    log = log or (lambda *a, **k: None)
    notes = []
    if not folder or not os.path.isdir(folder):
        return 0, ["Corpus C folder not found: %s" % folder]
    files = []
    for dirpath, dirnames, names in os.walk(folder):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for n in sorted(names):
            if not n.startswith(".") and n.lower().endswith(AUDIO_EXTS):
                files.append(os.path.join(dirpath, n))
        if len(files) >= cfg["c_max_files"]:
            files = files[:cfg["c_max_files"]]
            notes.append("Corpus C: only the first %d files are used" % cfg["c_max_files"])
            break
    n_items = 0
    budget = 60.0 * cfg["max_ram_min"]
    for fi, path in enumerate(files):
        if n_items >= cfg["c_max_items"]:
            notes.append("Corpus C: segment limit %d reached" % cfg["c_max_items"])
            break
        if progress:
            progress("indexing preloaded corpus: file %d/%d, %d sounds" %
                     (fi + 1, len(files), n_items))
        try:
            info = sf.info(path)
            sr = int(info.samplerate)
            hop = max(1, int(round(0.01 * sr)))
            env = []
            for blk in sf.blocks(path, blocksize=hop * 200, dtype="float32", always_2d=True):
                m = blk.mean(axis=1)
                n = len(m) // hop
                if n:
                    r = np.sqrt(np.mean(m[:n * hop].reshape(n, hop) ** 2, axis=1) + 1e-20)
                    env.append(20 * np.log10(r + 1e-12))
            env = np.concatenate(env) if env else np.zeros(0)
            segs = energy_segments(env, hop / sr, cfg["c_min_item_s"], cfg["max_item_s"])
            if len(segs) > cfg["c_max_per_file"]:            # spread over the file
                idx = np.linspace(0, len(segs) - 1, cfg["c_max_per_file"]).round().astype(int)
                segs = [segs[i] for i in sorted(set(idx))]
            for s0, s1 in segs:
                if n_items >= cfg["c_max_items"]:
                    break
                start, stop = int(s0 * sr), int(s1 * sr)
                a, _ = sf.read(path, start=start, stop=stop, dtype="float32", always_2d=True)
                if len(a) < int(0.3 * sr) or float(np.max(np.abs(a))) < 1e-4:
                    continue
                F, dec, desc = analyse_item(a.astype(np.float64)[:, 0] if a.shape[1] == 1
                                            else a.astype(np.float64), sr)
                iid = memory.new_id("C")
                it = CorpusItem(iid, "C", a, sr, F, desc, dec, time.time(),
                                {"root": iid, "parent": None, "method": None, "generation": 0,
                                 "source": "%s @ %.2f-%.2f s" % (os.path.basename(path), s0, s1)})
                it.src = (path, start, stop)
                if memory.ram_seconds() + it.ram_seconds() > budget:
                    it.audio = None                       # on demand from the original
                memory.items["C"].append(it)
                n_items += 1
        except Exception as ex:                           # noqa: BLE001
            notes.append("Corpus C: skipped %s (%s)" % (os.path.basename(path), ex))
    log("Corpus C: %d sounds from %d files" % (n_items, len(files)))
    return n_items, notes


# ============================================================
# v0.4.0 POLYPHONIC SPATIAL PLAYBACK
#   Every answer becomes a VOICE: a pre-rendered stereo buffer (envelope,
#   equal-power placement and slow movement already applied off the audio
#   thread) plus a gain that the mixer ramps smoothly.  The output callback
#   only sums the active voices' slices, applies the per-voice gain ramps
#   and a peak limiter - no allocation-heavy DSP, no locks, no I/O.
#   Roles:  "fg"  foreground response to a phrase (transform / recall / R+T)
#           "sec" secondary voice: a related sound from memory entering later,
#                 elsewhere in space, quieter (polyphonic density)
#           "bg"  ambient background texture built from memory material
#   No decorrelation filters and no phase tricks: placement is equal-power
#   amplitude panning (mono sources) or mid/side width + equal-power balance
#   (stereo sources), so the mono fold-down never cancels.
# ============================================================
ROLE_NAMES = {"fg": "response", "sec": "layer", "bg": "background"}
ROLE_TARGET_DB = {"fg": -18.0, "sec": -24.0, "bg": -33.0}   # RMS of the active part
LIMIT_CEILING = 0.94           # output peak ceiling (linear)
KILL_FADE_S = 0.25             # fade when a voice is stolen or stopped
STOP_FADE_S = 0.15             # whole-mix fade at engine stop
PAN_LIMIT = 0.85               # |pan| <= 0.85: at most ~19 dB between channels,
                               #   never a voice in one speaker only


def raised_cosine(n, rising=True):
    import numpy as np
    if n <= 0:
        return np.zeros(0, np.float32)
    w = 0.5 - 0.5 * np.cos(np.pi * (np.arange(n) + 0.5) / n)
    return (w if rising else w[::-1]).astype(np.float32)


def attack_is_sharp(m, sr):
    """True when the sound starts with a transient: the level reaches 70 %
    of its early maximum within 15 ms (1-ms RMS frames)."""
    import numpy as np
    k = max(1, int(0.001 * sr))
    seg = m[:int(0.2 * sr)]
    nf = len(seg) // k
    if nf < 3:
        return True
    r = np.sqrt(np.mean(seg[:nf * k].reshape(nf, k) ** 2, axis=1))
    mx = float(r.max())
    if mx <= 1e-6:
        return False
    first = int(np.argmax(r >= 0.7 * mx))
    return first * k <= int(0.015 * sr)


def shape_envelope(a, sr, fade_in_s, fade_out_s, preserve_transients=True,
                   truncated=False):
    """Raised-cosine fade-in / fade-out on (n, ch) audio.
    - Fades scale with the length: fade-in <= 15 % and fade-out <= 30 % of
      the sound (never below 3 ms: always click-free).
    - A transient start keeps its attack: the fade-in shrinks to 1 ms.
    - A sound cut by Max_response_s gets a longer fade-out (>= 0.5 s)."""
    import numpy as np
    n = len(a)
    if n == 0:
        return a, 0.0, 0.0
    dur = n / float(sr)
    m = a.mean(axis=1) if a.ndim == 2 else a
    fi = min(fade_in_s, 0.15 * dur)
    if preserve_transients and attack_is_sharp(m, sr):
        fi = 0.001                       # anti-click only: the attack is kept
    else:
        fi = max(fi, 0.003)
    fo = max(fade_out_s, 0.5) if truncated else fade_out_s
    fo = max(min(fo, 0.3 * dur), 0.003)
    ni, no = min(n, int(fi * sr)), min(n, int(fo * sr))
    b = a.astype(np.float32, copy=True)
    if b.ndim == 1:
        b = b[:, None]
    b[:ni] *= raised_cosine(ni, True)[:, None]
    b[n - no:] *= raised_cosine(no, False)[:, None]
    return b, ni / float(sr), no / float(sr)


def active_rms(a):
    """RMS over the frames that actually sound (within 40 dB of the peak
    frame) - a loudness estimate that is not diluted by silences."""
    import numpy as np
    m = a.mean(axis=1) if a.ndim == 2 else a
    k = 1024
    nf = len(m) // k
    if nf < 1:
        return float(np.sqrt(np.mean(m ** 2) + 1e-20))
    r = np.sqrt(np.mean(m[:nf * k].reshape(nf, k) ** 2, axis=1) + 1e-20)
    act = r[r >= r.max() * 0.01]
    return float(np.sqrt(np.mean(act ** 2)))


BURST_HEADROOM_DB = 6.0       # v0.4.7: loudest 100 ms <= role target + this
VOICE_PEAK_CEILING = 0.9      # v0.4.7: per-voice peak after spatialisation


def loudness_profile(a, sr, combine="mean"):
    """v0.4.7: (integrated, burst) loudness in dB of (n,) or (n, ch) audio.
    K-weighted (BS.1770 pre-filter); channel powers summed (combine="sum",
    BS.1770 - the acoustic total of what two speakers play) or averaged
    ("mean" - for identical channels = the mono reading).  integrated =
    mean power of the 400 ms blocks (100 ms hop) within 20 dB of the loudest
    and above -70; burst = the loudest 100 ms window (25 ms hop)."""
    import numpy as np
    import scipy.signal
    x = np.asarray(a, np.float64)
    if x.ndim == 1:
        x = x[:, None]
    if len(x) == 0:
        return -120.0, -120.0
    for kind, fc, q, g in (("shelf", 1500.0, 1 / math.sqrt(2), 4.0), ("hp", 38.0, 0.5, 0.0)):
        b, a_ = _rbj(kind, sr, fc, q, g)
        x = scipy.signal.lfilter(b, a_, x, axis=0)
    p = np.sum(x * x, axis=1) if combine == "sum" else np.mean(x * x, axis=1)
    c = np.concatenate([[0.0], np.cumsum(p)])

    def windows(w, hop):
        k = max(1, int(w * sr))
        if len(p) <= k:
            return np.array([c[-1] / max(len(p), 1)])
        idx = np.arange(0, len(p) - k + 1, max(1, int(hop * sr)))
        return (c[idx + k] - c[idx]) / k
    blk = windows(0.4, 0.1)
    db = 10 * np.log10(blk + 1e-20)
    keep = (db >= db.max() - 20.0) & (db > -70.0)
    integ = float(np.mean(blk[keep])) if keep.any() else float(blk.max())
    burst = float(windows(0.1, 0.025).max())
    return -0.691 + 10 * math.log10(integ + 1e-20), -0.691 + 10 * math.log10(burst + 1e-20)


def voice_loudness(a, sr):
    """v0.4.7: loudness of a sound AS IT WILL BE PLAYED.  spatialize() keeps a
    real stereo source as stereo (both channels at full power: the channel
    powers ADD) and pans anything else as mono (equal power: the total stays
    the mono power).  Measuring it that way gives mono, dual-mono and
    decorrelated stereo sources the same loudness after placement."""
    import numpy as np
    x = np.asarray(a)
    if x.ndim == 2 and x.shape[1] >= 2 and is_real_stereo(x):
        return loudness_profile(x[:, :2], sr, "sum")
    if x.ndim == 2:
        x = x[:, 0] if x.shape[1] == 1 else x.mean(axis=1)
    return loudness_profile(x, sr, "mean")


def level_match(a, target_db, max_boost_db=12.0, peak_ceiling=0.9, sr=None, info=None):
    """Static gain towards a role's target, at most +max_boost_db, never above
    the peak ceiling.  Returns (audio, gain_db).
    v0.4.7 with sr: perceptual - K-weighted integrated loudness of the sound
    as it will be played (voice_loudness: real stereo = channel powers
    summed, anything else = mono; L and R never cancel), and the
    loudest 100 ms kept <= target + BURST_HEADROOM_DB.  `info` (a dict)
    receives the measurements and what limited the gain.
    Without sr: the v0.4.0 RMS rule (kept for callers that have no rate)."""
    import numpy as np
    pk = float(np.max(np.abs(a))) if len(a) else 0.0
    if sr is None:
        rms = active_rms(a)
        if rms < 1e-6:
            return a, 0.0
        cands = {"target": target_db - 20 * math.log10(rms)}
    else:
        integ, burst = voice_loudness(a, sr)
        if integ < -90.0:
            return a, 0.0
        cands = {"target": target_db - integ, "burst": target_db + BURST_HEADROOM_DB - burst}
        if info is not None:
            info.update(integrated=integ, burst=burst)
    cands["boost"] = max_boost_db
    if pk > 0:
        cands["peak"] = 20 * math.log10(peak_ceiling / pk)
    why = min(cands, key=cands.get)
    gdb = cands[why]
    if info is not None:
        info.update(gain_db=gdb, limited_by=why)
    return (a * 10 ** (gdb / 20.0)).astype(np.float32), gdb


def _rbj(kind, sr, fc, q, gain_db=0.0):
    """RBJ biquad (b, a) for the BS.1770 K-weighting pre-filter."""
    w = 2 * math.pi * fc / sr
    c, al = math.cos(w), math.sin(w) / (2 * q)
    if kind == "shelf":
        A = 10 ** (gain_db / 40.0)
        s = 2 * math.sqrt(A) * al
        b = [A * ((A + 1) + (A - 1) * c + s), -2 * A * ((A - 1) + (A + 1) * c),
             A * ((A + 1) + (A - 1) * c - s)]
        a = [(A + 1) - (A - 1) * c + s, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - s]
    else:
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a = [1 + al, -2 * c, 1 - al]
    return b, a


def active_loudness_db(a, sr, block_s=0.1, rel_gate_db=20.0):
    """v0.4.1: K-weighted loudness (BS.1770 pre-filter: +4 dB shelf at
    1.5 kHz, high-pass at 38 Hz) over the 100 ms blocks that sound (within
    20 dB of the loudest block, above -70).  Channel powers are summed as in
    BS.1770.  A 997 Hz sine at amplitude 1 reads -3.0."""
    import numpy as np
    import scipy.signal
    x = np.asarray(a, np.float64)
    if x.ndim == 1:
        x = x[:, None]
    if len(x) == 0:
        return -120.0
    for kind, fc, q, g in (("shelf", 1500.0, 1 / math.sqrt(2), 4.0), ("hp", 38.0, 0.5, 0.0)):
        b, a_ = _rbj(kind, sr, fc, q, g)
        x = scipy.signal.lfilter(b, a_, x, axis=0)
    k = max(1, int(block_s * sr))
    nb = len(x) // k
    if nb < 1:
        p = np.array([float(np.sum(np.mean(x ** 2, axis=0)))])
    else:
        p = np.sum(np.mean(x[:nb * k].reshape(nb, k, x.shape[1]) ** 2, axis=1), axis=1)
    db = -0.691 + 10 * np.log10(p + 1e-20)
    keep = (db >= db.max() - rel_gate_db) & (db > -70.0)
    if not keep.any():
        return float(db.max())
    return float(-0.691 + 10 * math.log10(float(np.mean(p[keep])) + 1e-20))


class LevelFollower:
    """v0.4.1: how loud the performer plays NOW relative to this session.
    offset = EMA(phrase loudness) - median(phrase loudness), clamped to
    +-range.  Relative on purpose: microphone dBFS and speaker dBFS are not
    comparable without calibration, but a change of playing level is."""

    def __init__(self, range_db=9.0, min_phrases=3, history=200, alpha=0.4):
        self.range = max(0.0, float(range_db))
        self.min_phrases = max(1, int(min_phrases))
        self.alpha = alpha
        self.hist = collections.deque(maxlen=history)
        self.ema = None
        self.offset = 0.0
        self.counted = 0
        self.excluded = 0

    def update(self, db, excluded=False):
        import numpy as np
        if excluded or db is None or not math.isfinite(db) or db < -90.0:
            self.excluded += 1
            return self.offset
        self.hist.append(float(db))
        self.counted += 1
        self.ema = db if self.ema is None else (1 - self.alpha) * self.ema + self.alpha * db
        if len(self.hist) >= self.min_phrases:
            self.offset = clamp(self.ema - float(np.median(self.hist)), -self.range, self.range)
        return self.offset


TAIL_GRACE_S = 1.5             # v0.4.5: a natural tail may exceed Max_response_s by this


def trim_quiet(a, sr, limit_s, fade_s=0.05, search_from=0.85):
    """v0.4.5: shorten (n, ch) or (n,) audio to at most limit_s seconds,
    cutting at its quietest 10 ms frame between search_from x limit and the
    limit (the latest frame within 3 dB of the quietest), with a raised-cosine fade over the last fade_s before the cut.
    Returns (audio, cut) - unchanged audio and False when it already fits."""
    import numpy as np
    n = len(a)
    lim = int(round(limit_s * sr))
    if n <= lim:
        return a, False
    hop = max(1, int(0.01 * sr))
    lo = int(search_from * lim)
    seg = np.asarray(a[lo:lim], np.float64)
    if seg.ndim == 2:
        seg = seg.mean(axis=1)
    nf = len(seg) // hop
    cut = lim
    if nf >= 2:
        e = np.mean(seg[:nf * hop].reshape(nf, hop) ** 2, axis=1)
        # the LATEST frame within 3 dB of the quietest one: a real dip is
        # still chosen, a sound without one is cut close to the limit
        quiet = np.where(e <= float(e.min()) * 10 ** 0.3 + 1e-20)[0]
        cut = lo + (int(quiet[-1]) + 1) * hop
    b = np.array(a[:cut], np.float32, copy=True)
    nfd = min(len(b), int(fade_s * sr))
    if nfd > 0:
        w = raised_cosine(nfd, False)
        if b.ndim == 2:
            b[len(b) - nfd:] *= w[:, None]
        else:
            b[len(b) - nfd:] *= w
    return b, True


def onset_starts(a, sr, within=0.4):
    """v0.4.5: sample positions where a sound may sensibly start an excerpt:
    0 plus the spectral-flux onsets in its first `within` fraction (each
    moved 10 ms earlier so the attack is kept)."""
    import numpy as np
    m = a.mean(axis=1) if a.ndim == 2 else a
    m = np.asarray(m, np.float64)
    hop_s = 0.01
    mag, _ = stft_mag(m, sr, 1024, int(round(hop_s * sr)))
    pk, _ = onset_detect(mag, hop_s)
    out = [0]
    for p in pk:
        s = max(0, int((p * hop_s - 0.01) * sr))
        if 0 < s < within * len(m):
            out.append(s)
    return sorted(set(out))


def is_real_stereo(a):
    """Two channels that are not the same signal (correlation < 0.995 or a
    level difference > 1 dB): their image is PRESERVED, not re-panned."""
    import numpy as np
    if a.ndim != 2 or a.shape[1] < 2:
        return False
    L, R = a[:, 0].astype(np.float64), a[:, 1].astype(np.float64)
    eL, eR = float(np.sum(L * L)), float(np.sum(R * R))
    if eL < 1e-12 or eR < 1e-12:
        return eL + eR > 1e-12
    c = float(np.sum(L * R) / math.sqrt(eL * eR))
    return c < 0.995 or abs(10 * math.log10(eL / eR)) > 1.0


def pan_curve(n, sr, center, movement, width, rng, slow=False):
    """Pan position per sample in [-1, 1]: a centre plus a slow, smooth
    drift (two incommensurate sines, 7-19 s and 23-41 s periods; 20-60 s for
    background), scaled by the stereo width.  Movement 0 = fixed."""
    import numpy as np
    t = np.arange(n) / float(sr)
    if movement <= 0:
        p = np.full(n, center)
    else:
        T1 = rng.uniform(20.0, 41.0) if slow else rng.uniform(7.0, 19.0)
        T2 = rng.uniform(43.0, 61.0) if slow else rng.uniform(23.0, 41.0)
        ph1, ph2 = rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi)
        depth = 0.45 * movement
        p = center + depth * (0.7 * np.sin(2 * np.pi * t / T1 + ph1) +
                              0.3 * np.sin(2 * np.pi * t / T2 + ph2))
    return np.clip(p * width, -PAN_LIMIT, PAN_LIMIT)


def spatialize(a, sr, center, movement, width, rng, slow=False):
    """(n, ch) -> (n, 2) stereo.
    Mono: equal-power amplitude pan along pan_curve (L = cos, R = sin of
      (p + 1) pi / 4): constant power at every position, no decorrelation.
    Stereo: the original image is kept; its side signal is scaled by the
      width and the whole image is moved with an equal-power balance (half
      the movement of a mono source).  Mono fold-down: the L/R sum of a
      panned mono source varies by at most 3 dB with position and never
      cancels (no polarity or delay differences are introduced)."""
    import numpy as np
    n = len(a)
    if is_real_stereo(a):
        L, R = a[:, 0], a[:, 1]
        M, S = 0.5 * (L + R), 0.5 * (L - R) * width
        p = pan_curve(n, sr, center * 0.5, movement * 0.5, width, rng, slow)
        th = (p + 1.0) * np.pi / 4.0
        gl, gr = np.cos(th) * math.sqrt(2.0), np.sin(th) * math.sqrt(2.0)
        out = np.stack([(M + S) * gl, (M - S) * gr], axis=1)
    else:
        m = a[:, 0] if a.ndim == 2 else a
        p = pan_curve(n, sr, center, movement, width, rng, slow)
        th = (p + 1.0) * np.pi / 4.0
        out = np.stack([m * np.cos(th), m * np.sin(th)], axis=1)
    return np.ascontiguousarray(out, np.float32)


class Voice:
    """One sounding layer.  buf is final stereo audio; the mixer only reads
    it.  gain/target are linear; the mixer moves gain towards target by at
    most `rate` per second (smooth ducking, stealing and stop fades)."""
    _next = [1]

    def __init__(self, buf, role, name, center, wait=0, gain=1.0, rate=2.0):
        self.id = Voice._next[0]
        Voice._next[0] += 1
        self.buf = buf
        self.n = len(buf)
        self.role = role
        self.name = name
        self.center = center
        self.pos = 0
        self.wait = int(wait)        # frames of silence before it enters
        self.gain = gain
        self.target = gain
        self.rate = rate             # gain units per second
        self.kill = False
        self.done = False
        self.t_created = time.time()
        self.item_id = None          # v0.4.6: memory item shown on the map

    def remaining_s(self, sr):
        return (self.n - self.pos + self.wait) / float(sr)

    def fade_out(self, seconds):
        self.rate = 1.0 / max(seconds, 0.01)
        self.target = 0.0
        self.kill = True


class Mixer:
    """Polyphonic stereo mixer.  render() runs inside the PortAudio output
    callback: it sums voice slices with per-block linear gain ramps and a
    peak limiter (instant attack, ~0.2 s release, soft safety clip above the
    ceiling).  Voices are added / removed by replacing the list object
    (atomic under the GIL) from ONE worker thread at a time (add_lock)."""

    def __init__(self, sr, channels=2, max_frames=8192):
        import numpy as np
        self.np = np
        self.sr = sr
        self.ch = channels
        self.voices = []
        self.add_lock = threading.Lock()
        self.mix = np.zeros((max_frames, 2), np.float32)
        self.lim_gain = 1.0
        self.max_reduction_db = 0.0
        self.peak_out = 0.0
        self.max_active = 0
        self.master_target = 1.0
        self.master = 1.0

    # ---- worker side ----
    def add(self, v):
        with self.add_lock:
            self.voices = [x for x in self.voices if not x.done] + [v]

    def sweep(self):
        with self.add_lock:
            self.voices = [x for x in self.voices if not x.done]

    def active(self, role=None):
        return [v for v in self.voices if not v.done and not v.kill and
                (role is None or v.role == role)]

    def fade_all(self, seconds):
        self.master_target = 0.0
        self.master_rate = 1.0 / max(seconds, 0.01)

    # ---- audio-thread side ----
    def render(self, frames):
        np = self.np
        mix = self.mix[:frames]
        mix.fill(0.0)
        blk = frames / float(self.sr)
        ramp = (np.arange(1, frames + 1, dtype=np.float32) / frames)
        nact = 0
        for v in self.voices:
            if v.done:
                continue
            off = 0
            if v.wait > 0:
                if v.wait >= frames:
                    v.wait -= frames
                    continue
                off, v.wait = v.wait, 0
            n = min(frames - off, v.n - v.pos)
            if n <= 0:
                v.done = True
                continue
            g0 = v.gain
            step = v.rate * blk
            g1 = g0 + max(-step, min(step, v.target - g0))
            seg = v.buf[v.pos:v.pos + n]
            if g0 == g1:
                if g0 != 1.0:
                    mix[off:off + n] += seg * g0
                else:
                    mix[off:off + n] += seg
            else:
                gr = g0 + (g1 - g0) * ramp[:n]
                mix[off:off + n] += seg * gr[:, None]
            v.gain = g1
            v.pos += n
            if not v.kill:
                nact += 1                     # voices fading out are not counted
            if v.pos >= v.n or (v.kill and g1 <= 1e-4):
                v.done = True
        if nact > self.max_active:
            self.max_active = nact
        # master fade (engine stop): smooth, never a cut
        if self.master != self.master_target or self.master != 1.0:
            m0 = self.master
            step = getattr(self, "master_rate", 4.0) * blk
            m1 = m0 + max(-step, min(step, self.master_target - m0))
            mix *= (m0 + (m1 - m0) * ramp)[:, None]
            self.master = m1
        # peak limiter
        pk = float(np.max(np.abs(mix))) if frames else 0.0
        want = 1.0 if pk <= LIMIT_CEILING else LIMIT_CEILING / pk
        g0 = self.lim_gain
        g1 = want if want < g0 else g0 + (want - g0) * 0.05
        if g0 != 1.0 or g1 != 1.0:
            if want < g0:                       # instant attack for this block
                mix *= want
            else:
                mix *= (g0 + (g1 - g0) * ramp)[:, None]
        self.lim_gain = g1
        if g1 < 1.0:
            self.max_reduction_db = max(self.max_reduction_db, -20 * math.log10(max(g1, 1e-6)))
        np.clip(mix, -0.999, 0.999, out=mix)    # safety only (never reached in tests)
        pk2 = float(np.max(np.abs(mix))) if frames else 0.0
        if pk2 > self.peak_out:
            self.peak_out = pk2
        return mix


class SpaceAllocator:
    """Chooses where a new voice sits: away from the voices already sounding
    (largest gap among candidate positions), foreground answers alternate
    sides around the performer's centre, background voices spread wide.
    pan_variation 0 = deterministic alternation, 1 = free random choice."""

    def __init__(self, rng, width, variation):
        self.rng = rng
        self.width = width
        self.var = variation
        self.side = 1.0

    def place(self, role, others):
        rng = self.rng
        if role == "fg":
            self.side = -self.side
            base = self.side * (0.35 + 0.3 * rng.random())
        elif role == "sec":
            base = rng.uniform(-0.9, 0.9)
        else:
            base = rng.uniform(-0.6, 0.6)
        cands = [base] + [rng.uniform(-0.95, 0.95) for _ in range(8)]
        occ = [v.center for v in others]

        def gap(c):
            return min([abs(c - o) for o in occ] or [2.0])
        best = max(cands, key=gap)
        mix = self.var if occ else self.var * 0.5
        c = (1 - mix) * base + mix * best
        if occ and gap(c) < 0.25:              # never on top of another voice
            c = best
        return max(-0.95, min(0.95, c))


def build_texture(sources, sr, seconds, width, movement, rng, fade_s=3.0):
    """Ambient background from memory material: overlapping raised-cosine
    grains (1-6 s, 50 % overlap) taken from different places of 1-3 source
    sounds, each grain with its own small gain change and its own place in
    space, gently low-passed (one-pole, 4 kHz) so it sits behind the
    performer.  sources: list of (mono float array, sr).  Returns (n, 2)."""
    import numpy as np
    import scipy.signal
    n = int(seconds * sr)
    out = np.zeros((n, 2), np.float32)
    mats = []
    for a, s in sources:
        if s != sr:
            g = math.gcd(int(s), int(sr))
            a = scipy.signal.resample_poly(a, int(sr) // g, int(s) // g)
        a = np.asarray(a, np.float32)
        if len(a) >= int(0.6 * sr):
            mats.append(a)
    if not mats:
        return None
    pos = 0
    k = 0
    srch = int(0.025 * sr)                 # alignment search +-25 ms
    probe = int(0.12 * sr)                 # compared over 120 ms of overlap
    while pos < n:
        src = mats[k % len(mats)]
        glen = int(min(max(0.6 * len(src), 1.0 * sr), 6.0 * sr, len(src)))
        st = rng.randint(0, max(0, len(src) - glen))
        if pos > 0:
            # WSOLA-style: shift the grain (+-25 ms) so that its start lines
            # up with what is already sounding -> overlapping grains of tonal
            # material reinforce instead of cancelling
            ref = out[pos:pos + probe].sum(axis=1)
            lo, hi = max(0, st - srch), min(len(src) - glen, st + srch)
            if hi > lo and len(ref) == probe and float(np.dot(ref, ref)) > 1e-12 \
                    and hi + probe <= len(src):
                c = np.correlate(src[lo:hi + probe], ref, mode="valid")
                st = lo + int(np.argmax(c[:hi - lo + 1]))
        g = src[st:st + glen].copy()
        w = np.hanning(glen + 2)[1:-1].astype(np.float32)
        g *= w * (10 ** (rng.uniform(-2.0, 2.0) / 20.0))
        c = rng.uniform(-0.8, 0.8)
        st_g = spatialize(g[:, None], sr, c, movement, width, rng, slow=True)
        end = min(n, pos + glen)
        out[pos:end] += st_g[:end - pos]
        pos += max(glen // 2, int(0.3 * sr))
        k += 1
    b, a_ = scipy.signal.butter(1, min(0.99, 4000.0 / (sr / 2.0)))
    out = scipy.signal.lfilter(b, a_, out, axis=0).astype(np.float32)
    fn = min(int(fade_s * sr), n // 3)
    out[:fn] *= raised_cosine(fn, True)[:, None]
    out[n - fn:] *= raised_cosine(fn, False)[:, None]
    return out


# ============================================================
# v0.4.6 MEMORY MAP  (graph.tsv for the Praat Demo window)
# ============================================================
GRAPH_FILE = "graph.tsv"
GRAPH_BG = (0.97, 0.97, 0.97)
CLASS_RGB = {"paulstretch": (0.20, 0.40, 0.80), "markov": (0.55, 0.60, 0.20),
             "mds": (0.90, 0.55, 0.15), "spiral": (0.75, 0.25, 0.65),
             "speeddev": (0.15, 0.60, 0.55), "groove": (0.80, 0.25, 0.25),
             "passthrough": (0.50, 0.50, 0.55)}
CORPUS_RGB = {"A": (0.20, 0.40, 0.80), "B": (0.85, 0.45, 0.15), "C": (0.45, 0.45, 0.50),
              "P": (0.62, 0.70, 0.88)}
ACTION_RGB = {"recall": (0.45, 0.20, 0.60), "recall_transform": (0.80, 0.30, 0.65),
              "transform": (0.15, 0.62, 0.55), "influence": (0.66, 0.58, 0.80)}
REGION_RGB = {"C": (0.92, 0.92, 0.94), "P": (0.95, 0.95, 0.97)}


def _blend(rgb, amount, to=GRAPH_BG):
    """rgb moved `amount` (0..1) towards the background."""
    return tuple(c + (t - c) * clamp(amount, 0.0, 1.0) for c, t in zip(rgb, to))


def graph_similarity(qdescs, pdescs, scales, mode="hybrid"):
    """Vectorised group-weighted similarity, Q x N: the same z-normalised
    group distance as SonicMemory.similarity (incl. the pitched/unpitched
    penalty), WITHOUT its second-stage contour refinement.  For the map."""
    import numpy as np
    if mode == "pitch":
        # v0.4.9: as SonicMemory.similarity - an unpitched query is ranked
        # with hybrid weights (pitch mode cannot compare it)
        S = graph_similarity(qdescs, pdescs, scales, "_pitch_only")
        unv = [i for i, d in enumerate(qdescs) if not d["voiced"]]
        if unv:
            S[unv] = graph_similarity([qdescs[i] for i in unv], pdescs, scales, "hybrid")
        return S
    if mode == "_pitch_only":
        mode = "pitch"
    elif mode not in SIM_MODES or mode == "contrast":
        mode = "hybrid"
    W = SIM_MODES[mode]
    Q, N = len(qdescs), len(pdescs)
    num = np.zeros((Q, N))
    den = np.zeros((Q, N))
    for g, w in W.items():
        if g.startswith("_") or w <= 0:
            continue
        A = np.vstack([d["groups"][g] for d in qdescs])
        B = np.vstack([d["groups"][g] for d in pdescs])
        Z = (A[:, None, :] - B[None, :, :]) / scales[g][None, None, :]
        ok = ~np.isnan(Z)
        cnt = ok.sum(axis=2)
        dist = np.sqrt(np.where(ok, Z * Z, 0.0).sum(axis=2) / np.maximum(cnt, 1))
        if g == "pitch":
            vq = np.array([bool(d["voiced"]) for d in qdescs])
            vp = np.array([bool(d["voiced"]) for d in pdescs])
            dist = dist + 0.5 * (vq[:, None] != vp[None, :])
        has = cnt > 0
        num += np.where(has, w * dist, 0.0)
        den += np.where(has, w, 0.0)
    d = np.where(den > 0, num / np.maximum(den, 1e-12), 3.0)
    return np.exp(-SIM_SCALE * d)


class MemoryGraph:
    """The data behind the memory map.  Owned by the engine's brain thread
    (like SonicMemory); build() returns plain rows that the main thread
    writes to graph.tsv."""
    MAX_GHOSTS = 40

    def __init__(self, memory, mode="hybrid", min_sim=0.45, k=3, max_sim_edges=220,
                 max_actions=40):
        self.mem = memory
        self.mode = "hybrid" if mode == "contrast" else mode
        self.thr = 0.45 if mode == "contrast" else float(min_sim)
        self.k = k
        self.max_sim_edges = max_sim_edges
        self.nb = {}                                     # id -> [(id, sim)]
        self.ghosts = collections.OrderedDict()          # phrase id -> (t, gesture)
        self.actions = collections.deque(maxlen=max_actions)
        self.live = None

    # ---- updates ----
    def link(self, items, pool=None, chunk=64):
        import numpy as np
        pool = [p for p in (self.mem.all_items() if pool is None else pool)
                if p is not None and p.desc is not None]
        items = [it for it in items if it is not None and it.desc is not None]
        if not items or len(pool) < 2:
            return
        sc = self.mem._scales(pool, items[0].desc)
        pd = [p.desc for p in pool]
        for c0 in range(0, len(items), chunk):
            part = items[c0:c0 + chunk]
            S = graph_similarity([it.desc for it in part], pd, sc, self.mode)
            for r, it in enumerate(part):
                out = []
                for j in np.argsort(-S[r]):
                    if pool[j].id == it.id:
                        continue
                    if S[r, j] < self.thr or len(out) >= self.k:
                        break
                    out.append((pool[j].id, float(S[r, j])))
                self.nb[it.id] = out

    def phrase(self, pid, t, gesture):
        self.ghosts[pid] = (t, gesture)
        while len(self.ghosts) > self.MAX_GHOSTS:
            self.ghosts.popitem(last=False)
        self.live = pid

    def action(self, src, dst, kind, match=None):
        if src and dst and kind in ACTION_RGB:
            self.actions.append((src, dst, kind, match))

    # ---- layout ----
    def build(self):
        """(rows, nodes): rows = region / edge / live lines for graph.tsv,
        nodes = [(id, x, size, rgb)] (the main thread adds the 'sounding' flag).
        x and size are in 0..1 units of the drawing width."""
        mem = self.mem
        cs = sorted(mem.items["C"], key=lambda it: it.id)
        perf = [(it.t, it.id, it.corpus, it) for it in mem.items["A"] + mem.items["B"]]
        stored = {it.id for it in mem.items["A"]}
        perf += [(t, pid, "P", None) for pid, (t, g) in self.ghosts.items() if pid not in stored]
        perf.sort(key=lambda r: (r[0], r[1]))
        if cs and perf:
            regions = [("C", 0.0, 0.28), ("P", 0.32, 1.0)]
        elif cs:
            regions = [("C", 0.0, 1.0)]
        else:
            regions = [("P", 0.0, 1.0)]
        reg = dict((k, (a, b)) for k, a, b in regions)
        pos, nodes, gest = {}, [], {}

        def place(seq, key):
            a, b = reg[key]
            n = len(seq)
            step = (b - a) / max(n, 1)
            for i, (nid, corpus, it, g) in enumerate(seq):
                x = a + step * (i + 0.5)
                dur = it.duration if it is not None else 1.0
                size = clamp(0.42 * step, 0.0012, 0.0085) * (0.75 + 0.05 * min(dur, 5.0))
                pos[nid] = x
                gest[nid] = g
                nodes.append((nid, x, size, CORPUS_RGB[corpus]))
        if "C" in reg:
            place([(it.id, "C", it, it.gesture) for it in cs], "C")
        if "P" in reg:
            place([(nid, corp, it, it.gesture if it is not None else self.ghosts[nid][1])
                   for _, nid, corp, it in perf], "P")
        rows = []
        names = {"C": "Preloaded C (%d)" % len(cs),
                 "P": "Performance - phrases A, answers B (%d)" % len(perf)}
        for k, a, b in regions:
            rows.append(("region", a, b, 0, 0.0, REGION_RGB[k], names[k]))
        # upper arcs: similarity, newest sounds first, capped, weakest drawn first
        order = [nid for _, nid, _, _ in reversed(perf)] + [it.id for it in cs]
        seen, sims = set(), []
        for nid in order:
            for oid, s in self.nb.get(nid, ()):
                key = tuple(sorted((nid, oid)))
                if oid in pos and nid in pos and key not in seen:
                    seen.add(key)
                    sims.append((s, nid, oid))
            if len(sims) >= self.max_sim_edges:
                break
        for s, nid, oid in sorted(sims[:self.max_sim_edges]):
            st = clamp((s - self.thr) / max(1.0 - self.thr, 1e-6), 0.0, 1.0)
            rgb = _blend(CLASS_RGB.get(gest.get(nid), CLASS_RGB["passthrough"]), 0.7 * (1 - st))
            rows.append(("edge", pos[nid], pos[oid], 1, 1.0 + (st > 0.6), rgb, nid + ">" + oid))
        # lower arcs: actions, oldest first and palest
        acts = [a for a in self.actions if a[0] in pos and a[1] in pos]
        n = len(acts)
        for i, (a, b, kind, match) in enumerate(acts):
            age = (n - 1 - i) / max(n - 1, 1)
            w = 3.0 if match is None else 1.5 + 4.5 * clamp(match, 0.0, 1.0)
            if kind == "influence":
                w = 1.0 + 4.0 * clamp(match, 0.0, 1.0)
            rows.append(("edge", pos[a], pos[b], -1, round(w, 1),
                         _blend(ACTION_RGB[kind], 0.72 * age), kind))
        if self.live in pos:
            rows.append(("live", pos[self.live], 0.0, 0, 0.0, (0.80, 0.20, 0.20), self.live))
        return rows, nodes


def graph_tsv(rows, nodes, sounding=()):
    """graph.tsv text: kind x1 x2 side width r g b label (one header line)."""
    out = ["kind\tx1\tx2\tside\twidth\tr\tg\tb\tlabel"]

    def fmt(k, a, b, side, w, rgb, label):
        return "%s\t%.5f\t%.5f\t%d\t%.2f\t%.3f\t%.3f\t%.3f\t%s" % (
            k, a, b, side, w, rgb[0], rgb[1], rgb[2], (label or "-").replace("\t", " "))
    for r in rows:
        if r[0] != "live":
            out.append(fmt(*r))
    for nid, x, size, rgb in nodes:
        out.append(fmt("node", x, size, 1 if nid in sounding else 0, 0.0, rgb, nid))
    for r in rows:
        if r[0] == "live":
            out.append(fmt(*r))
    return "\n".join(out) + "\n"


# ============================================================
# v0.2.0 CONTINUOUS ENGINE  (command: serve)
# ============================================================
# Ownership (one owner per resource; no shared lock is held during
# analysis or rendering):
#   PortAudio input callback  copies each block into in_q (bounded; never
#                             blocks; a full queue is counted as an overrun)
#   DETECT thread   owns the PhraseDetector, the input ring and the leakage
#                   estimator; finalises phrases, analyses them with the
#                   unchanged v0.1.3 scoring, writes job files -> render_q
#   RENDER thread   owns the ONE headless Praat child process -> play_q
#   PLAY thread     owns what the output stream plays (one answer at a time)
#   PortAudio output callback  copies the current answer to the device and
#                   records what was played (for the leakage estimate)
#   MAIN thread     status file, stop request, Praat heartbeat, limits,
#                   ordered shutdown
STALE_RESPONSE_S = 90.0        # an answer older than this is dropped (logged)
RENDER_TIMEOUT_S = 180.0       # a Praat render taking longer is killed
HEARTBEAT_TIMEOUT_S = 20.0     # Praat GUI gone for this long -> engine stops
LEAK_MAX_LAG_S = 0.5           # speaker->mic search window
LEAK_DISCARD_RHO2 = 0.75       # >= 75 % of a phrase explained by playback
LEAK_Z_MIN = 12.0              # PHAT peak prominence for a plausible acoustic path
LEAK_LAG_MIN_S = 0.002         # path delays outside [2 ms, max - 5 ms] are not
LEAK_LAG_EDGE_S = 0.005        #   trusted (edge peaks = periodic ambiguity)
LEAK_DOMINANCE = 1.5           # main PHAT peak / next peak (periodic -> ~1)
LEAK_GAIN_RHO = 0.7            # gain updated only when the input is mostly leakage
LEAK_LAG_TOL_S = 0.003         # v0.4.0: phrase check accepts +-3 ms of clock drift
# AudioTools_CallResponse.praat form, one value per field in form order.
# Render mode (env AUDIOTOOLS_CR_JOB) ignores the values, but "praat --run"
# requires one argument per field.  KEEP IN SYNC WITH THE PRAAT FORM.
RENDER_FORM_ARGS = ["Custom (form and dialogs)",                    # v0.4.2 Preset
                    "Selected Sound(s)", "Automatic (gesture classifier)", "4",
                    "default", "default", "9", "0.5", "0.6", "12",
                    "0", "Transform only (v0.2)", "-",          # v0.3.0 memory fields
                    "0", "0",                                   # Memory / Playback settings
                    "0", "0"]
DISPLAY_NAMES = {
    "paulstretch": "Paulstretch", "markov": "Markov Soundscape Weaver",
    "mds": "MDS Space Navigator", "spiral": "Spiral Pitch Dance",
    "speeddev": "8-Channel Speed Deviations", "groove": "Percussive Groove Creator",
    "passthrough": "Original phrase",
}


def db_of(x):
    import numpy as np
    e = float(np.sqrt(np.mean(np.square(x, dtype=np.float64)) + 1e-20)) if len(x) else 0.0
    return 20 * math.log10(e + 1e-12)


class BoundedJobQueue:
    """FIFO with a hard limit and an explicit overflow policy.
    drop_oldest: the oldest UNSTARTED job is removed to make room.
    drop_newest: the incoming job is rejected.
    Dropped jobs are handed to on_drop (outside the lock) - never silent."""

    def __init__(self, name, maxlen, policy, on_drop):
        self.name, self.maxlen = name, max(1, int(maxlen))
        self.policy = policy if policy in ("drop_oldest", "drop_newest") else "drop_oldest"
        self.on_drop = on_drop
        self._d = collections.deque()
        self._cv = threading.Condition()
        self.closed = False

    def put(self, job):
        dropped = None
        with self._cv:
            if len(self._d) >= self.maxlen:
                if self.policy == "drop_newest":
                    dropped = job
                else:
                    dropped = self._d.popleft()
                    self._d.append(job)
            else:
                self._d.append(job)
            self._cv.notify()
        if dropped is not None:
            self.on_drop(dropped, "%s full (%d, %s)" % (self.name, self.maxlen, self.policy))
        return dropped is not job

    def get(self, timeout=0.2):
        with self._cv:
            if not self._d and not self.closed:
                self._cv.wait(timeout)
            if self._d:
                return self._d.popleft()
            return None

    def drain(self):
        with self._cv:
            out = list(self._d)
            self._d.clear()
            return out

    def close(self):
        with self._cv:
            self.closed = True
            self._cv.notify_all()

    def __len__(self):
        return len(self._d)


class Ring:
    """Mono float32 history with the wall-clock time of its newest sample.
    segment(t_end, dur) returns the samples that ended at wall time t_end;
    samples outside the history come back as zeros (= silence)."""

    def __init__(self, sr, seconds):
        import numpy as np
        self.np = np
        self.sr = sr
        self.n = int(sr * seconds)
        self.buf = np.zeros(self.n, np.float32)
        self.w = 0
        self.t_last = None
        self.lock = threading.Lock()

    def append(self, mono, t_end):
        m = len(mono)
        with self.lock:
            if m >= self.n:
                mono, m = mono[-self.n:], self.n
            i = self.w % self.n
            k = min(m, self.n - i)
            self.buf[i:i + k] = mono[:k]
            if m > k:
                self.buf[:m - k] = mono[k:]
            self.w += m
            self.t_last = t_end

    def segment(self, t_end, dur):
        np = self.np
        L = int(round(dur * self.sr))
        out = np.zeros(max(L, 0), np.float32)
        with self.lock:
            if self.t_last is None or L <= 0:
                return out
            end = self.w - int(round((self.t_last - t_end) * self.sr))
            start = end - L
            lo, hi = max(start, self.w - self.n, 0), min(end, self.w)
            if hi > lo:
                idx = np.arange(lo, hi) % self.n
                out[lo - start:hi - start] = self.buf[idx]
        return out


def leak_fit(x, y, max_lag_n):
    """Least-squares fit y[n] ~ a * x[n + max_lag_n - lag], lag in 0..max_lag_n
    (x must hold len(y) + max_lag_n samples ending with y).  Returns
    (gain a, correlation rho at the best lag, lag in samples).  rho^2 is the
    fraction of y's energy explained by the delayed, scaled playback."""
    import numpy as np
    x = np.asarray(x, np.float64)
    y = np.asarray(y, np.float64)
    Ly = len(y)
    if Ly == 0 or len(x) < Ly + max_lag_n:
        return 0.0, 0.0, 0
    ey = float(np.dot(y, y))
    if ey <= 1e-12:
        return 0.0, 0.0, 0
    N = 1 << int(math.ceil(math.log2(len(x) + Ly)))
    r = np.fft.irfft(np.fft.rfft(x, N) * np.conj(np.fft.rfft(y, N)), N)[:max_lag_n + 1]
    cs = np.concatenate([[0.0], np.cumsum(x * x)])
    ks = np.arange(max_lag_n + 1)
    ex = cs[ks + Ly] - cs[ks]
    rho = r / np.sqrt(np.maximum(ex, 1e-20) * ey)
    rho[ex <= 1e-12] = 0.0
    b = int(np.argmax(np.abs(rho)))
    a = float(r[b] / ex[b]) if ex[b] > 1e-12 else 0.0
    return a, float(rho[b]), max_lag_n - b


def leak_fit_stereo(xl, xr, y, max_lag_n, lag):
    """v0.4.0: fraction of y's energy explained by a * L + b * R at a given
    delay (two-regressor least squares).  With independent voices panned
    to different places the microphone hears L and R with different gains,
    which the mono (L + R) / 2 fit underestimates."""
    import numpy as np
    y = np.asarray(y, np.float64)
    Ly = len(y)
    b0 = max_lag_n - lag
    if Ly == 0 or b0 < 0 or len(xl) < b0 + Ly or len(xr) < b0 + Ly:
        return 0.0
    X = np.stack([np.asarray(xl[b0:b0 + Ly], np.float64),
                  np.asarray(xr[b0:b0 + Ly], np.float64)], axis=1)
    ey = float(np.dot(y, y))
    if ey <= 1e-12 or float(np.sum(X * X)) <= 1e-12:
        return 0.0
    coef, _, _, _ = np.linalg.lstsq(X, y, rcond=None)
    res = y - X @ coef
    return max(0.0, 1.0 - float(np.dot(res, res)) / ey)


def leak_path(x, y, max_lag_n, sr):
    """Robust speaker->mic path test.  The DELAY is found with a PHAT-weighted
    (phase-only) cross-correlation: a real acoustic path gives one sharp peak,
    while a performer who merely plays the same pitch as the answer does not
    (plain correlation of two periodic signals peaks at many lags).  The gain
    and rho are then the least-squares values at that delay.
    Returns dict(lag samples, z = peak prominence, a = gain, rho, plausible)."""
    import numpy as np
    x = np.asarray(x, np.float64)
    y = np.asarray(y, np.float64)
    Ly = len(y)
    res = {"lag": 0, "z": 0.0, "dom": 0.0, "a": 0.0, "rho": 0.0, "plausible": False}
    if Ly == 0 or len(x) < Ly + max_lag_n or float(np.dot(y, y)) <= 1e-12:
        return res
    N = 1 << int(math.ceil(math.log2(len(x) + Ly)))
    X = np.fft.rfft(x, N)
    Y = np.fft.rfft(y, N)
    G = X * np.conj(Y)
    r = np.fft.irfft(G / (np.abs(G) + 1e-12), N)[:max_lag_n + 1]
    b = int(np.argmax(r))
    guard = max(1, int(0.001 * sr))
    mask = np.ones(len(r), bool)
    mask[max(0, b - guard):b + guard + 1] = False
    z = float((r[b] - r[mask].mean()) / (r[mask].std() + 1e-12))
    mask2 = np.ones(len(r), bool)
    mask2[max(0, b - 2 * guard):b + 2 * guard + 1] = False
    second = float(r[mask2].max()) if mask2.any() else 0.0
    dom = float(r[b] / second) if second > 1e-12 else 99.0
    lag = max_lag_n - b
    seg = x[b:b + Ly]
    ex = float(np.dot(seg, seg))
    ey = float(np.dot(y, y))
    rt = float(np.dot(seg, y))
    res.update(lag=lag, z=z, dom=dom, a=(rt / ex if ex > 1e-12 else 0.0),
               rho=(rt / math.sqrt(ex * ey) if ex > 1e-12 else 0.0))
    res["plausible"] = (z >= LEAK_Z_MIN and dom >= LEAK_DOMINANCE and
                        int(LEAK_LAG_MIN_S * sr) <= lag <= max_lag_n - int(LEAK_LAG_EDGE_S * sr))
    return res


def praat_candidates(hint):
    c = []
    if hint and hint.lower() not in ("", "none", "auto"):
        c.append(hint)
    if os.environ.get("PRAAT_EXE"):
        c.append(os.environ["PRAAT_EXE"])
    for n in ("praat", "Praat", "praat_nogui", "praat_barren"):
        w = shutil.which(n)
        if w:
            c.append(w)
    home = os.path.expanduser("~")
    if sys.platform.startswith("win"):
        for base in (os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", ""),
                     os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs")):
            if base:
                c.append(os.path.join(base, "Praat", "Praat.exe"))
                c.append(os.path.join(base, "Praat.exe"))
        for d in ("Desktop", "Downloads", "Documents"):
            root = os.path.join(home, d)
            c.append(os.path.join(root, "Praat.exe"))
            try:
                for sub in os.listdir(root):
                    p = os.path.join(root, sub)
                    if os.path.isdir(p):
                        c.append(os.path.join(p, "Praat.exe"))
                        c.append(os.path.join(p, "audio", "Praat.exe"))
            except OSError:
                pass
    elif sys.platform == "darwin":
        c += ["/Applications/Praat.app/Contents/MacOS/Praat",
              os.path.join(home, "Applications/Praat.app/Contents/MacOS/Praat")]
    else:
        c += ["/usr/bin/praat", "/usr/local/bin/praat", os.path.join(home, "bin/praat")]
    seen, out = set(), []
    for x in c:
        if x and x not in seen:
            seen.add(x)
            out.append(x)
    return out


class PraatRenderer:
    """Runs AudioTools_CallResponse.praat headless in render mode, one job at
    a time.  The child is a tracked Popen: killed on timeout and on stop."""

    def __init__(self, hint, script, session, log):
        self.script, self.session, self.log = script, session, log
        self.exe, self.flags, self.version, self.error = "", [], 0, ""
        self.proc = None
        self.lock = threading.Lock()
        self.hint = hint

    @staticmethod
    def _resolve(path):
        path = os.path.expanduser(path or "")
        if os.path.isdir(path):
            for exe in ("Praat.exe", "praat.exe", "Praat", "praat", "praat_nogui",
                        "praat_barren", "Praat.app/Contents/MacOS/Praat"):
                cand = os.path.join(path, exe)
                if os.path.isfile(cand):
                    return cand
            return ""
        return path if os.path.isfile(path) else (shutil.which(path) or "")

    def _popen_kwargs(self):
        kw = {}
        if sys.platform.startswith("win"):
            kw["creationflags"] = 0x08000000          # CREATE_NO_WINDOW
        return kw

    def probe(self, path):
        """Prove an executable by RUNNING a script that writes praatVersion
        to a marker file (Windows Praat's stdout is empty or UTF-16)."""
        path = self._resolve(path)
        if not path:
            return False
        marker = os.path.join(self.session, "praat_probe.txt")
        script = os.path.join(self.session, "praat_probe.praat")
        with open(script, "w", encoding="utf-8") as fh:
            fh.write('form: "probe"\n    sentence: "Out", ""\nendform\n'
                     'writeFileLine: out$, praatVersion\n')
        for flags in (["--FULL-TRUST", "--no-pref-files"], ["--no-pref-files"]):
            try:
                if os.path.exists(marker):
                    os.remove(marker)
                subprocess.run([path] + flags + ["--run", script, marker],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=60, **self._popen_kwargs())
            except Exception as ex:                          # noqa: BLE001
                self.error = "%s: %s" % (path, ex)
                continue
            if os.path.exists(marker):
                try:
                    with open(marker, encoding="utf-8", errors="replace") as fh:
                        v = int(float(fh.read().split()[0]))
                except Exception:                            # noqa: BLE001
                    v = 0
                self.exe, self.flags, self.version = path, flags, v
                for f in (marker, script):
                    try:
                        os.remove(f)
                    except OSError:
                        pass
                return True
        return False

    def find(self):
        for c in praat_candidates(self.hint):
            if self.probe(c):
                return True
        self.error = ("no runnable Praat executable found - set praatExe$ at the top "
                      "of AudioTools_CallResponse.praat (the executable or its folder)")
        return False

    def kill(self):
        with self.lock:
            p = self.proc
        if p is not None and p.poll() is None:
            try:
                p.terminate()
                p.wait(2)
            except Exception:                                # noqa: BLE001
                try:
                    p.kill()
                    p.wait(2)
                except Exception:                            # noqa: BLE001
                    pass

    def render(self, job, stop_ev, max_response, plugin_root):
        """Returns (ok, message).  On success job.answer/answer_sr/used are set."""
        import soundfile as sf
        jobf = os.path.join(self.session, "job_%s.txt" % job.tag)
        out = os.path.join(self.session, "out_%s.wav" % job.tag)
        res = os.path.join(self.session, "res_%s.txt" % job.tag)
        plog = os.path.join(self.session, "praat_%s.log" % job.tag)
        job.files += [jobf, out, res, plog]
        write_kv_atomic(jobf, list(job.pairs) + [
            ("wav", job.wav), ("out", out), ("result", res), ("plugin_root", plugin_root),
            ("max_response", fnum(max_response, 3)), ("job_id", job.tag)])
        env = dict(os.environ)
        env["AUDIOTOOLS_CR_JOB"] = jobf
        argv = [self.exe] + self.flags + ["--run", self.script] + RENDER_FORM_ARGS
        with open(plog, "wb") as lf:
            try:
                p = subprocess.Popen(argv, stdout=lf, stderr=subprocess.STDOUT, env=env,
                                     **self._popen_kwargs())
            except Exception as ex:                          # noqa: BLE001
                return False, "cannot start Praat: %s" % ex
            with self.lock:
                self.proc = p
            t0 = time.time()
            reason = ""
            while p.poll() is None:
                if stop_ev.is_set():
                    reason = "session stopped"
                elif time.time() - t0 > RENDER_TIMEOUT_S:
                    reason = "render timeout (%.0f s)" % RENDER_TIMEOUT_S
                if reason:
                    self.kill()
                    break
                time.sleep(0.02)
            with self.lock:
                self.proc = None
        if reason:
            return False, reason
        meta = {}
        try:
            with open(res, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "=" in line:
                        k, v = line.rstrip("\r\n").split("=", 1)
                        meta[k] = v
        except OSError:
            tail = ""
            try:
                with open(plog, "rb") as fh:
                    raw = fh.read()[-600:]
                tail = raw.replace(b"\x00", b"").decode("utf-8", "replace").strip()
            except OSError:
                pass
            return False, "Praat wrote no result (exit %s) %s" % (p.returncode, tail[-300:])
        job.praat_log = meta.get("log", "")
        if meta.get("end") != "1" or meta.get("status") != "ok":
            return False, meta.get("msg", "render failed")
        try:
            a, sr = sf.read(out, dtype="float32", always_2d=True)
        except Exception as ex:                              # noqa: BLE001
            return False, "cannot read rendered WAV: %s" % ex
        used = meta.get("used", "")
        if used not in TRANSFORM_IDS:
            return False, "render reported an unknown transformation '%s'" % used
        job.answer, job.answer_sr, job.used = a, int(sr), used
        job.praat_sec = meta.get("sec", "")
        return True, meta.get("msg", "ok")


class Job:
    def __init__(self, jid, audio, sr, t):
        self.id = jid
        self.tag = "%04d" % jid
        self.audio = audio            # frames x channels float32 (musician)
        self.sr = sr
        self.t = dict(t)              # wall-clock timestamps
        self.selected = ""
        self.used = ""
        self.pairs = []
        self.wav = ""
        self.files = []
        self.answer = None
        self.answer_sr = sr
        self.msg = ""
        self.praat_log = ""
        self.praat_sec = ""
        # v0.3.0 sonic memory
        self.kind = "transform"       # transform | recall | recall_transform
        self.phrase_id = ""           # Corpus A id of the live phrase
        self.source_id = ""           # corpus id of the audio sent to Praat
        self.source_corpus = "A"
        self.recall_item = None
        self.match = None
        self.gen_out = 1              # generation of a Praat result
        self.secondary = None         # v0.4.0 secondary voice spec (dict) or None
        self.leak_expected = None     # v0.4.1 expected leakage dBFS at phrase end
        self.influences = []          # v0.4.8 (label, weight, phrase id) of earlier phrases
        self.contrib = []             # v0.4.9 (label, share of the chosen score, phrase id)
        self.action_name = ""


def pid_alive(pid):
    """True while process `pid` exists (no psutil; Windows via ctypes)."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    if sys.platform.startswith("win"):
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.windll.kernel32
        h = k32.OpenProcess(0x1000, False, pid)          # QUERY_LIMITED_INFORMATION
        if not h:
            return False
        code = wintypes.DWORD()
        ok = k32.GetExitCodeProcess(h, ctypes.byref(code))
        k32.CloseHandle(h)
        return bool(ok) and code.value == 259             # STILL_ACTIVE
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def proc_start_token(pid):
    """v0.3.1: an identity token for process `pid` = its start time as the
    OS reports it ("" if unknown).  A PID number alone can be reused by an
    unrelated process; PID + start time cannot."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return ""
    if pid <= 0:
        return ""
    try:
        if sys.platform.startswith("win"):
            import ctypes
            from ctypes import wintypes
            k32 = ctypes.windll.kernel32
            h = k32.OpenProcess(0x1000, False, pid)
            if not h:
                return ""
            try:
                c, e, k, u = (wintypes.FILETIME() for _ in range(4))
                if not k32.GetProcessTimes(h, ctypes.byref(c), ctypes.byref(e),
                                           ctypes.byref(k), ctypes.byref(u)):
                    return ""
                return "w%d" % ((c.dwHighDateTime << 32) | c.dwLowDateTime)
            finally:
                k32.CloseHandle(h)
        if os.path.exists("/proc/%d/stat" % pid):
            with open("/proc/%d/stat" % pid) as fh:
                raw = fh.read()
            return "l" + raw[raw.rindex(")") + 2:].split()[19]      # field 22: starttime
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True,
                             text=True, timeout=5).stdout.strip()
        return ("m" + out.replace(" ", "_")) if out else ""
    except Exception:                                        # noqa: BLE001
        return ""


def owner_alive(info):
    """v0.3.1: is the engine recorded in launch.txt (pid + start token) still
    running?  A live PID whose start time differs is a REUSED PID = dead."""
    pid = info.get("pid")
    if not pid or not pid_alive(pid):
        return False
    tok = info.get("start", "")
    if not tok:
        return True                  # identity unknown: treat as alive (never delete)
    now = proc_start_token(pid)
    return (not now) or now == tok


def remove_tree(path, attempts=40, delay=0.25):
    """Delete a session folder with bounded retries (Windows file locks).
    Returns the list of paths that could NOT be removed (empty = success)."""
    for _ in range(attempts):
        if not os.path.exists(path):
            return []
        for dirpath, dirnames, names in os.walk(path, topdown=False):
            for n in names:
                try:
                    os.remove(os.path.join(dirpath, n))
                except OSError:
                    pass
            for d in dirnames:
                try:
                    os.rmdir(os.path.join(dirpath, d))
                except OSError:
                    pass
        try:
            os.rmdir(path)
        except OSError:
            pass
        if not os.path.exists(path):
            return []
        time.sleep(delay)
    left = []
    for dirpath, dirnames, names in os.walk(path):
        left += [os.path.join(dirpath, n) for n in names]
    return left or [path]


# files the Praat GUI still needs after the engine has finished; everything
# else in the session folder belongs to the engine and is deleted by it
PRAAT_OWNED = ("status.txt", "summary.txt", "praat_alive.txt", "stop.request", "launch.txt",
               "cleanup.pending")


class Engine:
    def __init__(self, args, sd):
        import numpy as np
        self.np, self.sd, self.a = np, sd, args
        self.sr, self.ch = int(args.sr), int(args.channels)
        self.session = args.session
        self.stop_ev = threading.Event()
        self.in_q = queue.Queue(maxsize=3000)          # 30 s of 10 ms blocks
        self.phrase_q = BoundedJobQueue("pending phrases", args.max_pending,
                                        args.overflow, self._dropped)
        self.render_q = BoundedJobQueue("pending renders", args.max_pending,
                                        args.overflow, self._dropped)
        self.play_q = BoundedJobQueue("pending responses", args.max_responses,
                                      args.overflow, self._dropped)
        self.b_q = queue.Queue(maxsize=8)               # Praat results -> Corpus B
        self.det = PhraseDetector(self.sr, self.ch, args.sensitivity, args.min_phrase,
                                  args.end_silence, args.max_phrase, args.preroll)
        if args.leak_guard:
            self.det.leak_level = self._expected_leak_db
        self.hop_s = self.det.hop_s
        self.in_ring = Ring(self.sr, 3.0)
        self.out_ring = Ring(self.sr, args.max_phrase + LEAK_MAX_LAG_S + 2.0)
        # v0.4.0: the two output channels too (stereo leakage check)
        self.out_ring_l = Ring(self.sr, args.max_phrase + LEAK_MAX_LAG_S + 2.0)
        self.out_ring_r = Ring(self.sr, args.max_phrase + LEAK_MAX_LAG_S + 2.0)
        self.c = collections.Counter()
        self.state, self.message, self.processing, self.playing = "starting", "", "", ""
        self.stage = "start"
        self.input_db = -120.0
        self.lv_hist = collections.deque(maxlen=10)       # v0.4.10: last 100 ms
        self.det_event = ("", 0.0)                         # v0.4.11: last detector event
        self.leak_db, self.leak_rho = None, 0.0
        self.leak_lag, self.leak_cand, self.leak_conf = None, None, 0
        self.out_hold_db, self.out_hold_t = -120.0, 0.0
        self.out_ch = 1
        self.next_id = 1
        self.fatal = ""
        self.summary = []
        self.events = []
        self.delays = []
        self.t_start = time.time()
        self.t_activity = time.time()
        self.log_fh = None
        if args.debug_log and args.debug_log.lower() != "none":
            try:
                self.log_fh = open(args.debug_log, "a", encoding="utf-8")
            except OSError:
                self.log_fh = None
        self.renderer = PraatRenderer(args.praat, args.script, self.session, self.log)
        # ---- v0.3.0 sonic memory ----
        self.mcfg = {
            "enabled": bool(args.memory) and args.response_mode != "transform",
            "response_mode": args.response_mode, "use_A": bool(args.use_a),
            "use_B": bool(args.use_b), "use_C": bool(args.use_c),
            "sim_mode": args.sim_mode, "min_similarity": args.min_sim,
            "w_live": args.w_live, "w_processed": args.w_processed,
            "w_preloaded": args.w_preloaded, "p_transform": args.p_transform,
            "p_recall": args.p_recall, "p_recall_transform": args.p_recall_transform,
            "max_generation": args.max_generation, "max_live": args.max_live,
            "max_processed": args.max_processed, "max_ram_min": args.max_ram_min,
            "max_item_s": args.max_item_s, "candidates": args.candidates,
            "evolving": bool(args.evolving), "layered": bool(args.layered),
            "recent_exclude": args.recent_exclude, "cooldown": args.cooldown,
            "same_family_exclusion": bool(args.same_family),
            "c_max_items": args.c_max_items, "c_max_files": args.c_max_files,
            "c_max_per_file": args.c_max_per_file, "c_min_item_s": args.c_min_item_s,
        }
        seed = args.seed if args.seed > 0 else 1 + (zlib.crc32(self.session.encode()) % 2000000000)
        self.memory = SonicMemory(self.mcfg, seed, self.log)
        self.last_recall, self.last_match, self.last_action = "", "", ""
        # v0.4.8 phrase-level influence memory: previous phrases (id, desc, t)
        self.inf_depth = max(1, min(8, int(args.influence_depth)))
        self.inf_decay = clamp(float(args.influence_decay), 0.0, 1.0)
        self.inf_trend = clamp(float(args.trend_weight), 0.0, 1.0)
        self.history = collections.deque(maxlen=max(1, self.inf_depth))
        self.fault = os.environ.get("AUDIOTOOLS_CR_FAULT", "")   # test hook, inert by default
        self.status_fail_streak = 0
        # ---- v0.4.0 polyphonic spatial playback ----
        import random
        self.pcfg = {
            "polyphony": bool(args.polyphony), "max_voices": max(1, int(args.max_voices)),
            "density": clamp(args.density, 0.0, 1.0), "width": clamp(args.stereo_width, 0.0, 1.0),
            "movement": clamp(args.movement, 0.0, 1.0),
            "pan_variation": clamp(args.pan_variation, 0.0, 1.0),
            "fade_in": max(0.003, args.fade_in_ms / 1000.0),
            "fade_out": max(0.003, args.fade_out_ms / 1000.0),
            "transients": bool(args.preserve_transients),
            "level_match": bool(args.level_match),
            "background": bool(args.background) and bool(args.polyphony)
                          and args.response_mode != "corpus_only",
            "bg_db": float(args.background_db),
            "corpus_c_db": clamp(float(args.corpus_c_db), -12.0, 12.0),
            "layer_shape": args.layer_shape,
        }
        # v0.4.1: relative follower of the performer's playing level
        self.follower = LevelFollower(args.follow_range) if args.follow_input else None
        self.prng = random.Random(seed + 7919)       # playback choices only
        self.mixer = Mixer(self.sr)
        self.space = SpaceAllocator(self.prng, self.pcfg["width"], self.pcfg["pan_variation"])
        self.bg_recent = collections.deque(maxlen=4)
        self.bg_state = "off" if not self.pcfg["background"] else "waiting for material"
        self.t_performer = 0.0
        self.t_texture = -1e9                 # last background texture started
        self.bg_paused = False
        self.recent_answers = collections.deque(maxlen=3)
        self.layer_history = collections.deque(maxlen=4)
        # ---- v0.4.6 memory map ----
        self.graph = MemoryGraph(self.memory, args.sim_mode, args.min_sim) \
            if self.mcfg["enabled"] else None
        self.graph_data = None           # (rows, nodes), replaced whole by the brain thread
        self.graph_ver = 0
        self.graph_written = (0, None)
        self.graph_file_ver = 0
        self.t_graph = 0.0

    # ---------------- logging ----------------
    def log(self, msg, event=False):
        line = "%8.3f  %s" % (time.time() - self.t_start, msg)
        if event:
            self.events.append(line)
        if self.log_fh:
            try:
                self.log_fh.write(line + "\n")
                self.log_fh.flush()
            except (OSError, ValueError):
                pass

    def _dropped(self, job, why):
        self.c["dropped"] += 1
        self.log("DROPPED job %s (%s): %s" % (job.tag, job.selected or "unanalysed", why), True)
        self._cleanup_job(job)

    def _cleanup_job(self, job):
        for f in job.files:
            for _ in range(20):                          # Windows: bounded retries
                try:
                    if os.path.exists(f):
                        os.remove(f)
                    break
                except OSError:
                    time.sleep(0.05)
        job.files = []

    def _check_fault(self, where):
        if self.fault == where:
            self.fault = ""
            raise RuntimeError("injected test fault in %s worker" % where)

    # ---------------- audio callbacks (no DSP, no I/O, no locks held long) --------
    def _in_cb(self, indata, frames, tinfo, status):
        if status:
            self.c["input_status"] += 1
        try:
            self.in_q.put_nowait((indata.copy(), time.time()))
        except queue.Full:
            self.c["overruns"] += 1

    def _out_cb(self, outdata, frames, tinfo, status):
        """v0.4.0: sums the active voices (Mixer.render: slices, gain ramps,
        limiter).  No file access, no locks held, no DSP beyond additions."""
        if status:
            self.c["output_status"] += 1
        mix = self.mixer.render(frames)
        if self.out_ch == 1:
            outdata[:, 0] = mix.mean(axis=1)
        else:
            outdata[:, :2] = mix
            if outdata.shape[1] > 2:
                outdata[:, 2:] = 0
        mono = mix.mean(axis=1)
        t = time.time()
        self.out_ring.append(mono, t)
        self.out_ring_l.append(mix[:, 0], t)
        self.out_ring_r.append(mix[:, 1], t)
        # v0.4.0: the LOUDER channel - a voice panned towards the speaker the
        # microphone hears best must not be underestimated by the L+R mean
        lv = max(db_of(mix[:, 0]), db_of(mix[:, 1])) if self.out_ch == 2 else db_of(mono)
        held = self.out_hold_db - 20.0 * (t - self.out_hold_t)
        if lv >= held:
            self.out_hold_db, self.out_hold_t = lv, t

    def _out_level_now(self):
        return self.out_hold_db - 20.0 * (time.time() - self.out_hold_t)

    def _expected_leak_db(self):
        if self.leak_db is None:
            return None
        lv = self._out_level_now()
        if lv < -70:
            return None
        # v0.4.0: while ONLY the background texture sounds, its grain peaks
        # stand above its block level: 4 dB more margin (still far below a
        # played gesture, since the background sits around -33 dBFS)
        act = self.mixer.active()
        if act and all(v.role == "bg" for v in act):
            return lv + self.leak_db + 4.0
        return lv + self.leak_db

    # ---------------- DETECT thread (detection only; never searches memory) ----
    def _detect_loop(self):
        np = self.np
        hop = self.det.hop
        pending = np.zeros((0, self.ch), np.float32)
        t_leak = 0.0
        try:
            while not self.stop_ev.is_set():
                try:
                    block, tb = self.in_q.get(timeout=0.2)
                except queue.Empty:
                    continue
                mono = block[:, 0] if block.shape[1] == 1 else block.mean(axis=1)
                self.in_ring.append(mono, tb)
                pending = np.concatenate([pending, block], axis=0) if len(pending) else block
                while len(pending) >= hop:
                    ev = self.det.feed(pending[:hop])
                    # v0.4.10: the meter shows the detector's own frame level
                    self.lv_hist.append(self.det.last_db)
                    self.input_db = max(self.lv_hist)
                    pending = pending[hop:]
                    if self.det.state == "PHRASE":
                        self.t_performer = tb
                    if ev == "onset":
                        self.log("onset (floor %.1f dBFS, thr %.1f)" %
                                 (self.det.floor, self.det.thresholds()[0]))
                    elif ev == "discarded":
                        if self.det.last_discard == "noise":
                            self.det_event = ("noise ignored, background learned", time.time())
                            self.log("background noise mistaken for a phrase - ignored, floor "
                                     "%.1f dBFS" % self.det.floor, True)
                        else:
                            self.det_event = ("too short, ignored", time.time())
                            self.log("short trigger discarded (< %.2f s)" % self.a.min_phrase)
                    elif ev == "end":
                        self.det_event = ({"silence": "phrase end (silence)",
                                           "background": "phrase end (background learned)",
                                           "max_duration": "split at Max_phrase_s (continues)",
                                           "max_duration_steady": "steady noise learned as "
                                                                  "background"}.get(
                            self.det.ended_by, self.det.ended_by), time.time())
                        self._finalize(tb)
                        self.det.rearm()
                if tb - t_leak >= 1.0:
                    t_leak = tb
                    self._update_leak(tb)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "detector failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    def _update_leak(self, t_end):
        """A leakage level is trusted only for a VALIDATED path: a sharp PHAT
        peak at a plausible delay, confirmed by two consecutive estimates
        within 1 ms.  Otherwise any previous estimate decays."""
        if self._out_level_now() < -50:
            return
        y = self.in_ring.segment(t_end, 1.0)
        x = self.out_ring.segment(t_end, 1.0 + LEAK_MAX_LAG_S)
        if db_of(x) < -55 or db_of(y) < -70:
            return
        r = leak_path(x, y, int(LEAK_MAX_LAG_S * self.sr), self.sr)
        self.leak_rho = r["rho"]
        if r["plausible"] and r["a"] != 0:
            if self.leak_cand is not None and abs(r["lag"] - self.leak_cand) <= int(0.001 * self.sr):
                self.leak_conf += 1
            else:
                self.leak_conf = 1
            self.leak_cand = r["lag"]
        else:
            self.leak_conf, self.leak_cand = 0, None
        if self.leak_conf >= 2:
            self.leak_lag = r["lag"]
            if abs(r["rho"]) >= LEAK_GAIN_RHO:
                g = 20 * math.log10(abs(r["a"]))
                self.leak_db = g if self.leak_db is None else max(g, self.leak_db - 0.5)
                self.log("leakage path %.1f dB at %.1f ms (z %.0f, dominance %.1f, rho %.2f)" %
                         (g, 1000.0 * r["lag"] / self.sr, r["z"], r["dom"], r["rho"]))
            else:
                self.log("leakage path confirmed at %.1f ms; gain kept (performer playing, "
                         "rho %.2f)" % (1000.0 * r["lag"] / self.sr, r["rho"]))
        elif (self.leak_db is not None and self.leak_conf == 0 and
              db_of(x) + self.leak_db > self.det.floor + 10.0):
            # v0.4.0: decay only with EVIDENCE that the path is gone: the
            # predicted leakage would stand 10 dB above the input floor, yet
            # no path is found.  A quiet (or smooth, tonal) background layer
            # is not measurable and must not erase what was learned.
            self.leak_db -= 3.0
            if self.leak_db < -80:
                self.leak_db, self.leak_lag = None, None
        if self.leak_db is not None and self.leak_db > -20 and not self.c["leak_warned"]:
            self.c["leak_warned"] = 1
            self.log("WARNING: speaker->microphone leakage %.1f dB - use headphones or "
                     "separate the output from the microphone" % self.leak_db, True)

    def _finalize(self, tb):
        """Cut the finished phrase, run the (cheap) leakage check, hand it to
        the brain worker.  Analysis and memory work happen THERE."""
        np = self.np
        d = self.det
        end_idx = d.phrase_end_index()
        audio = d.phrase_audio()
        t_audio_end = tb - (len(d.buf) - end_idx) * d.hop_s
        t_end = tb - d.silence_frames_after_last_active() * d.hop_s
        dur = len(audio) / self.sr
        t_audio_start = t_audio_end - dur
        t_onset = t_audio_start + d.start_active * d.hop_s
        jid = self.next_id
        self.next_id += 1
        job = Job(jid, audio.astype(np.float32), self.sr,
                  {"onset": t_onset, "end": t_end, "detected": time.time()})
        self.c["phrases"] += 1
        self.t_activity = time.time()
        job.leak_expected = self._expected_leak_db()
        self.log("phrase %s: %.2f s, ended by %s, detection delay %.3f s" %
                 (job.tag, dur, d.ended_by, time.time() - t_end))
        mono = audio[:, 0] if audio.shape[1] == 1 else audio.mean(axis=1)
        if self.a.leak_guard and self.leak_lag is not None and self._out_level_now() > -70:
            x = self.out_ring.segment(t_audio_end, dur + LEAK_MAX_LAG_S)
            if db_of(x) > -55:
                mx = int(LEAK_MAX_LAG_S * self.sr)
                a, rho, lag = leak_fit(x, mono, mx)
                # +-3 ms: separate input / output clocks drift by a few ms
                tol = int(LEAK_LAG_TOL_S * self.sr)
                if abs(lag - self.leak_lag) > tol:
                    a, rho, lag = 0.0, 0.0, self.leak_lag
                # v0.4.0: several voices in different places - also test the
                # two output channels separately at the validated delay
                r2s = 0.0
                if self.out_ch == 2:
                    xl = self.out_ring_l.segment(t_audio_end, dur + LEAK_MAX_LAG_S)
                    xr = self.out_ring_r.segment(t_audio_end, dur + LEAK_MAX_LAG_S)
                    step = max(1, int(0.0005 * self.sr))
                    for lg in sorted(set([lag] + list(range(self.leak_lag - tol,
                                                            self.leak_lag + tol + 1, step)))):
                        r2s = max(r2s, leak_fit_stereo(xl, xr, mono, mx, lg))
                if r2s > rho * rho:
                    rho = math.sqrt(r2s)
                if rho * rho >= LEAK_DISCARD_RHO2:
                    self.c["leak_discarded"] += 1
                    self.log("phrase %s DISCARDED as playback leakage: %.0f %% of its energy "
                             "is the delayed answer (gain %.1f dB, lag %.0f ms)" %
                             (job.tag, 100 * rho * rho, 20 * math.log10(abs(a) + 1e-12),
                              1000.0 * lag / self.sr), True)
                    return
        if dur < 0.25:
            self.c["too_short"] += 1
            self.log("phrase %s too short for analysis (%.3f s)" % (job.tag, dur), True)
            return
        self.phrase_q.put(job)

    # ---------------- BRAIN thread: analysis, memory, decision ----------------
    def _brain_loop(self):
        try:
            while not self.stop_ev.is_set():
                job = self.phrase_q.get(0.05)
                if job is not None:
                    self._check_fault("brain")
                    self._think(job)
                    continue
                try:
                    done = self.b_q.get_nowait()
                except queue.Empty:
                    continue
                self._insert_processed(done)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "analysis worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    def _graph_publish(self):
        """v0.4.6 (brain thread, or main thread before the workers start)."""
        if self.graph is None:
            return
        try:
            self.graph_data = self.graph.build()
            self.graph_ver += 1
        except Exception as ex:                              # noqa: BLE001
            self.log("memory map not updated: %s" % ex)

    def _graph_write(self, now):
        """v0.4.6 (main thread): graph.tsv when the map or the sounding set
        changed, at most 4 times per second; a locked file is skipped."""
        if self.graph_data is None or now - self.t_graph < 0.25:
            return
        sounding = frozenset(v.item_id for v in self.mixer.active() if v.item_id)
        key = (self.graph_ver, sounding)
        if key == self.graph_written:
            return
        self.t_graph = now
        rows, nodes = self.graph_data
        path = os.path.join(self.session, GRAPH_FILE)
        try:
            write_text_atomic(path, graph_tsv(rows, nodes, sounding))
        except OSError:
            try:
                os.remove(path + ".tmp")
            except OSError:
                pass
            return
        self.graph_written = key
        self.graph_file_ver += 1

    @staticmethod
    def _inf_note(job):
        n = sum(1 for lab, w, pid in getattr(job, "influences", ()) if lab != "trend")
        t = any(lab == "trend" for lab, w, pid in getattr(job, "influences", ()))
        if not n and not t:
            return ""
        return " (%d phrases%s)" % (n + 1, " + trend" if t else "")

    def _forced(self):
        return None if self.a.force in ("", "auto") else self.a.force

    def _write_input(self, job, audio, sr, name):
        import soundfile as sf
        path = os.path.join(self.session, "%s_%s.wav" % (name, job.tag))
        job.files.append(path)                            # tracked BEFORE writing
        sf.write(path, audio, sr, subtype="FLOAT")
        job.wav = path

    def _think(self, job):
        np = self.np
        t0 = time.perf_counter()
        a64 = job.audio.astype(np.float64)
        a_in = a64[:, 0] if a64.shape[1] == 1 else a64
        try:
            F = extract_features(a_in, self.sr)
            t1 = time.perf_counter()
            info = decide(F, self._forced())
            nch = 1 if a_in.ndim == 1 else a_in.shape[1]
            seed = audio_seed(a_in)
            P = params_all(F, a_in, self.sr, nch, seed)
            desc = memory_descriptor(F) if self.mcfg["enabled"] else None
            t2 = time.perf_counter()
        except Exception as ex:                              # noqa: BLE001
            self.c["failed"] += 1
            self.log("phrase %s analysis failed: %s" % (job.tag, ex), True)
            return
        job.t["analysed"] = time.time()
        if self.follower is not None:
            ld = active_loudness_db(job.audio, self.sr)
            le = job.leak_expected
            excl = le is not None and le > ld - 15.0
            off = self.follower.update(ld, excl)
            self.log("phrase %s loudness %.1f dB%s -> level offset %+.1f dB" %
                     (job.tag, ld, " (not counted: speaker leakage)" if excl else "", off))
        mem = self.memory
        job.phrase_id = mem.new_id("A")
        action, why, cand, rt = "transform", "sonic memory off", None, None
        top = []
        t_mem = time.perf_counter()
        if self.mcfg["enabled"]:
            recentA = [it.id for it in mem.items["A"][-self.mcfg["recent_exclude"]:]] \
                if self.mcfg["recent_exclude"] > 0 else []
            horizon = 60.0 * (self.a.session_minutes if self.a.session_minutes > 0 else 20.0)
            progress = (time.time() - self.t_start) / horizon
            gsc = mem._scales(mem.all_items(), desc)
            smode = mem.cfg.get("sim_mode", "hybrid")

            def coherence(d, _q=desc, _sc=gsc):
                # v0.4.9: the retrieval's own similarity (mode, unpitched
                # rule, contour stage), not the map's approximation
                return influence_gate(mem.similarity(_q, [_DescOnly(d)], smode, scales=_sc)[0][1])
            t_phrase = job.t.get("end", time.time())
            infl = influence_queries(self.history, t_phrase, self.inf_depth, self.inf_decay,
                                     self.inf_trend, desc, gate=coherence)
            job.influences = [(lab, w, pid) for d, w, lab, pid in infl]
            cand, top, why = mem.retrieve(desc, exclude_ids={job.phrase_id} | set(recentA),
                                          exclude_roots=set(recentA), progress=progress,
                                          influences=infl)
            if infl:
                self.log("phrase %s influence: last 1.00, %s" % (job.tag, ", ".join(
                    "%s %.2f" % (lab, w) for d, w, lab, pid in infl)))
            rt = pick_recall_transform(cand, top, self._forced(), self.mcfg["max_generation"])
            action, why2 = mem.choose_action(cand, rt)
            why = why2 if cand or rt else why + " -> transform"
        t_mem = time.perf_counter() - t_mem
        chosen = cand if action == "recall" else rt if action == "recall_transform" else None
        if chosen is not None and job.influences and len(chosen.get("parts", ())) == \
                1 + len(job.influences):
            tot = sum(chosen["parts"]) or 1.0
            job.contrib = [(lab, part / tot, pid) for (lab, w, pid), part in
                           zip(job.influences, chosen["parts"][1:])]
            self.log("phrase %s: share of the chosen sound's score - last %.2f, %s" % (
                job.tag, chosen["parts"][0] / tot,
                ", ".join("%s %.2f" % (lab, sh) for lab, sh, pid in job.contrib)))
        if desc is not None:
            self.history.append((job.phrase_id, desc, job.t.get("end", time.time())))
        job.kind = action
        if action == "silence":
            job.selected = "silence"
            job.action_name = "Silent (no corpus match)"
            self.last_recall, self.last_match = "", ""
        elif action == "recall":
            it = cand["item"]
            mem.mark_recalled(it)
            job.recall_item, job.match, job.selected = it, cand["match"], "recall"
            job.source_id, job.source_corpus = it.id, it.corpus
            job.action_name = "Recall %s (%s)" % (it.id, CORPUS_NAMES[it.corpus])
            self.last_recall, self.last_match = "Corpus %s" % it.corpus, "%.2f%s" % (
                cand["match"], self._inf_note(job))
        elif action == "recall_transform":
            it = rt["item"]
            mem.mark_recalled(it)
            ia = it.get_audio()
            ia64 = ia.astype(np.float64)
            ia_in = ia64[:, 0] if ia64.shape[1] == 1 else ia64
            iseed = audio_seed(ia_in)
            dec = rt["decision"]
            iP = params_all(it.F, ia_in, it.sr, 1 if ia_in.ndim == 1 else ia_in.shape[1], iseed)
            job.pairs = decision_pairs(it.F, dec, iP, [
                ("status", "ok"), ("message", "ok"), ("source", "corpus %s" % it.id),
                ("duration", fnum(it.F["duration"], 4)), ("sr", it.sr), ("seed", iseed),
                ("t_phrase_end_epoch", "%.4f" % job.t["end"])])
            self._write_input(job, ia_in.astype(np.float32), it.sr, "c")
            job.selected, job.match = dec["selected"], rt["match"]
            job.source_id, job.source_corpus = it.id, it.corpus
            job.gen_out = it.generation + 1
            job.action_name = "%s on %s" % (DISPLAY_NAMES.get(job.selected, job.selected), it.id)
            self.last_recall, self.last_match = "Corpus %s" % it.corpus, "%.2f%s" % (
                rt["match"], self._inf_note(job))
        else:
            job.selected = info["selected"]
            job.source_id, job.source_corpus, job.gen_out = job.phrase_id, "A", 1
            job.action_name = DISPLAY_NAMES.get(job.selected, job.selected)
            if job.selected != "passthrough":
                self._write_input(job, a_in.astype(np.float32), self.sr, "p")
            job.pairs = decision_pairs(F, info, P, [
                ("status", "ok"), ("message", "ok"), ("source", "live continuous"),
                ("duration", fnum(F["duration"], 4)), ("sr", self.sr), ("channels", nch),
                ("seed", seed), ("t_features", fnum(t1 - t0, 4)), ("t_select", fnum(t2 - t1, 4)),
                ("t_phrase_end_epoch", "%.4f" % job.t["end"])])
            if not self.mcfg["enabled"]:
                self.last_recall, self.last_match = "", ""
        self.last_action = job.action_name
        if self.mcfg["enabled"] and self.mcfg["response_mode"] != "corpus_only":
            self._plan_secondary(job, F, cand, top if self.mcfg["enabled"] else [])
        self.log("phrase %s (%s) -> %s (%s)%s  [analysis %.0f ms, memory search %.0f ms over %d "
                 "sounds]" % (job.tag, job.phrase_id, job.action_name, why,
                              "" if job.match is None else "  match %.2f" % job.match,
                              1000 * (t2 - t0), 1000 * t_mem, sum(mem.counts().values())), True)
        if self.log_fh:
            rep = build_report(F, info, P, "Phrase %s - live continuous, %.2f s" %
                               (job.tag, F["duration"]))
            self.log("analysis %s (features %.3f s, selection %.3f s)\n%s" %
                     (job.tag, t1 - t0, t2 - t1, rep.rstrip()))
        # the live phrase enters Corpus A only AFTER its own retrieval
        if self.mcfg["enabled"] and self.mcfg["use_A"]:
            a_store, _ = trim_quiet(job.audio, self.sr, self.mcfg["max_item_s"])
            mem.add(CorpusItem(job.phrase_id, "A", a_store, self.sr, F, desc, info, time.time(),
                               {"root": job.phrase_id, "parent": None, "method": None,
                                "generation": 0, "source": "live phrase %s" % job.tag}))
        if self.graph is not None:
            g = self.graph
            g.phrase(job.phrase_id, time.time(), info["selected"])
            if self.mcfg["use_A"]:
                g.link([mem.find(job.phrase_id)])
            if action in ("recall", "recall_transform"):
                for lab, share, pid in job.contrib:             # v0.4.9: real shares
                    if pid:
                        g.action(pid, job.source_id, "influence", share)
                g.action(job.phrase_id, job.source_id, action, job.match)
            self._graph_publish()
        if action == "silence":
            # v0.4.1 corpus only: no answer, keep listening
            self.c["kind_silence"] += 1
            self._cleanup_job(job)
            return
        self.render_q.put(job)

    def _plan_secondary(self, job, F, cand, top):
        """v0.4.0 polyphonic density: with probability ~ density, a second,
        quieter voice from memory joins the answer - a related sound (from
        the ranked candidates) or, if none, an independent stored sound -
        entering 0.6-3.5 s after the answer (on the phrase's own pulse when
        it is rhythmic), as an excerpt of 60-100 % of its length, at its own
        place in space.  Runs in the brain thread (owner of the memory)."""
        pc = self.pcfg
        if not pc["polyphony"] or pc["max_voices"] < 2:
            return
        rng = self.prng
        p = 1.0 if self.mcfg["layered"] else 0.75 * pc["density"]
        busy = len(self.mixer.active())
        if busy >= pc["max_voices"] - 1:
            p *= 0.3                       # avoid constant maximum density
        if rng.random() >= p:
            return
        mem = self.memory
        skip = {job.phrase_id, job.source_id}
        if cand is not None:
            skip.add(cand["item"].id)
        pool = [r["item"] for r in top if r["item"].id not in skip]
        how = "related"
        # layers never repeat a recent answer or a recent layer, and they do NOT
        # enter the answers' cooldown history (v0.3 recall behaviour unchanged)
        recent = set(mem.recall_history) | set(self.layer_history)
        pool = [it for it in pool if it.id not in recent]
        if not pool:
            pool = [it for corp in ("A", "B", "C") if mem.corpus_weights(0.5)[corp] > 0
                    for it in mem.items[corp] if it.id not in skip and it.id not in recent
                    and it.duration >= 0.8]
            how = "independent"
        if not pool:
            return
        it = rng.choice(pool[:5])
        a = it.get_audio()
        if a is None or len(a) < int(0.5 * it.sr):
            return
        L = len(a)
        st = 0
        if self.pcfg.get("layer_shape", "whole") == "excerpt":
            # v0.4.5: start at an onset of the first 40 %, ALWAYS run to the
            # natural end of the sound (never a random start / early stop)
            starts = [s for s in onset_starts(a, it.sr) if L - s >= int(0.8 * it.sr)]
            st = rng.choice(starts) if starts else 0
        seg = L - st
        shape = "whole" if st == 0 else "excerpt %.1f-%.1f of %.1f s" % (
            st / float(it.sr), L / float(it.sr), L / float(it.sr))
        delay = rng.uniform(0.6, 3.5)
        ioi = F.get("ioi_median", 0.0) or 0.0
        if F.get("onset_rate", 0.0) > 1.5 and 0.08 < ioi < 1.5:
            delay = max(ioi, round(delay / ioi) * ioi)        # on the phrase's pulse
        it.recalls += 1                       # novelty bookkeeping only
        self.layer_history.append(it.id)
        if st > 0:
            self.c["layers_excerpt"] += 1
        job.secondary = {"audio": a[st:], "sr": it.sr, "delay": delay,
                         "corpus": it.corpus, "shape": shape, "item_id": it.id,
                         "gain_db": rng.uniform(-3.0, 1.0),
                         "name": "%s %s" % ("echo of" if how == "related" else "memory", it.id)}
        self.log("phrase %s: secondary voice planned: %s, %s (%.1f s), enters %.2f s after "
                 "the answer" % (job.tag, job.secondary["name"], shape, seg / float(it.sr), delay),
                 True)

    def _insert_processed(self, r):
        """A genuinely NEW Praat result becomes a Corpus B entry, analysed
        from its own audio (not from its source).  `r` is a snapshot made by
        the render worker (tag, answer, sr, used, source_id, gen_out)."""
        mem = self.memory
        if not (self.mcfg["enabled"] and self.mcfg["use_B"]) or r["answer"] is None:
            return
        if r["gen_out"] > self.mcfg["max_generation"]:
            self.log("job %s: generation %d > %d - not stored" %
                     (r["tag"], r["gen_out"], self.mcfg["max_generation"]))
            return
        np = self.np
        sr = r["sr"]
        # v0.4.5: the WHOLE answer (it was a raw first-Max_item_s slice)
        a, cut = trim_quiet(r["answer"], sr, self.a.max_response + TAIL_GRACE_S)
        if cut:
            self.log("job %s: stored answer trimmed at a quiet point to %.1f s" %
                     (r["tag"], len(a) / float(sr)))
        if len(a) < int(0.3 * sr):
            return
        a64 = a.astype(np.float64)
        F, dec, desc = analyse_item(a64[:, 0] if a64.shape[1] == 1 else a64, sr)
        parent = mem.find(r["source_id"])
        if parent is not None:
            sim = mem.similarity(desc, [parent], "hybrid")[0][1]
            if sim >= IDENTITY_SIM:
                self.log("job %s: result almost identical to %s (%.2f) - not stored" %
                         (r["tag"], parent.id, sim), True)
                return
        iid = mem.new_id("B")
        root = parent.root if parent is not None else r["source_id"]
        mem.add(CorpusItem(iid, "B", a.astype(np.float32), sr, F, desc, dec,
                           time.time(), {"root": root, "parent": r["source_id"],
                                         "method": r["used"], "generation": r["gen_out"],
                                         "source": "%s of %s" % (r["used"], r["source_id"])}))
        self.log("memory: %s = %s of %s (generation %d)" %
                 (iid, r["used"], r["source_id"], r["gen_out"]), True)
        if self.graph is not None:
            self.graph.link([mem.find(iid)])
            self.graph.action(r["source_id"], iid, "transform")
            self._graph_publish()

    # ---------------- RENDER thread ----------------
    def _render_loop(self):
        try:
            while not self.stop_ev.is_set():
                job = self.render_q.get(0.2)
                if job is None:
                    continue
                self._check_fault("render")
                if job.kind == "recall":
                    a = job.recall_item.get_audio()
                    job.answer, job.answer_sr, job.used = a, job.recall_item.sr, "recall"
                    job.msg = "recalled %s" % job.recall_item.id
                elif job.selected == "passthrough":
                    job.answer, job.answer_sr, job.used = job.audio, job.sr, "passthrough"
                    job.msg = "no transformation reached its confidence threshold"
                    self.c["passthrough"] += 1
                    self.log("job %s: %s - answering with the phrase itself" % (job.tag, job.msg), True)
                else:
                    self.processing = job.action_name
                    job.t["render_start"] = time.time()
                    ok, msg = self.renderer.render(job, self.stop_ev, self.a.max_response,
                                                   self.a.plugin_root)
                    job.t["render_end"] = time.time()
                    self.processing = ""
                    if self.stop_ev.is_set():
                        self.c["dropped"] += 1
                        self.log("job %s (%s): render interrupted by stop (%s) - not played" %
                                 (job.tag, job.selected, msg), True)
                        self._cleanup_job(job)
                        break
                    if self.log_fh and job.praat_log:
                        self.log("praat %s: %s" % (job.tag, job.praat_log))
                    if ok:
                        job.msg = msg
                        if job.used != job.selected:
                            self.log("job %s: %s failed in Praat, runner-up %s used" %
                                     (job.tag, job.selected, job.used), True)
                        try:
                            # a snapshot: the play worker releases job.answer later
                            self.b_q.put_nowait({"tag": job.tag, "answer": job.answer,
                                                 "sr": job.answer_sr, "used": job.used,
                                                 "source_id": job.source_id,
                                                 "gen_out": job.gen_out})
                        except queue.Full:
                            self.log("job %s: memory insert queue full - result not stored" %
                                     job.tag, True)
                    else:
                        self.c["failed"] += 1
                        job.answer, job.answer_sr, job.used = job.audio, job.sr, "passthrough"
                        job.msg = "render failed: %s" % msg
                        self.log("job %s (%s): %s - answering with the untransformed phrase" %
                                 (job.tag, job.selected, job.msg), True)
                    self.log("job %s rendered in %.2f s" %
                             (job.tag, job.t["render_end"] - job.t["render_start"]))
                    self._cleanup_job(job)                # Praat files: no longer needed
                self.play_q.put(job)
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "render worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    # ---------------- PLAY thread (v0.4.0: voices, not one buffer) -----------
    def _level_offset(self, corpus=None):
        """v0.4.1: follow-input offset + Corpus C balance, in dB."""
        off = self.follower.offset if self.follower is not None else 0.0
        if corpus == "C":
            off += self.pcfg["corpus_c_db"]
        return off

    def _make_voice(self, a, sr, role, name, wait_s=0.0, gain_db=0.0, corpus=None):
        """Format conversion, length cap, envelope, level, placement, slow
        movement -> a Voice (all off the audio thread).  Returns
        (voice or None, truncated)."""
        np = self.np
        import scipy.signal
        pc = self.pcfg
        a = np.asarray(a, np.float32)
        if a.ndim == 1:
            a = a[:, None]
        if sr != self.sr:
            g = math.gcd(int(sr), self.sr)
            a = scipy.signal.resample_poly(a, self.sr // g, int(sr) // g, axis=0).astype(np.float32)
        # v0.4.5: Max_response_s + grace; longer sounds are cut at their
        # quietest point near the limit (never inside the first 85 %)
        n_in = len(a)
        a, trunc = trim_quiet(a, self.sr, self.a.max_response + TAIL_GRACE_S)
        shape = "whole %.1f s" % (n_in / float(self.sr)) if not trunc else \
            "trimmed %.1f -> %.1f s" % (n_in / float(self.sr), len(a) / float(self.sr))
        if trunc:
            self.c["voices_trimmed"] += 1
        if len(a) < int(0.02 * self.sr):
            return None, trunc
        b, fi, fo = shape_envelope(a, self.sr, pc["fade_in"], pc["fade_out"],
                                   pc["transients"], truncated=trunc)
        gain_db = gain_db + self._level_offset(corpus)
        lvl = {}
        if pc["level_match"]:
            b, _ = level_match(b, ROLE_TARGET_DB[role] + gain_db, sr=self.sr, info=lvl)
        elif gain_db:
            b = (b * 10 ** (gain_db / 20.0)).astype(np.float32)
        center = self.space.place(role, self.mixer.active())
        st = spatialize(b, self.sr, center, pc["movement"], pc["width"], self.prng,
                        slow=(role == "bg"))
        # v0.4.7: the stereo balance can raise one channel (up to +3 dB):
        # keep the placed voice under the per-voice ceiling
        pk = float(np.max(np.abs(st))) if len(st) else 0.0
        if pk > VOICE_PEAK_CEILING:
            st *= VOICE_PEAK_CEILING / pk
            lvl["after_space_db"] = 20 * math.log10(VOICE_PEAK_CEILING / pk)
            self.c["voices_peak_trimmed"] += 1
        v = Voice(st, role, name, center, wait=int(wait_s * self.sr))
        v.shape = shape
        if lvl:
            v.shape += "; level %s%s" % (
                "" if "integrated" not in lvl else "%.1f / burst %.1f dB -> %+.1f dB (%s)" % (
                    lvl["integrated"], lvl["burst"], lvl["gain_db"], lvl["limited_by"]),
                "" if "after_space_db" not in lvl else ", %+.1f dB after placement" %
                lvl["after_space_db"])
        return v, trunc

    def _allocate(self, v, may_wait):
        """Voice allocation.  Priority fg > sec > bg: a new answer takes a
        free voice, else steals (fades out over 0.25 s) the oldest background
        texture, then the oldest secondary voice; a secondary voice may only
        steal a background texture.  Without polyphony, answers wait for the
        previous answer (the v0.2/v0.3 behaviour).  Returns True if added."""
        pc = self.pcfg
        while not self.stop_ev.is_set():
            act = self.mixer.active()
            if not pc["polyphony"]:
                if not [x for x in act if x.role == "fg"]:
                    break
            elif len(act) < pc["max_voices"]:
                break
            else:
                order = ("bg", "sec") if v.role == "fg" else (("bg",) if v.role == "sec" else ())
                victim = None
                for role in order:
                    cands = [x for x in act if x.role == role]
                    if cands:
                        victim = min(cands, key=lambda x: x.t_created)
                        break
                if victim is not None:
                    victim.fade_out(KILL_FADE_S)
                    self.c["voices_stolen"] += 1
                    self.log("voice %d (%s, %s) faded out to make room for %s" %
                             (victim.id, ROLE_NAMES[victim.role], victim.name, v.name))
                    break
            if not may_wait:
                return False
            time.sleep(0.05)
        if self.stop_ev.is_set():
            return False
        self.mixer.add(v)
        return True

    def _play_loop(self):
        try:
            while not self.stop_ev.is_set():
                job = self.play_q.get(0.2)
                if job is None:
                    continue
                self._check_fault("play")
                age = time.time() - job.t["end"]
                if age > STALE_RESPONSE_S:
                    self._dropped(job, "stale: %.0f s after the phrase ended" % age)
                    continue
                if job.kind == "recall":
                    name = job.action_name
                elif job.kind == "recall_transform" and job.used != "passthrough":
                    name = "%s on %s" % (DISPLAY_NAMES.get(job.used, job.used), job.source_id)
                else:
                    name = DISPLAY_NAMES.get(job.used, job.used)
                v, trunc = self._make_voice(job.answer, job.answer_sr, "fg", name,
                                            corpus=job.source_corpus if job.kind == "recall"
                                            else None)
                if trunc:
                    self.log("job %s answer %s (Max_response_s %.1f s + %.1f s grace, cut at "
                             "a quiet point, faded)" % (job.tag, v.shape if v is not None else
                                                        "trimmed", self.a.max_response,
                                                        TAIL_GRACE_S), True)
                out_s = v.n / float(self.sr) if v is not None else 0.0
                if v is not None:
                    v.item_id = job.source_id or job.phrase_id or None
                # keep the latest answers as material for the background layer
                if job.answer is not None:
                    m = job.answer.mean(axis=1) if job.answer.ndim == 2 else job.answer
                    self.recent_answers.append((m[:int(15 * job.answer_sr)].astype(self.np.float32),
                                                job.answer_sr, "answer %s" % job.tag))
                played = False
                if self.a.play and v is not None:
                    played = self._allocate(v, may_wait=True)
                job.t["play_start"] = time.time()
                if played:
                    self.log("job %s: voice %d '%s' at %+.2f, %s" %
                             (job.tag, v.id, name, v.center, v.shape), True)
                    sec = job.secondary
                    if sec is not None:
                        sv, _ = self._make_voice(sec["audio"], sec["sr"], "sec", sec["name"],
                                                 wait_s=sec["delay"], gain_db=sec["gain_db"],
                                                 corpus=sec.get("corpus"))
                        if sv is not None:
                            sv.item_id = sec.get("item_id")
                        if sv is not None and self._allocate(sv, may_wait=False):
                            self.c["voices_secondary"] += 1
                            self.log("job %s: secondary voice %d '%s' at %+.2f enters after "
                                     "%.2f s, %s / %s" % (job.tag, sv.id, sv.name, sv.center,
                                                          sec["delay"], sec.get("shape", "whole"),
                                                          sv.shape), True)
                        elif sv is not None:
                            self.log("job %s: no free voice for the secondary layer - skipped" %
                                     job.tag)
                elif self.stop_ev.is_set():
                    self.log("job %s interrupted by stop" % job.tag, True)
                self.t_activity = time.time()
                delay = job.t["play_start"] - job.t["end"]
                self.delays.append(delay)
                self.c["done"] += 1
                self.c["kind_" + job.kind] += 1
                self.summary.append("%s  %-34s in %5.2f s -> out %5.2f s   delay %5.2f s%s" % (
                    job.tag, name, len(job.audio) / job.sr, out_s, delay,
                    "" if v is None else "   pan %+.2f" % v.center))
                tt = job.t

                def rel(k):
                    return ("%.3f" % (tt[k] - tt["end"])) if k in tt else "-"
                self.log("job %s TIMING rel. to phrase end: onset %s | analysed %s | render %s..%s"
                         " | play start %s  (phrase end -> answer %.3f s)" %
                         (job.tag, rel("onset"), rel("analysed"), rel("render_start"),
                          rel("render_end"), rel("play_start"), delay))
                self._cleanup_job(job)
                job.answer = job.recall_item = job.secondary = None
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "playback worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    # ---------------- AMBIENT thread (v0.4.0) ----------------
    def _bg_material(self):
        """Candidate material for the background: stored sounds of the
        enabled corpora (sustained ones preferred) and the latest answers.
        Reads a SNAPSHOT of the corpus lists (the brain thread owns them);
        an item evicted meanwhile is simply skipped."""
        np = self.np
        out = []
        mem = self.memory
        if self.mcfg["enabled"]:
            w = mem.corpus_weights(0.5)
            for corp in ("B", "A", "C"):
                if w[corp] <= 0:
                    continue
                for it in list(mem.items[corp]):
                    if it.id in self.bg_recent or it.duration < 1.5 or it.F is None:
                        continue
                    sustained = it.F.get("perc_char", 0.5) < 0.45
                    out.append((it.id, it, w[corp] * (1.6 if sustained else 0.6)))
        for m, sr, label in list(self.recent_answers):
            if label not in self.bg_recent and len(m) >= int(1.5 * sr):
                out.append((label, (m, sr), 20.0))
        return out

    def _new_texture(self):
        np = self.np
        rng = self.prng
        cands = self._bg_material()
        if not cands:
            return None
        picks = []
        for _ in range(min(2, len(cands))):
            tot = sum(c[2] for c in cands)
            x = rng.random() * tot
            for c in cands:
                x -= c[2]
                if x <= 0:
                    picks.append(c)
                    cands = [d for d in cands if d is not c]
                    break
        sources = []
        for label, obj, _ in picks:
            if isinstance(obj, tuple):
                sources.append(obj)
            else:
                a = obj.audio
                if a is None:
                    try:
                        a = obj.get_audio() if obj.src else None
                    except Exception:                        # noqa: BLE001
                        a = None
                if a is None:
                    continue
                sources.append((a.mean(axis=1) if a.ndim == 2 else a, obj.sr))
            self.bg_recent.append(label)
        if not sources:
            return None
        secs = rng.uniform(20.0, 32.0)
        tex = build_texture(sources, self.sr, secs, self.pcfg["width"],
                            max(0.3, self.pcfg["movement"]), rng)
        if tex is None:
            return None
        from_c = any(not isinstance(p[1], tuple) and p[1].corpus == "C" for p in picks)
        off = self._level_offset("C" if from_c else None)
        if self.pcfg["level_match"]:
            tex, _ = level_match(tex, self.pcfg["bg_db"] + off, max_boost_db=18.0, peak_ceiling=0.5,
                                 sr=self.sr)
        elif off:
            tex = (tex * 10 ** (off / 20.0)).astype(self.np.float32)
        name = "texture from " + " + ".join(p[0] for p in picks)
        v = Voice(tex, "bg", name, 0.0, gain=0.0, rate=1.0 / 3.0)
        return v

    def _ambient_loop(self):
        """Keeps the space alive and balanced: a quiet background texture made
        from the performance's own material whenever there is material; it
        recedes (-9 dB) while the performer plays or when two answers sound,
        -4.5 dB under one answer, and comes back over ~1.5 s.  Secondary
        voices dip -4.5 dB while the performer plays.  A new texture starts
        3.5 s before the current one ends (they crossfade)."""
        pc = self.pcfg
        try:
            while not self.stop_ev.is_set():
                time.sleep(0.1)
                self._check_fault("ambient")
                self.mixer.sweep()
                act = self.mixer.active()
                fg = [v for v in act if v.role == "fg"]
                bg = [v for v in act if v.role == "bg"]
                perf = time.time() - self.t_performer < 1.0
                duck = 1.0
                if perf or len(fg) >= 2:
                    duck = 0.35
                elif len(fg) == 1:
                    duck = 0.6
                # the microphone hears the speakers strongly (the leakage
                # warning level): a continuous background would be heard as a
                # performer - it pauses (2 s fade), resumes below -23 dB
                if self.leak_db is not None and self.leak_db > -20:
                    self.bg_paused = True
                elif self.leak_db is None or self.leak_db < -23:
                    self.bg_paused = False
                if self.bg_paused:
                    for v in bg:
                        v.fade_out(2.0)
                    if pc["background"]:
                        self.bg_state = "paused (microphone hears the speakers)"
                    continue
                for v in bg:
                    v.target = duck
                    v.rate = 0.5
                for v in act:
                    if v.role == "sec":
                        v.target = 0.6 if perf else 1.0
                        v.rate = 1.0
                if not (pc["background"] and self.a.play):
                    continue
                since = time.time() - self.t_texture
                # a new texture: crossfade near the end of the current one, or
                # after a taken-over one - but never more than one per 8 s (4 s
                # when there is none at all): no thrashing under dense answers
                need = (not bg and since > 4.0) or \
                    (bg and min(v.remaining_s(self.sr) for v in bg) < 3.5 and since > 8.0)
                if need and len(act) < pc["max_voices"]:
                    v = self._new_texture()
                    if v is None:
                        if not bg:
                            self.bg_state = "waiting for material"
                        continue
                    v.target = duck
                    self.mixer.add(v)
                    self.t_texture = time.time()
                    self.c["textures"] += 1
                    self.log("background: voice %d %s (%.0f s)" %
                             (v.id, v.name, v.n / float(self.sr)), True)
                    bg = bg + [v]
                if bg:
                    self.bg_state = "on" if duck >= 0.99 else "receding"
        except Exception as ex:                              # noqa: BLE001
            import traceback
            self.fatal = "ambient worker failed: %s" % ex
            self.log(self.fatal + " | " + traceback.format_exc().replace("\n", " | "), True)
            self.stop_ev.set()

    # ---------------- status ----------------
    def status_pairs(self, final=False):
        lk = "none" if self.leak_db is None else fnum(self.leak_db, 1)
        mc = self.memory.counts()
        act = self.mixer.active()
        nfg = [v for v in act if v.role == "fg"]
        nsec = sum(1 for v in act if v.role == "sec")
        nbg = sum(1 for v in act if v.role == "bg")
        playing = " + ".join(v.name for v in nfg)
        return [
            ("state", self.state), ("stage", self.stage), ("mode", "continuous"),
            ("memory", "on" if self.mcfg["enabled"] else "off"),
            ("listening", "on" if (self.state == "running" and not final) else "off"),
            ("phrase", 1 if self.det.state == "PHRASE" else 0),
            ("processing", self.processing), ("playing", playing),
            ("voices", len(act)), ("voices_fg", len(nfg)), ("voices_sec", nsec),
            ("voices_bg", nbg), ("max_voices", self.pcfg["max_voices"]),
            ("background", self.bg_state if self.pcfg["background"] else "off"),
            ("bg_gain", fnum(max([v.gain for v in act if v.role == "bg"] or [0.0]), 3)),
            ("polyphony", "on" if self.pcfg["polyphony"] else "off"),
            ("level_offset", "off" if self.follower is None else fnum(self.follower.offset, 1)),
        ] + self._det_pairs() + [
            ("graph", "off" if self.graph is None else self.graph_file_ver),
            ("pending", len(self.phrase_q) + len(self.render_q) + len(self.play_q)),
            ("pending_render", len(self.render_q)), ("pending_play", len(self.play_q)),
            ("phrases", self.c["phrases"]), ("done", self.c["done"]),
            ("dropped", self.c["dropped"]), ("failed", self.c["failed"]),
            ("leak_discarded", self.c["leak_discarded"]), ("overruns", self.c["overruns"]),
            ("input_status", self.c["input_status"]), ("output_status", self.c["output_status"]),
            ("input_db", fnum(self.input_db, 1)), ("leak_db", lk),
            ("leak_warning", 1 if (self.leak_db is not None and self.leak_db > -20) else 0),
            ("mem_live", mc["A"]), ("mem_processed", mc["B"]), ("mem_preloaded", mc["C"]),
            ("mem_audio_min", fnum(self.memory.ram_seconds() / 60.0, 1)),
            ("recall", self.last_recall), ("match", self.last_match),
            ("action", self.last_action),
            ("message", self.message), ("uptime", fnum(time.time() - self.t_start, 1)),
            ("heartbeat", "%.3f" % time.time()),
        ]

    def _det_pairs(self):
        """v0.4.10: what the phrase detector is doing, in its own terms."""
        d = self.det
        if d.floor is None:
            return [("det_state", d.state.lower())]
        on, off = d.thresholds()
        quiet = d.silent_run * d.hop_s if d.state == "PHRASE" else 0.0
        lab, t = self.det_event
        return [("det_state", d.state.lower()), ("floor_db", fnum(d.floor, 1)),
                ("on_db", fnum(on, 1)), ("off_db", fnum(off, 1)),
                ("quiet_s", fnum(quiet, 1)), ("end_silence", fnum(d.end_silence, 1)),
                ("det_event", lab), ("det_event_age", fnum(time.time() - t, 1) if lab else "")]

    def write_status(self, final=False):
        """v0.3.2: status.txt is replaced atomically.  On Windows the rename
        fails while Praat has the file open (sharing violation); that is
        retried briefly, and if it still fails the update is skipped - the
        next one follows 0.1 s later.  A failure streak is logged once with
        its cause and once when it ends; the count goes to the summary.
        The FINAL status (Praat waits for it) is retried for up to 5 s."""
        path = os.path.join(self.session, "status.txt")
        tries = 250 if final else 5
        err = None
        for _ in range(tries):
            try:
                write_kv_atomic(path, self.status_pairs(final))
                if self.status_fail_streak:
                    self.log("status file writable again after %d failed update(s)" %
                             self.status_fail_streak, True)
                    self.status_fail_streak = 0
                return True
            except OSError as ex:                          # PermissionError = locked
                err = ex
                if not os.path.isdir(self.session):
                    break
                time.sleep(0.02)
        try:
            os.remove(path + ".tmp")                       # never leave a half file
        except OSError:
            pass
        self.c["status_write_failures"] += 1
        if self.status_fail_streak == 0:
            self.log("WARNING: status update failed (%s: %s) - retrying with the next update" %
                     (type(err).__name__, err), True)
        self.status_fail_streak += 1
        return False

    # ---------------- main ----------------
    def run(self):
        sd = self.sd
        a = self.a
        self.write_status()
        if not self.renderer.find():
            return self.finish("error", self.renderer.error)
        self.log("Praat renderer: %s (version %d, flags %s)" %
                 (self.renderer.exe, self.renderer.version, " ".join(self.renderer.flags)), True)
        if self.mcfg["enabled"] and self.mcfg["use_C"] and a.corpus_c not in ("", "none"):
            def progress(msg):
                self.message = msg
                self.write_status()
                if os.path.exists(os.path.join(self.session, "stop.request")):
                    raise KeyboardInterrupt
            try:
                n, notes = index_preloaded(a.corpus_c, self.memory, self.mcfg, progress, self.log)
            except KeyboardInterrupt:
                return self.finish("stopped", "stopped while indexing the preloaded corpus")
            for nt in notes:
                self.log(nt, True)
            self.log("Corpus C indexed: %d sounds (%.1f min of audio in RAM)" %
                     (n, self.memory.ram_seconds() / 60.0), True)
            if self.graph is not None and n:
                self.message = "drawing the memory map of the preloaded corpus"
                self.write_status()
                t0 = time.perf_counter()
                self.graph.link(self.memory.items["C"], pool=self.memory.items["C"])
                self.log("memory map: %d corpus links in %.2f s" % (
                    sum(len(v) for v in self.graph.nb.values()), time.perf_counter() - t0), True)
            self.message = ""
        try:
            in_dev = resolve_device(sd, a.device, "input")
            out_dev = resolve_device(sd, a.output_device, "output")
            info = (sd.query_devices(out_dev) if out_dev is not None
                    else sd.query_devices(kind="output"))
            self.out_ch = 2 if int(info.get("max_output_channels", 2)) >= 2 else 1
            self.in_stream = sd.InputStream(samplerate=self.sr, channels=self.ch, dtype="float32",
                                            blocksize=self.det.hop, device=in_dev,
                                            callback=self._in_cb)
            self.out_stream = sd.OutputStream(samplerate=self.sr, channels=self.out_ch,
                                              dtype="float32", blocksize=self.det.hop,
                                              device=out_dev, callback=self._out_cb)
        except Exception as ex:                              # noqa: BLE001
            return self.finish("error", "cannot open audio devices: %s" % ex)
        threads = [threading.Thread(target=f, name=n, daemon=True) for f, n in (
            (self._detect_loop, "detect"), (self._brain_loop, "brain"),
            (self._render_loop, "render"), (self._play_loop, "play"),
            (self._ambient_loop, "ambient"))]
        reason, state = "", "stopped"
        try:
            self.in_stream.start()
            self.out_stream.start()
        except Exception as ex:                              # noqa: BLE001
            self._close_streams()
            return self.finish("error", "cannot start audio streams: %s" % ex)
        for t in threads:
            t.start()
        self.state, self.stage = "running", "running"
        self._graph_publish()
        self.log("engine running: in %s / out %s (%d ch), %d Hz, pending<=%d, responses<=%d, "
                 "overflow %s, max response %.1f s, leakage guard %s, sonic memory %s (%s, %s), "
                 "seed %d" % (a.device, a.output_device, self.out_ch, self.sr, a.max_pending,
                              a.max_responses, a.overflow, a.max_response,
                              "on" if a.leak_guard else "off",
                              "on" if self.mcfg["enabled"] else "off", a.response_mode,
                              a.sim_mode, self.memory.seed), True)
        pc = self.pcfg
        self.log("playback: polyphony %s, max voices %d, density %.2f, width %.2f, movement %.2f, "
                 "pan variation %.2f, fades %.0f/%.0f ms, transients %s, level matching %s, "
                 "background %s (%.0f dB)" % (
                     "on" if pc["polyphony"] else "off", pc["max_voices"], pc["density"],
                     pc["width"], pc["movement"], pc["pan_variation"], 1000 * pc["fade_in"],
                     1000 * pc["fade_out"], "kept" if pc["transients"] else "faded",
                     "on" if pc["level_match"] else "off",
                     "on" if pc["background"] else "off", pc["bg_db"]), True)
        self.log("influence memory: depth %d, decay %.2f, trend %.2f, half-life %.0f s" % (
            self.inf_depth, self.inf_decay, self.inf_trend, INFLUENCE_HALF_LIFE_S), True)
        self.log("layers: %s sounds; playback cap %.1f s + %.1f s grace; Corpus B keeps "
                 "whole answers" % (pc["layer_shape"], a.max_response, TAIL_GRACE_S), True)
        self.log("level: follow live input %s, Corpus C balance %+.1f dB" % (
            "off" if self.follower is None else "on (+-%.0f dB)" % self.follower.range,
            pc["corpus_c_db"]), True)
        stop_file = os.path.join(self.session, "stop.request")
        alive_file = os.path.join(self.session, "praat_alive.txt")
        t_last_status = 0.0
        try:
            while True:
                time.sleep(0.05)
                now = time.time()
                if self.fatal:
                    reason, state = self.fatal, "error"
                elif os.path.exists(stop_file):
                    reason = "stopped by the user"
                elif a.heartbeat:
                    try:
                        beat = os.path.getmtime(alive_file)
                    except OSError:
                        beat = self.t_start
                    if now - beat > HEARTBEAT_TIMEOUT_S:
                        reason = "Praat stopped responding (no heartbeat for %.0f s)" % (now - beat)
                if not reason and a.session_minutes > 0 and now - self.t_start > 60 * a.session_minutes:
                    reason = "session length reached (%.0f min)" % a.session_minutes
                if (not reason and a.idle_stop > 0 and now - self.t_activity > a.idle_stop
                        and self.det.state != "PHRASE" and not self.processing
                        and not self.mixer.active("fg") and len(self.phrase_q) + len(self.render_q)
                        + len(self.play_q) == 0):
                    reason = "no phrase for %.0f s" % a.idle_stop
                if not reason:
                    try:
                        if not self.in_stream.active:
                            reason, state = "audio input stream stopped", "error"
                        elif not self.out_stream.active:
                            reason, state = "audio output stream stopped", "error"
                    except Exception:                        # noqa: BLE001
                        pass
                    if not reason and not all(t.is_alive() for t in threads):
                        reason, state = (self.fatal or "a worker thread ended unexpectedly"), "error"
                if reason:
                    break
                if now - t_last_status >= 0.1:
                    self._graph_write(now)
                    self.write_status()
                    t_last_status = now
        except KeyboardInterrupt:
            reason = "interrupted"
        # ---- STOP REQUESTED -> WORKERS STOPPED ----
        self.state, self.stage, self.message = "stopping", "stop_requested", reason
        self.write_status()
        # v0.4.0: fade the whole mix out before anything stops - no click
        self.mixer.fade_all(STOP_FADE_S)
        t_f = time.time()
        while self.mixer.master > 1e-4 and time.time() - t_f < STOP_FADE_S + 0.3:
            try:
                if self.out_stream is None or not self.out_stream.active:
                    break
            except Exception:                                # noqa: BLE001
                break
            time.sleep(0.02)
        time.sleep(0.03)
        self.stop_ev.set()
        for q_ in (self.phrase_q, self.render_q, self.play_q):
            q_.close()
        self.renderer.kill()                             # only our own Praat child
        for t in threads:
            t.join(5)
        alive = [t.name for t in threads if t.is_alive()]
        if alive:
            self.renderer.kill()
            for t in threads:
                t.join(5)
            alive = [t.name for t in threads if t.is_alive()]
        self.stage = "workers_stopped"
        self._close_streams()
        if self.det.state == "PHRASE":
            self.log("phrase in progress at stop was not processed", True)
        for q_, what in ((self.phrase_q, "unanalysed"), (self.render_q, "unrendered"),
                         (self.play_q, "unplayed")):
            for job in q_.drain():
                self.c["dropped"] += 1
                self.log("job %s %s at stop - not played" % (job.tag, what), True)
                self._cleanup_job(job)
        if alive:
            self.log("WARNING: worker(s) still alive after 10 s: %s" % ", ".join(alive), True)
        return self.finish(state, reason)

    def _close_streams(self):
        for name in ("in_stream", "out_stream"):
            s = getattr(self, name, None)
            if s is None:
                continue
            try:
                s.stop()
            except Exception:                                # noqa: BLE001
                pass
            try:
                s.close()
            except Exception:                                # noqa: BLE001
                pass
            setattr(self, name, None)

    def finish(self, state, reason):
        """FILE HANDLES CLOSED -> engine temp deleted.  Everything the engine
        created is removed here; only the small hand-over files the Praat GUI
        still reads remain, and Praat's cleanup removes those and the folder."""
        self.state, self.message = state, reason
        self.log("%s: %s" % (state.upper(), reason), True)
        np = self.np
        mc = self.memory.counts()
        lines = ["state=" + state, "reason=" + reason]
        lines.append("phrases=%d answers=%d dropped=%d failed=%d passthrough=%d "
                     "leak_discarded=%d overruns=%d input_status=%d output_status=%d" % (
                         self.c["phrases"], self.c["done"], self.c["dropped"], self.c["failed"],
                         self.c["passthrough"], self.c["leak_discarded"], self.c["overruns"],
                         self.c["input_status"], self.c["output_status"]))
        lines.append("status_write_failures=%d" % self.c["status_write_failures"])
        lines.append("detector gradual_entries=%d steady_background=%d background_releases=%d "
                     "false_triggers=%d final_floor=%s" % (
            self.det.gradual_entries, self.det.steady_learned, self.det.background_releases,
            self.det.false_triggers,
            "none" if self.det.floor is None else fnum(self.det.floor, 1)))
        lines.append("memory live=%d processed=%d preloaded=%d answers transform=%d recall=%d "
                     "recall_transform=%d silent=%d evicted=%d" % (
                         mc["A"], mc["B"], mc["C"], self.c["kind_transform"],
                         self.c["kind_recall"], self.c["kind_recall_transform"],
                         self.c["kind_silence"], self.memory.evicted))
        mx = self.mixer
        fo = self.follower
        lines.append("playback voices_max=%d secondary=%d textures=%d stolen=%d peak=%.3f "
                     "limiter_max_reduction=%.1f dB follow=%s corpus_c=%+.1f dB "
                     "trimmed=%d layer_excerpts=%d peak_after_placement=%d" % (
                         mx.max_active, self.c["voices_secondary"], self.c["textures"],
                         self.c["voices_stolen"], mx.peak_out, mx.max_reduction_db,
                         "off" if fo is None else "%+.1f dB (%d counted, %d excluded)" % (
                             fo.offset, fo.counted, fo.excluded),
                         self.pcfg["corpus_c_db"], self.c["voices_trimmed"],
                         self.c["layers_excerpt"], self.c["voices_peak_trimmed"]))
        if self.delays:
            d = np.array(self.delays)
            lines.append("delay phrase end -> answer: mean %.2f s, min %.2f s, max %.2f s" %
                         (d.mean(), d.min(), d.max()))
        if self.leak_db is not None:
            lines.append("leakage estimate %.1f dB" % self.leak_db)
        lines += ["answer " + s for s in self.summary]
        lines += ["event " + e.strip() for e in self.events]
        if state == "error":                 # engine_stderr.txt is deleted below
            try:
                with open(os.path.join(self.session, "engine_stderr.txt"), encoding="utf-8",
                          errors="replace") as fh:
                    lines += ["stderr " + l for l in fh.read().strip().splitlines()[-6:]]
            except OSError:
                pass
        # release memory and every handle we own
        self.memory.clear()
        if self.log_fh:
            for l in lines[:5]:
                self.log("SUMMARY " + l)
            try:
                self.log_fh.close()
            except OSError:
                pass
            self.log_fh = None
        try:
            if sys.stderr is not None and getattr(sys.stderr, "name", "").endswith("engine_stderr.txt"):
                f = sys.stderr
                sys.stderr = open(os.devnull, "w")
                f.close()
        except Exception:                                    # noqa: BLE001
            pass
        self.stage = "handles_closed"
        # delete every engine-owned file in the session (bounded retries)
        left = []
        try:
            for n in os.listdir(self.session):
                if n in PRAAT_OWNED:
                    continue
                p = os.path.join(self.session, n)
                ok = False
                for _ in range(20):
                    try:
                        if os.path.isdir(p):
                            ok = not remove_tree(p, 4, 0.05)
                        else:
                            os.remove(p)
                            ok = True
                        break
                    except OSError:
                        time.sleep(0.1)
                if not ok and os.path.exists(p):
                    left.append(n)
        except OSError:
            pass
        lines.insert(2, "engine_files_left=%d%s" % (len(left), (" " + ";".join(left)) if left else ""))
        self.stage = "engine_temp_deleted" if not left else "engine_temp_incomplete"
        try:
            write_text_atomic(os.path.join(self.session, "summary.txt"), "\n".join(lines) + "\n")
        except OSError:
            pass
        self.write_status(final=True)
        return 0 if state != "error" else 1


def cmd_serve(args):
    global MAX_RESPONSE_S
    MAX_RESPONSE_S = float(args.max_response)
    if not os.path.isdir(args.session):
        return 1                      # session already removed by Praat
    try:
        _boot_status(args.session, "starting", "loading numpy / scipy")
        import_dsp()
        _boot_status(args.session, "starting", "loading soundfile / sounddevice")
        import soundfile                                     # noqa: F401
        import sounddevice as sd
        _boot_status(args.session, "starting", "finding a Praat executable for rendering")
        if (not os.path.isdir(args.session) or
                os.path.exists(os.path.join(args.session, "stop.request"))):
            return 1                  # Praat gave up (or stopped) while we were loading
    except Exception as ex:                                  # noqa: BLE001
        write_kv_retry(os.path.join(args.session, "status.txt"),
                        [("state", "error"), ("message", "missing Python package: %s" % ex)])
        return 1
    eng = None
    try:
        eng = Engine(args, sd)
        rc = eng.run()
    except Exception as ex:                                  # noqa: BLE001
        import traceback
        rc = 1
        msg = "engine crashed: %s | %s" % (ex, traceback.format_exc().replace("\n", " | ")[-500:])
        if eng is not None:
            try:
                eng.stop_ev.set()
                eng.renderer.kill()
                eng._close_streams()
                eng.finish("error", msg)
            except Exception:                                # noqa: BLE001
                pass
        try:
            write_kv_retry(os.path.join(args.session, "status.txt"),
                            [("state", "error"), ("message", msg)])
        except OSError:
            pass
    abandoned = eng is not None and eng.message.startswith("Praat stopped responding")
    pending = os.path.exists(os.path.join(args.session, "cleanup.pending"))
    if abandoned or pending:
        # nobody is left to clean up (Praat gone), or Praat's cleanup found
        # this engine still running and deleted NOTHING: the engine is the
        # owner, it is about to exit, so it removes its own session now
        try:
            if sys.stderr is not None and getattr(sys.stderr, "name", "").endswith(".txt"):
                f = sys.stderr
                sys.stderr = open(os.devnull, "w")
                f.close()
        except Exception:                                    # noqa: BLE001
            pass
        time.sleep(0.5)
        if safe_session_dir(args.session):
            remove_tree(args.session)
    return rc


# ============================================================
def main(argv=None):
    ap = argparse.ArgumentParser(description="AudioTools Call & Response engine")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("probe")
    p.add_argument("--out", required=True)
    p.add_argument("--live", action="store_true")
    p = sub.add_parser("devices")
    p.add_argument("--out", required=True)
    for name in ("listen", "analyze"):
        p = sub.add_parser(name)
        p.add_argument("--session", required=True)
        p.add_argument("--cycle", required=True)
        p.add_argument("--force", default="auto")
        p.add_argument("--max-response", dest="max_response", type=float, default=20.0)
        if name == "analyze":
            p.add_argument("--input", required=True)
        else:
            p.add_argument("--device", default="default")
            p.add_argument("--sr", type=float, default=44100)
            p.add_argument("--channels", type=int, default=1)
            p.add_argument("--sensitivity", type=float, default=9.0)
            p.add_argument("--min-phrase", dest="min_phrase", type=float, default=0.5)
            p.add_argument("--end-silence", dest="end_silence", type=float, default=0.6)
            p.add_argument("--max-phrase", dest="max_phrase", type=float, default=12.0)
            p.add_argument("--preroll", type=float, default=0.25)
            p.add_argument("--timeout", type=float, default=30.0)
    p = sub.add_parser("serve")
    p.add_argument("--session", required=True)
    p.add_argument("--script", required=True, help="AudioTools_CallResponse.praat (render mode)")
    p.add_argument("--praat", default="none", help="Praat executable or its folder")
    p.add_argument("--plugin-root", dest="plugin_root", required=True)
    p.add_argument("--force", default="auto")
    p.add_argument("--device", default="default")
    p.add_argument("--output-device", dest="output_device", default="default")
    p.add_argument("--sr", type=float, default=44100)
    p.add_argument("--channels", type=int, default=1)
    p.add_argument("--sensitivity", type=float, default=9.0)
    p.add_argument("--min-phrase", dest="min_phrase", type=float, default=0.5)
    p.add_argument("--end-silence", dest="end_silence", type=float, default=0.6)
    p.add_argument("--max-phrase", dest="max_phrase", type=float, default=12.0)
    p.add_argument("--preroll", type=float, default=0.25)
    p.add_argument("--max-pending", dest="max_pending", type=int, default=3)
    p.add_argument("--max-responses", dest="max_responses", type=int, default=3)
    p.add_argument("--overflow", default="drop_oldest", choices=["drop_oldest", "drop_newest"])
    p.add_argument("--max-response", dest="max_response", type=float, default=20.0)
    p.add_argument("--session-minutes", dest="session_minutes", type=float, default=60.0)
    p.add_argument("--idle-stop", dest="idle_stop", type=float, default=300.0)
    p.add_argument("--leak-guard", dest="leak_guard", type=int, default=1)
    p.add_argument("--play", type=int, default=1)
    p.add_argument("--heartbeat", type=int, default=1,
                   help="stop when the Praat GUI stops writing praat_alive.txt")
    p.add_argument("--debug-log", dest="debug_log", default="none")
    # ---- v0.3.0 sonic memory ----
    p.add_argument("--memory", type=int, default=1)
    p.add_argument("--response-mode", dest="response_mode", default="hybrid",
                   choices=["transform", "recall", "recall_transform", "hybrid", "corpus_only"])
    p.add_argument("--use-a", dest="use_a", type=int, default=1)
    p.add_argument("--use-b", dest="use_b", type=int, default=1)
    p.add_argument("--use-c", dest="use_c", type=int, default=0)
    p.add_argument("--corpus-c", dest="corpus_c", default="none")
    p.add_argument("--sim-mode", dest="sim_mode", default="hybrid",
                   choices=["hybrid", "timbre", "pitch", "rhythm", "envelope", "contrast"])
    p.add_argument("--min-sim", dest="min_sim", type=float, default=0.45)
    p.add_argument("--w-live", dest="w_live", type=float, default=40.0)
    p.add_argument("--w-processed", dest="w_processed", type=float, default=30.0)
    p.add_argument("--w-preloaded", dest="w_preloaded", type=float, default=30.0)
    p.add_argument("--p-transform", dest="p_transform", type=float, default=40.0)
    p.add_argument("--p-recall", dest="p_recall", type=float, default=30.0)
    p.add_argument("--p-recall-transform", dest="p_recall_transform", type=float, default=30.0)
    p.add_argument("--max-generation", dest="max_generation", type=int, default=2)
    p.add_argument("--max-live", dest="max_live", type=int, default=100)
    p.add_argument("--max-processed", dest="max_processed", type=int, default=100)
    p.add_argument("--max-ram-min", dest="max_ram_min", type=float, default=30.0)
    p.add_argument("--max-item-s", dest="max_item_s", type=float, default=15.0)
    p.add_argument("--candidates", type=int, default=5)
    p.add_argument("--evolving", type=int, default=0)
    p.add_argument("--layered", type=int, default=0)
    p.add_argument("--recent-exclude", dest="recent_exclude", type=int, default=2)
    p.add_argument("--cooldown", type=int, default=4)
    p.add_argument("--same-family", dest="same_family", type=int, default=0)
    p.add_argument("--c-max-items", dest="c_max_items", type=int, default=300)
    p.add_argument("--c-max-files", dest="c_max_files", type=int, default=200)
    p.add_argument("--c-max-per-file", dest="c_max_per_file", type=int, default=20)
    p.add_argument("--c-min-item-s", dest="c_min_item_s", type=float, default=0.5)
    p.add_argument("--seed", type=int, default=0)
    # ---- v0.4.0 polyphonic spatial playback ----
    p.add_argument("--polyphony", type=int, default=1)
    p.add_argument("--max-voices", dest="max_voices", type=int, default=4)
    p.add_argument("--density", type=float, default=0.5)
    p.add_argument("--stereo-width", dest="stereo_width", type=float, default=1.0)
    p.add_argument("--movement", type=float, default=0.3)
    p.add_argument("--pan-variation", dest="pan_variation", type=float, default=0.5)
    p.add_argument("--fade-in-ms", dest="fade_in_ms", type=float, default=30.0)
    p.add_argument("--fade-out-ms", dest="fade_out_ms", type=float, default=400.0)
    p.add_argument("--preserve-transients", dest="preserve_transients", type=int, default=1)
    p.add_argument("--level-match", dest="level_match", type=int, default=1)
    p.add_argument("--background", type=int, default=1)
    p.add_argument("--background-db", dest="background_db", type=float, default=-33.0)
    # ---- v0.4.1 adaptive level ----
    p.add_argument("--follow-input", dest="follow_input", type=int, default=0)
    p.add_argument("--follow-range", dest="follow_range", type=float, default=9.0)
    p.add_argument("--corpus-c-db", dest="corpus_c_db", type=float, default=0.0)
    # ---- v0.4.5 ----
    p.add_argument("--layer-shape", dest="layer_shape", default="whole",
                   choices=["whole", "excerpt"])
    # ---- v0.4.8 ----
    p.add_argument("--influence-depth", dest="influence_depth", type=int, default=3)
    p.add_argument("--influence-decay", dest="influence_decay", type=float, default=0.5)
    p.add_argument("--trend-weight", dest="trend_weight", type=float, default=0.0)
    p = sub.add_parser("cleanup")
    p.add_argument("--session", required=True)
    p.add_argument("--wait", type=float, default=15.0)
    p.add_argument("--report", action="store_true",
                   help="print one result line (Praat reads it with runSubprocess$)")
    p = sub.add_parser("cleanup-stale")
    p.add_argument("--base", required=True)
    p.add_argument("--report", action="store_true")
    p = sub.add_parser("self-test")
    p.add_argument("--write-dir", dest="write_dir", default="")
    args = ap.parse_args(argv)
    if getattr(args, "force", "auto") not in ["auto", ""] + TRANSFORM_IDS:
        args.force = "auto"
    fn = {"probe": cmd_probe, "devices": cmd_devices, "listen": cmd_listen, "serve": cmd_serve,
          "analyze": cmd_analyze, "cleanup": cmd_cleanup,
          "cleanup-stale": cmd_cleanup_stale, "self-test": cmd_self_test}[args.cmd]
    return fn(args)


def read_args_file(path):
    """v0.4.4: engine arguments written by Praat, one per line, closed by
    "#end" (a missing marker = incomplete file).  Lines starting with "#"
    are comments.  Praat writes ASCII / Latin-1, UTF-8 or UTF-16 (non-Latin
    characters, e.g. a Hebrew folder name): detected from the BOM, else
    UTF-8, else Latin-1.  Returns the list of arguments."""
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        text = raw.decode("utf-16")
    elif raw.startswith(b"\xef\xbb\xbf"):
        text = raw[3:].decode("utf-8")
    else:
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            text = raw.decode("latin-1")
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if "#end" not in lines:
        raise ValueError("argument file is incomplete (no #end line): %s" % path)
    lines = lines[:lines.index("#end")]
    return [l for l in lines if not l.startswith("#")]


def cmd_launch(rest):
    """v0.2.0: start the continuous engine as a DETACHED process and return
    at once.  Praat calls this with an ordinary (blocking) runSubprocess - the
    same mechanism as v0.1.3 - instead of "asynchronous runSubprocess", whose
    child never ran on a Windows test machine.  The engine gets this Python's
    absolute path, no inherited handles (stdin/stdout/stderr -> DEVNULL, so
    Praat's blocking call can finish) and its own process group."""
    if len(rest) >= 2 and rest[0] == "--args-file":
        try:
            rest = read_args_file(rest[1])
        except (OSError, ValueError) as ex:
            sys.stderr.write("launch: %s\n" % ex)
            sess = os.path.dirname(os.path.abspath(rest[1]))
            if os.path.isdir(sess):
                _boot_status(sess, "error", "cannot read the engine arguments: %s" % ex)
            return 2
    if "--session" not in rest:
        sys.stderr.write("launch: --session is required\n")
        return 2
    sess = rest[rest.index("--session") + 1]
    os.makedirs(sess, exist_ok=True)
    argv = [sys.executable, os.path.abspath(__file__), "serve"] + list(rest)
    kw = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL, close_fds=True, cwd=sess)
    if sys.platform.startswith("win"):
        # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW
        kw["creationflags"] = 0x00000008 | 0x00000200 | 0x08000000
    else:
        kw["start_new_session"] = True
    try:
        p = subprocess.Popen(argv, **kw)
    except Exception as ex:                                  # noqa: BLE001
        _boot_status(sess, "error", "cannot start the engine process: %s" % ex)
        sys.stderr.write("launch failed: %s\n" % ex)
        return 1
    try:
        write_kv_atomic(os.path.join(sess, "launch.txt"),
                        [("pid", p.pid), ("start", proc_start_token(p.pid)),
                         ("python", sys.executable)])
    except OSError:
        pass
    return 0


def _serve_boot(argv):
    """v0.2.0: the engine runs detached with NO stdout/stderr, so a start-up
    failure would be invisible.  Before
    any import or argument parsing: write status 'starting' and send stderr to
    <session>/engine_stderr.txt.  Returns the session folder or None."""
    if len(argv) < 2 or argv[1] != "serve" or "--session" not in argv:
        return None
    try:
        sess = argv[argv.index("--session") + 1]
        if not os.path.isdir(sess):
            # v0.3.0: Praat has already given up and removed the session -
            # never re-create it (no temporary file may outlive a session)
            sys.exit(0)
        sys.stderr = open(os.path.join(sess, "engine_stderr.txt"), "a",
                          encoding="utf-8", buffering=1)
        if sys.stdout is None:
            sys.stdout = sys.stderr
        _boot_status(sess, "starting", "Python %s started (%s); loading packages" %
                     (sys.version.split()[0], sys.executable))
        return sess
    except Exception:                                        # noqa: BLE001
        return None


def _boot_status(sess, state, message):
    try:
        write_kv_retry(os.path.join(sess, "status.txt"),
                        [("state", state), ("message", message),
                         ("uptime", fnum(time.perf_counter() - T_PROCESS_START, 1))])
    except Exception:                                        # noqa: BLE001
        pass


if __name__ == "__main__":
    # --self-test is accepted as an alias of the self-test command
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        sys.argv[1] = "self-test"
    if len(sys.argv) > 1 and sys.argv[1] == "launch":
        sys.exit(cmd_launch(sys.argv[2:]))
    _sess = _serve_boot(sys.argv)
    if _sess is None:
        sys.exit(main())
    try:
        _rc = main()
    except SystemExit as _ex:                                # e.g. an argument error
        if _ex.code not in (0, None):
            _boot_status(_sess, "error", "engine exited during start-up (code %s) - see "
                         "engine_stderr.txt: %s" % (_ex.code, " | ".join(
                             open(os.path.join(_sess, "engine_stderr.txt"),
                                  encoding="utf-8", errors="replace").read()
                             .strip().splitlines()[-3:])))
        raise
    except BaseException as _ex:                             # noqa: BLE001
        import traceback
        _boot_status(_sess, "error", "engine crashed: %s | %s" % (
            _ex, traceback.format_exc().replace("\n", " | ")[-600:]))
        raise
    sys.exit(_rc)
