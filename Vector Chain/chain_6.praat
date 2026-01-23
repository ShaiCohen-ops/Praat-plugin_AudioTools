# ============================================================
# Praat AudioTools - Signal Chain 6 (Fixed)
# Flow: Phase Shaper -> Phase Modulation Matrix -> BPM Panning
# ============================================================

Erase all

# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 6 ---"

# --- Define Paths (Relative) ---
path1$ = "../Spectral/Phase Shaper.praat"
path2$ = "../Time & Granular/Phase_Modulation_Matrix.praat"
path3$ = "../Spatial & Surround/BPM_Panning.praat"

# ==============================================================================
# STEP 1: Phase Shaper
# ==============================================================================
selectObject: initial_sound
# Parameters: Mode, Preset, Intensity, IR_Dur, Trim, Stereo, Mix, Draw, Play
runScript: path1$, "Hyper-Dispersion (sweeping drone)", "Custom (use intensity below)", 1, 100, "no", "yes", 0.95, "yes", "no"

# Capture output (Phase Shaper appends mode name)
sound2 = selected("Sound")
appendInfoLine: "Step 1: Phase Shaper complete."

# ==============================================================================
# STEP 2: Phase Modulation Matrix
# ==============================================================================
selectObject: sound2
# Parameters: Preset, Layers, CarMin, CarMax, FixedCar, FixedFreq, ModMin, ModMax, FeedMin, FeedMax, Spread, Mix, Draw, Play
runScript: path2$, "Default (balanced)", 5, 0.1, 0.5, "no", 0.3, 8, 2, 0.7, 1.1, 0.1, 0.93, "yes", "no"

# Capture output
sound3 = selected("Sound")
appendInfoLine: "Step 2: Phase Modulation Matrix complete."

# ==============================================================================
# STEP 3: BPM Stereo Panning
# ==============================================================================
selectObject: sound3

# FIX: Changed "1. Circle..." to the valid option "1. Spiral (accelerating)"
# Parameters: Cycles, Pattern, Draw, Play
runScript: path3$, "8 cycles (medium)", "1. Spiral (accelerating)", "yes", "yes"

# Capture final output
sound4 = selected("Sound")
final_name$ = selected$("Sound")

appendInfoLine: "Step 3: BPM Panning complete."
appendInfoLine: "Chain finished. Final Output: ", final_name$

# ==============================================================================
# VISUALIZATION
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 14
Text: 5, "centre", 5, "half", "Phase Shaper -> Phase Mod -> BPM Panning"

selectObject: sound4