# ============================================================
# Praat AudioTools - Live 1 Random
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 1 processing chain with RANDOMIZED parameters
#   Flow: Record → Neural Drone → Percussive Groove → Crystalline Reverb
#   Each run generates different parameter combinations for unique results!
# ============================================================

# ============================================================
# USER FORM
# ============================================================

form Live Recording - Composition 1 Random Settings
    positive Recording_time_seconds 5.0
    comment Random seed (0 = use current time)
    integer Random_seed 0
endform

# ============================================================
# RANDOM SEED INITIALIZATION
# ============================================================

if random_seed = 0
    # Use current time as seed
    random_seed = randomInteger(1, 999999)
endif

# Initialize random generator
randomSeed = random_seed
appendInfoLine: "Random seed: ", random_seed

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
# PART 2: COMPOSITION 1 (AudioTools) - RANDOMIZED
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
path_intro$ = pluginPath$ + "AI & Adaptive/Neural Ambient Drone Designer.praat"
path_body$ = pluginPath$ + "Time & Granular/Percussive Audio Groove Creator.praat"
path_outro$ = pluginPath$ + "Reverb/Crystalline_Cascade.praat"

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 1 RANDOM - Drone → Groove → Crystalline"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Random seed: ", random_seed
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: "Plugin path: ", pluginPath$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Neural Ambient Drone) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Neural Drone - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Neural Ambient Drone Designer parameters
# Preset: always "Manual"
# Duration: 10-20 seconds
drone_dur = randomUniform(10, 20)

# Layers: 2-5
drone_layers = randomInteger(2, 5)

# Crossfade: 10-50 ms
drone_crossfade = randomInteger(10, 50)

# Shimmer: 0 or 1
drone_shimmer = randomInteger(0, 1)

# Shimmer probability: 0.1-0.3
drone_shimmer_prob = randomUniform(0.1, 0.3)

# Shimmer intervals: random choice
drone_shimmer_choice = randomInteger(1, 3)
if drone_shimmer_choice = 1
    drone_shimmer_intervals$ = "Octaves only"
elsif drone_shimmer_choice = 2
    drone_shimmer_intervals$ = "Octaves and fifths"
else
    drone_shimmer_intervals$ = "Full harmonic series"
endif

# Grain size: 80-150 ms
drone_grain = randomInteger(80, 150)

# Clusters: 2-5
drone_clusters = randomInteger(2, 5)

# K-means iterations: 5-15
drone_kmeans = randomInteger(5, 15)

# Stereo: always 1
drone_stereo = 1

# Stereo width: 0.5-0.9
drone_width = randomUniform(0.5, 0.9)

appendInfoLine: "  Duration: ", fixed$(drone_dur, 1), "s"
appendInfoLine: "  Layers: ", drone_layers
appendInfoLine: "  Crossfade: ", drone_crossfade, "ms"
appendInfoLine: "  Shimmer: ", if drone_shimmer then "yes" else "no" fi
appendInfoLine: "  Shimmer prob: ", fixed$(drone_shimmer_prob, 2)
appendInfoLine: "  Shimmer intervals: ", drone_shimmer_intervals$
appendInfoLine: "  Grain size: ", drone_grain, "ms"
appendInfoLine: "  Clusters: ", drone_clusters
appendInfoLine: "  K-means iter: ", drone_kmeans
appendInfoLine: "  Stereo width: ", fixed$(drone_width, 2)

# Neural Ambient Drone Designer parameters
# Args: Preset, Duration, Layers, Crossfade_ms, Shimmer, Shimmer_prob, Shimmer_intervals,
#       Grain_ms, Clusters, Kmeans_iter, Stereo, Stereo_width, Play
runScript: path_intro$, "Manual", drone_dur, drone_layers, drone_crossfade, drone_shimmer, 
    ... drone_shimmer_prob, drone_shimmer_intervals$, drone_grain, drone_clusters, 
    ... drone_kmeans, drone_stereo, drone_width, 0

