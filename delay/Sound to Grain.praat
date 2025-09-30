form Sound to Grain
    positive Number_of_grains 20
    positive Grain_length 0.3
    boolean Preview_result 0
    optionmenu Overlap_method: 1
        option Hanning
        option Rectangular
        option Triangular
    comment Extract grains from selected sound object
endform

# Check if a sound object is selected
if !selected("Sound")
    exitScript: "Please select a Sound object first."
endif

# Get selected sound info
soundID = selected("Sound")
soundName$ = selected$("Sound")
totalDuration = Get total duration

# Validate parameters
if grain_length > totalDuration
    exitScript: "Grain length cannot exceed sound duration (" + string$(totalDuration) + " s)."
endif

# Array to store grain IDs
grainIDs# = zero#(number_of_grains)

for grain from 1 to number_of_grains
    # Calculate random start position within valid range
    maxStart = totalDuration - grain_length
    if maxStart > 0
        startTime = randomUniform(0, maxStart)
        endTime = startTime + grain_length
        
        # Extract the grain
        selectObject: soundID
        if overlap_method = 1
            extractedID = Extract part: startTime, endTime, "Hanning", 1, "no"
        elif overlap_method = 2
            extractedID = Extract part: startTime, endTime, "Rectangular", 1, "no"
        else
            extractedID = Extract part: startTime, endTime, "Triangular", 1, "no"
        endif
        
        # Rename the extracted grain
        Rename: soundName$ + "_grain_" + string$(grain)
        grainIDs#[grain] = extractedID
        
        selectObject: extractedID
        if preview_result
            Play
            sleep(0.1)
        endif
    endif
endfor

# Select all grains and concatenate
if number_of_grains > 0
    selectObject: grainIDs#[1]
    for grain from 2 to number_of_grains
        if grainIDs#[grain] != 0
            plusObject: grainIDs#[grain]
        endif
    endfor
    
    concatenatedID = Concatenate
    concatenatedName$ = soundName$ + "_grains_concatenated"
    Rename: concatenatedName$
endif

# Clean up: remove individual grains
if number_of_grains > 0
    for grain from 1 to number_of_grains
        if grainIDs#[grain] != 0
            removeObject: grainIDs#[grain]
        endif
    endfor
endif

# Final selection: only original sound and concatenated result
selectObject: soundID
plusObject: concatenatedID

appendInfoLine: "=== Grain Extraction Complete ==="
appendInfoLine: "Extracted and concatenated ", number_of_grains, " grains"
appendInfoLine: "Final objects: '", soundName$, "' and '", concatenatedName$, "'"