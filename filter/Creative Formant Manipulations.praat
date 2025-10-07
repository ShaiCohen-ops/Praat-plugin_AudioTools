# ============================================================
# Praat AudioTools - Creative Formant Manipulations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creative Formant Manipulations script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Creative Formant Manipulations
# Various transformations using FormantPath and FormantGrid

form Creative Formant Manipulations
    comment Select manipulation type:
    optionmenu Manipulation_type 1
        option Formant rotation (vowel morphing)
        option Formant reversal (spectral flip)
        option Formant scrambling (randomize)
        option Formant scaling (gender shift)
        option Formant LFO modulation
        option Formant crossfade (temporal blend)
        option Formant freezing (hold vowels)
    comment FormantPath Parameters
    positive Time_step_(s) 0.005
    positive Max_number_of_formants 5
    positive Maximum_formant_(Hz) 5500
    positive Window_length_(s) 0.025
    positive Pre_emphasis_from_(Hz) 50
    positive Formant_smoothing_bandwidth 0.05
    positive Relative_formant_bandwidth 4
    comment Manipulation-specific parameters
    comment For Formant rotation:
    positive Rotation_amount_(semitones) 3
    comment For Formant scaling:
    positive Formant_shift_ratio 0.8
    positive Formant_stretch_ratio 1.2
    comment For Formant LFO:
    positive LFO_rate_Hz 2
    positive LFO_depth_semitones 6
    comment For Formant crossfade:
    positive Crossfade_cycles 3
    comment For Formant freezing:
    positive Freeze_interval_(s) 0.3
    positive Freeze_duration_(s) 0.15
    comment Cleanup
    boolean Keep_intermediate_objects 0
endform

# Get selected sound
sound = selected("Sound")
soundName$ = selected$("Sound")
duration = Get total duration
samplingFrequency = Get sampling frequency

writeInfoLine: "Creative Formant Manipulation"
appendInfoLine: "=============================="
appendInfoLine: "Processing: ", soundName$
appendInfoLine: "Type: ", manipulation_type$
appendInfoLine: ""

# Create FormantPath
selectObject: sound
To FormantPath (burg): time_step, max_number_of_formants, maximum_formant, window_length, pre_emphasis_from, formant_smoothing_bandwidth, relative_formant_bandwidth
formantPath = selected("FormantPath")

# Extract Formant
selectObject: formantPath
Extract Formant
formant = selected("Formant")

# Get formant info
selectObject: formant
numFrames = Get number of frames
startTime = Get time from frame number: 1
endTime = Get time from frame number: numFrames

# Store frame times
for frame to numFrames
    selectObject: formant
    frameTime[frame] = Get time from frame number: frame
endfor

# Down to FormantGrid
selectObject: formant
Down to FormantGrid
formantGrid = selected("FormantGrid")

appendInfoLine: "Formants extracted: ", numFrames, " frames"
appendInfoLine: ""

# ========================================
# MANIPULATION 1: Formant Rotation (Vowel Morphing)
# ========================================
if manipulation_type = 1
    appendInfoLine: "Applying formant rotation..."
    
    # Extract formant frequencies
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Rotate formants (shift all formants up/down in frequency)
    rotationFactor = 2^(rotation_amount / 12)
    
    selectObject: formantGrid
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            if freq[frame, f] <> undefined
                newFreq = freq[frame, f] * rotationFactor
                if newFreq > 0 and newFreq < maximum_formant
                    Remove formant points between: f, time - 0.0001, time + 0.0001
                    Add formant point: f, time, newFreq
                endif
            endif
        endfor
    endfor
    
    resultName$ = soundName$ + "_formant_rotated"
    appendInfoLine: "Formants rotated by ", rotation_amount, " semitones"

# ========================================
# MANIPULATION 2: Formant Reversal (Spectral Flip)
# ========================================
elsif manipulation_type = 2
    appendInfoLine: "Reversing formant order..."
    
    # Extract formant frequencies
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Reverse formant order (F1 becomes F5, F2 becomes F4, etc.)
    selectObject: formantGrid
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            reversedF = max_number_of_formants - f + 1
            if freq[frame, reversedF] <> undefined and freq[frame, reversedF] > 0
                Remove formant points between: f, time - 0.0001, time + 0.0001
                Add formant point: f, time, freq[frame, reversedF]
            endif
        endfor
    endfor
    
    resultName$ = soundName$ + "_formant_reversed"
    appendInfoLine: "Formant order reversed (F1↔F5, F2↔F4, etc.)"

# ========================================
# MANIPULATION 3: Formant Scrambling
# ========================================
elsif manipulation_type = 3
    appendInfoLine: "Scrambling formants..."
    
    # Extract formant frequencies
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Randomly shuffle formants at each frame
    selectObject: formantGrid
    for frame to numFrames
        time = frameTime[frame]
        
        # Create random permutation
        for f to max_number_of_formants
            perm[f] = f
        endfor
        
        # Fisher-Yates shuffle
        for i from max_number_of_formants to 2
            j = randomInteger(1, i)
            temp = perm[i]
            perm[i] = perm[j]
            perm[j] = temp
        endfor
        
        # Apply scrambled formants
        for f to max_number_of_formants
            scrambledF = perm[f]
            if freq[frame, scrambledF] <> undefined and freq[frame, scrambledF] > 0
                Remove formant points between: f, time - 0.0001, time + 0.0001
                Add formant point: f, time, freq[frame, scrambledF]
            endif
        endfor
    endfor
    
    resultName$ = soundName$ + "_formant_scrambled"
    appendInfoLine: "Formants randomly scrambled at each frame"