# Ensure stereo
selectObject: selected("Sound")
nch = Get number of channels
if nch = 1
    Convert to stereo
endif
sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_Intro"
dur_intro = Get total duration
appendInfoLine: "  Actual duration: ", fixed$(dur_intro, 2), " s"

# Fade Out for crossfade
selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Percussive Groove) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Percussive Groove - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Percussive Audio Groove Creator parameters
# Duration preset: random choice
groove_dur_choice = randomInteger(1, 3)
if groove_dur_choice = 1
    groove_dur$ = "1 bar"
elsif groove_dur_choice = 2
    groove_dur$ = "2 bars"
else
    groove_dur$ = "4 bars"
endif

# Pattern: random choice
groove_pattern_choice = randomInteger(1, 6)
if groove_pattern_choice = 1
    groove_pattern$ = "Standard 4/4"
elsif groove_pattern_choice = 2
    groove_pattern$ = "Syncopated Funk"
elsif groove_pattern_choice = 3
    groove_pattern$ = "Breakbeat"
elsif groove_pattern_choice = 4
    groove_pattern$ = "Half-time Feel"
elsif groove_pattern_choice = 5
    groove_pattern$ = "Double-time Feel"
else
    groove_pattern$ = "Sparse Minimal"
endif

# BPM: 90-140
groove_bpm = randomInteger(90, 140)

# Threshold: -25 to -15 dB
groove_thresh = randomUniform(-25, -15)

# Attack: 0.02-0.1
groove_attack = randomUniform(0.02, 0.1)

# Release: 0.1-0.3
groove_release = randomUniform(0.1, 0.3)

# Slice probability: 0.4-0.8
groove_slice_prob = randomUniform(0.4, 0.8)

# Reverse probability: 0.05-0.2
groove_rev_prob = randomUniform(0.05, 0.2)

# Min slice: 0.001-0.005
groove_min_slice = randomUniform(0.001, 0.005)

# Max silence: 0.03-0.08
groove_max_silence = randomUniform(0.03, 0.08)

# Velocity variation: 0.8-1.5
groove_velocity = randomUniform(0.8, 1.5)

# Stereo: always 1
groove_stereo = 1

appendInfoLine: "  Duration: ", groove_dur$
appendInfoLine: "  Pattern: ", groove_pattern$
appendInfoLine: "  BPM: ", groove_bpm
appendInfoLine: "  Threshold: ", fixed$(groove_thresh, 1), " dB"
appendInfoLine: "  Attack: ", fixed$(groove_attack, 3)
appendInfoLine: "  Release: ", fixed$(groove_release, 3)
appendInfoLine: "  Slice prob: ", fixed$(groove_slice_prob, 2)
appendInfoLine: "  Reverse prob: ", fixed$(groove_rev_prob, 2)
appendInfoLine: "  Min slice: ", fixed$(groove_min_slice, 4)
appendInfoLine: "  Max silence: ", fixed$(groove_max_silence, 3)
appendInfoLine: "  Velocity var: ", fixed$(groove_velocity, 2)

# Percussive Audio Groove Creator parameters
# Args: Duration, Pattern, BPM, Threshold, Attack, Release, Slice_prob, Rev_prob,
#       Min_slice, Max_silence, Velocity_var, Stereo, Viz, Play
runScript: path_body$, groove_dur$, groove_pattern$, groove_bpm, groove_thresh, 
    ... groove_attack, groove_release, groove_slice_prob, groove_rev_prob, 
    ... groove_min_slice, groove_max_silence, groove_velocity, groove_stereo, 0, 0

# Ensure stereo
selectObject: selected("Sound")
nch = Get number of channels
if nch = 1
    Convert to stereo
endif
sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_Body"
dur_body = Get total duration
appendInfoLine: "  Actual duration: ", fixed$(dur_body, 2), " s"

