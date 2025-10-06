# ============================================================
# Praat AudioTools - SpectralDrivenVibrato.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Modulation or vibrato-based processing script
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

# Step 1: Check if a Sound is selected
if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

appendInfoLine: "=== STEP 1: Sound selected ==="
originalSound = selected("Sound")
originalName$ = selected$("Sound")
appendInfoLine: "Original sound: ", originalName$

# Step 2: Create a copy of the original sound
selectObject: originalSound
copySound = Copy: "copy_of_" + originalName$
copySoundName$ = selected$("Sound")
appendInfoLine: newline$, "=== STEP 2: Copy created ==="
appendInfoLine: "Copy name: ", copySoundName$

# Step 3: Calculate Spectral Flatness and Roughness from ORIGINAL sound
appendInfoLine: newline$, "=== STEP 3: Spectral Analysis ==="
selectObject: originalSound

# Initialize analysis variables
minFreq = 80
maxFreq = 5000
lnSum = 0
linearSum = 0
validBins = 0
roughnessSum = 0
roughnessBins = 0

# Create spectrum for analysis
To Spectrum
spectrum = selected("Spectrum")

# Get spectrum info
selectObject: spectrum
nBins = Get number of bins
binWidth = Get bin width

# Analysis loop
for bin from 1 to nBins
    freq = (bin - 1) * binWidth
    if freq >= minFreq and freq <= maxFreq
        amp = Get real value in bin: bin
        power = amp * amp
        power = max(power, 1e-12)
        lnSum = lnSum + ln(power)
        linearSum = linearSum + power
        
        if bin > 1 and bin < nBins
            ampPrev = Get real value in bin: bin-1
            ampNext = Get real value in bin: bin+1
            roughnessSum = roughnessSum + abs(amp - (ampPrev + ampNext)/2)
            roughnessBins = roughnessBins + 1
        endif
        
        validBins = validBins + 1
    endif
endfor

# Calculate spectral features
if validBins > 0 and roughnessBins > 0
    flatness = exp(lnSum / validBins) / (linearSum / validBins)
    roughness = roughnessSum / roughnessBins
    
    appendInfoLine: "Spectral Flatness: ", fixed$(flatness, 6)
    appendInfoLine: "Spectral Roughness: ", fixed$(roughness, 6)
    
    # Scale parameters for vibrato
    # Map flatness (0-1) to depth (0.05-0.20 semitones)
    depth = 0.05 + (flatness * 0.15)
    
    # Map roughness to rate (4-7 Hz)
    roughness_scaled = min(roughness * 150, 1)
    rate_hz = 4 + (roughness_scaled * 3)
    
    appendInfoLine: newline$, "Scaled Vibrato Parameters:"
    appendInfoLine: "Vibrato Depth: ", fixed$(depth, 3), " semitones"
    appendInfoLine: "Vibrato Rate: ", fixed$(rate_hz, 2), " Hz"
else
    exitScript: "Error: Could not calculate spectral features."
endif

# Clean up analysis objects
selectObject: spectrum
Remove

# Step 4: Apply smooth delay-line vibrato to the COPY
appendInfoLine: newline$, "=== STEP 4: Applying Smooth Vibrato to Copy ==="

# Select the copy by name instead of variable
selectObject: "Sound " + copySoundName$

# Vibrato parameters
delay_ms = 5.0
phase_rad = 0.0

# Get sampling frequency
sampling = Get sampling frequency
base = round(delay_ms * sampling / 1000)

# Apply the smooth vibrato formula
Formula... self [max(1, min(ncol, col + round('base' * (1 + 'depth' * sin(2*pi*'rate_hz'*x + 'phase_rad')))))]

# Rename the final result
Rename: "final_vibrato_" + originalName$
finalSoundName$ = selected$("Sound")

appendInfoLine: "Smooth vibrato applied successfully!"
appendInfoLine: "Final sound: ", finalSoundName$

# Select the original sound to show it's preserved
selectObject: originalSound
appendInfoLine: newline$, "=== COMPLETE ==="
appendInfoLine: "Original sound preserved: ", selected$("Sound")

# Select the final vibrato sound for the user
selectObject: "Sound " + finalSoundName$
appendInfoLine: "Vibrato-modified sound ready: ", selected$("Sound")
Play