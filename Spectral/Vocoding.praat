# ============================================================
# Praat AudioTools - Vocoding.praat
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

# Poly-Carrier Vocoder (Expanded Stereo Version)
# Features: Stereo Spreading, Formant Shifting, Noise Injection

form Poly-Carrier Vocoder (Expanded)
    comment --- Vocoder Style ---
    optionmenu Carrier_type: 2
        option 1. Noise (Whisper)
        option 2. Robot Drone (Sawtooth)
        option 3. Pitch-Tracking (Pulse)
    
    positive Robot_pitch_hz 100
    
    comment --- Expansions ---
    integer Frequency_shift_bands 0
    comment (Negative = Deeper/Bigger, Positive = Higher/Smaller)
    positive High_freq_noise_threshold 3500
    comment (Frequencies above this use Noise for crisp consonants)
    
    comment --- Bands ---
    natural Number_of_bands 20
    positive Lower_freq_limit 50
    positive Upper_freq_limit 7500
    
    comment --- Envelope ---
    positive Envelope_smoothness_hz 100
    
    comment --- Output ---
    boolean Play_after 1
endform

# --- SETUP ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

writeInfoLine: "--- Super Vocoder Processing ---"

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
orig_sr = Get sampling frequency
n_channels = Get number of channels

# --- 1. PRE-CALCULATE PITCH (If needed) ---
if carrier_type = 3
    appendInfoLine: "Extracting pitch..."
    selectObject: orig_id
    if n_channels > 1
        tmp_mono = Convert to mono
        selectObject: tmp_mono
    else
        Copy: "tmp_mono"
        tmp_mono = selected("Sound")
    endif
    
    pitch_id = To Pitch: 0.0, 75, 600
    selectObject: pitch_id
    pp_id = To PointProcess
    
    removeObject: tmp_mono
    removeObject: pitch_id
endif

# --- 2. PREPARE INPUT ---
selectObject: orig_id
if n_channels > 1
    input_id = Convert to mono
else
    input_id = Copy: "input"
endif

selectObject: input_id
dur = Get total duration
Rename: "Modulator"

# --- 3. GENERATE CARRIERS ---
appendInfoLine: "Generating carriers..."

# A. The Main Carrier (Robot/Pulse)
if carrier_type = 1
    Create Sound from formula: "Carrier_Main", 1, 0, dur, orig_sr, "randomGauss(0, 0.2)"
elsif carrier_type = 2
    s_pitch$ = string$(robot_pitch_hz)
    # Using your preferred formula
    Create Sound from formula: "Carrier_Main", 1, 0, dur, orig_sr, "0.2 * 2 * (x * " + s_pitch$ + " - floor(0.5 + x * " + s_pitch$ + "))"
elsif carrier_type = 3
    selectObject: pp_id
    To Sound (pulse train): orig_sr, 1, 0.05, 2000
    Scale peak: 0.2
    Rename: "Carrier_Main"
    removeObject: pp_id
endif
carrier_main_id = selected("Sound")

# B. The Noise Carrier (For High Frequencies)
Create Sound from formula: "Carrier_Noise", 1, 0, dur, orig_sr, "randomGauss(0, 0.1)"
carrier_noise_id = selected("Sound")

# --- 4. CREATE STEREO OUTPUT BUFFERS ---
# We need Left and Right buffers now
out_L_id = Create Sound from formula: "Out_L", 1, 0, dur, orig_sr, "0"
out_R_id = Create Sound from formula: "Out_R", 1, 0, dur, orig_sr, "0"

# --- 5. BARK SCALE SETUP ---
b_low = hertzToBark(lower_freq_limit)
b_high = hertzToBark(upper_freq_limit)
step = (b_high - b_low) / number_of_bands
filter_smoothing_hz = 50

appendInfoLine: "Processing ", number_of_bands, " bands with shift: ", frequency_shift_bands

# --- 6. THE BAND LOOP ---
for i from 1 to number_of_bands
    
    # --- A. SOURCE FREQUENCIES (The Voice) ---
    b_src_upper = b_low + i * step
    b_src_lower = b_src_upper - step
    f_src_low = barkToHertz(b_src_lower)
    f_src_high = barkToHertz(b_src_upper)
    
    # --- B. CARRIER FREQUENCIES (The Robot + Shift) ---
    # We apply the shift here. If we shift +2, Band 1 voice triggers Band 3 robot.
    j = i + frequency_shift_bands
    
    # Only process if the shifted band is valid (inside 1 to Total Bands)
    if j > 0 and j <= number_of_bands
        
        b_car_upper = b_low + j * step
        b_car_lower = b_car_upper - step
        f_car_low = barkToHertz(b_car_lower)
        f_car_high = barkToHertz(b_car_upper)

        # --- C. PROCESS SOURCE (Get Envelope) ---
        selectObject: input_id
        src_band = Filter (pass Hann band): f_src_low, f_src_high, filter_smoothing_hz
        
        # Envelope extraction (RMS)
        Formula: "self * self"
        Filter (pass Hann band): 0, envelope_smoothness_hz, 20
        Formula: "sqrt(abs(self))"
        env_id = selected("Sound")
        removeObject: src_band

        # --- D. PROCESS CARRIER (Select Type & Filter) ---
        # Logic: If frequency is high, use Noise Carrier. If low, use Main Carrier.
        if f_car_low > high_freq_noise_threshold
            selectObject: carrier_noise_id
        else
            selectObject: carrier_main_id
        endif
        
        carrier_band = Filter (pass Hann band): f_car_low, f_car_high, filter_smoothing_hz
        carrier_band_id = selected("Sound")

        # --- E. MODULATE ---
        selectObject: carrier_band_id
        env_id_str$ = string$(env_id)
        # Using your preferred Formula method
        Formula: "self * object(" + env_id_str$ + ", x)"
        
        # --- F. STEREO DISTRIBUTION ---
        # Odd bands -> Left, Even bands -> Right
        carrier_str$ = string$(carrier_band_id)
        
        if i mod 2 = 1
            selectObject: out_L_id
            Formula: "self + object(" + carrier_str$ + ", x)"
        else
            selectObject: out_R_id
            Formula: "self + object(" + carrier_str$ + ", x)"
        endif

        # Cleanup loop objects
        removeObject: env_id
        removeObject: carrier_band_id
        
        if i mod 5 = 0
            appendInfoLine: "Band ", i, " -> ", j
        endif
    endif
endfor

# --- 7. FINALIZE ---
# Combine L and R
selectObject: out_L_id
plusObject: out_R_id
final_id = Combine to stereo
Rename: orig_name$ + "_Vocoder_Stereo"
Scale peak: 0.99

# Cleanup global objects
removeObject: input_id
removeObject: carrier_main_id
removeObject: carrier_noise_id
removeObject: out_L_id
removeObject: out_R_id

appendInfoLine: "Done!"

if play_after
    selectObject: final_id
    Play
endif