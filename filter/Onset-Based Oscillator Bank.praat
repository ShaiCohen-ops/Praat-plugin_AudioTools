# ============================================================
# Praat AudioTools - Onset-Based Oscillator Bank.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Onset-Based Oscillator Bank
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Onset-Based Oscillator Bank
    comment === Onset Detection ===
    positive onset_threshold 1.5
    positive onset_silence_threshold 35.0
    positive onset_min_interval 0.1
    
    comment === Oscillator Settings ===
    integer num_partials 12
    positive partial_spread 0.5
    
    comment === Envelope Randomization ===
    positive attack_base 0.005
    positive attack_random 0.01
    positive decay_base 1.5
    positive decay_random 0.8
    positive amplitude_random 0.3
    
    comment === Waveshaper ===
    real brightness 0.7
    positive waveshape_amount 0.2
    
    comment === Mix ===
    real dry_wet 1.0
endform

# Get selected sound
sound = selected("Sound")
selectObject: sound
name$ = selected$("Sound")
duration = Get total duration
sampling_rate = Get sampling frequency
num_channels = Get number of channels

# Create intensity object for onset detection
selectObject: sound
intensity = To Intensity: 50, 0, "yes"

# Detect onsets based on intensity changes
selectObject: intensity
num_frames = Get number of frames
onset_times# = zero#(num_frames)
num_onsets = 0
last_onset_time = -1

# First, check the intensity range
min_intensity = Get minimum: 0, 0, "Parabolic"
max_intensity = Get maximum: 0, 0, "Parabolic"
mean_intensity = Get mean: 0, 0, "energy"

writeInfoLine: "=== Intensity Analysis ==="
appendInfoLine: "Min intensity: ", fixed$(min_intensity, 2), " dB"
appendInfoLine: "Max intensity: ", fixed$(max_intensity, 2), " dB"
appendInfoLine: "Mean intensity: ", fixed$(mean_intensity, 2), " dB"
appendInfoLine: "Number of frames: ", num_frames
appendInfoLine: ""
appendInfoLine: "Searching for onsets..."
appendInfoLine: "Threshold: ", onset_threshold, " dB change"
appendInfoLine: "Silence threshold: ", onset_silence_threshold, " dB"
appendInfoLine: ""

# Calculate intensity derivative for onset detection
max_diff = 0
for i from 3 to num_frames - 1
    time = Get time from frame number: i
    current_intensity = Get value in frame: i
    prev_intensity = Get value in frame: i-1
    prev2_intensity = Get value in frame: i-2
    
    if current_intensity != undefined and prev_intensity != undefined and prev2_intensity != undefined
        # Calculate smoothed derivative
        intensity_diff = (current_intensity - prev_intensity + current_intensity - prev2_intensity) / 2
        
        # Track maximum difference for debugging
        if intensity_diff > max_diff
            max_diff = intensity_diff
        endif
        
        # Detect onset: significant intensity increase above silence threshold
        if intensity_diff > onset_threshold and current_intensity > onset_silence_threshold
            if time - last_onset_time > onset_min_interval
                num_onsets += 1
                onset_times#[num_onsets] = time
                last_onset_time = time
                appendInfoLine: "  Found onset at ", fixed$(time, 3), "s (intensity: ", fixed$(current_intensity, 1), " dB, diff: ", fixed$(intensity_diff, 2), " dB)"
            endif
        endif
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Maximum intensity difference found: ", fixed$(max_diff, 2), " dB"

writeInfoLine: "Detected ", num_onsets, " onsets"

# Create output sound (start with silence)
selectObject: sound
output = Create Sound from formula: name$ + "_resonated", num_channels, 0, duration, sampling_rate, "0"

