# ============================================================
# Praat AudioTools - Signal Chain 2 (Corrected)
# Version: 1.1 - 8-channel_speed_deviations v0.5 compatibility
# Flow: Spiral Pitch -> Neural Drone -> 8-channel Deviations
# ============================================================

Erase all

# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 2 ---"

# --- Define Paths (Relative) ---
# Ensure these match your actual folder structure
path1$ = "../Pitch/Spiral_Pitch_Dance.praat"
path2$ = "../AI & Adaptive/Neural_Ambient_Drone_Designer.praat"
path3$ = "../Spatial & Surround/8-channel_speed_deviations.praat"

# ==============================================================================
# STEP 1: Spiral Pitch Dance
# ==============================================================================
selectObject: initial_sound
# Parameters: Preset, Num_bands, Start_freq, Ratio, Jitter, Speed_Hz, Range_cents, Feedback, Play
runScript: path1$, "Manual (configure below)", 2, 24, 1.5, 0.005, 50, 1200, 0, 0

# Capture output (Naming convention: [Name]_spiral_[Preset])
expected_name_1$ = initial_name$ + "_spiral_Manual"
selectObject: "Sound " + expected_name_1$
sound2 = selected("Sound")
appendInfoLine: "Step 1: Spiral Pitch Dance complete."

# ==============================================================================
# STEP 2: Neural Ambient Drone Designer
# ==============================================================================
# Updated to match Version 0.4 parameters found in your uploaded file.
# Note: The output name now includes the preset name (e.g., "Manual").
selectObject: sound2

# Parameters match the form in Neural_Ambient_Drone_Designer.praat (v0.9, 13 args):
# 1. Preset (Manual)
# 2. Output_duration_sec (20.0)
# 3. Number_of_layers (3)
# 4. Grain_size_ms (100)
# 5. Grain_crossfade_ms (20)
# 6. Add_octave_shimmer (1)
# 7. Shimmer_probability (0.15)
# 8. Shimmer_intervals (Octaves only)
# 9. Number_of_clusters (3)
# 10. Kmeans_iterations (10)
# 11. Stereo_width (0.7)
# 12. Seed (0)
# 13. Play_result (0)

runScript: path2$, "Manual", 20.0, 3, 100, 20, 1, 0.15, "Octaves only", 3, 10, 0.7, 0, 0

# FIX: Output name is "_ClusterDrone_Manual" (matches Rename in
# Neural_Ambient_Drone_Designer.praat, which uses "_ClusterDrone_" +
# presetName$, not "_NeuralDrone_")
expected_name_2$ = expected_name_1$ + "_ClusterDrone_Manual"
selectObject: "Sound " + expected_name_2$
sound3 = selected("Sound")
appendInfoLine: "Step 2: Neural Drone complete."

# ==============================================================================
# STEP 3: 8-Channel Speed Deviations
# ==============================================================================
selectObject: sound3

# FIX: Updated to the current 8-channel_speed_deviations form. The old
# 22-arg call predates a compact-form rewrite that collapsed two groups of
# individual fields into single space-separated sentence fields:
#   - the 8 "Channel_N_speed" reals -> one "Manual speeds" sentence
#     ("Ch1..Ch8" values separated by spaces)
#   - the 2 "Min_pitch"/"Max_pitch" reals -> one "Pitch range" sentence
#     ("Min Max" separated by a space)
# The old positional call (with 8 separate channel-speed args and 2 separate
# pitch args) no longer aligns with any field past Speed_deviation_factor.
# The Manual speeds field is still parsed and validated even in Automatic
# mode, so it's passed through unchanged as one string.
#
# Current main-form signature (14 args):
#   Preset, Mode, Speed_deviation_factor, Manual_speeds, Random_min_speed,
#   Random_max_speed, Random_seed, Pitch_range, Override_sampling_frequency,
#   Target_sampling_frequency, Output_format, Scale_peak,
#   Draw_visualization, Play_result
runScript: path3$, "Custom (use mode below)", "Automatic (using factor)", 0.15, "0.85 0.88 0.91 0.94 1.06 1.09 1.12 1.15", 0.80, 1.20, 42, "75 600", 1, 44100, "8 channels - octophonic (Ch1-Ch8)", 0.95, 0, 1

# Capture final output (Praat leaves the last created object selected)
sound4 = selected("Sound")
final_name$ = selected$("Sound")

appendInfoLine: "Step 3: 8-Channel Deviations complete. Chain finished."

# ==============================================================================
# VISUALIZATION
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 16
Text: 5, "centre", 5, "half", "Spiral Pitch -> Neural Drone -> 8-Ch Deviations"

# Select the actual final result
selectObject: sound4