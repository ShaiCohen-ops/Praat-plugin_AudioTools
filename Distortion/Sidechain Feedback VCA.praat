# ============================================================
# Praat AudioTools - Sidechain Feedback VCA
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   AUDIO-REACTIVE NO-INPUT MIXER - Sidechain Feedback VCA
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
clearinfo
# --------------------------------------------------------------------------
# AUDIO-REACTIVE NO-INPUT MIXER - Sidechain Feedback VCA
# --------------------------------------------------------------------------
# 1. Select a Sound object in the list.
# 2. Run this script.
# --------------------------------------------------------------------------

# --- 1. Validation ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object to act as the controller."
endif

# Capture Input ID (Robust method)
input_Sound_ID = selected("Sound")
selectObject: input_Sound_ID
input_Name$ = selected$("Sound")
duration = Get total duration
sample_Rate = Get sampling frequency
n_channels = Get number of channels

printline [Analysis] Analyzing input: 'input_Name$' ('duration's)...

# --- 2. Feature Extraction (The "Knobs") ---

# A. Extract Pitch (Controls Resonance Center)
selectObject: input_Sound_ID

# If Stereo, create a temporary mono version for Pitch analysis
if n_channels > 1
    Convert to mono
    temp_Mono_ID = selected("Sound")
    selectObject: temp_Mono_ID
    To Pitch: 0.0, 75, 600
else
    To Pitch: 0.0, 75, 600
endif

pitch_ID = selected("Pitch")
selectObject: pitch_ID
mean_Pitch = Get mean: 0, 0, "Hertz"

# Safety: If unpitched (percussive), default to low rumble
if mean_Pitch = undefined
    mean_Pitch = 100
    printline ... No pitch detected. Defaulting Resonance to 100 Hz.
else
    printline ... Detected Input Pitch: 'mean_Pitch' Hz (Tuning Circuit...)
endif

# Cleanup Pitch Analysis files
selectObject: pitch_ID
Remove
if n_channels > 1
    selectObject: temp_Mono_ID
    Remove
endif

# B. Extract Intensity (Controls Feedback Gain)
selectObject: input_Sound_ID
To Intensity: 100, 0, "yes"
intensity_ID = selected("Intensity")

# FIX: Convert Intensity -> Matrix -> Sound
Down to Matrix
matrix_ID = selected("Matrix")
To Sound
Rename: "Control_Signal_Raw"
control_Raw_ID = selected("Sound")

# Resample Control Signal to match Input Sample Rate
Resample: sample_Rate, 50
Rename: "Control_Signal"
control_Final_ID = selected("Sound")

# Cleanup Intermediate Analysis files
selectObject: intensity_ID
plusObject: matrix_ID
plusObject: control_Raw_ID
Remove

# --- 3. UI Parameters ---

form Audio-Reactive Mixer Parameters
    comment The input file ('input_Name$') controls the knobs!
    
    comment Circuit Behavior
    positive Base_Feedback 0.8
    positive Input_Sensitivity 0.5
    # How much the input volume adds to feedback. 
    # High sensitivity = Loud input drives circuit into chaos.
    
    positive Damping_Factor 0.92
    positive Iterations 40
    
    comment Resonance
    # We use the Input Pitch, but you can offset it.
    real Frequency_Offset_(Hz) 0.0
    positive Bandwidth_(Hz) 150
    positive Analog_Instability 0.05
    
    optionmenu Spatial_Mode: 2
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
endform

# --- 4. Prepare Control Signal ---
selectObject: control_Final_ID
# Rename specifically for the Formula lookup
Rename: "VCA_Automation"
# Normalize roughly 0 to 1
Scale peak: 1.0
# Apply sensitivity curve
Formula: "'base_Feedback' + (self * 'input_Sensitivity')"
# Clip to safe limits
Formula: "if self > 1.8 then 1.8 else self fi"

# --- 5. Initialize Circuit ---
printline [Circuit] Initializing feedback loop...
Create Sound from formula: "Noise_L", 1, 0, duration, sample_Rate, "randomGauss(0, 0.0001)"
Create Sound from formula: "Noise_R", 1, 0, duration, sample_Rate, "randomGauss(0, 0.0001)"
Combine to stereo
Rename: "StereoLoop"
selectObject: "Sound Noise_L"
plusObject: "Sound Noise_R"
Remove

