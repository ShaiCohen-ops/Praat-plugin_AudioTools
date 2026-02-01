# ============================================================
# Praat AudioTools - Live 2
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 2 processing chain
#   Flow: Record → Spiral Pitch → Neural Drone → 8-Channel Spatial
# ============================================================

# ============================================================
# USER FORM
# ============================================================

form Live Recording - Composition 2 Settings
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
# PART 2: COMPOSITION 2 (AudioTools)
# Flow: Spiral Pitch → Neural Drone → 8-Channel Deviations
# ============================================================

# === INPUT SETUP ===
initial_sound = selected("Sound")
initial_name$ = selected$("Sound")

# === GET PLUGIN PATH ===
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

# === CONFIGURATION ===
overlap_sec = 0.15
final_fade_sec = 4.0

# === DEFINE SCRIPT PATHS ===
path_intro$ = pluginPath$ + "Pitch/Spiral_Pitch_Dance.praat"
path_body$ = pluginPath$ + "AI & Adaptive/Neural Ambient Drone Designer.praat"
path_outro$ = pluginPath$ + "Spatial & Surround/8-channel speed deviations.praat"

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 2 - Spiral → Drone → Spatial"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: "Plugin path: ", pluginPath$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Spiral Pitch Dance)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Spiral Pitch Dance) ==="
appendInfoLine: "  Generating..."

# Spiral Pitch Dance parameters:
# Preset, Num_bands, Start_freq, Ratio, Jitter, Speed_Hz, Range_cents, Feedback, Play
runScript: path_intro$, "Manual (configure below)", 2, 24, 1.5, 0.005, 50, 1200, 0, 0

# Get the output
sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_Spiral"

# Ensure stereo
selectObject: sound_intro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_intro
    sound_intro = tmp
    Rename: initial_name$ + "_Part1_Spiral"
endif

dur_intro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_intro, 2), " s"

# Fade Out for crossfade
selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Neural Ambient Drone)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Neural Ambient Drone) ==="
appendInfoLine: "  Generating..."

# Neural Ambient Drone Designer parameters:
# Preset, Duration, Layers, Crossfade_ms, Shimmer, Shimmer_prob, Shimmer_intervals,
# Grain_ms, Clusters, Kmeans_iter, Stereo, Stereo_width, Play
runScript: path_body$, "Evolving Pad", 20.0, 4, 30, 1, 0.18, "Octaves and fifths", 120, 4, 10, 1, 0.75, 0

# Get the output
sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_Drone"

# Ensure stereo
selectObject: sound_body
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_body
    sound_body = tmp
    Rename: initial_name$ + "_Part2_Drone"
endif

dur_body = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_body, 2), " s"

# Fade In for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# Fade Out for crossfade
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (8-Channel Speed Deviations)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (8-Channel Deviations) ==="
appendInfoLine: "  Generating..."

# 8-Channel Speed Deviations parameters:
# Preset, Mode, Factor, ch1-8 speeds, min, max, seed, pitch_floor, pitch_ceil, 
# use_original_sr, target_sr, visualize, play
runScript: path_outro$, "Custom (use mode below)", "Automatic (using factor)", 0.15, 0.85, 0.88, 0.91, 0.94, 1.06, 1.09, 1.12, 1.15, 0.80, 1.20, 42, 75, 600, 1, 44100, 0, 0

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
Rename: initial_name$ + "_Part3_Spatial"

# Ensure stereo (8-channel may output multichannel - convert to stereo)
selectObject: sound_outro
nch = Get number of channels
if nch > 2
    # Extract first two channels as stereo
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
    Rename: initial_name$ + "_Part3_Spatial"
elsif nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_outro
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_Spatial"
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

final_name$ = initial_name$ + "_Composition2"
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
    # Now remove artifacts (spiral, drone, deviations leftovers)
    for j to n
        tempName$ = name'j'$
        # Check if name contains artifact patterns and it's not our final sound
        if tempName$ <> final_name$
            isArtifact = 0
            if index(tempName$, "spiral") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Spiral") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Drone") > 0
                isArtifact = 1
            endif
            if index(tempName$, "NeuralDrone") > 0
                isArtifact = 1
            endif
            if index(tempName$, "deviations") > 0
                isArtifact = 1
            endif
            if index(tempName$, "Deviations") > 0
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
appendInfoLine: "  LIVE 2 COMPOSITION COMPLETE"
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