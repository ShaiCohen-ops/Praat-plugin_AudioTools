# ============================================================
# Praat AudioTools - Live 2 Random
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Live recording + Composition 2 processing chain with RANDOMIZED parameters
#   Flow: Record → Spiral Pitch → Neural Drone → 8-Channel Spatial
#   Each run generates different parameter combinations for unique results!
# ============================================================

# ============================================================
# USER FORM
# ============================================================

form Live Recording - Composition 2 Random Settings
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
# PART 2: COMPOSITION 2 (AudioTools) - RANDOMIZED
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
path_outro$ = pluginPath$ + "Spatial & Surround/8-channel_speed_deviations.praat"

# === INFO HEADER ===
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 2 RANDOM - Spiral → Drone → Spatial"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Random seed: ", random_seed
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: "Plugin path: ", pluginPath$
writeInfoLine: ""

# ==============================================================================
# PART 1: INTRO (Spiral Pitch Dance) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Spiral Pitch Dance - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Spiral Pitch Dance parameters
# Preset: random choice
spiral_preset_choice = randomInteger(1, 8)
if spiral_preset_choice = 1
    spiral_preset$ = "Manual (configure below)"
elsif spiral_preset_choice = 2
    spiral_preset$ = "Gentle Spiral"
elsif spiral_preset_choice = 3
    spiral_preset$ = "Moderate Spiral"
elsif spiral_preset_choice = 4
    spiral_preset$ = "Aggressive Spiral"
elsif spiral_preset_choice = 5
    spiral_preset$ = "Extreme Spiral"
elsif spiral_preset_choice = 6
    spiral_preset$ = "Fast Rotation"
elsif spiral_preset_choice = 7
    spiral_preset$ = "Slow Evolution"
else
    spiral_preset$ = "Psychedelic Swirl"
endif

# Spirals: 1-4
spiral_spirals = randomInteger(1, 4)

# Semitone range: 12-48
spiral_semitone = randomInteger(12, 48)

# Acceleration: 1.0-2.5
spiral_accel = randomUniform(1.0, 2.5)

# Time step: 0.003-0.008
spiral_timestep = randomUniform(0.003, 0.008)

# Floor pitch: 40-75 Hz
spiral_floor = randomInteger(40, 75)

# Ceiling pitch: 800-1500 Hz
spiral_ceiling = randomInteger(800, 1500)

appendInfoLine: "  Preset: ", spiral_preset$
appendInfoLine: "  Spirals: ", spiral_spirals
appendInfoLine: "  Semitone range: ", spiral_semitone
appendInfoLine: "  Acceleration: ", fixed$(spiral_accel, 2)
appendInfoLine: "  Time step: ", fixed$(spiral_timestep, 4)
appendInfoLine: "  Floor pitch: ", spiral_floor, " Hz"
appendInfoLine: "  Ceiling pitch: ", spiral_ceiling, " Hz"

# Spiral Pitch Dance parameters:
# Preset, Spirals, Semitone_range, Acceleration, Time_step, Floor_pitch, Ceiling_pitch, Draw, Play
runScript: path_intro$, spiral_preset$, spiral_spirals, spiral_semitone, spiral_accel, 
    ... spiral_timestep, spiral_floor, spiral_ceiling, 0, 0

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
appendInfoLine: "  Actual duration: ", fixed$(dur_intro, 2), " s"

# Fade Out for crossfade
selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 2: BODY (Neural Ambient Drone) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Neural Ambient Drone - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize Neural Ambient Drone Designer parameters
# Preset: random choice
drone_preset_choice = randomInteger(1, 6)
if drone_preset_choice = 1
    drone_preset$ = "Manual"
elsif drone_preset_choice = 2
    drone_preset$ = "Dark Ambient"
elsif drone_preset_choice = 3
    drone_preset$ = "Bright Shimmer"
elsif drone_preset_choice = 4
    drone_preset$ = "Dense Texture"
elsif drone_preset_choice = 5
    drone_preset$ = "Sparse Minimal"
else
    drone_preset$ = "Evolving Pad"
endif

# Duration: 15-30 seconds
drone_dur = randomUniform(15, 30)

# Layers: 3-6
drone_layers = randomInteger(3, 6)

# Crossfade: 15-50 ms
drone_crossfade = randomInteger(15, 50)

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

# Grain size: 60-180 ms
drone_grain = randomInteger(60, 180)

# Clusters: 3-6
drone_clusters = randomInteger(3, 6)

# K-means iterations: 5-15
drone_kmeans = randomInteger(5, 15)

# Stereo: always 1
drone_stereo = 1

# Stereo width: 0.5-0.95
drone_width = randomUniform(0.5, 0.95)

appendInfoLine: "  Preset: ", drone_preset$
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

