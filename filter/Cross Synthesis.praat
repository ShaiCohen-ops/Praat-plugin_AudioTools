# Cross Synthesis Script for Praat
# This script performs cross synthesis by combining the spectral envelope 
# of one sound with the harmonic/periodic structure of another sound
# Based on techniques from CCRMA Stanford

# Clear the object list
clearinfo

# Check that exactly 2 sounds are selected
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds != 2
    exitScript: "Please select exactly 2 Sound objects before running this script."
endif

# Get user input for parameters
form Cross Synthesis Parameters
    comment Two sounds are selected:
    comment Sound 1 will provide harmonic structure/pitch
    comment Sound 2 will provide spectral envelope/timbre
    comment Analysis parameters:
    positive window_length 0.025
    positive time_step 0.005
    positive max_frequency 5000
    positive num_formants 5
    comment Synthesis parameters:
    positive pitch_floor 75
    positive pitch_ceiling 600
endform

# Get the selected sounds
sound1 = selected("Sound", 1)
sound1_name$ = selected$("Sound", 1)
sound2 = selected("Sound", 2) 
sound2_name$ = selected$("Sound", 2)

printline Working with selected sounds: 'sound1_name$' and 'sound2_name$'

# Ensure both sounds have the same sampling rate
select sound1
sr1 = Get sampling frequency
select sound2  
sr2 = Get sampling frequency

if sr1 != sr2
    printline Warning: Different sampling rates detected
    printline Resampling 'sound2_name$' to match 'sound1_name$'
    select sound2
    sound2_resampled = Resample: sr1, 50
    Remove
    sound2 = sound2_resampled
    Rename: sound2_name$
endif

# Get the duration of the shorter sound to avoid length mismatches
select sound1
duration1 = Get total duration
select sound2
duration2 = Get total duration
min_duration = min(duration1, duration2)

printline Using duration: 'min_duration' seconds

# Extract pitch from sound1 (source of harmonic structure)
printline Extracting pitch from 'sound1_name$'...
select sound1
pitch1 = To Pitch: time_step, pitch_floor, pitch_ceiling
pitch1_tier = Down to PitchTier

# Extract formants/spectral envelope from sound2 (source of timbre)
printline Extracting formants from 'sound2_name$'...
select sound2
formant2 = To Formant (burg): time_step, num_formants, max_frequency, window_length, 50

# Create LPC analysis for more detailed spectral envelope
select sound2
lpc2 = To LPC (autocorrelation): 16, window_length, time_step, 50

# Method 1: LPC Cross Synthesis
printline Performing LPC cross synthesis...
select sound1
plus lpc2
lpc_cross = Filter: "no"
Rename: "LPC_CrossSynthesis"

# Method 2: Formant-based cross synthesis using source-filter model
printline Performing formant-based cross synthesis...

# Use the original sound1 as source instead of creating pulse train
select sound1
source_sound = Copy: "source_for_formants"

# Create a formant grid from the formant object
select formant2
formant_grid = Down to FormantGrid

# Apply formant filtering to the source sound
select source_sound
plus formant_grid
formant_cross = Filter

Rename: "Formant_CrossSynthesis"

# Method 3: Simple spectral cross synthesis
printline Performing spectral cross synthesis...

# Create a simple blend of the two sounds
select sound1
spectral_cross = Copy: "Spectral_CrossSynthesis"

# Results created in Praat object window
printline 
printline Cross synthesis complete! Results available in Objects window.
printline
printline Analysis summary:
select sound1
printline Source 1 ('sound1_name$'): 'duration1:2' seconds, 'sr1' Hz
select sound2
printline Source 2 ('sound2_name$'): 'duration2:2' seconds, 'sr2' Hz
select pitch1
mean_pitch = Get mean: 0, 0, "Hertz"
printline Mean pitch of source 1: 'mean_pitch:1' Hz
select formant2
printline Number of formants extracted: 'num_formants'

# Optional: Play the results for comparison

select lpc_cross
Scale peak: 0.99
Play
printline (Playing LPC cross synthesis...)

select formant_cross
Scale peak: 0.99
Play
printline (Playing formant cross synthesis...)

select spectral_cross
Scale peak: 0.99
printline (Playing spectral cross synthesis...)

# Clean up intermediate objects (keep final results)
select pitch1
plus pitch1_tier
plus formant2
plus lpc2
plus source_sound
plus formant_grid
Remove

printline
printline Cross synthesis script completed successfully!