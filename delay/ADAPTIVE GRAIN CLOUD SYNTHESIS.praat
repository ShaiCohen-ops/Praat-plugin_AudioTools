# ============================================================
# Praat AudioTools - ADAPTIVE GRAIN CLOUD SYNTHESIS.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Delay or temporal structure script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

; SCRIPT 1: ADAPTIVE GRAIN CLOUD SYNTHESIS
; Creates clouds of grains with adaptive density based on spectral content

form Adaptive Grain Cloud Synthesis
    comment Select a Sound object first
    positive grain_size_ms 50
    positive grain_overlap 0.75
    positive density_factor 2.0
    positive pitch_scatter 0.2
    positive time_scatter 0.1
    boolean reverse_grains 0
    choice window_type 1
        button Rectangular
        button Triangular
        button Parabolic
endform

# Check if a sound object is selected
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

Convert to mono

# Get selected sound info
sound = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound
duration = Get total duration
sample_rate = Get sample rate
num_channels = Get number of channels

# Validate parameters
if duration < grain_size_ms/1000
    exitScript: "Sound is shorter than grain size"
endif

# Calculate grain parameters
grain_duration = grain_size_ms / 1000
hop_time = grain_duration * (1 - grain_overlap)
num_grains = round(duration / hop_time * density_factor)

# Arrays to store grain IDs
grainIDs# = zero#(num_grains)
grainCount = 0

# Generate grains
for i from 1 to num_grains
    # Get source time within valid range
    max_start = duration - grain_duration
    if max_start > 0
        source_time = randomUniform(0, max_start)
        
        # Convert window_type number to string
        if window_type = 1
            window_shape$ = "rectangular"
        elsif window_type = 2
            window_shape$ = "triangular"
        else
            window_shape$ = "parabolic"
        endif
        
        # Extract grain
        selectObject: sound
        Extract part: source_time, source_time + grain_duration, window_shape$, 1, 0
        grain = selected("Sound")
        
        # Get spectral centroid for adaptive processing
        selectObject: grain
        To Spectrum: "yes"
        spectrum = selected("Spectrum")
        centroid = Get centre of gravity: 2
        selectObject: spectrum
        Remove
        
        # Adaptive grain modification based on spectral content
        selectObject: grain
        if centroid > 2000
            # High frequency content - shorter, more scattered grains
            Scale: 0.8
            grain_pitch_shift = randomGauss(0, pitch_scatter * 2)
        else
            # Low frequency content - longer, more stable grains
            grain_pitch_shift = randomGauss(0, pitch_scatter * 0.5)
        endif
        
        # Apply pitch shifting if needed
        if abs(grain_pitch_shift) > 0.01
            selectObject: grain
            To Spectrum: "yes"
            spectrum_grain = selected("Spectrum")
            shift_factor = 2^(grain_pitch_shift/12)
            Formula: "if x > 0 then self * shift_factor else self fi"
            To Sound
            shifted_grain = selected("Sound")
            
            selectObject: spectrum_grain
            Remove
            selectObject: grain
            Remove
            grain = shifted_grain
        endif
        
        # Reverse grain randomly
        selectObject: grain
        if reverse_grains and randomUniform(0, 1) > 0.5
            Reverse
        endif
        
        # Scale grain amplitude
        selectObject: grain
        Scale: 0.3
        
        # Store grain ID
        grainCount += 1
        grainIDs#[grainCount] = grain
        Rename: sound_name$ + "_grain_" + string$(grainCount)
    endif
endfor

# Concatenate ONLY the grains if any were created
if grainCount > 0
    # Select only the first grain
    selectObject: grainIDs#[1]
    
    # Add the rest of the grains to selection
    for i from 2 to grainCount
        if grainIDs#[i] != 0
            plusObject: grainIDs#[i]
        endif
    endfor
    
    # Concatenate only the selected grains
    output = Concatenate
    Rename: sound_name$ + "_granular"
    
    # Clean up individual grains
    for i from 1 to grainCount
        if grainIDs#[i] != 0
            removeObject: grainIDs#[i]
        endif
    endfor
    
    # Final scaling
    selectObject: output
    max_amplitude = Get maximum: 0, 0, "None"
    if max_amplitude > 0
        Scale peak: 0.99
    endif
    
    appendInfoLine: "=== Adaptive Grain Cloud Synthesis Complete ==="
    appendInfoLine: "Created ", grainCount, " grains from '", sound_name$, "'"
    appendInfoLine: "Result: '", sound_name$, "_granular'"
else
    appendInfoLine: "No grains could be created with current parameters"
endif

# Clean window - select only the result
if grainCount > 0
    selectObject: output
endif
Play