# Process each onset
successful_onsets = 0
for onset_idx from 1 to num_onsets
    onset_time = onset_times#[onset_idx]
    
    # Get pitch at onset - use a larger window for better detection
    selectObject: sound
    extract_start = max(0, onset_time - 0.02)
    extract_end = min(onset_time + 0.15, duration)
    
    if extract_end - extract_start > 0.03
        Extract part: extract_start, extract_end, "rectangular", 1, "no"
        part = selected("Sound")
        
        # Use autocorrelation method with wider range
        pitch_obj = To Pitch (ac): 0.0, 50, 15, "no", 0.01, 0.50, 0.01, 0.20, 0.10, 2500
        
        # Try to get pitch at onset time
        pitch = Get value at time: onset_time, "Hertz", "Linear"
        
        # If undefined, try getting mean pitch
        if pitch == undefined or pitch <= 0
            pitch = Get mean: 0, 0, "Hertz"
        endif
        
        # If still no pitch, try standard deviation weighted mean
        if pitch == undefined or pitch <= 0
            pitch = Get quantile: 0, 0, 0.5, "Hertz"
        endif
        
        # Last resort: get maximum pitch
        if pitch == undefined or pitch <= 0
            pitch = Get maximum: 0, 0, "Hertz", "Parabolic"
        endif
        
        removeObject: part, pitch_obj
        
        # Only proceed if pitch was detected - be very permissive
        if pitch != undefined and pitch >= 50 and pitch < 5000
            successful_onsets += 1
            if successful_onsets <= 5
                appendInfoLine: "Onset ", onset_idx, " at ", fixed$(onset_time, 3), "s - Pitch: ", fixed$(pitch, 1), " Hz"
            endif
        
        # Create oscillator bank for this onset
        for partial from 1 to num_partials
            # Calculate partial frequency with slight randomization
            freq = pitch * partial * (1 + randomUniform(-0.01, 0.01) * partial_spread)
            
            # Randomize envelope parameters
            attack = attack_base + randomUniform(0, attack_random)
            decay = decay_base + randomUniform(-decay_random, decay_random)
            decay = max(decay, 0.05)
            
            # Randomize amplitude (decreasing with partial number)
            base_amp = 0.15 / sqrt(partial)
            amp = base_amp * (1 + randomUniform(-amplitude_random, amplitude_random))
            
            # Calculate envelope duration
            env_duration = attack + decay
            end_time = min(onset_time + env_duration, duration)
            
            # Create sine wave for full duration, positioned at onset time
            selectObject: output
            Formula (part): onset_time, end_time, 1, num_channels,
                ... "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*(x-" + string$(onset_time) + "))" +
                ... " * if (x-" + string$(onset_time) + ") < " + string$(attack) + 
                ... " then (x-" + string$(onset_time) + ")/" + string$(attack) + 
                ... " else exp(-((x-" + string$(onset_time) + ")-" + string$(attack) + ")/" + string$(decay) + ") fi"
            
            # Apply waveshaping if enabled
            if waveshape_amount > 0
                waveshape_factor = 1 + waveshape_amount * brightness
                
                selectObject: output
                Formula (part): onset_time, end_time, 1, num_channels,
                    ... "self + " + string$(waveshape_amount * amp * waveshape_factor) + 
                    ... " * (sin(2*pi*" + string$(freq) + "*(x-" + string$(onset_time) + ")))^3" +
                    ... " * if (x-" + string$(onset_time) + ") < " + string$(attack) + 
                    ... " then (x-" + string$(onset_time) + ")/" + string$(attack) + 
                    ... " else exp(-((x-" + string$(onset_time) + ")-" + string$(attack) + ")/" + string$(decay) + ") fi"
            endif
        endfor
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Pitch detection successful for ", successful_onsets, " out of ", num_onsets, " onsets"

# Apply dry/wet mix
if dry_wet < 1.0
    selectObject: output
    Formula: "(1-" + string$(dry_wet) + ") * object[sound, x] + " + string$(dry_wet) + " * self"
endif

# Normalize output
selectObject: output
Scale peak: 0.99
Play

# Select final output
selectObject: output
removeObject: intensity

writeInfoLine: "Processing complete!"
appendInfoLine: "Created oscillator bank with ", num_partials, " partials per onset"
appendInfoLine: "Total onsets detected: ", num_onsets
appendInfoLine: "Successful pitch detections: ", successful_onsets
selectObject: output
max_amplitude = Get maximum: 0, 0, "None"
appendInfoLine: "Output maximum amplitude: ", fixed$(max_amplitude, 6)