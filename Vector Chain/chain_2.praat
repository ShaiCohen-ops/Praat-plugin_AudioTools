# ============================================================
# Praat AudioTools - Signal Chain 2 (Corrected)
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

# Parameters match the form in your file:
# 1. Preset (Manual)
# 2. Duration (20.0)
# 3. Layer density (3)
# 4. Crossfade (20)
# 5. Add octave shimmer (1)
# 6. Shimmer prob (0.15)
# 7. Shimmer intervals (Octaves only)
# 8. Grain size (100)
# 9. Clusters (3)
# 10. Iterations (10)
# 11. Stereo out (1)
# 12. Width (0.7)
# 13. Play result (0)

runScript: path2$, "Manual", 0, 20.0, 3, 20, 1, 0.15, "Octaves only", 100, 3, 10, 1, 0.7, 0

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
runScript: path3$, "Custom (use mode below)", "Automatic (using factor)", 0.15, 0.85, 0.88, 0.91, 0.94, 1.06, 1.09, 1.12, 1.15, 0.80, 1.20, 42, 75, 600, 1, 44100, 0, 1

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