# Set Center Frequency based on Input
resonance_Center = mean_Pitch + frequency_Offset

# --- 6. The Loop ---
printline [Processing] Running 'iterations' iterations...

for i from 1 to iterations
    selectObject: "Sound StereoLoop"
    Copy: "FeedbackPath"
    
    # --- Dynamic Drift (LFO) ---
    drift_hz = resonance_Center * analog_Instability
    current_freq = resonance_Center + randomGauss(0, drift_hz)
    width_drift = bandwidth * analog_Instability
    current_width = bandwidth + randomGauss(0, width_drift)
    
    # Safety Clamps
    if current_freq < 50
        current_freq = 50
    endif
    if current_width < 10
        current_width = 10
    endif

    # --- Filter Stage ---
    Filter (pass Hann band): current_freq - (current_width/2), current_freq + (current_width/2), 20
    Rename: "FilteredSignal"
    
    # --- Mixing Stage (VCA) ---
    selectObject: "Sound StereoLoop"
    
    # THE MAGIC FORMULA:
    # Multiplies loop by the VCA Automation curve (extracted from input intensity)
    Formula: "2/pi * arctan( (self * damping_Factor) + (Sound_FilteredSignal[] * Sound_VCA_Automation[]) )"
    
    # Cleanup Loop
    selectObject: "Sound FeedbackPath"
    plusObject: "Sound FilteredSignal"
    Remove
endfor

# --- 7. Spatial Post-Processing ---
selectObject: "Sound StereoLoop"

# Safety Check: Ensure Stereo
n_ch_loop = Get number of channels
if n_ch_loop = 1
    Convert to stereo
    Rename: "StereoLoop_Fixed"
    selectObject: "Sound StereoLoop"
    Remove
    selectObject: "Sound StereoLoop_Fixed"
    Rename: "StereoLoop"
endif

printline [Spatial] Applying Mode: 'spatial_Mode$'...

if spatial_Mode$ = "Mono"
    Convert to mono
    Rename: "Final_Output"
else
    selectObject: "Sound StereoLoop"
    Extract all channels
    
    # Robust ID Capture for Spatial Processing
    id_L = selected("Sound", 1)
    id_R = selected("Sound", 2)
    
    selectObject: id_L
    Rename: "Ch_1"
    
    selectObject: id_R
    Rename: "Ch_2"
    
    if spatial_Mode$ = "Stereo Wide"
        selectObject: "Sound Ch_1"
        Filter (pass Hann band): 0, 4000, 100
        Rename: "Ch_1_filtered"
        selectObject: "Sound Ch_2"
        Filter (pass Hann band): 200, 22050, 100
        Rename: "Ch_2_filtered"
        
    elsif spatial_Mode$ = "Rotating"
        rotation_rate = 0.2
        selectObject: "Sound Ch_1"
        Copy: "Ch_1_filtered"
        Formula: "self * (0.6 + cos(2*pi*'rotation_rate'*x) * 0.4)"
        selectObject: "Sound Ch_2"
        Copy: "Ch_2_filtered"
        Formula: "self * (0.6 + sin(2*pi*'rotation_rate'*x) * 0.4)"
        
    elsif spatial_Mode$ = "Binaural"
        selectObject: "Sound Ch_1"
        Filter (pass Hann band): 50, 3000, 80
        Rename: "Ch_1_filtered"
        selectObject: "Sound Ch_2"
        Formula: "if col > 30 then self[col - 30] else 0 fi"
        Filter (pass Hann band): 200, 6000, 80
        Rename: "Ch_2_filtered"
    endif
    
    selectObject: "Sound Ch_1_filtered"
    plusObject: "Sound Ch_2_filtered"
    Combine to stereo
    Rename: "Final_Output"
    
    # Robust Cleanup
    selectObject: "Sound Ch_1_filtered"
    plusObject: "Sound Ch_2_filtered"
    Remove
    selectObject: "Sound Ch_1"
    plusObject: "Sound Ch_2"
    Remove
endif

if spatial_Mode$ <> "Mono"
    selectObject: "Sound StereoLoop"
    Remove
endif

# Cleanup Control Signal
selectObject: "Sound VCA_Automation"
Remove

# --- 8. Final Output ---
selectObject: "Sound Final_Output"
Scale peak: 0.95
Play

printline Done. The feedback loop was driven by 'input_Name$'.