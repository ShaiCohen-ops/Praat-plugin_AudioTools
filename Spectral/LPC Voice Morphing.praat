# ============================================================
# Praat AudioTools - LPC Voice Morphing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# ============================================================
# LPC Vocoder Pro 
# ============================================================

form LPC Vocoder Pro
    comment === PRESETS ===
    optionmenu preset: 1
        option Custom
        option Natural Resynthesis
        option Robot Voice (Monotone)
        option Whisper (True Noise)
        option Deep Demon
    
    comment === SOURCE PARAMETERS ===
    positive time_step 0.01
    positive minimum_pitch 75
    positive maximum_pitch 600
    boolean force_monotone 0
    positive monotone_frequency 120
    
    comment === LPC FILTER PARAMETERS ===
    comment (0 = Auto-calculate based on sample rate)
    integer lpc_order 0
    positive analysis_window 0.025
    positive pre_emphasis_hz 50
    
    comment === OUTPUT ===
    positive target_intensity_db 70
    boolean play_after_processing 1
endform

# --- 1. PRESET LOGIC ---

source_type = 1 
# 1=Pulse (Voiced), 2=Noise (Whisper)

if preset = 2
    # Natural
    lpc_order = 0
    analysis_window = 0.025
    force_monotone = 0
elsif preset = 3
    # Robot
    lpc_order = 0
    analysis_window = 0.030
    force_monotone = 1
    monotone_frequency = 100
elsif preset = 4
    # Whisper
    lpc_order = 0
    analysis_window = 0.015 
    source_type = 2
elsif preset = 5
    # Deep Demon
    lpc_order = 0
    analysis_window = 0.040
    minimum_pitch = 50
    force_monotone = 0
endif

# --- 2. SETUP & CALIBRATION ---

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration

# Auto-Calculate LPC Order if set to 0
# Formula: (SamplingRate / 1000) + 2 to 4
if lpc_order = 0
    lpc_order = round(sr / 1000) + 4
    writeInfoLine: "Auto-calibrated LPC Order to: ", lpc_order, " poles"
else
    writeInfoLine: "Using manual LPC Order: ", lpc_order
endif

appendInfoLine: "Processing source: ", originalName$

# --- 3. SOURCE GENERATION (Excitation) ---

selectObject: originalID

if source_type = 1
    # --- VOICED SOURCE (PULSE TRAIN) ---
    appendInfo: "Generating glottal source..."
    
    # Extract Pitch
    To Pitch: time_step, minimum_pitch, maximum_pitch
    pitchID = selected("Pitch")
    
    # Convert to PitchTier for manipulation
    Down to PitchTier
    ptID = selected("PitchTier")
    
    if preset = 5
        # Deep Demon pitch shift
        Formula: "self * 0.6"
    endif
    
    if force_monotone
        # Flatten the pitch tier
        Formula: "monotone_frequency"
    endif
    
    # Conversion Chain: PitchTier -> Pitch -> PointProcess -> Sound
    # We must convert PitchTier back to Pitch to get the PointProcess
    selectObject: ptID
    To Pitch: time_step, minimum_pitch, maximum_pitch
    modPitchID = selected("Pitch")
    
    To PointProcess
    ppID = selected("PointProcess")
    
    # THE FIX: 7 Arguments exactly
    # 1. Sampling freq, 2. Adaptation(1.0), 3. Max Period(0.05)
    # 4. OpenPhase(0.7), 5. CollisionPhase(0.03), 6. Power1(3.0), 7. Power2(4.0)
    To Sound (phonation): sr, 1.0, 0.05, 0.7, 0.03, 3.0, 4.0
    sourceID = selected("Sound")
    Rename: "excitation_pulse"
    
    # Clean up intermediate pitch objects
    removeObject: pitchID, ptID, modPitchID, ppID
    
else
    # --- UNVOICED SOURCE (WHISPER) ---
    appendInfo: "Generating noise source..."
    # Gaussian noise provides a better "whisper" texture than uniform noise
    sourceID = Create Sound from formula: "excitation_noise", 1, 0, dur, sr, "randomGauss(0,0.2)"
endif

appendInfoLine: " done."

# --- 4. FILTER GENERATION (LPC) ---

appendInfo: "Analyzing spectral envelope..."
selectObject: originalID
# Standard LPC (Autocorrelation)
To LPC (autocorrelation): lpc_order, analysis_window, 0.005, pre_emphasis_hz
lpcID = selected("LPC")
appendInfoLine: " done."

# --- 5. SYNTHESIS (Filtering) ---

appendInfo: "Vocoding..."
selectObject: lpcID, sourceID
Filter: "no"
vocodedID = selected("Sound")
Rename: originalName$ + "_vocoded"
appendInfoLine: " done."

# --- 6. POST-PROCESSING ---

# A. Gain Compensation
Scale intensity: target_intensity_db

# B. Whisper Brightness Correction
if preset = 4
    # Whispers need a high-frequency tilt to sound intelligible
    Formula: "self + 0.5 * (self - self[col-1])"
endif

# --- 7. CLEANUP ---

removeObject: sourceID
removeObject: lpcID

selectObject: vocodedID
appendInfoLine: "✓ Complete."

if play_after_processing
    Play
endif