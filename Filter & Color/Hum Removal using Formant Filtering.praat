# ============================================================
# Praat AudioTools - Hum_Removal_using_Formant_Filtering.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed filter chain bug
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Removes electrical hum (50Hz or 60Hz) and harmonics
#   using cascaded band-stop filters.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
name$ = selected$("Sound")

form Hum Removal v0.2
    comment === Hum Frequency ===
    choice Base_frequency: 2
        option 50 Hz (Europe/Asia)
        option 60 Hz (Americas)
    comment === Filter Settings ===
    integer Max_harmonic 8
    positive Bandwidth 1.5
    comment (Width of notch in Hz, each side)
    comment === Output ===
    boolean Normalize_output 1
    real Peak_level 0.99
endform

# === Setup ===
selectObject: soundID
sampling_freq = Get sampling frequency
duration = Get total duration
nyquist = sampling_freq / 2

# Determine base frequency
if base_frequency = 1
    base_freq = 50
else
    base_freq = 60
endif

clearinfo
writeInfoLine: "=== Hum Removal v0.2 ==="
appendInfoLine: "Input: ", name$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Sample rate: ", sampling_freq, " Hz"
appendInfoLine: ""
appendInfoLine: "Base frequency: ", base_freq, " Hz"
appendInfoLine: "Harmonics: ", max_harmonic
appendInfoLine: "Bandwidth: ±", bandwidth, " Hz per notch"
appendInfoLine: ""

# === Create Working Copy ===
selectObject: soundID
processedID = Copy: name$ + "_hum_removed"

# === Apply Band-Stop Filters ===
appendInfoLine: "Applying notch filters:"

for harmonic from 1 to max_harmonic
    freq = base_freq * harmonic
    
    # Only filter if below Nyquist (with margin)
    if freq < nyquist * 0.9
        lowCut = freq - bandwidth
        highCut = freq + bandwidth
        
        # Ensure valid range
        if lowCut < 1
            lowCut = 1
        endif
        
        selectObject: processedID
        filteredID = Filter (stop Hann band): lowCut, highCut, bandwidth * 2
        
        # Replace processed with filtered result
        removeObject: processedID
        processedID = filteredID
        Rename: name$ + "_hum_removed"
        
        appendInfoLine: "  Notch ", harmonic, ": ", freq, " Hz (", fixed$(lowCut, 1), "-", fixed$(highCut, 1), " Hz)"
    else
        appendInfoLine: "  Skipped ", harmonic, ": ", freq, " Hz (above Nyquist)"
    endif
endfor

# === Normalize if requested ===
if normalize_output
    selectObject: processedID
    Scale peak: peak_level
    appendInfoLine: ""
    appendInfoLine: "Normalized to ", peak_level
endif

# === Output ===
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", name$, "_hum_removed"
appendInfoLine: ""
appendInfoLine: "Removed ", max_harmonic, " harmonics of ", base_freq, " Hz hum"

selectObject: soundID
Play