# ============================================================
# Praat AudioTools - Whisper Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Whisper Morph
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Whisper Morph
    optionmenu Preset: 1
        option Custom
        option Gentle Whisper
        option Breathy Whisper
        option Harsh Whisper
        option ASMR Style
    comment === Morph Type ===
    optionmenu Morph_type: 1
        option Dry to Wet (original -> whisper)
        option Wet to Dry (whisper -> original)
        option Dry-Wet-Dry (original -> whisper -> original)
        option Wet-Dry-Wet (whisper -> original -> whisper)
        option Full Whisper (no morph)
    comment === Whisper Parameters ===
    positive LPC_order_factor 1.0
    comment (1.0 = standard, higher = more formant detail)
    positive Breathiness 0.8
    comment (0 = more tonal, 1 = full noise)
    positive High_frequency_boost_(dB) 6.0
    comment === Morph Curve ===
    optionmenu Morph_curve: 1
        option Linear
        option Smooth (cosine)
        option Exponential
    comment === Output ===
    boolean Draw_morph_curve 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Gentle Whisper
    lPC_order_factor = 0.9
    breathiness = 0.7
    high_frequency_boost = 4.0
elsif preset = 3
    # Breathy Whisper
    lPC_order_factor = 1.0
    breathiness = 1.0
    high_frequency_boost = 8.0
elsif preset = 4
    # Harsh Whisper
    lPC_order_factor = 1.2
    breathiness = 0.9
    high_frequency_boost = 10.0
elsif preset = 5
    # ASMR Style
    lPC_order_factor = 1.1
    breathiness = 0.6
    high_frequency_boost = 3.0
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
originalIntensity = Get intensity (dB)

if originalIntensity = undefined
    exitScript: "Could not measure intensity - sound may be silent."
endif

if duration < 0.1
    exitScript: "Sound too short (min 0.1s)."
endif

writeInfoLine: "=== Whisper Morph ==="
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Intensity: ", fixed$(originalIntensity, 1), " dB"
appendInfoLine: ""

# ============================================================
# DRAW MORPH CURVE
# ============================================================
if draw_morph_curve
    Erase all
    Select outer viewport: 0, 6, 0, 3.5
    Axes: 0, duration, -0.1, 1.1
    
    Colour: "Black"
    Draw inner box
    
    # Grid
    Colour: "{0.8,0.8,0.8}"
    Draw line: 0, 0.5, duration, 0.5
    Draw line: duration/2, 0, duration/2, 1
    
    # Draw morph curve
    Colour: "Blue"
    Line width: 2
    
    step = duration / 200
    plotTime = 0
    
    # Calculate first point
    if morph_type = 5
        prevMix = 1
    elsif morph_type = 1
        prevMix = 0
    elsif morph_type = 2
        prevMix = 1
    elsif morph_type = 3
        prevMix = 0
    elsif morph_type = 4
        prevMix = 1
    endif
    prevTime = 0
    
    plotTime = step
    while plotTime <= duration
        # Calculate time position (0-1)
        tNorm = plotTime / duration
        
        # Calculate linear mix value based on morph type
        if morph_type = 5
            # Full whisper
            mixLin = 1
        elsif morph_type = 1
            # Dry to wet
            mixLin = tNorm
        elsif morph_type = 2
            # Wet to dry
            mixLin = 1 - tNorm
        elsif morph_type = 3
            # Dry-wet-dry
            if tNorm < 0.5
                mixLin = tNorm * 2
            else
                mixLin = (1 - tNorm) * 2
            endif
        elsif morph_type = 4
            # Wet-dry-wet
            if tNorm < 0.5
                mixLin = 1 - tNorm * 2
            else
                mixLin = (tNorm - 0.5) * 2
            endif
        endif
        
        # Apply curve shape
        if morph_curve = 1
            # Linear
            mixVal = mixLin
        elsif morph_curve = 2
            # Smooth (cosine)
            mixVal = 0.5 - 0.5 * cos(pi * mixLin)
        elsif morph_curve = 3
            # Exponential
            mixVal = mixLin * mixLin
        endif
        
        Draw line: prevTime, prevMix, plotTime, mixVal
        prevTime = plotTime
        prevMix = mixVal
        plotTime = plotTime + step
    endwhile
    
    # Labels
    Colour: "Black"
    Font size: 12
    Text: duration / 2, "Centre", 1.08, "Half", "Whisper Morph Curve"
    
    Font size: 10
    Text: duration / 2, "Centre", -0.07, "Half", "Time (s)"
    
    # Y-axis labels
    Font size: 9
    Text: -duration * 0.02, "Right", 0, "Half", "Dry"
    Text: -duration * 0.02, "Right", 1, "Half", "Wet"
    
    # Axis marks
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    
    Line width: 1
endif

# ============================================================
# CREATE WHISPERED VERSION
# ============================================================
appendInfoLine: "Creating whisper..."

# Convert to mono for LPC processing
selectObject: originalID
if numChannels > 1
    monoSource = Convert to mono
else
    monoSource = Copy: "mono"
endif

# Normalize for consistent LPC analysis
selectObject: monoSource
Scale peak: 0.95