# Fade In and Fade Out for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (Crystalline Cascade) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (Crystalline Reverb - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Crystalline Cascade parameters
# Preset: random choice
crys_preset_choice = randomInteger(1, 5)
if crys_preset_choice = 1
    crys_preset$ = "Custom (use settings below)"
elsif crys_preset_choice = 2
    crys_preset$ = "Subtle Flutter"
elsif crys_preset_choice = 3
    crys_preset$ = "Medium Flutter"
elsif crys_preset_choice = 4
    crys_preset$ = "Heavy Flutter"
else
    crys_preset$ = "Extreme Flutter"
endif

# Duration multiplier: 2.0-5.0
crys_dur = randomUniform(2.0, 5.0)

# Base frequency: 600-1200 Hz
crys_base_freq = randomInteger(600, 1200)

# Base density: 0.05-0.15
crys_base_density = randomUniform(0.05, 0.15)

# Flutter frequency: 800-1600 Hz
crys_flutter_freq = randomInteger(800, 1600)

# Flutter rate: 80-200 ms
crys_flutter_rate = randomInteger(80, 200)

# Flutter depth: 0.4-0.8
crys_flutter_depth = randomUniform(0.4, 0.8)

# Shimmer frequency: 40-100 Hz
crys_shimmer_freq = randomInteger(40, 100)

# Shimmer depth: 0.2-0.5
crys_shimmer_depth = randomUniform(0.2, 0.5)

# Stereo width: 0.5-0.9
crys_stereo_width = randomUniform(0.5, 0.9)

# Cascade rate: 30-80 ms
crys_cascade_rate = randomInteger(30, 80)

# Output scale: 0.8-0.95
crys_output_scale = randomUniform(0.8, 0.95)

appendInfoLine: "  Preset: ", crys_preset$
appendInfoLine: "  Duration mult: ", fixed$(crys_dur, 1)
appendInfoLine: "  Base freq: ", crys_base_freq, " Hz"
appendInfoLine: "  Base density: ", fixed$(crys_base_density, 3)
appendInfoLine: "  Flutter freq: ", crys_flutter_freq, " Hz"
appendInfoLine: "  Flutter rate: ", crys_flutter_rate, " ms"
appendInfoLine: "  Flutter depth: ", fixed$(crys_flutter_depth, 2)
appendInfoLine: "  Shimmer freq: ", crys_shimmer_freq, " Hz"
appendInfoLine: "  Shimmer depth: ", fixed$(crys_shimmer_depth, 2)
appendInfoLine: "  Stereo width: ", fixed$(crys_stereo_width, 2)
appendInfoLine: "  Cascade rate: ", crys_cascade_rate, " ms"
appendInfoLine: "  Output scale: ", fixed$(crys_output_scale, 2)

# Crystalline Cascade parameters
# Args: Preset, Dur_mult, Base_freq, Base_density, Flutter_freq, Flutter_rate, Flutter_depth,
#       Shimmer_freq, Shimmer_depth, Stereo_width, Cascade_rate, Output_scale, Viz, Play
runScript: path_outro$, crys_preset$, crys_dur, crys_base_freq, crys_base_density, 
    ... crys_flutter_freq, crys_flutter_rate, crys_flutter_depth, crys_shimmer_freq, 
    ... crys_shimmer_depth, crys_stereo_width, crys_cascade_rate, crys_output_scale, 0, 0

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
appendInfoLine: "  Actual duration: ", fixed$(dur_outro, 2), " s"

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

final_name$ = initial_name$ + "_Composition1_Random"
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
appendInfoLine: "  LIVE 1 RANDOM COMPOSITION COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Random seed used: ", random_seed
appendInfoLine: "Output: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_dur, 2), " s"
appendInfoLine: "Channels: ", final_nch
appendInfoLine: ""
appendInfoLine: "Playing..."

# Clear picture window
Erase all

selectObject: final_sound
Play