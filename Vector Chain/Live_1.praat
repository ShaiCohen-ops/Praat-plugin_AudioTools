# ============================================================
# Praat AudioTools - Live 1
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 1 processing chain
#   Flow: Record → Neural Drone → Percussive Groove → Crystalline Reverb
# ============================================================

# ============================================================
# USER FORM
# ============================================================

form Live Recording - Composition 1 Settings
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
# PART 2: COMPOSITION 1 (AudioTools)
# Flow: Neural Drone → Percussive Groove → Crystalline Reverb
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
path_intro$ = pluginPath$ + "AI & Adaptive/Neural_Ambient_Drone_Designer.praat"
path_body$  = pluginPath$ + "Time & Granular/Percussive Audio Groove Creator.praat"
path_outro$ = pluginPath$ + "Reverb/Crystalline_Cascade.praat"

# Praat 7 / script-relative fallback
if not fileReadable(path_intro$)
    path_intro$ = defaultDirectory$ + "/../AI & Adaptive/Neural_Ambient_Drone_Designer.praat"
endif

if not fileReadable(path_body$)
    path_body$ = defaultDirectory$ + "/../Time & Granular/Percussive Audio Groove Creator.praat"
endif

if not fileReadable(path_outro$)
    path_outro$ = defaultDirectory$ + "/../Reverb/Crystalline_Cascade.praat"
endif

path_intro$ = replace_regex$(path_intro$, "\\", "/", 0)
path_body$  = replace_regex$(path_body$,  "\\", "/", 0)
path_outro$ = replace_regex$(path_outro$, "\\", "/", 0)

if not fileReadable(path_intro$)
    exitScript: "Cannot find Neural_Ambient_Drone_Designer.praat"
endif

if not fileReadable(path_body$)
    exitScript: "Cannot find Percussive Audio Groove Creator.praat"
endif

if not fileReadable(path_outro$)
    exitScript: "Cannot find Crystalline_Cascade.praat"
endif

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 1 - Drone → Groove → Crystalline"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: "Plugin path: ", pluginPath$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Atmospheric Drone)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Neural Drone) ==="
appendInfoLine: "  Generating..."

# FIX: Updated to the correct 13-argument signature for
# Neural_Ambient_Drone_Designer v0.9. v0.9 dropped the separate Stereo
# on/off boolean - Stereo_width alone now controls it (negative = mono,
# >=0 = stereo) - and reordered Seed to the end, next to Play. The old
# v0.7 14-arg call below had a Stereo=1 value with no home in the new form.
# Neural Ambient Drone Designer parameters (v0.9):
# Preset, Duration, Layers, Grain_ms, Crossfade_ms, Shimmer, Shimmer_prob,
# Shimmer_intervals, Clusters, Kmeans_iter, Stereo_width, Seed, Play
# Seed=0 keeps the internal RNG unpredictable, matching prior behaviour.
# Stereo_width=0.7 (positive) keeps stereo output, matching the old Stereo=1.
runScript: path_intro$, "Manual", 15.0, 3, 100, 20, 1, 0.15, "Octaves only", 3, 10, 0.7, 0, 0

# Ensure stereo
selectObject: selected("Sound")
nch = Get number of channels
if nch = 1
    Convert to stereo
endif
sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_Intro"
dur_intro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_intro, 2), " s"

# Fade Out for crossfade
selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Rhythmic Groove)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Percussive Groove) ==="
appendInfoLine: "  Generating..."

# Percussive Audio Groove Creator parameters
runScript: path_body$, "4 bars", "Breakbeat", 110, -20, 0.05, 0.15, 0.6, 0.12, 0.002, 0.05, 1.2, 1, 0, 0

# Ensure stereo
selectObject: selected("Sound")
nch = Get number of channels
if nch = 1
    Convert to stereo
endif
sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_Body"
dur_body = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_body, 2), " s"

# Fade In and Fade Out for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (Crystalline Wash)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (Crystalline Reverb) ==="
appendInfoLine: "  Generating..."

# Crystalline Cascade parameters
runScript: path_outro$, "Subtle Flutter", 3.0, 800, 0.08, 1200, 120, 0.6, 60, 0.35, 0.7, 50, 0.88, 0, 0

# Ensure stereo
selectObject: selected("Sound")
nch = Get number of channels
if nch = 1
    Convert to stereo
endif
sound_outro_raw = selected("Sound")
Rename: initial_name$ + "_Part3_Raw"

# --- Trim trailing silence ---
selectObject: sound_outro_raw
Convert to mono
sound_outro_mono = selected("Sound")

# Trim (Extended Syntax)
Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"

mono_trimmed_outro = selected("Sound")
trimmed_dur = Get total duration
removeObject: sound_outro_mono, mono_trimmed_outro

# Crop original stereo
selectObject: sound_outro_raw
Extract part: 0, trimmed_dur, "rectangular", 1, "no"
sound_outro = selected("Sound")
Rename: initial_name$ + "_Part3_Outro"
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

final_name$ = initial_name$ + "_Composition1"
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

# Trim (Extended Syntax)
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

# Safe cleanup using nocheck for each object
nocheck removeObject: sound_intro
nocheck removeObject: sound_body
nocheck removeObject: sound_outro
nocheck removeObject: track2
nocheck removeObject: track3

# Remove recording (we only keep final result)
nocheck removeObject: initial_sound

# Comprehensive cleanup - find and remove any remaining artifacts
appendInfoLine: "  Searching for artifacts..."
select all
if numberOfSelected("Sound") > 0
    n = numberOfSelected("Sound")
    # Build array of names first to avoid selection issues
    for j to n
        name'j'$ = selected$("Sound", j)
    endfor
    # Now remove artifacts
    for j to n
        tempName$ = name'j'$
        # Check if name contains artifact patterns and it's not our final sound
        if tempName$ <> final_name$
            isArtifact = 0
            if index(tempName$, "cascade") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Cascade") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Recording") > 0
                isArtifact = 1
            endif
            if index(tempName$, "_Part") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Track_") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Drone") > 0
                isArtifact = 1
            endif
            if index(tempName$, "NeuralDrone") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Groove") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Crystalline") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Intro") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Body") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Outro") > 0
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
appendInfoLine: "  LIVE 1 COMPOSITION COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_dur, 2), " s"
appendInfoLine: "Channels: ", final_nch
appendInfoLine: ""
appendInfoLine: "Playing..."

# Clear picture window
Erase all

selectObject: final_sound
Play