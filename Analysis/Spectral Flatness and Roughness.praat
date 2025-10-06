# ============================================================
# Praat AudioTools - Spectral Flatness and Roughness.praat
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

clearinfo

# Basic check
if not selected("Sound")
    appendInfoLine: "Please select a sound object."
    exit
endif

# Initialize variables
soundName$ = selected$("Sound")
minFreq = 80
maxFreq = 5000
lnSum = 0
linearSum = 0
validBins = 0
roughnessSum = 0
roughnessBins = 0

appendInfoLine: "Analyzing: ", soundName$

# Create spectrum
To Spectrum
spectrumName$ = "Spectrum " + selected$("Spectrum")
selectObject: spectrumName$

# Get spectrum info
nBins = Get number of bins
binWidth = Get bin width

# Main analysis loop
for bin from 1 to nBins
    freq = (bin - 1) * binWidth
    if freq >= minFreq and freq <= maxFreq
        # Flatness calculation
        amp = Get real value in bin: bin
        power = amp * amp
        power = max(power, 1e-12)
        lnSum = lnSum + ln(power)
        linearSum = linearSum + power
        
        # Roughness calculation (skip first and last bins)
        if bin > 1 and bin < nBins
            ampPrev = Get real value in bin: bin-1
            ampNext = Get real value in bin: bin+1
            roughnessSum = roughnessSum + abs(amp - (ampPrev + ampNext)/2)
            roughnessBins = roughnessBins + 1
        endif
        
        validBins = validBins + 1
    endif
endfor

# Calculate and display results
if validBins > 0
    # Spectral flatness
    flatness = exp(lnSum / validBins) / (linearSum / validBins)
    appendInfoLine: newline$, "=== Spectral Flatness ==="
    appendInfoLine: "Value: ", fixed$(flatness, 6), " (0=tonal, 1=noisy)"
    
    if flatness < 0.1
        appendInfoLine: "Interpretation: Very tonal (clear harmonics)"
    elsif flatness < 0.3
        appendInfoLine: "Interpretation: Moderate harmonics (typical singing)"
    else
        appendInfoLine: "Interpretation: Noise-dominated (breathy/harsh)"
    endif
    
    # Spectral roughness
    if roughnessBins > 0
        roughness = roughnessSum / roughnessBins
        appendInfoLine: newline$, "=== Spectral Roughness ==="
        appendInfoLine: "Value: ", fixed$(roughness, 6), " (higher = more rough)"
        
        if roughness < 0.01
            appendInfoLine: "Interpretation: Smooth spectrum (pure tone)"
        elsif roughness < 0.03
            appendInfoLine: "Interpretation: Mild roughness (natural voice)"
        elsif roughness < 0.06
            appendInfoLine: "Interpretation: Moderate roughness (vocal strain)"
        else
            appendInfoLine: "Interpretation: High roughness (harsh/dissonant)"
        endif
    endif
else
    appendInfoLine: "Error: No valid frequency bins in analysis range."
endif

# Clean up
Remove