# Neural Ambient Drone Designer parameters:
# Preset, Duration, Layers, Crossfade_ms, Shimmer, Shimmer_prob, Shimmer_intervals,
# Grain_ms, Clusters, Kmeans_iter, Stereo, Stereo_width, Play
runScript: path_body$, drone_preset$, drone_dur, drone_layers, drone_crossfade, 
    ... drone_shimmer, drone_shimmer_prob, drone_shimmer_intervals$, drone_grain, 
    ... drone_clusters, drone_kmeans, drone_stereo, drone_width, 0

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
appendInfoLine: "  Actual duration: ", fixed$(dur_body, 2), " s"

# Fade In for crossfade
selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# Fade Out for crossfade
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ==============================================================================
# PART 3: OUTRO (8-Channel Speed Deviations) - RANDOMIZED
# ==============================================================================
selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (8-Channel Deviations - Randomized) ==="
appendInfoLine: "  Generating random parameters..."

# Randomize 8-Channel Speed Deviations parameters
# Preset: random choice
spatial_preset_choice = randomInteger(1, 7)
if spatial_preset_choice = 1
    spatial_preset$ = "Custom (use mode below)"
elsif spatial_preset_choice = 2
    spatial_preset$ = "Subtle (±5%)"
elsif spatial_preset_choice = 3
    spatial_preset$ = "Moderate (±15%)"
elsif spatial_preset_choice = 4
    spatial_preset$ = "Wide (±30%)"
elsif spatial_preset_choice = 5
    spatial_preset$ = "Extreme (±50%)"
elsif spatial_preset_choice = 6
    spatial_preset$ = "Accelerando (0.7 to 1.3)"
else
    spatial_preset$ = "Decelerando (1.3 to 0.7)"
endif

# Mode: random choice (1=Automatic, 2=Manual, 3=Random)
spatial_mode_choice = randomInteger(1, 3)
if spatial_mode_choice = 1
    spatial_mode$ = "Automatic (using factor)"
elsif spatial_mode_choice = 2
    spatial_mode$ = "Manual (input all values)"
else
    spatial_mode$ = "Random deviation"
endif

# Speed deviation factor: 0.1-0.4
spatial_factor = randomUniform(0.1, 0.4)

# Manual channel speeds (random around 1.0)
spatial_ch1 = randomUniform(0.75, 0.90)
spatial_ch2 = randomUniform(0.85, 0.95)
spatial_ch3 = randomUniform(0.90, 0.98)
spatial_ch4 = randomUniform(0.95, 1.00)
spatial_ch5 = randomUniform(1.00, 1.05)
spatial_ch6 = randomUniform(1.05, 1.15)
spatial_ch7 = randomUniform(1.10, 1.20)
spatial_ch8 = randomUniform(1.15, 1.30)

# Random min/max: 0.7-1.3
spatial_min = randomUniform(0.70, 0.85)
spatial_max = randomUniform(1.15, 1.30)

# Random seed
spatial_seed = randomInteger(1, 1000)

# Pitch range: 60-100 Hz, 500-800 Hz
spatial_floor = randomInteger(60, 100)
spatial_ceiling = randomInteger(500, 800)

# Use original SR: always 1
spatial_use_sr = 1

# Target SR: 44100
spatial_target_sr = 44100

appendInfoLine: "  Preset: ", spatial_preset$
appendInfoLine: "  Mode: ", spatial_mode$
appendInfoLine: "  Factor: ", fixed$(spatial_factor, 2)
appendInfoLine: "  Ch speeds: ", fixed$(spatial_ch1, 2), ", ", fixed$(spatial_ch2, 2), 
    ... ", ", fixed$(spatial_ch3, 2), ", ", fixed$(spatial_ch4, 2), ", ", fixed$(spatial_ch5, 2), 
    ... ", ", fixed$(spatial_ch6, 2), ", ", fixed$(spatial_ch7, 2), ", ", fixed$(spatial_ch8, 2)
appendInfoLine: "  Random range: ", fixed$(spatial_min, 2), " - ", fixed$(spatial_max, 2)
appendInfoLine: "  Random seed: ", spatial_seed
appendInfoLine: "  Pitch floor: ", spatial_floor, " Hz"
appendInfoLine: "  Pitch ceiling: ", spatial_ceiling, " Hz"

# 8-Channel Speed Deviations parameters:
# Preset, Mode, Factor, ch1-8 speeds, min, max, seed, pitch_floor, pitch_ceil, 
# use_original_sr, target_sr, visualize, play
runScript: path_outro$, spatial_preset$, spatial_mode$, spatial_factor, 
    ... spatial_ch1, spatial_ch2, spatial_ch3, spatial_ch4, spatial_ch5, 
    ... spatial_ch6, spatial_ch7, spatial_ch8, spatial_min, spatial_max, spatial_seed, 
    ... spatial_floor, spatial_ceiling, spatial_use_sr, spatial_target_sr, 0, 0

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

final_name$ = initial_name$ + "_Composition2_Random"
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
appendInfoLine: "  LIVE 2 RANDOM COMPOSITION COMPLETE"
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
