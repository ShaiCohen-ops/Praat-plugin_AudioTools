# ============================================================
# Praat AudioTools - Chain 3
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   This script executes a sequential processing chain using three
#   AudioTools modules:
#   1. Whisper Morph - Morphs the original sound into a whisper.
#   2. Bimodal Contour Grammar - Generates and applies a contour based on custom grammatical rules.
#   3. Percussive Audio Groove Creator - Embeds a rhythmic breakbeat into the resulting audio.
#
#   The script concludes by generating a visual text summary of the
#   pipeline in the Praat Picture window.
#
# Changelog v1.1:
#   - Updated Whisper_Morph call to the v1.3 11-argument form signature.
# ============================================================

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
path1$ = "../Filter & Color/Whisper_Morph.praat"
path2$ = "../Pitch/Bimodal_Contour_Grammar.praat"
path3$ = "../Time & Granular/Percussive Audio Groove Creator.praat"

# ==============================================================================
# STEP 1: Whisper Morph
# ==============================================================================
selectObject: initial_sound

# Whisper Morph v1.3 parameters (11 args):
# Preset, Morph_type, LPC_order_factor, Breathiness, Brightness_adjust_dB,
# Gate_range_dB, Random_seed, Morph_curve, Safety_peak,
# Draw_visualization, Play_result
runScript: path1$, "Gentle Whisper", "Dry to Wet (original -> whisper)", 1.0, 0.8, 0.0, 40, 0, "Smooth (cosine)", 0.99, 0, 0

# Select Output
expected_name_1$ = initial_name$ + "_whispermorph"
selectObject: "Sound " + expected_name_1$
sound2 = selected("Sound")

# ==============================================================================
# STEP 2: Bimodal Contour Grammar
# ==============================================================================
selectObject: sound2

# 16 arguments for Bimodal Contour Grammar v0.5
runScript: path2$, "Custom", 100, 200, 1.0, 1.0, 5.0, 0, "Pitch+Loudness Rainbow", "Thin continuous line", 1.0, 4.0, 70, 10, 0, 0, 0

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
