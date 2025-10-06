# ============================================================
# Praat AudioTools - globally change the pitch and duration.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Change F0 and Duration
    comment This script changes pitch and duration of selected sounds
    sentence f0_expression self*1.0
    comment (e.g., self*1.5, self+50, self*0.8)
    positive duration_factor 1.5
    comment (1.0 = no change, 2.0 = twice as long, 0.5 = half length)
    comment Analysis parameters for F0:
    positive minimum_f0 75
    positive maximum_f0 300
    comment Output options:
    boolean play_after_synthesis 1
    boolean delete_manipulation_file 1
endform

# Find number of selected Sounds
numberOfSounds = numberOfSelected("Sound")

if numberOfSounds = 0
    exitScript: "Please select at least one Sound object."
endif

# Store names and IDs of selected Sounds
for ifile from 1 to numberOfSounds
    sound$ = selected$("Sound", ifile)
    soundID = selected("Sound", ifile)
    ids'ifile' = soundID
    names'ifile'$ = sound$
endfor

# Process each sound
for ifile from 1 to numberOfSounds
    soundID = ids'ifile'
    sound$ = names'ifile'$
    call fodurnchange
endfor

procedure fodurnchange
    # Get duration
    select soundID
    durn = Get duration
    
    # Create Pitch object
    select Sound 'sound$'
    To Pitch: 0.01, minimum_f0, maximum_f0
    plus Sound 'sound$'
    To Manipulation
    
    # Apply pitch transformation
    select Pitch 'sound$'
    Formula: f0_expression$
    
    # Convert to PitchTier and replace
    Down to PitchTier
    select Manipulation 'sound$'
    plus PitchTier 'sound$'
    Replace pitch tier
    
    # Clean up pitch objects
    select Pitch 'sound$'
    plus PitchTier 'sound$'
    Remove
    
    # Add duration change if needed
    if duration_factor <> 1.0
        Create DurationTier: sound$, 0, durn
        Add point: 0, duration_factor
        select Manipulation 'sound$'
        plus DurationTier 'sound$'
        Replace duration tier
        select DurationTier 'sound$'
        Remove
    endif
    
    # Resynthesize
    select Manipulation 'sound$'
    Get resynthesis (PSOLA)
    
    if play_after_synthesis
        Play
    endif
    
    # Rename result
    Rename: sound$ + ".f" + f0_expression$ + ".d" + string$(duration_factor)
    name$ = selected$("Sound")
    
    # Clean up manipulation if requested
    if delete_manipulation_file
        select Manipulation 'sound$'
        Remove
    endif
    
    select Sound 'name$'
endproc
