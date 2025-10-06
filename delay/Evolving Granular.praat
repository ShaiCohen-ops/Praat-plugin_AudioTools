# ============================================================
# Praat AudioTools - Evolving Granular.praat
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

# ===================================================================
#  Evolving Granular Audio Manipulation
#  Fragments source audio into grains with evolving parameters
#  WARNING: This script uses intensive sample-by-sample processing
#  Lower density values for faster processing
# ===================================================================

form Evolving Granular Manipulation
    comment === GRAIN PARAMETERS ===
    real Initial_density 10.0
    real Final_density 25.0
    real Grain_duration_min 0.05
    real Grain_duration_max 0.15
    comment === EVOLUTION PARAMETERS ===
    choice Evolution_type: 1
        button Density_growth
        button Pitch_sweep
        button Statistical_shift
    real Pitch_shift_semitones 7.0
    comment === RANDOMIZATION ===
    real Position_randomness 0.3
    real Pitch_randomness 2.0
    real Amplitude_randomness 0.2
    comment NOTE: Higher density = slower processing
    comment Recommended: 5-15 grains/sec for testing
endform

# Get selected Sound
sound = selected("Sound")
sound_name$ = selected$("Sound")
duration = Get total duration
sampling_rate = Get sampling frequency
n_samples = Get number of samples
n_channels = Get number of channels

# Convert to mono if stereo
if n_channels > 1
    Convert to mono
    sound_mono = selected("Sound")
    sound = sound_mono
endif

writeInfoLine: "Creating Evolving Granular Manipulation..."
appendInfoLine: "  Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "  Evolution type: ", evolution_type$

# Calculate total number of grains
avg_density = (initial_density + final_density) / 2
total_grains = round(avg_density * duration)

appendInfoLine: "  Total grains: ", total_grains
appendInfoLine: ""
appendInfoLine: "  WARNING: This may take several minutes!"
appendInfoLine: "  Processing uses sample-by-sample operations."
appendInfoLine: "  Progress updates every 100 grains..."
appendInfoLine: ""

# Create output sound (silence)
Create Sound from formula: sound_name$ + "_granular", 1, 0, duration, sampling_rate, "0"
output_sound = selected("Sound")

# ===================================================================
# GRAIN GENERATION
# ===================================================================

if evolution_type = 1
    call DensityGrowth
elsif evolution_type = 2
    call PitchSweep
else
    call StatisticalShift
endif

# ===================================================================
# FINALIZE
# ===================================================================

selectObject: output_sound
Scale peak: 0.95
Rename: sound_name$ + "_granular_evolved"

# Clean up mono conversion if it was done
if n_channels > 1
    removeObject: sound_mono
endif

appendInfoLine: ""
appendInfoLine: "✓ Evolving Granular Manipulation complete!"
appendInfoLine: "  Processed grains: ", total_grains
appendInfoLine: "  Duration: ", fixed$(duration, 2), " s"

# ===================================================================
# PROCEDURES
# ===================================================================

procedure DensityGrowth
    for grain to total_grains
        normalized_time = (grain - 1) / total_grains
        current_density = initial_density + (final_density - initial_density) * normalized_time
        
        # Determine grain timing
        grain_center = normalized_time * duration + position_randomness * randomGauss(0, 1)
        grain_dur = grain_duration_min + (grain_duration_max - grain_duration_min) * randomUniform(0, 1)
        grain_start = grain_center - grain_dur / 2
        
        # Density-based acceptance probability
        time_probability = current_density / ((initial_density + final_density) / 2)
        
        if randomUniform(0, 1) < time_probability and grain_start >= 0 and grain_start + grain_dur <= duration
            # Extract grain from source
            source_pos = grain_start + position_randomness * randomGauss(0, 0.5)
            if source_pos < 0
                source_pos = 0
            elsif source_pos > duration - grain_dur
                source_pos = duration - grain_dur
            endif
            
            # Pitch randomization
            pitch_shift = pitch_randomness * randomGauss(0, 1)
            
            # Amplitude randomization
            amp_factor = 1 + amplitude_randomness * randomGauss(0, 1)
            if amp_factor < 0.3
                amp_factor = 0.3
            elsif amp_factor > 1.5
                amp_factor = 1.5
            endif
            
            call AddGrain 'source_pos' 'grain_start' 'grain_dur' 'pitch_shift' 'amp_factor'
        endif
        
        if grain mod 100 = 0
            appendInfoLine: "  Processing: ", grain, "/", total_grains, " (", fixed$(grain/total_grains*100, 1), "%)"
        endif
    endfor
endproc

