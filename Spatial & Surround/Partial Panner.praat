# ============================================================
# Praat AudioTools - Partial Panner.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Spray / Partial Panner (Mono → Stereo)
#   Pans different frequency bands across the stereo field.
#   Creates spatial width by distributing spectrum in stereo.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Efficient accumulation using Formula (not Combine to stereo loops)
#   - Modern selectObject: syntax throughout
#   - Fixed undefined preset$ variable
#   - Fixed division by zero for single band
#   - Added visualization of band distribution
#   - Added play_result toggle
#   - Proper formula string building
#   - Cleaner object management
# ============================================================

clearinfo

# ============================================================
# FORM
# ============================================================

form Partial Panner (Harmonic Spray)
    comment ─────────────────────────────────────────
    comment Preset
    optionmenu Preset: 3
        option Custom
        option Subtle Widening
        option Standard Spread
        option Extreme Spray
        option Reverse (High→L, Low→R)
        option Dense Shimmer
        option Coarse Texture
    comment ─────────────────────────────────────────
    positive Number_of_bands 8
    real Pan_width 0.8
    comment (0 = mono, 1 = full spread, negative = reverse)
    real Bandwidth_octaves 0.5
    comment (0.25 = narrow, 1.0 = wide)
    comment ─────────────────────────────────────────
    positive LF_protection_Hz 150
    positive Min_frequency_Hz 80
    positive Max_frequency_Hz 16000
    comment ─────────────────────────────────────────
    real Dry_wet_mix 1.0
    comment (0 = dry, 1 = wet)
    comment ─────────────────────────────────────────
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET SYSTEM
# ============================================================

if preset = 2
    # Subtle Widening
    number_of_bands = 6
    pan_width = 0.5
    bandwidth_octaves = 0.5
    presetName$ = "Subtle"
elsif preset = 3
    # Standard Spread
    number_of_bands = 8
    pan_width = 0.8
    bandwidth_octaves = 0.5
    presetName$ = "Standard"
elsif preset = 4
    # Extreme Spray
    number_of_bands = 16
    pan_width = 1.0
    bandwidth_octaves = 0.33
    presetName$ = "Extreme"
elsif preset = 5
    # Reverse
    number_of_bands = 10
    pan_width = -0.9
    bandwidth_octaves = 0.5
    presetName$ = "Reverse"
elsif preset = 6
    # Dense Shimmer
    number_of_bands = 20
    pan_width = 0.7
    bandwidth_octaves = 0.33
    presetName$ = "Dense"
elsif preset = 7
    # Coarse Texture
    number_of_bands = 4
    pan_width = 1.0
    bandwidth_octaves = 1.0
    presetName$ = "Coarse"
else
    presetName$ = "Custom"
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
nChan = Get number of channels

# Clamp parameters
if number_of_bands < 1
    number_of_bands = 1
endif
if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

# Adjust max frequency to Nyquist
maxFreq = min(max_frequency_Hz, sr / 2 * 0.95)
minFreq = min_frequency_Hz

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Partial Panner v0.2"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Bands: ", number_of_bands
appendInfoLine: "Pan width: ", fixed$(pan_width, 2)
appendInfoLine: "Bandwidth: ", fixed$(bandwidth_octaves, 2), " octaves"
appendInfoLine: "LF protection: ", lF_protection_Hz, " Hz"
appendInfoLine: "Frequency range: ", minFreq, " - ", fixed$(maxFreq, 0), " Hz"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# CONVERT TO MONO
# ============================================================

selectObject: original
if nChan > 1
    monoSound = Convert to mono
else
    monoSound = Copy: "mono_temp"
endif

# ============================================================
# CALCULATE BAND PARAMETERS
# ============================================================

appendInfoLine: "Calculating band parameters..."

# Store band info for visualization
for i from 1 to number_of_bands
    # Logarithmic band center frequency
    bandCenter[i] = minFreq * (maxFreq / minFreq) ^ ((i - 0.5) / number_of_bands)
    
    # Bandwidth in Hz (Q-based)
    bwMultiplier = 2 ^ bandwidth_octaves
    bandLow[i] = bandCenter[i] / sqrt(bwMultiplier)
    bandHigh[i] = bandCenter[i] * sqrt(bwMultiplier)
    
    # Normalized position (0 to 1)
    if number_of_bands > 1
        normPos = (i - 1) / (number_of_bands - 1)
    else
        normPos = 0.5
    endif
    
    # S-curve mapping for perceptually smoother distribution
    sCurveInput = (normPos * 2 - 1) * 2.5
    # tanh approximation: tanh(x) ≈ x / sqrt(1 + x^2) for small x, or use exp
    sCurveOutput = (exp(2 * sCurveInput) - 1) / (exp(2 * sCurveInput) + 1)
    
    # Frequency-dependent pan width (reduced at low frequencies)
    freqNorm = ln(bandCenter[i] / minFreq) / ln(maxFreq / minFreq)
    freqScale = 0.3 + 0.7 * (freqNorm ^ 0.7)
    
    # LF protection
    if bandCenter[i] < lF_protection_Hz
        lfScale = (bandCenter[i] / lF_protection_Hz) ^ 2
        freqScale = freqScale * (0.2 + 0.8 * lfScale)
    endif
    
    # Final pan position (-1 = left, +1 = right)
    effectiveWidth = pan_width * freqScale
    bandPan[i] = sCurveOutput * effectiveWidth
    
    # Constant power panning gains
    panAngle = (bandPan[i] + 1) / 2 * pi / 2
    bandGainL[i] = cos(panAngle)
    bandGainR[i] = sin(panAngle)
