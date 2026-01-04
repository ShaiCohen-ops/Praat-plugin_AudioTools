# ============================================================
# Praat AudioTools - Tempo-Pitch Curves (Accelerando & Ritardando).praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Tempo Curves (Accelerando & Ritardando)
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Tempo Curves (Accelerando & Ritardando)
    comment Apply tempo variations to the selected sound
    comment 
    optionmenu Pattern_type 1
        option Accelerando (slow → fast)
        option Ritardando (fast → slow)
        option Slow-Fast-Slow
    comment 
    optionmenu Pitch_behavior 1
        option Pitch changes with tempo (PSOLA + pitch shift)
        option Keep pitch constant (PSOLA duration only)
    comment 
    real Strength 2.0
    comment    (1 = mild, 2 = medium, 3 = strong)
    comment 
    optionmenu Duration_mode 1
        option Keep original duration
        option Specify new duration
    real Target_duration 5.0
    comment 
    boolean Play_result_when_finished 1
endform

##############################################################################
# STEP 1: Check that exactly one Sound is selected
##############################################################################

if numberOfSelected("Sound") != 1
    exitScript: "Error: Please select exactly one Sound object."
endif

# Get the selected Sound and its properties
sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
originalDuration = Get total duration
samplingFrequency = Get sampling frequency
numberOfChannels = Get number of channels

# Get user choices from form
patternType = pattern_type
pitchBehavior = pitch_behavior
durationMode = duration_mode
targetDuration = target_duration

# Create pattern name string for logging
if patternType = 1
    patternName$ = "Accelerando (slow → fast)"
elsif patternType = 2
    patternName$ = "Ritardando (fast → slow)"
else
    patternName$ = "Slow-Fast-Slow"
endif

# Validate and clip strength
if strength < 0.5
    strength = 0.5
elsif strength > 5
    strength = 5
endif

# Validate target duration
if durationMode = 2 and targetDuration <= 0.01
    exitScript: "Error: Target duration must be greater than 0.01 seconds."
endif

##############################################################################
# STEP 2: Prepare working sound - convert to mono if needed
##############################################################################

# Convert to mono for processing if needed, but keep original
if numberOfChannels > 1
    selectObject: sound
    workingSound = Convert to mono
else
    selectObject: sound
    workingSound = Copy: soundName$ + "_working"
endif

selectObject: workingSound
originalDuration = Get total duration

##############################################################################
# STEP 3: Calculate tempo factor ranges
##############################################################################

# Base tempo factor ranges scale with strength
minTempoFactor = 1.0 - (0.25 * strength)
maxTempoFactor = 1.0 + (0.35 * strength)

# Ensure factors stay in safe range
if minTempoFactor < 0.4
    minTempoFactor = 0.4
endif
if maxTempoFactor > 3.0
    maxTempoFactor = 3.0
endif

##############################################################################
# STEP 4: Process according to pitch behavior mode
##############################################################################

if pitchBehavior = 1
    #=========================================================================
    # MODE A: PSOLA with pitch shift (simulates tape-speed)
    #=========================================================================
    
    writeInfoLine: "Processing with PSOLA + pitch shift (tape-speed effect)..."
    appendInfoLine: "Pattern: ", patternName$
    appendInfoLine: "Strength: ", strength
    appendInfoLine: ""
    
    selectObject: workingSound
    manipulation = To Manipulation: 0.01, 75, 600
    
    # Extract pitch tier
    selectObject: manipulation
    pitchTier = Extract pitch tier
    
    # Create duration tier from scratch
    durationTier = Create DurationTier: "tempo_curve", 0, originalDuration
    
    # Apply tempo curve to duration tier
    numPoints = 30
    
    for i from 0 to numPoints
        t = i * originalDuration / numPoints
        x = i / numPoints
        
        # Calculate tempo factor at this point
        if patternType = 1
            tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
        elsif patternType = 2
            tempoFactorPoint = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
        else
            centered = (x - 0.5) * 2
            tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
        endif
        
        # Duration factor is inverse of tempo
        durationFactorPoint = 1.0 / tempoFactorPoint
        
        # Ensure factors are reasonable
        if durationFactorPoint < 0.3
            durationFactorPoint = 0.3
        elsif durationFactorPoint > 3.0
            durationFactorPoint = 3.0
        endif
        
        # Add point to duration tier
        selectObject: durationTier
        Add point: t, durationFactorPoint
    endfor
    
    # Apply average pitch shift to simulate tape-speed
    # Multiply all pitch values by average tempo factor
    avgTempoFactor = (minTempoFactor + maxTempoFactor) / 2
    selectObject: pitchTier
    Formula: "self * " + string$(avgTempoFactor)
    
    # If keeping original duration, normalize duration factors
    if durationMode = 1
        sumFactors = 0
        for i from 0 to numPoints
            x = i / numPoints
            
            if patternType = 1
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
            elsif patternType = 2
                tempoFactorPoint = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
            else
                centered = (x - 0.5) * 2
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
            endif
            
            durationFactorPoint = 1.0 / tempoFactorPoint
            sumFactors = sumFactors + durationFactorPoint
        endfor
        
        meanFactor = sumFactors / (numPoints + 1)
        
        # Rebuild duration tier normalized
        selectObject: durationTier
        Remove points between: 0, originalDuration
        
        for i from 0 to numPoints
            t = i * originalDuration / numPoints
            x = i / numPoints
            
            if patternType = 1
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
            elsif patternType = 2
                tempoFactorPoint = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
            else
                centered = (x - 0.5) * 2
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
            endif
            
            durationFactorPoint = 1.0 / tempoFactorPoint
            normalizedFactor = durationFactorPoint / meanFactor
            
            Add point: t, normalizedFactor
        endfor
    endif
    
    # Replace both tiers in manipulation
    selectObject: manipulation
    plusObject: pitchTier
    Replace pitch tier
    
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    newSound = Get resynthesis (overlap-add)
    
    # Handle specified duration mode
    if durationMode = 2
        selectObject: newSound
        actualDuration = Get total duration
        
        if abs(actualDuration - targetDuration) > 0.01
            # Use Change gender but keep formants constant
            scaleFactor = targetDuration / actualDuration
            Change gender: 75, 600, 1.0, 0, scaleFactor, 1.0
            scaled = selected("Sound")
            selectObject: newSound
            Remove
            newSound = scaled
        endif
    endif
    
    # Rename
    selectObject: newSound
    if patternType = 1
        Rename: soundName$ + "_accel_pitched"
    elsif patternType = 2
        Rename: soundName$ + "_ritard_pitched"
    else
        Rename: soundName$ + "_slowFastSlow_pitched"
    endif
    
    # Clean up intermediate objects
    selectObject: manipulation
    Remove
    selectObject: pitchTier
    Remove
    selectObject: durationTier
    Remove
    
