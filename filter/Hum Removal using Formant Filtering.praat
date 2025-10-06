# ============================================================
# Praat AudioTools - Hum Removal using Formant Filtering.praat
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

# Hum Removal using Formant Filtering

form Hum Removal (Formant Method)
    choice Base_frequency: 2
        option 50 Hz
        option 60 Hz
    integer Max_harmonic: 8
    positive Bandwidth: 1.5
endform

sound = selected("Sound")
name$ = selected$("Sound")

base_freq = if base_frequency = 1 then 50 else 60 fi

# Create working copy
select sound
processed = Copy: "hum_free"

# Get sampling frequency once before the loop
select processed
sampling_freq = Get sampling frequency

# Apply series of band-stop filters for each harmonic
for harmonic to max_harmonic
    freq = base_freq * harmonic
    
    if freq < sampling_freq / 2 * 0.8
        # Use band-stop filtering
        select processed
        Filter (stop Hann band): freq - bandwidth, freq + bandwidth, 100
        
        # Remove the temporary band object that was created
        temp_band = selected("Sound")
        removeObject: temp_band
    endif
endfor

# Finalize - rename the processed sound
select processed
Rename: name$ + "_hum_removed"

echo Hum removal completed using formant filtering
echo Original sound: 'name$'
echo Processed sound: 'name$'_hum_removed
echo Both sounds remain in the Objects list