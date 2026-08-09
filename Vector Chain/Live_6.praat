# ============================================================
# Praat AudioTools - Live 6
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Praat 7 path compatibility
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 6 processing chain
#   Flow: Record -> Phase Shaper -> Phase Modulation Matrix -> BPM Panning
#
# v1.1:
#   - Praat 7-compatible script lookup. First tries preferencesDirectory$,
#     then falls back to paths relative to this Vector Chain script.
#   - Keeps the current signatures of Phase_Shaper v0.4,
#     Phase_Modulation_Matrix v0.3 and BPM_Panning v0.4.
# ============================================================

form Live Recording - Composition 6 Settings
    positive Recording_time_seconds 5.0
endform

# ============================================================
# PART 1: RECORDING & PREPARATION
# ============================================================

Record Sound (fixed time): "Microphone", 1.0, 0.5, "44100", recording_time_seconds
recorded = selected("Sound")
Rename: "Recording_raw"

Scale peak: 0.99

Trim silences: 0.08, "yes", 100, 0, -35, 0.1, 0.05, "no", "Trim"
trimmed = selected("Sound")
Rename: "Recording"

selectObject: recorded
Remove

selectObject: trimmed

# ============================================================
# PART 2: COMPOSITION 6 (AudioTools)
# ============================================================

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")

# === GET PLUGIN PATH ===
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

overlap_sec = 0.1
final_fade_sec = 3.0

# === DEFINE SCRIPT PATHS ===
path_intro$ = pluginPath$ + "Spectral/Phase_Shaper.praat"
path_body$  = pluginPath$ + "Time & Granular/Phase_Modulation_Matrix.praat"
path_outro$ = pluginPath$ + "Spatial & Surround/BPM_Panning.praat"

# Praat 7 / script-relative fallback
if not fileReadable(path_intro$)
    path_intro$ = defaultDirectory$ + "/../Spectral/Phase_Shaper.praat"
endif
if not fileReadable(path_body$)
    path_body$ = defaultDirectory$ + "/../Time & Granular/Phase_Modulation_Matrix.praat"
endif
if not fileReadable(path_outro$)
    path_outro$ = defaultDirectory$ + "/../Spatial & Surround/BPM_Panning.praat"
endif

# Normalise Windows separators
path_intro$ = replace_regex$(path_intro$, "\\", "/", 0)
path_body$  = replace_regex$(path_body$,  "\\", "/", 0)
path_outro$ = replace_regex$(path_outro$, "\\", "/", 0)

if not fileReadable(path_intro$)
    exitScript: "Cannot find Phase_Shaper.praat"
endif
if not fileReadable(path_body$)
    exitScript: "Cannot find Phase_Modulation_Matrix.praat"
endif
if not fileReadable(path_outro$)
    exitScript: "Cannot find BPM_Panning.praat"
endif

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 6 - Phase Shaper -> Phase Mod -> BPM"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Phase Shaper)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Phase Shaper) ==="
appendInfoLine: "  Generating..."

# Phase_Shaper v0.4: 9 arguments
runScript: path_intro$, "Hyper-Dispersion (sweeping drone)", "Custom (use intensity below)", 0.8, 100, "no", "no", 0.95, "no", "no"

sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_PhaseShaper"

selectObject: sound_intro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_intro
    sound_intro = tmp
    Rename: initial_name$ + "_Part1_PhaseShaper"
endif

dur_intro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_intro, 2), " s"

selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Phase Modulation Matrix)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Phase Modulation Matrix) ==="
appendInfoLine: "  Generating..."

# Phase_Modulation_Matrix v0.3: 16 arguments
runScript: path_body$, "Default (balanced)", 5, 0.1, 0.5, "no", 0.3, 8, 2, "no", 20, 0.7, 1.1, 0.1, 0.93, "no", "no"

sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_PhaseMod"

selectObject: sound_body
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_body
    sound_body = tmp
    Rename: initial_name$ + "_Part2_PhaseMod"
endif

dur_body = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_body, 2), " s"

selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (BPM Stereo Panning)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (BPM Stereo Panning) ==="
appendInfoLine: "  Generating..."

# BPM_Panning v0.4: 11 arguments
runScript: path_outro$, 120, "1/16 (sixteenth notes)", 50, "1010100110101001", "1.  Ping-pong (hard L/R alternation)", 0.3, "Downmix to mono and pan (true panning)", "Peak (scale to target)", 0.95, 0, 0

sound_outro_raw = selected("Sound")
Rename: initial_name$ + "_Part3_Raw"

# Trim trailing silence using mono analysis, then crop the original stereo result
selectObject: sound_outro_raw
Convert to mono
sound_outro_mono = selected("Sound")
Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"
mono_trimmed_outro = selected("Sound")
trimmed_dur = Get total duration
removeObject: sound_outro_mono, mono_trimmed_outro