endfor

# ============================================================
# CREATE OUTPUT ACCUMULATORS
# ============================================================

Create Sound from formula: "left_accum", 1, 0, duration, sr, "0"
leftAccum = selected("Sound")

Create Sound from formula: "right_accum", 1, 0, duration, sr, "0"
rightAccum = selected("Sound")

# ============================================================
# PROCESS EACH BAND
# ============================================================

appendInfoLine: "Processing ", number_of_bands, " bands..."

for i from 1 to number_of_bands
    # Progress
    if i mod 4 = 0 or i = number_of_bands
        appendInfoLine: "  Band ", i, "/", number_of_bands, ": ", fixed$(bandCenter[i], 0), " Hz"
    endif
    
    # Smoothing for filter
    smoothHz = (bandHigh[i] - bandLow[i]) / 6
    
    # Filter the mono source
    selectObject: monoSound
    filtered = Filter (pass Hann band): bandLow[i], bandHigh[i], smoothHz
    filteredId$ = string$(filtered)
    
    # Add to left accumulator (efficient Formula method)
    gainLStr$ = fixed$(bandGainL[i], 10)
    selectObject: leftAccum
    Formula: "self + " + gainLStr$ + " * Object_" + filteredId$ + "[col]"
    
    # Add to right accumulator
    gainRStr$ = fixed$(bandGainR[i], 10)
    selectObject: rightAccum
    Formula: "self + " + gainRStr$ + " * Object_" + filteredId$ + "[col]"
    
    # Clean up filtered band
    removeObject: filtered
endfor

# ============================================================
# COMBINE TO STEREO (WET SIGNAL)
# ============================================================

appendInfoLine: ""
appendInfoLine: "Combining to stereo..."

selectObject: leftAccum
plusObject: rightAccum
wetStereo = Combine to stereo

# Apply pan law compensation (-3.5 dB)
selectObject: wetStereo
Formula: "self * 0.668"

# ============================================================
# CREATE DRY SIGNAL
# ============================================================

# Mono centered as stereo
selectObject: monoSound
dryLeft = Copy: "dry_L"
selectObject: monoSound
dryRight = Copy: "dry_R"

selectObject: dryLeft
plusObject: dryRight
dryStereo = Combine to stereo

# ============================================================
# MIX DRY/WET
# ============================================================

wetLevel = dry_wet_mix
dryLevel = 1 - dry_wet_mix

wetStr$ = fixed$(wetLevel, 10)
dryStr$ = fixed$(dryLevel, 10)
dryId$ = string$(dryStereo)

selectObject: wetStereo
result = Copy: originalName$ + "_spray_" + presetName$

selectObject: result
Formula: "self * " + wetStr$ + " + Object_" + dryId$ + "[col, row] * " + dryStr$

# Normalize
selectObject: result
Scale peak: 0.99

# ============================================================
# CLEANUP
# ============================================================

