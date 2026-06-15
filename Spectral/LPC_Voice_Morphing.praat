# ============================================================
# Praat AudioTools - LPC_Voice_Morphing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - Stereo-safe mono analysis; spectrogram viewports
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LPC Vocoder - resynthesizes sound using pulse train or noise
#   excitation filtered through LPC spectral envelope.
# ============================================================

form LPC Vocoder Pro v0.3
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Natural Resynthesis
        option Robot Voice (Monotone)
        option Whisper (True Noise)
        option Deep Demon
    
    comment === SOURCE PARAMETERS ===
    positive Time_step 0.01
    positive Minimum_pitch 75
    positive Maximum_pitch 600
    boolean Force_monotone 0
    positive Monotone_frequency 120
    
    comment === LPC FILTER PARAMETERS ===
    comment (0 = Auto-calculate based on sample rate)
    integer LPC_order 0
    positive Analysis_window 0.025
    positive Pre_emphasis_hz 50
    
    comment === OUTPUT ===
    positive Target_intensity_dB 70
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# --- 1. PRESET LOGIC ---

source_type = 1 
# 1=Pulse (Voiced), 2=Noise (Whisper)

if preset = 2
    # Natural
    lPC_order = 0
    analysis_window = 0.025
    force_monotone = 0
    presetName$ = "Natural"
elsif preset = 3
    # Robot
    lPC_order = 0
    analysis_window = 0.030
    force_monotone = 1
    monotone_frequency = 100
    presetName$ = "Robot"
elsif preset = 4
    # Whisper
    lPC_order = 0
    analysis_window = 0.015 
    source_type = 2
    presetName$ = "Whisper"
elsif preset = 5
    # Deep Demon
    lPC_order = 0
    analysis_window = 0.040
    minimum_pitch = 50
    force_monotone = 0
    presetName$ = "DeepDemon"
else
    presetName$ = "Custom"
endif

# --- 2. SETUP & CALIBRATION ---

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
numChannels = Get number of channels

# Pitch / LPC / Filter require a mono signal. Build a mono analysis copy
# (the original is kept untouched for the visualization).
if numChannels > 1
    selectObject: originalID
    analysisID = Convert to mono
    Rename: "analysis_mono"
else
    selectObject: originalID
    analysisID = Copy: "analysis_mono"
endif

# Auto-Calculate LPC Order if set to 0
# Formula: (SamplingRate / 1000) + 2 to 4
if lPC_order = 0
    lPC_order = round(sr / 1000) + 4
    writeInfoLine: "Auto-calibrated LPC Order to: ", lPC_order, " poles"
else
    writeInfoLine: "Using manual LPC Order: ", lPC_order
endif

appendInfoLine: "Processing source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# --- 3. SOURCE GENERATION (Excitation) ---

selectObject: analysisID

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
        monoStr$ = fixed$(monotone_frequency, 2)
        Formula: monoStr$
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
selectObject: analysisID
# Standard LPC (Autocorrelation)
To LPC (autocorrelation): lPC_order, analysis_window, 0.005, pre_emphasis_hz
lpcID = selected("LPC")
appendInfoLine: " done."

# --- 5. SYNTHESIS (Filtering) ---

appendInfo: "Vocoding..."
selectObject: lpcID
plusObject: sourceID
Filter: "no"
vocodedID = selected("Sound")
Rename: originalName$ + "_vocoded_" + presetName$
appendInfoLine: " done."

# --- 6. POST-PROCESSING ---

# A. Gain Compensation
Scale intensity: target_intensity_dB

# B. Whisper Brightness Correction
if preset = 4
    # Whispers need a high-frequency tilt to sound intelligible
    Formula: "self + 0.5 * (self - self[col-1])"
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "LPC Vocoder: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Vocoded waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: vocodedID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Vocoded"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    Select inner viewport: 0.5, 3.7, 2.15, 3.65
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Vocoded spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    Select inner viewport: 4.5, 7.7, 2.15, 3.65
    selectObject: vocodedID
    resSpecID = To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Vocoded Spectrogram"
    removeObject: resSpecID
    
    # Info panel
    Select outer viewport: 0, 8, 4.0, 4.6
    Select inner viewport: 0.5, 7.7, 4.05, 4.55
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "LPC: " + string$(lPC_order)
    if source_type = 1
        Text: 0.15, "left", 0.5, "half", "Source: Pulse"
    else
        Text: 0.15, "left", 0.5, "half", "Source: Noise"
    endif
    if force_monotone
        Text: 0.35, "left", 0.5, "half", "Monotone: " + string$(monotone_frequency) + " Hz"
    else
        Text: 0.35, "left", 0.5, "half", "Pitch: " + string$(minimum_pitch) + "-" + string$(maximum_pitch)
    endif
    Text: 0.6, "left", 0.5, "half", "Window: " + fixed$(analysis_window * 1000, 0) + " ms"
    Text: 0.8, "left", 0.5, "half", "Intensity: " + string$(target_intensity_dB) + " dB"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# --- 7. CLEANUP ---

removeObject: sourceID
removeObject: lpcID
removeObject: analysisID

selectObject: originalID
plusObject: vocodedID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", originalName$, "_vocoded_", presetName$

if play_result
    selectObject: vocodedID
    Play
endif