selectObject: sound_outro_raw
Extract part: 0, trimmed_dur, "rectangular", 1, "no"
sound_outro = selected("Sound")
Rename: initial_name$ + "_Part3_BPM"

selectObject: sound_outro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_outro
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_BPM"
endif

dur_outro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_outro, 2), " s"

removeObject: sound_outro_raw

selectObject: sound_outro
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# MIXING
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "=== Mixing Parts ==="

selectObject: sound_intro
fs = Get sampling frequency

start_1 = 0
start_2 = dur_intro - overlap_sec
start_3 = start_2 + dur_body - overlap_sec
total_dur = start_3 + dur_outro

appendInfoLine: "  Part 1 starts: ", fixed$(start_1, 2), " s"
appendInfoLine: "  Part 2 starts: ", fixed$(start_2, 2), " s"
appendInfoLine: "  Part 3 starts: ", fixed$(start_3, 2), " s"
appendInfoLine: "  Total duration: ", fixed$(total_dur, 2), " s"

# Track 1
silence_end1_dur = total_dur - dur_intro
if silence_end1_dur > 0
    Create Sound from formula: "Silence_End1", 2, 0, silence_end1_dur, fs, "0"
    silence_end1 = selected("Sound")
    selectObject: sound_intro
    plusObject: silence_end1
    Concatenate
    track1 = selected("Sound")
    Rename: "Track_1_Aligned"
    removeObject: silence_end1
else
    selectObject: sound_intro
    track1 = Copy: "Track_1_Aligned"
endif

# Track 2
Create Sound from formula: "Silence_Start2", 2, 0, start_2, fs, "0"
silence_start2 = selected("Sound")

silence_end2_dur = total_dur - (start_2 + dur_body)
if silence_end2_dur > 0
    Create Sound from formula: "Silence_End2", 2, 0, silence_end2_dur, fs, "0"
    silence_end2 = selected("Sound")
else
    Create Sound from formula: "Silence_End2", 2, 0, 0.001, fs, "0"
    silence_end2 = selected("Sound")
endif

selectObject: silence_start2
plusObject: sound_body
plusObject: silence_end2
Concatenate
track2 = selected("Sound")
Rename: "Track_2_Aligned"
removeObject: silence_start2, silence_end2

# Track 3
Create Sound from formula: "Silence_Start3", 2, 0, start_3, fs, "0"
silence_start3 = selected("Sound")
selectObject: silence_start3
plusObject: sound_outro
Concatenate
track3 = selected("Sound")
Rename: "Track_3_Aligned"
removeObject: silence_start3

appendInfoLine: "  Summing tracks..."
selectObject: track1
track2_str$ = string$(track2)
track3_str$ = string$(track3)
Formula: "self + object(" + track2_str$ + ", x) + object(" + track3_str$ + ", x)"

final_name$ = initial_name$ + "_Composition6"
Rename: final_name$
final_sound = selected("Sound")

# ==============================================================================
# FINAL MASTERING
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "=== Final Mastering ==="
appendInfoLine: "  Trimming silence..."

selectObject: final_sound
Convert to mono
mono_for_trim = selected("Sound")
Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"
mono_trimmed_final = selected("Sound")
trimmed_final_dur = Get total duration
removeObject: mono_for_trim, mono_trimmed_final

selectObject: final_sound
Extract part: 0, trimmed_final_dur, "rectangular", 1, "no"
trimmed_final = selected("Sound")
removeObject: final_sound
final_sound = trimmed_final
Rename: final_name$

appendInfoLine: "  Applying fade-out (", fixed$(final_fade_sec, 1), " s)..."
selectObject: final_sound
final_dur = Get total duration
fade_start = final_dur - final_fade_sec
if fade_start > 0
    Formula: "if x > " + string$(fade_start) + " then self * ((xmax - x) / " + string$(final_fade_sec) + ") else self fi"
endif

appendInfoLine: "  Normalizing..."
Scale peak: 0.99

# ==============================================================================
# CLEANUP
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Cleaning up intermediate files..."

nocheck removeObject: sound_intro
nocheck removeObject: sound_body
nocheck removeObject: sound_outro
nocheck removeObject: track2
nocheck removeObject: track3
nocheck removeObject: initial_sound

# ==============================================================================
# FINISH
# ==============================================================================
selectObject: final_sound
final_dur = Get total duration
final_nch = Get number of channels

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  LIVE 6 COMPOSITION COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_dur, 2), " s"
appendInfoLine: "Channels: ", final_nch
appendInfoLine: ""
appendInfoLine: "Playing..."

Erase all
selectObject: final_sound
Play