# Calculate LPC order based on sample rate
# Rule of thumb: 2 + sampleRate/1000
lpcOrder = round((2 + sampleRate / 1000) * lPC_order_factor)
lpcOrder = max(10, min(50, lpcOrder))

appendInfoLine: "  LPC order: ", lpcOrder

# Create LPC model
selectObject: monoSource
lpcObj = To LPC (burg): lpcOrder, 0.025, 0.005, 50

# Create noise source
noiseSource = Create Sound from formula: "noise", 1, 0, duration, sampleRate, "randomGauss(0, 0.5)"

# Filter noise through LPC (vocal tract model)
selectObject: noiseSource
plusObject: lpcObj
whisperRaw = Filter: "yes"

# Apply high-frequency emphasis (whispers have more HF energy)
selectObject: whisperRaw
To Spectrum: "yes"
whisperSpec = selected("Spectrum")

# Boost high frequencies with smooth curve
boostDB$ = fixed$(high_frequency_boost, 2)
selectObject: whisperSpec
Formula: "self * 10^((" + boostDB$ + " * (x / 8000)) / 20)"

whisperEQ = To Sound

# Get envelope from original to shape whisper
selectObject: monoSource
intensityObj = To Intensity: 100, 0.01, "yes"

selectObject: intensityObj
Down to IntensityTier
envTier = selected("IntensityTier")

# Apply envelope to whisper
selectObject: whisperEQ
plusObject: envTier
whisperShaped = Multiply: "yes"

# Scale to match original intensity
selectObject: whisperShaped
Scale intensity: originalIntensity

# Final whisper sound
selectObject: whisperShaped
whisperFinal = Copy: "whisper"
Scale peak: 0.95

# Cleanup whisper intermediates
removeObject: lpcObj, noiseSource, whisperRaw, whisperSpec, whisperEQ
removeObject: intensityObj, envTier, whisperShaped

# ============================================================
# APPLY MORPH
# ============================================================
appendInfoLine: "Applying morph..."

# Rename sounds for formula reference
selectObject: monoSource
Rename: "drysig"
selectObject: whisperFinal
Rename: "wetsig"

# Create output
selectObject: monoSource
morphedSound = Copy: "morphed"

# Build morph formula
durStr$ = fixed$(duration, 8)

if morph_type = 5
    # Full whisper - just use wet signal
    selectObject: morphedSound
    Formula: "Sound_wetsig[]"
else
    # Build mix formula based on morph type and curve
    
    if morph_type = 1
        # Dry to wet: mix = t/dur
        mixFormula$ = "(x/" + durStr$ + ")"
    elsif morph_type = 2
        # Wet to dry: mix = 1 - t/dur
        mixFormula$ = "(1 - x/" + durStr$ + ")"
    elsif morph_type = 3
        # Dry-wet-dry
        halfDur$ = fixed$(duration/2, 8)
        mixFormula$ = "(if x < " + halfDur$ + " then (x/" + halfDur$ + ") else (1 - (x-" + halfDur$ + ")/" + halfDur$ + ") fi)"
    elsif morph_type = 4
        # Wet-dry-wet
        halfDur$ = fixed$(duration/2, 8)
        mixFormula$ = "(if x < " + halfDur$ + " then (1 - x/" + halfDur$ + ") else ((x-" + halfDur$ + ")/" + halfDur$ + ") fi)"
    endif
    
    # Apply curve transformation
    if morph_curve = 1
        # Linear - use as is
        finalMixFormula$ = mixFormula$
    elsif morph_curve = 2
        # Smooth (cosine): 0.5 - 0.5*cos(pi*mix)
        finalMixFormula$ = "(0.5 - 0.5 * cos(pi * " + mixFormula$ + "))"
    elsif morph_curve = 3
        # Exponential: mix^2
        finalMixFormula$ = "(" + mixFormula$ + ")^2"
    endif
    
    # Apply crossfade formula
    selectObject: morphedSound
    Formula: "Sound_drysig[] * (1 - " + finalMixFormula$ + ") + Sound_wetsig[] * " + finalMixFormula$
endif

# Rename and finalize
selectObject: morphedSound
Rename: originalName$ + "_whispermorph"

Scale peak: 0.95

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoSource, whisperFinal

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "Complete!"

morphTypeNames$[1] = "Dry to Wet"
morphTypeNames$[2] = "Wet to Dry"
morphTypeNames$[3] = "Dry-Wet-Dry"
morphTypeNames$[4] = "Wet-Dry-Wet"
morphTypeNames$[5] = "Full Whisper"

curveNames$[1] = "Linear"
curveNames$[2] = "Smooth"
curveNames$[3] = "Exponential"

appendInfoLine: "Morph: ", morphTypeNames$[morph_type]
if morph_type <> 5
    appendInfoLine: "Curve: ", curveNames$[morph_curve]
endif
appendInfoLine: "Breathiness: ", fixed$(breathiness * 100, 0), "%"
appendInfoLine: "HF Boost: +", fixed$(high_frequency_boost, 1), " dB"

if play_result
    selectObject: morphedSound
    Play
endif
