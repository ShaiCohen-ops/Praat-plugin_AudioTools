# ============================================================
# Praat AudioTools - Extraction.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# --- Form for Extraction Method and Processing Parameters ---
form Extraction and Processing Options
    comment 1. Choose Extraction Method
    
    optionmenu method 1
        option Percentage_Window
        option Random_Duration
    
    # --- 2. Percentage Window Parameters (Used if method = 1) ---
    positive start_percent 25
    positive end_percent 75
    
    # --- 3. Random Duration Parameters (Used if method = 2) ---
    real extraction_duration 2.0
    
    # --- 4. Processing and Fade Parameters ---
    comment Processing & Fade:
    
    # Attenuation Divisor
    positive attenuation_divisor 1.1
    
    # Fade Duration (Controls how long the linear fade lasts)
    real fade_time 0.1 
    
    # Scale Peak
    positive scale_peak 0.99
    
    # --- 5. General Option ---
    boolean play_extracted_sound 1
endform

# Get the name and ID of the currently selected Sound object
audio_file$ = selected$("Sound")
sound_id = selected("Sound")

# Error check: ensure a Sound object is actually selected
if sound_id = undefined
    exitScript: "Please select a Sound object in the Praat Objects window before running the script."
endif

selectObject: sound_id
total_duration = Get total duration

# --- Conditional Logic to Set Window Boundaries ---
if method = 1 ; Percentage Window
    
    if start_percent >= end_percent
        exitScript: "Error: Start percentage must be less than End percentage."
    endif
    if start_percent < 0 or end_percent > 100
        exitScript: "Error: Percentages must be between 0 and 100."
    endif
    
    window_start = total_duration * (start_percent / 100)
    window_end = total_duration * (end_percent / 100)
    segment_duration = window_end - window_start
    
    
elif method = 2 ; Random Duration
    
    if extraction_duration <= 0
        exitScript: "Error: Extraction duration must be a positive number."
    elif extraction_duration > total_duration
        exitScript: "Error: Requested duration ('extraction_duration') is longer than the whole sound."
    endif
    
    max_start_time = total_duration - extraction_duration
    window_start = randomUniform (0, max_start_time)
    window_end = window_start + extraction_duration 
    segment_duration = extraction_duration
    
endif

# --- Fade Validation (Ensures fade time is safe) ---
if fade_time <= 0
    exitScript: "Error: Fade time must be positive."
elif fade_time > segment_duration / 2
    exitScript: "Error: Fade time cannot be longer than half the segment duration."
endif


# --- 1. Extraction ---
selectObject: sound_id
windowed_sound = Extract part: window_start, window_end, "rectangular", 1, "no"
Rename: "extracted_and_faded"
selectObject: windowed_sound

# --- 2. Attenuate ---
# Attenuate the entire signal by the user-defined divisor
Formula: "self / 'attenuation_divisor'"


# --- 3. Apply Linear Fade-In (0 to 1 over the fade_time) ---
# Formula applies the function: min(1, time / fade_time)
Formula: "self * min(1, x / 'fade_time')"


# --- 4. Apply Linear Fade-Out (1 to 0 over the last fade_time) ---
# Formula applies the function: min(1, (segment_duration - time) / fade_time)
# We must use the sound's current duration (xmax) as the segment_duration is a variable
# The sound object knows its own duration as xmax.
Formula: "self * min(1, (xmax - x) / 'fade_time')"


# --- 5. Scale to Peak ---
Scale peak: scale_peak


# --- 6. Play if requested ---
if play_extracted_sound
    Play
endif