procedure PitchSweep
    for grain to total_grains
        grain_center = randomUniform(0, duration)
        normalized_time = grain_center / duration
        
        grain_dur = grain_duration_min + (grain_duration_max - grain_duration_min) * randomUniform(0, 1)
        grain_start = grain_center - grain_dur / 2
        
        if grain_start >= 0 and grain_start + grain_dur <= duration
            # Progressive pitch shift
            current_pitch_shift = pitch_shift_semitones * normalized_time
            pitch_shift = current_pitch_shift + pitch_randomness * randomGauss(0, 1)
            
            # Source position
            source_pos = grain_start + position_randomness * randomGauss(0, 0.3)
            if source_pos < 0
                source_pos = 0
            elsif source_pos > duration - grain_dur
                source_pos = duration - grain_dur
            endif
            
            # Amplitude evolves inversely with pitch
            amp_factor = (1.2 - normalized_time * 0.4) + amplitude_randomness * randomGauss(0, 1)
            if amp_factor < 0.3
                amp_factor = 0.3
            elsif amp_factor > 1.5
                amp_factor = 1.5
            endif
            
            call AddGrain 'source_pos' 'grain_start' 'grain_dur' 'pitch_shift' 'amp_factor'
        endif
        
        if grain mod 100 = 0
            appendInfoLine: "  Processing: ", grain, "/", total_grains, " (", fixed$(grain/total_grains*100, 1), "%)"
        endif
    endfor
endproc

procedure StatisticalShift
    for grain to total_grains
        grain_center = randomUniform(0, duration)
        normalized_time = grain_center / duration
        
        # Three distinct temporal regions with different characteristics
        if normalized_time < 0.33
            # Region 1: Low, sparse, long grains
            grain_dur = 0.08 + 0.1 * randomUniform(0, 1)
            pitch_shift = -4 + pitch_randomness * randomGauss(0, 1)
            amp_factor = 0.9 + amplitude_randomness * randomGauss(0, 1)
            
        elsif normalized_time < 0.66
            # Region 2: Mid-range, dense, medium grains
            grain_dur = 0.04 + 0.06 * randomUniform(0, 1)
            pitch_shift = 2 + pitch_randomness * 1.5 * randomGauss(0, 1)
            amp_factor = 0.7 + amplitude_randomness * randomGauss(0, 1)
            
        else
            # Region 3: High, very dense, short grains
            grain_dur = 0.02 + 0.04 * randomUniform(0, 1)
            pitch_shift = 8 + pitch_randomness * 2 * randomGauss(0, 1)
            amp_factor = 0.5 + amplitude_randomness * randomGauss(0, 1)
        endif
        
        grain_start = grain_center - grain_dur / 2
        
        if grain_start >= 0 and grain_start + grain_dur <= duration
            source_pos = grain_start + position_randomness * randomGauss(0, 0.5)
            if source_pos < 0
                source_pos = 0
            elsif source_pos > duration - grain_dur
                source_pos = duration - grain_dur
            endif
            
            if amp_factor < 0.2
                amp_factor = 0.2
            elsif amp_factor > 1.3
                amp_factor = 1.3
            endif
            
            call AddGrain 'source_pos' 'grain_start' 'grain_dur' 'pitch_shift' 'amp_factor'
        endif
        
        if grain mod 100 = 0
            appendInfoLine: "  Processing: ", grain, "/", total_grains, " (", fixed$(grain/total_grains*100, 1), "%)"
        endif
    endfor
endproc

procedure AddGrain source_pos grain_start grain_dur pitch_shift amp_factor
    # Extract grain from source audio
    selectObject: sound
    Extract part: source_pos, source_pos + grain_dur, "rectangular", 1, "no"
    grain_extract = selected("Sound")
    
    # Apply pitch shift if needed and grain is long enough
    # Minimum grain duration for pitch analysis: ~3 periods at 80 Hz = 0.0375s
    min_grain_for_pitch = 0.04
    if abs(pitch_shift) > 0.1 and grain_dur >= min_grain_for_pitch
        pitch_factor = 2^(pitch_shift / 12)
        # Calculate appropriate pitch floor (must be >= 77.64 Hz)
        min_pitch_floor = 80
        max_pitch_ceiling = 600
        Lengthen (overlap-add): min_pitch_floor, max_pitch_ceiling, pitch_factor
        grain_shifted = selected("Sound")
        removeObject: grain_extract
        grain_extract = grain_shifted
        # Update duration after pitch shift
        selectObject: grain_extract
        grain_dur = Get total duration
    endif
    
    # Apply amplitude envelope (Hann window)
    selectObject: grain_extract
    Formula: "self * (1 - cos(2*pi*x/" + string$(grain_dur) + "))/2 * " + string$(amp_factor)
    
    # Mix grain into output sample by sample
    selectObject: grain_extract
    grain_n_samples = Get number of samples
    
    for i to grain_n_samples
        grain_time = (i - 1) / sampling_rate
        output_time = grain_start + grain_time
        
        if output_time < duration
            selectObject: grain_extract
            grain_value = Get value at sample number: 1, i
            
            selectObject: output_sound
            output_sample = round(output_time * sampling_rate) + 1
            
            if output_sample > 0 and output_sample <= n_samples
                current_value = Get value at sample number: 1, output_sample
                new_value = current_value + grain_value
                Set value at sample number: 1, output_sample, new_value
            endif
        endif
    endfor
    
    # Clean up
    removeObject: grain_extract
    selectObject: output_sound
endproc