removeObject: leftAccum, rightAccum, wetStereo, dryStereo, dryLeft, dryRight, monoSound

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Partial Panner: " + originalName$ + " (" + presetName$ + ")"
    
    # === Frequency Band Distribution ===
    Select outer viewport: 0, 8, 0.6, 3.0
    Select inner viewport: 0.6, 7.6, 0.8, 2.8
    
    # Log frequency axis
    minLogF = ln(minFreq)
    maxLogF = ln(maxFreq)
    
    Axes: minLogF, maxLogF, -1.2, 1.2
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", minLogF, maxLogF, -1.2, 1.2
    
    # Reference lines
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    Draw line: minLogF, 0, maxLogF, 0
    Draw line: minLogF, -1, maxLogF, -1
    Draw line: minLogF, 1, maxLogF, 1
    
    # LF protection zone
    if lF_protection_Hz > minFreq
        lfLogF = ln(lF_protection_Hz)
        Paint rectangle: "{0.95, 0.9, 0.9}", minLogF, lfLogF, -1.2, 1.2
    endif
    
    # Labels
    Font size: 7
    Colour: "{0.5, 0.5, 0.5}"
    Text: minLogF - 0.1, "right", -1, "half", "L"
    Text: minLogF - 0.1, "right", 0, "half", "C"
    Text: minLogF - 0.1, "right", 1, "half", "R"
    
    # Draw bands
    for i from 1 to number_of_bands
        logCenter = ln(bandCenter[i])
        logLow = ln(bandLow[i])
        logHigh = ln(bandHigh[i])
        pan = bandPan[i]
        
        # Color based on pan position
        if pan < 0
            r = 0.3
            b = 0.5 - pan * 0.4
        else
            r = 0.5 + pan * 0.4
            b = 0.3
        endif
        col$ = "{" + fixed$(r, 2) + ", 0.5, " + fixed$(b, 2) + "}"
        
        # Draw band rectangle
        Colour: col$
        Paint rectangle: col$, logLow, logHigh, -0.1, pan
        
        # Draw center line
        Line width: 2
        Draw line: logCenter, 0, logCenter, pan
        Paint circle (mm): col$, logCenter, pan, 1.5
    endfor
    
    # Frequency markers
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
        
    f = 100
    while f <= 10000
        if f >= minFreq and f <= maxFreq
            if f = 100 or f = 200 or f = 500 or f = 1000 or f = 2000 or f = 5000 or f = 10000
                logF = ln(f)
                Colour: "{0.8, 0.8, 0.8}"
                Line width: 1
                Draw line: logF, -1.15, logF, -1.05
                Colour: "{0.4, 0.4, 0.4}"
                if f < 1000
                    Text: logF, "centre", -1.25, "half", string$(f)
                else
                    Text: logF, "centre", -1.25, "half", string$(f/1000) + "k"
                endif
            endif
        endif
        f = f + 100
    endwhile
   
    
    # Border
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Frequency (Hz, log scale)"
    Text left: "yes", "Pan Position"
    
    # === Gain Distribution ===
    Select outer viewport: 0, 8, 3.1, 5.0
    Select inner viewport: 0.6, 7.6, 3.3, 4.8
    
    Axes: minLogF, maxLogF, -0.1, 1.1
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", minLogF, maxLogF, -0.1, 1.1
    
    # Reference
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: minLogF, 0, maxLogF, 0
    Draw line: minLogF, 1, maxLogF, 1
    
    # Draw L/R gains for each band
    for i from 1 to number_of_bands
        logCenter = ln(bandCenter[i])
        
        # Left gain (blue)
        Colour: "{0.3, 0.5, 0.8}"
        Paint circle (mm): "{0.3, 0.5, 0.8}", logCenter, bandGainL[i], 1.5
        
        # Right gain (red)
        Colour: "{0.8, 0.5, 0.3}"
        Paint circle (mm): "{0.8, 0.5, 0.3}", logCenter, bandGainR[i], 1.5
    endfor
    
    # Connect points
    Colour: "{0.3, 0.5, 0.8}"
    Line width: 1
    for i from 2 to number_of_bands
        Draw line: ln(bandCenter[i-1]), bandGainL[i-1], ln(bandCenter[i]), bandGainL[i]
    endfor
    
    Colour: "{0.8, 0.5, 0.3}"
    for i from 2 to number_of_bands
        Draw line: ln(bandCenter[i-1]), bandGainR[i-1], ln(bandCenter[i]), bandGainR[i]
    endfor
    
    # Border
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 8
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Gain"
    
    # Legend
    Font size: 7
    Colour: "{0.3, 0.5, 0.8}"
    Text: maxLogF * 0.95, "right", 1.05, "half", "Left"
    Colour: "{0.8, 0.5, 0.3}"
    Text: maxLogF * 0.85, "right", 1.05, "half", "Right"
    
    # === Info bar ===
    Select outer viewport: 0, 8, 5.1, 5.5
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", presetName$ + " | " + string$(number_of_bands) + " bands | Width: " + fixed$(pan_width, 2) + " | BW: " + fixed$(bandwidth_octaves, 2) + " oct | LF: " + string$(lF_protection_Hz) + "Hz | Mix: " + fixed$(dry_wet_mix * 100, 0) + "%"
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PROCESSING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: ""
appendInfoLine: "Features applied:"
appendInfoLine: "  ✓ Q-based proportional bandwidth"
appendInfoLine: "  ✓ Frequency-dependent pan width"
appendInfoLine: "  ✓ S-curve spatial mapping"
appendInfoLine: "  ✓ Mono-safe bass protection"
appendInfoLine: "  ✓ Constant power panning"
appendInfoLine: "  ✓ Pan law compensation (-3.5dB)"

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result