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

# --- Define Paths (Absolute via preferencesDirectory$) ---
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

path1$ = pluginPath$ + "Spectral/Phase Shaper.praat"
path2$ = pluginPath$ + "Time & Granular/Phase_Modulation_Matrix.praat"
path3$ = pluginPath$ + "Spatial & Surround/BPM_Panning.praat"

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

# FIX: Updated to the correct 8-argument signature matching Live_6
# Parameters: Tempo_bpm, Subdivision, Swing_percent, Accent_grid, Pattern, Edge_smoothness, Draw, Play
runScript: path3$, 120, "1/16 (sixteenth notes)", 50, "1010100110101001", "1.  Ping-pong (hard L/R alternation)", 0.3, 0, 1

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
