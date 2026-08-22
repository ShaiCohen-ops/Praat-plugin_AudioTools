# ============================================================
# Praat AudioTools - Even-Odd_Harmonic_Binaural_Separation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2025)
# v0.5 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Separates even and odd harmonics into different stereo channels
#   for a binaural-style listening effect. Two separation methods:
#     - Cascading notches: applies Hann band-stop filters per
#       harmonic to remove. Gentler, slower roll-off, less audible
#       artifacts on moderate F0_factor settings.
#     - Spectral zeroing: goes to Spectrum domain and zeros bins
#       around rejected harmonics, then inverse-FFT. Sharper
#       notches, no per-iteration filter ringing, but can produce
#       pre-echo on transients (brick-wall character).
#
#   IMPORTANT — perceptual asymmetry:
#   In strict harmonic notation, the "odd" channel contains the
#   fundamental (h=1) plus harmonics 3, 5, 7... and the "even"
#   channel contains 2, 4, 6, 8... So the "even" channel has the
#   fundamental REMOVED. On voice/sustained sources this is
#   striking: the odd channel preserves the perceived pitch; the
#   even channel can sound like a different pitch (the missing
#   fundamental illusion may or may not restore it). This is
#   musically expected, not a bug.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5:
#   - HEADLINE NEW: LTAS panel in visualization shows the actual
#     long-term average spectrum of both output channels overlaid.
#     This is the only way to verify separation visually — a clean
#     comb of odd harmonics in one color, a clean comb of even
#     harmonics in the other, gaps where each was filtered.
#     Reveals filter bleed, F0 detection errors, and any
#     unexpected harmonic content (sub-harmonics, noise floor).
#   - NEW: Method form parameter chooses between "Cascading notches"
#     (v0.3 behavior, default) and "Spectral zeroing" (single-pass
#     Spectrum-domain zeroing). Surgical alternative for users who
#     want sharper separation, accepting the pre-echo tradeoff.
#   - NEW: Pitch_floor and Pitch_ceiling form parameters control
#     the auto-detect range. v0.3 hardcoded 75-600 Hz which failed
#     for low bass and high voices. Default kept at 75-600.
#   - Repurposed Preset 5 ("Custom F0"): now means user-supplied
#     F0 with explicit per-channel orientation. v0.3 made it
#     identical to preset 1, which was confusing. v0.5: when
#     preset 5 is selected, Auto_detect_F0 is forced OFF and
#     the script uses manual_F0_Hz with odd-L/even-R orientation.
#   - Visualization rewritten to suite 8x8 standard with title
#     bar + metadata subtitle, aligned panel titles, output
#     waveform panel with Ch1 blue / Ch2 orange, summary bar.
#   - Header documents the perceptual asymmetry (fundamental
#     belongs to odd channel) so users understand what to expect.
# Changelog v0.3:
#   - Added presets, visualization, play toggle. Removed gotos.
# ============================================================

form Even-Odd Harmonic Binaural Separation v0.5
    comment === PRESET ===
    optionmenu Preset: 1
        option: "1. Odd Left / Even Right"
        option: "2. Even Left / Odd Right"
        option: "3. Odd Only (mono->stereo)"
        option: "4. Even Only (mono->stereo)"
        option: "5. Custom (manual F0, Odd L / Even R)"
    
    comment === Separation Method ===
    optionmenu Method: 1
        option: "Cascading notches (gentler, v0.3)"
        option: "Spectral zeroing (sharper, NEW)"
    
    comment === F0 Detection ===
    boolean Auto_detect_F0 1
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Manual_F0_Hz 100
    
    comment === Filter Settings ===
    positive Maximum_frequency 5000
    positive Filter_width_factor 0.4
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# CHECK INPUT
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sr = Get sampling frequency
n_input_channels = Get number of channels

# ============================================================
# RESOLVE PRESET / METHOD NAMES
# ============================================================

if preset = 1
    presetName$ = "OddL_EvenR"
elsif preset = 2
    presetName$ = "EvenL_OddR"
elsif preset = 3
    presetName$ = "OddOnly"
elsif preset = 4
    presetName$ = "EvenOnly"
else
    presetName$ = "Custom"
    # Preset 5: force manual F0
    auto_detect_F0 = 0
endif

if method = 1
    methodName$ = "CascadeNotches"
else
    methodName$ = "SpectralZero"
endif

# ============================================================
# MAKE WORKING COPY (mono if input is multichannel)
# ============================================================

if n_input_channels > 1
    selectObject: sound
    monoCopy = Convert to mono
    workCopy = monoCopy
