# ============================================================
# Praat AudioTools - Whisper Morph.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2025) - Crisp EQ + gating
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Whisper Morph - Transforms speech into whispered versions
#   using LPC-based vocal tract modeling with filtered noise.
#   Supports various morph trajectories and curve shapes.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Changelog v1.2:
#   - Whisper EQ replaced with an aggressive octave-band curve (inline):
#     cuts lows, boosts the turbulence band -> crisp, airy whisper instead
#     of muddy. high_frequency_boost shifts the upper bands.
#   - Gate folded into the envelope: gaps (>40 dB below peak) are zeroed,
#     removing the residual breath bed between phrases.
#   - Fully self-contained: no external script files required.
#
# Changelog v1.1:
#   - Breathiness now actually affects the sound: blends the noise-
#     excited whisper with the tonal original (was a no-op display value).
#   - Blended whisper re-matched to the dry intensity so the morph does
#     not lose level toward the wet end (uncorrelated noise+voice mix).
#   - Whisper trimmed back to the original length (To Spectrum "yes"
#     had zero-padded it to a power of two).
#
# Changelog v1.0:
#   - Upgraded visualization (4-panel layout)
#   - Added preset name display
#   - Added spectrogram comparison
#   - Improved info output
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
    boolean Draw_visualization 1
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
    preset$ = "Gentle Whisper"
elsif preset = 3
    # Breathy Whisper
    lPC_order_factor = 1.0
    breathiness = 1.0
    high_frequency_boost = 8.0
    preset$ = "Breathy Whisper"
elsif preset = 4
    # Harsh Whisper
    lPC_order_factor = 1.2
    breathiness = 0.9
    high_frequency_boost = 10.0
    preset$ = "Harsh Whisper"
elsif preset = 5
    # ASMR Style
    lPC_order_factor = 1.1
    breathiness = 0.6
    high_frequency_boost = 3.0
    preset$ = "ASMR Style"
else
    preset$ = "Custom"
endif

# Get morph type name
if morph_type = 1
    morphType$ = "Dry to Wet"
elsif morph_type = 2
    morphType$ = "Wet to Dry"
elsif morph_type = 3
    morphType$ = "Dry-Wet-Dry"
elsif morph_type = 4
    morphType$ = "Wet-Dry-Wet"
else
    morphType$ = "Full Whisper"
endif

# Get curve name
if morph_curve = 1
    curve$ = "Linear"
elsif morph_curve = 2
    curve$ = "Smooth"
else
    curve$ = "Exponential"
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
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Sound: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Intensity: ", fixed$(originalIntensity, 1), " dB"
appendInfoLine: ""

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

# Aggressive octave-band EQ (inline, no external file): cut the low rumble
# below ~350 Hz, boost the 0.5-2.8 kHz turbulence band, gentle top trim ->
# crisp, airy whisper instead of muddy. high_frequency_boost (dB) shifts
# the upper bands; its default of 6 gives the base curve (-24/+12/+24/-6).
hb = high_frequency_boost
gMid = 12 + (hb - 6)
gHigh = 24 + (hb - 6)
selectObject: whisperRaw
To Spectrum: "yes"
whisperSpec = selected("Spectrum")
Formula: "self * 10 ^ ( (if x < 354 then -24 else if x < 707 then gMid else if x < 2828 then gHigh else if x < 11314 then gMid else -6 fi fi fi fi) / 20 )"
whisperEQ_pad = To Sound
selectObject: whisperEQ_pad
Extract part: 0, duration, "rectangular", 1, "no"
whisperEQ = selected("Sound")
removeObject: whisperEQ_pad, whisperSpec

# Get envelope from original to shape whisper, with a gate folded in:
# frames more than 40 dB below the peak (the silent gaps) are zeroed, so
# the whisper goes properly silent between phrases instead of leaving a
# breath bed. The 40 here is the gate range -- the main tunable.
selectObject: monoSource
intensityObj = To Intensity: 100, 0.01, "yes"
selectObject: intensityObj
maxInt = Get maximum: 0, 0, "Parabolic"
Formula: "if self < maxInt - 40 then 0 else self fi"
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
removeObject: lpcObj, noiseSource, whisperRaw, whisperEQ
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

# Breathiness: blend the noise-excited whisper (wetsig) with the tonal
# original (drysig). LPC filtering is linear, so this signal-domain blend
# equals mixing a residual+noise excitation -- breathiness 1 = full-noise
# whisper, ->0 = fully tonal. (Previously breathiness had no audible effect.)
if breathiness < 1
    # Match the blended whisper's loudness to the dry signal so the morph
    # does not drop in level toward the wet end: mixing uncorrelated noise +
    # voice lowers RMS, so re-scale to the dry intensity afterwards.
    selectObject: monoSource
    dryIntensity = Get intensity (dB)
    selectObject: whisperFinal
    Formula: "self * breathiness + Sound_drysig[] * (1 - breathiness)"
    Scale intensity: dryIntensity
endif

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
finalName$ = selected$("Sound")

