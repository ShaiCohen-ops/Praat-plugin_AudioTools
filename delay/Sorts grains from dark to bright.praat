# ============================================================
# Praat AudioTools - Sorts grains from dark to bright.praat
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
; Sorts grains from dark to bright before concatenation:

form Adaptive Grain Cloud Synthesis
    comment Select a Sound object first
    positive grain_size_ms 150
    positive grain_size_variation 50
    choice grain_size_mode 1
        button Fixed
        button Random
    positive grain_overlap 0.3
    positive density_factor 1.5
    positive pitch_scatter 0.2
    positive time_scatter 0.1
    boolean reverse_grains 0
    choice window_type 2
        button Rectangular
        button Triangular
        button Parabolic
    boolean sort_grains 1
    choice sort_direction 1
        button Dark_to_bright
        button Bright_to_dark
    positive gap_between_grains 50
    boolean exaggerate_spectral_differences 1
    choice sorting_intensity 2
        button Subtle
        button Moderate
        button Strong
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

if grain_size_mode = 2 and grain_size_variation > grain_size_ms
    grain_size_variation = grain_size_ms * 0.8
    appendInfoLine: "Warning: Grain size variation reduced to ", fixed$(grain_size_variation, 0), "ms for safety"
endif

# Calculate grain parameters with reduced density for better sorting perception
base_grain_duration = grain_size_ms / 1000
hop_time = base_grain_duration * (1 - grain_overlap)
num_grains = round((duration / hop_time) * density_factor)

# Arrays to store grain IDs and brightness values
grainIDs# = zero#(num_grains)
grainBrightness# = zero#(num_grains)
grainOriginalBrightness# = zero#(num_grains)
grainDurations# = zero#(num_grains)
grainCount = 0

appendInfoLine: "=== Generating Grains ==="
appendInfoLine: "Grain size mode: ", if grain_size_mode = 1 then "Fixed" else "Random" fi
if grain_size_mode = 2
    appendInfoLine: "Grain size variation: ±", grain_size_variation, "ms"
endif

