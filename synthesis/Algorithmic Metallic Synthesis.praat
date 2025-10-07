# ============================================================
# Praat AudioTools - Algorithmic Metallic Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Algorithmic Metallic Synthesis script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Algorithmic Metallic Synthesis
# Inspired by SuperCollider code

form Algorithmic Metallic Sound
    positive Base_frequency 200
    positive Number_of_voices 5
    positive Modulation_rate 0.5
    positive Resonance_decay 0.1
    positive Duration 3
    boolean Normalize 1
endform

# Create main sound
Create Sound from formula: "metallic", 1, 0, duration, 44100, "0"

# Generate multiple detuned voices
for i from 1 to number_of_voices
    # Calculate detuned frequency for this voice
    this_freq = (i + 2) * base_frequency
    detune = 1 + ((i - 1) * 0.02)
    
    # Create modulated carrier with higher amplitude
    Create Sound from formula: "carrier_'i'", 1, 0, duration, 44100, "0.5 * sin(2*pi*'this_freq'*x*'detune' + sin(2*pi*'modulation_rate'*x)*3)"
    
    # Create rhythmic trigger pattern
    Create Sound from formula: "trigger_'i'", 1, 0, duration, 44100, "if (x*('i'+2)) mod 1 < 0.2 then 1 else 0 fi"
    
    # Apply amplitude modulation based on trigger
    select Sound carrier_'i'
    Copy: "modulated_'i'"
    Formula: "self * Sound_trigger_'i'[] * 2"
    
    # Apply resonant bandpass filtering with wider bandwidth
    Filter (pass Hann band): this_freq, this_freq, 200
    
    # Add decay to create ringing
    Formula: "self * (0.5 + 0.5 * exp(-x/'resonance_decay'))"
    
    # Add to main mix with less aggressive scaling
    select Sound metallic
    Formula: "self + Sound_modulated_'i'_band[]"
    
    # Clean up all voice objects
    select Sound carrier_'i'
    plus Sound trigger_'i'
    plus Sound modulated_'i'
    plus Sound modulated_'i'_band
    Remove
endfor

# Apply final processing
select Sound metallic

# Boost overall amplitude
Formula: "self * 0.5"

# Add stereo width
Copy: "metallic_left"
Copy: "metallic_right"

# Create stereo differences
select Sound metallic_right
Formula: "sin(2*pi*0.5*x) * 0.2 + self * 0.8"

# Combine to stereo
select Sound metallic_left
plus Sound metallic_right
Combine to stereo
Rename: "'base_frequency'_metallic_alg"

# Normalize if requested
if normalize
    Scale peak: 0.9
endif
Play

# Clean up all temporary objects
select Sound metallic
plus Sound metallic_left
plus Sound metallic_right
Remove

# Select and play the final result
select Sound 'base_frequency'_metallic_alg