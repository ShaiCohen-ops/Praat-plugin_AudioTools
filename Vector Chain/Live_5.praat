# ============================================================
# Praat AudioTools - Live 5
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026) - Praat 7 path compatibility
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 5 processing chain
#   Flow: Record -> Full-Wave Rectifier -> Brownian Motion -> 8-Channel Movements
#
# v1.1:
#   - Added Praat 7 / script-relative fallbacks for all child scripts.
#   - Current child-script signatures retained for Full-Wave Rectifier v0.4b,
#     Brownian Motion Texture v0.3, and 8-Channel Movements v0.5.
# ============================================================

# ============================================================
# USER FORM
# ============================================================

form Live Recording - Composition 5 Settings
    positive Recording_time_seconds 5.0
endform

# ============================================================
# PART 1: RECORDING & PREPARATION
# ============================================================

# 1. Record
Record Sound (fixed time): "Microphone", 1.0, 0.5, "44100", recording_time_seconds
recorded = selected("Sound")
Rename: "Recording_raw"

# 2. Normalize
Scale peak: 0.99

# 3. Trim Silence
Trim silences: 0.08, "yes", 100, 0, -35, 0.1, 0.05, "no", "Trim"

trimmed = selected("Sound")
Rename: "Recording"

# 4. Clean up raw file
selectObject: recorded
Remove

# 5. Select result for the next section
selectObject: trimmed

# ============================================================
# PART 2: COMPOSITION 5 (AudioTools)
# Flow: Full-Wave Rectifier -> Brownian Motion -> 8-Channel Movements
# ============================================================

# === INPUT SETUP ===
initial_sound = selected("Sound")
initial_name$ = selected$("Sound")

# === GET PLUGIN PATH ===
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

# === CONFIGURATION ===
overlap_sec = 0.1
final_fade_sec = 3.0

# === DEFINE SCRIPT PATHS ===
path_intro$ = pluginPath$ + "Distortion/Full-Wave_Rectifier_Abs.praat"
path_body$  = pluginPath$ + "Time & Granular/Brownian_Motion_Texture_Generator.praat"
path_outro$ = pluginPath$ + "Spatial & Surround/8-Channel_Movements.praat"

# Praat 7 / script-relative fallback
if not fileReadable(path_intro$)
    path_intro$ = defaultDirectory$ + "/../Distortion/Full-Wave_Rectifier_Abs.praat"
endif

if not fileReadable(path_body$)
    path_body$ = defaultDirectory$ + "/../Time & Granular/Brownian_Motion_Texture_Generator.praat"
endif

if not fileReadable(path_outro$)
    path_outro$ = defaultDirectory$ + "/../Spatial & Surround/8-Channel_Movements.praat"
endif

path_intro$ = replace_regex$(path_intro$, "\\", "/", 0)
path_body$  = replace_regex$(path_body$,  "\\", "/", 0)
path_outro$ = replace_regex$(path_outro$, "\\", "/", 0)

if not fileReadable(path_intro$)
    exitScript: "Cannot find Full-Wave_Rectifier_Abs.praat"
endif

if not fileReadable(path_body$)
    exitScript: "Cannot find Brownian_Motion_Texture_Generator.praat"
endif

if not fileReadable(path_outro$)
    exitScript: "Cannot find 8-Channel_Movements.praat"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 5 - Rectifier -> Brownian -> Movements"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Full-Wave Rectifier)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Full-Wave Rectifier) ==="
appendInfoLine: "  Generating..."

# Full-Wave Rectifier v0.4b parameters (8 args)
# Preset, Dc_handling, Output_level, Scale_peak, Show_spectrum,
# Spectrum_reference, Draw_visualization, Play_result
runScript: path_intro$, "Standard level (0.95 peak)", "Raw rectification (v0.2/v0.3)", "Normalize to target", 0.95, 0, "Match levels (isolates harmonic change)", 0, 0

# Get the output
sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_Rectifier"

# Ensure stereo
selectObject: sound_intro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_intro
    sound_intro = tmp
    Rename: initial_name$ + "_Part1_Rectifier"
endif

dur_intro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_intro, 2), " s"

# Fade Out for crossfade
selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Brownian Motion Texture Generator)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Brownian Motion Texture) ==="
appendInfoLine: "  Generating..."

# Brownian Motion Texture v0.3 parameters (17 args)
# Preset, GrainDur, OutDur, Density, TimeStep, TimeDrift, SpatialEnable,
# SpatialStep, SpatialDrift, BoundaryHandling, AmpScale, RandomPositions,
# FadeDur, FadeOut, AllowOverlap, Draw, Play
runScript: path_body$, "Dense Cloud", 0.05, 10.0, 20, 0.1, 0.0, 1, 0.15, 0.0, "Clamp (matches v0.2 — pins at edges)", 0.7, 1, 0.005, 2.0, 1, 0, 0

# Get the output
sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_Brownian"

# Ensure stereo
selectObject: sound_body
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_body
    sound_body = tmp
    Rename: initial_name$ + "_Part2_Brownian"
endif

dur_body = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_body, 2), " s"

# Fade In for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# Fade Out for crossfade
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (8-Channel Spatial Movements)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (8-Channel Movements) ==="
appendInfoLine: "  Generating..."