# Generate grains
for i from 1 to num_grains
    # Calculate grain duration based on mode
    if grain_size_mode = 1
        # Fixed grain size
        grain_duration = base_grain_duration
    else
        # Random grain size within variation range
        variation_seconds = (grain_size_variation / 1000) * randomUniform(-1, 1)
        grain_duration = base_grain_duration + variation_seconds
        # Ensure minimum and maximum bounds
        min_duration = base_grain_duration * 0.3
        max_duration = base_grain_duration * 2.0
        if grain_duration < min_duration
            grain_duration = min_duration
        elsif grain_duration > max_duration
            grain_duration = max_duration
        endif
    endif
    
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
        
        # Get spectral centroid for adaptive processing and brightness measurement
        selectObject: grain
        To Spectrum: "yes"
        spectrum = selected("Spectrum")
        centroid = Get centre of gravity: 2
        brightness = centroid
        original_brightness = brightness
        
        selectObject: spectrum
        Remove
        
        # Enhanced spectral exaggeration for better sorting perception
        if exaggerate_spectral_differences
            if sorting_intensity = 1
                # Subtle - small adjustments
                spectral_boost = 1.2
            elsif sorting_intensity = 2
                # Moderate - noticeable adjustments
                spectral_boost = 1.5
            else
                # Strong - dramatic adjustments
                spectral_boost = 2.0
            endif
            
            # Apply spectral emphasis based on brightness
            selectObject: grain
            To Spectrum: "yes"
            spectrum = selected("Spectrum")
            
            if brightness > 1000
                # Bright grains - emphasize high frequencies
                Formula: "if x > 1000 then self * spectral_boost else self fi"
                brightness = brightness * 1.3
            else
                # Dark grains - emphasize low frequencies
                Formula: "if x < 800 then self * spectral_boost else self fi"
                brightness = brightness * 0.7
            endif
            
            To Sound
            processed_grain = selected("Sound")
            selectObject: spectrum
            Remove
            selectObject: grain
            Remove
            grain = processed_grain
        endif
        
        # Adaptive grain modification based on spectral content
        selectObject: grain
        if original_brightness > 1500
            # High frequency content - brighter treatment
            grain_pitch_shift = randomGauss(0.5, pitch_scatter * 1.5)
        elsif original_brightness < 800
            # Low frequency content - darker treatment
            grain_pitch_shift = randomGauss(-0.3, pitch_scatter * 0.8)
        else
            # Medium frequency content
            grain_pitch_shift = randomGauss(0, pitch_scatter)
        endif
        
        # Apply pitch shifting to enhance spectral differences
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
        
        # Reverse grain randomly (but strategically for sorting effect)
        selectObject: grain
        if reverse_grains and randomUniform(0, 1) > 0.7
            Reverse
            # Adjust brightness perception for reversed grains
            brightness = brightness * 0.9
        endif
        
        # Scale grain amplitude based on spectral position and size
        selectObject: grain
        if brightness > 1500
            # Bright grains - slightly louder
            Scale: 0.35
        elsif brightness < 800
            # Dark grains - slightly quieter
            Scale: 0.25
        else
            Scale: 0.3
        endif
        
        # Additional amplitude scaling based on grain duration
        # Longer grains slightly quieter, shorter grains slightly louder for balance
        duration_ratio = grain_duration / base_grain_duration
        if duration_ratio < 0.7
            # Short grains - boost slightly
            Scale: 1.1
        elsif duration_ratio > 1.3
            # Long grains - reduce slightly
            Scale: 0.9
        endif
        
        # Store grain ID and brightness
        grainCount += 1
        grainIDs#[grainCount] = grain
        grainBrightness#[grainCount] = brightness
        grainOriginalBrightness#[grainCount] = original_brightness
        grainDurations#[grainCount] = grain_duration
        
        Rename: sound_name$ + "_grain_" + string$(grainCount) + "_" + fixed$(brightness, 0) + "Hz_" + fixed$(grain_duration*1000, 0) + "ms"
        
        appendInfoLine: "Grain ", grainCount, ": ", fixed$(grain_duration*1000, 0), "ms, original=", fixed$(original_brightness, 0), 
        ... "Hz, processed=", fixed$(brightness, 0), "Hz"
    endif
endfor

