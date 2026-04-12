# ============================================================
# Praat AudioTools - Live 3 Random
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 3 processing chain with RANDOMIZED parameters
#   Flow: Record -> Whisper Morph -> Bimodal Contour -> Percussive Groove
#   Each run generates different parameter combinations for unique results!
# ============================================================

# ============================================================
# USER FORM
# ============================================================

form Live Recording - Composition 3 Random Settings
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
# PART 2: COMPOSITION 3 (AudioTools) - RANDOMIZED
# Flow: Whisper Morph -> Bimodal Contour -> Percussive Groove
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
path_intro$ = pluginPath$ + "Filter & Color/Whisper Morph.praat"
path_body$ = pluginPath$ + "Pitch/Bimodal_Contour_Grammar.praat"
path_outro$ = pluginPath$ + "Time & Granular/Percussive Audio Groove Creator.praat"

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 3 RANDOM - Whisper -> Contour -> Groove"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Random seed: ", random_seed
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: "Plugin path: ", pluginPath$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Whisper Morph) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Whisper Morph - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Whisper Morph parameters
# Preset: random choice
whisper_preset_choice = randomInteger(1, 5)
if whisper_preset_choice = 1
    whisper_preset$ = "Custom"
elsif whisper_preset_choice = 2
    whisper_preset$ = "Gentle Whisper"
elsif whisper_preset_choice = 3
    whisper_preset$ = "Breathy Whisper"
elsif whisper_preset_choice = 4
    whisper_preset$ = "Harsh Whisper"
else
    whisper_preset$ = "ASMR Style"
endif

# Morph type: random choice
whisper_morph_choice = randomInteger(1, 5)
if whisper_morph_choice = 1
    whisper_morph$ = "Dry to Wet (original -> whisper)"
elsif whisper_morph_choice = 2
    whisper_morph$ = "Wet to Dry (whisper -> original)"
elsif whisper_morph_choice = 3
    whisper_morph$ = "Dry-Wet-Dry (original -> whisper -> original)"
elsif whisper_morph_choice = 4
    whisper_morph$ = "Wet-Dry-Wet (whisper -> original -> whisper)"
else
    whisper_morph$ = "Full Whisper (no morph)"
endif

# LPC order factor: 0.8-1.3
whisper_lpc = randomUniform(0.8, 1.3)

# Breathiness: 0.5-1.0
whisper_breath = randomUniform(0.5, 1.0)

# High frequency boost: 2.0-12.0 dB
whisper_hf_boost = randomUniform(2.0, 12.0)

# Morph curve: random choice
whisper_curve_choice = randomInteger(1, 3)
if whisper_curve_choice = 1
    whisper_curve$ = "Linear"
elsif whisper_curve_choice = 2
    whisper_curve$ = "Smooth (cosine)"
else
    whisper_curve$ = "Exponential"
endif

appendInfoLine: "  Preset: ", whisper_preset$
appendInfoLine: "  Morph type: ", whisper_morph$
appendInfoLine: "  LPC order factor: ", fixed$(whisper_lpc, 2)
appendInfoLine: "  Breathiness: ", fixed$(whisper_breath, 2)
appendInfoLine: "  HF boost: ", fixed$(whisper_hf_boost, 1), " dB"
appendInfoLine: "  Curve: ", whisper_curve$

# Whisper Morph parameters:
# Preset, Morph_type, LPC_factor, Breathiness, HF_boost, Curve, Draw, Play
runScript: path_intro$, whisper_preset$, whisper_morph$, whisper_lpc, 
    ... whisper_breath, whisper_hf_boost, whisper_curve$, 0, 0

# Get the output
sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_Whisper"

# Ensure stereo
selectObject: sound_intro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_intro
    sound_intro = tmp
    Rename: initial_name$ + "_Part1_Whisper"
endif

dur_intro = Get total duration
appendInfoLine: "  Actual duration: ", fixed$(dur_intro, 2), " s"

# Fade Out for crossfade
selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Bimodal Contour Grammar) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Bimodal Contour Grammar - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Bimodal Contour Grammar v0.4 parameters
contour_seed = randomInteger(1, 999999)
bc_preset$ = "Custom"
bc_lo = randomInteger(50, 150)
bc_hi = randomInteger(200, 800)
bc_gest = randomUniform(0.5, 2.0)
bc_int = randomUniform(0.5, 2.0)
bc_wobble = randomUniform(0.0, 10.0)

# Color scheme: random choice
contour_color_choice = randomInteger(1, 4)
if contour_color_choice = 1
    contour_color$ = "Pitch+Loudness Rainbow"
elsif contour_color_choice = 2
    contour_color$ = "PitchClass+Loudness Wheel"
elsif contour_color_choice = 3
    contour_color$ = "Intensity Heatmap"
else
    contour_color$ = "Octave Spiral"
endif

# Line style: random choice
contour_line_choice = randomInteger(1, 3)
if contour_line_choice = 1
    contour_line$ = "Thin continuous line"
elsif contour_line_choice = 2
    contour_line$ = "Thickness varies with loudness"
