# ============================================================
# Praat AudioTools - spectral roll-off frequency.praat
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

# Calculate the spectral roll-off frequency (85% energy) for a selected Sound object.

# Clear the Info window for clean output.
clearinfo

# Check if a Sound object is selected.
if selected("Sound") = 0
    writeInfoLine: "Error: No Sound object selected. Please select a Sound object and try again."
    exit
endif

# Get the sound name.
selectObject: selected("Sound")
soundName$ = selected$("Sound")
writeInfoLine: "Processing Sound: ", soundName$
# Note: Amplitude scaling is skipped for compatibility.
# Uncomment the next line if Formula is supported in your Praat version.
# Formula... self * 32768  # Scale to max amplitude for 16-bit audio.
appendInfoLine: "Note: Amplitude scaling skipped due to compatibility issues."

# Convert to Spectrum object.
To Spectrum... "yes"

# Check if Spectrum object was created.
if selected("Spectrum") = 0
    appendInfoLine: "Error: Failed to create Spectrum object."
    selectObject: selected("Sound")
    exit
endif

# Get the number of frequency bins in the Spectrum object.
selectObject: selected("Spectrum")
numberOfBins = Get number of bins
appendInfoLine: "Number of frequency bins: ", numberOfBins

# Compute the total energy by summing the squared amplitudes of all frequency bins.
totalEnergy = 0
for i from 1 to numberOfBins
    amplitude = Get real value in bin: i
    totalEnergy += amplitude ^ 2
endfor

# Check if total energy is zero or very small.
if totalEnergy < 1e-10
    appendInfoLine: "Error: Total energy is too small (", fixed$(totalEnergy, 6), "). The sound may be silent or invalid."
    removeObject: selected("Spectrum")
    selectObject: selected("Sound")
    exit
endif

appendInfoLine: "Total energy: ", fixed$(totalEnergy, 6)

# Find the roll-off frequency (frequency at which 85% of the total energy is accumulated).
cumulativeEnergy = 0
rolloffFreq = 0
targetEnergy = totalEnergy * 0.85
for i from 1 to numberOfBins
    amplitude = Get real value in bin: i
    cumulativeEnergy += amplitude ^ 2
    # Log progress every 1000 bins for debugging.
    if i mod 1000 = 0 or i = numberOfBins
        percent = (cumulativeEnergy / totalEnergy) * 100
        appendInfoLine: "Bin ", i, ": Cumulative energy = ", fixed$(cumulativeEnergy, 6), " (", fixed$(percent, 2), "%)"
    endif
    if cumulativeEnergy >= targetEnergy
        rolloffFreq = Get frequency from bin number: i
        appendInfoLine: "Roll-off found at bin ", i, ": ", fixed$(rolloffFreq, 2), " Hz (", fixed$((cumulativeEnergy / totalEnergy) * 100, 2), "%)"
        exit
    endif
endfor

# Output the result or a warning if roll-off wasn't found.
if rolloffFreq = 0
    appendInfoLine: "Warning: Roll-off frequency not found. Cumulative energy reached ", fixed$((cumulativeEnergy / totalEnergy) * 100, 2), "%."
else
    appendInfoLine: "Spectral roll-off (85%): ", fixed$(rolloffFreq, 2), " Hz"
endif

# Clean up by removing the Spectrum object.
removeObject: selected("Spectrum")
selectObject: selected("Sound")