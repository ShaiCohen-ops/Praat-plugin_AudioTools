Erase all
# 1. Preparation
numSelected = numberOfSelected("Sound")
if numSelected <> 1
    exitScript: "Please select exactly one Sound object to start the chain."
endif

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")
appendInfoLine: "--- Starting AudioTools Chain 3 ---"

# --- Define Paths (Relative) ---
path1$ = "../Filter & Color/Whisper Morph.praat"
path2$ = "../Pitch/Bimodal Contour Grammar.praat"
path3$ = "../Time & Granular/Percussive Audio Groove Creator.praat"

# ==============================================================================
# STEP 1: Whisper Morph
# ==============================================================================
selectObject: initial_sound
runScript: path1$, "Gentle Whisper", "Dry to Wet (original -> whisper)", 1.0, 0.8, 6.0, "Smooth (cosine)", 0, 0

# Select Output
expected_name_1$ = initial_name$ + "_whispermorph"
selectObject: "Sound " + expected_name_1$
sound2 = selected("Sound")

# ==============================================================================
# STEP 2: Bimodal Contour Grammar
# ==============================================================================
selectObject: sound2
runScript: path2$, 0, 1000, 500, "Pitch+Loudness Rainbow", "Thin continuous line", 1.0, 4.0, 70, 10, 0, 0, 0

# Select Output
expected_name_2$ = expected_name_1$ + "_grammar"
selectObject: "Sound " + expected_name_2$
sound3 = selected("Sound")

# ==============================================================================
# STEP 3: Percussive Audio Groove Creator
# ==============================================================================
selectObject: sound3
# Play_result set to 1 (Enabled)
runScript: path3$, "4 bars", "Breakbeat", 120, -20, 0.05, 0.15, 0.6, 0.12, 0.002, 0.05, 1.2, 1, 0, 1

# Select Output
sound4 = selected("Sound")

# ==============================================================================
# VISUALIZATION 
# ==============================================================================
Erase all
Select outer viewport: 0, 8, 0.1, 3.5
Axes: 0, 10, 0, 10
Font size: 16
Text: 5, "centre", 5, "half", "Whisper Morph -> Bimodal Contour -> Groove Creator"

selectObject: sound4