# ============================================================
# Praat AudioTools - Signal Chain 6
# Flow: Phase Shaper -> Phase Modulation Matrix -> BPM Panning
# Praat 7 path compatibility update
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

# --- Define Paths (Praat 7 compatible) ---
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

path1$ = pluginPath$ + "Spectral/Phase_Shaper.praat"
path2$ = pluginPath$ + "Time & Granular/Phase_Modulation_Matrix.praat"
path3$ = pluginPath$ + "Spatial & Surround/BPM_Panning.praat"

# Praat 7 / script-relative fallback
if not fileReadable(path1$)
    path1$ = defaultDirectory$ + "/../Spectral/Phase_Shaper.praat"
endif
if not fileReadable(path2$)
    path2$ = defaultDirectory$ + "/../Time & Granular/Phase_Modulation_Matrix.praat"
endif
if not fileReadable(path3$)
    path3$ = defaultDirectory$ + "/../Spatial & Surround/BPM_Panning.praat"
endif

path1$ = replace_regex$(path1$, "\\", "/", 0)
path2$ = replace_regex$(path2$, "\\", "/", 0)
path3$ = replace_regex$(path3$, "\\", "/", 0)

if not fileReadable(path1$)
    exitScript: "Cannot find Phase_Shaper.praat"
endif
if not fileReadable(path2$)
    exitScript: "Cannot find Phase_Modulation_Matrix.praat"
endif
if not fileReadable(path3$)
    exitScript: "Cannot find BPM_Panning.praat"
endif

# ==============================================================================
# STEP 1: Phase Shaper
# ==============================================================================
selectObject: initial_sound

# Phase Shaper v0.4 parameters (9 args):
# Mode, Preset, Intensity, Wet_dry_percent, Trim_to_original,
# Stereo_output, Scale_peak, Draw_visualization, Play_result
runScript: path1$, "Hyper-Dispersion (sweeping drone)", "Custom (use intensity below)", 1, 100, "no", "yes", 0.95, "yes", "no"

# Capture output
sound2 = selected("Sound")
appendInfoLine: "Step 1: Phase Shaper complete."

# ==============================================================================
# STEP 2: Phase Modulation Matrix
# ==============================================================================
selectObject: sound2

# Phase Modulation Matrix v0.3 parameters (16 args):
# Preset, Layers, CarMin, CarMax, FixedCar, FixedFreq, ModBase, ModIncr,
# FixedMsDepth, DepthMs, Feedback, GainBase, GainRate, Scale, Draw, Play
runScript: path2$, "Default (balanced)", 5, 0.1, 0.5, "no", 0.3, 8, 2, "no", 20, 0.7, 1.1, 0.1, 0.93, "yes", "no"

# Capture output
sound3 = selected("Sound")
appendInfoLine: "Step 2: Phase Modulation Matrix complete."

# ==============================================================================
# STEP 3: BPM Stereo Panning
# ==============================================================================
selectObject: sound3

# BPM Panning v0.4 parameters (11 args):
# Tempo_bpm, Subdivision, Swing_percent, Accent_grid, Pattern,
# Edge_transition_percent, Stereo_input, Output_normalisation,
# Peak_target, Draw_visualization, Play_result
runScript: path3$, 120, "1/16 (sixteenth notes)", 50, "1010100110101001", "1.  Ping-pong (hard L/R alternation)", 0.3, "Downmix to mono and pan (true panning)", "Peak (scale to target)", 0.95, 0, 1

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
