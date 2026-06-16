# ============================================================
# Praat AudioTools - Vocoding.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - Fix wet/dry mix channel indexing (crashed at wet<100%)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Poly-carrier vocoder with multiple carrier types, Bark-scale
#   frequency bands, formant shifting, and high-frequency noise
#   injection for crisp consonants. Creates robot voice, whisper,
#   and pitch-tracked effects with stereo spreading.
#
# Changelog v0.3:
#   - Fixed wet/dry mix: object[id] -> object[id, row, col]. The old form
#     had no column/row index and errored (or misread) whenever Wet < 100%
#     (the default 100% hid it).
# Changelog v0.2:
#   - Added presets
#   - Added wet/dry mix control
#   - Added visualization
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

form Poly-Carrier Vocoder
    comment === Presets ===
    optionmenu Preset: 1
        option Custom
        option Classic Robot
        option Whisper Ghost
        option Deep Monster
        option Chipmunk
        option Pitch Follower
        option Metallic Drone
    comment === Vocoder Style ===
    optionmenu Carrier_type: 2
        option 1. Noise (Whisper)
        option 2. Robot Drone (Sawtooth)
        option 3. Pitch-Tracking (Pulse)
    positive Robot_pitch_hz 100
    comment === Expansions ===
    integer Frequency_shift_bands 0
    comment (Negative = Deeper/Bigger, Positive = Higher/Smaller)
    positive High_freq_noise_threshold 3500
    comment (Frequencies above this use Noise for crisp consonants)
    comment === Bands ===
    natural Number_of_bands 20
    positive Lower_freq_limit 50
    positive Upper_freq_limit 7500
    comment === Envelope ===
    positive Envelope_smoothness_hz 100
    comment === Mix ===
    real Wet_dry_percent 100
    comment (0 = dry, 100 = full vocoder)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_after 1
endform

# === APPLY PRESETS ===
presetName$ = "Custom"

if preset = 2
    # Classic Robot
    carrier_type = 2
    robot_pitch_hz = 100
    frequency_shift_bands = 0
    number_of_bands = 20
    presetName$ = "ClassicRobot"
elsif preset = 3
    # Whisper Ghost
    carrier_type = 1
    frequency_shift_bands = 0
    number_of_bands = 24
    envelope_smoothness_hz = 80
    presetName$ = "WhisperGhost"
elsif preset = 4
    # Deep Monster
    carrier_type = 2
    robot_pitch_hz = 60
    frequency_shift_bands = -3
    number_of_bands = 20
    presetName$ = "DeepMonster"
elsif preset = 5
    # Chipmunk
    carrier_type = 2
    robot_pitch_hz = 200
    frequency_shift_bands = 4
    number_of_bands = 20
    presetName$ = "Chipmunk"
elsif preset = 6
    # Pitch Follower
    carrier_type = 3
    frequency_shift_bands = 0
    number_of_bands = 24
    presetName$ = "PitchFollower"
elsif preset = 7
    # Metallic Drone
    carrier_type = 2
    robot_pitch_hz = 150
    frequency_shift_bands = 0
    number_of_bands = 32
    envelope_smoothness_hz = 50
    presetName$ = "MetallicDrone"
endif

# --- SETUP ---
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

writeInfoLine: "=== Poly-Carrier Vocoder v0.3 ==="
appendInfoLine: "Preset: ", presetName$

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
n_channels = Get number of channels
orig_dur = Get total duration

# Carrier type name
if carrier_type = 1
    carrierName$ = "Noise"
elsif carrier_type = 2
    carrierName$ = "Sawtooth"
else
    carrierName$ = "PitchTrack"
endif

appendInfoLine: "Carrier: ", carrierName$
appendInfoLine: "Bands: ", number_of_bands, " | Shift: ", frequency_shift_bands
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

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

# Keep dry copy for mix
selectObject: orig_id
if n_channels > 1
    dry_sound = Convert to mono
else
    dry_sound = Copy: "dry"
endif

# --- 3. GENERATE CARRIERS ---
appendInfoLine: "Generating carriers..."

# A. The Main Carrier (Robot/Pulse)
if carrier_type = 1
    Create Sound from formula: "Carrier_Main", 1, 0, dur, orig_sr, "randomGauss(0, 0.2)"
elsif carrier_type = 2
    s_pitch$ = string$(robot_pitch_hz)
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
    j = i + frequency_shift_bands
    
    # Only process if the shifted band is valid
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
        Formula: "self * object(" + env_id_str$ + ", x)"
        
        # --- F. STEREO DISTRIBUTION ---
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

# --- 7. COMBINE STEREO ---
selectObject: out_L_id
plusObject: out_R_id
final_id = Combine to stereo
Scale peak: 0.99

