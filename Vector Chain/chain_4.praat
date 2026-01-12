# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 4 (Cubic) ---"

# --- Define Paths (Relative) ---
path1$ = "../Modulation/Metamodulator.praat"
path2$ = "../Time & Granular/Adaptive Grain Cloud Synthesis.praat"
path3$ = "../Spatial & Surround/8-Channel_Comb_Delay.praat"

# ==============================================================================
# STEP 1: Metamodulator (Cubic Phase Distortion)
# ==============================================================================
selectObject: initial_sound
# FIX: Changed Preset to "Cubic: Strong Distortion"
# Args: Preset, Manual_Algo, F_carrier, F_start, F_end, Mod_factor, Mod_rate, Scale, Viz, Play
runScript: path1$, "Cubic: Strong Distortion", "1. Cubic Phase Distortion", 200, 100, 800, 2.0, 5.0, 0.95, 0, 0

# Select Output
sound2 = selected("Sound")
appendInfoLine: "Step 1: Metamodulator (Cubic) complete."

# ==============================================================================
# STEP 2: Adaptive Grain Cloud Synthesis
# ==============================================================================
selectObject: sound2
# Args: Preset, Grain_size, Overlap, Density, Pitch_scatter, Pos_scatter, 
#       Adaptive_dur, Rev_random, Out_dur_factor, Viz, Play
runScript: path2$, "Dense Cloud", 50, 0.5, 2.0, 0.0, 0.2, 1, 0, 1.0, 0, 0

# Select Output
sound3 = selected("Sound")
appendInfoLine: "Step 2: Grain Cloud complete."

# ==============================================================================
# STEP 3: 8-Channel Comb Delay
# ==============================================================================
selectObject: sound3
# Args: Preset, D1-D8, Reverse_even, Scale_peak, Viz, Play
runScript: path3$, "Linear (2,4,6,8,10,12,14,16)", 2, 4, 6, 8, 10, 12, 14, 16, 0, 0.99, 0, 1

# Select Output
sound4 = selected("Sound")

# ==============================================================================
# VISUALIZATION (Simple Text)
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 16
Text: 5, "centre", 5, "half", "Cubic Phase Distortion -> Adaptive Grain Cloud -> 8-Channel Comb Delay"

selectObject: sound4