else
    contour_line$ = "Dots with size varies with loudness"
endif

# Dot sizes: 0.5-2.0 (min), 2.0-6.0 (max)
contour_min_dot = randomUniform(0.5, 2.0)
contour_max_dot = randomUniform(2.0, 6.0)

# Base loudness: 60-80
contour_loudness = randomInteger(60, 80)

# Loudness variation: 5-15
contour_variation = randomInteger(5, 15)

# Grid and labels: random
contour_grid = randomInteger(0, 1)
contour_labels = randomInteger(0, 1)

appendInfoLine: "  Random seed: ", contour_seed
appendInfoLine: "  Base Lo Hz: ", bc_lo
appendInfoLine: "  Base Hi Hz: ", bc_hi
appendInfoLine: "  Color scheme: ", contour_color$
appendInfoLine: "  Line style: ", contour_line$
appendInfoLine: "  Dot sizes: ", fixed$(contour_min_dot, 1), " - ", fixed$(contour_max_dot, 1)
appendInfoLine: "  Base loudness: ", contour_loudness
appendInfoLine: "  Loudness variation: ", contour_variation
appendInfoLine: "  Show grid: ", if contour_grid then "yes" else "no" fi
appendInfoLine: "  Show labels: ", if contour_labels then "yes" else "no" fi

# Bimodal Contour Grammar v0.4 parameters (16 arguments)
runScript: path_body$, bc_preset$, bc_lo, bc_hi, bc_gest, bc_int, bc_wobble, contour_seed, contour_color$, contour_line$, contour_min_dot, contour_max_dot, contour_loudness, contour_variation, contour_grid, contour_labels, 0

# Get the output
sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_Contour"

# Ensure stereo
selectObject: sound_body
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_body
    sound_body = tmp
    Rename: initial_name$ + "_Part2_Contour"
endif

dur_body = Get total duration
appendInfoLine: "  Actual duration: ", fixed$(dur_body, 2), " s"

# Fade In and Fade Out for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (Percussive Groove) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (Percussive Groove - Randomized) ==="
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

# BPM: 80-150
groove_bpm = randomInteger(80, 150)

# Threshold: -30 to -15 dB
groove_thresh = randomUniform(-30, -15)

# Min silence: 0.03-0.08
groove_min_silence = randomUniform(0.03, 0.08)

# Max segment: 0.1-0.2
groove_max_segment = randomUniform(0.1, 0.2)

# Groove density: 0.4-0.9
groove_density = randomUniform(0.4, 0.9)

# Clip max length: 0.08-0.18
groove_clip_max = randomUniform(0.08, 0.18)

# Attack: 0.001-0.005
groove_attack = randomUniform(0.001, 0.005)

# Release: 0.03-0.08
groove_release = randomUniform(0.03, 0.08)

# Shape intensity: 0.8-1.5
groove_shape = randomUniform(0.8, 1.5)

# Stereo: always 1
groove_stereo = 1

appendInfoLine: "  Duration: ", groove_dur$
appendInfoLine: "  Pattern: ", groove_pattern$
appendInfoLine: "  BPM: ", groove_bpm
appendInfoLine: "  Threshold: ", fixed$(groove_thresh, 1), " dB"
appendInfoLine: "  Min silence: ", fixed$(groove_min_silence, 3)
appendInfoLine: "  Max segment: ", fixed$(groove_max_segment, 3)
appendInfoLine: "  Density: ", fixed$(groove_density, 2)
appendInfoLine: "  Clip max: ", fixed$(groove_clip_max, 3)
appendInfoLine: "  Attack: ", fixed$(groove_attack, 4)
appendInfoLine: "  Release: ", fixed$(groove_release, 3)
appendInfoLine: "  Shape intensity: ", fixed$(groove_shape, 2)

# Percussive Audio Groove Creator parameters:
# Length, Pattern, BPM, Threshold, Min_silence, Max_segment, Density, Clip_max,
# Attack, Release, Shape, Stereo, Draw, Play
runScript: path_outro$, groove_dur$, groove_pattern$, groove_bpm, groove_thresh, 
    ... groove_min_silence, groove_max_segment, groove_density, groove_clip_max, 
    ... groove_attack, groove_release, groove_shape, groove_stereo, 0, 0

# Get the output
sound_outro = selected("Sound")
Rename: initial_name$ + "_Part3_Groove"

# Ensure stereo
selectObject: sound_outro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_outro
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_Groove"
endif

dur_outro = Get total duration
appendInfoLine: "  Actual duration: ", fixed$(dur_outro, 2), " s"

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
final_name$ = initial_name$ + "_Composition3"
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
            if index(tempName$, "intro") > 0
                isArtifact = 1
            endif
            if index(tempName$, "body") > 0
                isArtifact = 1
            endif
            if index(tempName$, "outro") > 0
                isArtifact = 1
            endif
            if index(tempName$, "bimodal") > 0
                isArtifact = 1
            endif
            if index(tempName$, "groove") > 0
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
appendInfoLine: "  LIVE 3 RANDOM COMPOSITION COMPLETE"
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