# ========================================
# MANIPULATION 4: Formant Scaling (Gender Shift)
# ========================================
elsif manipulation_type = 4
    appendInfoLine: "Scaling formants for gender shift..."
    
    # Extract formant frequencies and bandwidths
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
                bw[frame, f] = Get bandwidth at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
                bw[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Scale formants
    selectObject: formantGrid
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            if freq[frame, f] <> undefined and freq[frame, f] > 0
                newFreq = freq[frame, f] * formant_shift_ratio
                newBW = bw[frame, f] * formant_stretch_ratio
                if newFreq > 0 and newFreq < maximum_formant
                    Remove formant points between: f, time - 0.0001, time + 0.0001
                    Add formant point: f, time, newFreq
                    Remove bandwidth points between: f, time - 0.0001, time + 0.0001
                    Add bandwidth point: f, time, newBW
                endif
            endif
        endfor
    endfor
    
    resultName$ = soundName$ + "_gender_shifted"
    appendInfoLine: "Formants scaled: frequency × ", fixed$(formant_shift_ratio, 2), ", bandwidth × ", fixed$(formant_stretch_ratio, 2)

# ========================================
# MANIPULATION 5: Formant LFO Modulation
# ========================================
elsif manipulation_type = 5
    appendInfoLine: "Applying LFO modulation to formants..."
    
    # Extract formant frequencies
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Apply LFO modulation
    selectObject: formantGrid
    for frame to numFrames
        time = frameTime[frame]
        
        # Calculate LFO value (sine wave)
        lfoValue = sin(2 * pi * lFO_rate_Hz * time)
        modulation = 2^((lfoValue * lFO_depth_semitones) / 12)
        
        for f to max_number_of_formants
            if freq[frame, f] <> undefined and freq[frame, f] > 0
                newFreq = freq[frame, f] * modulation
                if newFreq > 0 and newFreq < maximum_formant
                    Remove formant points between: f, time - 0.0001, time + 0.0001
                    Add formant point: f, time, newFreq
                endif
            endif
        endfor
    endfor
    
    resultName$ = soundName$ + "_formant_LFO"
    appendInfoLine: "LFO applied: ", lFO_rate_Hz, " Hz, depth ", lFO_depth_semitones, " semitones"

# ========================================
# MANIPULATION 6: Formant Crossfade (Temporal Blend)
# ========================================
elsif manipulation_type = 6
    appendInfoLine: "Creating formant crossfade..."
    
    # Extract formant frequencies
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Crossfade between beginning and end formants
    selectObject: formantGrid
    for frame to numFrames
        time = frameTime[frame]
        
        # Calculate crossfade position (cycling)
        cyclePosition = (time / duration) * crossfade_cycles
        fadeAmount = (sin(cyclePosition * 2 * pi) + 1) / 2
        
        for f to max_number_of_formants
            startFreq = freq[1, f]
            endFreq = freq[numFrames, f]
            
            if startFreq <> undefined and endFreq <> undefined and startFreq > 0 and endFreq > 0
                blendedFreq = startFreq * (1 - fadeAmount) + endFreq * fadeAmount
                Remove formant points between: f, time - 0.0001, time + 0.0001
                Add formant point: f, time, blendedFreq
            endif
        endfor
    endfor
    
    resultName$ = soundName$ + "_formant_crossfade"
    appendInfoLine: "Crossfading between start and end formants, ", crossfade_cycles, " cycles"

# ========================================
# MANIPULATION 7: Formant Freezing
# ========================================
elsif manipulation_type = 7
    appendInfoLine: "Freezing formants at intervals..."
    
    # Extract formant frequencies
    for frame to numFrames
        time = frameTime[frame]
        for f to max_number_of_formants
            selectObject: formant
            numFormants = Get number of formants: frame
            if f <= numFormants
                freq[frame, f] = Get value at time: f, time, "hertz", "Linear"
            else
                freq[frame, f] = undefined
            endif
        endfor
    endfor
    
    # Freeze formants at regular intervals
    selectObject: formantGrid
    currentTime = 0
    while currentTime < duration
        # Find frame to freeze
        freezeFrame = round((currentTime / duration) * numFrames)
        if freezeFrame < 1
            freezeFrame = 1
        endif
        if freezeFrame > numFrames
            freezeFrame = numFrames
        endif
        
        # Apply frozen formants for freeze_duration
        freezeStart = currentTime
        freezeEnd = min(currentTime + freeze_duration, duration)
        
        for frame to numFrames
            time = frameTime[frame]
            if time >= freezeStart and time <= freezeEnd
                for f to max_number_of_formants
                    if freq[freezeFrame, f] <> undefined and freq[freezeFrame, f] > 0
                        Remove formant points between: f, time - 0.0001, time + 0.0001
                        Add formant point: f, time, freq[freezeFrame, f]
                    endif
                endfor
            endif
        endfor
        
        currentTime = currentTime + freeze_interval
    endwhile
    
    resultName$ = soundName$ + "_formant_frozen"
    appendInfoLine: "Formants frozen every ", freeze_interval, " s for ", freeze_duration, " s"
endif

# Apply FormantGrid to sound using filtering
selectObject: sound
plus formantGrid
Filter
result = selected("Sound")
Rename: resultName$

# Print summary
appendInfoLine: ""
appendInfoLine: "Processing complete!"
appendInfoLine: "Output: ", resultName$

# Cleanup
if keep_intermediate_objects = 0
    removeObject: formantPath
    removeObject: formant
    removeObject: formantGrid
    appendInfoLine: ""
    appendInfoLine: "Intermediate objects removed"
endif
Play

selectObject: result