# Sort grains by brightness if requested
if sort_grains and grainCount > 1
    appendInfoLine: "=== Sorting Grains by Brightness ==="
    
    # Enhanced sorting with gap insertion
    for i from 1 to grainCount
        for j from i+1 to grainCount
            if (sort_direction = 1 and grainBrightness#[i] > grainBrightness#[j]) or 
            ... (sort_direction = 2 and grainBrightness#[i] < grainBrightness#[j])
                # Swap brightness values
                tempBrightness = grainBrightness#[i]
                grainBrightness#[i] = grainBrightness#[j]
                grainBrightness#[j] = tempBrightness
                
                tempOriginal = grainOriginalBrightness#[i]
                grainOriginalBrightness#[i] = grainOriginalBrightness#[j]
                grainOriginalBrightness#[j] = tempOriginal
                
                # Swap grain IDs
                tempGrain = grainIDs#[i]
                grainIDs#[i] = grainIDs#[j]
                grainIDs#[j] = tempGrain
                
                # Swap durations
                tempDuration = grainDurations#[i]
                grainDurations#[i] = grainDurations#[j]
                grainDurations#[j] = tempDuration
            endif
        endfor
    endfor
    
    # Display detailed sorting results
    appendInfoLine: "Final sort order:"
    for i from 1 to grainCount
        if grainIDs#[i] != 0
            selectObject: grainIDs#[i]
            grainName$ = selected$("Sound")
            appendInfoLine: i, ". ", grainName$, " (", fixed$(grainDurations#[i]*1000, 0), "ms, brightness=", fixed$(grainBrightness#[i], 0), 
            ... "Hz, original=", fixed$(grainOriginalBrightness#[i], 0), "Hz)"
        endif
    endfor
endif

# Create silence for gaps
gap_duration = gap_between_grains / 1000
if gap_duration > 0
    silence = Create Sound from formula: "silence", 1, 0, gap_duration, 44100, "0"
endif

# Concatenate grains in sorted order WITH GAPS
if grainCount > 0
    appendInfoLine: "=== Concatenating Grains with Gaps ==="
    
    # Create a temporary sequence with gaps
    selectObject: grainIDs#[1]
    temp_sound = Copy: "temp1"
    
    for i from 2 to grainCount
        if grainIDs#[i] != 0
            # Add gap if requested
            if gap_duration > 0
                selectObject: temp_sound
                plusObject: silence
                temp_with_gap = Concatenate
                selectObject: temp_with_gap
                plusObject: grainIDs#[i]
                new_temp = Concatenate
                selectObject: temp_sound
                Remove
                selectObject: temp_with_gap
                Remove
                temp_sound = new_temp
            else
                selectObject: temp_sound
                plusObject: grainIDs#[i]
                new_temp = Concatenate
                selectObject: temp_sound
                Remove
                temp_sound = new_temp
            endif
        endif
    endfor
    
    selectObject: temp_sound
    output = Copy: sound_name$ + "_granular_sorted"
    selectObject: temp_sound
    Remove
    
    # Clean up
    if gap_duration > 0
        selectObject: silence
        Remove
    endif
    
    # Clean up individual grains
    for i from 1 to grainCount
        if grainIDs#[i] != 0
            removeObject: grainIDs#[i]
        endif
    endfor
    
    # Final scaling with dynamic range preservation
    selectObject: output
    max_amplitude = Get maximum: 0, 0, "None"
    if max_amplitude > 0
        Scale peak: 0.9
        # Slightly lower to preserve dynamics
    endif
    
    # Calculate statistics
    total_duration = 0
    minBrightness = 1000000
    maxBrightness = 0
    minGrainDuration = 1000
    maxGrainDuration = 0
    for i from 1 to grainCount
        total_duration += grainDurations#[i]
        if grainBrightness#[i] < minBrightness
            minBrightness = grainBrightness#[i]
        endif
        if grainBrightness#[i] > maxBrightness
            maxBrightness = grainBrightness#[i]
        endif
        if grainDurations#[i] < minGrainDuration
            minGrainDuration = grainDurations#[i]
        endif
        if grainDurations#[i] > maxGrainDuration
            maxGrainDuration = grainDurations#[i]
        endif
    endfor
    
    # Get the actual output duration
    selectObject: output
    total_duration_output = Get total duration
    
    appendInfoLine: "=== Adaptive Grain Cloud Synthesis Complete ==="
    appendInfoLine: "Created and sorted ", grainCount, " grains from '", sound_name$, "'"
    appendInfoLine: "Grain size mode: ", if grain_size_mode = 1 then "Fixed" else "Random" fi
    if grain_size_mode = 2
        appendInfoLine: "Grain size range: ", fixed$(minGrainDuration*1000, 0), "-", fixed$(maxGrainDuration*1000, 0), "ms"
    endif
    appendInfoLine: "Sort direction: ", if sort_direction = 1 then "Dark to bright" else "Bright to dark" fi
    appendInfoLine: "Spectral exaggeration: ", if exaggerate_spectral_differences then "ON" else "OFF" fi
    appendInfoLine: "Gap between grains: ", gap_between_grains, "ms"
    appendInfoLine: "Brightness range: ", fixed$(minBrightness, 0), "-", fixed$(maxBrightness, 0), "Hz"
    appendInfoLine: "Total output duration: ", fixed$(total_duration_output, 2), "s"
    appendInfoLine: "Result: '", selected$("Sound"), "'"
else
    appendInfoLine: "No grains could be created with current parameters"
endif

# Clean window - select only the result
if grainCount > 0
    selectObject: output
endif