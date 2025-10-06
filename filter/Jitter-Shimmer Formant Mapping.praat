# ============================================================
# Praat AudioTools - Jitter-Shimmer Formant Mapping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Filtering or timbral modification script
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

appendInfoLine: "=== JITTER/SHIMMER TO FORMANT MAPPING ==="
appendInfoLine: "Select sounds to analyze and modify..."

# Check if sounds are selected
if not selected("Sound")
    exitScript: "Please select Sound objects first."
endif

number_of_selected_sounds = numberOfSelected("Sound")
appendInfoLine: "Number of sounds selected: ", number_of_selected_sounds

# Store selected sounds in array
for i from 1 to number_of_selected_sounds
    sound'i' = selected("Sound", i)
endfor

appendInfoLine: newline$, "=== ANALYZING JITTER AND SHIMMER ==="

# Analyze each sound and store jitter/shimmer values
for current_sound from 1 to number_of_selected_sounds
    select sound'current_sound'
    name$ = selected$("Sound")
    
    # Analyze jitter and shimmer in one go
    select sound'current_sound'
    pitch = To Pitch (raw cc): 0, 75, 600, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
    select sound'current_sound'
    plus pitch
    pointprocess = To PointProcess (cc)
    select sound'current_sound'
    plus pitch
    plus pointprocess
    voiceReport$ = Voice report: 0, 0, 75, 600, 1.3, 1.6, 0.03, 0.45
    
    jitter = (extractNumber(voiceReport$, "Jitter (local): ")) * 100
    shimmer = (extractNumber(voiceReport$, "Shimmer (local): ")) * 100
    
    appendInfoLine: "Sound: ", name$, " - Jitter: ", fixed$(jitter, 2), "%, Shimmer: ", fixed$(shimmer, 2), "%"
    
    # Store values for later use
    jitter'current_sound' = jitter
    shimmer'current_sound' = shimmer
    
    # Clean up analysis objects
    select pitch
    plus pointprocess
    Remove
endfor

appendInfoLine: newline$, "=== APPLYING FORMANT MODIFICATIONS ==="

# Apply formant modifications based on jitter/shimmer
for current_sound from 1 to number_of_selected_sounds
    select sound'current_sound'
    originalName$ = selected$("Sound")
    
    jitter = jitter'current_sound'
    shimmer = shimmer'current_sound'
    
    appendInfoLine: "Processing: ", originalName$, " (Jitter: ", fixed$(jitter, 2), "%, Shimmer: ", fixed$(shimmer, 2), "%)"
    
    # Map jitter to F1 modification and shimmer to F2 modification
    f1_shift_factor = 1.0 + (jitter * 0.1)
    f2_shift_factor = 1.0 + (shimmer * 0.08)
    
    appendInfoLine: "  F1 shift factor: ", fixed$(f1_shift_factor, 3)
    appendInfoLine: "  F2 shift factor: ", fixed$(f2_shift_factor, 3)
    
    # SIMPLE APPROACH: Use band-pass filtering to emphasize modified formant regions
    select sound'current_sound'
    
    # Create band-pass filters around modified F1 and F2 regions
    # F1 region (typically 300-900 Hz)
    f1_low = 300 * f1_shift_factor
    f1_high = 900 * f1_shift_factor
    
    # F2 region (typically 900-2500 Hz)  
    f2_low = 900 * f2_shift_factor
    f2_high = 2500 * f2_shift_factor
    
    # Apply band-pass filtering for F1 region
    select sound'current_sound'
    f1_filtered = Filter (pass Hann band): f1_low, f1_high, 100
    
    # Apply band-pass filtering for F2 region
    select sound'current_sound'
    f2_filtered = Filter (pass Hann band): f2_low, f2_high, 100
    
    # Combine the filtered sounds
    select f1_filtered
    plus f2_filtered
    combined = Combine to stereo
    
    # Convert to mono if needed
    select combined
    finalSound = Convert to mono
    Rename: "formant_mod_" + originalName$ + "_j" + fixed$(jitter, 1) + "_s" + fixed$(shimmer, 1)
    
    # Play original and modified
    appendInfoLine: "  Playing original then modified..."
    select finalSound
    Play
    
    # Clean up temporary objects
    select f1_filtered
    plus f2_filtered
    plus combined
    Remove
    
    appendInfoLine: "  Completed: ", originalName$
endfor
appendInfoLine: newline$, "=== MAPPING SUMMARY ==="
appendInfoLine: "Jitter → Formant 1 region: Higher jitter = higher F1 frequencies"
appendInfoLine: "Shimmer → Formant 2 region: Higher shimmer = higher F2 frequencies"
appendInfoLine: "Method: Band-pass filtering around modified formant regions"