# 8-Channel Spatial Movements v0.5 parameters (16 args)
# Pattern, Motion_speed, Frequency_hz, Fadein_time, Exponent, Path_radius,
# Source_focus, Custom_x, Custom_y, Floor_db, Scale_peak, Number_of_points,
# Random_seed, Output_format, Draw_visualization, Play_result
runScript: path_outro$, "8. [SPATIAL] Circular rotation", 0.2, 2.0, 1.0, 1.0, 0.7, 2.0, 0.0, 0.0, -60.0, 0.95, 100, 1, "8 channels - octophonic (Ch1-Ch8)", 0, 0

# Get the output
sound_outro_raw = selected("Sound")
Rename: initial_name$ + "_Part3_Raw"

# --- Trim trailing silence (stereo-safe method) ---
selectObject: sound_outro_raw
Convert to mono
sound_outro_mono = selected("Sound")

Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"
mono_trimmed_outro = selected("Sound")
trimmed_dur = Get total duration
removeObject: sound_outro_mono, mono_trimmed_outro

# Crop original to trimmed duration
selectObject: sound_outro_raw
Extract part: 0, trimmed_dur, "rectangular", 1, "no"
sound_outro = selected("Sound")
Rename: initial_name$ + "_Part3_Movements"

# Ensure stereo (8-channel may output multichannel - convert to stereo)
selectObject: sound_outro
nch = Get number of channels
if nch > 2
    Extract one channel: 1
    ch1 = selected("Sound")
    selectObject: sound_outro
    Extract one channel: 2
    ch2 = selected("Sound")
    selectObject: ch1
    plusObject: ch2
    Combine to stereo
    tmp = selected("Sound")
    removeObject: sound_outro, ch1, ch2
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_Movements"
elsif nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_outro
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_Movements"
endif

dur_outro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_outro, 2), " s"

# Clean up raw
removeObject: sound_outro_raw

# Fade In for crossfade
selectObject: sound_outro
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# MIXING
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "=== Mixing Parts ==="

# Get sample rate from intro
selectObject: sound_intro
fs = Get sampling frequency

# Calculate start times
start_1 = 0
start_2 = dur_intro - overlap_sec
start_3 = start_2 + dur_body - overlap_sec
total_dur = start_3 + dur_outro

appendInfoLine: "  Part 1 starts: ", fixed$(start_1, 2), " s"
appendInfoLine: "  Part 2 starts: ", fixed$(start_2, 2), " s"
appendInfoLine: "  Part 3 starts: ", fixed$(start_3, 2), " s"
appendInfoLine: "  Total duration: ", fixed$(total_dur, 2), " s"

# --- Prepare Track 1 (Intro) ---
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

# --- Prepare Track 2 (Body) ---
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

# --- Prepare Track 3 (Outro) ---
Create Sound from formula: "Silence_Start3", 2, 0, start_3, fs, "0"
silence_start3 = selected("Sound")
selectObject: silence_start3
plusObject: sound_outro
Concatenate
track3 = selected("Sound")
Rename: "Track_3_Aligned"
removeObject: silence_start3

# --- Sum All Tracks ---
appendInfoLine: "  Summing tracks..."

selectObject: track1
track2_str$ = string$(track2)
track3_str$ = string$(track3)
Formula: "self + object(" + track2_str$ + ", x) + object(" + track3_str$ + ", x)"

final_name$ = initial_name$ + "_Composition5"
Rename: final_name$
final_sound = selected("Sound")

# ==============================================================================
# FINAL MASTERING
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "=== Final Mastering ==="

# --- Trim trailing silence ---
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

# --- Apply final fade-out ---
appendInfoLine: "  Applying fade-out (", fixed$(final_fade_sec, 1), " s)..."

selectObject: final_sound
final_dur = Get total duration
fade_start = final_dur - final_fade_sec

if fade_start > 0
    Formula: "if x > " + string$(fade_start) + " then self * ((xmax - x) / " + string$(final_fade_sec) + ") else self fi"
endif

# --- Normalize ---
appendInfoLine: "  Normalizing..."
Scale peak: 0.99

# ==============================================================================
# CLEANUP (Keep only final result)
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Cleaning up intermediate files..."

nocheck removeObject: sound_intro
nocheck removeObject: sound_body
nocheck removeObject: sound_outro
nocheck removeObject: track2
nocheck removeObject: track3
nocheck removeObject: initial_sound

# Comprehensive cleanup - find and remove any remaining artifacts
appendInfoLine: "  Searching for artifacts..."
select all
if numberOfSelected("Sound") > 0
    n = numberOfSelected("Sound")
    for j to n
        name'j'$ = selected$("Sound", j)
    endfor
    for j to n
        tempName$ = name'j'$
        if tempName$ <> final_name$
            isArtifact = 0
            if index(tempName$, "Rectifier") > 0
                isArtifact = 1
            endif
            if index(tempName$, "rectifier") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Brownian") > 0
                isArtifact = 1
            endif
            if index(tempName$, "brownian") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Movement") > 0
                isArtifact = 1
            endif
            if index(tempName$, "movement") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Texture") > 0
                isArtifact = 1
            endif
            if index(tempName$, "_Part") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Track_") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Recording") > 0 and tempName$ <> final_name$
                isArtifact = 1
            endif
            if isArtifact = 1
                appendInfoLine: "    Removing artifact: ", tempName$
                nocheck selectObject: "Sound " + tempName$
                nocheck Remove
            endif
        endif
    endfor
endif

# ==============================================================================
# FINISH
# ==============================================================================
selectObject: final_sound
final_dur = Get total duration
final_nch = Get number of channels

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  LIVE 5 COMPOSITION COMPLETE"
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