else
    selectObject: sound
    workCopy = Copy: "working"
endif

# ============================================================
# F0 DETECTION
# ============================================================

if auto_detect_F0
    selectObject: workCopy
    pitch = To Pitch: 0.01, pitch_floor, pitch_ceiling
    f0 = Get mean: 0, 0, "Hertz"
    if f0 = undefined
        f0 = manual_F0_Hz
        appendInfoLine: "Warning: Could not detect F0, using manual: ", f0, " Hz"
    endif
    removeObject: pitch
else
    f0 = manual_F0_Hz
endif

# ============================================================
# INFO HEADER
# ============================================================

writeInfoLine: "============================================"
appendInfoLine: "  EVEN-ODD HARMONIC BINAURAL SEPARATION v0.5"
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Method: ", methodName$
appendInfoLine: "F0: ", fixed$(f0, 2), " Hz"
if auto_detect_F0
    appendInfoLine: "  Detected (range: ", pitch_floor, "-", pitch_ceiling, " Hz)"
else
    appendInfoLine: "  Manual"
endif

# Rejection-band parameters
rejectWidth = f0 * filter_width_factor
maxHarmonic = floor(maximum_frequency / f0)
nyquist = sr / 2

appendInfoLine: "Notch ±", fixed$(rejectWidth, 1), " Hz  |  Up to harmonic ", maxHarmonic
appendInfoLine: ""

# ============================================================
# CREATE ODD-HARMONICS SOUND  (remove EVEN harmonics 2,4,6,...)
# Skip if preset 4 (Even-only output)
# ============================================================

if preset <> 4
    appendInfoLine: "Building ODD harmonics..."
    
    if method = 1
        # CASCADING NOTCHES — apply Hann stop-band filter per
        # even harmonic, removing previous after each pass.
        selectObject: workCopy
        oddSound = Copy: "odd_temp"
        
        h = 2
        keepGoing = 1
        while h <= maxHarmonic and keepGoing = 1
            freq = h * f0
            if freq > nyquist - 200
                keepGoing = 0
            else
                lowFreq = max(5, freq - rejectWidth)
                highFreq = freq + rejectWidth
                
                selectObject: oddSound
                filtered = Filter (stop Hann band): lowFreq, highFreq, 100
                removeObject: oddSound
                oddSound = filtered
                
                h = h + 2
            endif
        endwhile
        
        selectObject: oddSound
        Scale peak: 0.95
    else
        # SPECTRAL ZEROING — single-pass Spectrum manipulation.
        # Build a formula that zeros bins inside any even-harmonic
        # rejection band; everything else passes through.
        selectObject: workCopy
        oddSpec = To Spectrum: "yes"
        
        # Build the rejection condition. For each even harmonic h
        # in range, the band is [h*f0 - rejectWidth, h*f0 + rejectWidth].
        # We accumulate a single boolean expression.
        cond$ = "0"
        h = 2
        while h <= maxHarmonic
            freq = h * f0
            if freq <= nyquist - 200
                lowFreq = max(5, freq - rejectWidth)
                highFreq = freq + rejectWidth
                cond$ = cond$ + " or (x > " + fixed$(lowFreq, 4)
                    ... + " and x < " + fixed$(highFreq, 4) + ")"
            endif
            h = h + 2
        endwhile
        
        # If condition is true, zero the bin; else pass through
        selectObject: oddSpec
        Formula: "if (" + cond$ + ") then 0 else self fi"
        oddSound = To Sound
        # The To Sound output is the same length as the input here
        # (Spectrum was created with "yes" padding, so inverse returns
        # the original length). But to be safe:
        selectObject: oddSound
        oddDur = Get total duration
        if oddDur > duration + 0.001
            Extract part: 0, duration, "rectangular", 1, "no"
            trimmedOdd = selected("Sound")
            removeObject: oddSound
            oddSound = trimmedOdd
        endif
        Scale peak: 0.95
        removeObject: oddSpec
    endif
    
    selectObject: oddSound
    Rename: "odd_channel"
endif

# ============================================================
# CREATE EVEN-HARMONICS SOUND  (remove ODD harmonics 1,3,5,...)
# Skip if preset 3 (Odd-only output)
# ============================================================