else
    #=========================================================================
    # MODE B: PSOLA - pitch constant, duration only
    #=========================================================================
    
    writeInfoLine: "Processing with PSOLA (pitch constant)..."
    appendInfoLine: "Pattern: ", patternName$
    appendInfoLine: "Strength: ", strength
    appendInfoLine: ""
    
    selectObject: workingSound
    manipulation = To Manipulation: 0.01, 75, 600
    
    # Create duration tier with tempo curve
    durationTier = Create DurationTier: "tempo_curve", 0, originalDuration
    
    # Add tempo curve points - NO pitch changes
    numPoints = 30
    
    for i from 0 to numPoints
        t = i * originalDuration / numPoints
        x = i / numPoints
        
        # Calculate tempo factor
        if patternType = 1
            tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
        elsif patternType = 2
            tempoFactorPoint = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
        else
            centered = (x - 0.5) * 2
            tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
        endif
        
        # Convert to duration factor
        durationFactorPoint = 1.0 / tempoFactorPoint
        
        if durationFactorPoint < 0.3
            durationFactorPoint = 0.3
        elsif durationFactorPoint > 3.0
            durationFactorPoint = 3.0
        endif
        
        selectObject: durationTier
        Add point: t, durationFactorPoint
    endfor
    
    # If keeping original duration, normalize
    if durationMode = 1
        sumFactors = 0
        for i from 0 to numPoints
            x = i / numPoints
            
            if patternType = 1
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
            elsif patternType = 2
                tempoFactorPoint = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
            else
                centered = (x - 0.5) * 2
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
            endif
            
            durationFactorPoint = 1.0 / tempoFactorPoint
            sumFactors = sumFactors + durationFactorPoint
        endfor
        
        meanFactor = sumFactors / (numPoints + 1)
        
        # Rebuild tier normalized
        selectObject: durationTier
        Remove points between: 0, originalDuration
        
        for i from 0 to numPoints
            t = i * originalDuration / numPoints
            x = i / numPoints
            
            if patternType = 1
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * x
            elsif patternType = 2
                tempoFactorPoint = maxTempoFactor - (maxTempoFactor - minTempoFactor) * x
            else
                centered = (x - 0.5) * 2
                tempoFactorPoint = minTempoFactor + (maxTempoFactor - minTempoFactor) * (1 - centered^2)
            endif
            
            durationFactorPoint = 1.0 / tempoFactorPoint
            normalizedFactor = durationFactorPoint / meanFactor
            
            Add point: t, normalizedFactor
        endfor
    endif
    
    # Replace duration tier
    selectObject: manipulation
    plusObject: durationTier
    Replace duration tier
    
    # Resynthesize
    selectObject: manipulation
    newSound = Get resynthesis (overlap-add)
    
    # Handle specified duration
    if durationMode = 2
        selectObject: newSound
        actualDuration = Get total duration
        
        if abs(actualDuration - targetDuration) > 0.01
            # Use Change gender but keep pitch constant
            scaleFactor = targetDuration / actualDuration
            Change gender: 75, 600, 1.0, 0, scaleFactor, 1.0
            scaled = selected("Sound")
            selectObject: newSound
            Remove
            newSound = scaled
        endif
    endif
    
    # Rename
    selectObject: newSound
    if patternType = 1
        Rename: soundName$ + "_accel_PSOLA"
    elsif patternType = 2
        Rename: soundName$ + "_ritard_PSOLA"
    else
        Rename: soundName$ + "_slowFastSlow_PSOLA"
    endif
    
    # Clean up intermediate objects
    selectObject: manipulation
    Remove
    selectObject: durationTier
    Remove
endif

##############################################################################
# STEP 5: Clean up working sound and finalize
##############################################################################

# Remove working sound copy
selectObject: workingSound
Remove

# Finalize output
selectObject: newSound
Scale peak: 0.99

# Play if requested
if play_result_when_finished
    Play
endif

# Report success
appendInfoLine: ""
appendInfoLine: "=============================="
appendInfoLine: "Tempo curve applied successfully!"
appendInfoLine: "=============================="
appendInfoLine: "Original duration: ", fixed$(originalDuration, 3), " s"
selectObject: newSound
finalActualDuration = Get total duration
appendInfoLine: "Result duration: ", fixed$(finalActualDuration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Output: ", selected$("Sound")