Scale peak: 0.95

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # === TITLE ===
    Select outer viewport: 1, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Whisper Morph## | " + preset$ + " | " + morphType$
    
    # === ORIGINAL WAVEFORM ===
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.8, 7.6, 0.7, 1.5
    
    selectObject: originalID
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 0.6, 1.6
    Text left: "yes", "Original"
    
    # === MORPHED OUTPUT WAVEFORM ===
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.8, 7.6, 1.8, 2.6
    
    selectObject: morphedSound
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.15, 8, 1.7, 2.7
    Text left: "yes", "Morphed"
    Text bottom: "yes", "Time (s)"
    
    # === MORPH CURVE (Left panel) ===
    Select outer viewport: 0, 4, 2.9, 4.5
    Select inner viewport: 0.8, 3.6, 3.0, 4.4
    
    Axes: 0, duration, -0.05, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1
    
    # Reference lines
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: 0, 0.5, duration, 0.5
    Draw line: duration/2, 0, duration/2, 1
    Solid line
    
    # Draw morph curve
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    
    step = duration / 200
    
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
            mixLin = 1
        elsif morph_type = 1
            mixLin = tNorm
        elsif morph_type = 2
            mixLin = 1 - tNorm
        elsif morph_type = 3
            if tNorm < 0.5
                mixLin = tNorm * 2
            else
                mixLin = (1 - tNorm) * 2
            endif
        elsif morph_type = 4
            if tNorm < 0.5
                mixLin = 1 - tNorm * 2
            else
                mixLin = (tNorm - 0.5) * 2
            endif
        endif
        
        # Apply curve shape
        if morph_curve = 1
            mixVal = mixLin
        elsif morph_curve = 2
            mixVal = 0.5 - 0.5 * cos(pi * mixLin)
        elsif morph_curve = 3
            mixVal = mixLin * mixLin
        endif
        
        Draw line: prevTime, prevMix, plotTime, mixVal
        prevTime = plotTime
        prevMix = mixVal
        plotTime = plotTime + step
    endwhile
    
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mix (Dry-Wet)"
    Text bottom: "yes", "Time (s)"
    
    # Label for curve panel
    Select outer viewport: 0, 4, 2.75, 2.9
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 2.0, "centre", 0.5, "half", "Morph Curve (" + curve$ + ")"
    
    # === SPECTRAL COMPARISON (Right panel) ===
    Select outer viewport: 4, 8, 2.9, 4.5
    Select inner viewport: 4.8, 7.6, 3.0, 4.4
    
    # Create temporary spectra for comparison
    selectObject: originalID
    if numChannels > 1
        tempOrigMono = Convert to mono
    else
        tempOrigMono = Copy: "tempOrig"
    endif
    
    selectObject: tempOrigMono
    tempOrigSpec = To Spectrum: "yes"
    
    selectObject: morphedSound
    tempMorphSpec = To Spectrum: "yes"
    
    # Get frequency range
    selectObject: tempOrigSpec
    maxFreq = Get highest frequency
    
    # Draw original spectrum (gray)
    Axes: 0, min(8000, maxFreq), 0, 80
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, min(8000, maxFreq), 0, 80
    
    selectObject: tempOrigSpec
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, min(8000, maxFreq), 0, 80, "no"
    
    # Draw morphed spectrum (blue)
    selectObject: tempMorphSpec
    Colour: "{0.3, 0.5, 0.7}"
    Draw: 0, min(8000, maxFreq), 0, 80, "no"
    
    # Cleanup temp spectra
    removeObject: tempOrigMono, tempOrigSpec, tempMorphSpec
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Level (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Label for spectrum panel
    Select outer viewport: 4, 8, 2.75, 2.9
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 6.0, "centre", 0.5, "half", "Spectrum (Gray=Original, Blue=Morphed)"
    
    # === INFO BOX ===
	Select outer viewport: 0, 8, 4.6, 5.3
	Axes: 0, 1, 0, 1
	Font size: 6
	Colour: "{0.4, 0.4, 0.4}"
	Text: 0.5, "centre", 0.7, "half", "LPC order: " + string$(lpcOrder) + " | Breathiness: " + fixed$(breathiness * 100, 0) + "% | HF Boost: +" + fixed$(high_frequency_boost, 1) + " dB"
	Text: 0.5, "centre", 0.3, "half", "Duration: " + fixed$(duration, 2) + "s | Sample rate: " + string$(sampleRate) + " Hz | Channels: " + string$(numChannels)
	Font size: 10
    	Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoSource, whisperFinal

# ============================================================
# OUTPUT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Morph: ", morphType$
if morph_type <> 5
    appendInfoLine: "Curve: ", curve$
endif
appendInfoLine: "Breathiness: ", fixed$(breathiness * 100, 0), "%"
appendInfoLine: "HF Boost: +", fixed$(high_frequency_boost, 1), " dB"
appendInfoLine: ""
appendInfoLine: "Output: ", finalName$

if play_result
    appendInfoLine: ""
    appendInfoLine: "Playing result..."
    selectObject: morphedSound
    Play
endif

selectObject: morphedSound