if preset <> 3
    appendInfoLine: "Building EVEN harmonics..."
    
    if method = 1
        # CASCADING NOTCHES
        selectObject: workCopy
        evenSound = Copy: "even_temp"
        
        h = 1
        keepGoing = 1
        while h <= maxHarmonic and keepGoing = 1
            freq = h * f0
            if freq > nyquist - 200
                keepGoing = 0
            else
                lowFreq = max(5, freq - rejectWidth)
                highFreq = freq + rejectWidth
                
                selectObject: evenSound
                filtered = Filter (stop Hann band): lowFreq, highFreq, 100
                removeObject: evenSound
                evenSound = filtered
                
                h = h + 2
            endif
        endwhile
        
        selectObject: evenSound
        Scale peak: 0.95
    else
        # SPECTRAL ZEROING
        selectObject: workCopy
        evenSpec = To Spectrum: "yes"
        
        cond$ = "0"
        h = 1
        while h <= maxHarmonic
            freq = h * f0
            if freq <= nyquist - 200
                lowFreq = max(5, freq - rejectWidth)
                highFreq = freq + rejectWidth
                cond$ = cond$ + " or (x > " + fixed$(lowFreq, 4)
                    ... + " and x < " + fixed$(highFreq, 4) + ")"
            endif
            h = h + 2
        endwhile
        
        selectObject: evenSpec
        Formula: "if (" + cond$ + ") then 0 else self fi"
        evenSound = To Sound
        selectObject: evenSound
        evenDur = Get total duration
        if evenDur > duration + 0.001
            Extract part: 0, duration, "rectangular", 1, "no"
            trimmedEven = selected("Sound")
            removeObject: evenSound
            evenSound = trimmedEven
        endif
        Scale peak: 0.95
        removeObject: evenSpec
    endif
    
    selectObject: evenSound
    Rename: "even_channel"
endif

# ============================================================
# COMBINE TO STEREO BASED ON PRESET
# ============================================================

if preset = 1
    # Odd Left / Even Right
    selectObject: oddSound, evenSound
    result = Combine to stereo
    removeObject: oddSound, evenSound
    leftLabel$ = "Odd (1,3,5...)"
    rightLabel$ = "Even (2,4,6...)"
elsif preset = 2
    # Even Left / Odd Right
    selectObject: evenSound, oddSound
    result = Combine to stereo
    removeObject: oddSound, evenSound
    leftLabel$ = "Even (2,4,6...)"
    rightLabel$ = "Odd (1,3,5...)"
elsif preset = 3
    # Odd Only (mono -> stereo)
    selectObject: oddSound
    result = Convert to stereo
    removeObject: oddSound
    leftLabel$ = "Odd"
    rightLabel$ = "Odd"
elsif preset = 4
    # Even Only (mono -> stereo)
    selectObject: evenSound
    result = Convert to stereo
    removeObject: evenSound
    leftLabel$ = "Even"
    rightLabel$ = "Even"
else
    # Preset 5 — Custom = same as Preset 1 with manual F0
    selectObject: oddSound, evenSound
    result = Combine to stereo
    removeObject: oddSound, evenSound
    leftLabel$ = "Odd (manual F0)"
    rightLabel$ = "Even (manual F0)"
endif

selectObject: result
Rename: soundName$ + "_binaural_" + presetName$ + "_" + methodName$

# ============================================================
# CLEANUP working copies
# ============================================================

removeObject: workCopy

# ============================================================
# COMPUTE LTAS FOR OUTPUT  (for visualization Panel B)
# ============================================================

if draw_visualization
    appendInfoLine: "Computing LTAS for visualization..."
    
    selectObject: result
    Extract one channel: 1
    leftViz = selected("Sound")
    leftSpec = To Spectrum: "yes"
    leftLtas = To Ltas (1-to-1)
    Rename: "ltas_left"
    leftLtasID = selected("Ltas")
    removeObject: leftViz, leftSpec
    
    selectObject: result
    Extract one channel: 2
    rightViz = selected("Sound")
    rightSpec = To Spectrum: "yes"
    rightLtas = To Ltas (1-to-1)
    Rename: "ltas_right"
    rightLtasID = selected("Ltas")
    removeObject: rightViz, rightSpec
endif

# ============================================================
# FINAL STATS
# ============================================================

selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##EVEN-ODD HARMONIC BINAURAL SEPARATION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Method: " + methodName$
        ... + "  |  F0: " + fixed$(f0, 1) + " Hz"
        ... + "  |  Up to h" + string$(maxHarmonic)
        ... + "  |  Notch ±" + fixed$(rejectWidth, 1) + " Hz"
    
    # ----------------------------------------------------------
    # PANEL A: HARMONIC LAYOUT DIAGRAM  (left, headline)
    # Where each harmonic ends up: left vs right.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    maxFreqDisplay = min(maximum_frequency, 2500)
    Axes: 0, maxFreqDisplay, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxFreqDisplay, -1.5, 1.5
    
    # Centerline (separates L and R visual zones)
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: 0, 0, maxFreqDisplay, 0
    Solid line
    
    # Per-harmonic bars
    for h from 1 to maxHarmonic
        freq = h * f0
        if freq <= maxFreqDisplay
            isOdd = (h mod 2) = 1
            barW = max(5, f0 * 0.10)
            
            if isOdd
                # Odd harmonic — blue (channel depends on preset)
                if preset = 1 or preset = 5
                    # Odd goes to LEFT (top half)
                    Paint rectangle: "{0.25, 0.50, 0.82}", freq - barW, freq + barW, 0.05, 1.20
                elsif preset = 2
                    # Odd goes to RIGHT (bottom half)
                    Paint rectangle: "{0.25, 0.50, 0.82}", freq - barW, freq + barW, -1.20, -0.05
                elsif preset = 3
                    # Odd only — both halves
                    Paint rectangle: "{0.25, 0.50, 0.82}", freq - barW, freq + barW, 0.05, 1.20
                    Paint rectangle: "{0.25, 0.50, 0.82}", freq - barW, freq + barW, -1.20, -0.05
                endif
            else
                # Even harmonic — orange
                if preset = 1 or preset = 5
                    # Even goes to RIGHT (bottom half)
                    Paint rectangle: "{0.82, 0.45, 0.25}", freq - barW, freq + barW, -1.20, -0.05
                elsif preset = 2
                    # Even goes to LEFT (top half)
                    Paint rectangle: "{0.82, 0.45, 0.25}", freq - barW, freq + barW, 0.05, 1.20
                elsif preset = 4
                    # Even only — both halves
                    Paint rectangle: "{0.82, 0.45, 0.25}", freq - barW, freq + barW, 0.05, 1.20
                    Paint rectangle: "{0.82, 0.45, 0.25}", freq - barW, freq + barW, -1.20, -0.05
                endif
            endif
            
            # Harmonic number label
            if h <= 12 or h mod 2 = 0
                Font size: 6
                Colour: "{0.30, 0.30, 0.30}"
                Text: freq, "centre", 1.35, "half", string$(h)
            endif
        endif
    endfor
    
    # Channel labels
    Font size: 7
    Colour: "{0.25, 0.50, 0.82}"
    Text: maxFreqDisplay * 0.02, "left", 0.65, "half", "L: " + leftLabel$
    Colour: "{0.82, 0.45, 0.25}"
    Text: maxFreqDisplay * 0.02, "left", -0.65, "half", "R: " + rightLabel$
    
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 500, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Frequency (Hz)"
    
    # ----------------------------------------------------------
    # PANEL B: ACTUAL OUTPUT LTAS (L vs R)
    # The honest test of whether separation worked.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    selectObject: leftLtasID
    leftLtasMax = Get maximum: 0, 0, "None"
    selectObject: rightLtasID
    rightLtasMax = Get maximum: 0, 0, "None"
    
    ltasMax = leftLtasMax
    if rightLtasMax > ltasMax
        ltasMax = rightLtasMax
    endif
    
    # Show 0 to maxFreqDisplay on linear x; dB scale on y
    yLo = ltasMax - 60
    yHi = ltasMax + 5
    
    Axes: 0, maxFreqDisplay, yLo, yHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxFreqDisplay, yLo, yHi
    
    # Light vertical guides at every 5th harmonic
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    for h from 1 to maxHarmonic
        if h mod 5 = 0
            freq = h * f0
            if freq <= maxFreqDisplay
                Draw line: freq, yLo, freq, yHi
            endif
        endif
    endfor
    
    # 0 dB reference line (i.e. peak)
    Colour: "{0.65, 0.65, 0.65}"
    Dotted line
    Draw line: 0, ltasMax, maxFreqDisplay, ltasMax
    Solid line
    
    # Plot LEFT LTAS (blue)
    selectObject: leftLtasID
    leftBins = Get number of bins
    leftBinW = Get bin width
    
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1.3
    prevF = 0
    prevDb = yLo
    bin = 1
    while bin <= leftBins
        f = (bin - 0.5) * leftBinW
        if f > maxFreqDisplay
            bin = leftBins + 1
        else
            v = Get value in bin: bin
            if v = undefined
                v = yLo
            endif
            if v < yLo
                v = yLo
            endif
            if bin > 1
                Draw line: prevF, prevDb, f, v
            endif
            prevF = f
            prevDb = v
            bin = bin + 1
        endif
    endwhile
    
    # Plot RIGHT LTAS (orange)
    selectObject: rightLtasID
    rightBins = Get number of bins
    rightBinW = Get bin width
    
    Colour: "{0.82, 0.45, 0.25}"
    Line width: 1.3
    prevF = 0
    prevDb = yLo
    bin = 1
    while bin <= rightBins
        f = (bin - 0.5) * rightBinW
        if f > maxFreqDisplay
            bin = rightBins + 1
        else
            v = Get value in bin: bin
            if v = undefined
                v = yLo
            endif
            if v < yLo
                v = yLo
            endif
            if bin > 1
                Draw line: prevF, prevDb, f, v
            endif
            prevF = f
            prevDb = v
            bin = bin + 1
        endif
    endwhile
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.75, 2.70
    Select inner viewport: 4.02, 4.4, 0.77, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Mag (dB)"
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    Axes: 0, maxFreqDisplay, yLo, yHi
    Text bottom: "yes", "Freq (Hz)"
    
    # ----------------------------------------------------------
    # PANEL C: NOTCH PATTERN VISUALIZATION
    # Shows where the rejection bands are — useful to see the
    # filter_width_factor's effect at the chosen F0.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    Axes: 0, maxFreqDisplay, 0, 1.2
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, maxFreqDisplay, 0, 1.2
    
    # Draw notch gates (one per harmonic that gets removed)
    # For preset 1, 5: notches around even harmonics in left output;
    # For preset 2, 3: notches around odd harmonics; etc.
    # Show notches for both channels overlaid (light fill, transparent)
    
    # Notch pattern for ODD output (i.e. removes EVEN)
    if preset <> 4
        # Show even-harmonic notches
        Colour: "{0.78, 0.45, 0.25}"
        for h from 1 to maxHarmonic
            if h mod 2 = 0
                freq = h * f0
                if freq <= maxFreqDisplay
                    lowFreq = max(5, freq - rejectWidth)
                    highFreq = min(maxFreqDisplay, freq + rejectWidth)
                    Paint rectangle: "{0.93, 0.78, 0.65}", lowFreq, highFreq, 0.55, 1.05
                endif
            endif
        endfor
    endif
    
    # Notch pattern for EVEN output (removes ODD)
    if preset <> 3
        Colour: "{0.45, 0.55, 0.78}"
        for h from 1 to maxHarmonic
            if h mod 2 = 1
                freq = h * f0
                if freq <= maxFreqDisplay
                    lowFreq = max(5, freq - rejectWidth)
                    highFreq = min(maxFreqDisplay, freq + rejectWidth)
                    Paint rectangle: "{0.65, 0.78, 0.93}", lowFreq, highFreq, 0.05, 0.55
                endif
            endif
        endfor
    endif
    
    # Channel labels
    Font size: 6
    Colour: "{0.45, 0.30, 0.20}"
    Text: maxFreqDisplay * 0.02, "left", 0.80, "half", "Notches in ODD ch"
    Colour: "{0.20, 0.30, 0.45}"
    Text: maxFreqDisplay * 0.02, "left", 0.30, "half", "Notches in EVEN ch"
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Freq (Hz)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.20, "centre", 7.30, "half", "Harmonic layout (target distribution)"
    Text: 6.10, "centre", 7.30, "half", "Output LTAS L vs R (upper) & notch pattern (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    Extract one channel: 1
    vCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh1
    
    selectObject: result
    Extract one channel: 2
    vCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh2
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output  (blue=L  orange=R)"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, finalDur, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 6.98
    Select inner viewport: 0.55, 7.72, 6.26, 6.92
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.64, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + soundName$
        ... + "  |  Method: " + methodName$
        ... + "  |  F0: " + fixed$(f0, 2) + " Hz"
        ... + "  |  Notch width factor: " + fixed$(filter_width_factor, 2)
        ... + "  |  Up to h" + string$(maxHarmonic)
    
    Text: 0.02, "left", 0.28, "half",
        ... "L: " + leftLabel$
        ... + "  |  R: " + rightLabel$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Note: fundamental belongs to ODD channel"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Select outer viewport: 0, 8, 0, 7.08
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: leftLtasID, rightLtasID
endif

# ============================================================
# DONE
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "  COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "  Left:  ", leftLabel$
appendInfoLine: "  Right: ", rightLabel$
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)
appendInfoLine: ""
appendInfoLine: "Listen with headphones for binaural effect."
appendInfoLine: "Note: the fundamental belongs to the ODD channel —"
appendInfoLine: "the EVEN channel is missing-fundamental and may"
appendInfoLine: "perceive a different pitch."

if play_result
    selectObject: result
    Play
endif

selectObject: result
