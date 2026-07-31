# ============================================================
# Praat AudioTools - Composition 1 (Stereo Safe)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Composition chain combining Neural Drone (Intro) + 
#   Percussive Groove (Mid) + Crystalline Reverb (Outro)
#
# Flow: Atmospheric intro → Rhythmic body → Reverberant outro
# ============================================================

# === INPUT VALIDATION ===
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the composition."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")

# === GET PLUGIN PATH ===
# This finds the plugin folder regardless of where Praat is installed
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

# === CONFIGURATION ===
overlap_sec = 0.1
final_fade_sec = 3.0

# === DEFINE SCRIPT PATHS ===
path_intro$ = pluginPath$ + "AI & Adaptive/Neural_Ambient_Drone_Designer.praat"
path_body$ = pluginPath$ + "Time & Granular/Percussive Audio Groove Creator.praat"
path_outro$ = pluginPath$ + "Reverb/Crystalline_Cascade.praat"

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  COMPOSITION 1 - Three-Part Structure"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Input: ", initial_name$
writeInfoLine: "Plugin path: ", pluginPath$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Atmospheric Drone)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Neural Drone) ==="
appendInfoLine: "  Generating..."

# Neural Ambient Drone Designer parameters (matches current 13-arg form, v0.9):
# Preset, Output_duration_sec, Number_of_layers, Grain_size_ms, Grain_crossfade_ms,
# Add_octave_shimmer, Shimmer_probability, Shimmer_intervals, Number_of_clusters,
# Kmeans_iterations, Stereo_width, Seed, Play_result
# Seed=0 keeps the internal RNG unpredictable, matching prior behaviour.
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

# Percussive Audio Groove Creator parameters:
# Length, Pattern, BPM, Threshold, Attack, Sustain, Density, Swing, Fade_in, Fade_out,
# Velocity_var, Stereo, Reverb, Play
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

# Fade In for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# Fade Out for crossfade
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (Crystalline Wash)
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (Crystalline Reverb) ==="
appendInfoLine: "  Generating..."

# Crystalline Cascade parameters:
# Preset, Decay, Diffusion_freq, Diffusion_depth, Early_freq, Early_spacing,
# Early_decay, Early_count, Mix, Shimmer, Shimmer_detune, Damping, Stereo_width, Visualize, Play
runScript: path_outro$, "Subtle Flutter", 3.0, 800, 0.08, 1200, 120, 0.6, 60, 0.35, 0.7, 50, 0.88, 0, 0

# Ensure stereo
selectObject: selected("Sound")
nch = Get number of channels
if nch = 1
    Convert to stereo
endif
sound_outro_raw = selected("Sound")
Rename: initial_name$ + "_Part3_Raw"

# --- Trim trailing silence (stereo-safe method) ---
# Create mono copy to analyze
selectObject: sound_outro_raw
Convert to mono
sound_outro_mono = selected("Sound")

# Trim the mono copy
Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"
mono_trimmed_outro = selected("Sound")
trimmed_dur = Get total duration
removeObject: sound_outro_mono, mono_trimmed_outro

# Crop original stereo to trimmed duration
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

final_name$ = initial_name$ + "_Composition"
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
# CLEANUP (Keep only original + result)
# ==============================================================================
appendInfoLine: ""
appendInfoLine: "Cleaning up intermediate files..."

removeObject: sound_intro, sound_body, sound_outro, track2, track3

# ==============================================================================
# FINISH
# ==============================================================================
selectObject: final_sound
final_dur = Get total duration
final_nch = Get number of channels

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPOSITION COMPLETE"
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