# --- 8. WET/DRY MIX ---
if dry_level > 0
    # Extend dry to stereo
    selectObject: dry_sound
    dry_stereo = Convert to stereo
    removeObject: dry_sound
    dry_sound = dry_stereo
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dry_sound)
    
    selectObject: final_id
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + ", row, col] * " + dry_str$
endif

selectObject: final_id
Rename: orig_name$ + "_vocoder_" + presetName$
Scale peak: 0.99

# === VISUALIZATION ===
if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0.0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Vocoder: " + presetName$ + " (" + carrierName$ + ")"
    
    # --- Original waveform ---
    Select outer viewport: 0, 4, 0.6, 1.6
    Select inner viewport: 0.4, 3.8, 0.7, 1.5
    selectObject: orig_id
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # --- Main carrier waveform (small segment) ---
    Select outer viewport: 4, 8, 0.6, 1.6
    Select inner viewport: 4.4, 7.8, 0.7, 1.5
    selectObject: carrier_main_id
    # Show just first 50ms
    show_dur = min(0.05, dur)
    Colour: "{0.6, 0.4, 0.7}"
    Draw: 0, show_dur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Carrier"
    
    # --- Result waveform ---
    Select outer viewport: 0, 4, 1.8, 2.8
    Select inner viewport: 0.4, 3.8, 1.9, 2.7
    selectObject: final_id
    Colour: "{0.3, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # --- Result spectrogram ---
    Select outer viewport: 4, 8, 1.8, 2.8
    Select inner viewport: 4.4, 7.8, 1.9, 2.7
    selectObject: final_id
    # Convert to mono for spectrogram
    final_mono = Convert to mono
    To Spectrogram: 0.005, upper_freq_limit, 0.002, 20, "Gaussian"
    final_spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Spectrogram"
    Text bottom: "yes", "Time (s)"
    removeObject: final_mono, final_spec
    
    # --- Band diagram ---
    Select outer viewport: 0, 8, 3.0, 4.2
    Select inner viewport: 0.4, 7.6, 3.1, 4.1
    
    Axes: 0, upper_freq_limit, 0, number_of_bands + 1
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, upper_freq_limit, 0, number_of_bands + 1
    
    # Draw bands
    for i from 1 to number_of_bands
        b_upper = b_low + i * step
        b_lower = b_upper - step
        f_low = barkToHertz(b_lower)
        f_high = barkToHertz(b_upper)
        
        # Source band color
        if i mod 2 = 1
            col$ = "{0.7, 0.8, 0.9}"
        else
            col$ = "{0.9, 0.8, 0.7}"
        endif
        
        Paint rectangle: col$, f_low, f_high, i - 0.4, i + 0.4
        
        # Show shifted target
        j = i + frequency_shift_bands
        if j > 0 and j <= number_of_bands and frequency_shift_bands <> 0
            b_car_upper = b_low + j * step
            b_car_lower = b_car_upper - step
            f_car_low = barkToHertz(b_car_lower)
            f_car_mid = (f_car_low + barkToHertz(b_car_upper)) / 2
            f_src_mid = (f_low + f_high) / 2
            
            Colour: "{0.5, 0.5, 0.5}"
            Arrow size: 0.8
            Draw arrow: f_src_mid, i, f_car_mid, i
        endif
    endfor
    
    # Noise threshold line
    if high_freq_noise_threshold < upper_freq_limit
        Colour: "{0.8, 0.5, 0.5}"
        Dotted line
        Draw line: high_freq_noise_threshold, 0, high_freq_noise_threshold, number_of_bands + 1
        Solid line
        Font size: 5
        Text: high_freq_noise_threshold, "left", number_of_bands + 0.5, "half", " Noise"
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Band"
    Text bottom: "yes", "Frequency (Hz)"
    
    # --- Parameters ---
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    
    shift_str$ = ""
    if frequency_shift_bands > 0
        shift_str$ = "+" + string$(frequency_shift_bands)
    else
        shift_str$ = string$(frequency_shift_bands)
    endif
    
    Text: 0.5, "centre", 0.5, "half", 
        ... "Carrier: " + carrierName$ +
        ... " | Pitch: " + string$(robot_pitch_hz) + " Hz" +
        ... " | Bands: " + string$(number_of_bands) +
        ... " | Shift: " + shift_str$ +
        ... " | Range: " + string$(lower_freq_limit) + "-" + string$(upper_freq_limit) + " Hz" +
        ... " | Wet: " + fixed$(wet_dry_percent, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# Cleanup global objects
removeObject: input_id
removeObject: carrier_main_id
removeObject: carrier_noise_id
removeObject: out_L_id
removeObject: out_R_id
removeObject: dry_sound

appendInfoLine: ""
appendInfoLine: "Done!"

if play_after
    selectObject: final_id
    Play
endif

selectObject: final_id