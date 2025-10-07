# ============================================================
# Praat AudioTools - Wave Shaper Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Wave Shaper Distortion script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Enhanced Wave Shaper
    choice Shape: 1
        option Hyperbolic Tangent (soft)
        option Sine Fold (warm)
        option Arc Tangent (smooth)
        option Polynomial (aggressive)
        option Absolute Value (digital)
        option Square Law (fuzzy)
        option Chebyshev (harmonic)
        option Sigmoid (tube-like)
        option Exponential Fold (chaotic)
        option Bitcrush (lo-fi)
        option Wave Wrap (circular)
        option Diode Ladder (analog)
    positive Drive 2.0
    positive Mix_(%) 80
    boolean Normalize 1
    comment ──────────────────────
    optionmenu Mode: 1
        option Standard
        option Frequency Split
        option Asymmetric
        option Multi-Stage
        option Stereo Wide
    comment (see documentation for mode details)
endform

# Validation
if !selected("Sound")
    beginPause("No sound selected")
        comment("Please select a sound object first")
    endPause("OK", 1)
    exitScript()
endif

sound = selected("Sound")
original_name$ = selected$("Sound")
is_stereo = do("Get number of channels") = 2

# Create working copy
select sound
Copy: "processing"
proc_sound = selected("Sound")

# ====== MODE-SPECIFIC PROCESSING ======

if mode = 1
    # STANDARD MODE
    select proc_sound
    Formula: "self * drive"
    call applyWaveShaping
    
elsif mode = 2
    # FREQUENCY SPLIT MODE (800 Hz split)
    freq_split = 800
    
    select proc_sound
    Filter (pass Hann band): 0, freq_split, 100
    Rename: "low_band"
    low_band = selected("Sound")
    
    select proc_sound
    Filter (pass Hann band): freq_split, 0, 100
    Rename: "high_band"
    high_band = selected("Sound")
    
    # Process bands (low=normal, high=1.5x drive)
    select low_band
    Formula: "self * drive"
    call applyWaveShaping
    
    select high_band
    Formula: "self * drive * 1.5"
    call applyWaveShaping
    
    # Recombine
    select low_band
    plus high_band
    Combine to stereo
    Convert to mono
    Rename: "combined"
    
    select low_band
    plus high_band
    Remove
    
    select Sound combined
    proc_sound = selected("Sound")
    
elsif mode = 3
    # ASYMMETRIC MODE (different pos/neg)
    select proc_sound
    Formula: "self * drive"
    call applyWaveShaping
    Formula: "if self > 0 then self * 1.3 else self * 0.8 fi"
    
elsif mode = 4
    # MULTI-STAGE MODE (3 cascaded stages)
    select proc_sound
    stage_drive = drive ^ (1/3)
    for stage from 1 to 3
        Formula: "self * stage_drive"
        call applyWaveShaping
    endfor
    
elsif mode = 5
    # STEREO WIDE MODE (Mid/Side processing)
    if is_stereo
        select proc_sound
        Extract left channel
        Rename: "left_temp"
        left_temp = selected("Sound")
        
        select proc_sound
        Extract right channel
        Rename: "right_temp"
        right_temp = selected("Sound")
        
        # Create mid (mono sum)
        select left_temp
        Copy: "mid"
        mid_temp = selected("Sound")
        Formula: "(self + Sound_right_temp[]) / 2"
        Formula: "self * drive"
        call applyWaveShaping
        
        # Create side (difference)
        select right_temp
        Copy: "side"
        side_temp = selected("Sound")
        Formula: "(Sound_left_temp[] - self) / 2"
        Formula: "self * drive * 1.5"
        call applyWaveShaping
        
        # Recombine to L/R
        select mid_temp
        plus side_temp
        Combine to stereo
        stereo_combined = selected("Sound")
        
        # Decode M/S back to L/R
        Formula: "if col mod 2 = 1 then Sound_mid[row] + Sound_side[row] else Sound_mid[row] - Sound_side[row] fi"
        Rename: "stereo_processed"
        
        select left_temp
        plus right_temp
        plus mid_temp
        plus side_temp
        plus proc_sound
        Remove
        
        select Sound stereo_processed
        proc_sound = selected("Sound")
    else
        # Fallback to standard for mono
        select proc_sound
        Formula: "self * drive"
        call applyWaveShaping
    endif
endif

# ====== MIX & NORMALIZE ======

# Mix dry/wet
if mix < 100
    select sound
    Copy: "dry_signal"
    dry_sound = selected("Sound")
    
    select proc_sound
    wet_level = mix / 100
    dry_level = 1 - wet_level
    
    Formula: "(self * wet_level) + (Sound_dry_signal[] * dry_level)"
    
    select dry_sound
    Remove
endif

# Normalize
if normalize
    select proc_sound
    Scale peak: 0.95
endif

# Final naming
select proc_sound
call getShapeName
call getModeName
Rename: "'original_name$'_'shape_name$'_'mode_name$'"

# Play and select
Play
select Sound 'original_name$'_'shape_name$'_'mode_name$'

# ====== PROCEDURES ======

procedure applyWaveShaping
    if shape = 1
        Formula: "tanh(self * 1.5) / 1.5"
    elsif shape = 2
        Formula: "sin(self * 2.5) * 0.85"
    elsif shape = 3
        Formula: "2 * arctan(self * 1.8) / pi"
    elsif shape = 4
        Formula: "self - (self * self * self) * 0.33"
    elsif shape = 5
        Formula: "if self > 0 then self else -self fi"
    elsif shape = 6
        Formula: "self * abs(self) * 0.8"
    elsif shape = 7
        # Chebyshev polynomials (harmonic)
        Formula: "self * 0.7 + (2 * self * self - 1) * 0.2 + (4 * self^3 - 3 * self) * 0.1"
    elsif shape = 8
        # Sigmoid
        Formula: "(2 / (1 + exp(-self * 2))) - 1"
    elsif shape = 9
        # Exponential fold
        Formula: "(exp(self) - exp(-self)) / (exp(self) + exp(-self) + 0.1)"
    elsif shape = 10
        # Bitcrush
        levels = 16
        Formula: "floor(self * levels + 0.5) / levels"
    elsif shape = 11
        # Wave wrap
        Formula: "if abs(self) > 1 then -self / abs(self) * (2 - abs(self)) else self fi"
    elsif shape = 12
        # Diode ladder
        Formula: "if self > 0 then (1 - exp(-self * 2)) * 0.5 else (exp(self * 2) - 1) * 0.3 fi"
    endif
endproc

procedure getShapeName
    if shape = 1
        shape_name$ = "tanh"
    elsif shape = 2
        shape_name$ = "sinefold"
    elsif shape = 3
        shape_name$ = "arctan"
    elsif shape = 4
        shape_name$ = "poly"
    elsif shape = 5
        shape_name$ = "abs"
    elsif shape = 6
        shape_name$ = "square"
    elsif shape = 7
        shape_name$ = "cheby"
    elsif shape = 8
        shape_name$ = "sigmoid"
    elsif shape = 9
        shape_name$ = "expfold"
    elsif shape = 10
        shape_name$ = "bitcrush"
    elsif shape = 11
        shape_name$ = "wrap"
    elsif shape = 12
        shape_name$ = "diode"
    endif
endproc

procedure getModeName
    if mode = 1
        mode_name$ = "std"
    elsif mode = 2
        mode_name$ = "freqsplit"
    elsif mode = 3
        mode_name$ = "asym"
    elsif mode = 4
        mode_name$ = "multi"
    elsif mode = 5
        mode_name$ = "wide"
    endif
endproc